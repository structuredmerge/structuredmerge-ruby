# frozen_string_literal: true

module Bash
  module Merge
    # Analyzes Bash script structure, extracting nodes, comments, and freeze blocks.
    # This is the main analysis class that prepares Bash content for merging.
    #
    # @example Basic usage
    #   analysis = FileAnalysis.new(bash_source)
    #   analysis.valid? # => true
    #   analysis.nodes # => [NodeWrapper, FreezeNodeBase, ...]
    #   analysis.freeze_blocks # => [FreezeNodeBase, ...]
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      # Default freeze token for identifying freeze blocks
      DEFAULT_FREEZE_TOKEN = 'bash-merge'

      # @return [CommentTracker] Comment tracker for this file
      attr_reader :comment_tracker

      # @return [TreeHaver::Tree, nil] Parsed AST
      attr_reader :ast

      # @return [Array] Parse errors if any
      attr_reader :errors

      class << self
        # Find the parser library path using TreeHaver::GrammarFinder
        #
        # @return [String, nil] Path to the parser library or nil if not found
        # @raise [TreeHaver::NotAvailable] if ENV is set to invalid path
        def find_parser_path
          TreeHaver::GrammarFinder.new(:bash).find_library_path
        end
      end

      # Initialize file analysis
      #
      # @param source [String] Bash source code to analyze
      # @param freeze_token [String] Token for freeze block markers
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param parser_path [String, nil] Path to tree-sitter-bash parser library
      # @param options [Hash] Additional options (forward compatibility - ignored by FileAnalysis)
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil, parser_path: nil, **_options)
        @source = source
        @lines = source.lines.map(&:chomp)
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @parser_path = parser_path || self.class.find_parser_path
        @errors = []
        # **options captures any additional parameters (e.g., node_typing) for forward compatibility

        # Initialize comment tracking
        @comment_tracker = CommentTracker.new(source)

        # Parse the Bash script
        DebugLogger.time('FileAnalysis#parse_bash') { parse_bash }

        # Extract freeze blocks and integrate with nodes
        @freeze_blocks = extract_freeze_blocks
        @nodes = integrate_nodes_and_freeze_blocks

        DebugLogger.debug('FileAnalysis initialized', {
                            signature_generator: signature_generator ? 'custom' : 'default',
                            nodes_count: @nodes.size,
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

      # Describe how Bash merges currently own and emit comments.
      #
      # Bash comment handling is fully source-augmented and emitted through the
      # synthetic merge layer.
      #
      # @return [Ast::Merge::Comment::SupportStyle]
      def comment_support_style
        @comment_support_style ||= shared_comment_support_style(
          source: :bash_source,
          style: :hash_comment,
          read_strategy: :source_augmented_portable_write
        )
      end

      # Get all tracked comments converted to shared Ast::Merge comment nodes.
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

      # Build a passive shared comment attachment for an owner.
      #
      # @param owner [Object] Structural owner for the attachment
      # @param options [Hash] Additional metadata / lookup overrides
      # @return [Ast::Merge::Comment::Attachment]
      def comment_attachment_for(owner, **options)
        shared_comment_attachment_for(
          owner,
          tracker_attachment: comment_tracker.comment_attachment_for(owner, **options),
          **options
        )
      end

      # @return [Symbol]
      def comment_attachment_strategy
        :augmenter_preferred_tracker_layout
      end

      def ruleset_owner_selector
        :line_bound_statements
      end

      def ruleset_render_family
        :bash_script_statements
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

      # The base module uses 'statements' - provide both names for compatibility
      # @return [Array<NodeWrapper, FreezeNodeBase>]
      def statements
        @nodes ||= []
      end

      # Alias for convenience - bash-merge prefers "nodes" terminology
      alias nodes statements

      # Check if a line is within a freeze block.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Boolean]
      def in_freeze_block?(line_num)
        @freeze_blocks.any? { |fb| fb.location.cover?(line_num) }
      end

      # Get the freeze block containing the given line.
      #
      # @param line_num [Integer] 1-based line number
      # @return [FreezeNode, nil]
      def freeze_block_at(line_num)
        @freeze_blocks.find { |fb| fb.location.cover?(line_num) }
      end

      # Override to detect tree-sitter nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.is_a?(NodeWrapper) || value.is_a?(FreezeNode) || super
      end

      # Get the root node of the parse tree
      # @return [NodeWrapper, nil]
      def root_node
        return unless valid?

        NodeWrapper.new(@ast.root_node, lines: @lines, source: @source)
      end

      # Get top-level statements from the script
      # @return [Array<NodeWrapper>]
      def top_level_statements
        return [] unless valid?

        @top_level_statements ||= begin
          root = @ast.root_node
          if root
            statements = []
            root.each do |child|
              next if child.type.to_s == 'comment' # Comments handled separately

              statements << NodeWrapper.new(child, lines: @lines, source: @source)
            end
            statements
          else
            []
          end
        end
      end

      private

      def parse_bash
        # TreeHaver handles backend selection against the grammars Bash::Merge
        # has already registered during bootstrap.
        # Set TREE_HAVER_BACKEND=ffi for bash (MRI/Rust have compatibility issues)
        parser = TreeHaver.parser_for(:bash, library_path: @parser_path)
        @ast = parser.parse(@source)

        # Check for parse errors in the tree
        collect_parse_errors(@ast.root_node) if @ast&.root_node&.has_error?
      rescue TreeHaver::Error => e
        # TreeHaver::Error inherits from Exception, not StandardError.
        # This also catches TreeHaver::NotAvailable (subclass of Error).
        @errors << e.message
        @ast = nil
      rescue StandardError => e
        @errors << e.message
        @ast = nil
      end

      def collect_parse_errors(node)
        # Collect ERROR and MISSING nodes from the tree
        if node.type.to_s == 'ERROR' || node.missing?
          @errors << {
            type: node.type.to_s,
            start_point: node.start_point,
            end_point: node.end_point,
            text: node.to_s
          }
        end

        node.each { |child| collect_parse_errors(child) }
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

        blocks
      end

      def integrate_nodes_and_freeze_blocks
        return @freeze_blocks.dup unless valid?

        result = []
        processed_lines = ::Set.new

        # Mark freeze block lines as processed
        @freeze_blocks.each do |fb|
          (fb.start_line..fb.end_line).each { |ln| processed_lines << ln }
          result << fb
        end

        # Add top-level statements that aren't in freeze blocks
        top_level_statements.each do |stmt|
          next unless stmt.start_line && stmt.end_line

          # Skip if any part of this statement is in a freeze block
          stmt_lines = (stmt.start_line..stmt.end_line).to_a
          next if stmt_lines.any? { |ln| processed_lines.include?(ln) }

          result << stmt
        end

        # Sort by start line
        result.sort_by { |node| node.start_line || 0 }
      end

      def compute_node_signature(node)
        case node
        when FreezeNode
          node.signature
        when NodeWrapper
          node.signature
        end
      end
    end
  end
end
