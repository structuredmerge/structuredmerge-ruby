# frozen_string_literal: true

require 'ast/crispr'
require 'markly/merge'
require 'version_gem'
require_relative 'markly/version'

module Ast
  module Crispr
    module Markdown
      module Markly
        class Error < StandardError; end

        class Adapter
          def read_ast(document)
            analysis = ::Markly::Merge::FileAnalysis.new(document.content)
            return analysis if analysis.valid?

            raise Ast::Crispr::Error.new("Unable to read structural owners from #{document.source_label}",
                                         details: { source_label: document.source_label })
          end

          def structural_owners(document, owner_scope: :shared_default)
            analysis = document.ast
            case owner_scope
            when :shared_default, :heading_sections
              analysis.heading_section_owners
            when :link_definitions
              analysis.link_definition_owners
            when :html_comments
              analysis.html_comment_owners
            when :inline_references
              analysis.inline_reference_owners
            when :table_rows
              analysis.table_row_owners
            else
              raise Ast::Crispr::Error.new('Unsupported CRISPR owner scope', details: { owner_scope: owner_scope })
            end
          end

          def comment_regions_for(_document, _owner, region: :leading, owner_scope: :shared_default)
            raise Ast::Crispr::Error.new(
              'Unsupported CRISPR comment region',
              details: { region: region, owner_scope: owner_scope }
            )
          end

          def comment_region_text(_document, _comment_region)
            raise Ast::Crispr::Error.new('Markdown CRISPR adapter does not expose comment regions')
          end

          def structure_profile(owner_scope: :shared_default)
            case owner_scope
            when :shared_default, :heading_sections
              Ast::Crispr::StructureProfile.new(
                owner_scope: owner_scope,
                owner_selector: :heading_sections,
                supported_comment_regions: [],
                metadata: { adapter: :markly }
              )
            when :link_definitions
              Ast::Crispr::StructureProfile.new(
                owner_scope: owner_scope,
                owner_selector: :link_definitions,
                supported_comment_regions: [],
                metadata: { adapter: :markly }
              )
            when :html_comments
              Ast::Crispr::StructureProfile.new(
                owner_scope: owner_scope,
                owner_selector: :line_bound_statements,
                supported_comment_regions: [],
                metadata: { adapter: :markly, markdown_owner: :html_comment }
              )
            when :inline_references
              Ast::Crispr::StructureProfile.new(
                owner_scope: owner_scope,
                owner_selector: :inline_references,
                supported_comment_regions: [],
                metadata: { adapter: :markly, markdown_owner: :inline_reference }
              )
            when :table_rows
              Ast::Crispr::StructureProfile.new(
                owner_scope: owner_scope,
                owner_selector: :table_rows,
                supported_comment_regions: [],
                metadata: { adapter: :markly, markdown_owner: :table_row }
              )
            else
              raise Ast::Crispr::Error.new('Unsupported CRISPR owner scope', details: { owner_scope: owner_scope })
            end
          end

          private

        end

        module Selectors
          module_function

          def heading_section(heading_text:, level: nil, id: nil, limit: nil, metadata: {}, **options)
            Ast::Crispr::OwnerSelector.new(
              id: id || "heading_section_#{heading_text}",
              limit: limit,
              metadata: metadata.merge(
                adapter: Ast::Crispr::Markdown::Markly.adapter,
                owner_scope: :heading_sections,
                selector_kind: :heading_section,
                selection_intent: :section_branch,
                include_trailing_gap: false
              ).merge(options),
              locate: lambda do |context|
                context.structural_owners(owner_scope: :heading_sections).filter_map do |owner|
                  next unless owner.heading_text.to_s.strip == heading_text.to_s.strip
                  next if level && owner.level != level

                  Ast::Crispr::Match.new(
                    node: owner,
                    start_line: owner.location.start_line,
                    end_line: owner.location.end_line,
                    metadata: {
                      start_boundary: :owner_start,
                      end_boundary: :owner_end,
                      payload_kind: :section_branch,
                      heading_text: owner.heading_text,
                      level: owner.level,
                      base: owner.base
                    }
                  )
                end
              end
            )
          end

          def link_definition(label: nil, url: nil, id: nil, limit: nil, metadata: {}, **options)
            Ast::Crispr::OwnerSelector.new(
              id: id || ['link_definition', label, url].compact.join(':'),
              limit: limit,
              metadata: metadata.merge(
                adapter: Ast::Crispr::Markdown::Markly.adapter,
                owner_scope: :link_definitions,
                selector_kind: :link_definition,
                selection_intent: :predicate_filter,
                include_trailing_gap: false
              ).merge(options),
              locate: lambda do |context|
                context.structural_owners(owner_scope: :link_definitions).filter_map do |owner|
                  next if label && owner.label.to_s != label.to_s
                  next if url && owner.url.to_s != url.to_s

                  Ast::Crispr::Match.new(
                    node: owner,
                    start_line: owner.location.start_line,
                    end_line: owner.location.end_line,
                    metadata: {
                      start_boundary: :owner_start,
                      end_boundary: :owner_end,
                      payload_kind: :structural_owner_body,
                      label: owner.label,
                      url: owner.url
                    }
                  )
                end
              end
            )
          end

          def html_comment(text:, id: nil, limit: nil, metadata: {}, **options)
            Ast::Crispr::OwnerSelector.new(
              id: id || "html_comment_#{text}",
              limit: limit,
              metadata: metadata.merge(
                adapter: Ast::Crispr::Markdown::Markly.adapter,
                owner_scope: :html_comments,
                selector_kind: :html_comment,
                selection_intent: :predicate_filter,
                include_trailing_gap: false
              ).merge(options),
              locate: lambda do |context|
                context.structural_owners(owner_scope: :html_comments).filter_map do |owner|
                  next unless owner.text.to_s == text.to_s

                  Ast::Crispr::Match.new(
                    node: owner,
                    start_line: owner.location.start_line,
                    end_line: owner.location.end_line,
                    metadata: {
                      start_boundary: :owner_start,
                      end_boundary: :owner_end,
                      payload_kind: :structural_owner_body,
                      text: owner.text
                    }
                  )
                end
              end
            )
          end

          def inline_reference(label: nil, reference_kind: nil, id: nil, limit: nil, metadata: {}, **options)
            Ast::Crispr::OwnerSelector.new(
              id: id || ['inline_reference', label, reference_kind].compact.join(':'),
              limit: limit,
              metadata: metadata.merge(
                adapter: Ast::Crispr::Markdown::Markly.adapter,
                owner_scope: :inline_references,
                selector_kind: :inline_reference,
                selection_intent: :predicate_filter,
                include_trailing_gap: false
              ).merge(options),
              locate: lambda do |context|
                context.structural_owners(owner_scope: :inline_references).filter_map do |owner|
                  next if label && !owner.labels.include?(label.to_s)
                  next if reference_kind && owner.reference_kind != reference_kind.to_sym

                  Ast::Crispr::Match.new(
                    node: owner,
                    start_line: owner.location.start_line,
                    end_line: owner.location.end_line,
                    metadata: {
                      start_boundary: :owner_start,
                      end_boundary: :owner_end,
                      payload_kind: :structural_owner_body,
                      label: owner.label,
                      labels: owner.labels,
                      reference_kind: owner.reference_kind,
                      start_column: owner.start_column,
                      end_column: owner.end_column
                    }
                  )
                end
              end
            )
          end

          def html_comment_block(start_text:, end_text:, id: nil, limit: nil, span: :nearest,
                                 include_trailing_gap: false, metadata: {}, **options)
            Ast::Crispr::OwnerSelector.new(
              id: id || "html_comment_block_#{start_text}",
              limit: limit,
              metadata: metadata.merge(
                adapter: Ast::Crispr::Markdown::Markly.adapter,
                owner_scope: :html_comments,
                selector_kind: :html_comment_block,
                selection_intent: :predicate_filter,
                include_trailing_gap: include_trailing_gap
              ).merge(options),
              locate: lambda do |context|
                comments = context.structural_owners(owner_scope: :html_comments)
                if span.to_sym == :outermost
                  opening = comments.find { |comment| comment.text.to_s == start_text.to_s }
                  closing = comments.reverse.find do |comment|
                    opening && comment.text.to_s == end_text.to_s && comment.location.end_line >= opening.location.start_line
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
                        start_boundary: :owner_start,
                        end_boundary: (include_trailing_gap ? :owner_end_plus_trailing_gap : :owner_end),
                        payload_kind: :structural_owner_body,
                        start_text: start_text,
                        end_text: end_text
                      }
                    )
                  ]
                end

                comments.each_with_index.filter_map do |owner, index|
                  next unless owner.text.to_s == start_text.to_s

                  closing = comments[index + 1..]&.find { |comment| comment.text.to_s == end_text.to_s }
                  next unless closing

                  end_line = closing.location.end_line
                  end_line = context.expand_following_gap(end_line) if include_trailing_gap
                  Ast::Crispr::Match.new(
                    node: owner,
                    start_line: owner.location.start_line,
                    end_line: end_line,
                    metadata: {
                      start_boundary: :owner_start,
                      end_boundary: (include_trailing_gap ? :owner_end_plus_trailing_gap : :owner_end),
                      payload_kind: :structural_owner_body,
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

Ast::Crispr::Markdown::Markly::Version.class_eval do
  extend VersionGem::Basic
end
