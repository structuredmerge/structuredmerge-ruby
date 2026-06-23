# frozen_string_literal: true

module Dotenv
  module Merge
    # File analysis for dotenv files.
    # Parses dotenv source and extracts environment variable assignments,
    # comments, and freeze blocks.
    #
    # Dotenv files follow a simple format:
    # - `KEY=value` - Environment variable assignment
    # - `export KEY=value` - Assignment with export prefix
    # - `# comment` - Comment line
    # - Blank lines are preserved
    #
    # @example Basic usage
    #   analysis = FileAnalysis.new(dotenv_source)
    #   analysis.statements.each do |stmt|
    #     puts stmt.class
    #   end
    #
    # @example With custom freeze token
    #   analysis = FileAnalysis.new(source, freeze_token: "my-merge")
    #   # Looks for: # my-merge:freeze / # my-merge:unfreeze
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      # Default freeze token for identifying freeze blocks
      # @return [String]
      DEFAULT_FREEZE_TOKEN = 'dotenv-merge'

      # @return [CommentTracker] Comment tracker for this file
      attr_reader :comment_tracker

      # Initialize file analysis with dotenv parser
      #
      # @param source [String] Dotenv source code to analyze
      # @param freeze_token [String] Token for freeze block markers (default: "dotenv-merge")
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param options [Hash] Additional options (forward compatibility - ignored by FileAnalysis)
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil, **_options)
        @source = source
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        # **options captures any additional parameters (e.g., node_typing) for forward compatibility

        # Parse all lines
        @lines = parse_lines(source)

        # Initialize comment tracking before freeze block integration
        @comment_tracker = CommentTracker.new(@lines)

        # Extract and integrate freeze blocks
        @statements = extract_and_integrate_statements

        DebugLogger.debug('FileAnalysis initialized', {
                            signature_generator: signature_generator ? 'custom' : 'default',
                            lines_count: @lines.size,
                            statements_count: @statements.size,
                            freeze_blocks: freeze_blocks.size,
                            assignments: assignment_lines.size
                          })
      end

      # Check if parse was successful (dotenv always succeeds, may have invalid lines)
      # @return [Boolean]
      def valid?
        true
      end

      # Get shared comment capability information for this analysis.
      #
      # @return [Ast::Merge::Comment::Capability]
      def comment_capability
        @comment_capability ||= comment_tracker.augment(owners: []).capability
      end

      # Describe how dotenv merges currently own and emit comments.
      #
      # Dotenv comment handling is source-augmented and emitted through the
      # synthetic merge layer.
      #
      # @return [Ast::Merge::Comment::SupportStyle]
      def comment_support_style
        @comment_support_style ||= shared_comment_support_style(
          source: :dotenv_source,
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

      # Build a passive shared comment attachment for an owner.
      #
      # @param owner [Object] Structural owner for the attachment
      # @param options [Hash] Additional metadata / lookup overrides
      # @return [Ast::Merge::Comment::Attachment]
      def comment_attachment_for(owner, **options)
        shared_comment_attachment_for(
          owner,
          tracker_attachment: comment_augmenter(**options).attachment_for(owner),
          **options
        )
      end

      # @return [Symbol]
      def comment_attachment_strategy
        :tracker_layout_merge
      end

      def ruleset_owner_selector
        :assignment_lines_plus_freeze_blocks
      end

      def ruleset_match_key
        :env_key
      end

      def ruleset_render_family
        :dotenv_assignments
      end

      # Get assignment lines (not in freeze blocks)
      # @return [Array<EnvLine>]
      def assignment_lines
        @statements.select { |stmt| stmt.is_a?(EnvLine) && stmt.assignment? }
      end

      # Get merge-relevant structural owners in source order.
      # For dotenv this means assignment lines plus integrated freeze blocks,
      # excluding standalone comments, blanks, and invalid lines.
      #
      # @return [Array<EnvLine, FreezeNode>]
      def structural_owners
        @structural_owners ||= @statements.select do |stmt|
          stmt.is_a?(FreezeNode) || (stmt.is_a?(EnvLine) && stmt.assignment?)
        end
      end

      # Get all assignment lines including those in freeze blocks
      # @return [Array<EnvLine>]
      def all_assignments
        @lines.select(&:assignment?)
      end

      # Get a specific line (1-indexed)
      # Override base to return EnvLine objects instead of raw strings
      # @param line_number [Integer] Line number (1-indexed)
      # @return [EnvLine, nil] The line object
      def line_at(line_number)
        return if line_number < 1

        @lines[line_number - 1]
      end

      # Compute default signature for a node
      # @param node [EnvLine, FreezeNode] The statement
      # @return [Array, nil] Signature array
      def compute_node_signature(node)
        case node
        when FreezeNode
          node.signature
        when EnvLine
          node.signature
        end
      end

      # NOTE: fallthrough_node? is inherited from FileAnalyzable.
      # EnvLine inherits from AstNode and FreezeNode inherits from FreezeNodeBase,
      # both of which are recognized by the base implementation.

      # Get environment variable by key
      # @param key [String] The environment variable key
      # @return [EnvLine, nil] The assignment line or nil
      def env_var(key)
        @lines.find { |line| line.assignment? && line.key == key }
      end

      # Get all environment variable keys
      # @return [Array<String>] List of keys
      def keys
        all_assignments.map(&:key)
      end

      private

      def comment_augmenter_default_owners
        structural_owners
      end

      # Parse source into EnvLine objects
      # @param source [String] Source content
      # @return [Array<EnvLine>]
      def parse_lines(source)
        source.lines.each_with_index.map do |line, index|
          EnvLine.new(line.chomp, index + 1)
        end
      end

      # Extract statements, integrating freeze blocks
      # @return [Array<EnvLine, FreezeNode>]
      def extract_and_integrate_statements
        freeze_markers = find_freeze_markers
        return @lines.dup if freeze_markers.empty?

        # Build freeze blocks from markers
        freeze_blocks = build_freeze_blocks(freeze_markers)

        # Integrate: replace lines in freeze blocks with FreezeNode
        integrate_freeze_blocks(freeze_blocks)
      end

      # Find all freeze markers in the source
      # @return [Array<Hash>] Array of marker info hashes
      def find_freeze_markers
        markers = []
        pattern = Ast::Merge::FreezeNodeBase.pattern_for(:hash_comment, @freeze_token)

        @lines.each do |line|
          next unless line.comment?

          next unless line.raw =~ pattern

          marker_type = ::Regexp.last_match(1) # 'freeze' or 'unfreeze'
          reason = ::Regexp.last_match(2)&.strip
          reason = nil if reason&.empty?

          markers << {
            type: marker_type.to_sym,
            line: line.line_number,
            reason: reason
          }
        end

        markers
      end

      # Build FreezeNode objects from markers
      # @param markers [Array<Hash>] Freeze markers
      # @return [Array<FreezeNode>]
      def build_freeze_blocks(markers)
        blocks = []
        open_marker = nil

        markers.each do |marker|
          case marker[:type]
          when :freeze
            if open_marker
              DebugLogger.warning("Nested freeze block at line #{marker[:line]}, ignoring")
            else
              open_marker = marker
            end
          when :unfreeze
            if open_marker
              blocks << FreezeNode.new(
                start_line: open_marker[:line],
                end_line: marker[:line],
                analysis: self,
                reason: open_marker[:reason]
              )
              open_marker = nil
            else
              DebugLogger.warning("Unfreeze without freeze at line #{marker[:line]}, ignoring")
            end
          end
        end

        DebugLogger.warning("Unclosed freeze block starting at line #{open_marker[:line]}") if open_marker

        blocks
      end

      # Integrate freeze blocks into statement list
      # @param freeze_blocks [Array<FreezeNode>]
      # @return [Array<EnvLine, FreezeNode>]
      def integrate_freeze_blocks(freeze_blocks)
        return @lines.dup if freeze_blocks.empty?

        # Build a set of line numbers covered by freeze blocks
        frozen_lines = Set.new
        freeze_blocks.each do |block|
          (block.start_line..block.end_line).each { |ln| frozen_lines << ln }
        end

        result = []
        freeze_block_starts = freeze_blocks.map(&:start_line).to_set

        @lines.each do |line|
          if frozen_lines.include?(line.line_number)
            # If this is the start of a freeze block, add the FreezeNode
            if freeze_block_starts.include?(line.line_number)
              block = freeze_blocks.find { |b| b.start_line == line.line_number }
              result << block if block
            end
            # Skip individual lines in freeze blocks
          else
            result << line
          end
        end

        result
      end
    end
  end
end
