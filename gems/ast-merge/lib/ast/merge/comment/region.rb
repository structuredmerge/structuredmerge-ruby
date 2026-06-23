# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # A merge-facing region representing a contiguous span of comment-related
      # content with a specific ownership kind.
      #
      # Regions are passive data objects. They normalize parser-native or
      # source-augmented comment nodes into a shape that merge gems can attach to
      # structural AST nodes without changing merge behavior on their own.
      class Region
        # Supported normalized comment region kinds.
        #
        # @return [Array<Symbol>]
        KINDS = %i[
          leading
          inline
          trailing
          orphan
          preamble
          postlude
        ].freeze

        attr_reader :kind, :nodes, :metadata

        def initialize(kind:, nodes:, metadata: {}, **options)
          @kind = normalize_kind(kind)
          @nodes = Array(nodes).freeze
          @metadata = metadata.merge(options).freeze
        end

        def leading?
          kind == :leading
        end

        def inline?
          kind == :inline
        end

        def trailing?
          kind == :trailing
        end

        def orphan?
          kind == :orphan
        end

        def preamble?
          kind == :preamble
        end

        def postlude?
          kind == :postlude
        end

        # A floating region is gap-separated from its owner node by at least one
        # blank line.  Floating comments are positional — they belong to a place
        # in the file rather than to the specific AST node the parser attached
        # them to.  This distinction matters for merge deduplication: when two
        # sides attach the same floating comment block to different nodes, only
        # one copy should survive the merge.
        #
        # The value is set by the Augmenter during region construction.
        def floating?
          metadata[:floating] == true
        end

        def empty?
          nodes.empty?
        end

        # Return the first line touched by the region.
        #
        # @return [Integer, nil]
        def start_line
          locations.map(&:start_line).compact.min
        end

        # Return the last line touched by the region.
        #
        # @return [Integer, nil]
        def end_line
          locations.map(&:end_line).compact.max
        end

        # Return a synthetic location spanning the region.
        #
        # @return [AstNode::Location, nil]
        def location
          return if empty? || start_line.nil? || end_line.nil?

          AstNode::Location.new(
            start_line: start_line,
            end_line: end_line,
            start_column: 0,
            end_column: 0
          )
        end

        # Return normalized multi-line text used for region comparisons.
        #
        # @return [String]
        def normalized_content
          nodes
            .map { |node| node.respond_to?(:normalized_content) ? node.normalized_content : node.to_s }
            .join("\n")
        end

        # Return the raw text for all nodes in the region.
        #
        # @return [String]
        def text
          nodes
            .map { |node| node.respond_to?(:slice) ? node.slice.to_s : node.to_s }
            .join("\n")
        end

        # Return a compact signature for matching equivalent regions.
        #
        # @return [Array]
        def signature
          [:comment_region, kind, normalized_content[0..120]]
        end

        # Return all freeze/unfreeze actions exposed by nodes in the region.
        #
        # @param freeze_token [String] token to detect
        # @return [Array<Symbol>]
        def freeze_actions(freeze_token)
          nodes.filter_map do |node|
            next unless node.respond_to?(:freeze_action)

            node.freeze_action(freeze_token)
          end
        end

        def freeze?(freeze_token)
          freeze_actions(freeze_token).include?(:freeze)
        end

        def unfreeze?(freeze_token)
          freeze_actions(freeze_token).include?(:unfreeze)
        end

        def freeze_marker?(freeze_token)
          freeze?(freeze_token) || unfreeze?(freeze_token)
        end

        # Return a concise debug representation of the region.
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} kind=#{kind} lines=#{start_line}..#{end_line} nodes=#{nodes.size}>"
        end

        private

        def locations
          nodes.filter_map { |node| node.respond_to?(:location) ? node.location : nil }
        end

        def normalize_kind(kind)
          normalized = kind&.to_sym
          return normalized if KINDS.include?(normalized)

          raise ArgumentError,
                "Unknown comment region kind: #{kind.inspect}. Expected one of: #{KINDS.join(', ')}"
        end
      end
    end
  end
end
