# frozen_string_literal: true

module Markdown
  module Merge
    # Base class for smart Markdown file merging.
    #
    # Orchestrates the smart merge process for Markdown files using
    # FileAnalysisBase, FileAligner, ConflictResolver, and MergeResult to
    # merge two Markdown files intelligently. Freeze blocks marked with
    # HTML comments are preserved exactly as-is.
    #
    # Subclasses must implement:
    # - #create_file_analysis(content, **options) - Create parser-specific FileAnalysis
    # - #node_to_source(node, analysis) - Convert a node to source text
    #
    # SmartMergerBase provides flexible configuration for different merge scenarios:
    # - Preserve destination customizations (default)
    # - Apply template updates
    # - Add new sections from template
    # - Inner-merge fenced code blocks using language-specific mergers (optional)
    #
    # @example Subclass implementation
    #   class SmartMerger < Markdown::Merge::SmartMergerBase
    #     def create_file_analysis(content, **options)
    #       FileAnalysis.new(content, **options)
    #     end
    #
    #     def node_to_source(node, analysis)
    #       case node
    #       when FreezeNode
    #         node.full_text
    #       else
    #         analysis.source_range(node.start_line, node.end_line)
    #       end
    #     end
    #   end
    #
    # @abstract Subclass and implement parser-specific methods
    # @see FileAnalysisBase
    # @see FileAligner
    # @see ConflictResolver
    # @see MergeResult
    class SmartMergerBase
      include PreservationSupport

      # @return [FileAnalysisBase] Analysis of the template file
      attr_reader :template_analysis

      # @return [FileAnalysisBase] Analysis of the destination file
      attr_reader :dest_analysis

      # @return [FileAligner] Aligner for finding matches and differences
      attr_reader :aligner

      # @return [ConflictResolver] Resolver for handling conflicting content
      attr_reader :resolver

      # @return [CodeBlockMerger, nil] Merger for fenced code blocks
      attr_reader :code_block_merger

      # @return [Hash{Symbol,String => #call}, nil] Node typing configuration
      attr_reader :node_typing

      # @return [Ast::Merge::Runtime::Session, nil] Runtime session for this merge
      attr_reader :runtime_session
      attr_reader :corruption_handling, :resolution_mode, :unresolved_policy

      # Creates a new SmartMerger for intelligent Markdown file merging.
      #
      # @param template_content [String] Template Markdown source code
      # @param dest_content [String] Destination Markdown source code
      #
      # @param signature_generator [Proc, nil] Optional proc to generate custom node signatures.
      #   The proc receives a node and should return one of:
      #   - An array representing the node's signature
      #   - `nil` to indicate the node should have no signature
      #   - The original node to fall through to default signature computation
      #
      # @param preference [Symbol, Hash] Controls which version to use when nodes
      #   have matching signatures but different content:
      #   - `:destination` (default) - Use destination version (preserves customizations)
      #   - `:template` - Use template version (applies updates)
      #   - Hash for per-type preferences: `{ default: :destination, gem_table: :template }`
      #
      # @param add_template_only_nodes [Boolean, #call] Controls whether to add nodes that only
      #   exist in template:
      #   - `false` (default) - Skip template-only nodes
      #   - `true` - Add all template-only nodes to result
      #   - Callable (Proc/Lambda) - Called with (node, entry) for each template-only node.
      #     Return truthy to add the node, falsey to skip it.
      #     @example Filter to only add gem family link refs
      #       add_template_only_nodes: ->(node, entry) {
      #         sig = entry[:signature]
      #         sig.is_a?(Array) && sig.first == :gem_family
      #       }
      #
      # @param inner_merge_code_blocks [Boolean, CodeBlockMerger] Controls inner-merge for
      #   fenced code blocks:
      #   - `true` - Enable inner-merge using default CodeBlockMerger
      #   - `false` (default) - Disable inner-merge (use standard conflict resolution)
      #   - `CodeBlockMerger` instance - Use custom CodeBlockMerger
      #
      # @param remove_template_missing_nodes [Boolean] Controls whether to remove nodes that only
      #   exist in destination when not present in template:
      #   - `false` (default) - Preserve destination-only nodes
      #   - `true` - Remove destination-only structural nodes while still preserving
      #     freeze blocks, standalone HTML comment-only fragments, and parser-consumed
      #     non-structural content such as link reference definitions
      #
      # @param freeze_token [String] Token to use for freeze block markers.
      #   Default: "markdown-merge"
      #
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching of
      #   unmatched nodes. Default: nil (fuzzy matching disabled).
      #   Set to TableMatchRefiner.new to enable fuzzy table matching.
      #
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences. Maps node type names to callables that
      #   can wrap nodes with custom merge_types for use with Hash-based preference.
      #   @example
      #     node_typing = {
      #       table: ->(node) {
      #         text = node.to_plaintext
      #         if text.include?("tree_haver")
      #           Ast::Merge::NodeTyping.with_merge_type(node, :gem_family_table)
      #         else
      #           node
      #         end
      #       }
      #     }
      #     merger = SmartMerger.new(template, dest,
      #       node_typing: node_typing,
      #       preference: { default: :destination, gem_family_table: :template })
      #
      # @param normalize_whitespace [Boolean, Symbol] Whitespace normalization mode:
      #   - `false` (default) - No normalization
      #   - `true` or `:basic` - Collapse excessive blank lines (3+ → 2)
      #   - `:link_refs` - Basic + remove blank lines between consecutive link reference definitions
      #   - `:strict` - All normalizations (same as :link_refs currently)
      #
      # @param rehydrate_link_references [Boolean] If true, convert inline links/images
      #   to reference-style when a matching link reference definition exists. Default: false
      #
      # @param parser_options [Hash] Additional parser-specific options
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        inner_merge_code_blocks: false,
        inner_merge_lists: false,
        remove_template_missing_nodes: false,
        corruption_handling: :heal,
        freeze_token: FileAnalysisBase::DEFAULT_FREEZE_TOKEN,
        match_refiner: nil,
        node_typing: nil,
        resolution_mode: :eager,
        unresolved_policy: nil,
        normalize_whitespace: false,
        rehydrate_link_references: false,
        **parser_options
      )
        @preference = preference
        @add_template_only_nodes = add_template_only_nodes
        @remove_template_missing_nodes = remove_template_missing_nodes
        @corruption_handling = ::Ast::Merge::Healer.normalize_mode(corruption_handling)
        @match_refiner = match_refiner || default_match_refiner(
          inner_merge_lists: inner_merge_lists,
          inner_merge_code_blocks: inner_merge_code_blocks
        )
        @node_typing = node_typing
        @resolution_mode = resolution_mode
        @unresolved_policy = Ast::Merge::UnresolvedPolicy.coerce(unresolved_policy)
        @normalize_whitespace = normalize_whitespace
        @rehydrate_link_references = rehydrate_link_references

        # Validate node_typing if provided
        Ast::Merge::NodeTyping.validate!(node_typing) if node_typing
        validate_resolution_mode!(resolution_mode)

        # Set up code block merger
        @code_block_merger = case inner_merge_code_blocks
                             when true
                               CodeBlockMerger.new
                             when false
                               nil
                             when CodeBlockMerger
                               inner_merge_code_blocks
                             else
                               raise ArgumentError,
                                     'inner_merge_code_blocks must be true, false, or a CodeBlockMerger instance'
                             end

        # Set up list merger
        @list_merger = case inner_merge_lists
                       when true
                         ListMerger.new
                       when false
                         nil
                       when ListMerger
                         inner_merge_lists
                       else
                         raise ArgumentError, 'inner_merge_lists must be true, false, or a ListMerger instance'
                       end

        # Parse template
        begin
          @template_analysis = create_file_analysis(
            template_content,
            freeze_token: freeze_token,
            signature_generator: signature_generator,
            **parser_options
          )
        rescue StandardError => e
          raise template_parse_error_class.new(errors: [e])
        end

        # Parse destination
        begin
          @dest_analysis = create_file_analysis(
            dest_content,
            freeze_token: freeze_token,
            signature_generator: signature_generator,
            **parser_options
          )
        rescue StandardError => e
          raise destination_parse_error_class.new(errors: [e])
        end

        @aligner = FileAligner.new(@template_analysis, @dest_analysis, match_refiner: @match_refiner)
        @resolver = ConflictResolver.new(
          preference: @preference,
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
          resolution_mode: @resolution_mode,
          unresolved_policy: @unresolved_policy
        )
        @runtime_session = nil
        @runtime_root_operation = nil
      end

      def default_match_refiner(inner_merge_lists:, inner_merge_code_blocks:)
        refiners = []
        refiners << ListMatchRefiner.new if inner_merge_lists
        refiners << CodeBlockMatchRefiner.new if inner_merge_code_blocks
        return if refiners.empty?
        return refiners.first if refiners.length == 1

        Ast::Merge::CompositeMatchRefiner.new(*refiners)
      end

      # Create a FileAnalysis instance for the given content.
      #
      # @abstract Subclasses must implement this method
      # @param content [String] Markdown content to analyze
      # @param options [Hash] Analysis options
      # @return [FileAnalysisBase] File analysis instance
      def create_file_analysis(content, **options)
        raise NotImplementedError, "#{self.class} must implement #create_file_analysis"
      end

      # Returns the TemplateParseError class to use.
      #
      # Subclasses should override to return their parser-specific error class.
      #
      # @return [Class] TemplateParseError class
      def template_parse_error_class
        TemplateParseError
      end

      # Returns the DestinationParseError class to use.
      #
      # Subclasses should override to return their parser-specific error class.
      #
      # @return [Class] DestinationParseError class
      def destination_parse_error_class
        DestinationParseError
      end

      # Perform the merge operation and return the merged content as a string.
      #
      # @return [String] The merged Markdown content
      def merge
        merge_result.content
      end

      # Perform the merge operation and return the full MergeResult object.
      #
      # @return [MergeResult] The merge result containing merged content and metadata
      def merge_result
        return @merge_result if @merge_result

        @merge_result = DebugLogger.time('SmartMergerBase#merge') do
          prepare_runtime_session!
          alignment = DebugLogger.time('SmartMergerBase#align') do
            @aligner.align
          end

          DebugLogger.debug('Alignment complete', {
                              total_entries: alignment.size,
                              matches: alignment.count { |e| e[:type] == :match },
                              template_only: alignment.count { |e| e[:type] == :template_only },
                              dest_only: alignment.count { |e| e[:type] == :dest_only }
                            })

          # Process alignment using OutputBuilder
          builder, stats, frozen_blocks, conflicts, unresolved_cases = DebugLogger.time('SmartMergerBase#process') do
            process_alignment(alignment)
          end

          # Get content from OutputBuilder
          raw_content = builder.to_s
          content = raw_content

          # Collect problems from post-processing
          problems = DocumentProblems.new

          # Apply post-processing transformations
          content, problems = apply_post_processing(content, problems)
          complete_runtime_session!(content: content, stats: stats, problems: problems,
                                    unresolved_cases: unresolved_cases)

          # Get final content from OutputBuilder
          MergeResult.new(
            content: content,
            raw_content: raw_content,
            conflicts: conflicts,
            frozen_blocks: frozen_blocks,
            stats: stats,
            problems: problems,
            unresolved_cases: unresolved_cases
          )
        end
      end

      # Perform the merge and return a hash with content, debug info, and runtime data.
      #
      # @return [Hash] Hash with :content, :debug, :runtime, and :statistics keys
      def merge_with_debug
        result = merge_result
        template_analysis_debug = {
          valid: @template_analysis&.valid? || false,
          statements: @template_analysis&.statements&.size || 0
        }
        dest_analysis_debug = {
          valid: @dest_analysis&.valid? || false,
          statements: @dest_analysis&.statements&.size || 0
        }

        {
          content: result.content,
          debug: {
            template_statements: template_analysis_debug[:statements],
            dest_statements: dest_analysis_debug[:statements],
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            corruption_handling: @corruption_handling,
            runtime_operation_count: runtime_session&.operations&.size || 0,
            runtime_diagnostic_count: runtime_session&.diagnostics&.size || 0
          },
          runtime: runtime_session&.to_h,
          statistics: result.stats,
          decisions: result.stats,
          template_analysis: template_analysis_debug,
          dest_analysis: dest_analysis_debug
        }
      end

      # Get merge statistics (convenience method).
      #
      # @return [Hash] Statistics from the merge result
      def stats
        merge_result.stats
      end

      private

      def prepare_runtime_session!
        root_surface = Ast::Merge::Runtime::Surface.new(
          surface_kind: :markdown_document,
          declared_language: :markdown,
          effective_language: :markdown,
          address: 'document[0]',
          reconstruction_strategy: :portable_write,
          metadata: {
            backend: @template_analysis.respond_to?(:backend) ? @template_analysis.backend : nil
          }.compact
        )
        registry = Ast::Merge::Runtime::DelegationRegistry.new(
          delegates: runtime_delegates,
          metadata: {
            source: :markdown_merge
          }
        )

        @runtime_session = Ast::Merge::Runtime::Session.new(
          policy_context: runtime_policy_context,
          metadata: runtime_metadata,
          delegation_registry: registry
        )
        @runtime_root_operation = Ast::Merge::Runtime::Operation.new(
          operation_id: 'markdown-document-root',
          surface: root_surface,
          template_fragment: @template_analysis.source.to_s,
          destination_fragment: @dest_analysis.source.to_s,
          requested_strategy: :merge_document,
          options: {
            inner_merge_code_blocks: !@code_block_merger.nil?,
            inner_merge_lists: !@list_merger.nil?,
            corruption_handling: @corruption_handling,
            resolution_mode: @resolution_mode,
            unresolved_policy: @unresolved_policy.to_h
          }
        )
        @runtime_session.register(
          @runtime_root_operation,
          frame: Ast::Merge::Runtime::Frame.new(
            operation_id: @runtime_root_operation.operation_id,
            depth: 0,
            surface_path: root_surface.address,
            language_chain: [:markdown]
          ),
          delegate: @runtime_session.resolve_delegate_for(root_surface)
        )
      end

      def complete_runtime_session!(content:, stats:, problems:, unresolved_cases: [])
        return unless @runtime_root_operation

        delegated_children = @runtime_root_operation.children.select do |operation|
          operation.surface.surface_kind == :markdown_fenced_code_block
        end

        child_result = Ast::Merge::Runtime::ChildResult.new(
          replacement_text: content,
          diagnostics: @runtime_root_operation.diagnostics,
          capabilities_used: runtime_capabilities_used_for(delegated_children),
          capabilities_missing: runtime_capabilities_missing_for(delegated_children),
          unresolved_cases: unresolved_cases,
          metadata: {
            child_operation_ids: @runtime_root_operation.children.map(&:operation_id),
            stats: stats,
            problems: problems.all
          }
        )

        if child_result.unresolved?
          @runtime_root_operation.unresolved!(result: child_result)
        else
          @runtime_root_operation.complete!(result: child_result)
        end
      end

      def runtime_policy_context
        {
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          remove_template_missing_nodes: @remove_template_missing_nodes,
          corruption_handling: @corruption_handling,
          resolution_mode: @resolution_mode,
          unresolved_policy: @unresolved_policy.to_h
        }
      end

      def validate_resolution_mode!(resolution_mode)
        return if Ast::Merge::MergerConfig::VALID_RESOLUTION_MODES.include?(resolution_mode)

        raise ArgumentError,
              "Invalid resolution_mode: #{resolution_mode.inspect}. " \
                "Must be one of: #{Ast::Merge::MergerConfig::VALID_RESOLUTION_MODES.map(&:inspect).join(', ')}"
      end

      def runtime_metadata
        {
          merger_class: self.class.name,
          inner_merge_code_blocks: !@code_block_merger.nil?,
          inner_merge_lists: !@list_merger.nil?
        }
      end

      def runtime_delegates
        [runtime_markdown_delegate, *@code_block_merger&.runtime_delegates.to_a]
      end

      def runtime_markdown_delegate
        Ast::Merge::Runtime::Delegate.new(
          name: 'markdown-document',
          priority: 10,
          surface_kinds: [:markdown_document],
          languages: [:markdown],
          feature_profile: safe_runtime_feature_profile_for(@dest_analysis),
          capabilities: { merge: [:markdown_document] },
          metadata: {
            source: :markdown_merge
          }
        )
      end

      def safe_runtime_feature_profile_for(analysis)
        return unless analysis&.respond_to?(:feature_profile)

        analysis.feature_profile
      rescue StandardError
        nil
      end

      def runtime_capabilities_used_for(delegated_children)
        capabilities = [:top_level_merge]
        capabilities << :delegated_child_merge unless delegated_children.empty?
        capabilities
      end

      def runtime_capabilities_missing_for(delegated_children)
        return [] unless delegated_children.any?(&:failed?)

        [:delegated_child_merge]
      end

      # Apply post-processing transformations to merged content.
      #
      # @param content [String] The merged content
      # @param problems [DocumentProblems] Problems collector to add to
      # @return [Array<String, DocumentProblems>] [transformed_content, problems]
      def apply_post_processing(content, problems)
        content = collapse_cross_source_preamble_prefixes(content)

        # Apply whitespace normalization if enabled
        if @normalize_whitespace
          # Support both boolean and symbol modes
          mode = @normalize_whitespace == true ? :basic : @normalize_whitespace
          normalizer = WhitespaceNormalizer.new(content, mode: mode)
          content = normalizer.normalize
          problems.merge!(normalizer.problems)
        end

        # Apply link reference rehydration if enabled
        if @rehydrate_link_references
          rehydrator = LinkReferenceRehydrator.new(content)
          content = rehydrator.rehydrate
          problems.merge!(rehydrator.problems)
        end

        [content, problems]
      end

      STANDALONE_HTML_COMMENT_LINE_RE = /\A\s*<!--.*?-->\s*\z/

      def collapse_cross_source_preamble_prefixes(content)
        template_comments, = leading_standalone_comment_run(@template_analysis.source.to_s)
        return content if template_comments.empty?

        merged_comments, remainder = leading_standalone_comment_run(content)
        return content if merged_comments.empty?

        destination_specific_comments = merged_comments.reject { |line| template_comments.include?(line) }
        return content if destination_specific_comments.empty?

        should_heal = ::Ast::Merge::Healer.handle(
          mode: @corruption_handling,
          kind: :duplicate_template_preamble_prefix,
          message: 'merged Markdown preamble begins with duplicated template-owned standalone comment lines',
          prefix: '[markdown-merge]',
          error_class: Markdown::Merge::CorruptionDetectedError,
          warner: lambda { |formatted|
            DebugLogger.debug_warning(formatted, {
                                        template_comment_lines: template_comments.length,
                                        merged_comment_lines: merged_comments.length,
                                        destination_specific_comment_lines: destination_specific_comments.length
                                      })
          }
        )
        return content unless should_heal

        remainder = remainder.sub(/\A(?:\s*\n)+/, '')
        rebuilt = destination_specific_comments.join("\n")
        return rebuilt if remainder.empty?

        "#{rebuilt}\n\n#{remainder}"
      end

      def leading_standalone_comment_run(text)
        lines = text.to_s.split("\n", -1)
        comment_lines = []
        index = 0

        while index < lines.length
          line = lines[index]
          if line.strip.empty?
            comment_lines << line if comment_lines.any?
            index += 1
            next
          end

          break unless STANDALONE_HTML_COMMENT_LINE_RE.match?(line)

          comment_lines << line
          index += 1
        end

        normalized_comment_lines = comment_lines.reject(&:empty?)
        remainder = lines[index..]&.join("\n").to_s
        [normalized_comment_lines, remainder]
      end

      # Process alignment entries and build result using OutputBuilder
      #
      # @param alignment [Array<Hash>] Alignment entries
      # @return [Array] [output_builder, stats, frozen_blocks, conflicts, unresolved_cases]
      def process_alignment(alignment)
        builder = OutputBuilder.new
        frozen_blocks = []
        conflicts = []
        unresolved_cases = []
        stats = { nodes_added: 0, nodes_removed: 0, nodes_modified: 0 }
        preserve_removed_separator_gap = false
        link_ownership_context = removal_mode_link_ownership_context(alignment) if @remove_template_missing_nodes
        removal_comment_ownership = removal_mode_comment_ownership_context(alignment) if @remove_template_missing_nodes

        alignment.each_with_index do |entry, index|
          case entry[:type]
          when :match
            preserve_removed_separator_gap = false
            frozen = process_match_to_builder(entry, builder, stats, conflicts, unresolved_cases)
            frozen_blocks << frozen if frozen
          when :template_only
            preserve_removed_separator_gap = false
            process_template_only_to_builder(entry, builder, stats)
          when :dest_only
            frozen, preserve_removed_separator_gap = process_dest_only_to_builder(
              entry,
              builder,
              stats,
              preserve_separator_gap: preserve_removed_separator_gap,
              remaining_entries: alignment[(index + 1)..] || [],
              link_ownership_context: link_ownership_context,
              removal_comment_ownership: removal_comment_ownership&.[](entry[:dest_index])
            )
            frozen_blocks << frozen if frozen
          end
        end

        [builder, stats, frozen_blocks, conflicts, unresolved_cases]
      end

      # Process a matched node pair, adding to OutputBuilder
      #
      # @param entry [Hash] Alignment entry
      # @param builder [OutputBuilder] Output builder to add to
      # @param stats [Hash] Statistics hash to update
      # @return [Hash, nil] Frozen block info if applicable
      def process_match_to_builder(entry, builder, stats, conflicts, unresolved_cases)
        template_node = apply_node_typing(entry[:template_node])
        dest_node = apply_node_typing(entry[:dest_node])

        # Try inner-merge for code blocks first
        if @code_block_merger && code_block_node?(template_node) && code_block_node?(dest_node)
          inner_result = try_inner_merge_code_block_to_builder(template_node, dest_node, builder, stats, conflicts,
                                                               unresolved_cases)
          return if inner_result
        end

        # Try inner-merge for lists
        if @list_merger && list_node?(template_node) && list_node?(dest_node)
          inner_result = try_inner_merge_list_to_builder(template_node, dest_node, builder, stats, conflicts,
                                                         unresolved_cases)
          return if inner_result
        end

        resolution = @resolver.resolve(
          template_node,
          dest_node,
          template_index: entry[:template_index],
          dest_index: entry[:dest_index]
        )
        conflicts << resolution[:conflict] if resolution[:conflict]

        frozen_info = nil

        # Use unwrapped node for source extraction
        raw_template_node = Ast::Merge::NodeTyping.unwrap(template_node)
        raw_dest_node = Ast::Merge::NodeTyping.unwrap(dest_node)

        case resolution[:source]
        when :template
          preserved_link_definitions = preserved_destination_link_definitions_for_match(raw_template_node,
                                                                                        raw_dest_node)
          preserved_link_definitions.each do |link_definition|
            builder.add_node_source(link_definition, @dest_analysis)
          end
          unless preserved_link_definitions.empty?
            stats[:preserved_destination_link_definitions] ||= 0
            stats[:preserved_destination_link_definitions] += preserved_link_definitions.length
          end
          stats[:nodes_modified] += 1 if resolution[:decision] != :identical
          emitted_range = builder.add_node_source(raw_template_node, @template_analysis)
        when :destination
          if raw_dest_node.respond_to?(:freeze_node?) && raw_dest_node.freeze_node?
            frozen_info = {
              start_line: raw_dest_node.start_line,
              end_line: raw_dest_node.end_line,
              reason: raw_dest_node.reason
            }
          end
          emitted_range = builder.add_node_source(raw_dest_node, @dest_analysis)
        end

        if resolution[:unresolved_case]
          unresolved_cases << unresolved_case_with_output_range(resolution[:unresolved_case],
                                                                emitted_range)
        end

        frozen_info
      end

      def unresolved_case_with_output_range(unresolved_case, output_range)
        return unresolved_case unless unresolved_case && output_range

        metadata = unresolved_case.metadata.dup
        relative_output_range = metadata.delete(:relative_output_range)
        metadata[:output_range] =
          if relative_output_range
            output_range_from_relative(output_range, relative_output_range)
          else
            output_range
          end

        Ast::Merge::Runtime::ResolutionCase.new(
          case_id: unresolved_case.case_id,
          reason: unresolved_case.reason,
          candidates: unresolved_case.candidates,
          provisional_winner: unresolved_case.provisional_winner,
          surface_path: unresolved_case.surface_path,
          operation_id: unresolved_case.operation_id,
          metadata: metadata
        )
      end

      def output_range_from_relative(parent_range, relative_range)
        start_offset, = Array(parent_range)
        relative_start, relative_end = Array(relative_range)
        return parent_range unless [start_offset, relative_start, relative_end].all?

        [start_offset + relative_start.to_i, start_offset + relative_end.to_i]
      end

      def preserved_destination_link_definitions_for_match(template_node, dest_node)
        destination_link_definitions = consumed_link_definitions_within(dest_node, @dest_analysis)
        return [] if destination_link_definitions.empty?

        template_signatures = consumed_link_definitions_within(template_node, @template_analysis)
                              .map(&:signature)
                              .to_set

        destination_link_definitions.reject do |link_definition|
          template_signatures.include?(link_definition.signature)
        end
      end

      def consumed_link_definitions_within(node, analysis)
        return [] if skip_link_ownership_scanning_for_node?(node, analysis)

        pos = node.source_position
        start_line = pos&.dig(:start_line)
        end_line = pos&.dig(:end_line)
        return [] unless start_line && end_line

        (start_line..end_line).filter_map do |line_number|
          LinkDefinitionNode.parse(analysis.source_range(line_number, line_number), line_number: line_number)
        end.then { |definitions| unique_link_definitions_by_signature(definitions) }
      rescue StandardError => e
        return [] if missing_source_position_protocol_error?(e)

        raise
      end

      def missing_source_position_protocol_error?(error)
        error.is_a?(NoMethodError) || error.class.name == 'RSpec::Mocks::MockExpectationError'
      end

      # Apply node typing to a node if node_typing is configured.
      #
      # For markdown nodes, this supports matching by:
      # 1. Node class name (standard NodeTyping behavior)
      # 2. Canonical node type (e.g., :heading, :table, :paragraph)
      #
      # Note: Markdown nodes are pre-wrapped with canonical merge_type by
      # NodeTypeNormalizer during parsing. This method allows custom node_typing
      # to override or refine that canonical type.
      #
      # @param node [Object] The node to potentially wrap with merge_type
      # @return [Object] The node, possibly wrapped with NodeTyping::Wrapper
      def apply_node_typing(node)
        return node unless @node_typing
        return node unless node

        # For markdown nodes, check if there's a custom callable for the canonical type.
        # This takes precedence because nodes are pre-wrapped by NodeTypeNormalizer.
        if node.respond_to?(:type)
          canonical_type = node.type
          callable = @node_typing[canonical_type] ||
                     @node_typing[canonical_type.to_s] ||
                     @node_typing[canonical_type.to_sym]
          if callable
            # Call the custom lambda - it may return a refined typed node
            # or the original node unchanged
            return callable.call(node)
          end
        end

        # Fall back to standard class-name-based matching
        result = Ast::Merge::NodeTyping.process(node, @node_typing)
        return result if Ast::Merge::NodeTyping.typed_node?(result)

        node
      end

      # Check if a node is a code block.
      #
      # @param node [Object] Node to check
      # @return [Boolean] true if the node is a code block
      def code_block_node?(node)
        return false if node.respond_to?(:freeze_node?) && node.freeze_node?

        node.respond_to?(:type) && node.type.to_s == 'code_block'
      end

      # Check if a node is an ordered or unordered list.
      #
      # @param node [Object] Node to check
      # @return [Boolean] true if the node is a list
      def list_node?(node)
        return false if node.respond_to?(:freeze_node?) && node.freeze_node?

        node.respond_to?(:type) && node.type.to_s == 'list'
      end

      # Try to inner-merge two list nodes at the item level, adding to OutputBuilder.
      #
      # @param template_node [Object] Template list node
      # @param dest_node [Object] Destination list node
      # @param builder [OutputBuilder] Output builder to add to
      # @param stats [Hash] Statistics hash to update
      # @return [Boolean] true if merged, false to fall back to standard resolution
      def try_inner_merge_list_to_builder(template_node, dest_node, builder, stats, conflicts, unresolved_cases)
        result = @list_merger.merge_lists(
          template_node,
          dest_node,
          preference: @preference.is_a?(Hash) ? @preference.fetch(:default, :destination) : @preference,
          add_template_only_nodes: @add_template_only_nodes,
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
          resolution_mode: @resolution_mode,
          unresolved_policy: @unresolved_policy
        )

        if result[:merged]
          stats[:nodes_modified] += 1 unless result.dig(:stats, :decision) == :identical
          stats[:inner_merges] ||= 0
          stats[:inner_merges] += 1
          emitted_range = builder.add_raw(result[:content])
          remapped_cases = Array(result[:unresolved_cases]).map do |resolution_case|
            unresolved_case_with_output_range(resolution_case, emitted_range)
          end
          unresolved_cases.concat(remapped_cases)
          conflicts.concat(remapped_cases.map { |resolution_case| conflict_for_resolution_case(resolution_case) })
          true
        else
          DebugLogger.debug('List inner-merge skipped', { reason: result[:reason] })
          false
        end
      end

      # Try to inner-merge two code block nodes, adding to OutputBuilder
      #
      # @param template_node [Object] Template code block
      # @param dest_node [Object] Destination code block
      # @param builder [OutputBuilder] Output builder to add to
      # @param stats [Hash] Statistics hash to update
      # @return [Boolean] true if merged, false to fall back to standard resolution
      def try_inner_merge_code_block_to_builder(template_node, dest_node, builder, stats, conflicts, unresolved_cases)
        result = @code_block_merger.merge_code_blocks(
          template_node,
          dest_node,
          preference: @preference,
          runtime_session: @runtime_session,
          parent_operation: @runtime_root_operation,
          add_template_only_nodes: @add_template_only_nodes,
          resolution_mode: @resolution_mode,
          unresolved_policy: @unresolved_policy
        )

        if result[:merged]
          stats[:nodes_modified] += 1 unless result.dig(:stats, :decision) == :identical
          stats[:inner_merges] ||= 0
          stats[:inner_merges] += 1
          emitted_range = builder.add_raw(result[:content])
          remapped_cases = remap_delegated_unresolved_cases(
            result[:unresolved_cases],
            result[:runtime_operation_id],
            result[:runtime_surface_path],
            emitted_range,
            result[:metadata]
          )
          unresolved_cases.concat(remapped_cases)
          conflicts.concat(remapped_cases.map { |resolution_case| conflict_for_resolution_case(resolution_case) })
          true
        else
          DebugLogger.debug('Inner-merge skipped', { reason: result[:reason] })
          false # Fall back to standard resolution
        end
      end

      def remap_delegated_unresolved_cases(unresolved_cases, runtime_operation_id, runtime_surface_path,
                                           output_range = nil, delegated_metadata = nil)
        root_apply_candidates = delegated_metadata.to_h[:root_apply_candidates_by_case_id].to_h
        delegated_apply_renderer = delegated_metadata.to_h[:delegated_apply_renderer]
        Array(unresolved_cases).map do |resolution_case|
          suffix = delegated_surface_suffix_for(resolution_case.surface_path)
          metadata = resolution_case.metadata.merge(
            delegated_case_id: resolution_case.case_id
          )
          apply_candidates = root_apply_candidates[resolution_case.case_id]
          if output_range && apply_candidates
            metadata = metadata.merge(
              output_range: output_range,
              output_candidate_by_selection: apply_candidates
            )
          end
          if output_range && delegated_apply_renderer
            metadata = metadata.merge(
              output_range: output_range,
              delegated_apply_group: runtime_operation_id,
              delegated_apply_renderer: delegated_apply_renderer,
              delegated_applied_selections: {},
              delegated_root_applied_selections: {},
              delegated_runtime_operation_id: runtime_operation_id,
              delegated_runtime_surface_path: runtime_surface_path
            )
          end

          Ast::Merge::Runtime::ResolutionCase.new(
            case_id: "#{runtime_operation_id}-#{resolution_case.case_id}",
            reason: resolution_case.reason,
            candidates: resolution_case.candidates,
            provisional_winner: resolution_case.provisional_winner,
            surface_path: [runtime_surface_path, suffix].compact.join(' > '),
            operation_id: runtime_operation_id,
            metadata: metadata
          )
        end
      end

      def delegated_surface_suffix_for(surface_path)
        path = surface_path.to_s
        return if path.empty? || path == 'document[0]'

        path.sub(/\Adocument\[0\]\s*>\s*/, '')
      end

      def conflict_for_resolution_case(resolution_case)
        {
          case_id: resolution_case.case_id,
          reason: resolution_case.reason,
          template: resolution_case.candidates[:template],
          destination: resolution_case.candidates[:destination],
          provisional_winner: resolution_case.provisional_winner,
          location: resolution_case.surface_path
        }.compact
      end

      # Try to inner-merge two code block nodes.
      #
      # @deprecated Use try_inner_merge_code_block_to_builder instead
      # @param template_node [Object] Template code block
      # @param dest_node [Object] Destination code block
      # @param stats [Hash] Statistics hash to update
      # @return [Array, nil] [content_string, nil] if merged, nil to fall back to standard resolution
      def try_inner_merge_code_block(template_node, dest_node, stats)
        result = @code_block_merger.merge_code_blocks(
          template_node,
          dest_node,
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes
        )

        if result[:merged]
          stats[:nodes_modified] += 1 unless result.dig(:stats, :decision) == :identical
          stats[:inner_merges] ||= 0
          stats[:inner_merges] += 1
          [result[:content], nil]
        else
          DebugLogger.debug('Inner-merge skipped', { reason: result[:reason] })
          nil # Fall back to standard resolution
        end
      end

      # Process a template-only node, adding to OutputBuilder
      #
      # @param entry [Hash] Alignment entry
      # @param builder [OutputBuilder] Output builder to add to
      # @param stats [Hash] Statistics hash to update
      # @return [void]
      def process_template_only_to_builder(entry, builder, stats)
        return unless should_add_template_only_node?(entry)

        stats[:nodes_added] += 1
        builder.add_node_source(entry[:template_node], @template_analysis)
      end

      # Determine if a template-only node should be added.
      #
      # Gap lines (blank lines/whitespace) represent formatting. Document-trailing gap lines
      # (at the very end with no more content after them) follow preference. Other gap lines
      # Determine if a template-only node should be added.
      #
      # Gap lines (blank lines) and all other nodes follow the add_template_only_nodes setting.
      # When false (default), template-only content is skipped.
      # When true, all template-only content including gap lines is included.
      #
      # @param entry [Hash] Alignment entry with :template_node and :signature
      # @return [Boolean] true if the node should be added
      def should_add_template_only_node?(entry)
        node = entry[:template_node]

        case @add_template_only_nodes
        when false, nil
          false
        when true
          true
        else
          # Callable filter
          if @add_template_only_nodes.respond_to?(:call)
            @add_template_only_nodes.call(node, entry)
          else
            true
          end
        end
      end

      # Process a destination-only node, adding to OutputBuilder.
      #
      # All dest-only nodes are included, including gap lines (formatting).
      #
      # @param entry [Hash] Alignment entry
      # @param builder [OutputBuilder] Output builder to add to
      # @param stats [Hash] Statistics hash to update
      # @return [Hash, nil] Frozen block info if applicable
      def process_dest_only_to_builder(entry, builder, stats, preserve_separator_gap: false, remaining_entries: [],
                                       link_ownership_context: nil, removal_comment_ownership: nil)
        node = entry[:dest_node]

        frozen_info = nil

        if node.respond_to?(:freeze_node?) && node.freeze_node?
          frozen_info = {
            start_line: node.start_line,
            end_line: node.end_line,
            reason: node.reason
          }
        end

        unless @remove_template_missing_nodes
          builder.add_node_source(node, @dest_analysis)
          return [frozen_info, false]
        end

        if preserve_removed_dest_only_node?(node, removal_comment_ownership)
          if link_definition_node?(node)
            return [frozen_info, false] unless preserve_removed_link_definition_node?(node, link_ownership_context)

            link_ownership_context[:preserved] << node.signature if link_ownership_context
          end

          if standalone_comment_node?(node,
                                      @dest_analysis) && preserved_removal_comment_node?(node,
                                                                                         removal_comment_ownership)
            stats[:preserved_destination_comment_fragments] ||= 0
            stats[:preserved_destination_comment_fragments] += 1
          end

          builder.add_node_source(node, @dest_analysis)
          return [frozen_info, preserve_separator_gap_after_removed_node?(node, remaining_entries)]
        end

        if preserve_removed_separator_gap_line?(node)
          return [frozen_info, false] if builder.empty? || builder.blank_line_terminated?

          should_preserve_gap = preserve_separator_gap && separator_gap_needed_after_removed_node?(remaining_entries)
          should_preserve_gap ||= leading_separator_gap_before_preserved_comment_needed?(remaining_entries)
          return [frozen_info, false] unless should_preserve_gap

          builder.add_node_source(node, @dest_analysis)
          return [frozen_info, false]
        end

        if removable_destination_only_node?(node)
          preserved_link_definitions = preserved_destination_link_definitions_for_removed_node(node,
                                                                                               link_ownership_context)

          if preserved_link_definitions.any?
            builder.add_gap_line(count: 1) unless builder.empty? || builder.blank_line_terminated?

            preserved_link_definitions.each do |link_definition|
              builder.add_node_source(link_definition, @dest_analysis)
              link_ownership_context[:preserved] << link_definition.signature if link_ownership_context
            end

            stats[:preserved_destination_link_definitions] ||= 0
            stats[:preserved_destination_link_definitions] += preserved_link_definitions.length
          end

          stats[:nodes_removed] += 1
          return [nil, preserve_separator_gap || separator_gap_needed_after_removed_node?(remaining_entries)]
        end

        [nil, preserve_separator_gap]
      end

      # Removal-mode node classification — Markdown-family local.
      #
      # These predicates live here rather than in PreservationSupport because their
      # semantics are specific to full-document removal mode and would be meaningless
      # or misleading in a shared preservation context:
      #
      # * preserve_removed_separator_gap_line? — named entry-point for removal mode;
      #   delegates directly to PreservationSupport#blank_gap_line_node?.
      #
      # * removable_destination_only_node? — intentionally does NOT exclude standalone
      #   comment nodes. Standalone comments ARE removable in removal mode unless they
      #   are owned by a remove plan. This makes it distinct from
      #   PreservationSupport#structural_preservation_statement?, which excludes all
      #   three non-structural categories (gap lines, standalone comments, link defs).
      #
      # * boundary_owner_statement? — identifies any non-blank-gap-line statement as a
      #   valid boundary anchor for remove-plan construction. This is a removal-mode
      #   concept only; PartialTemplateMerger has no equivalent boundary-anchoring need.
      def preserve_removed_dest_only_node?(node, removal_comment_ownership = nil)
        return true if node.respond_to?(:freeze_node?) && node.freeze_node?
        return true if link_definition_node?(node)
        return true if non_blank_gap_line_node?(node)

        preserved_removal_comment_node?(node, removal_comment_ownership)
      end

      def preserve_separator_gap_after_removed_node?(node, remaining_entries = [])
        standalone_comment_node?(node, @dest_analysis) && separator_gap_needed_after_removed_node?(remaining_entries)
      end

      def leading_separator_gap_before_preserved_comment_needed?(remaining_entries)
        next_entry = remaining_entries.find do |entry|
          entry[:type] != :dest_only || !preserve_removed_separator_gap_line?(entry[:dest_node])
        end

        next_entry && next_entry[:type] == :dest_only && standalone_comment_node?(next_entry[:dest_node],
                                                                                  @dest_analysis)
      end

      def separator_gap_needed_after_removed_node?(remaining_entries)
        remaining_entries.any? { |entry| entry_kept_after_removed_node?(entry) }
      end

      def entry_kept_after_removed_node?(entry)
        case entry[:type]
        when :match
          true
        when :template_only
          should_add_template_only_node?(entry)
        when :dest_only
          node = entry[:dest_node]
          (node.respond_to?(:freeze_node?) && node.freeze_node?) || preserve_removed_dest_only_node?(node)
        else
          false
        end
      end

      def preserve_removed_separator_gap_line?(node)
        blank_gap_line_node?(node)
      end

      def removable_destination_only_node?(node)
        !gap_line_node?(node) && !link_definition_node?(node)
      end

      def removal_mode_link_ownership_context(alignment)
        needed = Set.new
        available = Set.new

        alignment.each do |entry|
          kept_node, analysis = kept_node_for_link_ownership(entry)
          next unless kept_node && analysis

          link_reference_signatures_within(kept_node, analysis).each { |signature| needed << signature }
          link_definition_signatures_within(kept_node, analysis).each { |signature| available << signature }
        end

        { needed: needed, available: available, preserved: Set.new }
      end

      def removal_mode_comment_ownership_context(alignment)
        contexts = {}
        run_entries = []

        alignment.each do |entry|
          if removal_mode_comment_run_entry?(entry)
            run_entries << entry
            next
          end

          merge_removal_comment_ownership_context!(contexts, run_entries)
          run_entries = []
        end

        merge_removal_comment_ownership_context!(contexts, run_entries)
        contexts
      end

      def merge_removal_comment_ownership_context!(contexts, run_entries)
        ownership = removal_comment_ownership_for_run(run_entries)
        return contexts unless ownership

        Array(run_entries).each do |entry|
          contexts[entry[:dest_index]] = ownership
        end

        contexts
      end

      def removal_comment_ownership_for_run(run_entries)
        entries = Array(run_entries)
        return if entries.empty?
        return unless entries.any? { |entry| removal_mode_removable_structural_node?(entry[:dest_node]) }

        remove_plan = removal_mode_remove_plan_for_entries(entries)
        return unless remove_plan

        {
          remove_plan: remove_plan,
          owned_comment_region_keys: remove_plan_preserved_comment_keys(remove_plan),
          owned_comment_node_keys: removal_mode_owned_comment_node_keys(remove_plan, entries)
        }.freeze
      end

      def removal_mode_comment_run_entry?(entry)
        return false unless entry[:type] == :dest_only

        node = entry[:dest_node]
        preserve_removed_separator_gap_line?(node) ||
          standalone_comment_node?(node, @dest_analysis) ||
          removal_mode_removable_structural_node?(node)
      end

      def removal_mode_removable_structural_node?(node)
        removable_destination_only_node?(node) && !preserve_removed_dest_only_node?(node)
      end

      def removal_mode_remove_plan_for_entries(entries)
        first_entry = entries.first
        last_entry = entries.last
        return unless first_entry && last_entry

        first_dest_index = first_entry[:dest_index]
        last_dest_index = last_entry[:dest_index]
        return if first_dest_index.nil? || last_dest_index.nil?

        statements = entries.map { |entry| entry[:dest_node] }

        leading_statement = preceding_boundary_statement(first_dest_index)
        trailing_statement = following_boundary_statement(last_dest_index)

        Ast::Merge::StructuralEdit::RemovePlanSupport.build_remove_plan(
          analysis: @dest_analysis,
          statements: statements,
          leading_statement: leading_statement,
          trailing_statement: trailing_statement,
          source: :smart_merger_base_removal_mode
        )
      end

      def preceding_boundary_statement(dest_index)
        @dest_analysis.statements[0...dest_index].reverse_each.find { |statement| boundary_owner_statement?(statement) }
      end

      def following_boundary_statement(dest_index)
        Array(@dest_analysis.statements[(dest_index + 1)..]).find { |statement| boundary_owner_statement?(statement) }
      end

      def boundary_owner_statement?(statement)
        statement && !preserve_removed_separator_gap_line?(statement)
      end

      def removal_mode_owned_comment_node_keys(remove_plan, run_entries)
        remove_plan_preserved_comment_keys_for_nodes(
          remove_plan,
          nodes: Array(run_entries).map { |entry| entry[:dest_node] },
          analysis: @dest_analysis
        )
      end

      def preserved_removal_comment_node?(node, removal_comment_ownership = nil)
        return false unless standalone_comment_node?(node, @dest_analysis)
        return true unless removal_comment_ownership

        remove_plan_owns_comment_node?(
          node,
          @dest_analysis,
          removal_comment_ownership.fetch(:remove_plan),
          preserved_comment_keys: removal_comment_ownership.fetch(:owned_comment_region_keys)
        ) || removal_comment_ownership.fetch(:owned_comment_node_keys).include?(preserved_comment_node_key(node,
                                                                                                           @dest_analysis))
      end

      def kept_node_for_link_ownership(entry)
        case entry[:type]
        when :match
          template_node = apply_node_typing(entry[:template_node])
          dest_node = apply_node_typing(entry[:dest_node])

          resolution = @resolver.resolve(
            template_node,
            dest_node,
            template_index: entry[:template_index],
            dest_index: entry[:dest_index]
          )

          if resolution[:source] == :template
            [Ast::Merge::NodeTyping.unwrap(template_node), @template_analysis]
          else
            [Ast::Merge::NodeTyping.unwrap(dest_node), @dest_analysis]
          end
        when :template_only
          return unless should_add_template_only_node?(entry)

          [Ast::Merge::NodeTyping.unwrap(entry[:template_node]), @template_analysis]
        when :dest_only
          node = entry[:dest_node]
          return unless preserve_removed_dest_only_node?(node)
          return if link_definition_node?(node)

          [node, @dest_analysis]
        end
      end

      def preserved_destination_link_definitions_for_removed_node(node, link_ownership_context)
        return [] unless link_ownership_context

        destination_link_definitions = consumed_link_definitions_within(node, @dest_analysis)
        return [] if destination_link_definitions.empty?

        needed_signatures = link_ownership_context.fetch(:needed)
        available_signatures = link_ownership_context.fetch(:available)
        preserved_signatures = link_ownership_context.fetch(:preserved)

        destination_link_definitions.reject do |link_definition|
          signature = link_definition.signature
          !needed_signatures.include?(signature) ||
            available_signatures.include?(signature) ||
            preserved_signatures.include?(signature)
        end
      end

      def preserve_removed_link_definition_node?(node, link_ownership_context)
        return true unless link_ownership_context

        signature = node.signature
        !link_ownership_context.fetch(:available).include?(signature) &&
          !link_ownership_context.fetch(:preserved).include?(signature)
      end

      def link_definition_signatures_within(node, analysis)
        return Set.new if standalone_comment_node?(node, analysis)

        if node.is_a?(LinkDefinitionNode)
          Set[node.signature]
        else
          consumed_link_definitions_within(node, analysis).map(&:signature).to_set
        end
      end

      def link_reference_signatures_within(node, analysis)
        return Set.new if skip_link_ownership_scanning_for_node?(node, analysis)

        source = node_to_source(node, analysis)
        return Set.new if source.nil? || source.empty?

        source.scan(/!?\[([^\]]+)\]\[([^\]]*)\]/).each_with_object(Set.new) do |(text_label, explicit_label), signatures|
          label = explicit_label.to_s.empty? ? text_label : explicit_label
          normalized_label = label.to_s.downcase
          next if normalized_label.empty?

          signatures << [:link_definition, normalized_label]
        end
      end

      def skip_link_ownership_scanning_for_node?(node, analysis)
        return true if gap_line_node?(node) || link_definition_node?(node)
        return true if node.respond_to?(:freeze_node?) && node.freeze_node?
        return true if standalone_comment_node?(node, analysis)

        literal_link_ownership_context_node?(node)
      end

      def unique_link_definitions_by_signature(link_definitions)
        seen = Set.new

        link_definitions.each_with_object([]) do |link_definition, unique_definitions|
          signature = link_definition.signature
          next if seen.include?(signature)

          seen << signature
          unique_definitions << link_definition
        end
      end

      def literal_link_ownership_context_node?(node)
        return false unless node.respond_to?(:type)

        %w[code_block html html_block custom_block].include?(node.type.to_s)
      end

      # Convert a node to its source text.
      #
      # Default implementation uses source positions and falls back to to_commonmark.
      # Subclasses may override for parser-specific behavior.
      #
      # @param node [Object] Node to convert
      # @param analysis [FileAnalysisBase] Analysis for source lookup
      # @return [String] Source text
      def node_to_source(node, analysis)
        # Check for any FreezeNode type (base class or subclass)
        if node.is_a?(Ast::Merge::FreezeNodeBase)
          node.full_text
        else
          pos = node.source_position
          start_line = pos&.dig(:start_line)
          end_line = pos&.dig(:end_line)

          return node.to_commonmark unless start_line && end_line

          analysis.source_range(start_line, end_line)
        end
      end

      # Check if a gap line is document-trailing (no more content after it).
      #
      # A gap line is document-trailing if there are no more content nodes after it
      # in the statements list. We check all siblings after this gap line - if they're
      # all gap lines (no content), then this is document-trailing.
      #
      # @param gap_line [GapLineNode] The gap line to check
      # @param analysis [FileAnalysisBase] The analysis containing the gap line
      # @return [Boolean] true if the gap line is document-trailing
      def gap_line_is_document_trailing?(gap_line, analysis)
        # Find this gap line's index in the statements
        statements = analysis.statements
        gap_index = statements.index(gap_line)

        DebugLogger.debug('Checking if gap line is document-trailing', {
                            gap_line_number: gap_line.line_number,
                            gap_index: gap_index,
                            total_statements: statements.length
                          })

        return true if gap_index.nil? # Shouldn't happen, but treat as trailing if missing

        # Check all statements after this gap line
        # If they're ALL gap lines (no content nodes), then this is document-trailing
        (gap_index + 1...statements.length).each do |i|
          node = statements[i]
          # If we find a non-gap-line node, this gap line is NOT document-trailing
          next if gap_line_node?(node)

          DebugLogger.debug('Found content after gap line', {
                              next_node_index: i,
                              next_node_type: node.class.name
                            })
          return false
        end

        # All remaining nodes are gap lines (or no nodes after), so this is document-trailing
        DebugLogger.debug('Gap line IS document-trailing - no content after it')
        true
      end
    end
  end
end
