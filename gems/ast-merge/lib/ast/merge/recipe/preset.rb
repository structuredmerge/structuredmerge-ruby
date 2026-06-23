# frozen_string_literal: true

require 'yaml'

module Ast
  module Merge
    module Recipe
      # Base configuration for merge presets.
      #
      # A Preset provides merge configuration (signature generators, node typing,
      # preferences) without requiring a template file. This is useful for
      # defining reusable merge behaviors that can be applied to any merge operation.
      #
      # `Config` inherits from `Preset` and adds template/target file handling
      # for standalone recipe execution.
      #
      # @example Loading a preset
      #   preset = Preset.load("presets/gemfile.yml")
      #   merger = Prism::Merge::SmartMerger.new(
      #     template, destination,
      #     **preset.to_h
      #   )
      #
      # @example Creating a preset programmatically
      #   preset = Preset.new(
      #     "name" => "my_preset",
      #     "merge" => { "preference" => "template" }
      #   )
      #
      # @see Config For full recipe with template/target support
      # @see ScriptLoader For loading Ruby scripts from companion folders
      class Preset
        # @return [String] Preset name
        attr_reader :name

        # @return [String, nil] Preset description
        attr_reader :description

        # @return [Symbol] Parser to use (:prism, :markly, :psych, etc.)
        attr_reader :parser

        # @return [Hash] Merge configuration
        attr_reader :merge_config

        # @return [String, nil] Freeze token for preserving sections
        attr_reader :freeze_token

        # @return [String, nil] Path to the preset file (for script resolution)
        attr_reader :preset_path

        # @return [Boolean] Whether the parser was explicitly configured in YAML/hash input
        attr_reader :parser_explicit

        class << self
          # Load a preset from a YAML file.
          #
          # @param path [String] Path to the preset YAML file
          # @return [Preset]
          # @raise [ArgumentError] If file not found
          def load(path)
            raise ArgumentError, "Preset file not found: #{path}" unless File.exist?(path)

            yaml = YAML.safe_load_file(path, permitted_classes: [Regexp, Symbol])
            new(yaml, preset_path: path)
          end
        end

        # Initialize a preset from a hash.
        #
        # @param config [Hash] Parsed YAML config or programmatic config
        # @param preset_path [String, nil] Path to preset file (for script resolution)
        def initialize(config, preset_path: nil)
          @preset_path = preset_path
          @name = config['name'] || 'unnamed'
          @description = config['description']
          @parser_explicit = config.key?('parser') || config.key?(:parser)
          @parser = (config['parser'] || config[:parser] || 'prism').to_sym
          @merge_config = parse_merge_config(config['merge'] || {})
          @freeze_token = config['freeze_token']
        end

        # Whether the parser was explicitly configured.
        #
        # This lets callers distinguish between the recipe model's internal
        # default (`:prism`) and a parser choice the recipe author intended the
        # stock runner to honor automatically.
        #
        # @return [Boolean]
        def parser_explicit?
          parser_explicit == true
        end

        # Get the merge preference setting.
        #
        # @return [Symbol, Hash] Preference (:template, :destination, or per-type hash)
        def preference
          merge_config[:preference] || :template
        end

        # Get the add_missing setting, loading as callable if it's a script reference.
        #
        # @return [Boolean, Proc] Boolean value or callable filter
        def add_missing
          value = merge_config[:add_missing]
          return true if value.nil?
          return value if [true, false].include?(value)
          return value if value.respond_to?(:call)

          # It's a script reference - load it
          script_loader.load_callable(value)
        end

        # Convenience alias for boolean check.
        #
        # @return [Boolean, Proc]
        def add_missing?
          add_missing
        end

        # Get the signature_generator callable, loading from script if needed.
        #
        # @return [Proc, nil] Signature generator callable
        def signature_generator
          value = merge_config[:signature_generator]
          return if value.nil?
          return value if value.respond_to?(:call)

          script_loader.load_callable(value)
        end

        # Get the node_typing configuration with callables loaded.
        #
        # @return [Hash, nil] Hash of type => callable
        def node_typing
          value = merge_config[:node_typing]
          return if value.nil?
          return value if value.is_a?(Hash) && value.values.all? { |v| v.respond_to?(:call) }

          script_loader.load_callable_hash(value)
        end

        # Get the match_refiner callable, loading from script if needed.
        #
        # @return [Object, nil] Match refiner instance or callable
        def match_refiner
          value = merge_config[:match_refiner]
          return if value.nil?
          return value if value.respond_to?(:call) || value.is_a?(Ast::Merge::MatchRefinerBase)

          script_loader.load_callable(value)
        end

        # Get the normalize_whitespace setting.
        #
        # This is a format-specific post-processing option forwarded to mergers
        # that explicitly support it (currently markdown-family recipe flows).
        #
        # @return [Boolean]
        def normalize_whitespace
          merge_config[:normalize_whitespace] == true
        end

        # Get the rehydrate_link_references setting.
        #
        # @return [Boolean] Whether to convert inline links to reference style
        def rehydrate_link_references
          merge_config[:rehydrate_link_references] == true
        end

        # Convert preset to a hash suitable for SmartMerger options.
        #
        # @return [Hash]
        def to_h
          {
            preference: preference,
            add_template_only_nodes: add_missing,
            signature_generator: signature_generator,
            node_typing: node_typing,
            match_refiner: match_refiner,
            freeze_token: freeze_token,
            normalize_whitespace: normalize_whitespace,
            rehydrate_link_references: rehydrate_link_references
          }.compact
        end

        # Get the script loader instance.
        #
        # @return [ScriptLoader]
        def script_loader
          @script_loader ||= ScriptLoader.new(recipe_path: preset_path)
        end

        protected

        def parse_merge_config(config)
          {
            preference: parse_preference(config['preference']),
            add_missing: config['add_missing'],
            replace_mode: config['replace_mode'] == true,
            match_by: Array(config['match_by']).map(&:to_sym),
            deep: config['deep'] == true,
            signature_generator: config['signature_generator'],
            node_typing: config['node_typing'],
            match_refiner: config['match_refiner'],
            normalize_whitespace: config['normalize_whitespace'] == true,
            rehydrate_link_references: config['rehydrate_link_references'] == true
          }
        end

        def parse_preference(pref)
          return :template if pref.nil?
          return pref.to_sym if pref.is_a?(String)

          # Hash of type => preference
          pref.transform_keys(&:to_sym).transform_values(&:to_sym) if pref.is_a?(Hash)
        end
      end
    end
  end
end
