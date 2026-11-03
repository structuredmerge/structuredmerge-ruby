# frozen_string_literal: true

require "ast/crispr"
require "psych/merge"
require_relative "psych/version"

module Ast
  module Crispr
    module Yaml
      module Psych
        # A YAML structural owner backed by a Psych Merge node wrapper.
        Owner = Struct.new(:location, :key, :path, :kind, :index, :wrapper, keyword_init: true) do
          def node
            wrapper.node
          end

          def start_line
            location.start_line
          end

          def end_line
            location.end_line
          end
        end

        class Adapter
          def read_ast(document)
            analysis = ::Psych::Merge::FileAnalysis.new(document.content, source_label: document.source_label)
            return analysis if analysis.valid?

            raise Ast::Crispr::Error.new(
              "Unable to read structural owners from #{document.source_label}",
              details: { source_label: document.source_label, errors: analysis.errors }
            )
          end

          def structural_owners(document, owner_scope: :shared_default)
            groups = statement_groups(document)
            case owner_scope
            when :shared_default, :top_level_statements
              groups.first || []
            when :mapping_entries
              groups.flatten.select { |owner| owner.kind == :mapping_entry }
            when :nested_mapping_entries
              groups.flatten.select { |owner| owner.kind == :mapping_entry && owner.path.length > 1 }
            when :sequence_items
              groups.flatten.select { |owner| owner.kind == :sequence_item }
            when :all_statements
              groups.flatten
            else
              raise Ast::Crispr::Error.new("Unsupported CRISPR owner scope", details: { owner_scope: owner_scope })
            end
          end

          def comment_regions_for(document, owner, region: :leading, owner_scope: :shared_default)
            unless %i[leading trailing].include?(region.to_sym)
              raise Ast::Crispr::Error.new(
                "Unsupported CRISPR comment region",
                details: { region: region, owner_scope: owner_scope }
              )
            end

            attachment = document.ast.comment_attachment_for(owner.wrapper)
            [attachment.public_send("#{region}_region")].compact
          end

          def comment_region_text(_document, comment_region)
            comment_region.text
          end

          def structure_profile(owner_scope: :shared_default)
            supported_scopes = %i[
              shared_default top_level_statements mapping_entries nested_mapping_entries sequence_items all_statements
            ]
            unless supported_scopes.include?(owner_scope.to_sym)
              raise Ast::Crispr::Error.new("Unsupported CRISPR owner scope", details: { owner_scope: owner_scope })
            end

            Ast::Crispr::StructureProfile.new(
              owner_scope: owner_scope,
              owner_selector: :line_bound_statements,
              supported_comment_regions: %i[leading trailing],
              metadata: { adapter: :yaml_psych, selector: owner_scope }
            )
          end

          # Sibling groups preserve YAML's nested ownership boundaries for
          # comment selection and structural layout calculations.
          def statement_groups(document)
            analysis = document.ast
            analysis.structural_owner_groups.map do |group|
              group.map do |wrapper|
                metadata = analysis.structural_owner_metadata_for(wrapper)
                # A mapping entry owns its key line, even when the value starts on a later line.
                start_line = [wrapper.start_line, metadata[:key_start_line]].compact.min || 1
                end_line = wrapper.end_line || start_line
                Owner.new(
                  location: ::Ast::Merge::AstNode::Location.new(start_line: start_line, end_line: end_line),
                  key: wrapper.key,
                  path: metadata.fetch(:path),
                  kind: metadata.fetch(:kind),
                  index: metadata[:index],
                  wrapper: wrapper
                )
              end
            end
          end

          def layout_attachment_for(document, owner, **options)
            document.ast.layout_attachment_for(owner.wrapper, **options)
          end
        end

        # Anchor adapter so selector matches can be used as Insert destinations.
        AnchorPoint = Struct.new(:anchor)

        module Selectors
          module_function

          # Insert resolves destinations through an anchor; insert after the matched owner.
          def anchored(selector)
            Ast::Crispr::OwnerSelector.new(
              id: selector.id, locate: selector.locate, owned_span: selector.owned_span,
              anchor: ->(_context, match) { AnchorPoint.new(match) },
              limit: selector.limit, metadata: selector.metadata
            )
          end

          def owner_filter(id:, limit: nil, owner_scope: :shared_default, include_trailing_gap: false, metadata: {},
                           &block)
            Ast::Crispr::Selectors.owner_filter(
              id: id,
              limit: limit,
              owner_scope: owner_scope,
              include_trailing_gap: include_trailing_gap,
              adapter: Ast::Crispr::Yaml::Psych.adapter,
              metadata: metadata,
              &block
            )
          end

          def mapping_entry(path:, id: nil, limit: nil, metadata: {}, **options)
            expected_path = normalize_path(path)
            anchored(owner_filter(
              id: id || "yaml_mapping_entry_#{expected_path.join(".")}",
              limit: limit,
              owner_scope: :mapping_entries,
              metadata: metadata.merge(options)
            ) { |_context, owner| owner.path == expected_path })
          end

          def sequence_item(path:, index:, id: nil, limit: nil, metadata: {}, **options)
            expected_path = normalize_path(path) + [Integer(index)]
            anchored(owner_filter(
              id: id || "yaml_sequence_item_#{expected_path.join(".")}",
              limit: limit,
              owner_scope: :sequence_items,
              metadata: metadata.merge(options)
            ) { |_context, owner| owner.path == expected_path })
          end

          def comment_region_owned_owner(marker:, id: nil, limit: nil, owner_scope: :shared_default,
                                         comment_region: :leading, include_trailing_gap: true, metadata: {}, **options)
            Ast::Crispr::Selectors.comment_region_owned_owner(
              marker: marker,
              id: id,
              limit: limit,
              owner_scope: owner_scope,
              comment_region: comment_region,
              include_trailing_gap: include_trailing_gap,
              adapter: Ast::Crispr::Yaml::Psych.adapter,
              metadata: metadata,
              **options
            )
          end

          def normalize_path(path)
            path.is_a?(Array) ? path : path.to_s.split(".").reject(&:empty?)
          end
          private_class_method :normalize_path
        end

        Targets = Selectors

        class << self
          def adapter
            @adapter ||= Adapter.new
          end

          def document_context(content:, source_label: "source", metadata: {}, **options)
            Ast::Crispr::DocumentContext.new(
              content: content,
              source_label: source_label,
              adapter: adapter,
              metadata: metadata,
              **options
            )
          end
        end
      end
    end
  end
end
