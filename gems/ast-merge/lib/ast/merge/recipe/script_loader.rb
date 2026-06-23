# frozen_string_literal: true

module Ast
  module Merge
    module Recipe
      # Loads Ruby scripts referenced by a recipe from a companion folder.
      #
      # Convention: A recipe at `.merge-recipes/my_recipe.yml` can reference
      # scripts in `.merge-recipes/my_recipe/` folder.
      #
      # Scripts must define a callable object (lambda, proc, or object with #call method).
      #
      # @example Script reference in recipe YAML
      #   merge:
      #     signature_generator: scripts/signature_generator.rb
      #     node_typing:
      #       heading: scripts/heading_typing.rb
      #     add_missing: scripts/add_missing_filter.rb
      #
      # @example Script file content (signature_generator.rb)
      #   # Must return a callable
      #   lambda do |node|
      #     text = node.respond_to?(:to_plaintext) ? node.to_plaintext.to_s : node.to_s
      #     if text.include?("gem family")
      #       [:gem_family, :section]
      #     else
      #       nil
      #     end
      #   end
      #
      # @see Config For recipe configuration
      # @see Runner For recipe execution
      #
      class ScriptLoader
        # @return [String, nil] Base directory for script resolution
        attr_reader :base_dir

        # @return [Hash] Cache of loaded scripts
        attr_reader :script_cache

        # Initialize a script loader.
        #
        # @param recipe_path [String, nil] Path to recipe file (determines script folder)
        # @param base_dir [String, nil] Override base directory for scripts
        def initialize(recipe_path: nil, base_dir: nil)
          @base_dir = determine_base_dir(recipe_path, base_dir)
          @script_cache = {}
        end

        # Load a callable from a script reference.
        #
        # @param reference [String, Proc, nil] Script path, inline expression, or existing callable
        # @return [Proc, nil] The callable, or nil if reference is nil
        # @raise [ArgumentError] If script not found or doesn't return a callable
        def load_callable(reference)
          return if reference.nil?
          return reference if reference.respond_to?(:call)

          # Check if it's an inline lambda expression
          return evaluate_inline_expression(reference) if inline_expression?(reference)

          # It's a file path reference
          load_script_file(reference)
        end

        # Load a callable used by an explicit recipe `ruby_script` step.
        #
        # This is currently an alias of `#load_callable`, but kept separate so
        # the step-script contract can evolve without conflating it with merge
        # option callables like `signature_generator` or `add_missing`.
        #
        # @param reference [String, Proc, nil]
        # @return [Proc, nil]
        def load_step_callable(reference)
          load_callable(reference)
        end

        # Load a hash of callables (e.g., node_typing config).
        #
        # @param config [Hash, nil] Hash with script references as values
        # @return [Hash, nil] Hash with callables as values
        def load_callable_hash(config)
          return if config.nil? || config.empty?

          config.transform_values { |ref| load_callable(ref) }
        end

        # Check if scripts directory exists.
        #
        # @return [Boolean]
        def scripts_available?
          !!(base_dir && Dir.exist?(base_dir))
        end

        # List available scripts.
        #
        # @return [Array<String>] Script filenames
        def available_scripts
          return [] unless scripts_available?

          Dir.glob(File.join(base_dir, '**/*.rb')).map do |path|
            path.sub("#{base_dir}/", '')
          end
        end

        private

        def determine_base_dir(recipe_path, override_base_dir)
          return override_base_dir if override_base_dir

          return unless recipe_path

          # Convention: scripts folder has same name as recipe (without extension)
          recipe_dir = File.dirname(recipe_path)
          recipe_basename = File.basename(recipe_path, '.*')
          scripts_dir = File.join(recipe_dir, recipe_basename)

          scripts_dir if Dir.exist?(scripts_dir)
        end

        def inline_expression?(reference)
          return false unless reference.is_a?(String)

          # Check for inline lambda/proc syntax
          reference.strip.start_with?('->', 'lambda', 'proc', '->(')
        end

        def evaluate_inline_expression(expression)
          # Evaluate the expression in a clean binding
          # rubocop:disable Security/Eval
          result = eval(expression, TOPLEVEL_BINDING.dup, '(inline)', 1)
          # rubocop:enable Security/Eval

          unless result.respond_to?(:call)
            raise ArgumentError, "Inline expression must return a callable, got: #{result.class}"
          end

          result
        rescue SyntaxError => e
          raise ArgumentError, "Invalid inline expression syntax: #{e.message}"
        rescue StandardError => e
          raise ArgumentError, "Failed to evaluate inline expression: #{e.message}"
        end

        def load_script_file(path)
          # Check cache first
          return script_cache[path] if script_cache.key?(path)

          absolute_path = resolve_script_path(path)

          unless File.exist?(absolute_path)
            raise ArgumentError, "Script not found: #{path} (looked in #{absolute_path})"
          end

          script_content = File.read(absolute_path)

          # Evaluate the script - it should return a callable
          # rubocop:disable Security/Eval
          result = eval(script_content, TOPLEVEL_BINDING.dup, absolute_path, 1)
          # rubocop:enable Security/Eval

          unless result.respond_to?(:call)
            raise ArgumentError,
                  "Script #{path} must return a callable (lambda, proc, or object with #call), got: #{result.class}"
          end

          # Cache and return
          script_cache[path] = result
          result
        rescue SyntaxError => e
          raise ArgumentError, "Syntax error in script #{path}: #{e.message}"
        rescue StandardError => e
          raise ArgumentError, "Failed to load script #{path}: #{e.message}"
        end

        def resolve_script_path(path)
          # If path is absolute, use it directly
          return path if File.absolute_path?(path)

          # If we have a base_dir, resolve relative to it
          if base_dir
            resolved = File.expand_path(path, base_dir)
            return resolved if File.exist?(resolved)
          end

          # Fall back to current directory
          File.expand_path(path)
        end
      end
    end
  end
end
