# frozen_string_literal: true

require 'ast/crispr'
require 'prism'
require 'tree_haver'
require 'version_gem'
require_relative 'prism/version'

module Ast
  module Crispr
    module Ruby
      module Prism
        class Error < StandardError; end
        BACKEND_REFERENCE = ::TreeHaver::BackendReference.new(id: 'prism', family: 'native').freeze
        BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

        class << self
          def register_backend!
            BACKEND_REGISTRY.mutex.synchronize do
              return if BACKEND_REGISTRY.registered

              ::TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)
              ::TreeHaver.register_language(
                :ruby,
                backend_module: ::TreeHaver::Backends::Prism,
                backend_type: :prism,
                gem_name: 'prism'
              )

              BACKEND_REGISTRY.registered = true
            end
          end
        end

        module Utils
          module_function

          def parse_with_comments(source)
            Ast::Crispr::Ruby::Prism.register_backend!
            ::TreeHaver.with_backend(Ast::Crispr::Ruby::Prism::BACKEND_REFERENCE.id) do
              ::TreeHaver.parser_for(:ruby).parse(source).parse_result
            end
          end

          def extract_statements(body_node)
            return [] unless body_node

            if body_node.is_a?(::Prism::StatementsNode)
              body_node.body.compact
            else
              [body_node].compact
            end
          end

          def find_leading_comments(parse_result, current_stmt, prev_stmt, body_node)
            start_line = prev_stmt ? prev_stmt.location.end_line : body_node.location.start_line
            end_line = current_stmt.location.start_line

            parse_result.comments.select do |comment|
              comment.location.start_line > start_line &&
                comment.location.start_line < end_line
            end
          end
        end

        class Adapter
          def read_ast(document)
            result = Utils.parse_with_comments(document.content)
            return result if result.success?

            raise Ast::Crispr::Error.new("Unable to read structural owners from #{document.source_label}",
                                         details: { source_label: document.source_label })
          end

          def structural_owners(document, owner_scope: :shared_default)
            parse_result = document.ast
            case owner_scope
            when :shared_default, :line_bound_statements, :top_level_statements
              Utils.extract_statements(parse_result.value.statements)
            when :ruby_comments
              parse_result.comments
            else
              raise Ast::Crispr::Error.new('Unsupported CRISPR owner scope', details: { owner_scope: owner_scope })
            end
          end

          def comment_regions_for(document, owner, region: :leading, owner_scope: :shared_default)
            parse_result = document.ast
            owners = structural_owners(document, owner_scope: owner_scope)
            index = owners.index(owner)
            return [] unless index

            case region
            when :leading
              previous_owner = index.positive? ? owners[index - 1] : nil
              if previous_owner
                Utils.find_leading_comments(parse_result, owner, previous_owner, parse_result.value.statements)
              else
                parse_result.comments.select { |comment| comment.location.start_line < owner.location.start_line }
              end
            else
              raise Ast::Crispr::Error.new('Unsupported CRISPR comment region', details: { region: region })
            end
          end

          def comment_region_text(document, comment_region)
            document.location_slice(comment_region.location).rstrip
          end

          def structure_profile(owner_scope: :shared_default)
            case owner_scope
            when :shared_default, :line_bound_statements, :top_level_statements
              Ast::Crispr::StructureProfile.new(
                owner_scope: owner_scope,
                owner_selector: :line_bound_statements,
                supported_comment_regions: [:leading],
                metadata: { adapter: :prism }
              )
            when :ruby_comments
              Ast::Crispr::StructureProfile.new(
                owner_scope: owner_scope,
                owner_selector: :line_bound_statements,
                supported_comment_regions: [],
                metadata: { adapter: :prism, selector: :ruby_comments }
              )
            else
              raise Ast::Crispr::Error.new('Unsupported CRISPR owner scope', details: { owner_scope: owner_scope })
            end
          end
        end

        module Selectors
          module_function

          def owner_filter(id:, limit: nil, owner_scope: :shared_default, include_trailing_gap: false, metadata: {},
                           &block)
            Ast::Crispr::Selectors.owner_filter(
              id: id,
              limit: limit,
              owner_scope: owner_scope,
              include_trailing_gap: include_trailing_gap,
              adapter: Ast::Crispr::Ruby::Prism.adapter,
              metadata: metadata,
              &block
            )
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
              adapter: Ast::Crispr::Ruby::Prism.adapter,
              metadata: metadata,
              **options
            )
          end

          def comment_line_block(start_text:, end_text:, id: nil, limit: nil, span: :nearest,
                                 include_trailing_gap: false, metadata: {}, **options)
            Ast::Crispr::OwnerSelector.new(
              id: id || "ruby_comment_line_block_#{start_text}",
              limit: limit,
              metadata: metadata.merge(
                adapter: Ast::Crispr::Ruby::Prism.adapter,
                owner_scope: :ruby_comments,
                selector_kind: :ruby_comment_line_block,
                selection_intent: :line_marker_block,
                include_trailing_gap: include_trailing_gap
              ).merge(options),
              locate: lambda do |context|
                comments = context.structural_owners(owner_scope: :ruby_comments)
                if span.to_sym == :outermost
                  opening = comments.find do |comment|
                    context.location_slice(comment.location).rstrip == start_text.to_s
                  end
                  closing = comments.reverse.find do |comment|
                    opening &&
                      context.location_slice(comment.location).rstrip == end_text.to_s &&
                      comment.location.end_line >= opening.location.start_line
                  end
                  next [] unless opening && closing

                  end_line = closing.location.end_line
                  end_line = context.expand_following_gap(end_line) if include_trailing_gap
                  next [
                    Ast::Crispr::Match.new(
                      node: opening,
                      start_line: opening.location.start_line,
                      end_line: end_line,
                      metadata: {
                        start_boundary: :comment_region_start,
                        end_boundary: (include_trailing_gap ? :owner_end_plus_trailing_gap : :owner_end),
                        payload_kind: :comment_owned_body,
                        start_text: start_text,
                        end_text: end_text
                      }
                    )
                  ]
                end

                comments.each_with_index.filter_map do |comment, index|
                  next unless context.location_slice(comment.location).rstrip == start_text.to_s

                  closing = comments[index + 1..]&.find do |candidate|
                    context.location_slice(candidate.location).rstrip == end_text.to_s
                  end
                  next unless closing

                  end_line = closing.location.end_line
                  end_line = context.expand_following_gap(end_line) if include_trailing_gap
                  Ast::Crispr::Match.new(
                    node: comment,
                    start_line: comment.location.start_line,
                    end_line: end_line,
                    metadata: {
                      start_boundary: :comment_region_start,
                      end_boundary: (include_trailing_gap ? :owner_end_plus_trailing_gap : :owner_end),
                      payload_kind: :comment_owned_body,
                      start_text: start_text,
                      end_text: end_text
                    }
                  )
                end
              end
            )
          end
        end

        Targets = Selectors

        class << self
          def adapter
            @adapter ||= Adapter.new
          end

          def document_context(content:, source_label: 'source', metadata: {}, **options)
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

Ast::Crispr::Ruby::Prism::Version.class_eval do
  extend VersionGem::Basic
end
