# frozen_string_literal: true

module Markdown
  module Merge
    # Orchestrates the smart merge process for Markdown files using tree_haver backends.
    #
    # Extends SmartMergerBase with backend-agnostic parsing via tree_haver.
    # Supports both Commonmarker and Markly backends.
    #
    # Uses FileAnalysis, FileAligner, ConflictResolver, and MergeResult to
    # merge two Markdown files intelligently. Freeze blocks marked with
    # HTML comments are preserved exactly as-is.
    #
    # SmartMerger provides flexible configuration for different merge scenarios:
    # - Preserve destination customizations (default)
    # - Apply template updates
    # - Add new sections from template
    # - Inner-merge fenced code blocks using language-specific mergers (optional)
    #
    # @example Basic merge (destination customizations preserved)
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #   if result.success?
    #     File.write("output.md", result.content)
    #   end
    #
    # @example With specific backend
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     backend: :markly
    #   )
    #   result = merger.merge
    #
    # @example Template updates win
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    # @example Custom signature matching
    #   sig_gen = ->(node) {
    #     canonical_type = Ast::Merge::NodeTyping.merge_type_for(node) || node.type
    #     if canonical_type == :heading
    #       [:heading, node.header_level]  # Match by level only, not content
    #     else
    #       node  # Fall through to default
    #     end
    #   }
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_generator: sig_gen
    #   )
    #
    # @see FileAnalysis
    # @see SmartMergerBase
    class SmartMerger < SmartMergerBase
      VALID_BACKENDS = %i[auto commonmarker markly].freeze

      class << self
        def default_backend
          :auto
        end

        def default_freeze_token
          FileAnalysis::DEFAULT_FREEZE_TOKEN
        end

        def default_inner_merge_code_blocks
          false
        end

        def default_parser_options
          {}
        end

        def file_analysis_class
          FileAnalysis
        end

        def template_parse_error_class
          TemplateParseError
        end

        def destination_parse_error_class
          DestinationParseError
        end
      end

      # @return [Symbol] The backend being used (:commonmarker, :markly)
      attr_reader :backend

      # Creates a new SmartMerger for intelligent Markdown file merging.
      #
      # @param template_content [String] Template Markdown source code
      # @param dest_content [String] Destination Markdown source code
      #
      # @param backend [Symbol] Backend to use for parsing:
      #   - `:commonmarker` - Use Commonmarker (comrak Rust parser)
      #   - `:markly` - Use Markly (cmark-gfm C library)
      #   - `:auto` (default) - Auto-detect available backend
      #
      # @param signature_generator [Proc, nil] Optional proc to generate custom node signatures.
      #   The proc receives a node (wrapped with canonical merge_type) and should return one of:
      #   - An array representing the node's signature
      #   - `nil` to indicate the node should have no signature
      #   - The original node to fall through to default signature computation
      #
      # @param preference [Symbol] Controls which version to use when nodes
      #   have matching signatures but different content:
      #   - `:destination` (default) - Use destination version (preserves customizations)
      #   - `:template` - Use template version (applies updates)
      #
      # @param add_template_only_nodes [Boolean] Controls whether to add nodes that only
      #   exist in template:
      #   - `false` (default) - Skip template-only nodes
      #   - `true` - Add template-only nodes to result
      #
      # @param inner_merge_code_blocks [Boolean, CodeBlockMerger] Controls inner-merge for
      #   fenced code blocks:
      #   - `true` - Enable inner-merge using default CodeBlockMerger
      #   - `false` (default) - Disable inner-merge (use standard conflict resolution)
      #   - `CodeBlockMerger` instance - Use custom CodeBlockMerger
      #
      # @param remove_template_missing_nodes [Boolean] Controls whether destination-only
      #   structural nodes should be removed instead of preserved. Standalone HTML
      #   comment-only fragments, freeze blocks, and link reference definitions remain
      #   preserved when enabled.
      #
      # @param freeze_token [String] Token to use for freeze block markers.
      #   Default: "markdown-merge"
      #   Looks for: <!-- markdown-merge:freeze --> / <!-- markdown-merge:unfreeze -->
      #
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching of
      #   unmatched nodes. Default: nil (fuzzy matching disabled).
      #   Set to TableMatchRefiner.new to enable fuzzy table matching.
      #
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences. Maps node type names to callables.
      #
      # @param parser_options [Hash] Backend-specific parser options.
      #   For commonmarker: { options: {} }
      #   For markly: { flags: Markly::DEFAULT, extensions: [:table] }
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      def initialize(
        template_content,
        dest_content,
        backend: self.class.default_backend,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        inner_merge_code_blocks: self.class.default_inner_merge_code_blocks,
        inner_merge_lists: false,
        remove_template_missing_nodes: false,
        freeze_token: self.class.default_freeze_token,
        match_refiner: nil,
        node_typing: nil,
        **parser_options
      )
        validate_backend!(backend)

        @requested_backend = backend
        @parser_options = self.class.default_parser_options.merge(parser_options)

        super(
          template_content,
          dest_content,
          signature_generator: signature_generator,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          inner_merge_code_blocks: inner_merge_code_blocks,
          inner_merge_lists: inner_merge_lists,
          remove_template_missing_nodes: remove_template_missing_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          node_typing: node_typing,
          # Pass through for FileAnalysis
          backend: backend,
          **parser_options,
        )

        # Capture the resolved backend from template analysis
        @backend = @template_analysis.backend
      end

      # Create a FileAnalysis instance for parsing.
      #
      # @param content [String] Markdown content to analyze
      # @param options [Hash] Analysis options
      # @return [FileAnalysis] File analysis instance
      def create_file_analysis(content, **opts)
        self.class.file_analysis_class.new(
          content,
          backend: opts[:backend] || @requested_backend,
          freeze_token: opts[:freeze_token],
          signature_generator: opts[:signature_generator],
          **@parser_options
        )
      end

      # Returns the TemplateParseError class to use.
      #
      # @return [Class] Markdown::Merge::TemplateParseError
      def template_parse_error_class
        self.class.template_parse_error_class
      end

      # Returns the DestinationParseError class to use.
      #
      # @return [Class] Markdown::Merge::DestinationParseError
      def destination_parse_error_class
        self.class.destination_parse_error_class
      end

      # Convert a node to its source text.
      #
      # Handles wrapped nodes from NodeTypeNormalizer, gap line nodes,
      # and link definition nodes created during gap detection.
      #
      # @param node [Object] Node to convert (may be wrapped)
      # @param analysis [FileAnalysis] Analysis for source lookup
      # @return [String] Source text
      def node_to_source(node, analysis)
        # Check for any FreezeNode type (base class or subclass)
        return node.full_text if node.is_a?(Ast::Merge::FreezeNodeBase)

        # Handle gap line nodes (created for blank lines and link definitions)
        return node.content if node.is_a?(LinkDefinitionNode) || node.is_a?(GapLineNode)

        # Unwrap if needed to access source_position
        raw_node = Ast::Merge::NodeTyping.unwrap(node)

        pos = raw_node.source_position
        start_line = pos&.dig(:start_line)
        end_line = pos&.dig(:end_line)

        # Fall back to to_commonmark if no position info
        return raw_node.to_commonmark unless start_line && end_line

        # Get source from line range
        source = analysis.source_range(start_line, end_line)

        # Handle Markly's buggy position reporting for :html nodes
        # where end_line < start_line results in empty source_range.
        # Fall back to to_commonmark in that case.
        if source.empty? && raw_node.respond_to?(:to_commonmark)
          raw_node.to_commonmark.chomp
        else
          source
        end
      end

      private

      def validate_backend!(backend)
        normalized_backend = backend.respond_to?(:to_sym) ? backend.to_sym : backend
        return if VALID_BACKENDS.include?(normalized_backend)

        raise ArgumentError, "Unknown backend: #{backend}"
      end
    end
  end
end
