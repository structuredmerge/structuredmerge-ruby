# frozen_string_literal: true

module Toml
  module Merge
    # Tracks pre-extracted TOML comment entries and exposes shared comment helpers.
    #
    # Inherits shared lookup, query, region-building, and attachment API from
    # +Ast::Merge::Comment::HashTrackerBase+. This tracker differs from most
    # siblings in that it receives pre-extracted comment entries from the TOML
    # parser rather than scanning source lines itself.
    #
    # Format-specific overrides:
    # - Initialization accepts pre-extracted entries + backend hint
    # - Region building preserves internal blank lines between comment nodes
    # - Inline comment detection is owner-aware (table headers vs key/value pairs)
    class CommentTracker < Ast::Merge::Comment::HashTrackerBase
      attr_reader :comment_entries, :backend

      def initialize(lines, comment_entries, backend: :tree_sitter)
        @comment_entries = Array(comment_entries).map { |entry| normalize_entry(entry) }
        @backend = backend
        super(Array(lines))
      end

      # Override: TOML inline comment detection is owner-aware — table headers
      # only match inline comments on their own line, while key/value pairs
      # match across their full line range.
      def comment_attachment_for(owner, line_num: nil, **options)
        owner_line = line_num || owner_start_line(owner)
        return Ast::Merge::Comment::Attachment.new(owner: owner, metadata: options) unless owner_line

        owner_last_line = owner_end_line(owner) || owner_line
        leading_region = build_toml_region(:leading, leading_comments_before(owner_line))
        inline_region = build_toml_region(:inline, owner_inline_comment_entries(owner, line_num: owner_line))
        trailing_region = build_toml_region(:trailing, trailing_comments_after(owner_last_line))

        Ast::Merge::Comment::Attachment.new(
          owner: owner,
          leading_region: leading_region,
          inline_region: inline_region,
          trailing_region: trailing_region,
          metadata: {
            source: native_comment_backend? ? :toml_native : :toml_source,
            line_num: owner_line,
            end_line: owner_last_line
          }.merge(options)
        )
      end

      def inline_comment_for(owner, line_num: nil)
        owner_inline_comment_entries(owner, line_num: line_num).first
      end

      def owner_inline_comment_entries(owner, line_num: nil)
        start_line = line_num || owner_start_line(owner)
        return [] unless start_line

        end_line = if owner_table_like?(owner)
                     start_line
                   else
                     owner_end_line(owner) || start_line
                   end

        @comment_entries.select do |entry|
          !entry[:full_line] && (start_line..end_line).cover?(entry[:line])
        end
      end

      private

      # Override: use pre-extracted entries directly instead of scanning source.
      def extract_comments
        @comment_entries
      end

      def normalize_entry(entry)
        entry.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value
        end
      end

      def native_comment_backend?
        @backend != :parslet
      end

      # Override: TOML region building preserves internal blank lines
      # between consecutive comment nodes.
      def build_comment_node(comment)
        comment[:comment_node] ||= Ast::Merge::Comment::TrackedHashAdapter.node(comment, style: :hash_comment)
      end

      def build_toml_region(kind, entries, metadata: {})
        return if entries.empty?

        nodes = []
        previous_line = nil
        include_blank_lines = kind != :inline

        entries.sort_by { |entry| entry[:line] }.each do |entry|
          if include_blank_lines && previous_line
            ((previous_line + 1)...entry[:line]).each do |line_number|
              if line_at(line_number).to_s.strip.empty?
                nodes << Ast::Merge::Comment::Empty.new(line_number: line_number, text: line_at(line_number).to_s)
              end
            end
          end

          nodes << build_comment_node(entry)
          previous_line = entry[:line]
        end

        Ast::Merge::Comment::Region.new(
          kind: kind,
          nodes: nodes,
          metadata: {
            source: native_comment_backend? ? :toml_native : :toml_source,
            tracked_hashes: entries
          }.merge(metadata)
        )
      end

      def owner_table_like?(owner)
        actual_owner = owner.respond_to?(:unwrap) ? owner.unwrap : owner
        return true if actual_owner.respond_to?(:table?) && actual_owner.table?
        return true if actual_owner.respond_to?(:array_of_tables?) && actual_owner.array_of_tables?

        NodeTypeNormalizer.table_type?(NodeTypeNormalizer.canonical_type(actual_owner.type, @backend))
      rescue NoMethodError
        false
      end

      def owner_start_line(owner)
        actual_owner = owner.respond_to?(:unwrap) ? owner.unwrap : owner
        return actual_owner.start_line if actual_owner.respond_to?(:start_line)

        node_start_line(actual_owner)
      end

      def owner_end_line(owner)
        actual_owner = owner.respond_to?(:unwrap) ? owner.unwrap : owner
        return actual_owner.end_line if actual_owner.respond_to?(:end_line)

        node_end_line(actual_owner)
      end

      def node_start_line(node)
        extract_point_row(node.respond_to?(:start_point) ? node.start_point : nil)&.+(1)
      end

      def node_end_line(node)
        extract_point_row(node.respond_to?(:end_point) ? node.end_point : nil)&.+(1)
      end

      def extract_point_row(point)
        return point.row if point.respond_to?(:row)
        return point[:row] if point.is_a?(Hash)

        nil
      end

      # Override owner_line_num for the base class's leading comment helpers.
      def owner_line_num(owner)
        owner_start_line(owner)
      end
    end
  end
end
