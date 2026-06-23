# frozen_string_literal: true

module Ast
  module Merge
    module Text
      # Text file analysis class for the text-based AST.
      #
      # This class parses plain text files into a simple AST structure where:
      # - Top-level nodes are LineNodes (one per line)
      # - Nested nodes are WordNodes (words within each line, split on word boundaries)
      #
      # This provides a minimal AST implementation that can be used to test
      # the merge infrastructure with any text-based content.
      #
      # @example Basic usage
      #   analysis = FileAnalysis.new("Hello world\nGoodbye world")
      #   analysis.statements.size  # => 2
      #   analysis.statements[0].words.size  # => 2
      #
      # @example With freeze blocks
      #   content = <<~TEXT
      #     Line one
      #     # text-merge:freeze
      #     Frozen content
      #     # text-merge:unfreeze
      #     Line four
      #   TEXT
      #   analysis = FileAnalysis.new(content, freeze_token: "text-merge")
      #   analysis.freeze_blocks.size  # => 1
      class FileAnalysis
        include FileAnalyzable

        # Default freeze token for text files
        DEFAULT_FREEZE_TOKEN = 'text-merge'

        # Initialize a new FileAnalysis
        #
        # @param source [String] Source text content
        # @param freeze_token [String] Token for freeze block markers
        # @param signature_generator [Proc, nil] Custom signature generator
        def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil)
          @source = source
          # Split preserving empty lines, but remove trailing empty line from final newline
          @lines = source.split("\n", -1)
          @lines.pop if @lines.last&.empty? && source.end_with?("\n")
          @freeze_token = freeze_token
          @signature_generator = signature_generator
          @statements = parse_statements
        end

        # Get all top-level statements (LineNodes and FreezeNodes)
        #
        # @return [Array<LineNode, FreezeNodeBase>] All top-level statements
        attr_reader :statements

        # Compute signature for a node
        #
        # @param node [Object] Node to compute signature for
        # @return [Array, nil] Signature array or nil
        def compute_node_signature(node)
          case node
          when LineNode
            node.signature
          when FreezeNodeBase
            [:freeze_block, node.start_line, node.end_line]
          end
        end

        # Check if a value is a fallthrough node
        #
        # @param value [Object] Value to check
        # @return [Boolean] True if fallthrough node
        def fallthrough_node?(value)
          value.is_a?(LineNode) || value.is_a?(FreezeNodeBase) || super
        end

        # Build a whitespace-normalized, searchable string from a set of line nodes.
        #
        # Joins each line's normalized content with a single space, collapsing all
        # internal whitespace. This allows phrase-based content matching (e.g. MIT
        # license detection) regardless of where the author chose to break lines.
        #
        # @example Detect MIT license regardless of line breaks
        #   analysis = FileAnalysis.new(license_text)
        #   analysis.searchable_text.downcase.include?("permission is hereby granted")
        #
        # @param nodes [Array<LineNode>, nil] Subset of nodes to search.
        #   Defaults to all statements when nil.
        # @return [String] Single-space-joined, stripped, whitespace-collapsed string
        def searchable_text(nodes: nil)
          source_nodes = nodes || @statements
          source_nodes
            .select { |n| n.is_a?(LineNode) }
            .map(&:normalized_content)
            .reject(&:empty?)
            .join(' ')
            .gsub(/\s+/, ' ')
            .strip
        end

        private

        # Parse source into statements (LineNodes and FreezeNodes)
        #
        # @return [Array] Parsed statements
        def parse_statements
          statements = []
          freeze_start = nil
          freeze_start_line = nil

          @lines.each_with_index do |line, idx|
            line_number = idx + 1

            # Check for freeze markers
            if freeze_marker?(line, :freeze)
              freeze_start = line_number
              freeze_start_line = line
              next
            end

            if freeze_marker?(line, :unfreeze)
              if freeze_start
                # Create freeze block
                freeze_content = @lines[(freeze_start - 1)..(line_number - 1)].join("\n")
                statements << FreezeNodeBase.new(
                  start_line: freeze_start,
                  end_line: line_number,
                  content: freeze_content,
                  reason: extract_freeze_reason(freeze_start_line)
                )
                freeze_start = nil
                freeze_start_line = nil
              end
              next
            end

            # Skip lines inside freeze blocks
            next if freeze_start

            # Regular line
            statements << LineNode.new(line, line_number: line_number)
          end

          # Handle unclosed freeze block
          if freeze_start
            raise FreezeNodeBase::InvalidStructureError.new(
              "Unclosed freeze block starting at line #{freeze_start}",
              start_line: freeze_start
            )
          end

          statements
        end

        # Check if a line is a freeze marker
        #
        # @param line [String] Line to check
        # @param type [Symbol] :freeze or :unfreeze
        # @return [Boolean] True if line is a marker
        def freeze_marker?(line, type)
          style = Comment::Style.for(:hash_comment)
          return false unless style.match_line?(line)

          marker_type = Comment::Line.new(text: line, line_number: 1, style: style).freeze_action(@freeze_token)
          case type
          when :freeze
            marker_type == :freeze
          when :unfreeze
            marker_type == :unfreeze
          else
            false
          end
        end

        # Extract freeze reason from marker line
        #
        # @param line [String] Freeze marker line
        # @return [String, nil] Reason or nil
        def extract_freeze_reason(line)
          pattern = FreezeNodeBase.pattern_for(:hash_comment, @freeze_token)
          match = line.match(pattern)
          reason = match[2]&.strip
          reason.nil? || reason.empty? ? nil : reason
        end
      end
    end
  end
end
