# frozen_string_literal: true

module TreeHaver
  # Factory module for loading language grammars
  #
  # Language is the entry point for loading and using grammars. It provides
  # a unified interface that works across all backends (MRI, Rust, FFI, Java, Citrus, Parslet).
  #
  # This is a module with only module methods (factory pattern), not a class.
  # Backend-specific Language classes (e.g., Backends::Citrus::Language,
  # Backends::Parslet::Language) inherit from Base::Language.
  #
  # For tree-sitter backends, languages are loaded from shared library files (.so/.dylib/.dll).
  # For pure-Ruby backends (Citrus, Parslet, Prism, Psych), languages are built-in or provided by gems.
  #
  # == Loading Languages
  #
  # The primary way to load a language is via registration:
  #
  #   TreeHaver.register_language(:toml, path: "/path/to/libtree-sitter-toml.so")
  #   language = TreeHaver::Language.toml
  #
  # For explicit loading without registration:
  #
  #   language = TreeHaver::Language.from_library(
  #     "/path/to/libtree-sitter-toml.so",
  #     symbol: "tree_sitter_toml"
  #   )
  #
  # For ruby_tree_sitter compatibility:
  #
  #   language = TreeHaver::Language.load("toml", "/path/to/libtree-sitter-toml.so")
  #
  # @example Register and load a language
  #   TreeHaver.register_language(:toml, path: "/path/to/grammar.so")
  #   language = TreeHaver::Language.toml
  #
  # @see Base::Language The base class that backend Language classes inherit from
  module Language
    class << self
      # Load a language grammar from a shared library (ruby_tree_sitter compatibility)
      #
      # This method provides API compatibility with ruby_tree_sitter which uses
      # `Language.load(name, path)`.
      #
      # @param name [String] the language name (e.g., "toml")
      # @param path [String] absolute path to the language shared library
      # @param validate [Boolean] if true, validates the path for safety (default: true)
      # @return [Language] loaded language handle
      # @raise [NotAvailable] if the library cannot be loaded
      # @raise [ArgumentError] if the path fails security validation
      # @example
      #   language = TreeHaver::Language.load("toml", "/usr/local/lib/libtree-sitter-toml.so")
      def load(name, path, validate: true)
        from_library(path, symbol: "tree_sitter_#{name}", name: name, validate: validate)
      end

      # Load a language grammar from a shared library
      #
      # The library must export a function that returns a pointer to a TSLanguage struct.
      # By default, TreeHaver looks for a symbol named "tree_sitter_<name>".
      #
      # == Security
      #
      # By default, paths are validated using {PathValidator} to prevent path traversal
      # and other attacks. Set `validate: false` to skip validation (not recommended
      # unless you've already validated the path).
      #
      # @param path [String] absolute path to the language shared library (.so/.dylib/.dll)
      # @param symbol [String, nil] name of the exported function (defaults to auto-detection)
      # @param name [String, nil] logical name for the language (used in caching)
      # @param validate [Boolean] if true, validates path and symbol for safety (default: true)
      # @param backend [Symbol, String, nil] optional backend to use (overrides context/global)
      # @return [Language] loaded language handle
      # @raise [NotAvailable] if the library cannot be loaded or the symbol is not found
      # @raise [ArgumentError] if path or symbol fails security validation
      # @example
      #   language = TreeHaver::Language.from_library(
      #     "/usr/local/lib/libtree-sitter-toml.so",
      #     symbol: "tree_sitter_toml",
      #     name: "toml"
      #   )
      # @example With explicit backend
      #   language = TreeHaver::Language.from_library(
      #     "/usr/local/lib/libtree-sitter-toml.so",
      #     symbol: "tree_sitter_toml",
      #     backend: :ffi
      #   )
      def from_library(path, symbol: nil, name: nil, validate: true, backend: nil)
        if validate
          unless PathValidator.safe_library_path?(path)
            errors = PathValidator.validation_errors(path)
            raise ArgumentError, "Unsafe library path: #{path.inspect}. Errors: #{errors.join('; ')}"
          end

          if symbol && !PathValidator.safe_symbol_name?(symbol)
            raise ArgumentError, "Unsafe symbol name: #{symbol.inspect}. " \
              'Symbol names must be valid C identifiers.'
          end
        end

        # from_library only works with tree-sitter backends that support .so files
        # Pure Ruby backends (Citrus, Prism, Psych, Commonmarker, Markly) don't support from_library
        mod = TreeHaver.resolve_native_backend_module(backend)

        if mod.nil?
          if backend
            raise NotAvailable,
                  "Requested backend #{backend.inspect} is not available or does not support shared libraries"
          else
            raise NotAvailable,
                  'No native tree-sitter backend is available for loading shared libraries. ' \
                    'Available native backends (MRI, Rust, FFI, Java) require platform-specific setup. ' \
                    'For pure-Ruby parsing, use backend-specific Language classes directly (e.g., Prism, Psych, Citrus).'
          end
        end

        # Backend must implement .from_library; fallback to .from_path for older impls
        # Include effective backend AND ENV vars in cache key since they affect loading
        effective_b = TreeHaver.resolve_effective_backend(backend)
        key = [effective_b, path, symbol, name, ENV['TREE_SITTER_LANG_SYMBOL']]
        LanguageRegistry.fetch(key) do
          if mod::Language.respond_to?(:from_library)
            mod::Language.from_library(path, symbol: symbol, name: name)
          else
            mod::Language.from_path(path)
          end
        end
      end
      # Alias for {from_library}
      # @see from_library
      alias from_path from_library

      # Dynamic helper to load a registered language by name
      #
      # After registering a language with {TreeHaver.register_language},
      # you can load it using a method call. The appropriate backend will be
      # used based on registration and current backend.
      #
      # @example With tree-sitter
      #   TreeHaver.register_language(:toml, path: "/path/to/libtree-sitter-toml.so")
      #   language = TreeHaver::Language.toml
      #
      # @example With both backends
      #   TreeHaver.register_language(:toml,
      #     path: "/path/to/libtree-sitter-toml.so", symbol: "tree_sitter_toml")
      #   TreeHaver.register_language(:toml,
      #     grammar_module: TomlRB::Document)
      #   language = TreeHaver::Language.toml  # Uses appropriate grammar for active backend
      #
      # @param method_name [Symbol] the registered language name
      # @param args [Array] positional arguments
      # @param kwargs [Hash] keyword arguments
      # @return [Language] loaded language handle
      # @raise [NoMethodError] if the language name is not registered
      def method_missing(method_name, *args, **kwargs, &block)
        # Resolve only if the language name was registered
        all_backends = TreeHaver.registered_language(method_name)
        return super unless all_backends

        # Check current backend
        current_backend = TreeHaver.backend_module

        # Determine which backend type to use
        backend_type = if current_backend == Backends::Citrus
                         :citrus
                       elsif current_backend == Backends::Parslet
                         :parslet
                       else
                         :tree_sitter # MRI, Rust, FFI, Java all use tree-sitter
                       end

        # Get backend-specific registration
        reg = all_backends[backend_type]

        # If Citrus backend is active
        if backend_type == :citrus
          return Backends::Citrus::Language.new(reg[:grammar_module]) if reg && reg[:grammar_module]

          # No Citrus grammar for this language — provide actionable error
          raise NotAvailable,
                "No Citrus grammar registered for :#{method_name}. " \
                  'This language may only be available via tree-sitter. ' \
                  'Check that the correct backend is selected (current: citrus). ' \
                  "Registered backends for :#{method_name}: #{all_backends.keys.inspect}"
        end

        # If Parslet backend is active
        if backend_type == :parslet
          return Backends::Parslet::Language.new(reg[:grammar_class]) if reg && reg[:grammar_class]

          # No Parslet grammar for this language — provide actionable error
          raise NotAvailable,
                "No Parslet grammar registered for :#{method_name}. " \
                  'This language may only be available via tree-sitter. ' \
                  'Check that the correct backend is selected (current: parslet). ' \
                  "Registered backends for :#{method_name}: #{all_backends.keys.inspect}"
        end

        # For tree-sitter backends, try to load from path
        # If that fails, fall back to Citrus if available
        if reg && reg[:path]
          path = kwargs[:path] || args.first || reg[:path]
          # Symbol priority: kwargs override > registration > derive from method_name
          symbol = if kwargs.key?(:symbol)
                     kwargs[:symbol]
                   elsif reg[:symbol]
                     reg[:symbol]
                   else
                     "tree_sitter_#{method_name}"
                   end
          # Name priority: kwargs override > derive from symbol (strip tree_sitter_ prefix)
          # Using symbol-derived name ensures ruby_tree_sitter gets the correct language name
          # e.g., "toml" not "toml_both" when symbol is "tree_sitter_toml"
          name = kwargs[:name] || symbol&.sub(/\Atree_sitter_/, '')

          begin
            return from_library(path, symbol: symbol, name: name)
          rescue NotAvailable, ArgumentError, LoadError => e
            # Tree-sitter failed to load - check for Citrus fallback
            # Note: FFI::NotFoundError inherits from LoadError, so it's caught here too
            handle_tree_sitter_load_failure(e, all_backends)
          end
        end

        # No tree-sitter path registered - check for Citrus or Parslet fallback
        # This enables auto-fallback when tree-sitter grammar is not installed
        # but a pure Ruby grammar (Citrus or Parslet) is available.
        # Only fall back when backend is :auto - explicit native backend requests should fail.
        if TreeHaver.effective_backend == :auto
          citrus_reg = all_backends[:citrus]
          if citrus_reg && citrus_reg[:grammar_module]
            return Backends::Citrus::Language.new(citrus_reg[:grammar_module])
          end

          parslet_reg = all_backends[:parslet]
          if parslet_reg && parslet_reg[:grammar_class]
            return Backends::Parslet::Language.new(parslet_reg[:grammar_class])
          end
        end

        # No appropriate registration found
        raise ArgumentError,
              "No grammar registered for :#{method_name} compatible with #{backend_type} backend. " \
                "Registered backends: #{all_backends.keys.inspect}"
      end

      # @api private
      def respond_to_missing?(method_name, include_private = false)
        !!TreeHaver.registered_language(method_name) || super
      end

      private

      # Handle tree-sitter load failure with optional Citrus/Parslet fallback
      #
      # This handles cases where:
      # - The .so file doesn't exist or can't be loaded (NotAvailable, LoadError)
      # - FFI can't find required symbols like ts_parser_new (FFI::NotFoundError inherits from LoadError)
      # - Invalid arguments were provided (ArgumentError)
      #
      # Fallback to Citrus/Parslet ONLY happens when:
      # - The effective backend is :auto (user didn't explicitly request a native backend)
      # - A Citrus or Parslet grammar is registered for the language
      #
      # If the user explicitly requested a native backend (:mri, :rust, :ffi, :java),
      # we should NOT silently fall back to pure Ruby - that would violate the user's intent.
      #
      # @param error [Exception] the original error
      # @param all_backends [Hash] all registered backends for the language
      # @return [Backends::Citrus::Language, Backends::Parslet::Language] if fallback available and allowed
      # @raise [Exception] re-raises original error if no fallback or fallback not allowed
      # @api private
      def handle_tree_sitter_load_failure(error, all_backends)
        # Only fall back to pure Ruby when backend is :auto
        # If user explicitly requested a native backend, respect that choice
        effective = TreeHaver.effective_backend
        if effective == :auto
          citrus_reg = all_backends[:citrus]
          if citrus_reg && citrus_reg[:grammar_module]
            return Backends::Citrus::Language.new(citrus_reg[:grammar_module])
          end

          parslet_reg = all_backends[:parslet]
          if parslet_reg && parslet_reg[:grammar_class]
            return Backends::Parslet::Language.new(parslet_reg[:grammar_class])
          end
        end
        # No pure Ruby fallback allowed or available, re-raise the original error
        raise error
      end
    end
  end
end
