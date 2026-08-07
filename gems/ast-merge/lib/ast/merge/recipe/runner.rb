# frozen_string_literal: true

module Ast
  module Merge
    module Recipe
      # Executes a merge recipe against target files.
      #
      # The runner:
      # 1. Loads the template file
      # 2. Expands target file globs
      # 3. For each target, finds the injection point and performs the merge
      # 4. Collects results for reporting
      #
      # @example Running a recipe
      #   recipe = Recipe::Config.load(".merge-recipes/gem_family_section.yml")
      #   runner = Recipe::Runner.new(recipe, dry_run: true)
      #   results = runner.run
      #   puts runner.summary
      #
      # @example With custom parser
      #   runner = Recipe::Runner.new(recipe, parser: :markly, base_dir: "/path/to/project")
      #   results = runner.run
      #
      # @see Config For recipe configuration
      # @see ScriptLoader For loading Ruby scripts from recipe folders
      #
      class Runner
        # Result of processing a single file
        Result = Struct.new(:path, :relative_path, :status, :changed, :has_anchor, :message, :stats, :problems, :error,
                            :content, keyword_init: true)
        # Result of a single in-memory recipe step pipeline.
        #
        # @!attribute [r] content
        #   @return [String] resulting content after step execution
        # @!attribute [r] changed
        #   @return [Boolean] whether any step changed the content
        # @!attribute [r] has_anchor
        #   @return [Boolean] whether the required anchor was found
        # @!attribute [r] message
        #   @return [String, nil] human-readable status message
        # @!attribute [r] stats
        #   @return [Hash] aggregated merge statistics
        # @!attribute [r] problems
        #   @return [Array<String>] non-fatal issues collected during execution
        StepResult = Struct.new(:content, :changed, :has_anchor, :message, :stats, :problems, keyword_init: true)

        # @return [Config] The recipe being executed
        attr_reader :recipe

        # @return [Boolean] Whether this is a dry run
        attr_reader :dry_run

        # @return [String] Base directory for path resolution
        attr_reader :base_dir

        # @return [Symbol] Parser to use (:markly, :commonmarker, :prism, :psych, etc.)
        attr_reader :parser

        # @return [Array<String>, nil] Target files override (from command line)
        attr_reader :target_files

        # @return [Array<Result>] Results from the last run
        attr_reader :results

        # @return [Hash] Caller-supplied runtime context available to ruby_script steps
        attr_reader :context

        # Initialize a recipe runner.
        #
        # @param recipe [Config] The recipe to execute
        # @param dry_run [Boolean] If true, don't write files
        # @param base_dir [String, nil] Base directory for path resolution
        # @param parser [Symbol, nil] Which parser to use; when omitted, prefer an explicitly configured recipe parser, otherwise default to :markly
        # @param verbose [Boolean] Enable verbose output
        # @param target_files [Array<String>, nil] Override recipe targets with these files
        # @param context [Hash, nil] Caller-supplied runtime context for ruby_script steps
        def initialize(recipe, dry_run: false, base_dir: nil, parser: nil, verbose: false, target_files: nil,
                       context: nil, **_options)
          @recipe = recipe
          @dry_run = dry_run
          @base_dir = base_dir || Dir.pwd
          @parser = resolve_parser(parser)
          @verbose = verbose
          @target_files = target_files
          @context = normalize_runtime_context(context)
          @results = []
        end

        # Run the recipe against all target files.
        #
        # @return [Array<Result>] Results for each processed file
        def run
          @results = []
          ensure_file_recipe!

          template_content = load_template

          # Use command-line targets if provided, otherwise expand from recipe
          files_to_process = if @target_files && !@target_files.empty?
                               # Expand paths relative to base_dir
                               @target_files.map { |f| File.expand_path(f, @base_dir) }
                             else
                               # Let the recipe expand targets from its own location
                               recipe.expand_targets
                             end

          files_to_process.each do |target_path|
            result = process_file(target_path, template_content)
            @results << result
            yield result if block_given?
          end

          @results
        end

        # Run the recipe against caller-provided content instead of on-disk files.
        #
        # This is the execution path for content-only recipes that omit
        # template/target bindings from YAML and expect the caller to provide the
        # template and destination strings directly.
        #
        # @param template_content [String] Source/template content for the recipe
        # @param destination_content [String] Existing destination content
        # @param target_path [String, nil] Optional synthetic path for reporting
        # @param relative_path [String, nil] Optional synthetic relative path for reporting
        # @param context [Hash, nil] Optional per-call runtime context merged into runner context
        # @return [Result]
        def run_content(template_content:, destination_content:, target_path: nil, relative_path: nil, context: nil,
                        **_options)
          @results = [process_file_steps(
            target_path || relative_path || '(memory)',
            relative_path || target_path || '(memory)',
            template_content,
            destination_content,
            write_changes: false,
            context: runtime_context(context)
          )]
          yield @results.first if block_given?
          @results.first
        end

        # Get results grouped by status.
        #
        # @return [Hash<Symbol, Array<Result>>]
        def results_by_status
          @results.group_by(&:status)
        end

        # Get a summary hash of the run.
        #
        # @return [Hash]
        def summary
          by_status = results_by_status
          {
            total: @results.size,
            updated: (by_status[:updated] || []).size,
            would_update: (by_status[:would_update] || []).size,
            unchanged: (by_status[:unchanged] || []).size,
            skipped: (by_status[:skipped] || []).size,
            errors: (by_status[:error] || []).size
          }
        end

        # Format results as an array of hashes for TableTennis.
        #
        # @return [Array<Hash>]
        def results_table
          @results.map do |r|
            {
              file: r.relative_path,
              status: r.status.to_s,
              changed: r.changed ? 'yes' : 'no',
              message: r.message
            }
          end
        end

        # Format summary as an array of hashes for TableTennis.
        #
        # @return [Array<Hash>]
        def summary_table
          s = summary
          [
            { metric: 'Total files', value: s[:total] },
            { metric: 'Updated', value: dry_run ? s[:would_update] : s[:updated] },
            { metric: 'Unchanged', value: s[:unchanged] },
            { metric: 'Skipped (no anchor)', value: s[:skipped] },
            { metric: 'Errors', value: s[:errors] }
          ]
        end

        private

        def ensure_file_recipe!
          return unless recipe.respond_to?(:file_recipe?)
          return if recipe.file_recipe?

          raise ArgumentError, 'Recipe has no template path; use run_content for content-only recipes'
        end

        def load_template
          # Let the recipe resolve the template path from its own location
          path = recipe.template_absolute_path
          raise ArgumentError, 'Recipe has no template path; use run_content for content-only recipes' if path.nil?
          raise ArgumentError, "Template not found: #{path}" unless File.exist?(path)

          File.read(path)
        end

        def process_file(target_path, template_content)
          relative_path = make_relative(target_path)

          begin
            destination_content = File.read(target_path)
            process_file_steps(
              target_path,
              relative_path,
              template_content,
              destination_content,
              write_changes: true,
              context: runtime_context
            )
          rescue StandardError => e
            Result.new(
              path: target_path,
              relative_path: relative_path,
              status: :error,
              changed: false,
              has_anchor: false,
              message: e.message,
              error: e,
              content: destination_content
            )
          end
        end

        # Create the appropriate PartialTemplateMerger based on parser type.
        #
        # @param options [Hash] Merger options
        # @return [Object] A PartialTemplateMerger instance
        def create_partial_template_merger(**options)
          selected_parser = (options.delete(:parser) || parser).to_sym
          partial_target = options[:partial_target]
          raise ArgumentError, 'Recipe runner requires injection.anchor or injection.key_path' unless partial_target

          case selected_parser
          when :markly, :commonmarker
            unless partial_target[:kind] == :navigable
              raise ArgumentError,
                    "Parser #{selected_parser.inspect} requires a navigable partial target (injection.anchor / injection.boundary)"
            end

            require 'markdown/merge' unless defined?(Markdown::Merge)
            Markdown::Merge::PartialTemplateMerger.new(
              template: options.fetch(:template),
              destination: options.fetch(:destination),
              anchor: partial_target.fetch(:anchor),
              boundary: partial_target[:boundary],
              backend: selected_parser,
              preference: options[:preference],
              add_missing: options[:add_missing],
              when_missing: options[:when_missing],
              replace_mode: options[:replace_mode],
              signature_generator: options[:signature_generator],
              node_typing: options[:node_typing],
              match_refiner: options[:match_refiner],
              normalize_whitespace: options[:normalize_whitespace],
              rehydrate_link_references: options[:rehydrate_link_references]
            )
          when :prism
            require 'prism/merge' unless defined?(Prism::Merge)
            unless partial_target[:kind] == :navigable
              raise ArgumentError,
                    'Parser :prism currently requires a navigable partial target (injection.anchor / injection.boundary)'
            end

            Prism::Merge::PartialTemplateMerger.new(
              template: options.fetch(:template),
              destination: options.fetch(:destination),
              anchor: partial_target.fetch(:anchor),
              boundary: partial_target[:boundary],
              preference: options[:preference],
              add_missing: options[:add_missing],
              when_missing: options[:when_missing],
              replace_mode: options[:replace_mode],
              signature_generator: options[:signature_generator],
              node_typing: options[:node_typing],
              match_refiner: options[:match_refiner]
            )
          when :psych
            require 'psych/merge' unless defined?(Psych::Merge)
            unless partial_target[:kind] == :key_path
              raise ArgumentError, 'Parser :psych currently requires injection.key_path'
            end

            key_path = partial_target[:key_path]
            raise ArgumentError, 'Psych partial merge requires injection.key_path' if key_path.nil? || key_path.empty?

            Psych::Merge::PartialTemplateMerger.new(
              template: options.fetch(:template),
              destination: options.fetch(:destination),
              key_path: key_path,
              preference: options[:preference],
              add_missing: options[:add_missing],
              when_missing: options[:when_missing]
            )
          else
            raise ArgumentError, "Unknown parser: #{selected_parser}. Supported: :markly, :commonmarker, :prism, :psych"
          end
        end

        def create_smart_merger(**options)
          selected_parser = (options.delete(:parser) || parser).to_sym

          case selected_parser
          when :markly, :commonmarker
            require 'markdown/merge' unless defined?(Markdown::Merge)
            Markdown::Merge::SmartMerger.new(
              options.fetch(:template),
              options.fetch(:destination),
              backend: selected_parser,
              preference: options[:preference],
              add_template_only_nodes: options[:add_missing],
              signature_generator: options[:signature_generator],
              node_typing: options[:node_typing],
              match_refiner: options[:match_refiner],
              freeze_token: recipe.freeze_token,
              normalize_whitespace: options[:normalize_whitespace],
              rehydrate_link_references: options[:rehydrate_link_references]
            )
          when :prism
            require 'prism/merge' unless defined?(Prism::Merge)
            Prism::Merge::SmartMerger.new(
              options.fetch(:template),
              options.fetch(:destination),
              preference: options[:preference],
              add_template_only_nodes: options[:add_missing],
              signature_generator: options[:signature_generator],
              node_typing: options[:node_typing],
              match_refiner: options[:match_refiner],
              freeze_token: recipe.freeze_token
            )
          when :psych
            require 'psych/merge' unless defined?(Psych::Merge)
            Psych::Merge::SmartMerger.new(
              options.fetch(:template),
              options.fetch(:destination),
              preference: options[:preference],
              add_template_only_nodes: options[:add_missing],
              signature_generator: options[:signature_generator],
              node_typing: options[:node_typing],
              match_refiner: options[:match_refiner],
              freeze_token: recipe.freeze_token
            )
          else
            raise ArgumentError,
                  "Unknown parser: #{selected_parser}. Supported smart-merge parsers: :markly, :commonmarker, :prism, :psych"
          end
        end

        def merge_target_found?(result)
          return result.section_found? if result.respond_to?(:section_found?)
          return result.key_path_found? if result.respond_to?(:key_path_found?)
          return result.has_section if result.respond_to?(:has_section)
          return result.has_key_path if result.respond_to?(:has_key_path)

          raise ArgumentError, "Unsupported partial merge result: #{result.class}"
        end

        def process_file_steps(target_path, relative_path, template_content, destination_content, write_changes:,
                               context:)
          current_content = destination_content
          step_results = []

          recipe.execution_steps.each_with_index do |step, index|
            step_result = execute_step(
              step,
              step_index: index,
              target_path: target_path,
              relative_path: relative_path,
              template_content: template_content,
              destination_content: destination_content,
              current_content: current_content,
              context: context
            )

            step_results << step_result
            current_content = step_result.content
          end

          create_result_from_steps(
            target_path: target_path,
            relative_path: relative_path,
            original_content: destination_content,
            final_content: current_content,
            step_results: step_results,
            write_changes: write_changes
          )
        end

        def execute_step(step, step_index:, target_path:, relative_path:, template_content:, destination_content:,
                         current_content:, context:)
          case step[:kind]
          when :partial_merge
            execute_partial_merge_step(step, template_content: template_content, current_content: current_content)
          when :smart_merge
            execute_smart_merge_step(step, template_content: template_content, current_content: current_content)
          when :ruby_script
            execute_ruby_script_step(
              step,
              step_index: step_index,
              target_path: target_path,
              relative_path: relative_path,
              template_content: template_content,
              destination_content: destination_content,
              current_content: current_content,
              context: context
            )
          else
            raise ArgumentError, "Unsupported recipe step kind: #{step[:kind].inspect}"
          end
        end

        def execute_partial_merge_step(step, template_content:, current_content:)
          merge_options = resolved_step_merge_config(step)
          merger = create_partial_template_merger(
            parser: step[:parser],
            template: template_content,
            destination: current_content,
            partial_target: step[:partial_target],
            preference: merge_options[:preference],
            add_missing: merge_options[:add_missing],
            when_missing: step[:when_missing],
            replace_mode: merge_options[:replace_mode],
            signature_generator: merge_options[:signature_generator],
            node_typing: merge_options[:node_typing],
            match_refiner: merge_options[:match_refiner],
            normalize_whitespace: merge_options[:normalize_whitespace],
            rehydrate_link_references: merge_options[:rehydrate_link_references]
          )

          result = merger.merge
          StepResult.new(
            content: result.content,
            changed: result.changed,
            has_anchor: merge_target_found?(result),
            message: result.message,
            stats: result.stats,
            problems: result.respond_to?(:problems) ? result.problems : nil
          )
        end

        def execute_smart_merge_step(step, template_content:, current_content:)
          merge_options = resolved_step_merge_config(step)
          merger = create_smart_merger(
            parser: step[:parser],
            template: template_content,
            destination: current_content,
            preference: merge_options[:preference],
            add_missing: merge_options[:add_missing],
            signature_generator: merge_options[:signature_generator],
            node_typing: merge_options[:node_typing],
            match_refiner: merge_options[:match_refiner],
            normalize_whitespace: merge_options[:normalize_whitespace],
            rehydrate_link_references: merge_options[:rehydrate_link_references]
          )

          normalize_smart_merge_result(merger, original_content: current_content)
        end

        def execute_ruby_script_step(step, step_index:, target_path:, relative_path:, template_content:,
                                     destination_content:, current_content:, context:)
          callable = recipe.script_loader.load_step_callable(step[:script])
          result = callable.call(
            content: current_content,
            template_content: template_content,
            destination_content: destination_content,
            target_path: target_path,
            relative_path: relative_path,
            recipe: recipe,
            runner: self,
            step: step,
            step_index: step_index,
            parser: step[:parser] || parser,
            context: context
          )

          normalize_script_step_result(result, original_content: current_content)
        end

        def normalize_smart_merge_result(merger, original_content:)
          if merger.respond_to?(:merge_result)
            merge_result = merger.merge_result
            raw_content = merge_result.respond_to?(:content) ? merge_result.content : nil
            content = raw_content.is_a?(String) ? raw_content : merge_result.to_s
            stats = if merge_result.respond_to?(:stats)
                      merge_result.stats
                    else
                      (merger.respond_to?(:stats) ? merger.stats : {})
                    end
            problems = merge_result.respond_to?(:problems) ? merge_result.problems : nil
          else
            content = merger.merge.to_s
            stats = merger.respond_to?(:stats) ? merger.stats : {}
            problems = nil
          end

          StepResult.new(
            content: content,
            changed: content != original_content,
            has_anchor: true,
            message: content != original_content ? 'Smart merge updated content' : 'Smart merge made no changes',
            stats: stats,
            problems: problems
          )
        end

        def normalize_script_step_result(result, original_content:)
          if result.is_a?(String)
            return StepResult.new(
              content: result,
              changed: result != original_content,
              has_anchor: true,
              message: result != original_content ? 'Script step updated content' : 'Script step made no changes',
              stats: {}
            )
          end

          if result.is_a?(Hash)
            content = result[:content] || result['content']
            raise ArgumentError, 'ruby_script step results must include :content' if content.nil?

            changed = if result.key?(:changed) || result.key?('changed')
                        result.key?(:changed) ? result[:changed] : result['changed']
                      else
                        content != original_content
                      end

            return StepResult.new(
              content: content,
              changed: changed,
              has_anchor: if result.key?(:has_anchor)
                            result[:has_anchor]
                          else
                            (result.key?('has_anchor') ? result['has_anchor'] : true)
                          end,
              message: result[:message] || result['message'] || (changed ? 'Script step updated content' : 'Script step made no changes'),
              stats: result[:stats] || result['stats'] || {},
              problems: result[:problems] || result['problems']
            )
          end

          if result.respond_to?(:content)
            content = result.content
            changed = result.respond_to?(:changed) ? result.changed : (content != original_content)
            has_anchor = if result.respond_to?(:section_found?) || result.respond_to?(:key_path_found?) || result.respond_to?(:has_section) || result.respond_to?(:has_key_path)
                           merge_target_found?(result)
                         else
                           true
                         end

            return StepResult.new(
              content: content,
              changed: changed,
              has_anchor: has_anchor,
              message: result.respond_to?(:message) ? result.message : nil,
              stats: result.respond_to?(:stats) ? result.stats : {},
              problems: result.respond_to?(:problems) ? result.problems : nil
            )
          end

          raise ArgumentError, 'ruby_script step must return a String, Hash, or object responding to #content'
        end

        def runtime_context(override = nil)
          return context if override.nil?

          context.merge(normalize_runtime_context(override))
        end

        def normalize_runtime_context(value)
          return {} if value.nil?

          raise ArgumentError, 'Recipe runner context must be a Hash-like object' unless value.respond_to?(:to_h)

          value.to_h.transform_keys do |key|
            key.respond_to?(:to_sym) ? key.to_sym : key
          end
        end

        def resolved_step_merge_config(step)
          config = step[:merge_config] || recipe.merge_config

          {
            preference: config[:preference] || :template,
            add_missing: resolve_add_missing(config[:add_missing]),
            replace_mode: config[:replace_mode] == true,
            signature_generator: resolve_callable(config[:signature_generator]),
            node_typing: resolve_callable_hash(config[:node_typing]),
            match_refiner: resolve_match_refiner(config[:match_refiner]),
            normalize_whitespace: config[:normalize_whitespace] == true,
            rehydrate_link_references: config[:rehydrate_link_references] == true
          }
        end

        def resolve_add_missing(value)
          return true if value.nil?
          return value if [true, false].include?(value)
          return value if value.respond_to?(:call)

          recipe.script_loader.load_callable(value)
        end

        def resolve_callable(value)
          return if value.nil?
          return value if value.respond_to?(:call)

          recipe.script_loader.load_callable(value)
        end

        def resolve_callable_hash(value)
          return if value.nil?
          return value if value.is_a?(Hash) && value.values.all? { |callable| callable.respond_to?(:call) }

          recipe.script_loader.load_callable_hash(value)
        end

        def resolve_match_refiner(value)
          return if value.nil?
          return value if value.respond_to?(:call) || value.is_a?(Ast::Merge::MatchRefinerBase)

          recipe.script_loader.load_callable(value)
        end

        def create_result_from_steps(target_path:, relative_path:, original_content:, final_content:, step_results:,
                                     write_changes:)
          changed = if step_results.size == 1
                      step_results.first.changed
                    else
                      final_content != original_content
                    end
          problems = step_results.filter_map(&:problems)
          problems = problems.size == 1 ? problems.first : problems unless problems.empty?
          combined_stats = if step_results.size == 1
                             step_results.first.stats
                           else
                             { steps: step_results.map(&:stats) }
                           end
          has_anchor = step_results.any?(&:has_anchor)
          message = step_results.reverse.find do |step_result|
            step_result.message && !step_result.message.empty?
          end&.message

          if changed
            File.write(target_path, final_content) if write_changes && !dry_run

            Result.new(
              path: target_path,
              relative_path: relative_path,
              status: dry_run ? :would_update : :updated,
              changed: true,
              has_anchor: has_anchor,
              message: if step_results.size > 1
                         message || (dry_run ? 'Would update' : 'Updated')
                       elsif has_anchor
                         dry_run ? 'Would update' : 'Updated'
                       else
                         message || 'No matching anchor found'
                       end,
              content: final_content,
              stats: combined_stats,
              problems: problems
            )
          elsif has_anchor
            Result.new(
              path: target_path,
              relative_path: relative_path,
              status: :unchanged,
              changed: false,
              has_anchor: true,
              message: 'No changes needed',
              content: final_content,
              stats: combined_stats,
              problems: problems
            )
          else
            Result.new(
              path: target_path,
              relative_path: relative_path,
              status: :skipped,
              changed: false,
              has_anchor: false,
              message: message || 'No matching anchor found',
              content: final_content,
              stats: combined_stats,
              problems: problems
            )
          end
        end

        def resolve_parser(parser_override)
          return parser_override.to_sym if parser_override
          return recipe.parser.to_sym if recipe.respond_to?(:parser_explicit?) && recipe.parser_explicit?

          :markly
        end

        def make_relative(path)
          # Try to make path relative to base_dir first
          return path.sub("#{base_dir}/", '') if path.start_with?(base_dir)

          # If recipe has a path, try relative to recipe's parent directory
          if recipe.recipe_path
            recipe_base = File.dirname(recipe.recipe_path, 2)
            return path.sub("#{recipe_base}/", '') if path.start_with?(recipe_base)
          end

          # Fall back to the path itself
          path
        end
      end
    end
  end
end
