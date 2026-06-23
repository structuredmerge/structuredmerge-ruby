# frozen_string_literal: true

module Toml
  module Merge
    # High-level merger for TOML content.
    # Orchestrates parsing, analysis, and conflict resolution.
    #
    # Extends SmartMergerBase with backend-agnostic parsing via tree_haver.
    # Supports both tree-sitter and Citrus/toml-rb backends (auto-selected by TreeHaver).
    #
    # @example Basic usage
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #   File.write("merged.toml", result.output)
    #
    # @example Force Citrus backend via environment
    #   # Set TREE_HAVER_BACKEND=citrus before requiring toml/merge
    #   merger = SmartMerger.new(template, dest)
    #   result = merger.merge
    #
    # @example Force Citrus backend via TreeHaver
    #   TreeHaver.with_backend(:citrus) do
    #     merger = SmartMerger.new(template, dest)
    #     result = merger.merge
    #   end
    #
    # @example With options
    #   merger = SmartMerger.new(template, dest,
    #     preference: :template,
    #     add_template_only_nodes: true)
    #   result = merger.merge
    #
    # @example Enable fuzzy matching
    #   merger = SmartMerger.new(template, dest, match_refiner: TableMatchRefiner.new)
    #
    # @example With regions (embedded content)
    #   merger = SmartMerger.new(template, dest,
    #     regions: [{ detector: SomeDetector.new, merger_class: SomeMerger }])
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      include ::Ast::Merge::Runtime::RootSessionSupport

      attr_reader :runtime_session, :corruption_handling

      # @return [Symbol] The AST format being used (:tree_sitter or :citrus)
      attr_reader :backend

      # @return [Boolean] Whether destination-only nodes should be removed while
      #   promoting their attached comments
      attr_reader :remove_template_missing_nodes

      # Creates a new SmartMerger
      #
      # @param template_content [String] Template TOML content
      # @param dest_content [String] Destination TOML content
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param preference [Symbol, Hash] :destination, :template, or per-type Hash
      # @param add_template_only_nodes [Boolean] Whether to add nodes only found in template
      # @param freeze_token [String, nil] Token for freeze block markers
      # @param match_refiner [#call, nil] Match refiner for fuzzy matching
      # @param remove_template_missing_nodes [Boolean] Whether to remove destination-only
      #   nodes while preserving their attached comments
      # @param regions [Array<Hash>, nil] Region configurations for nested merging
      # @param region_placeholder [String, nil] Custom placeholder for regions
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences
      # @param sort_keys [Boolean] Whether to alphabetically sort key=value pairs
      #   within gap-separated blocks after merging
      # @param options [Hash] Additional options for forward compatibility
      #
      # @note To force a specific backend, use TreeHaver.with_backend or TREE_HAVER_BACKEND env var.
      #   TreeHaver handles backend selection, auto-detection, and fallback.
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        remove_template_missing_nodes: false,
        corruption_handling: :heal,
        freeze_token: nil,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        node_typing: nil,
        sort_keys: false,
        **options
      )
        @remove_template_missing_nodes = remove_template_missing_nodes
        @corruption_handling = ::Ast::Merge::Healer.normalize_mode(corruption_handling)
        @sort_keys = sort_keys

        super(
          template_content,
          dest_content,
          signature_generator: signature_generator,
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

        # Capture the resolved backend from template analysis (for NodeTypeNormalizer)
        @backend = @template_analysis.backend
      end

      # Backward-compatible options hash
      #
      # @return [Hash] The merge options
      def options
        {
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          remove_template_missing_nodes: @remove_template_missing_nodes,
          resolution_mode: @resolution_mode,
          unresolved_policy: @unresolved_policy.to_h,
          corruption_handling: @corruption_handling,
          match_refiner: @match_refiner
        }
      end

      # Perform the merge operation and return the full MergeResult object.
      #
      # @return [MergeResult] The merge result containing merged TOML content and metadata
      def merge_result
        return @merge_result if @merge_result

        root_operation = start_runtime_session!
        @merge_result = super
        complete_runtime_session!(root_operation, @merge_result)
        @merge_result
      rescue StandardError => e
        fail_runtime_session!(root_operation, e)
        raise
      end

      # Perform the merge and return detailed runtime-aware debug information.
      #
      # @return [Hash] Hash containing :content, :debug, :runtime, :statistics, and :decisions
      def merge_with_debug
        result_obj = merge_result
        template_analysis_debug = {
          valid: @template_analysis.valid?,
          statements: @template_analysis.statements.size
        }
        dest_analysis_debug = {
          valid: @dest_analysis.valid?,
          statements: @dest_analysis.statements.size
        }

        {
          content: result_obj.to_toml,
          debug: {
            template_statements: template_analysis_debug[:statements],
            dest_statements: dest_analysis_debug[:statements],
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            resolution_mode: @resolution_mode,
            corruption_handling: @corruption_handling,
            freeze_token: @freeze_token,
            sort_keys: @sort_keys,
            backend: @backend,
            runtime_operation_count: runtime_session&.operations&.size || 0,
            runtime_diagnostic_count: runtime_session&.diagnostics&.size || 0
          },
          runtime: runtime_session&.to_h,
          statistics: result_obj.statistics,
          decisions: result_obj.decision_summary,
          template_analysis: template_analysis_debug,
          dest_analysis: dest_analysis_debug
        }
      end

      protected

      # @return [Class] The analysis class for TOML files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token (not used for TOML)
      def default_freeze_token
        'toml-merge'
      end

      # @return [Class] The resolver class for TOML files
      def resolver_class
        ConflictResolver
      end

      # @return [Class] The result class for TOML files
      def result_class
        MergeResult
      end

      # Perform the TOML-specific merge
      #
      # @return [MergeResult] The merge result
      def perform_merge
        @resolver.resolve(@result)

        KeySorter.new(@result.lines_array).sort! if @sort_keys

        DebugLogger.debug('Merge complete', {
                            lines: @result.line_count,
                            decisions: @result.statistics
                          })

        @result
      end

      # Build the resolver with TOML-specific signature
      def build_resolver
        ConflictResolver.new(
          @template_analysis,
          @dest_analysis,
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          remove_template_missing_nodes: @remove_template_missing_nodes,
          resolution_mode: @resolution_mode,
          corruption_handling: @corruption_handling,
          match_refiner: @match_refiner
        )
      end

      # Build the result (no-arg constructor for TOML)
      def build_result
        MergeResult.new
      end

      # @return [Class] The template parse error class for TOML
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for TOML
      def destination_parse_error_class
        DestinationParseError
      end

      private

      def start_runtime_session!
        start_runtime_root_session!(
          surface_kind: :toml_document,
          declared_language: :toml,
          effective_language: :toml,
          operation_id: 'toml-document-root',
          delegate_name: 'toml-runtime',
          policy_context: {
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            sort_keys: @sort_keys,
            resolution_mode: @resolution_mode,
            unresolved_policy: @unresolved_policy.to_h
          },
          metadata: { merger: self.class.name, backend: @backend },
          options: {
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            sort_keys: @sort_keys,
            resolution_mode: @resolution_mode,
            unresolved_policy: @unresolved_policy.to_h
          },
          language_chain: [:toml],
          delegate_metadata: { merger: self.class.name, backend: @backend }
        )
      end

      def complete_runtime_session!(root_operation, merge_result)
        complete_runtime_root_session!(
          root_operation: root_operation,
          replacement_text: merge_result.to_toml,
          unresolved_cases: merge_result.unresolved_cases,
          metadata: {
            stats: merge_result.statistics,
            decisions: merge_result.decision_summary,
            backend: @backend
          }
        )
      end

      def fail_runtime_session!(root_operation, error)
        fail_runtime_root_session!(
          root_operation: root_operation,
          error: error,
          kind: :merge_failed,
          metadata: { backend: @backend }
        )
      end

      # TOML FileAnalysis accepts signature_generator
      def build_full_analysis_options
        {
          signature_generator: @signature_generator
        }
      end
    end
  end
end
