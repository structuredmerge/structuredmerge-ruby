# frozen_string_literal: true

module Markdown
  module Merge
    # Builds markdown output from merge operations.
    #
    # Handles markdown-specific concerns like:
    # - Extracting source from original nodes
    # - Reconstructing consumed link reference definitions
    # - Preserving gap lines (blank line spacing)
    # - Automatic structural spacing (blank lines between tables, headings, etc.)
    # - Assembling final merged content
    #
    # Unlike Emitter classes used in JSON/YAML/etc, OutputBuilder focuses on
    # source preservation and reconstruction rather than generation from scratch.
    #
    # @example Basic usage
    #   builder = OutputBuilder.new
    #   builder.add_node_source(node, analysis)
    #   builder.add_link_definition(link_def_node)
    #   builder.add_gap_line(count: 2)
    #   content = builder.to_s
    class OutputBuilder
      # Initialize a new OutputBuilder
      #
      # @param preserve_formatting [Boolean] Whether to preserve original formatting
      # @param auto_spacing [Boolean] Whether to automatically insert blank lines between structural elements
      def initialize(preserve_formatting: true, auto_spacing: true)
        @parts = []
        @length = 0
        @preserve_formatting = preserve_formatting
        @auto_spacing = auto_spacing
        @last_node_type = nil  # Track previous node type for spacing decisions
        @last_end_line = nil   # Track previous node's end line for adjacency detection
        @last_analysis = nil   # Track previous node's analysis for same-source detection
      end

      # Add a node's source content
      #
      # Automatically inserts structural blank lines when transitioning between
      # certain node types (tables, headings, code blocks, etc.) if auto_spacing is enabled.
      # Skips auto-spacing when nodes are adjacent in the same source — the original
      # formatting is preserved by the source extraction.
      #
      # @param node [Object] Node to add (can be parser node, FreezeNode, LinkDefinitionNode, etc.)
      # @param analysis [FileAnalysisBase] Analysis for accessing source
      def add_node_source(node, analysis)
        # Determine node type for spacing decisions
        current_type = MarkdownStructure.node_type(node)

        # Auto-spacing logic:
        # - Skip for gap_line and freeze_block (they handle their own spacing)
        # - Skip if last node was a gap_line (we already have spacing)
        # - Skip if nodes are adjacent in the same source (original spacing is correct)
        # - Otherwise, check MarkdownStructure.needs_blank_between? which handles
        #   contiguous types (like link_definitions that shouldn't have blanks between them)
        # Skip auto-spacing when nodes are adjacent lines in the same source.
        # The original source formatting is correct — no blank line was there.
        if !(%i[gap_line freeze_block].include?(current_type) ||
                       @last_node_type == :gap_line) && @auto_spacing && @last_node_type && current_type && MarkdownStructure.needs_blank_between?(@last_node_type,
                                                                                                                                                   current_type) && !same_source_adjacent?(
                                                                                                                                                     node, analysis
                                                                                                                                                   ) && !(@parts.empty? || blank_line_terminated?)
          # Only add spacing if we don't already have adequate blank lines
          # Check the last part to see if it already ends with blank line(s)
          add_gap_line(count: 1)
        end

        content = extract_source(node, analysis)
        return unless content && !content.empty?

        range = append_part(content)
        # Update last node type (track all node types for proper spacing)
        @last_node_type = current_type
        @last_end_line = node_end_line(node)
        @last_analysis = analysis
        range
      end

      # Add a reconstructed link definition
      #
      # @param node [LinkDefinitionNode] Link definition node
      def add_link_definition(node)
        formatted = LinkDefinitionFormatter.format(node)
        append_part(formatted) if formatted && !formatted.empty?
      end

      # Add gap lines (blank line preservation)
      #
      # @param count [Integer] Number of blank lines to add
      def add_gap_line(count: 1)
        append_part("\n" * count) if count > 0
      end

      # Add raw text content
      #
      # @param text [String] Raw text to add
      def add_raw(text)
        append_part(text) if text && !text.empty?
      end

      # Get final content
      #
      # @return [String] Assembled markdown content
      def to_s
        @parts.join
      end

      # Check if builder has any content
      #
      # @return [Boolean]
      def empty?
        @parts.empty?
      end

      # Check whether the current output already ends with a blank-line separator.
      #
      # This looks across part boundaries so a trailing blank line represented as
      # separate content + gap parts still counts as an existing separator.
      #
      # @return [Boolean]
      def blank_line_terminated?
        trailing_newlines = 0

        @parts.reverse_each do |part|
          next if part.nil? || part.empty?

          idx = part.length - 1
          while idx >= 0 && part[idx] == "\n"
            trailing_newlines += 1
            idx -= 1
          end

          break if idx >= 0
        end

        trailing_newlines >= 2
      end

      # Clear all content
      def clear
        @parts.clear
        @length = 0
      end

      private

      def append_part(text)
        start_offset = @length
        @parts << text
        @length += text.bytesize
        [start_offset, @length]
      end

      # Check if the current node is adjacent (consecutive lines) to the previous
      # node in the same source file. When true, the original source already has
      # the correct inter-node spacing and auto-spacing should not add blank lines.
      #
      # @param node [Object] Current node being added
      # @param analysis [FileAnalysisBase] Current node's analysis
      # @return [Boolean] true if nodes are from the same source and adjacent
      def same_source_adjacent?(node, analysis)
        return false unless @last_end_line && @last_analysis
        return false unless @last_analysis.equal?(analysis)

        current_start = node_start_line(node)
        return false unless current_start

        # Adjacent: the current node starts on or immediately after the previous node ended
        current_start <= @last_end_line + 1
      end

      # Extract start line from a node
      #
      # @param node [Object] Node to inspect
      # @return [Integer, nil] 1-based start line
      def node_start_line(node)
        if node.respond_to?(:source_position)
          node.source_position&.dig(:start_line)
        elsif node.respond_to?(:start_line)
          node.start_line
        end
      end

      # Extract end line from a node
      #
      # @param node [Object] Node to inspect
      # @return [Integer, nil] 1-based end line
      def node_end_line(node)
        if node.respond_to?(:source_position)
          node.source_position&.dig(:end_line)
        elsif node.respond_to?(:end_line)
          node.end_line
        end
      end

      # Extract source content from a node
      #
      # @param node [Object] Node to extract from
      # @param analysis [FileAnalysisBase] Analysis for source access
      # @return [String, nil] Extracted content
      def extract_source(node, analysis)
        case node
        when LinkDefinitionNode
          # Link definitions need reconstruction with trailing newline
          "#{LinkDefinitionFormatter.format(node)}\n"
        when GapLineNode
          # Gap lines are single blank lines
          "\n"
        when Ast::Merge::FreezeNodeBase
          # Freeze blocks have their full text
          node.full_text
        else
          # Regular nodes - extract from source
          extract_parser_node_source(node, analysis)
        end
      end

      # Extract source from a parser-specific node
      #
      # @param node [Object] Parser node
      # @param analysis [FileAnalysisBase] Analysis for source access
      # @return [String, nil] Extracted content
      def extract_parser_node_source(node, analysis)
        # Try source_position method first (used by some nodes)
        if node.respond_to?(:source_position)
          pos = node.source_position
          start_line = pos&.dig(:start_line)
          end_line = pos&.dig(:end_line)

          if start_line && end_line
            return analysis.source_range(start_line, end_line)
          elsif node.respond_to?(:to_commonmark)
            # Fallback to commonmark rendering
            return node.to_commonmark
          end
        end

        # Try direct start_line/end_line attributes
        return unless node.respond_to?(:start_line) && node.respond_to?(:end_line)
        return unless node.start_line && node.end_line

        # Extract source range (formatting preservation handled elsewhere)
        analysis.source_range(node.start_line, node.end_line)
      end
    end
  end
end
