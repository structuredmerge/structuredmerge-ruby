# frozen_string_literal: true

module Prism
  module Merge
    # A merger that uses section-based semantics with recursive body merging for cleaner merging.
    #
    # SmartMerger:
    # 1. Converts each top-level node into a "section" identified by its signature
    # 2. Uses SectionTyping-style merge logic to decide which sections to include
    # 3. Recursively merges matching class/module/block bodies
    # 4. Outputs each selected node exactly once (with its comments)
    #
    # This approach avoids the complexity of tracking line ranges for anchors
    # and boundaries, which can lead to duplicate content when comments are
    # attached to multiple overlapping ranges.
    #
    # ## Merge Algorithm
    #
    # 1. Parse both template and destination files
    # 2. Generate signatures for all top-level nodes in both files
    # 3. Build a signature -> node map for destination
    # 4. Walk template nodes in order:
    #    - If signature matches a dest node:
    #      - If class/module/block with mergeable body: recursively merge bodies
    #      - Otherwise: output based on preference
    #    - If template-only: output if add_template_only_nodes is true
    # 5. Output any remaining dest-only nodes
    #
    # ## Recursive Body Merging
    #
    # When matching class/module definitions or CallNodes with blocks are found,
    # the merger recursively merges their body contents. This allows template
    # updates to nested methods/constants to be merged with destination customizations.
    #
    # @example Basic merge
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #
    # @example Template wins with additions
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      # @return [Integer, Float] Maximum recursion depth for body merging
      attr_reader :max_recursion_depth

      # @return [Hash, nil] Options to pass to Text::SmartMerger for comment-only files
      attr_reader :text_merger_options

      # @return [Boolean] Whether to remove destination-only nodes that are missing from the template
      attr_reader :remove_template_missing_nodes

      # @return [Symbol] How suspected corruption should be handled (:heal, :warn, :error, :skip)
      attr_reader :corruption_handling

      # @return [Boolean] Whether template-only require calls may be emitted
      attr_reader :merge_template_requires

      # @return [Symbol] Where template-only nodes are emitted
      attr_reader :template_only_placement

      # @return [Ast::Merge::Runtime::Session, nil] Runtime-charter state recorded during merge
      attr_reader :runtime_session

      CORRUPTION_HANDLINGS = ::Ast::Merge::Healer::HANDLINGS

      # Creates a new SmartMerger.
      #
      # @param template_content [String] Template Ruby source code
      # @param dest_content [String] Destination Ruby source code
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param preference [Symbol, Hash] :template, :destination, or per-type Hash
      # @param add_template_only_nodes [Boolean] Whether to add template-only nodes
      # @param remove_template_missing_nodes [Boolean] Whether to remove destination-only nodes
      #   while preserving or promoting their attached comments
      # @param freeze_token [String, nil] Token for freeze block markers
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences
      # @param max_recursion_depth [Integer, Float] Maximum depth for recursive body merging.
      #   Default: Float::INFINITY (no limit). This is a safety valve that users can set
      #   if they encounter edge cases.
      # @param current_depth [Integer] Current recursion depth (internal use)
      # @param match_refiner [#call, nil] Optional match refiner (unused but accepted for API compatibility)
      # @param regions [Array<Hash>, nil] Region configurations (unused but accepted for API compatibility)
      # @param region_placeholder [String, nil] Custom placeholder prefix (unused but accepted for API compatibility)
      # @param text_merger_options [Hash, nil] Options to pass to Text::SmartMerger when
      #   merging comment-only files (files with no Ruby code statements). Supported options:
      #   - :freeze_token - Token for freeze block markers (defaults to @freeze_token or "text-merge")
      #   - Any other options supported by Ast::Merge::Text::SmartMerger
      # @param options [Hash] Additional options for forward compatibility
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        remove_template_missing_nodes: false,
        freeze_token: nil,
        node_typing: nil,
        max_recursion_depth: Float::INFINITY,
        current_depth: 0,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        text_merger_options: nil,
        corruption_handling: :heal,
        merge_template_requires: false,
        template_only_placement: :after_anchor,
        **options
      )
        @max_recursion_depth = max_recursion_depth
        @current_depth = current_depth
        @text_merger_options = text_merger_options
        @remove_template_missing_nodes = remove_template_missing_nodes
        @corruption_handling = normalize_corruption_handling(corruption_handling)
        @merge_template_requires = merge_template_requires
        @template_only_placement = normalize_template_only_placement(template_only_placement)
        @dest_prefix_comment_lines = nil

        # Store the raw (unwrapped) signature_generator so that
        # merge_node_body_recursively can pass it to inner SmartMergers
        # without double-wrapping.
        @raw_signature_generator = signature_generator

        # Wrap signature_generator to include node_typing processing
        effective_signature_generator = build_effective_signature_generator(signature_generator, node_typing)

        super(
          template_content,
          dest_content,
          signature_generator: effective_signature_generator,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          remove_template_missing_nodes: remove_template_missing_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          regions: regions,
          region_placeholder: region_placeholder,
          node_typing: node_typing,
          **options
        )
      end

      def normalize_template_only_placement(value)
        normalized = value.to_s.empty? ? "after_anchor" : value.to_s
        return normalized.to_sym if %w[after_anchor destination_tail].include?(normalized)

        raise ArgumentError, "Unsupported template-only placement #{value.inspect}"
      end

      # Determine whether the given analysis represents a comment-only file.
      #
      # Returns true when every top-level statement is a comment/block/empty
      # node produced by the comment parsers. This is used to decide whether to
      # delegate to the comment-only merger logic.
      #
      # @param analysis [FileAnalysis]
      # @return [Boolean]
      def comment_only_file?(analysis)
        comment_only_file_merger.comment_only_file?(analysis)
      end

      # Perform the merge and return a hash with content, debug info, and statistics.
      #
      # @return [Hash] Hash with :content, :debug, and :statistics keys
      def merge_with_debug
        result_obj = merge_result
        template_analysis_debug = {
          valid: @template_analysis&.valid? || false,
          statements: @template_analysis&.statements&.size || 0,
        }
        dest_analysis_debug = {
          valid: @dest_analysis&.valid? || false,
          statements: @dest_analysis&.statements&.size || 0,
        }
        {
          content: result_obj.to_s,
          debug: {
            template_statements: template_analysis_debug[:statements],
            dest_statements: dest_analysis_debug[:statements],
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            freeze_token: @freeze_token,
            corruption_handling: @corruption_handling,
            runtime_operation_count: runtime_session&.operations&.size || 0,
            runtime_diagnostic_count: runtime_session&.diagnostics&.size || 0,
          },
          runtime: runtime_session&.to_h,
          statistics: result_obj.respond_to?(:statistics) ? result_obj.statistics : result_obj.decision_summary,
          decisions: result_obj.respond_to?(:decision_summary) ? result_obj.decision_summary : result_obj.statistics,
          template_analysis: template_analysis_debug,
          dest_analysis: dest_analysis_debug,
        }
      end

      protected

      # @return [Class] The analysis class for Ruby files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token for Ruby
      def default_freeze_token
        "prism-merge"
      end

      # @return [Class] The result class for Ruby files
      def result_class
        MergeResult
      end

      # @return [Class, nil] No aligner needed for SmartMerger
      def aligner_class
        nil
      end

      # @return [Class, nil] No resolver needed for SmartMerger
      def resolver_class
        nil
      end

      # Build the result with analysis references
      def build_result
        MergeResult.new(
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
        )
      end

      # Override parse_and_analyze to thread per-source gemspec block variable overrides.
      #
      # When a caller passes `template_gemspec_block_var:` or `dest_gemspec_block_var:`
      # in the format_options (captured via `**format_options` in the base class), those
      # overrides are applied to the resulting `FileAnalysis` object after construction.
      # This supports recursive body merges where the `Gem::Specification.new do |X|`
      # wrapper is absent from the extracted body text and auto-detection cannot fire.
      #
      # @param content [String] Source content to parse
      # @param source [Symbol] :template or :destination
      # @return [FileAnalysis]
      def parse_and_analyze(content, source)
        analysis = super
        var_key = (source == :template) ? :template_gemspec_block_var : :dest_gemspec_block_var
        var = @format_options[var_key]
        analysis.gemspec_block_var = var if var && analysis.respond_to?(:gemspec_block_var=)
        analysis
      end

      # @return [Class] The template parse error class for Ruby
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for Ruby
      def destination_parse_error_class
        DestinationParseError
      end

      # Perform the SmartMerger's section-based merge with recursive body merging.
      #
      # The algorithm processes nodes in destination order to preserve user additions
      # in their original positions, while injecting template-only nodes at the beginning.
      #
      # For comment-only files (no Ruby code statements), FileAnalysis parses the content
      # into Comment::Block and Comment::Empty nodes. We detect this case by checking if
      # ALL statements are comment nodes, and delegate to merge_comment_only_files.
      #
      # @return [MergeResult] The merge result
      def perform_merge
        validate_files!
        top_level_merge_runner.merge
      end

      private

      def record_runtime_session(session)
        @runtime_session = session
      end

      def normalize_corruption_handling(value)
        Ast::Merge::Healer.normalize_mode(value)
      end

      def handle_suspected_corruption(kind:, message:)
        Ast::Merge::Healer.handle(
          mode: corruption_handling,
          kind: kind,
          message: message,
          prefix: "[prism-merge]",
          error_class: Prism::Merge::CorruptionDetectedError,
        )
      end

      # Check if a node has a freeze marker in its leading comments.
      #
      # Returns true if a freeze marker (with or without a matching unfreeze) appears
      # anywhere in the node's leading comments, or if the node is already wrapped as
      # a FrozenWrapper. The caller is responsible for deciding whether a balanced
      # freeze/unfreeze pair is a template-originated standalone block (via
      # `preference_for_node`) vs a genuine user customization.
      #
      # @param node [Prism::Node, Ast::Merge::NodeTyping::FrozenWrapper, nil] The node to check
      # @return [Boolean] true if the node has any freeze marker in its leading comments
      def frozen_node?(node)
        return false if node.nil?

        # Already wrapped as frozen (includes Freezable module)
        return true if node.is_a?(Ast::Merge::Freezable)

        return false unless @freeze_token

        # Get the actual node (in case it's a Wrapper)
        actual_node = node.respond_to?(:unwrap) ? node.unwrap : node

        freeze_pattern = /#{Regexp.escape(@freeze_token)}:freeze/i

        if actual_node.respond_to?(:location) && actual_node.location.respond_to?(:leading_comments)
          return actual_node.location.leading_comments.any? { |comment| comment.slice.match?(freeze_pattern) }
        end

        false
      end

      # Check if a node contains freeze blocks within its body/content.
      #
      # This is used to detect if a class, module, block, or other container
      # has freeze markers anywhere inside it (not just as a leading comment).
      #
      # @param node [Prism::Node] The node to check
      # @param analysis [FileAnalysis] The file analysis (for context)
      # @return [Boolean] true if the node contains freeze markers
      def node_contains_freeze_blocks?(node, analysis = nil)
        return false unless @freeze_token

        # Get the actual node (in case it's a Wrapper)
        actual_node = node.respond_to?(:unwrap) ? node.unwrap : node

        freeze_pattern = /#{Regexp.escape(@freeze_token)}:freeze/i

        # Check if node content contains a freeze marker
        if actual_node.respond_to?(:slice)
          return true if actual_node.slice.match?(freeze_pattern)
        end

        false
      end

      def validate_files!
        unless @template_analysis.valid?
          raise TemplateParseError.new(
            "Template file has parsing errors",
            content: @template_content,
            parse_result: @template_analysis.parse_result,
          )
        end

        unless @dest_analysis.valid?
          raise DestinationParseError.new(
            "Destination file has parsing errors",
            content: @dest_content,
            parse_result: @dest_analysis.parse_result,
          )
        end
      end

      # Handle merging of files that contain only comments (no code statements).
      #
      # For comment-only files (like files with just `# frozen_string_literal: true`),
      # there are no Prism AST nodes to match. We use Prism::Merge::Comment::Parser
      # to parse comments into AST nodes, then apply the same two-phase merge algorithm
      # used by perform_merge:
      #
      # Phase 1: Process template comment nodes in order
      #   - Match by signature (normalized content)
      #   - Apply preference for matched pairs
      #   - Add template-only nodes if add_template_only_nodes is true
      #
      # Phase 2: Add dest-only comment nodes
      #   - Preserves user additions (comments not in template)
      #   - Uses index-based tracking to preserve duplicate comments
      #
      # This ensures consistent preference-based behavior across all merge operations.
      # Comment nodes match by their normalized content (signature). When multiple
      # dest nodes have the same signature, only the first matches; the rest are
      # treated as dest-only and preserved in Phase 2.
      #
      # @return [MergeResult] The merge result
      def merge_comment_only_files
        comment_only_file_merger.merge
      end

      # Build a map of signature -> [indices] for comment nodes.
      #
      # @param nodes [Array<Ast::Merge::Comment::*>] Comment nodes
      # @return [Hash{Array => Array<Integer>}] Map of signatures to node indices
      def build_comment_indices_map(nodes)
        comment_only_file_merger.send(:build_comment_indices_map, nodes)
      end

      # Find the first unmatched index for a given signature.
      #
      # @param indices_map [Hash] Map of signature -> [indices]
      # @param signature [Array, nil] The signature to look up
      # @param matched_indices [Set] Already matched indices
      # @return [Integer, nil] First unmatched index or nil
      def find_first_unmatched_index(indices_map, signature, matched_indices)
        comment_only_file_merger.send(:find_first_unmatched_index, indices_map, signature, matched_indices)
      end

      # Add a comment node to the result.
      #
      # @param node [Ast::Merge::Comment::*] The comment node
      # @param source [Symbol] :template or :destination
      def add_comment_node_to_result(node, source)
        comment_only_file_merger.send(:add_comment_node_to_result, node, source)
      end

      def emit_comment_only_prefix_lines(template_lines, dest_lines)
        comment_only_file_merger.send(:emit_comment_only_prefix_lines, template_lines, dest_lines)
      end

      def comment_only_prefix_lines(lines)
        comment_only_file_merger.send(:comment_only_prefix_lines_for, lines)
      end

      def ruby_magic_comment_line?(line)
        !!ruby_magic_comment_line_type(line)
      end

      def ruby_magic_comment_line_type(line)
        comment_only_file_merger.send(:ruby_magic_comment_line_type, line)
      end

      # Build a map of signature -> node for an analysis.
      #
      # @param analysis [FileAnalysis] The file analysis
      # @return [Hash{Array => Prism::Node}] Map of signatures to nodes
      def build_signature_map(analysis)
        map = Hash.new { |h, k| h[k] = [] }
        analysis.statements.each_with_index do |node, idx|
          entry = {node: node, index: idx}

          # BlockDirective nodes (NocovNode, FreezeNode) wrap inner content.
          # For matching, register the directive under each child's signature
          # so that a NocovNode{desc, task} matches template's bare desc or task.
          # The entry still points to the full directive node for emission.
          if node.is_a?(Ast::Merge::BlockDirective) && !node.is_a?(Ast::Merge::FreezeNodeBase)
            children = node.children
            unless children.length == 1
              # Multi-child: register under each child's signature AND
              # the directive's own composite signature (for directive-to-directive matching).
              children.each do |child|
                child_sig = analysis.generate_signature(child)
                map[child_sig] << entry if child_sig
              end
            end
          end
          sig = analysis.generate_signature(node)
          map[sig] << entry if sig
        end
        map
      end

      # Determine preference for a specific node pair.
      #
      # Frozen nodes (those with freeze markers in leading_comments) always
      # prefer the destination version, as they represent user customizations
      # that should be preserved across template updates.
      #
      # However, when BOTH the template and the destination node carry a freeze
      # marker, the freeze block is a template-originated standalone directive
      # (e.g., the instructions block at the top of a Rakefile). In that case the
      # freeze does NOT represent a user customisation and the normal preference
      # logic applies (typically template-wins under :template preference).
      #
      # @param template_node [Prism::Node] Template node
      # @param dest_node [Prism::Node] Destination node
      # @return [Symbol] :template or :destination
      def preference_for_node(template_node, dest_node)
        # BlockDirective nodes (FreezeNode, NocovNode) carry an explicit merge_policy.
        # nil means "follow file preference" (no override).
        if dest_node.is_a?(Ast::Merge::BlockDirective)
          policy = dest_node.merge_policy
          return policy if policy

          # If dest has a BlockDirective (e.g. a user-added NocovNode) but the
          # template counterpart is a plain node (no BlockDirective), preserve the
          # user's directive rather than stripping it.
          return :destination unless template_node.is_a?(Ast::Merge::BlockDirective)
        end

        # Use claimed_lines from the respective FileAnalysis so that freeze markers
        # that were already promoted to BlockDirective nodes (and thus claimed) are
        # not double-counted here.  Without this, a dest node whose leading_comments
        # include a claimed freeze line (hoisted by Prism's attach_comments!) would
        # incorrectly appear "frozen" even after the FreezeNode was extracted.
        dest_claimed = @dest_analysis&.claimed_lines || Set.new
        template_claimed = @template_analysis&.claimed_lines || Set.new
        if @dest_analysis&.frozen_node?(dest_node, claimed_lines: dest_claimed)
          # Only treat as user customisation when the template counterpart does NOT
          # also carry a freeze marker.  If the template also has one, the freeze
          # block is template-originated (standalone instructions block) and we
          # should fall through to normal preference logic.
          unless @template_analysis&.frozen_node?(template_node, claimed_lines: template_claimed)
            return :destination
          end
        end

        return @preference unless @preference.is_a?(Hash)

        # Process nodes through node_typing if configured
        typed_template = @node_typing ? ::Ast::Merge::NodeTyping.process(template_node, @node_typing) : template_node
        typed_dest = @node_typing ? ::Ast::Merge::NodeTyping.process(dest_node, @node_typing) : dest_node

        # Check for merge_type from NodeTyping
        if ::Ast::Merge::NodeTyping.typed_node?(typed_template)
          merge_type = ::Ast::Merge::NodeTyping.merge_type_for(typed_template)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        if ::Ast::Merge::NodeTyping.typed_node?(typed_dest)
          merge_type = ::Ast::Merge::NodeTyping.merge_type_for(typed_dest)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        default_preference
      end

      def default_preference
        if @preference.is_a?(Hash)
          @preference.fetch(:default, :destination)
        else
          @preference
        end
      end

      # Build an effective signature generator that incorporates node_typing.
      #
      # When node_typing is provided, this wraps the signature_generator (or creates one)
      # to process nodes through node_typing first. This allows:
      #
      # - Custom signature_generators to receive typed nodes with merge_type
      # - Default signature generation to work with the underlying node (via unwrap in
      #   FileAnalyzable#generate_signature)
      #
      # The node_typing processing happens here (for signature generation) AND in
      # preference_for_node (for preference determination), so typed nodes are handled
      # consistently in both contexts.
      #
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param node_typing [Hash, nil] Node typing configuration
      # @return [Proc, nil] Combined signature generator, or nil if neither is provided
      def build_effective_signature_generator(signature_generator, node_typing)
        return signature_generator unless node_typing

        ->(node) {
          # First, process through node_typing to potentially add merge_type
          processed_node = ::Ast::Merge::NodeTyping.process(node, node_typing)

          # Then, pass to signature_generator or return processed node for default handling
          # FileAnalyzable#generate_signature will unwrap Wrappers for default signature computation
          if signature_generator
            signature_generator.call(processed_node)
          else
            processed_node
          end
        }
      end

      # Emit destination magic comments and any lines that precede the first
      # AST node's leading comments.
      #
      # Magic comments (frozen_string_literal, encoding, etc.) are file-level
      # metadata managed by Prism. The destination is the real file on disk,
      # so its magic comments must always be preserved — regardless of merge
      # preference. This method:
      #
      # 1. Emits any lines before the first leading comment (shebangs, etc.)
      # 2. Emits magic comments from the first dest node's leading comments
      # 3. Emits blank lines between the last magic comment and the first
      #    non-magic leading comment (or the node itself)
      # 4. Records which dest line numbers were emitted so that
      #    add_node_to_result can skip them (preventing duplication)
      #
      # @param result [MergeResult] The merge result
      # @param analysis [FileAnalysis] The destination file analysis
      # @return [Integer] The last line number emitted (0 if none)
      def emit_dest_prefix_lines(result, analysis)
        node_emission_support.emit_dest_prefix_lines(result: result, analysis: analysis)
      end

      # Check if a Prism comment object is a Ruby magic comment.
      #
      # @param comment [Prism::Comment] A Prism comment object
      # @return [Boolean]
      def prism_magic_comment?(comment)
        node_emission_support.send(:prism_magic_comment?, comment)
      end

      # Emit blank/gap lines from the destination source between the last output line
      # and the next node (including its leading comments). This preserves blank lines
      # that separate top-level blocks.
      #
      # @param result [MergeResult] The merge result
      # @param analysis [FileAnalysis] The destination file analysis
      # @param last_output_line [Integer] The last dest line number that was output
      # @param next_node [Prism::Node] The next node about to be output
      # @return [Integer] The updated last output line number
      def emit_dest_gap_lines(result, analysis, last_output_line, next_node)
        node_emission_support.emit_dest_gap_lines(
          result: result,
          analysis: analysis,
          last_output_line: last_output_line,
          next_node: next_node,
        )
      end

      def add_matched_template_node_to_result(result, template_node, dest_node)
        node_emission_support.emit_matched_template_node(
          result: result,
          template_node: template_node,
          dest_node: dest_node,
        )
      end

      # Add a node to the result, including its leading and trailing comments.
      #
      # @param result [MergeResult] The merge result
      # @param node [Prism::Node] The node to add
      # @param analysis [FileAnalysis] The source analysis
      # @param source [Symbol] :template or :destination
      def add_node_to_result(result, node, analysis, source, matched_template_node: nil)
        node_emission_support.emit_node(
          result: result,
          node: node,
          analysis: analysis,
          source: source,
          matched_template_node: matched_template_node,
        )
      end

      def emit_removed_destination_node_comments(result, node, analysis)
        node_emission_support.emit_removed_destination_node_comments(
          result: result,
          node: node,
          analysis: analysis,
        )
      end

      def filtered_leading_comments_for(node, source)
        wrapper_comment_support.filtered_leading_comments_for(node, source)
      end

      def emit_leading_comments(result, comments, analysis:, source:, decision:, prev_comment_line: nil)
        wrapper_comment_support.emit_leading_comments(
          result,
          comments,
          analysis: analysis,
          source: source,
          decision: decision,
          prev_comment_line: prev_comment_line,
        )
      end

      def emit_blank_lines_between(result, last_comment_line:, next_content_line:, analysis:, source:, decision:)
        wrapper_comment_support.emit_blank_lines_between(
          result,
          last_comment_line: last_comment_line,
          next_content_line: next_content_line,
          analysis: analysis,
          source: source,
          decision: decision,
        )
      end

      def emit_external_trailing_comments(result, comments, source_node:, analysis:, source:, decision:)
        wrapper_comment_support.emit_external_trailing_comments(
          result,
          comments,
          source_node: source_node,
          analysis: analysis,
          source: source,
          decision: decision,
        )
      end

      def append_inline_comment_entries(line, entries)
        wrapper_comment_support.append_inline_comment_entries(line, entries)
      end

      def inline_comment_entries_by_line(entries)
        wrapper_comment_support.inline_comment_entries_by_line(entries)
      end

      def line_inline_comment_entries(analysis, line_num)
        wrapper_comment_support.line_inline_comment_entries(analysis, line_num)
      end

      def begin_node_boundary_lines(node)
        begin_node_structure(node).boundary_lines
      end

      def wrapper_inline_comment_entries_by_line(analysis, node)
        wrapper_comment_support.wrapper_inline_comment_entries_by_line(analysis, node)
      end

      def begin_node_clause_start_line(node)
        begin_node_structure(node).clause_start_line
      end

      def begin_node_rescue_nodes(node)
        begin_node_structure(node).rescue_nodes
      end

      def rescue_node_signature(rescue_node)
        BeginNodeStructure.rescue_signature(rescue_node)
      end

      def rescue_node_reference_name(rescue_node)
        begin_node_rescue_semantics.send(:rescue_node_reference_name, rescue_node)
      end

      def local_variable_read_names_in(node, names = [])
        begin_node_rescue_semantics.send(:local_variable_read_names_in, node, names)
      end

      def local_variable_read_names_in_source(source)
        begin_node_rescue_semantics.send(:local_variable_read_names_in_source, source)
      end

      def local_reference_node_named?(node, name)
        begin_node_rescue_semantics.send(:local_reference_node_named?, node, name)
      end

      def local_reference_offsets_in(node, name, offsets = [])
        begin_node_rescue_semantics.send(:local_reference_offsets_in, node, name, offsets)
      end

      def rewrite_local_reference_in_source(source, from:, to:)
        begin_node_rescue_semantics.send(:rewrite_local_reference_in_source, source, from: from, to: to)
      end

      def normalized_clause_body_and_header_source(template_clause_node, dest_clause_node, clause_body, preferred_source)
        begin_node_rescue_semantics.normalized_clause_body_and_header_source(
          template_clause_node: template_clause_node,
          dest_clause_node: dest_clause_node,
          clause_body: clause_body,
          preferred_source: preferred_source,
        )
      end

      def begin_node_clause_regions(node)
        begin_node_structure(node).clause_regions
      end

      def begin_node_clause_nodes_by_type(node)
        begin_node_structure(node).clause_nodes_by_type
      end

      def begin_node_structure(node)
        BeginNodeStructure.new(node)
      end

      def begin_node_merge_planner(template_node:, dest_node:, node_preference:)
        BeginNodeMergePlanner.new(
          merger: self,
          template_node: template_node,
          dest_node: dest_node,
          node_preference: node_preference,
        )
      end

      def begin_node_plan_emitter
        @begin_node_plan_emitter ||= BeginNodePlanEmitter.new(merger: self)
      end

      def begin_node_clause_body_support
        @begin_node_clause_body_support ||= BeginNodeClauseBodySupport.new(
          merger: self,
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
          freeze_token: @freeze_token,
          raw_signature_generator: @raw_signature_generator,
          node_typing: @node_typing,
        )
      end

      def recursive_node_body_merger
        @recursive_node_body_merger ||= RecursiveNodeBodyMerger.new(merger: self)
      end

      def begin_node_clause_body_merger
        @begin_node_clause_body_merger ||= BeginNodeClauseBodyMerger.new(merger: self)
      end

      def begin_node_clause_header_emitter
        @begin_node_clause_header_emitter ||= BeginNodeClauseHeaderEmitter.new(merger: self)
      end

      def wrapper_comment_support
        @wrapper_comment_support ||= WrapperCommentSupport.new(merger: self)
      end

      def comment_only_file_merger
        @comment_only_file_merger ||= CommentOnlyFileMerger.new(merger: self)
      end

      def node_emission_support
        @node_emission_support ||= NodeEmissionSupport.new(merger: self)
      end

      def node_body_layout_for(node, analysis)
        NodeBodyLayout.new(node: node, analysis: analysis, merger: self)
      end

      def recursive_merge_policy
        @recursive_merge_policy ||= RecursiveMergePolicy.new(merger: self)
      end

      def top_level_merge_runner
        @top_level_merge_runner ||= TopLevelMergeRunner.new(merger: self)
      end

      def clause_statements_node(node)
        begin_node_clause_body_support.clause_statements_node(node)
      end

      def clause_header_end_line(node, region)
        begin_node_clause_body_support.clause_header_end_line(node, region)
      end

      def clause_body_start_line(node, region)
        begin_node_clause_body_support.clause_body_start_line(node, region)
      end

      def extract_region_body(region, analysis, body_start_line: region[:start_line] + 1, body_end_line: region[:end_line])
        begin_node_clause_body_support.extract_region_body(
          region,
          analysis,
          body_start_line: body_start_line,
          body_end_line: body_end_line,
        )
      end

      def emit_clause_header_lines(
        template_clause_node,
        template_region,
        dest_clause_node,
        dest_region,
        header_source,
        decision,
        template_inline_by_line,
        dest_inline_by_line
      )
        begin_node_clause_header_emitter.emit(
          template_clause_node: template_clause_node,
          template_region: template_region,
          dest_clause_node: dest_clause_node,
          dest_region: dest_region,
          header_source: header_source,
          decision: decision,
          template_inline_by_line: template_inline_by_line,
          dest_inline_by_line: dest_inline_by_line,
        )
      end

      def split_leading_comment_prefix(body_text)
        begin_node_clause_body_support.split_leading_comment_prefix(body_text)
      end

      def body_contains_freeze_markers?(body_text)
        begin_node_clause_body_support.body_contains_freeze_markers?(body_text)
      end

      def clause_body_components(node, region, analysis)
        begin_node_clause_body_support.clause_body_components(node, region, analysis)
      end

      def statement_signatures_for_nodes(nodes, analysis)
        begin_node_clause_body_support.statement_signatures_for_nodes(nodes, analysis)
      end

      def begin_node_statement_signatures(node, analysis)
        begin_node_clause_body_support.begin_node_statement_signatures(node, analysis)
      end

      def clause_body_fully_duplicated_in_preferred_begin?(clause_node, clause_analysis, preferred_begin_node, preferred_begin_analysis)
        begin_node_clause_body_support.clause_body_fully_duplicated_in_preferred_begin?(
          clause_node,
          clause_analysis,
          preferred_begin_node,
          preferred_begin_analysis,
        )
      end

      def merge_clause_body_recursively(template_clause_node, template_clause_region, dest_clause_node, dest_clause_region)
        begin_node_clause_body_merger.merge(
          template_clause_node: template_clause_node,
          template_clause_region: template_clause_region,
          dest_clause_node: dest_clause_node,
          dest_clause_region: dest_clause_region,
        )
      end

      def clause_bodies_have_matching_statements?(template_body, dest_body)
        begin_node_clause_body_support.clause_bodies_have_matching_statements?(template_body, dest_body)
      end

      def merge_ordered_clause_types(primary_types, secondary_types)
        begin_node_rescue_semantics.merge_ordered_clause_types(primary_types, secondary_types)
      end

      def rescue_clause_type?(clause_type)
        begin_node_rescue_semantics.send(:rescue_clause_type?, clause_type)
      end

      def broad_rescue_clause_type?(clause_type)
        begin_node_rescue_semantics.send(:broad_rescue_clause_type?, clause_type)
      end

      def clause_kind_sort_key(clause_type)
        begin_node_rescue_semantics.send(:clause_kind_sort_key, clause_type)
      end

      def normalize_exception_name(exception_name)
        begin_node_rescue_semantics.send(:normalize_exception_name, exception_name)
      end

      def qualify_source_constant_name(constant_name, namespace = nil)
        begin_node_rescue_semantics.send(:qualify_source_constant_name, constant_name, namespace)
      end

      def source_defined_exception_hierarchy
        begin_node_rescue_semantics.send(:source_defined_exception_hierarchy)
      end

      def collect_source_defined_exception_definitions(node, namespace, definitions)
        begin_node_rescue_semantics.send(:collect_source_defined_exception_definitions, node, namespace, definitions)
      end

      def resolve_exception_constant(exception_name)
        begin_node_rescue_semantics.send(:resolve_exception_constant, exception_name)
      end

      def rescue_clause_exception_constants(clause_type)
        begin_node_rescue_semantics.send(:rescue_clause_exception_constants, clause_type)
      end

      def rescue_clause_exception_names(clause_type)
        begin_node_rescue_semantics.send(:rescue_clause_exception_names, clause_type)
      end

      def exception_constant_covers?(covering_constant, covered_constant)
        begin_node_rescue_semantics.send(:exception_constant_covers?, covering_constant, covered_constant)
      end

      def source_defined_exception_covers?(covering_name, covered_name)
        begin_node_rescue_semantics.send(:source_defined_exception_covers?, covering_name, covered_name)
      end

      def exception_name_covers?(covering_name, covered_name)
        begin_node_rescue_semantics.send(:exception_name_covers?, covering_name, covered_name)
      end

      def rescue_clause_covers?(covering_clause_type, covered_clause_type)
        begin_node_rescue_semantics.send(:rescue_clause_covers?, covering_clause_type, covered_clause_type)
      end

      def broader_rescue_clause_type_than?(left_clause_type, right_clause_type)
        begin_node_rescue_semantics.send(:broader_rescue_clause_type_than?, left_clause_type, right_clause_type)
      end

      def canonicalize_rescue_clause_order(clause_types)
        begin_node_rescue_semantics.canonicalize_rescue_clause_order(clause_types)
      end

      def canonicalize_begin_clause_kind_order(clause_types)
        begin_node_rescue_semantics.canonicalize_begin_clause_kind_order(clause_types)
      end

      def begin_node_rescue_semantics
        @begin_node_rescue_semantics ||= BeginNodeRescueSemantics.new(
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
        )
      end

      def begin_node_has_clause_or_body?(node)
        begin_node_structure(node).has_clause_or_body?
      end

      def begin_node_clause_line_map(template_node, dest_node)
        begin_node_structure(template_node).line_map_for(begin_node_structure(dest_node))
      end

      def external_trailing_comments_for(node)
        wrapper_comment_support.external_trailing_comments_for(node)
      end

      # Determines if two matching nodes should be recursively merged.
      #
      # Recursive merge is performed for matching class/module definitions and
      # CallNodes with blocks to intelligently combine their body contents
      # (nested methods, constants, etc.). This allows template updates to
      # internals to be merged with destination customizations.
      #
      # @param template_node [Prism::Node, nil] Node from template file
      # @param dest_node [Prism::Node, nil] Node from destination file
      # @return [Boolean] true if nodes should be recursively merged
      #
      # @note Recursive merge is NOT performed for:
      #   - Conditional nodes (if/unless) - treated as atomic units
      #   - Nodes of different types
      #   - Blocks whose body contains only literals/expressions with no mergeable statements
      #   - When max_recursion_depth has been reached (safety valve)
      def should_merge_recursively?(template_node, dest_node)
        recursive_merge_policy.should_merge?(template_node: template_node, dest_node: dest_node)
      end

      # Check if a body (StatementsNode) contains statements that could be merged.
      #
      # Mergeable statements are those that can generate signatures and be
      # independently matched between template and destination. This includes
      # method definitions, class/module definitions, method calls, assignments, etc.
      #
      # Bodies containing only literals (strings, numbers, arrays, hashes) or
      # simple expressions should not be recursively merged as there's nothing
      # to align - they should be treated atomically.
      #
      # @param body [Prism::StatementsNode, nil] The body to check
      # @return [Boolean] true if the body contains mergeable statements
      # @api private
      def body_has_mergeable_statements?(body)
        recursive_merge_policy.body_has_mergeable_statements?(body)
      end

      # Check if a statement is mergeable (can generate a signature).
      #
      # @param node [Prism::Node] The node to check
      # @return [Boolean] true if this node type can be merged
      # @api private
      def mergeable_statement?(node)
        recursive_merge_policy.mergeable_statement?(node)
      end

      # Recursively merges the body of matching class, module, or call-with-block nodes.
      #
      # This method extracts the body content (everything between the opening
      # declaration and the closing 'end'), creates a new nested SmartMerger to merge
      # those bodies, and then reassembles the complete node with the merged body.
      #
      # @param template_node [Prism::Node] Node from template
      # @param dest_node [Prism::Node] Node from destination
      #
      # @note The nested merger is configured with:
      #   - Same signature_generator, preference, add_template_only_nodes, and freeze_token
      #   - Incremented current_depth to track recursion level
      #
      # @api private
      def merge_node_body_recursively(template_node, dest_node)
        recursive_node_body_merger.merge(template_node: template_node, dest_node: dest_node)
      end

      # Extracts the body content of a node (without declaration and closing 'end').
      #
      # @param node [Prism::Node] The node to extract body from
      # @param analysis [FileAnalysis] The file analysis containing the node
      # @return [String] The extracted body content
      #
      # @api private
      def extract_node_body(node, analysis)
        node_body_layout_for(node, analysis).body_text
      end
    end
  end
end
