# frozen_string_literal: true

module Json
  module Merge
    # High-level merger for JSON / JSONC content.
    #
    # @example Basic usage
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #   File.write("merged.json", result.output)
    #
    # @example With options
    #   merger = SmartMerger.new(template, dest,
    #     preference: :template,
    #     add_template_only_nodes: true)
    #   result = merger.merge
    #
    # @example Enable fuzzy matching
    #   merger = SmartMerger.new(template, dest, match_refiner: ObjectMatchRefiner.new)
    #
    # @example With regions (embedded content)
    #   merger = SmartMerger.new(template, dest,
    #     regions: [{ detector: SomeDetector.new, merger_class: SomeMerger }])
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      include ::Ast::Merge::Runtime::RootSessionSupport

      attr_reader :runtime_session, :corruption_handling

      # Creates a new SmartMerger
      #
      # @param template_content [String] Template JSON content
      # @param dest_content [String] Destination JSON content
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param preference [Symbol, Hash] :destination, :template, or per-type Hash
      # @param add_template_only_nodes [Boolean] Whether to add nodes only found in template
      # @param remove_template_missing_nodes [Boolean] Whether to remove nodes missing from template
      # @param freeze_token [String, nil] Token for freeze block markers
      # @param match_refiner [#call, nil] Match refiner for fuzzy matching
      # @param regions [Array<Hash>, nil] Region configurations for nested merging
      # @param region_placeholder [String, nil] Custom placeholder for regions
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences
      # @param options [Hash] Additional options for forward compatibility
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
        merge_arrays: true,
        preserve_atomic_formatting: false,
        **options
      )
        @remove_template_missing_nodes = remove_template_missing_nodes
        @corruption_handling = ::Ast::Merge::Healer.normalize_mode(corruption_handling)
        @merge_arrays = merge_arrays
        @preserve_atomic_formatting = preserve_atomic_formatting

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
          merge_arrays: merge_arrays,
          preserve_atomic_formatting: preserve_atomic_formatting,
          **options
        )
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
      # @return [MergeResult] The merge result containing merged JSON content and metadata
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
          nodes: @template_analysis.nodes.size,
          freeze_blocks: @template_analysis.freeze_blocks.size
        }
        dest_analysis_debug = {
          valid: @dest_analysis.valid?,
          nodes: @dest_analysis.nodes.size,
          freeze_blocks: @dest_analysis.freeze_blocks.size
        }

        {
          content: result_obj.to_json,
          debug: {
            template_nodes: template_analysis_debug[:nodes],
            dest_nodes: dest_analysis_debug[:nodes],
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            corruption_handling: @corruption_handling,
            freeze_token: @freeze_token,
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

      # @return [Class] The analysis class for JSON files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token (not used for JSON)
      def default_freeze_token
        'json-merge'
      end

      # @return [Class] The resolver class for JSON files
      def resolver_class
        ConflictResolver
      end

      # @return [Class] The result class for JSON files
      def result_class
        MergeResult
      end

      # Perform the JSON-specific merge
      #
      # @return [MergeResult] The merge result
      def perform_merge
        @resolver.resolve(@result)

        DebugLogger.debug('Merge complete', {
                            lines: @result.line_count,
                            decisions: @result.statistics
                          })

        @result
      end

      # Build the resolver with JSON-specific signature
      def build_resolver
        ConflictResolver.new(
          @template_analysis,
          @dest_analysis,
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          remove_template_missing_nodes: @remove_template_missing_nodes,
          resolution_mode: @resolution_mode,
          corruption_handling: @corruption_handling,
          match_refiner: @match_refiner,
          node_typing: @node_typing,
          merge_arrays: @merge_arrays,
          preserve_atomic_formatting: @preserve_atomic_formatting
        )
      end

      # Build the result (no-arg constructor for JSON)
      def build_result
        MergeResult.new
      end

      # @return [Class] The template parse error class for JSON
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for JSON
      def destination_parse_error_class
        DestinationParseError
      end

      private

      def start_runtime_session!
        start_runtime_root_session!(
          surface_kind: :json_document,
          declared_language: :json,
          effective_language: :json,
          operation_id: 'json-document-root',
          delegate_name: 'json-runtime',
          policy_context: {
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            resolution_mode: @resolution_mode,
            unresolved_policy: @unresolved_policy.to_h
          },
          metadata: { merger: self.class.name },
          options: {
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            resolution_mode: @resolution_mode,
            unresolved_policy: @unresolved_policy.to_h
          },
          language_chain: [:json],
          delegate_metadata: { merger: self.class.name }
        )
      end

      def complete_runtime_session!(root_operation, merge_result)
        complete_runtime_root_session!(
          root_operation: root_operation,
          replacement_text: merge_result.to_json,
          unresolved_cases: merge_result.unresolved_cases,
          metadata: {
            stats: merge_result.statistics,
            decisions: merge_result.decision_summary
          }
        )
      end

      def fail_runtime_session!(root_operation, error)
        fail_runtime_root_session!(
          root_operation: root_operation,
          error: error,
          kind: :merge_failed
        )
      end
    end
  end
end
