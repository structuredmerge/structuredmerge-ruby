# frozen_string_literal: true

module Markdown
  module Merge
    # Merges fenced code blocks using language-specific *-merge gems.
    #
    # When two code blocks with the same signature are matched, this class
    # delegates the merge to the appropriate language-specific merger:
    # - Ruby code → prism-merge
    # - YAML code → psych-merge
    # - JSON code → json-merge
    # - TOML code → toml-merge
    #
    # @example Basic usage
    #   merger = CodeBlockMerger.new
    #   result = merger.merge_code_blocks(template_node, dest_node, preference: :destination)
    #   if result[:merged]
    #     puts result[:content]
    #   else
    #     # Fall back to standard resolution
    #   end
    #
    # @example With custom mergers
    #   merger = CodeBlockMerger.new(
    #     mergers: {
    #       "ruby" => ->(template, dest, pref) { MyCustomRubyMerger.merge(template, dest, pref) },
    #     }
    #   )
    #
    # @see SmartMergerBase
    # @api public
    class CodeBlockMerger
      # Default language-to-merger mapping
      # Each merger is a lambda that takes (template_content, dest_content, preference)
      # and returns { merged: true/false, content: String, stats: Hash }
      # simplecov:disable integration - DEFAULT_MERGERS lambdas require external gems
      DEFAULT_MERGERS = {
        # Ruby code blocks
        'ruby' => lambda { |template, dest, preference, **opts|
          require 'prism/merge'
          CodeBlockMerger.merge_with_prism(template, dest, preference, **opts)
        },
        'rb' => lambda { |template, dest, preference, **opts|
          require 'prism/merge'
          CodeBlockMerger.merge_with_prism(template, dest, preference, **opts)
        },

        # YAML code blocks
        'yaml' => lambda { |template, dest, preference, **opts|
          require 'psych/merge'
          CodeBlockMerger.merge_with_psych(template, dest, preference, **opts)
        },
        'yml' => lambda { |template, dest, preference, **opts|
          require 'psych/merge'
          CodeBlockMerger.merge_with_psych(template, dest, preference, **opts)
        },

        # JSON code blocks
        'json' => lambda { |template, dest, preference, **opts|
          require 'json/merge'
          CodeBlockMerger.merge_with_json(template, dest, preference, **opts)
        },

        # Markdown code blocks
        'markdown' => lambda { |template, dest, preference, **opts|
          require 'markdown/merge'
          CodeBlockMerger.merge_with_markdown(template, dest, preference, **opts)
        },
        'md' => lambda { |template, dest, preference, **opts|
          require 'markdown/merge'
          CodeBlockMerger.merge_with_markdown(template, dest, preference, **opts)
        },

        # TOML code blocks
        'toml' => lambda { |template, dest, preference, **opts|
          require 'toml/merge'
          CodeBlockMerger.merge_with_toml(template, dest, preference, **opts)
        }
      }.freeze
      # simplecov:enable

      # @return [Hash<String, Proc>] Language to merger mapping
      attr_reader :mergers

      # @return [Boolean] Whether inner-merge is enabled
      attr_reader :enabled

      # @return [Array<Ast::Merge::Runtime::Delegate>] Runtime delegates exposed by this merger
      attr_reader :runtime_delegates

      # Creates a new CodeBlockMerger.
      #
      # @param mergers [Hash<String, Proc>] Custom language-to-merger mapping.
      #   Mergers are merged with defaults, allowing selective overrides.
      # @param enabled [Boolean] Whether to enable inner-merge (default: true)
      def initialize(mergers: {}, enabled: true)
        @mergers = DEFAULT_MERGERS.merge(mergers)
        @enabled = enabled
        @runtime_delegates = build_runtime_delegates.freeze
      end

      # Check if inner-merge is available for a language.
      #
      # @param language [String] The language identifier from fence_info
      # @return [Boolean] true if a merger exists for this language
      def supports_language?(language)
        return false unless @enabled
        return false if language.nil? || language.empty?

        @mergers.key?(language.downcase)
      end

      # Merge two code blocks using the appropriate language-specific merger.
      #
      # @param template_node [Object] Template code block node
      # @param dest_node [Object] Destination code block node
      # @param preference [Symbol] :destination or :template
      # @param opts [Hash] Additional options passed to the merger
      # @return [Hash] { merged: Boolean, content: String, stats: Hash }
      def merge_code_blocks(template_node, dest_node, preference:, runtime_session: nil, parent_operation: nil, **opts)
        if runtime_session && parent_operation
          return merge_code_blocks_with_runtime(
            template_node,
            dest_node,
            preference: preference,
            runtime_session: runtime_session,
            parent_operation: parent_operation,
            **opts
          )
        end

        merge_code_blocks_without_runtime(template_node, dest_node, preference: preference, **opts)
      end

      def merge_code_blocks_without_runtime(template_node, dest_node, preference:, **opts)
        return not_merged('inner-merge disabled') unless @enabled

        language = extract_language(template_node) || extract_language(dest_node)
        return not_merged('no language specified') unless language

        template_content = extract_content(template_node)
        dest_content = extract_content(dest_node)

        perform_code_block_merge(
          language: language,
          template_content: template_content,
          dest_content: dest_content,
          preference: preference,
          reference_node: dest_node,
          **opts
        )
      end

      private

      def merge_code_blocks_with_runtime(template_node, dest_node, preference:, runtime_session:, parent_operation:,
                                         **opts)
        operation = build_runtime_operation(
          template_node: template_node,
          dest_node: dest_node,
          preference: preference,
          runtime_session: runtime_session,
          parent_operation: parent_operation,
          **opts
        )

        parent_operation.add_child(operation)
        parent_frame = runtime_session.frame_for(parent_operation.operation_id)
        delegate = runtime_session.resolve_delegate_for(operation.surface, capability: :merge)
        runtime_session.register(
          operation,
          frame: Ast::Merge::Runtime::Frame.new(
            parent_operation_id: parent_operation.operation_id,
            operation_id: operation.operation_id,
            depth: parent_frame ? parent_frame.depth + 1 : 1,
            surface_path: operation.surface.address,
            language_chain: [*(parent_frame&.language_chain || [:markdown]),
                             operation.surface.effective_language].compact
          ),
          delegate: delegate
        )

        unless delegate
          reason = unsupported_runtime_reason_for(operation.surface)
          operation.fail!(
            diagnostic: Ast::Merge::Runtime::Diagnostic.new(
              severity: :warn,
              kind: :unsupported_capability,
              operation_id: operation.operation_id,
              surface_path: operation.surface.address,
              message: reason,
              metadata: {
                capability: :merge,
                language: operation.surface.effective_language
              }
            )
          )
          return not_merged(reason).merge(runtime_operation_id: operation.operation_id)
        end

        operation.running!
        child_result = delegate.merge(operation: operation, session: runtime_session)
        if child_result.unresolved?
          operation.unresolved!(result: child_result)
        else
          operation.complete!(result: child_result)
        end

        if child_result.metadata[:merged]
          {
            merged: true,
            content: child_result.replacement_text,
            stats: child_result.metadata[:stats] || {},
            runtime_operation_id: operation.operation_id,
            runtime_surface_path: operation.surface.address,
            unresolved_cases: child_result.unresolved_cases,
            metadata: child_result.metadata
          }
        else
          not_merged(child_result.metadata[:reason] || 'merger declined').merge(
            stats: child_result.metadata[:stats] || {},
            runtime_operation_id: operation.operation_id
          )
        end
      end

      def build_runtime_operation(template_node:, dest_node:, preference:, runtime_session:, parent_operation:, **opts)
        language = extract_language(template_node) || extract_language(dest_node)
        reference_node = dest_node || template_node
        surface = Ast::Merge::Runtime::Surface.new(
          surface_kind: :markdown_fenced_code_block,
          declared_language: language,
          effective_language: language,
          address: runtime_surface_address(reference_node, runtime_session),
          parent_address: parent_operation.surface.address,
          span: runtime_surface_span(reference_node),
          reconstruction_strategy: :portable_write,
          metadata: {
            fence_info: reference_node&.respond_to?(:fence_info) ? reference_node.fence_info : nil,
            language: language
          }.compact
        )

        Ast::Merge::Runtime::Operation.new(
          operation_id: "markdown-code-block-#{runtime_session.operations.count}",
          surface: surface,
          template_fragment: rebuild_code_block(language, extract_content(template_node), template_node),
          destination_fragment: rebuild_code_block(language, extract_content(dest_node), dest_node),
          requested_strategy: :delegate_child_surface,
          options: {
            preference: preference,
            add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
            resolution_mode: opts.fetch(:resolution_mode, :eager),
            unresolved_policy: Ast::Merge::UnresolvedPolicy.coerce(opts[:unresolved_policy]).to_h,
            template_content: extract_content(template_node),
            destination_content: extract_content(dest_node),
            reference_node: reference_node
          }
        )
      end

      def runtime_surface_address(reference_node, runtime_session)
        span = runtime_surface_span(reference_node)
        suffix =
          if span
            "L#{span.begin}-L#{span.end}"
          else
            "operation-#{runtime_session.operations.count}"
          end

        "document[0] > fenced_code_block[#{suffix}]"
      end

      def runtime_surface_span(node)
        position = node_source_position(node)
        start_line = position&.dig(:start_line)
        end_line = position&.dig(:end_line)
        return unless start_line && end_line

        start_line..end_line
      end

      def node_source_position(node)
        raw_node = unwrap_code_block_node(node)
        raw_node&.source_position
      rescue NoMethodError
        nil
      end

      def build_runtime_delegates
        [
          Ast::Merge::Runtime::Delegate.new(
            name: 'markdown-code-block-inner-merge',
            priority: 100,
            surface_kinds: [:markdown_fenced_code_block],
            languages: mergers.keys,
            capabilities: { merge: [:markdown_fenced_code_block] },
            merge: method(:merge_runtime_surface),
            metadata: {
              source: :markdown_merge,
              languages: mergers.keys.sort
            }
          )
        ]
      end

      def merge_runtime_surface(operation:, session:)
        result = perform_code_block_merge(
          language: operation.surface.effective_language,
          template_content: operation.options[:template_content].to_s,
          dest_content: operation.options[:destination_content].to_s,
          preference: operation.options[:preference],
          reference_node: operation.options[:reference_node],
          add_template_only_nodes: operation.options.fetch(:add_template_only_nodes, false),
          resolution_mode: operation.options[:resolution_mode],
          unresolved_policy: operation.options[:unresolved_policy]
        )

        if result[:merged]
          Ast::Merge::Runtime::ChildResult.new(
            replacement_text: result[:content],
            diagnostics: operation.diagnostics,
            capabilities_used: %i[delegated_child_merge language_specific_merge],
            capabilities_missing: [],
            unresolved_cases: result[:unresolved_cases] || [],
            metadata: {
              merged: true,
              stats: result[:stats] || {},
              language: operation.surface.effective_language,
              delegate_name: operation.delegate_name,
              session_policy: session.policy_context
            }.merge(result[:metadata] || {})
          )
        else
          operation.add_diagnostic(
            Ast::Merge::Runtime::Diagnostic.new(
              severity: :warn,
              kind: :delegated_merge_declined,
              operation_id: operation.operation_id,
              surface_path: operation.surface.address,
              message: result[:reason].to_s,
              metadata: {
                language: operation.surface.effective_language
              }
            )
          )

          Ast::Merge::Runtime::ChildResult.new(
            replacement_text: '',
            diagnostics: operation.diagnostics,
            capabilities_used: [:delegated_child_merge],
            capabilities_missing: [:language_specific_merge],
            metadata: {
              merged: false,
              reason: result[:reason],
              stats: result[:stats] || {},
              language: operation.surface.effective_language,
              delegate_name: operation.delegate_name,
              session_policy: session.policy_context
            }.merge(result[:metadata] || {})
          )
        end
      end

      def perform_code_block_merge(language:, template_content:, dest_content:, preference:, reference_node:, **opts)
        return not_merged('no language specified') unless language

        merger = @mergers[language.to_s.downcase]
        return not_merged("no merger for language: #{language}") unless merger

        if template_content == dest_content
          return {
            merged: true,
            content: rebuild_code_block(language, dest_content, reference_node),
            stats: { decision: :identical }
          }
        end

        begin
          result = merger.call(template_content, dest_content, preference, nested_mergers: @mergers, **opts)
          if result[:merged]
            metadata = (result[:metadata] || {}).dup
            metadata[:root_apply_candidates_by_case_id] = root_apply_candidates_by_case_id(
              merger: merger,
              unresolved_cases: result[:unresolved_cases],
              language: language,
              template_content: template_content,
              dest_content: dest_content,
              preference: preference,
              reference_node: reference_node,
              **opts
            )
            metadata[:delegated_apply_renderer] = delegated_apply_renderer(
              merger: merger,
              language: language,
              template_content: template_content,
              dest_content: dest_content,
              preference: preference,
              reference_node: reference_node,
              **opts
            )
            {
              merged: true,
              content: rebuild_code_block(language, result[:content], reference_node),
              stats: result[:stats] || {},
              unresolved_cases: result[:unresolved_cases] || [],
              metadata: metadata
            }
          else
            not_merged(result[:reason] || 'merger declined').merge(
              stats: result[:stats] || {},
              metadata: result[:metadata] || {}
            )
          end
        rescue LoadError => e
          not_merged("merger gem not available: #{e.message}")
        rescue TreeHaver::Error => e
          not_merged("backend not available: #{e.message}")
        rescue StandardError => e
          if defined?(::Prism::Merge::ParseError) && e.is_a?(::Prism::Merge::ParseError)
            not_merged("Ruby parse error: #{e.message}")
          else
            not_merged("merge failed: #{e.class}: #{e.message}")
          end
        end
      end

      def unsupported_runtime_reason_for(surface)
        language = surface.effective_language || surface.declared_language
        return 'no language specified' unless language

        "no merger for language: #{language}"
      end

      def root_apply_candidates_by_case_id(merger:, unresolved_cases:, language:, template_content:, dest_content:,
                                           preference:, reference_node:, **opts)
        cases = Array(unresolved_cases)
        return {} unless cases.one?

        resolution_case = cases.first
        {
          resolution_case.case_id => {
            template: rebuild_code_block(
              language,
              merged_delegate_content_for(
                merger: merger,
                template_content: template_content,
                dest_content: dest_content,
                preference: preference,
                case_id: resolution_case.case_id,
                selection: :template,
                **opts
              ),
              reference_node
            ),
            destination: rebuild_code_block(
              language,
              merged_delegate_content_for(
                merger: merger,
                template_content: template_content,
                dest_content: dest_content,
                preference: preference,
                case_id: resolution_case.case_id,
                selection: :destination,
                **opts
              ),
              reference_node
            )
          }
        }
      end

      def delegated_apply_renderer(merger:, language:, template_content:, dest_content:, preference:, reference_node:,
                                   **opts)
        lambda do |selections|
          delegated_result = delegated_merge_result_for(
            merger: merger,
            template_content: template_content,
            dest_content: dest_content,
            preference: preference,
            apply_unresolved_resolutions: selections,
            **opts
          )
          {
            content: rebuild_code_block(language, delegated_result[:content].to_s, reference_node),
            unresolved_cases: delegated_result[:unresolved_cases] || [],
            metadata: delegated_result[:metadata] || {}
          }
        end
      end

      def merged_delegate_content_for(merger:, template_content:, dest_content:, preference:, case_id: nil, selection: nil,
                                      apply_unresolved_resolutions: nil, **opts)
        delegated_merge_result_for(
          merger: merger,
          template_content: template_content,
          dest_content: dest_content,
          preference: preference,
          case_id: case_id,
          selection: selection,
          apply_unresolved_resolutions: apply_unresolved_resolutions,
          **opts
        )[:content].to_s
      end

      def delegated_merge_result_for(merger:, template_content:, dest_content:, preference:, case_id: nil, selection: nil,
                                     apply_unresolved_resolutions: nil, **opts)
        merger.call(
          template_content,
          dest_content,
          preference,
          **opts,
          apply_unresolved_resolutions: apply_unresolved_resolutions || { case_id => selection }
        )
      end

      # Extract language from a code block node.
      #
      # @param node [Object] The code block node
      # @return [String, nil] The language identifier
      def extract_language(node)
        raw_node = unwrap_code_block_node(node)
        info = safe_code_block_value(raw_node, :fence_info)
        return if info.nil? || info.empty?

        # fence_info may contain additional info after the language (e.g., "ruby linenos")
        info.split(/\s+/).first
      end

      # Extract content from a code block node.
      #
      # @param node [Object] The code block node
      # @return [String] The code content
      def extract_content(node)
        raw_node = unwrap_code_block_node(node)
        safe_code_block_value(raw_node, :string_content, :text).to_s
      end

      # Rebuild a fenced code block with merged content.
      #
      # @param language [String] The language identifier
      # @param content [String] The merged content
      # @param reference_node [Object] Node to copy fence style from
      # @return [String] The reconstructed code block
      def rebuild_code_block(language, content, _reference_node)
        # Ensure content ends with newline for proper fence closing
        content = content.chomp + "\n" unless content.end_with?("\n")

        # Use backticks as default fence
        fence = '```'

        "#{fence}#{language}\n#{content}#{fence}\n"
      end

      # Return a not-merged result.
      #
      # @param reason [String] Why merge was not performed
      # @return [Hash] Not-merged result hash
      def not_merged(reason)
        { merged: false, reason: reason }
      end

      def unwrap_code_block_node(node)
        return node unless defined?(Ast::Merge::NodeTyping::Wrapper) && node.is_a?(Ast::Merge::NodeTyping::Wrapper)

        Ast::Merge::NodeTyping.unwrap(node)
      end

      def safe_code_block_value(node, *methods)
        methods.each do |method_name|
          return node.public_send(method_name) if node
        rescue NoMethodError
          next
        rescue Exception => e
          next if e.class.name == 'RSpec::Mocks::MockExpectationError'

          raise
        end

        nil
      end

      class << self
        # Merge Ruby code using prism-merge.
        #
        # @param template [String] Template Ruby code
        # @param dest [String] Destination Ruby code
        # @param preference [Symbol] :destination or :template
        # @return [Hash] Merge result
        # @raise [Prism::Merge::ParseError] If template or dest has syntax errors
        # @note Errors are handled by merge_code_blocks when called via DEFAULT_MERGERS
        def merge_with_prism(template, dest, preference, **opts)
          merger = ::Prism::Merge::SmartMerger.new(
            template,
            dest,
            preference: preference,
            add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
            resolution_mode: opts.fetch(:resolution_mode, :eager),
            unresolved_policy: opts[:unresolved_policy]
          )
          merge_result = merger.merge_result
          if opts[:apply_unresolved_resolutions]
            merge_result.apply_unresolved_resolutions!(opts[:apply_unresolved_resolutions])
          end

          {
            merged: true,
            content: merge_result.to_s,
            stats: merger.stats,
            unresolved_cases: merge_result.unresolved_cases
          }
        end

        # Merge YAML code using psych-merge.
        #
        # @param template [String] Template YAML code
        # @param dest [String] Destination YAML code
        # @param preference [Symbol] :destination or :template
        # @return [Hash] Merge result
        # @raise [Psych::Merge::ParseError] If template or dest has syntax errors
        # @note Errors are handled by merge_code_blocks when called via DEFAULT_MERGERS
        def merge_with_psych(template, dest, preference, **opts)
          merger = ::Psych::Merge::SmartMerger.new(
            template,
            dest,
            preference: preference,
            add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
            resolution_mode: opts.fetch(:resolution_mode, :eager),
            unresolved_policy: opts[:unresolved_policy]
          )
          merge_result = merger.merge_result
          if opts[:apply_unresolved_resolutions]
            merge_result.apply_unresolved_resolutions!(opts[:apply_unresolved_resolutions])
          end

          {
            merged: true,
            content: merge_result.to_yaml,
            stats: merger.stats,
            unresolved_cases: merge_result.unresolved_cases
          }
        end

        # Merge JSON code using json-merge.
        #
        # @param template [String] Template JSON code
        # @param dest [String] Destination JSON code
        # @param preference [Symbol] :destination or :template
        # @return [Hash] Merge result
        # @raise [Json::Merge::ParseError] If template or dest has syntax errors
        # @note Errors are handled by merge_code_blocks when called via DEFAULT_MERGERS
        def merge_with_json(template, dest, preference, **opts)
          merger = ::Json::Merge::SmartMerger.new(
            template,
            dest,
            preference: preference,
            add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
            resolution_mode: opts.fetch(:resolution_mode, :eager),
            unresolved_policy: opts[:unresolved_policy]
          )
          merge_result = merger.merge_result
          if opts[:apply_unresolved_resolutions]
            merge_result.apply_unresolved_resolutions!(opts[:apply_unresolved_resolutions])
          end

          {
            merged: true,
            content: merge_result.to_json,
            stats: merger.stats,
            unresolved_cases: merge_result.unresolved_cases
          }
        end

        # Merge Markdown code using markdown-merge.
        #
        # @param template [String] Template Markdown code
        # @param dest [String] Destination Markdown code
        # @param preference [Symbol] :destination or :template
        # @return [Hash] Merge result
        def merge_with_markdown(template, dest, preference, **opts)
          nested_code_block_merger = CodeBlockMerger.new(
            mergers: opts.fetch(:nested_mergers, {}),
            enabled: opts.fetch(:inner_merge_code_blocks, true)
          )
          merger = ::Markdown::Merge::SmartMerger.new(
            template,
            dest,
            preference: preference,
            add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
            inner_merge_code_blocks: nested_code_block_merger,
            resolution_mode: opts.fetch(:resolution_mode, :eager),
            unresolved_policy: opts[:unresolved_policy]
          )
          merge_result = merger.merge_result
          if opts[:apply_unresolved_resolutions]
            merge_result.apply_unresolved_resolutions!(opts[:apply_unresolved_resolutions])
          end

          {
            merged: true,
            content: merge_result.to_s,
            stats: merger.stats,
            unresolved_cases: merge_result.unresolved_cases,
            metadata: {
              nested_runtime_session: merger.runtime_session&.to_h
            }
          }
        end

        # Merge TOML code using toml-merge.
        #
        # @param template [String] Template TOML code
        # @param dest [String] Destination TOML code
        # @param preference [Symbol] :destination or :template
        # @return [Hash] Merge result
        # @raise [Toml::Merge::ParseError] If template or dest has syntax errors
        # @note Errors are handled by merge_code_blocks when called via DEFAULT_MERGERS
        def merge_with_toml(template, dest, preference, **opts)
          merger = ::Toml::Merge::SmartMerger.new(
            template,
            dest,
            preference: preference,
            add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
            resolution_mode: opts.fetch(:resolution_mode, :eager),
            unresolved_policy: opts[:unresolved_policy]
          )
          merge_result = merger.merge_result
          if opts[:apply_unresolved_resolutions]
            merge_result.apply_unresolved_resolutions!(opts[:apply_unresolved_resolutions])
          end

          {
            merged: true,
            content: merge_result.to_toml,
            stats: merger.stats,
            unresolved_cases: merge_result.unresolved_cases
          }
        end
      end
    end
  end
end
