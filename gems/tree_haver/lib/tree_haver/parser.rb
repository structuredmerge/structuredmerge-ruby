# frozen_string_literal: true

module TreeHaver
  # Unified Parser facade providing a consistent API across all backends
  #
  # This class acts as a facade/adapter that delegates to backend-specific
  # parser implementations. It automatically selects the appropriate backend
  # and provides a unified interface regardless of which parser is being used.
  #
  # == Backend Selection
  #
  # The parser automatically selects a backend based on:
  # 1. Explicit `backend:` parameter in constructor
  # 2. `TreeHaver.backend` global setting
  # 3. `TREE_HAVER_BACKEND` environment variable
  # 4. Auto-detection (tries available backends in order)
  #
  # == Supported Backends
  #
  # **Tree-sitter backends** (native, high-performance):
  # - `:mri` - ruby_tree_sitter gem (C extension, MRI only)
  # - `:rust` - tree_stump gem (Rust via magnus, MRI only)
  # - `:ffi` - FFI bindings to libtree-sitter (MRI, JRuby)
  # - `:java` - java-tree-sitter (JRuby only)
  #
  # **Pure Ruby backends** (portable, no native dependencies):
  # - `:citrus` - Citrus PEG parser (e.g., toml-rb)
  # - `:parslet` - Parslet PEG parser (e.g., toml gem)
  # - `:prism` - Ruby's official parser (Ruby only)
  # - `:psych` - YAML parser (stdlib)
  #
  # == Wrapping/Unwrapping Responsibility
  #
  # TreeHaver::Parser handles ALL object wrapping and unwrapping:
  #
  # **Language objects:**
  # - Unwraps Language wrappers before passing to backend.language=
  # - MRI backend receives ::TreeSitter::Language
  # - Rust backend receives String (language name)
  # - FFI backend receives wrapped Language (needs to_ptr)
  # - Citrus backend receives grammar module
  # - Parslet backend receives grammar class
  #
  # **Tree objects:**
  # - parse() receives raw source, backend returns raw tree, Parser wraps it
  # - parse_string() unwraps old_tree before passing to backend, wraps returned tree
  # - Backends always work with raw backend trees, never TreeHaver::Tree
  #
  # **Node objects:**
  # - Backends return raw nodes, TreeHaver::Tree and TreeHaver::Node wrap them
  #
  # This design ensures:
  # - Principle of Least Surprise: wrapping happens at boundaries, consistently
  # - Backends are simple: they don't need to know about TreeHaver wrappers
  # - Single Responsibility: wrapping logic is only in TreeHaver::Parser
  #
  # @example Basic parsing
  #   parser = TreeHaver::Parser.new
  #   parser.language = TreeHaver::Language.toml
  #   tree = parser.parse("[package]\nname = \"foo\"")
  #
  # @example Explicit backend selection
  #   parser = TreeHaver::Parser.new(backend: :citrus)
  #   parser.language = TreeHaver::Language.toml
  #   tree = parser.parse(toml_source)
  #
  # @see Base::Parser The base class defining the parser interface
  # @see Backends::Citrus::Parser Citrus backend implementation
  # @see Backends::Parslet::Parser Parslet backend implementation
  # @see Backends::Prism::Parser Prism backend implementation
  class Parser < Base::Parser
    # Create a new parser instance
    #
    # The parser automatically selects the best available backend unless
    # explicitly specified. Use the `backend:` parameter to force a specific backend.
    #
    # @param backend [Symbol, String, nil] optional backend to use (overrides context/global)
    #   Valid values: :auto, :mri, :rust, :ffi, :java, :citrus, :parslet, :prism, :psych
    # @raise [NotAvailable] if no backend is available or requested backend is unavailable
    # @example Default (auto-selects best available backend)
    #   parser = TreeHaver::Parser.new
    # @example Explicit backend
    #   parser = TreeHaver::Parser.new(backend: :citrus)
    def initialize(backend: nil)
      super() # Initialize @language from Base::Parser

      # Convert string backend names to symbols for consistency
      backend = backend.to_sym if backend.is_a?(String)

      mod = TreeHaver.resolve_backend_module(backend)

      if mod.nil?
        raise NotAvailable, "Requested backend #{backend.inspect} is not available" if backend

        raise NotAvailable, 'No TreeHaver backend is available'

      end

      # Try to create the parser, with fallback to pure Ruby if tree-sitter fails
      # This enables auto-fallback when tree-sitter runtime isn't available
      begin
        @impl = mod::Parser.new
        @explicit_backend = backend # Remember for introspection (always a Symbol or nil)
      rescue NoMethodError, LoadError => e
        # NOTE: FFI::NotFoundError inherits from LoadError, so it's caught here too
        handle_parser_creation_failure(e, backend)
      end
    end

    # Handle parser creation failure with optional Citrus/Parslet fallback
    #
    # @param error [Exception] the error that caused parser creation to fail
    # @param backend [Symbol, nil] the requested backend
    # @raise [NotAvailable] if no fallback is available
    # @api private
    def handle_parser_creation_failure(error, backend)
      # Tree-sitter backend failed (likely missing runtime library)
      # Try Citrus or Parslet as fallback if we weren't explicitly asked for a specific backend
      raise error unless backend.nil? || backend == :auto

      if Backends::Citrus.available?
        @impl = Backends::Citrus::Parser.new
        @explicit_backend = :citrus
      elsif Backends::Parslet.available?
        @impl = Backends::Parslet::Parser.new
        @explicit_backend = :parslet
      else
        # No fallback available, re-raise original error
        raise NotAvailable, "Tree-sitter backend failed: #{error.message}. " \
          'Citrus/Parslet fallback not available. Install tree-sitter runtime, citrus gem, or parslet gem.'
      end

      # Explicit backend was requested, don't fallback
    end

    # Get the backend this parser is using (for introspection)
    #
    # Returns the actual backend in use, resolving :auto to the concrete backend.
    #
    # @return [Symbol] the backend name (:mri, :rust, :ffi, :java, :citrus, or :parslet)
    def backend
      if @explicit_backend && @explicit_backend != :auto
        @explicit_backend
      else
        # Determine actual backend from the implementation class
        case @impl.class.name
        when /MRI/
          :mri
        when /Rust/
          :rust
        when /FFI/
          :ffi
        when /Java/
          :java
        when /Citrus/
          :citrus
        when /Parslet/
          :parslet
        else
          # Fallback to effective_backend if we can't determine from class name
          TreeHaver.effective_backend
        end
      end
    end

    # Set the language grammar for this parser
    #
    # The language must be compatible with the parser's backend. If a mismatch
    # is detected (e.g., Citrus language on tree-sitter parser), the parser
    # will automatically switch to the correct backend.
    #
    # @param lang [Language] the language to use for parsing
    # @return [Language] the language that was set
    # @example
    #   parser.language = TreeHaver::Language.from_library("/path/to/grammar.so")
    def language=(lang)
      # Auto-switch backend if language type doesn't match current parser
      # This handles the case where Language.toml returns a Citrus/Parslet language
      # but the parser was initialized with a tree-sitter backend
      switch_backend_for_language(lang)

      # Unwrap the language before passing to backend
      # Backends receive raw language objects, never TreeHaver wrappers
      inner_lang = unwrap_language(lang)
      @impl.language = inner_lang

      # Store on base class for API compatibility
      @language = lang
    end

    # Parse source code into a syntax tree
    #
    # @param source [String] the source code to parse (should be UTF-8)
    # @return [Tree] the parsed syntax tree
    # @example
    #   tree = parser.parse("x = 1")
    #   puts tree.root_node.type
    def parse(source)
      tree_impl = @impl.parse(source)
      # Wrap backend tree with source so Node#text works
      Tree.new(tree_impl, source: source)
    end

    # Parse source code into a syntax tree (with optional incremental parsing)
    #
    # This method provides API compatibility with ruby_tree_sitter which uses
    # `parse_string(old_tree, source)`.
    #
    # == Incremental Parsing
    #
    # tree-sitter supports **incremental parsing** where you can pass a previously
    # parsed tree along with edit information to efficiently re-parse only the
    # changed portions of source code. This is a major performance optimization
    # for editors and IDEs that need to re-parse on every keystroke.
    #
    # The workflow for incremental parsing is:
    # 1. Parse the initial source: `tree = parser.parse_string(nil, source)`
    # 2. User edits the source (e.g., inserts a character)
    # 3. Call `tree.edit(...)` to update the tree's position data
    # 4. Re-parse with the old tree: `new_tree = parser.parse_string(tree, new_source)`
    # 5. tree-sitter reuses unchanged nodes, only re-parsing affected regions
    #
    # TreeHaver passes through to the underlying backend if it supports incremental
    # parsing (MRI and Rust backends do). Check `TreeHaver.capabilities[:incremental]`
    # to see if the current backend supports it.
    #
    # @param old_tree [Tree, nil] previously parsed tree for incremental parsing, or nil for fresh parse
    # @param source [String] the source code to parse (should be UTF-8)
    # @return [Tree] the parsed syntax tree
    # @see https://tree-sitter.github.io/tree-sitter/using-parsers#editing tree-sitter incremental parsing docs
    # @see Tree#edit For marking edits before incremental re-parsing
    # @example First parse (no old tree)
    #   tree = parser.parse_string(nil, "x = 1")
    # @example Incremental parse
    #   tree.edit(start_byte: 4, old_end_byte: 5, new_end_byte: 6, ...)
    #   new_tree = parser.parse_string(tree, "x = 42")
    def parse_string(old_tree, source)
      # Pass through to backend if it supports incremental parsing
      if old_tree && @impl.respond_to?(:parse_string)
        # Extract the underlying implementation from our Tree wrapper
        old_impl = if old_tree.respond_to?(:inner_tree)
                     old_tree.inner_tree
                   elsif old_tree.respond_to?(:instance_variable_get)
                     # Fallback for compatibility
                     old_tree.instance_variable_get(:@inner_tree) || old_tree.instance_variable_get(:@impl) || old_tree
                   else
                     old_tree
                   end
        tree_impl = @impl.parse_string(old_impl, source)
        # Wrap backend tree with source so Node#text works
        Tree.new(tree_impl, source: source)
      elsif @impl.respond_to?(:parse_string)
        tree_impl = @impl.parse_string(nil, source)
        # Wrap backend tree with source so Node#text works
        Tree.new(tree_impl, source: source)
      else
        # Fallback for backends that don't support parse_string
        parse(source)
      end
    end

    private

    # Switch backend if language type doesn't match current parser
    #
    # This is necessary because TreeHaver.parser_for may return a Language
    # from a different backend than the Parser was initialized with.
    # For example, Language.toml might return a Citrus::Language when
    # tree-sitter-toml is not available, but Parser was initialized with :auto.
    #
    # @param lang [Object] The language object
    # @api private
    def switch_backend_for_language(lang)
      return unless lang.respond_to?(:backend)

      lang_backend = lang.backend
      parser_backend = backend

      # No switch needed if backends match
      return if lang_backend == parser_backend

      # Switch to matching backend parser
      case lang_backend
      when :citrus
        unless @impl.is_a?(Backends::Citrus::Parser)
          @impl = Backends::Citrus::Parser.new
          @explicit_backend = :citrus
        end
      when :parslet
        unless @impl.is_a?(Backends::Parslet::Parser)
          @impl = Backends::Parslet::Parser.new
          @explicit_backend = :parslet
        end
      when :prism
        unless @impl.is_a?(Backends::Prism::Parser)
          @impl = Backends::Prism::Parser.new
          @explicit_backend = :prism
        end
      when :psych
        unless @impl.is_a?(Backends::Psych::Parser)
          @impl = Backends::Psych::Parser.new
          @explicit_backend = :psych
        end
        # Tree-sitter backends (:mri, :rust, :ffi, :java) - don't auto-switch between them
        # as that would require reloading the language from the .so file
      end
    end

    # Unwrap a language object to extract the raw backend language
    #
    # This method is smart about backend compatibility:
    # 1. If language has a backend attribute, checks if it matches current backend
    # 2. If mismatch detected, attempts to reload language for correct backend
    # 3. If reload successful, uses new language; otherwise continues with original
    # 4. Unwraps the language wrapper to get raw backend object
    #
    # @param lang [Object] wrapped or raw language object
    # @return [Object] raw backend language object appropriate for current backend
    # @api private
    def unwrap_language(lang)
      # Check if this is a TreeHaver language wrapper with backend info
      if lang.respond_to?(:backend)
        # Verify backend compatibility FIRST
        # This prevents passing languages from wrong backends to native code
        # Exception: :auto backend is permissive - accepts any language
        current_backend = backend

        if lang.backend != current_backend && current_backend != :auto
          # Backend mismatch! Try to reload for correct backend
          reloaded = try_reload_language_for_backend(lang, current_backend)
          if reloaded
            lang = reloaded
          else
            # Couldn't reload - this is an error
            raise TreeHaver::Error,
                  "Language backend mismatch: language is for #{lang.backend}, parser is #{current_backend}. " \
                    'Cannot reload language for correct backend. ' \
                    "Create a new language with TreeHaver::Language.from_library when backend is #{current_backend}."
          end
        end

        # Get the current parser's language (if set)
        current_lang = @impl.respond_to?(:language) ? @impl.language : nil

        # Language mismatch detected! The parser might have a different language set
        # Compare the actual language objects using Comparable
        if current_lang && lang != current_lang
          # Different language being set (e.g., switching from TOML to JSON)
          # This is fine, just informational
        end
      end

      # Unwrap based on backend type
      # All TreeHaver Language wrappers have the backend attribute
      unless lang.respond_to?(:backend)
        # This shouldn't happen - all our wrappers have backend attribute
        # If we get here, it's likely a raw backend object that was passed directly
        raise TreeHaver::Error,
              "Expected TreeHaver Language wrapper with backend attribute, got #{lang.class}. " \
                'Use TreeHaver::Language.from_library to create language objects.'
      end

      case lang.backend
      when :mri
        return lang.to_language if lang.respond_to?(:to_language)
        return lang.inner_language if lang.respond_to?(:inner_language)

        lang
      when :rust
        return lang.name if lang.respond_to?(:name)

        lang
      when :ffi
        lang  # FFI needs wrapper for to_ptr
      when :java
        lang.impl if lang.respond_to?(:impl)
      when :citrus
        lang  # Citrus backend accepts Language wrapper (handles both)
      when :parslet
        lang  # Parslet backend accepts Language wrapper (handles both)
      when :prism
        lang  # Prism backend expects the Language wrapper
      when :psych
        lang  # Psych backend expects the Language wrapper
      when :commonmarker
        lang  # Commonmarker backend expects the Language wrapper
      when :markly
        lang  # Markly backend expects the Language wrapper
      else
        # Unknown backend (e.g., test backend)
        # Try generic unwrapping methods for flexibility in testing
        return lang.to_language if lang.respond_to?(:to_language)
        return lang.inner_language if lang.respond_to?(:inner_language)
        return lang.impl if lang.respond_to?(:impl)
        return lang.grammar_module if lang.respond_to?(:grammar_module)
        return lang.grammar_class if lang.respond_to?(:grammar_class)
        return lang.name if lang.respond_to?(:name)

        # If nothing works, pass through as-is
        # This allows test languages to be passed directly
        lang
      end
    end

    # Try to reload a language for the current backend
    #
    # This handles the case where a language was loaded for one backend,
    # but is now being used with a different backend (e.g., after backend switch).
    #
    # @param lang [Object] language object with metadata
    # @param target_backend [Symbol] backend to reload for
    # @return [Object, nil] reloaded language or nil if reload not possible
    # @api private
    def try_reload_language_for_backend(lang, target_backend)
      # Can't reload without path information
      return unless lang.respond_to?(:path) || lang.respond_to?(:grammar_module)

      # For tree-sitter backends, reload from path
      if lang.respond_to?(:path) && lang.path
        begin
          # Use Language.from_library which respects current backend
          return Language.from_library(
            lang.path,
            symbol: lang.respond_to?(:symbol) ? lang.symbol : nil,
            name: lang.respond_to?(:name) ? lang.name : nil
          )
        rescue StandardError => e
          # Reload failed, continue with original
          warn("TreeHaver: Failed to reload language for backend #{target_backend}: #{e.message}") if $VERBOSE
          return
        end
      end

      # For Citrus, can't really reload as it's just a module reference
      nil
    end
  end
end
