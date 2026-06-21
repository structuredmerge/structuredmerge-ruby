# frozen_string_literal: true

module TreeHaver
  # Utility for finding and registering Parslet grammar gems.
  #
  # ParsletGrammarFinder provides language-agnostic discovery of Parslet grammar
  # gems. Given a language name and gem information, it attempts to load the
  # grammar and register it with tree_haver.
  #
  # Unlike tree-sitter grammars (which are .so files), Parslet grammars are
  # Ruby classes that inherit from Parslet::Parser. This class handles the
  # discovery and registration of these grammars.
  #
  # @example Basic usage with toml gem
  #   finder = TreeHaver::ParsletGrammarFinder.new(
  #     language: :toml,
  #     gem_name: "toml",
  #     grammar_const: "TOML::Parslet"
  #   )
  #   finder.register! if finder.available?
  #
  # @example With custom require path
  #   finder = TreeHaver::ParsletGrammarFinder.new(
  #     language: :json,
  #     gem_name: "json-parslet",
  #     grammar_const: "JsonParslet::Grammar",
  #     require_path: "json/parslet"
  #   )
  #
  # @see GrammarFinder For tree-sitter grammar discovery
  # @see CitrusGrammarFinder For Citrus grammar discovery
  class ParsletGrammarFinder
    # @return [Symbol] the language identifier
    attr_reader :language_name

    # @return [String] the gem name to require
    attr_reader :gem_name

    # @return [String] the constant path to the grammar class (e.g., "TOML::Parslet")
    attr_reader :grammar_const

    # @return [String, nil] custom require path (defaults to gem_name)
    attr_reader :require_path

    # Initialize a Parslet grammar finder
    #
    # @param language [Symbol, String] the language name (e.g., :toml, :json)
    # @param gem_name [String] the gem name (e.g., "toml")
    # @param grammar_const [String] constant path to grammar class (e.g., "TOML::Parslet")
    # @param require_path [String, nil] custom require path (defaults to gem_name as-is)
    def initialize(language:, gem_name:, grammar_const:, require_path: nil)
      @language_name = language.to_sym
      @gem_name = gem_name
      @grammar_const = grammar_const
      @require_path = require_path || gem_name
      @load_attempted = false
      @available = false
      @grammar_class = nil
    end

    # Check if the Parslet grammar is available
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
        warn("ParsletGrammarFinder: require_path is nil or empty for #{@language_name}") if debug
        @available = false
        return false
      end

      begin
        # Try to require the gem
        require @require_path

        # Try to resolve the constant
        @grammar_class = resolve_constant(@grammar_const)

        # Verify it can create a parser instance with a parse method
        unless valid_grammar_class?(@grammar_class)
          if debug
            warn("ParsletGrammarFinder: #{@grammar_const} is not a valid Parslet grammar class")
            warn("ParsletGrammarFinder: #{@grammar_const}.class = #{@grammar_class.class}")
          end
          @available = false
          return false
        end

        @available = true
      rescue LoadError => e
        # simplecov:disable defensive - requires gem to not be installed
        if debug
          warn("ParsletGrammarFinder: Failed to load '#{@require_path}': #{e.class}: #{e.message}")
          warn("ParsletGrammarFinder: LoadError backtrace:\n  #{e.backtrace&.first(10)&.join("\n  ")}")
        end
        @available = false
        # simplecov:enable
      rescue NameError => e
        # simplecov:disable defensive - requires gem with missing constant
        if debug
          warn("ParsletGrammarFinder: Failed to resolve '#{@grammar_const}': #{e.class}: #{e.message}")
          warn("ParsletGrammarFinder: NameError backtrace:\n  #{e.backtrace&.first(10)&.join("\n  ")}")
        end
        @available = false
        # simplecov:enable
      rescue TypeError => e
        # simplecov:disable defensive - TruffleRuby-specific edge case
        warn("ParsletGrammarFinder: TypeError during load of '#{@require_path}': #{e.class}: #{e.message}")
        warn("ParsletGrammarFinder: This may be a TruffleRuby bundled_gems.rb issue")
        if debug
          warn("ParsletGrammarFinder: TypeError backtrace:\n  #{e.backtrace&.first(10)&.join("\n  ")}")
        end
        @available = false
        # simplecov:enable
      rescue => e
        # simplecov:disable defensive - catch-all for unexpected errors
        warn("ParsletGrammarFinder: Unexpected error: #{e.class}: #{e.message}")
        if debug
          warn("ParsletGrammarFinder: backtrace:\n  #{e.backtrace&.first(10)&.join("\n  ")}")
        end
        @available = false
        # simplecov:enable
      end

      @available
    end

    # Get the resolved grammar class
    #
    # @return [Class, nil] the grammar class if available
    def grammar_class
      available? # Ensure we've tried to load
      @grammar_class
    end

    # Register this Parslet grammar with TreeHaver
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
        grammar_class: @grammar_class,
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
        grammar_class: @grammar_class&.name,
      }
    end

    # Get a human-readable error message when grammar is not found
    #
    # @return [String] error message with installation hints
    def not_found_message
      "Parslet grammar for #{@language_name} not found. " \
        "Install #{@gem_name} gem: gem install #{@gem_name}"
    end

    private

    # Resolve a constant path like "TOML::Parslet"
    #
    # @param const_path [String] constant path
    # @return [Object] the constant
    # @raise [NameError] if constant not found
    def resolve_constant(const_path)
      const_path.split("::").reduce(Object) do |mod, const_name|
        mod.const_get(const_name)
      end
    end

    # Check if the class is a valid Parslet grammar
    #
    # @param klass [Class] the class to check
    # @return [Boolean] true if valid
    def valid_grammar_class?(klass)
      return false unless klass.respond_to?(:new)

      # Check if it's a Parslet::Parser subclass
      if defined?(::Parslet::Parser)
        return true if klass < ::Parslet::Parser
      end

      # Fallback: check if it can create an instance that responds to parse
      begin
        instance = klass.new
        instance.respond_to?(:parse)
      rescue StandardError
        false
      end
    end
  end
end
