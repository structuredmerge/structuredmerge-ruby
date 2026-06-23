# frozen_string_literal: true

module TreeHaver
  # Thread-safe language registrations and cache for loaded Language handles
  #
  # The LanguageRegistry provides two main functions:
  # 1. **Registrations**: Store mappings from language names to backend-specific configurations
  # 2. **Cache**: Memoize loaded Language objects to avoid repeated dlopen calls
  #
  # The registry supports multiple backends for the same language, allowing runtime
  # switching, benchmarking, and fallback scenarios.
  #
  # == Supported Backend Types
  #
  # The registry is extensible and supports any backend type. Common types include:
  #
  # - `:tree_sitter` - Native tree-sitter grammars (.so files)
  # - `:citrus` - Citrus PEG parser grammars (pure Ruby)
  # - `:prism` - Ruby's Prism parser (Ruby source only)
  # - `:psych` - Ruby's Psych parser (YAML only)
  # - `:commonmarker` - Commonmarker gem (Markdown)
  # - `:markly` - Markly gem (Markdown/GFM)
  # - `:rbs` - RBS gem (RBS type signatures) - registered externally by rbs-merge
  #
  # External gems can register their own backend types using the same API.
  #
  # Registration structure:
  # ```ruby
  # @registrations = {
  #   toml: {
  #     tree_sitter: { path: "/path/to/lib.so", symbol: "tree_sitter_toml" },
  #     citrus: { grammar_module: TomlRB::Document, gem_name: "toml-rb" }
  #   },
  #   ruby: {
  #     prism: { backend_module: TreeHaver::Backends::Prism }
  #   },
  #   yaml: {
  #     psych: { backend_module: TreeHaver::Backends::Psych }
  #   },
  #   markdown: {
  #     commonmarker: { backend_module: TreeHaver::Backends::Commonmarker },
  #     markly: { backend_module: TreeHaver::Backends::Markly }
  #   },
  #   rbs: {
  #     rbs: { backend_module: Rbs::Merge::Backends::RbsBackend }  # External
  #   }
  # }
  # ```
  #
  # @example Register tree-sitter grammar
  # ```ruby
  #   TreeHaver::LanguageRegistry.register(:toml, :tree_sitter,
  #     path: "/path/to/lib.so", symbol: "tree_sitter_toml")
  # ```
  #
  # @example Register Citrus grammar
  # ```ruby
  #   TreeHaver::LanguageRegistry.register(:toml, :citrus,
  #     grammar_module: TomlRB::Document, gem_name: "toml-rb")
  # ```
  #
  # @example Register a pure Ruby backend (internal or external)
  # ```ruby
  #   TreeHaver::LanguageRegistry.register(:rbs, :rbs,
  #     backend_module: Rbs::Merge::Backends::RbsBackend,
  #     gem_name: "rbs")
  # ```
  #
  # @api private
  module LanguageRegistry
    @mutex = Mutex.new
    @cache = {}
    @registrations = {}

    module_function

    # Register a language for a specific backend
    #
    # Stores backend-specific configuration for a language. Multiple backends
    # can be registered for the same language without conflict.
    #
    # @param name [Symbol, String] language identifier (e.g., :toml, :json, :ruby, :yaml, :rbs)
    # @param backend_type [Symbol] backend type (:tree_sitter, :citrus, :prism, :psych, :commonmarker, :markly, or custom)
    # @param config [Hash] backend-specific configuration
    # @option config [String] :path tree-sitter library path (for tree-sitter backends)
    # @option config [String] :symbol exported symbol name (for tree-sitter backends)
    # @option config [Module] :grammar_module Citrus grammar module (for Citrus backend)
    # @option config [Module] :backend_module backend module with Language/Parser classes (for pure Ruby backends)
    # @option config [String] :gem_name gem name for error messages and availability checks
    # @return [void]
    # @example Register tree-sitter grammar
    #   LanguageRegistry.register(:toml, :tree_sitter,
    #     path: "/usr/local/lib/libtree-sitter-toml.so", symbol: "tree_sitter_toml")
    # @example Register Citrus grammar
    #   LanguageRegistry.register(:toml, :citrus,
    #     grammar_module: TomlRB::Document, gem_name: "toml-rb")
    # @example Register pure Ruby backend (external gem)
    #   LanguageRegistry.register(:rbs, :rbs,
    #     backend_module: Rbs::Merge::Backends::RbsBackend, gem_name: "rbs")
    def register(name, backend_type, **config)
      key = name.to_sym
      backend_key = backend_type.to_sym

      @mutex.synchronize do
        @registrations[key] ||= {}
        @registrations[key][backend_key] = config.compact
      end
      nil
    end

    # Fetch registration entries for a language
    #
    # Returns all backend-specific configurations for a language.
    #
    # @param name [Symbol, String] language identifier
    # @param backend_type [Symbol, nil] optional backend type to filter by
    # @return [Hash{Symbol => Hash}, Hash, nil] all backends or specific backend config
    # @example Get all backends
    #   entries = LanguageRegistry.registered(:toml)
    #   # => {
    #   #   tree_sitter: { path: "/usr/local/lib/libtree-sitter-toml.so", symbol: "tree_sitter_toml" },
    #   #   citrus: { grammar_module: TomlRB::Document, gem_name: "toml-rb" }
    #   # }
    # @example Get specific backend
    #   entry = LanguageRegistry.registered(:toml, :citrus)
    #   # => { grammar_module: TomlRB::Document, gem_name: "toml-rb" }
    def registered(name, backend_type = nil)
      @mutex.synchronize do
        lang_config = @registrations[name.to_sym]
        return unless lang_config

        if backend_type
          lang_config[backend_type.to_sym]
        else
          lang_config
        end
      end
    end

    # Fetch a cached language by key or compute and store it
    #
    # This method provides thread-safe memoization for loaded Language objects.
    # If the key exists in the cache, the cached value is returned immediately.
    # Otherwise, the block is called to compute the value, which is then cached.
    #
    # @param key [Array] cache key, typically [path, symbol, name]
    # @yieldreturn [Object] the computed language handle (called only on cache miss)
    # @return [Object] the cached or computed language handle
    # @example
    #   language = LanguageRegistry.fetch(["/path/lib.so", "symbol", "toml"]) do
    #     expensive_language_load_operation
    #   end
    def fetch(key)
      @mutex.synchronize do
        return @cache[key] if @cache.key?(key)

        value = yield
        @cache[key] = value
      end
    end

    # Clear the language cache
    #
    # Removes all cached Language objects. The next call to {fetch} for any key
    # will recompute the value. Does not clear registrations.
    #
    # @return [void]
    # @example
    #   LanguageRegistry.clear_cache!
    def clear_cache!
      @mutex.synchronize { @cache.clear }
      nil
    end

    # Clear all registrations and cache
    #
    # Removes all language registrations and cached Language objects.
    # Primarily used in tests to reset state between test cases.
    #
    # @return [void]
    # @example
    #   LanguageRegistry.clear
    def clear
      @mutex.synchronize do
        @registrations.clear
        @cache.clear
      end
      nil
    end
  end
end
