# frozen_string_literal: true

module TreeHaver
  # Utility for finding and registering Citrus grammar gems.
  #
  # CitrusGrammarFinder provides language-agnostic discovery of Citrus grammar
  # gems. Given a language name and gem information, it attempts to load the
  # grammar and register it with tree_haver.
  #
  # Unlike tree-sitter grammars (which are .so files), Citrus grammars are
  # Ruby modules that respond to .parse(source). This class handles the
  # discovery and registration of these grammars.
  #
  # @example Basic usage with toml-rb
  #   finder = TreeHaver::CitrusGrammarFinder.new(
  #     language: :toml,
  #     gem_name: "toml-rb",
  #     grammar_const: "TomlRB::Document"
  #   )
  #   finder.register! if finder.available?
  #
  # @example With custom require path
  #   finder = TreeHaver::CitrusGrammarFinder.new(
  #     language: :json,
  #     gem_name: "json-rb",
  #     grammar_const: "JsonRB::Grammar",
  #     require_path: "json/rb"
  #   )
  #
  # @see GrammarFinder For tree-sitter grammar discovery
  class CitrusGrammarFinder
    # @return [Symbol] the language identifier
    attr_reader :language_name

    # @return [String] the gem name to require
    attr_reader :gem_name

    # @return [String] the constant path to the grammar (e.g., "TomlRB::Document")
    attr_reader :grammar_const

    # @return [String, nil] custom require path (defaults to gem_name with dashes to slashes)
    attr_reader :require_path

    # Initialize a Citrus grammar finder
    #
    # @param language [Symbol, String] the language name (e.g., :toml, :json)
    # @param gem_name [String] the gem name (e.g., "toml-rb")
    # @param grammar_const [String] constant path to grammar (e.g., "TomlRB::Document")
    # @param require_path [String, nil] custom require path (defaults to gem_name as-is)
    def initialize(language:, gem_name:, grammar_const:, require_path: nil)
      @language_name = language.to_sym
      @gem_name = gem_name
      @grammar_const = grammar_const
      @require_path = require_path || gem_name
      @load_attempted = false
      @available = false
      @grammar_module = nil
    end

    # Check if the Citrus grammar is available
    #
    # Attempts to require the gem and resolve the grammar constant.
    # Result is cached after first call.
    #
    # @return [Boolean] true if grammar is available
    def available?
      return @available if @load_attempted

      @load_attempted = true
      debug = ENV["TREE_HAVER_DEBUG"]

      # Guard against nil require_path (can happen if gem_name was nil)
      if @require_path.nil? || @require_path.empty?
        warn("CitrusGrammarFinder: require_path is nil or empty for #{@language_name}") if debug
        @available = false
        return false
      end

      begin
        # Try to require the gem
        require @require_path

        # Try to resolve the constant
        @grammar_module = resolve_constant(@grammar_const)

        # Verify it responds to parse
        unless @grammar_module.respond_to?(:parse)
          # simplecov:disable defensive - requires a gem with malformed grammar module
          # Show what methods ARE available to help diagnose the issue
          if debug
            available_methods = @grammar_module.methods(false).sort.first(20)
            warn("CitrusGrammarFinder: #{@grammar_const} doesn't respond to :parse")
            warn("CitrusGrammarFinder: #{@grammar_const}.class = #{@grammar_module.class}")
            warn("CitrusGrammarFinder: #{@grammar_const} is a #{@grammar_module.is_a?(Module) ? "Module" : "non-Module"}")
            warn("CitrusGrammarFinder: Available singleton methods (first 20): #{available_methods.inspect}")
            if @grammar_module.respond_to?(:instance_methods)
              instance_methods = @grammar_module.instance_methods(false).sort.first(20)
              warn("CitrusGrammarFinder: Available instance methods (first 20): #{instance_methods.inspect}")
            end
          end
          @available = false
          return false
          # simplecov:enable
        end

        @available = true
      rescue LoadError => e
        # simplecov:disable defensive - requires gem to not be installed
        # Only show LoadError details when debugging
        if debug
          warn("CitrusGrammarFinder: Failed to load '#{@require_path}': #{e.class}: #{e.message}")
          warn("CitrusGrammarFinder: LoadError backtrace:\n  #{e.backtrace&.first(10)&.join("\n  ")}")
        end
        @available = false
        # simplecov:enable
      rescue NameError => e
        # simplecov:disable defensive - requires gem with missing constant
        # Only show NameError details when debugging
        if debug
          warn("CitrusGrammarFinder: Failed to resolve '#{@grammar_const}': #{e.class}: #{e.message}")
          warn("CitrusGrammarFinder: NameError backtrace:\n  #{e.backtrace&.first(10)&.join("\n  ")}")
        end
        @available = false
        # simplecov:enable
      rescue TypeError => e
        # simplecov:disable defensive - TruffleRuby-specific edge case
        # TruffleRuby's bundled_gems.rb can raise TypeError when File.path is called on nil
        # This happens in bundled_gems.rb:124 warning? method when caller locations return nil
        # Always warn about TypeError as it indicates a platform-specific issue
        warn("CitrusGrammarFinder: TypeError during load of '#{@require_path}': #{e.class}: #{e.message}")
        warn("CitrusGrammarFinder: This may be a TruffleRuby bundled_gems.rb issue")
        if debug
          warn("CitrusGrammarFinder: TypeError backtrace:\n  #{e.backtrace&.first(10)&.join("\n  ")}")
        end
        @available = false
        # simplecov:enable
      rescue => e
        # simplecov:disable defensive - catch-all for unexpected errors
        # Always warn about unexpected errors
        warn("CitrusGrammarFinder: Unexpected error: #{e.class}: #{e.message}")
        if debug
          warn("CitrusGrammarFinder: backtrace:\n  #{e.backtrace&.first(10)&.join("\n  ")}")
        end
        @available = false
        # simplecov:enable
      end

      @available
    end

    # Get the resolved grammar module
    #
    # @return [Module, nil] the grammar module if available
    def grammar_module
      available? # Ensure we've tried to load
      @grammar_module
    end

    # Register this Citrus grammar with TreeHaver
    #
    # After registration, the language can be used via:
    #   TreeHaver::Language.{language_name}
    #
    # @param raise_on_missing [Boolean] if true, raises when grammar not available
    # @return [Boolean] true if registration succeeded
    # @raise [NotAvailable] if grammar not available and raise_on_missing is true
    def register!(raise_on_missing: false)
      unless available?
        if raise_on_missing
          raise NotAvailable, not_found_message
        end
        return false
      end

      TreeHaver.register_language(
        @language_name,
        grammar_module: @grammar_module,
        gem_name: @gem_name,
      )
      true
    end

    # Get debug information about the search
    #
    # @return [Hash] diagnostic information
    def search_info
      {
        language: @language_name,
        gem_name: @gem_name,
        grammar_const: @grammar_const,
        require_path: @require_path,
        available: available?,
        grammar_module: @grammar_module&.name,
      }
    end

    # Get a human-readable error message when grammar is not found
    #
    # @return [String] error message with installation hints
    def not_found_message
      "Citrus grammar for #{@language_name} not found. " \
        "Install #{@gem_name} gem: gem install #{@gem_name}"
    end

    private

    # Resolve a constant path like "TomlRB::Document"
    #
    # @param const_path [String] constant path
    # @return [Object] the constant
    # @raise [NameError] if constant not found
    def resolve_constant(const_path)
      const_path.split("::").reduce(Object) do |mod, const_name|
        mod.const_get(const_name)
      end
    end
  end
end
