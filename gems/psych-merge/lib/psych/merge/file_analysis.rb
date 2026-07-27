# frozen_string_literal: true

module Psych
  module Merge
    # Analyzes YAML file structure, extracting statements, comments, and freeze blocks.
    # This is the main analysis class that prepares YAML content for merging.
    #
    # @example Basic usage
    #   analysis = FileAnalysis.new(yaml_source)
    #   analysis.valid? # => true
    #   analysis.statements # => [NodeWrapper, FreezeNodeBase, ...]
    #   analysis.freeze_blocks # => [FreezeNodeBase, ...]
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      # Default freeze token for identifying freeze blocks
      DEFAULT_FREEZE_TOKEN = 'psych-merge'

      # @return [CommentTracker] Comment tracker for this file
      attr_reader :comment_tracker

      # @return [Psych::Nodes::Stream, nil] Parsed AST
      attr_reader :ast

      # @return [TreeHaver::Backends::Psych::Tree, nil] TreeHaver tree (for future use)
      attr_reader :tree

      # @return [Array] Parse errors if any
      attr_reader :errors

      # Initialize file analysis
      #
      # @param source [String] YAML source code to analyze
      # @param freeze_token [String] Token for freeze block markers
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param options [Hash] Additional options (forward compatibility - ignored by FileAnalysis)
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil, **_options)
        @source = source
        @lines = source.lines.map(&:chomp)
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @errors = []
        # **options captures any additional parameters (e.g., node_typing) for forward compatibility

        # Initialize comment tracking
        @comment_tracker = CommentTracker.new(source)

        # Parse the YAML
        DebugLogger.time('FileAnalysis#parse_yaml') { parse_yaml }

        # Extract freeze blocks and integrate with nodes
        @freeze_blocks = extract_freeze_blocks
        @statements = integrate_nodes_and_freeze_blocks

        DebugLogger.debug('FileAnalysis initialized', {
                            signature_generator: signature_generator ? 'custom' : 'default',
                            statements_count: @statements.size,
                            freeze_blocks: @freeze_blocks.size,
                            valid: valid?
                          })
      end

      # Check if parse was successful
      # @return [Boolean]
      def valid?
        @errors.empty? && !@ast.nil?
      end

      # Get shared comment capability information for this analysis.
      #
      # @return [Ast::Merge::Comment::Capability]
      def comment_capability
        @comment_capability ||= comment_tracker.augment(owners: []).capability
      end

      # Describe how Psych merges currently own and emit comments.
      #
      # YAML comment handling is source-augmented and emitted through the
      # synthetic merge layer rather than native AST mutation.
      #
      # @return [Ast::Merge::Comment::SupportStyle]
      def comment_support_style
        @comment_support_style ||= shared_comment_support_style(
          source: :psych_source,
          style: :hash_comment,
          read_strategy: :source_augmented_portable_write
        )
      end

      # Get all comments converted to shared Ast::Merge comment nodes.
      #
      # @return [Array<Ast::Merge::Comment::Line>]
      def comment_nodes
        comment_tracker.comment_nodes
      end

      # Get a shared Ast::Merge comment node at a specific line.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Ast::Merge::Comment::Line, nil]
      def comment_node_at(line_num)
        comment_tracker.comment_node_at(line_num)
      end

      # Get comments in a line range converted to a shared comment region.
      #
      # @param range [Range] Range of 1-based line numbers
      # @param kind [Symbol] Region kind (:leading, :inline, :orphan, etc.)
      # @param full_line_only [Boolean] Whether to keep only full-line comments
      # @return [Ast::Merge::Comment::Region]
      def comment_region_for_range(range, kind:, full_line_only: false)
        comment_tracker.comment_region_for_range(
          range,
          kind: kind,
          full_line_only: full_line_only
        )
      end

      # Build a passive shared comment augmenter for this analysis.
      #
      # @param owners [Array<#start_line,#end_line>, nil] Owners used for attachment inference
      # @param options [Hash] Additional augmenter options
      # @return [Ast::Merge::Comment::Augmenter]
      def comment_augmenter(owners: nil, **options)
        comment_tracker.augment(
          owners: owners || comment_augmenter_default_owners,
          **options
        )
      end

      # Check if a line is within a freeze block.
      #
      # NOTE: This method intentionally does NOT call `super` or use the base
      # `freeze_blocks` method. The base implementation derives freeze blocks from
      # `statements.select { |n| n.is_a?(Freezable) }`, but during initialization
      # `@freeze_blocks` is extracted BEFORE `@statements` is populated (see
      # `integrate_nodes_and_freeze_blocks`). This method is called during that
      # integration process, so we must use `@freeze_blocks` directly.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Boolean]
      def in_freeze_block?(line_num)
        @freeze_blocks.any? { |fb| fb.location.cover?(line_num) }
      end

      # Get the freeze block containing the given line.
      #
      # NOTE: This method intentionally does NOT call `super` or use the base
      # `freeze_blocks` method. The base implementation derives freeze blocks from
      # `statements.select { |n| n.is_a?(Freezable) }`, but during initialization
      # `@freeze_blocks` is extracted BEFORE `@statements` is populated (see
      # `integrate_nodes_and_freeze_blocks`). This method is called during that
      # integration process, so we must use `@freeze_blocks` directly.
      #
      # @param line_num [Integer] 1-based line number
      # @return [FreezeNode, nil]
      def freeze_block_at(line_num)
        @freeze_blocks.find { |fb| fb.location.cover?(line_num) }
      end

      # Override to detect Psych nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.is_a?(NodeWrapper) || value.is_a?(Ast::Merge::FreezeNodeBase) || value.is_a?(MappingEntry) || super
      end

      # Get mapping entries from the root document
      # @return [Array<Array(NodeWrapper, NodeWrapper)>]
      def root_mapping_entries
        return [] unless valid? && @ast.children&.any?

        doc = @ast.children.first
        return [] unless doc.is_a?(::Psych::Nodes::Document)

        root = doc.children&.first
        return [] unless root.is_a?(::Psych::Nodes::Mapping)

        root_wrapper = wrap_root_node(root)
        root_wrapper.mapping_entries(comment_tracker: @comment_tracker)
      end

      # Get the root node of the first document
      # @return [NodeWrapper, nil]
      def root_node
        return unless valid? && @ast.children&.any?

        doc = @ast.children.first
        return unless doc.is_a?(::Psych::Nodes::Document)

        root = doc.children&.first
        return unless root

        wrap_root_node(root)
      end

      # Build a passive shared comment attachment for an owner.
      #
      # @param owner [Object] Structural owner for the attachment
      # @param line_num [Integer, nil] Optional line number override
      # @param options [Hash] Additional attachment metadata
      # @return [Ast::Merge::Comment::Attachment]
      def comment_attachment_for(owner, line_num: nil, **options)
        base_attachment = if owner.is_a?(MappingEntry) && options.empty?
                            mapping_entry_attachment(owner)
                          else
                            @comment_tracker.comment_attachment_for(owner, line_num: line_num, **options)
                          end

        shared_comment_attachment_for(
          owner,
          tracker_attachment: base_attachment,
          line_num: line_num,
          **options
        )
      end

      # @return [Symbol]
      def comment_attachment_strategy
        :tracker_layout_merge
      end

      def ruleset_owner_selector
        :mapping_entries
      end

      def ruleset_match_key
        :key_name
      end

      def ruleset_render_family
        :key_value_colon
      end

      private

      def mapping_entry_attachment(owner)
        augmenter_attachment = comment_augmenter(owners: [owner]).attachment_for(owner)
        comment_blocks = full_line_comment_blocks_before(owner.key.start_line || 1)
        leading_comments = comment_blocks.last || []
        floating_leading = leading_comments.any? && gap_before_comment_block?(leading_comments,
                                                                              owner.key.start_line || 1)

        Ast::Merge::Comment::Attachment.new(
          owner: owner,
          leading_region: build_comment_region(:leading, leading_comments, floating: floating_leading),
          inline_region: build_comment_region(:inline, [inline_comment_node_at(owner.key.start_line || 1)].compact),
          trailing_region: augmenter_attachment&.trailing_region,
          orphan_regions: comment_blocks[0...-1].map { |block| build_comment_region(:orphan, block) }.compact,
          metadata: { key_name: owner.key_name }
        )
      end

      def build_comment_region(kind, comments, floating: false)
        return if comments.empty?

        Ast::Merge::Comment::Region.new(kind: kind, nodes: comments, metadata: { floating: floating })
      end

      def inline_comment_node_at(line_num)
        raw_line = @lines[line_num - 1].to_s
        return if raw_line.strip.start_with?('#')

        @comment_tracker.comment_node_at(line_num)
      end

      def full_line_comment_blocks_before(line_num)
        blocks = []
        current_block = []
        current_line = line_num - 1

        while current_line.positive?
          raw_line = @lines[current_line - 1]
          stripped = raw_line.to_s.strip
          if stripped.empty?
            unless current_block.empty?
              blocks.unshift(current_block.reverse)
              current_block = []
            end
            current_line -= 1
            next
          end

          break unless stripped.start_with?('#')

          comment = @comment_tracker.comment_node_at(current_line)
          break unless comment

          current_block << comment
          current_line -= 1
        end

        blocks.unshift(current_block.reverse) unless current_block.empty?
        blocks
      end

      def gap_before_comment_block?(comments, line_num)
        return false if comments.empty?

        last_comment_line = comments.last.line_number
        ((last_comment_line + 1)...line_num).any? { |current_line| @lines[current_line - 1].to_s.strip.empty? }
      end

      def wrap_root_node(root)
        line_num = (root.start_line + 1 if root.respond_to?(:start_line) && root.start_line)

        NodeWrapper.new(
          root,
          lines: @lines,
          leading_comments: line_num ? @comment_tracker.leading_comments_before(line_num) : [],
          inline_comment: line_num ? @comment_tracker.inline_comment_at(line_num) : nil,
          comment_tracker: @comment_tracker
        )
      end

      def parse_yaml
        # Route through the Psych backend that Psych::Merge registers with
        # TreeHaver during bootstrap.
        @tree = TreeHaver.with_backend(Psych::Merge::BACKEND_REFERENCE.id) do
          TreeHaver.parser_for(:yaml, backend_type: :psych).parse(@source)
        end
        @ast = @tree.root_node.inner_node
      rescue ::Psych::SyntaxError => e
        @errors << e
        @ast = nil
        @tree = nil
        # Re-raise to allow SmartMergerBase to wrap with appropriate error type
        raise
      end

      def extract_freeze_blocks
        # Use shared pattern from Ast::Merge::FreezeNodeBase with our specific token
        freeze_pattern = Ast::Merge::FreezeNodeBase.pattern_for(:hash_comment, @freeze_token)

        freeze_starts = []
        freeze_ends = []

        @lines.each_with_index do |line, idx|
          line_num = idx + 1
          next unless (match = line.match(freeze_pattern))

          marker_type = match[1]&.downcase # 'freeze' or 'unfreeze'
          if marker_type == 'freeze'
            freeze_starts << { line: line_num, marker: line }
          elsif marker_type == 'unfreeze'
            freeze_ends << { line: line_num, marker: line }
          end
        end

        # Match freeze starts with ends
        blocks = []
        freeze_starts.each do |start_info|
          # Find the next unfreeze after this freeze
          matching_end = freeze_ends.find { |e| e[:line] > start_info[:line] }
          next unless matching_end

          # Remove used end marker
          freeze_ends.delete(matching_end)

          blocks << FreezeNode.new(
            start_line: start_info[:line],
            end_line: matching_end[:line],
            lines: @lines,
            start_marker: start_info[:marker],
            end_marker: matching_end[:marker]
          )
        end

        blocks.sort_by(&:start_line)
      end

      def integrate_nodes_and_freeze_blocks
        return @freeze_blocks unless valid? && @ast.children&.any?

        all_nodes = []
        doc = @ast.children.first
        return @freeze_blocks unless doc.is_a?(::Psych::Nodes::Document)

        root = doc.children&.first
        return @freeze_blocks unless root

        # For mappings, extract key-value pairs as individual nodes
        if root.is_a?(::Psych::Nodes::Mapping)
          root_wrapper = wrap_root_node(root)
          entries = root_wrapper.mapping_entries(comment_tracker: @comment_tracker)

          entries.each do |key_wrapper, value_wrapper|
            key_line = key_wrapper.start_line || 1

            # Check if this entry is inside a freeze block
            if in_freeze_block?(key_line)
              # Entry is in freeze block, will be handled by freeze block
              next
            end

            # Check if there's a freeze block that should come before this entry
            @freeze_blocks.each do |fb|
              all_nodes << fb if fb.start_line < key_line && !all_nodes.include?(fb)
            end

            # Add the key-value pair as a mapping entry
            all_nodes << MappingEntry.new(
              key: key_wrapper,
              value: value_wrapper,
              lines: @lines,
              comment_tracker: @comment_tracker
            )
          end
        else
          # For sequences or scalars at root, wrap the whole thing
          all_nodes << wrap_root_node(root)
        end

        # Add any remaining freeze blocks at the end (common to both branches)
        @freeze_blocks.each do |fb|
          all_nodes << fb unless all_nodes.include?(fb)
        end

        all_nodes.sort_by { |n| n.start_line || 0 }
      end

      def compute_node_signature(node)
        case node
        when FreezeNode
          node.signature
        when MappingEntry
          [:mapping_entry, node.key_name]
        when NodeWrapper
          node.signature
        end
      end
    end

    # Represents a key-value entry in a YAML mapping
    class MappingEntry
      # @return [NodeWrapper] The key node
      attr_reader :key

      # @return [NodeWrapper] The value node
      attr_reader :value

      # @return [Array<String>] Source lines
      attr_reader :lines

      # @return [CommentTracker] Comment tracker
      attr_reader :comment_tracker

      # @param key [NodeWrapper] Key wrapper
      # @param value [NodeWrapper] Value wrapper
      # @param lines [Array<String>] Source lines
      # @param comment_tracker [CommentTracker] Comment tracker
      def initialize(key:, value:, lines:, comment_tracker:)
        @key = key
        @value = value
        @lines = lines
        @comment_tracker = comment_tracker
      end

      # Get a passive shared comment attachment for this mapping entry.
      #
      # @return [Ast::Merge::Comment::Attachment]
      def comment_attachment
        @comment_attachment ||= @comment_tracker.comment_attachment_for(
          self,
          line_num: @key.start_line,
          leading_comments: @comment_tracker.leading_comments_before(@key.start_line || 1),
          inline_comment: @comment_tracker.inline_comment_at(@key.start_line || 1),
          key_name: key_name
        )
      end

      # @return [Ast::Merge::Comment::Region, nil]
      def leading_comment_region
        comment_attachment.leading_region
      end

      # @return [Ast::Merge::Comment::Region, nil]
      def inline_comment_region
        comment_attachment.inline_region
      end

      # Get the key name as a string
      # @return [String, nil]
      def key_name
        @key.value
      end

      # Get the start line (from the key)
      # @return [Integer, nil]
      def start_line
        leading_comment_region&.start_line || @key.start_line
      end

      # Get the end line (from the value)
      # @return [Integer, nil]
      def end_line
        @value.end_line || @key.end_line
      end

      # Get the line range
      # @return [Range, nil]
      def line_range
        return unless start_line && end_line

        start_line..end_line
      end

      # Get the content for this entry
      # @return [String]
      def content
        return '' unless start_line && end_line

        (start_line..end_line).map { |ln| @lines[ln - 1] }.compact.join("\n")
      end

      # Generate signature for this entry
      # @return [Array]
      def signature
        [:mapping_entry, key_name]
      end

      # Location-like object for compatibility
      def location
        @location ||= FreezeNode::Location.new(start_line, end_line)
      end

      # Check if this is a freeze node
      # @return [Boolean]
      def freeze_node?
        false
      end

      # Check if this is a mapping
      # @return [Boolean]
      def mapping?
        @value.mapping?
      end

      # Check if this is a sequence
      # @return [Boolean]
      def sequence?
        @value.sequence?
      end

      # Check if this is a scalar
      # @return [Boolean]
      def scalar?
        @value.scalar?
      end

      # Get the anchor if present
      # @return [String, nil]
      def anchor
        @value.anchor
      end

      # String representation
      # @return [String]
      def inspect
        "#<#{self.class.name} key=#{key_name.inspect} lines=#{start_line}..#{end_line}>"
      end
    end
  end
end
