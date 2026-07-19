# frozen_string_literal: true

require 'ast/crispr'
require 'prism/merge'
require 'version_gem'
require_relative 'prism/version'

module Ast
  module Crispr
    module Ruby
      module Prism
        class Error < StandardError; end

        module Utils
          module_function

          def parse_analysis(source, source_label: nil)
            ::Prism::Merge::FileAnalysis.new(source, source_label: source_label)
          end

          def parse_with_comments(source)
            parse_analysis(source).parse_result
          end
        end

        class Adapter
          def read_ast(document)
            analysis = Utils.parse_analysis(document.content, source_label: document.source_label)
            return analysis if analysis.valid?

            raise Ast::Crispr::Error.new("Unable to read structural owners from #{document.source_label}",
                                         details: { source_label: document.source_label })
          end

          def structural_owners(document, owner_scope: :shared_default)
            analysis = document.ast
            case owner_scope
            when :shared_default, :line_bound_statements, :top_level_statements
              analysis.statements
            when :ruby_comments
              analysis.parse_result.comments
            else
              raise Ast::Crispr::Error.new('Unsupported CRISPR owner scope', details: { owner_scope: owner_scope })
            end
          end

          def comment_regions_for(document, owner, region: :leading, owner_scope: :shared_default)
            analysis = document.ast
            owners = structural_owners(document, owner_scope: owner_scope)

            case region
            when :leading
              analysis.leading_comments_for_owner(owner, owners: owners)
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
