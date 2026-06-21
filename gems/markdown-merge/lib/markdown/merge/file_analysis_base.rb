# frozen_string_literal: true

require "digest"
require "set"

module Markdown
  module Merge
    # Base class for file analysis for Markdown files.
    #
    # Parses Markdown source code and extracts:
    # - Top-level block elements (headings, paragraphs, lists, code blocks, etc.)
    # - Freeze blocks marked with HTML comments
    # - Structural signatures for matching elements between files
    #
    # Subclasses must implement parser-specific methods:
    # - #parse_document(source) - Parse source and return document node
    # - #next_sibling(node) - Get next sibling of a node
    # - #compute_parser_signature(node) - Compute signature for parser-specific nodes
    # - #node_type_name(type) - Map canonical type names if needed
    #
    # Freeze blocks are marked with HTML comments:
    #   <!-- markdown-merge:freeze -->
    #   ... content to preserve ...
    #   <!-- markdown-merge:unfreeze -->
    #
    # @example Basic usage (subclass)
    #   class FileAnalysis < Markdown::Merge::FileAnalysisBase
    #     def parse_document(source)
    #       Markly.parse(source, flags: @flags)
    #     end
    #
    #     def next_sibling(node)
    #       node.next
    #     end
    #   end
    #
    # @abstract Subclass and implement parser-specific methods
    class FileAnalysisBase
      include Ast::Merge::FileAnalyzable

      # Default freeze token for identifying freeze blocks
      # @return [String]
      DEFAULT_FREEZE_TOKEN = "markdown-merge"

      # @return [Object] The root document node
      attr_reader :document

      # @return [Array] Parse errors if any
      attr_reader :errors

      # @return [CommentTracker] Comment tracker for this file
      attr_reader :comment_tracker

      # Note: :source is inherited from Ast::Merge::FileAnalyzable

      # Initialize file analysis
      #
      # @param source [String] Markdown source code to analyze
      # @param freeze_token [String] Token for freeze block markers
      # @param signature_generator [Proc, nil] Custom signature generator
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil, **parser_options)
        @source = source
        # Split by newlines, keeping trailing empty strings (-1)
        # But remove the final empty string if source ends with newline
        # (that empty string represents the "line after the last newline" which doesn't exist)
        @lines = source.split("\n", -1)
        @lines.pop if @lines.last == "" && source.end_with?("\n")
        @comment_tracker = CommentTracker.new(@lines)

        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @parser_options = parser_options
        @errors = []

        # Parse the Markdown source - subclasses implement this
        @document = DebugLogger.time("FileAnalysisBase#parse") do
          parse_document(source)
        end

        # Extract and integrate all nodes including freeze blocks
        @statements = extract_and_integrate_all_nodes

        DebugLogger.debug("FileAnalysisBase initialized", {
          signature_generator: signature_generator ? "custom" : "default",
          document_children: count_children(@document),
          statements_count: @statements.size,
          freeze_blocks: freeze_blocks.size,
        })
      end

      # Parse the source document.
      #
      # @abstract Subclasses must implement this method
      # @param source [String] Markdown source to parse
      # @return [Object] Root document node
      def parse_document(source)
        raise NotImplementedError, "#{self.class} must implement #parse_document"
      end

      # Get the next sibling of a node.
      #
      # Different parsers use different methods (next vs next_sibling).
      #
      # @abstract Subclasses must implement this method
      # @param node [Object] Current node
      # @return [Object, nil] Next sibling or nil
      def next_sibling(node)
        raise NotImplementedError, "#{self.class} must implement #next_sibling"
      end

      # Check if parse was successful
      # @return [Boolean]
      def valid?
        @errors.empty? && !@document.nil?
      end

      # Get shared comment capability information for this analysis.
      #
      # @return [Object]
      def comment_capability
        @comment_capability ||= comment_tracker.augment(owners: []).capability
      end

      # Describe how Markdown merges currently own and emit comments.
      #
      # Standalone HTML comments are source-augmented and emitted through the
      # shared synthetic comment layer rather than parser-native comment AST.
      #
      # @return [Ast::Merge::Comment::SupportStyle]
      def comment_support_style
        @comment_support_style ||= shared_comment_support_style(
          source: :markdown_source,
          style: :html_comment,
          read_strategy: :source_augmented_portable_write,
        )
      end

      # Get all tracked comments converted to shared comment nodes.
      #
      # @return [Array]
      def comment_nodes
        comment_tracker.comment_nodes
      end

      # Get a shared comment node at a specific line.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Object, nil]
      def comment_node_at(line_num)
        comment_tracker.comment_node_at(line_num)
      end

      # Get comments in a line range converted to a shared comment region.
      #
      # @param range [Range] Range of 1-based line numbers
      # @param kind [Symbol] Region kind
      # @param full_line_only [Boolean] Whether to keep only full-line comments
      # @return [Object]
      def comment_region_for_range(range, kind:, full_line_only: false)
        comment_tracker.comment_region_for_range(
          range,
          kind: kind,
          full_line_only: full_line_only,
        )
      end

      # Build a passive shared comment attachment for an owner.
      #
      # @param owner [Object] Structural owner for the attachment
      # @param options [Hash] Additional metadata / lookup overrides
      # @return [Object]
      def comment_attachment_for(owner, **options)
        augmented_attachment = comment_augmenter(**options).attachment_for(owner)

        shared_comment_attachment_for(
          owner,
          tracker_attachment: augmented_attachment || comment_tracker.comment_attachment_for(owner, **options),
          **options,
        )
      end

      # @return [Symbol]
      def comment_attachment_strategy
        :normalize_tracked_layout_merge
      end

      def ruleset_logical_owners
        {
          link_definition: :preserve_if_referenced,
        }
      end

      def ruleset_surfaces
        [
          {name: :fenced_code_block, selector: :language_tag},
        ]
      end

      def ruleset_delegation_policies
        [
          {surface_name: :fenced_code_block, strategy: :by_language},
        ]
      end

      # Build a passive shared comment augmenter for this analysis.
      #
      # @param owners [Array, nil] Owners used for attachment inference
      # @param options [Hash] Additional augmenter options
      # @return [Object]
      def comment_augmenter(owners: nil, **options)
        comment_tracker.augment(
          owners: owners || comment_augmenter_default_owners,
          **options,
        )
      end

      # Get all statements (block nodes outside freeze blocks + FreezeNode instances)
      # @return [Array<Object, FreezeNode>]
      attr_reader :statements

      # Compute default signature for a node
      # @param node [Object] The parser node or FreezeNode
      # @return [Array, nil] Signature array
      def compute_node_signature(node)
        case node
        when Ast::Merge::FreezeNodeBase
          node.signature
        when LinkDefinitionNode
          node.signature
        when GapLineNode
          node.signature
        else
          compute_parser_signature(node)
        end
      end

      # Override to detect parser nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.is_a?(Ast::Merge::FreezeNodeBase) ||
          value.is_a?(LinkDefinitionNode) ||
          value.is_a?(GapLineNode) ||
          parser_node?(value) ||
          super
      end

      # Check if value is a parser-specific node.
      #
      # @param value [Object] Value to check
      # @return [Boolean] true if this is a parser node
      def parser_node?(value)
        # Default: check if it responds to :type (common for AST nodes)
        value.respond_to?(:type)
      end

      # Compute signature for a parser-specific node.
      #
      # @abstract Subclasses should override this method
      # @param node [Object] The parser node
      # @return [Array, nil] Signature array
      def compute_parser_signature(node)
        type = node.type
        case type
        when :heading, :header
          level = node.header_level
          # H1 is the document title — treat as a singleton.
          # A well-formed markdown document has exactly one H1. Matching by text
          # would cause a generic template title ("AGENTS.md - Development Guide")
          # and a project-qualified destination title ("AGENTS.md - myGem Development Guide")
          # to be treated as different nodes, keeping both in the merged output.
          # Using level-only for H1 makes them the same structural slot so the
          # preferred version wins cleanly without duplication.
          return [:heading, 1] if level == 1

          # H2+ match by level and normalized text content
          [:heading, level, extract_text_content(node)]
        when :paragraph
          # Content-based: Match paragraphs by content hash (first 32 chars of digest)
          text = extract_text_content(node)
          [:paragraph, Digest::SHA256.hexdigest(text)[0, 32]]
        when :code_block
          # Content-based: Match code blocks by fence info and content hash
          content = safe_string_content(node)
          fence_info = node.respond_to?(:fence_info) ? node.fence_info : nil
          [:code_block, fence_info, Digest::SHA256.hexdigest(content)[0, 16]]
        when :list
          # Content-fingerprint: Match lists by type and a hash of the first few
          # items' significant tokens. This lets two lists with similar (but not
          # identical) content match by signature so item-level inner-merge can run,
          # rather than the template list being appended as a template-only node.
          list_type = node.respond_to?(:list_type) ? node.list_type : nil
          items_text = []
          child = node.first_child
          while child
            items_text << extract_text_content(child).downcase.gsub(/\W+/, " ").strip
            child = next_sibling(child)
            break if items_text.size >= 5
          end
          fingerprint = Digest::SHA256.hexdigest(items_text.sort.join("|"))[0, 16]
          [:list, list_type, fingerprint]
        when :block_quote, :blockquote
          # Content-based: Match block quotes by content hash
          text = extract_text_content(node)
          [:blockquote, Digest::SHA256.hexdigest(text)[0, 16]]
        when :thematic_break, :hrule
          # Structure-based: All thematic breaks are equivalent
          [:hrule]
        when :html_block, :html
          # Content-based: Match HTML blocks by content hash
          content = safe_string_content(node)
          [:html, Digest::SHA256.hexdigest(content)[0, 16]]
        when :table
          # Content-based: Match tables by structure and header content
          header_content = extract_table_header_content(node)
          [:table, count_children(node), Digest::SHA256.hexdigest(header_content)[0, 16]]
        when :footnote_definition
          # Name/label-based: Match footnotes by name or label
          label = node.respond_to?(:name) ? node.name : safe_string_content(node)
          [:footnote_definition, label]
        when :custom_block
          # Content-based: Match custom blocks by content hash
          text = extract_text_content(node)
          [:custom_block, Digest::SHA256.hexdigest(text)[0, 16]]
        else
          # Unknown type - use type and position
          pos = node.source_position
          [:unknown, type, pos&.dig(:start_line)]
        end
      end

      # Safely get string content from a node
      # @param node [Object] The node
      # @return [String] String content or empty string
      def safe_string_content(node)
        node.string_content.to_s
      rescue TypeError
        # Some node types don't support string_content
        extract_text_content(node)
      end

      # Extract all text content from a node and its children
      # @param node [Object] The node
      # @return [String] Concatenated text content
      def extract_text_content(node)
        text_parts = []
        node.walk do |child|
          if child.type == :text
            text_parts << child.string_content.to_s
          elsif child.type == :code
            text_parts << child.string_content.to_s
          end
        end
        text_parts.join
      end

      # Get the source text for a range of lines
      #
      # Lines are joined with newlines, and each line gets a trailing newline
      # except for the last line of the file (which may or may not have one in the original).
      #
      # @param start_line [Integer] Start line (1-indexed)
      # @param end_line [Integer] End line (1-indexed)
      # @return [String] Source text
      def source_range(start_line, end_line)
        return "" if start_line < 1 || end_line < start_line

        extracted_lines = @lines[(start_line - 1)..(end_line - 1)]
        return "" if extracted_lines.empty?

        # Add newlines between and after lines, but not after the last line of the file
        # unless it originally had one
        result = extracted_lines.join("\n")

        # Add trailing newline if this isn't the last line of the file
        # (the last line may or may not have a trailing newline in the original source)
        if end_line < @lines.length
          result += "\n"
        elsif @source&.end_with?("\n")
          # Last line of file, but original source ends with newline
          result += "\n"
        end

        result
      end

      protected

      # Extract header content from a table node
      # @param node [Object] The table node
      # @return [String] Header row content
      def extract_table_header_content(node)
        # First row of a table is typically the header
        first_row = node.first_child
        return "" unless first_row

        extract_text_content(first_row)
      end

      # Count children of a node
      # @param node [Object] The node
      # @return [Integer] Child count
      def count_children(node)
        count = 0
        child = node.first_child
        while child
          count += 1
          child = next_sibling(child)
        end
        count
      end

      private

      def comment_augmenter_default_owners
        @comment_augmenter_default_owners ||= @statements.select do |statement|
          statement.respond_to?(:source_position) && statement.source_position &&
            (!statement.respond_to?(:merge_type) || statement.merge_type != :gap_line) &&
            !standalone_comment_statement?(statement)
        end
      end

      def standalone_comment_statement?(statement)
        pos = statement.respond_to?(:source_position) ? statement.source_position : nil
        return false unless pos
        return false unless pos[:start_line] && pos[:end_line] && pos[:start_line] == pos[:end_line]

        comment_tracker.comment_node_at(pos[:start_line])
      end

      # Extract all nodes and integrate freeze blocks
      # @return [Array<Object>] Integrated list of nodes and freeze blocks
      def extract_and_integrate_all_nodes
        freeze_markers = find_freeze_markers

        # Use gap-aware collection to preserve link definitions and gap lines
        base_nodes = collect_top_level_nodes_with_gaps

        return base_nodes if freeze_markers.empty?

        # Build freeze blocks from markers
        freeze_blocks = build_freeze_blocks(freeze_markers)
        return base_nodes if freeze_blocks.empty?

        # Integrate nodes with freeze blocks
        integrate_nodes_with_freeze_blocks(freeze_blocks, base_nodes)
      end

      # Collect top-level nodes from document
      # @return [Array<Object>]
      def collect_top_level_nodes
        nodes = []
        child = @document.first_child
        while child
          nodes << child
          child = next_sibling(child)
        end
        nodes
      end

      # Collect top-level nodes with gap line detection.
      #
      # Markdown parsers consume certain content (like link reference definitions)
      # during parsing. This method detects "gap" lines that aren't covered by any
      # node and creates synthetic nodes for them.
      #
      # @return [Array<Object>] Nodes including gap line nodes
      def collect_top_level_nodes_with_gaps
        parser_nodes = collect_top_level_nodes
        return parser_nodes if @lines.empty?

        # Track which lines are covered by parser nodes
        covered_lines = Set.new
        parser_nodes.each do |node|
          pos = node.source_position
          next unless pos

          start_line = pos[:start_line]
          end_line = pos[:end_line]

          # Handle Markly's buggy position reporting for :html nodes
          # where end_line can be less than start_line (e.g., "lines 3-2")
          if end_line < start_line
            # Just mark the start_line as covered
            covered_lines << start_line
          else
            (start_line..end_line).each { |l| covered_lines << l }
          end
        end

        # Find gap lines (lines not covered by any node)
        total_lines = @lines.size
        gap_line_numbers = (1..total_lines).to_a - covered_lines.to_a

        # Create nodes for gap lines
        gap_nodes = create_gap_nodes(gap_line_numbers)

        # Integrate gap nodes with parser nodes in line order
        integrate_gap_nodes(parser_nodes, gap_nodes)
      end

      # Create nodes for gap lines.
      #
      # Link reference definitions get LinkDefinitionNode, others get GapLineNode.
      # Every gap line gets a node so we can reconstruct the document exactly.
      #
      # @param line_numbers [Array<Integer>] Gap line numbers (1-based)
      # @return [Array<Object>] Gap nodes
      def create_gap_nodes(line_numbers)
        line_numbers.map do |line_num|
          content = @lines[line_num - 1] || ""

          # Try to parse as link definition first
          link_node = LinkDefinitionNode.parse(content, line_number: line_num)
          if link_node
            link_node
          else
            GapLineNode.new(content, line_number: line_num)
          end
        end
      end

      # Integrate gap nodes with parser nodes in line order.
      # Sets preceding_node for gap lines to enable context-aware signatures.
      #
      # @param parser_nodes [Array<Object>] Parser-generated nodes
      # @param gap_nodes [Array<Object>] Gap line nodes
      # @return [Array<Object>] All nodes in line order
      def integrate_gap_nodes(parser_nodes, gap_nodes)
        all_nodes = parser_nodes + gap_nodes

        # Sort by start line
        sorted_nodes = all_nodes.sort_by do |node|
          pos = node.source_position
          pos ? pos[:start_line] : 0
        end

        # Set preceding_node for gap lines based on their position in the sorted list
        # This allows gap lines to have context-aware signatures
        sorted_nodes.each_with_index do |node, idx|
          if node.is_a?(GapLineNode) && idx > 0
            # Find the previous non-gap-line node (structural node)
            preceding = sorted_nodes[0...idx].reverse.find { |n| !n.is_a?(GapLineNode) }
            node.preceding_node = preceding
            if preceding
              node.preceding_signature = begin
                compute_node_signature(preceding)
              rescue StandardError
                nil
              end
            end
          end
        end

        sorted_nodes
      end

      # Find freeze markers from parsed HTML nodes.
      #
      # Freeze markers are HTML comments that Markly parses as :html nodes.
      # By analyzing the parsed nodes (not raw source lines), we automatically ignore
      # freeze markers that appear inside code blocks (they're part of the code block's
      # string content, not separate nodes).
      #
      # Note: We only support freeze markers as standalone HTML comment nodes.
      # Freeze markers embedded inside other HTML tags (e.g., `<div><!-- freeze -->text</div>`)
      # are not detected because they're part of a larger HTML node's content.
      #
      # @return [Array<Hash>] Marker information
      def find_freeze_markers
        markers = []
        pattern = Ast::Merge::FreezeNodeBase.pattern_for(:html_comment, @freeze_token)

        return markers unless @document

        # Walk through top-level nodes looking for HTML nodes with freeze markers
        child = @document.first_child
        while child
          node_type = child.type

          # Check HTML nodes for freeze markers
          # Handle both raw Markly (:html) and TreeHaver normalized ("html_block", :html_block) types
          if node_type == :html || node_type == :html_block || node_type == "html_block" || node_type == "html"
            # Try multiple content extraction methods:
            # 1. string_content (raw Markly/Commonmarker)
            # 2. to_commonmark on wrapper
            # 3. inner_node.to_commonmark (TreeHaver Commonmarker wrapper)
            content = nil

            if child.respond_to?(:string_content)
              begin
                content = child.string_content.to_s
              rescue TypeError
                # Some nodes don't have string_content
                content = nil
              end
            end

            if content.nil? || content.empty?
              if child.respond_to?(:to_commonmark)
                content = child.to_commonmark.to_s
              end
            end

            # TreeHaver Commonmarker wrapper stores content in inner_node
            if (content.nil? || content.empty?) && child.respond_to?(:inner_node)
              inner = child.inner_node
              if inner.respond_to?(:to_commonmark)
                content = inner.to_commonmark.to_s
              end
            end

            content ||= ""
            match = content.match(pattern)

            if match
              pos = child.source_position
              marker_type = match[1] # "freeze" or "unfreeze"
              reason = match[2]      # optional reason

              markers << {
                line: pos ? pos[:start_line] : 0,
                type: marker_type.to_sym,
                text: content.strip,
                reason: reason,
                node: child, # Keep reference to the actual node
              }
            end
          end

          child = next_sibling(child)
        end

        DebugLogger.debug("Found freeze markers", {count: markers.size})
        markers
      end

      # Build freeze blocks from markers
      # @param markers [Array<Hash>] Marker information
      # @return [Array<FreezeNode>] Freeze blocks
      def build_freeze_blocks(markers)
        blocks = []
        stack = []

        markers.each do |marker|
          case marker[:type]
          when :freeze
            stack.push(marker)
          when :unfreeze
            if stack.any?
              start_marker = stack.pop
              blocks << create_freeze_block(start_marker, marker)
            else
              DebugLogger.debug("Unmatched unfreeze marker", {line: marker[:line]})
            end
          end
        end

        # Warn about unclosed freeze blocks
        stack.each do |unclosed|
          DebugLogger.debug("Unclosed freeze marker", {line: unclosed[:line]})
        end

        blocks.sort_by(&:start_line)
      end

      # Create a freeze block from start and end markers.
      #
      # Subclasses may override to provide parser-specific FreezeNode subclass.
      #
      # @param start_marker [Hash] Start marker info
      # @param end_marker [Hash] End marker info
      # @return [FreezeNode]
      def create_freeze_block(start_marker, end_marker)
        start_line = start_marker[:line]
        end_line = end_marker[:line]

        # Content is between the markers (exclusive)
        content_start = start_line + 1
        content_end = end_line - 1

        content = if content_start <= content_end
          source_range(content_start, content_end)
        else
          ""
        end

        # Parse the content to get nodes (for nested analysis)
        parsed_nodes = parse_freeze_block_content(content)

        freeze_node_class.new(
          start_line: start_line,
          end_line: end_line,
          content: content,
          start_marker: start_marker[:text],
          end_marker: end_marker[:text],
          nodes: parsed_nodes,
          reason: start_marker[:reason],
        )
      end

      # Returns the FreezeNode class to use.
      #
      # Subclasses should override this to return their own FreezeNode class.
      #
      # @return [Class] FreezeNode class
      def freeze_node_class
        Ast::Merge::FreezeNodeBase
      end

      # Parse content within a freeze block.
      #
      # Subclasses should override this to use their parser.
      #
      # @param content [String] Content to parse
      # @return [Array<Object>] Parsed nodes
      def parse_freeze_block_content(content)
        return [] if content.empty?

        begin
          content_doc = parse_document(content)
          nodes = []
          child = content_doc.first_child
          while child
            nodes << child
            child = next_sibling(child)
          end
          nodes
        rescue StandardError => e
          # simplecov:disable defensive - parser rarely fails on valid markdown subset
          DebugLogger.debug("Failed to parse freeze block content", {error: e.message})
          []
          # simplecov:enable
        end
      end

      # Integrate nodes with freeze blocks
      # @param freeze_blocks [Array<FreezeNode>] Freeze blocks
      # @param base_nodes [Array<Object>, nil] Base nodes (defaults to collect_top_level_nodes_with_gaps)
      # @return [Array<Object>] Integrated list
      def integrate_nodes_with_freeze_blocks(freeze_blocks, base_nodes = nil)
        result = []
        freeze_index = 0
        current_freeze = freeze_blocks[freeze_index]

        top_level_nodes = base_nodes || collect_top_level_nodes_with_gaps

        top_level_nodes.each do |node|
          node_start = node.source_position&.dig(:start_line) || 0
          node_end = node.source_position&.dig(:end_line) || node_start

          # Add any freeze blocks that come before this node
          while current_freeze && current_freeze.start_line < node_start
            result << current_freeze
            freeze_index += 1
            current_freeze = freeze_blocks[freeze_index]
          end

          # Skip nodes that are inside a freeze block
          inside_freeze = freeze_blocks.any? do |fb|
            node_start >= fb.start_line && node_end <= fb.end_line
          end

          result << node unless inside_freeze
        end

        # Add remaining freeze blocks
        while freeze_index < freeze_blocks.size
          result << freeze_blocks[freeze_index]
          freeze_index += 1
        end

        result
      end
    end
  end
end
