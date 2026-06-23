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
          Location = Struct.new(:start_line, :end_line, keyword_init: true)
          HeadingSectionOwner = Struct.new(
            :location,
            :heading_text,
            :heading_source,
            :level,
            :base,
            keyword_init: true
          )
          LinkDefinitionOwner = Struct.new(
            :location,
            :label,
            :url,
            :title,
            :source,
            keyword_init: true
          )
          HtmlCommentOwner = Struct.new(
            :location,
            :text,
            :source,
            keyword_init: true
          )
          InlineReferenceOwner = Struct.new(
            :location,
            :line,
            :start_column,
            :end_column,
            :source,
            :reference_kind,
            :label,
            :labels,
            keyword_init: true
          )
          TableRowOwner = Struct.new(
            :location,
            :source,
            :text,
            keyword_init: true
          )

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
              build_heading_sections(analysis)
            when :link_definitions
              build_link_definitions(analysis)
            when :html_comments
              build_html_comments(analysis)
            when :inline_references
              build_inline_references(analysis)
            when :table_rows
              build_table_rows(analysis)
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

          def build_heading_sections(analysis)
            headings = Array(analysis.statements).filter_map do |statement|
              next unless heading_statement?(statement)

              build_heading_owner(statement, analysis)
            end

            headings.each_with_index.map do |owner, index|
              branch_end_line = branch_end_line(headings, index, analysis)
              HeadingSectionOwner.new(
                location: Location.new(start_line: owner.location.start_line, end_line: branch_end_line),
                heading_text: owner.heading_text,
                heading_source: owner.heading_source,
                level: owner.level,
                base: owner.base
              )
            end
          end

          def build_link_definitions(analysis)
            Array(analysis.statements).filter_map do |statement|
              next unless statement.respond_to?(:merge_type) && statement.merge_type == :link_definition

              position = statement.source_position
              next unless position

              LinkDefinitionOwner.new(
                location: Location.new(start_line: position[:start_line], end_line: position[:end_line]),
                label: statement.label,
                url: statement.url,
                title: statement.title,
                source: if statement.respond_to?(:content)
                          statement.content
                        else
                          analysis.source_range(
                            position[:start_line], position[:end_line]
                          ).chomp
                        end
              )
            end
          end

          def build_html_comments(analysis)
            analysis.comment_tracker.comment_nodes.map do |comment|
              HtmlCommentOwner.new(
                location: Location.new(start_line: comment.location.start_line, end_line: comment.location.end_line),
                text: comment.content,
                source: comment.text
              )
            end
          end

          def build_inline_references(analysis)
            analysis.source.to_s.lines.each_with_index.flat_map do |line, index|
              inline_references_for_line(line.chomp, index + 1)
            end
          end

          def build_table_rows(analysis)
            ast_table_lines = {}
            ast_rows = Array(analysis.statements).flat_map do |statement|
              node = unwrap_markdown_statement(statement)
              next [] unless node.respond_to?(:type) && node.type.to_s == 'table'

              table_position = node.source_position
              if table_position
                (table_position[:start_line]..table_position[:end_line]).each do |line|
                  ast_table_lines[line] = true
                end
              end
              Array(node.children).filter_map do |child|
                next unless child.respond_to?(:type) && child.type.to_s == 'table_row'

                position = child.source_position
                next unless position

                TableRowOwner.new(
                  location: Location.new(start_line: position[:start_line], end_line: position[:end_line]),
                  source: analysis.source_range(position[:start_line], position[:end_line]),
                  text: child.to_plaintext.to_s
                )
              end
            end
            ast_lines = ast_rows.map { |owner| owner.location.start_line }.to_h { |line| [line, true] }
            loose_rows = analysis.source.to_s.lines.each_with_index.filter_map do |line, index|
              line_number = index + 1
              next if ast_lines[line_number]
              next if ast_table_lines[line_number]
              next unless loose_table_row_line?(line)

              TableRowOwner.new(
                location: Location.new(start_line: line_number, end_line: line_number),
                source: line,
                text: line
              )
            end
            ast_rows + loose_rows
          end

          def loose_table_row_line?(line)
            stripped = line.to_s.lstrip
            return false unless stripped.start_with?('|')

            stripped.include?(' |') || stripped.include?('| ')
          end

          def heading_statement?(statement)
            merge_type = if statement.respond_to?(:merge_type)
                           statement.merge_type
                         else
                           unwrap_markdown_statement(statement)&.type
                         end

            %w[heading header].include?(merge_type.to_s)
          end

          def build_heading_owner(statement, analysis)
            node = unwrap_markdown_statement(statement)
            position = node&.source_position
            return unless node && position

            heading_source = analysis.source_range(position[:start_line], position[:end_line]).sub(/\n\z/, '')
            heading_text = node.to_plaintext.to_s.sub(/\n+\z/, '')
            HeadingSectionOwner.new(
              location: Location.new(start_line: position[:start_line], end_line: position[:end_line]),
              heading_text: heading_text,
              heading_source: heading_source,
              level: node.header_level,
              base: normalize_heading_base(heading_text)
            )
          rescue StandardError
            nil
          end

          def branch_end_line(headings, index, analysis)
            current = headings[index]
            cursor = index + 1
            while cursor < headings.length
              return headings[cursor].location.start_line - 1 if headings[cursor].level <= current.level

              cursor += 1
            end

            analysis.source.to_s.lines.length
          end

          def unwrap_markdown_statement(statement)
            if defined?(Ast::Merge::NodeTyping)
              Ast::Merge::NodeTyping.unwrap(statement)
            else
              statement
            end
          rescue StandardError
            statement
          end

          def normalize_heading_base(text)
            text.to_s.sub(/\A(?:\d\uFE0F?\u20E3|[^[:alnum:][:space:]])+[ \t]*/u, '').strip.downcase
          end

          def inline_references_for_line(line, line_number)
            owners = []
            index = 0
            while index < line.length
              image = inline_image_reference_at(line, index, line_number)
              if image
                owners << image
                index = image.end_column
                next
              end

              link = inline_link_reference_at(line, index, line_number)
              if link
                owners << link
                index = link.end_column
                next
              end

              index += 1
            end
            owners
          end

          def inline_image_reference_at(line, index, line_number)
            return unless line[index] == '!' && line[index + 1] == '['

            alt_end = closing_bracket_index(line, index + 1)
            return unless alt_end && line[alt_end + 1] == '['

            label_end = closing_bracket_index(line, alt_end + 1)
            return unless label_end

            label = line[(alt_end + 2)...label_end]
            inline_reference_owner(
              line: line,
              line_number: line_number,
              start_column: index,
              end_column: label_end + 1,
              reference_kind: :image_reference,
              label: label,
              labels: [label]
            )
          end

          def inline_link_reference_at(line, index, line_number)
            return unless line[index] == '['

            text_end = closing_bracket_index(line, index)
            return unless text_end && line[text_end + 1] == '['

            label_end = closing_bracket_index(line, text_end + 1)
            return unless label_end

            text = line[(index + 1)...text_end]
            label = line[(text_end + 2)...label_end]
            image_owner = inline_image_reference_at(text, 0, line_number)
            labels = [label]
            labels.unshift(image_owner.label) if image_owner && image_owner.source == text
            inline_reference_owner(
              line: line,
              line_number: line_number,
              start_column: index,
              end_column: label_end + 1,
              reference_kind: labels.length > 1 ? :linked_image_reference : :link_reference,
              label: label,
              labels: labels
            )
          end

          def inline_reference_owner(line:, line_number:, start_column:, end_column:, reference_kind:, label:, labels:)
            InlineReferenceOwner.new(
              location: Location.new(start_line: line_number, end_line: line_number),
              line: line_number,
              start_column: start_column,
              end_column: end_column,
              source: line[start_column...end_column],
              reference_kind: reference_kind,
              label: label,
              labels: labels.compact.uniq
            )
          end

          def closing_bracket_index(text, opening_index)
            depth = 0
            index = opening_index
            while index < text.length
              case text[index]
              when '['
                depth += 1
              when ']'
                depth -= 1
                return index if depth.zero?
              end
              index += 1
            end
            nil
          end
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
