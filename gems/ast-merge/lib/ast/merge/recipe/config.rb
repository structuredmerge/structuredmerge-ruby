# frozen_string_literal: true

require 'yaml'

module Ast
  module Merge
    module Recipe
      # Loads and represents a merge recipe from YAML configuration.
      #
      # A recipe extends Preset with:
      # - Optional template file specification
      # - Optional target file patterns
      # - Injection point configuration
      # - when_missing behavior
      #
      # File-oriented recipes provide a template path and targets for on-disk
      # execution via Runner#run. Content-oriented recipes may omit both and be
      # executed in memory via Runner#run_content.
      #
      # @example Loading a file-oriented recipe
      #   recipe = Config.load(".merge-recipes/gem_family_section.yml")
      #   recipe.name          # => "gem_family_section"
      #   recipe.template_path # => "GEM_FAMILY_SECTION.md"
      #   recipe.targets       # => ["README.md", "vendor/*/README.md"]
      #
      # @example Recipe YAML format
      #   name: gem_family_section
      #   description: Update gem family section in README files
      #
      #   template: GEM_FAMILY_SECTION.md
      #
      #   targets:
      #     - "README.md"
      #     - "vendor/*/README.md"
      #
      #   injection:
      #     anchor:
      #       type: heading
      #       text: /Gem Family/
      #     position: replace
      #     boundary:
      #       type: heading
      #       same_or_shallower: true
      #
      #   merge:
      #     preference: template
      #     add_missing: true
      #
      #   when_missing: skip
      #
      # @see Preset For base configuration without template/targets
      # @see Runner For executing recipes
      # @see ScriptLoader For loading Ruby scripts from recipe folders
      class Config < Preset
        # @return [String, nil] Path to template file (relative to recipe or absolute)
        attr_reader :template_path

        # @return [Array<String>] Glob patterns for target files
        attr_reader :targets

        # @return [Hash] Injection point / partial target configuration
        attr_reader :injection

        # @return [Symbol] Behavior when the partial target is not found (:skip, :append, :prepend, :add)
        attr_reader :when_missing

        # @return [Array<Hash>] Normalized execution steps
        attr_reader :steps

        # Alias for compatibility - recipe_path points to the same file as preset_path
        def recipe_path
          preset_path
        end

        class << self
          # Load a recipe from a YAML file.
          #
          # @param path [String] Path to the recipe YAML file
          # @return [Config] Loaded recipe
          # @raise [ArgumentError] If file doesn't exist or is invalid
          def load(path)
            raise ArgumentError, "Recipe file not found: #{path}" unless File.exist?(path)

            yaml = YAML.safe_load_file(path, permitted_classes: [Regexp, Symbol])
            new(yaml, preset_path: path)
          end
        end

        # Create a recipe from a hash (parsed YAML or programmatic).
        #
        # @param config [Hash] Recipe configuration
        # @param preset_path [String, nil] Path to recipe file (for relative path resolution)
        # @param recipe_path [String, nil] Alias for preset_path (backward compatibility)
        def initialize(config, preset_path: nil, recipe_path: nil)
          # Support both preset_path and recipe_path for backward compatibility
          effective_path = preset_path || recipe_path
          super(config, preset_path: effective_path)

          @template_path = config['template']
          @targets = Array(config.fetch('targets', default_targets_for(@template_path)))
          @when_missing = (config['when_missing'] || 'skip').to_sym
          validate_top_level_step_contract!(config)
          @injection = parse_injection(config['injection'] || {})
          @steps = parse_steps(config['steps'])
        end

        # Get the absolute path to the template file.
        #
        # @param base_dir [String] Base directory for relative paths
        # @return [String] Absolute path to template
        def template_absolute_path(base_dir: nil)
          return if @template_path.nil?
          return @template_path if File.absolute_path?(@template_path)

          base = base_dir || (preset_path ? File.dirname(preset_path) : Dir.pwd)
          File.expand_path(@template_path, base)
        end

        # Expand target globs to actual file paths.
        #
        # @param base_dir [String] Base directory for glob expansion
        # @return [Array<String>] Absolute paths to target files
        def expand_targets(base_dir: nil)
          return [] if targets.empty?

          base = base_dir || (preset_path ? File.dirname(preset_path) : Dir.pwd)

          targets.flat_map do |pattern|
            if File.absolute_path?(pattern)
              Dir.glob(pattern)
            else
              # Expand and normalize to remove .. segments
              expanded_pattern = File.expand_path(pattern, base)
              Dir.glob(expanded_pattern)
            end
          end.uniq.sort
        end

        # Build an InjectionPointFinder query from the injection config.
        #
        # @return [Hash] Arguments for InjectionPointFinder#find
        def finder_query
          return {} unless navigable_partial_target?

          anchor = injection[:anchor] || {}
          boundary = injection[:boundary] || {}

          query = {
            type: anchor[:type],
            text: anchor[:text],
            position: injection[:position] || :replace,
            boundary_type: boundary[:type],
            boundary_text: boundary[:text]
          }

          # Support tree-depth based boundary detection
          # same_or_shallower: true means "end at next sibling (same tree level or above)"
          query[:boundary_same_or_shallower] = true if boundary[:same_or_shallower]

          query.compact
        end

        # Get the normalized partial-target contract for this recipe.
        #
        # This is the shared shape used by the stock runner to dispatch between
        # parser families without baking parser-specific YAML parsing logic into
        # the runner itself.
        #
        # @return [Hash, nil]
        def partial_target
          return if explicit_steps?

          case partial_target_kind
          when :navigable
            {
              kind: :navigable,
              anchor: injection[:anchor],
              position: injection[:position] || :replace,
              boundary: injection[:boundary]
            }.compact
          when :key_path
            {
              kind: :key_path,
              key_path: injection[:key_path]
            }
          end
        end

        # @return [Symbol, nil] The normalized target selector kind
        def partial_target_kind
          return if explicit_steps?

          return :key_path if injection[:key_path]
          return :navigable if injection[:anchor]

          nil
        end

        # @return [Boolean]
        def navigable_partial_target?
          partial_target_kind == :navigable
        end

        # @return [Boolean]
        def key_path_partial_target?
          partial_target_kind == :key_path
        end

        # @return [Boolean] Whether this recipe uses explicit step execution
        def explicit_steps?
          !@steps.empty?
        end

        # @return [Array<Hash>] Explicit steps or a synthesized legacy-compatible step
        def execution_steps
          return steps unless steps.empty?

          [legacy_implicit_step]
        end

        # Whether to use replace mode (template replaces section entirely).
        #
        # @return [Boolean]
        def replace_mode?
          merge_config[:replace_mode] == true
        end

        # @return [Boolean] Whether this recipe can be executed against files on disk.
        def file_recipe?
          !template_path.nil?
        end

        # @return [Boolean] Whether this recipe expects caller-provided content.
        def content_recipe?
          !file_recipe?
        end

        private

        STEP_KINDS = %i[partial_merge smart_merge ruby_script].freeze

        def default_targets_for(template_path)
          template_path ? ['*.md'] : []
        end

        def parse_injection(config)
          return {} if config.empty?

          anchor = parse_matcher(config['anchor'] || {})
          boundary = parse_matcher(config['boundary'] || {})
          key_path = parse_key_path(config['key_path'])
          position = config['position']

          validate_injection!(anchor: anchor, boundary: boundary, key_path: key_path, position: position)

          if key_path
            return {
              key_path: key_path
            }
          end

          result = {}
          result[:anchor] = anchor if anchor
          result[:position] = (position || 'replace').to_sym if anchor
          result[:boundary] = boundary if boundary
          result
        end

        def parse_steps(config)
          return [].freeze if config.nil?

          steps = Array(config)
          raise ArgumentError, 'Recipe steps cannot be empty' if steps.empty?

          steps.map { |step_config| parse_step(step_config) }.freeze
        end

        def parse_step(step_config)
          raise ArgumentError, 'Each recipe step must be a Hash' unless step_config.is_a?(Hash)

          kind = config_value(step_config, :kind)&.to_sym
          unless STEP_KINDS.include?(kind)
            allowed = STEP_KINDS.map(&:inspect).join(', ')
            raise ArgumentError, "Recipe step kind must be one of: #{allowed}"
          end

          step = {
            kind: kind,
            name: config_value(step_config, :name),
            parser: normalize_step_parser(step_config)
          }.compact

          case kind
          when :partial_merge
            parse_partial_merge_step!(step, step_config)
          when :smart_merge
            parse_smart_merge_step!(step, step_config)
          when :ruby_script
            parse_ruby_script_step!(step, step_config)
          end

          step.freeze
        end

        def parse_partial_merge_step!(step, step_config)
          injection = parse_injection(config_value(step_config, :injection) || {})
          partial_target = build_partial_target(injection)
          unless partial_target
            raise ArgumentError,
                  'partial_merge step requires injection.anchor or injection.key_path'
          end

          step[:partial_target] = partial_target
          step[:when_missing] = (config_value(step_config, :when_missing) || when_missing).to_sym
          step[:merge_config] =
            merge_config.merge(parse_step_merge_overrides(config_value(step_config, :merge) || {})).freeze
        end

        def parse_smart_merge_step!(step, step_config)
          step[:merge_config] =
            merge_config.merge(parse_step_merge_overrides(config_value(step_config, :merge) || {})).freeze
        end

        def parse_ruby_script_step!(step, step_config)
          script = config_value(step_config, :script)
          raise ArgumentError, 'ruby_script step requires script' if script.nil? || script.to_s.strip.empty?

          step[:script] = script
        end

        def normalize_step_parser(step_config)
          parser_value = config_value(step_config, :parser)
          return if parser_value.nil?

          parser_value.to_sym
        end

        def parse_step_merge_overrides(config)
          result = {}

          if config.key?('preference') || config.key?(:preference)
            result[:preference] = parse_preference(config_value(config, :preference))
          end
          if config.key?('add_missing') || config.key?(:add_missing)
            result[:add_missing] = config_value(config, :add_missing)
          end
          if config.key?('replace_mode') || config.key?(:replace_mode)
            result[:replace_mode] = config_value(config, :replace_mode) == true
          end
          if config.key?('match_by') || config.key?(:match_by)
            result[:match_by] = Array(config_value(config, :match_by)).map(&:to_sym)
          end
          result[:deep] = config_value(config, :deep) == true if config.key?('deep') || config.key?(:deep)
          if config.key?('signature_generator') || config.key?(:signature_generator)
            result[:signature_generator] = config_value(config, :signature_generator)
          end
          if config.key?('node_typing') || config.key?(:node_typing)
            result[:node_typing] = config_value(config, :node_typing)
          end
          if config.key?('match_refiner') || config.key?(:match_refiner)
            result[:match_refiner] = config_value(config, :match_refiner)
          end
          if config.key?('normalize_whitespace') || config.key?(:normalize_whitespace)
            result[:normalize_whitespace] = config_value(config, :normalize_whitespace) == true
          end
          if config.key?('rehydrate_link_references') || config.key?(:rehydrate_link_references)
            result[:rehydrate_link_references] = config_value(config, :rehydrate_link_references) == true
          end

          result
        end

        def build_partial_target(injection_config)
          return if injection_config.nil? || injection_config.empty?

          if injection_config[:key_path]
            {
              kind: :key_path,
              key_path: injection_config[:key_path]
            }
          elsif injection_config[:anchor]
            {
              kind: :navigable,
              anchor: injection_config[:anchor],
              position: injection_config[:position] || :replace,
              boundary: injection_config[:boundary]
            }.compact
          end
        end

        def legacy_implicit_step
          step_parser = parser_explicit? ? parser : nil

          if injection.any?
            {
              kind: :partial_merge,
              parser: step_parser,
              partial_target: build_partial_target(injection),
              when_missing: when_missing,
              merge_config: merge_config
            }.freeze
          else
            {
              kind: :smart_merge,
              parser: step_parser,
              merge_config: merge_config
            }.freeze
          end
        end

        def validate_top_level_step_contract!(config)
          return unless config.key?('steps') || config.key?(:steps)
          return unless config['injection'] || config[:injection]
          return if (config['injection'] || config[:injection]).empty?

          raise ArgumentError, 'Recipe must use either top-level injection or explicit steps, not both'
        end

        def config_value(config, key)
          return config[key.to_s] if config.key?(key.to_s)
          return config[key] if config.key?(key)

          nil
        end

        def parse_key_path(config)
          return if config.nil?

          Array(config).map do |segment|
            segment.is_a?(Symbol) ? segment.to_s : segment
          end
        end

        def parse_matcher(config)
          return if config.empty?

          {
            type: config['type']&.to_sym,
            text: parse_text_pattern(config['text']),
            level: config['level'],
            level_lte: config['level_lte'],
            level_gte: config['level_gte'],
            same_or_shallower: config['same_or_shallower'] == true
          }.compact
        end

        def parse_text_pattern(text)
          return if text.nil?
          return text if text.is_a?(Regexp)

          # Handle /regex/ syntax in YAML strings
          if text.is_a?(String) && text.start_with?('/') && text.end_with?('/')
            Regexp.new(text[1..-2])
          else
            text
          end
        end

        def validate_injection!(anchor:, boundary:, key_path:, position:)
          has_anchor = !anchor.nil?
          has_key_path = !key_path.nil?

          return unless has_anchor || has_key_path || boundary || !position.nil?

          if has_anchor && has_key_path
            raise ArgumentError,
                  'Recipe injection must choose exactly one partial target shape: anchor/boundary or key_path'
          end

          raise ArgumentError, 'Recipe injection.boundary requires injection.anchor' if boundary && !has_anchor

          raise ArgumentError, 'Recipe injection.position requires injection.anchor' if !position.nil? && !has_anchor

          return unless has_key_path && key_path.empty?

          raise ArgumentError, 'Recipe injection.key_path cannot be empty'
        end
      end
    end
  end
end
