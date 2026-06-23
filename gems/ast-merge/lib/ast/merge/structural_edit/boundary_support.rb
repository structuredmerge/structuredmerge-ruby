# frozen_string_literal: true

module Ast
  module Merge
    module StructuralEdit
      # Shared helpers for building structural-edit boundaries and removed
      # attachment payloads from statement-like objects.
      #
      # This module stays parser-agnostic: it only depends on the shared
      # analysis attachment hooks (`layout_attachment_for`,
      # `comment_attachment_for`) plus statement-like line-range interfaces
      # (`start_line` / `end_line` or `source_position`).
      module BoundarySupport
        extend self

        # Build a boundary descriptor for a surviving statement adjacent to a splice.
        #
        # @param analysis [Object] analysis exposing shared attachment hooks
        # @param statement [Object, nil] adjacent surviving statement
        # @param edge [Symbol] boundary edge, +:leading+ or +:trailing+
        # @param source [Symbol, String, nil] optional metadata source tag
        # @return [Boundary, nil]
        def build_splice_boundary(analysis, statement, edge:, source: nil)
          return unless statement

          owner = statement_owner(statement)

          Boundary.new(
            edge: edge,
            owner: owner,
            layout_attachment: analysis.respond_to?(:layout_attachment_for) ? analysis.layout_attachment_for(owner) : nil,
            comment_attachment: analysis.respond_to?(:comment_attachment_for) ? analysis.comment_attachment_for(owner) : nil,
            metadata: source ? { source: source } : {}
          )
        end

        # Collect comment/layout attachments from removed statements when they preserve fragments.
        #
        # @param analysis [Object] analysis exposing attachment hooks
        # @param statements [Array<Object>] removed statements
        # @return [Array<Object>]
        def removed_statement_attachments_for(analysis, statements)
          Array(statements).filter_map do |statement|
            owner = statement_owner(statement)

            comment_attachment = if analysis.respond_to?(:comment_attachment_for)
                                   analysis.comment_attachment_for(owner)
                                 end
            next comment_attachment if attachment_preserves_fragments?(comment_attachment)

            layout_attachment = (analysis.layout_attachment_for(owner) if analysis.respond_to?(:layout_attachment_for))
            next layout_attachment if attachment_preserves_fragments?(layout_attachment)
          end
        end

        def attachment_preserves_fragments?(attachment)
          return false unless attachment
          return !attachment.empty? if attachment.respond_to?(:empty?)

          gaps = attachment.respond_to?(:gaps) ? attachment.gaps : []
          regions = attachment.respond_to?(:regions) ? attachment.regions : []
          gaps.any? || regions.any?
        end

        # Return the starting line for a statement-like object.
        #
        # @param statement [Object]
        # @return [Integer, nil]
        def statement_start_line(statement)
          if statement.respond_to?(:start_line)
            statement.start_line
          elsif statement.respond_to?(:source_position)
            statement.source_position&.dig(:start_line)
          end
        end

        # Return the ending line for a statement-like object.
        #
        # @param statement [Object]
        # @return [Integer, nil]
        def statement_end_line(statement)
          if statement.respond_to?(:end_line)
            statement.end_line
          elsif statement.respond_to?(:source_position)
            statement.source_position&.dig(:end_line)
          end
        end

        private

        def statement_owner(statement)
          statement.respond_to?(:node) ? statement.node : statement
        end
      end
    end
  end
end
