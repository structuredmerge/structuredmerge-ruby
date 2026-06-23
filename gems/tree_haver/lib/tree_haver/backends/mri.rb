# frozen_string_literal: true

module TreeHaver
  module Backends
    # MRI backend using the ruby_tree_sitter gem
    #
    # This backend wraps the ruby_tree_sitter gem, which is a native C extension
    # for MRI Ruby. It provides the most feature-complete tree-sitter integration
    # on MRI, including support for the Query API.
    #
    # == Tree/Node Architecture
    #
    # This backend (like all tree-sitter backends: MRI, Rust, FFI, Java) does NOT
    # define its own Tree or Node classes. Instead:
    #
    # - Parser#parse returns raw `::TreeSitter::Tree` objects
    # - These are wrapped by `TreeHaver::Tree` (inherits from `Base::Tree`)
    # - `TreeHaver::Tree#root_node` wraps raw nodes in `TreeHaver::Node`
    #
    # This differs from pure-Ruby backends (Citrus, Prism, Psych) which define
    # their own `Backend::X::Tree` and `Backend::X::Node` classes.
    #
    # @see TreeHaver::Tree The wrapper class for tree-sitter Tree objects
    # @see TreeHaver::Node The wrapper class for tree-sitter Node objects
    # @see TreeHaver::Base::Tree Base class documenting the Tree API contract
    # @see TreeHaver::Base::Node Base class documenting the Node API contract
    #
    # == Platform Compatibility
    #
    # - MRI Ruby: ✓ Full support (fastest tree-sitter backend on MRI)
    # - JRuby: ✗ Cannot load native C extensions (runs on JVM)
    # - TruffleRuby: ✗ C extension not compatible with TruffleRuby
    #
    # @see https://github.com/Faveod/ruby-tree-sitter ruby_tree_sitter
    module MRI
      @load_attempted = false
      @loaded = false

      # Check if the MRI backend is available
      #
      # Attempts to require ruby_tree_sitter on first call and caches the result.
      #
      # @note When this method returns true, the FFI backend becomes permanently
      #   unavailable for the remainder of the process. This is because loading
      #   ruby_tree_sitter defines `::TreeSitter::Parser`, which the FFI backend
      #   checks to detect conflicts. The MRI backend statically links tree-sitter,
      #   while FFI dynamically links libtree-sitter.so - when both are loaded,
      #   FFI will segfault when trying to set a language on a parser due to
      #   incompatible pointer types from different tree-sitter builds.
      #
      # @return [Boolean] true if ruby_tree_sitter is available
      # @see TreeHaver::Backends::FFI.available? FFI availability check
      # @example
      #   if TreeHaver::Backends::MRI.available?
      #     puts "MRI backend is ready"
      #     # Note: FFI backend is now blocked for this process
      #   end
      class << self
        def available?
          return @loaded if @load_attempted

          @load_attempted = true
          begin
            # ruby_tree_sitter is a C extension that only works on MRI
            # It doesn't work on JRuby or TruffleRuby
            if RUBY_ENGINE == 'ruby'
              require 'tree_sitter'
              @loaded = true
            else
              # simplecov:disable only runs on non-MRI engines (JRuby, TruffleRuby)
              @loaded = false
              # simplecov:enable
            end
          rescue LoadError
            # simplecov:disable only runs when ruby_tree_sitter gem is not installed
            @loaded = false
            # simplecov:enable
          rescue StandardError
            # simplecov:disable defensive code - StandardError during require is extremely rare
            @loaded = false
            # simplecov:enable
          end
          @loaded
        end

        # Reset the load state (primarily for testing)
        #
        # @return [void]
        # @api private
        def reset!
          @load_attempted = false
          @loaded = false
        end

        # Get capabilities supported by this backend
        #
        # @return [Hash{Symbol => Object}] capability map
        # @example
        #   TreeHaver::Backends::MRI.capabilities
        #   # => { backend: :mri, query: true, bytes_field: true, incremental: true, comment_support: :nodes_only }
        def capabilities
          return {} unless available?

          {
            backend: :mri,
            query: true,
            bytes_field: true,
            incremental: true,
            comment_support: :nodes_only
          }
        end
      end

      # Wrapper for ruby_tree_sitter Language
      #
      # Wraps ::TreeSitter::Language from ruby_tree_sitter to provide a consistent
      # API across all backends.
      class Language
        include Comparable

        # The wrapped TreeSitter::Language object
        # @return [::TreeSitter::Language]
        attr_reader :inner_language

        # The backend this language is for
        # @return [Symbol]
        attr_reader :backend

        # The path this language was loaded from (if known)
        # @return [String, nil]
        attr_reader :path

        # The symbol name (if known)
        # @return [String, nil]
        attr_reader :symbol

        # @api private
        # @param lang [::TreeSitter::Language] the language object from ruby_tree_sitter
        # @param path [String, nil] path language was loaded from
        # @param symbol [String, nil] symbol name
        def initialize(lang, path: nil, symbol: nil)
          @inner_language = lang
          @backend = :mri
          @path = path
          @symbol = symbol
        end

        # Get the language name
        #
        # Derives a name from the symbol or path.
        #
        # @return [Symbol] language name
        def language_name
          # Try to derive from symbol (e.g., "tree_sitter_toml" -> :toml)
          if @symbol
            name = @symbol.to_s.sub(/^tree_sitter_/, '')
            return name.to_sym
          end

          # Try to derive from path (e.g., "/path/to/libtree-sitter-toml.so" -> :toml)
          if @path
            name = LibraryPathUtils.derive_language_name_from_path(@path)
            return name.to_sym if name
          end

          :unknown
        end

        # Alias for language_name (API compatibility)
        alias name language_name

        # Compare languages for equality
        #
        # MRI languages are equal if they have the same backend, path, and symbol.
        # Path and symbol uniquely identify a loaded language.
        #
        # @param other [Object] object to compare with
        # @return [Integer, nil] -1, 0, 1, or nil if not comparable
        def <=>(other)
          return unless other.is_a?(Language)
          return unless other.backend == @backend

          # Compare by path first, then symbol
          cmp = (@path || '') <=> (other.path || '')
          return cmp if cmp.nonzero?

          (@symbol || '') <=> (other.symbol || '')
        end

        # Hash value for this language (for use in Sets/Hashes)
        # @return [Integer]
        def hash
          [@backend, @path, @symbol].hash
        end

        # Alias eql? to ==
        alias eql? ==

        # Convert to the underlying TreeSitter::Language for passing to parser
        #
        # @return [::TreeSitter::Language]
        def to_language
          @inner_language
        end
        alias to_ts_language to_language

        # Load a language from a shared library (preferred method)
        #
        # @param path [String] absolute path to the language shared library
        # @param symbol [String] the exported symbol name (e.g., "tree_sitter_json")
        # @param name [String, nil] optional language name (unused by MRI backend)
        # @return [Language] wrapped language handle
        # @raise [TreeHaver::NotAvailable] if ruby_tree_sitter is not available
        # @example
        #   lang = TreeHaver::Backends::MRI::Language.from_library("/path/to/lib.so", symbol: "tree_sitter_json")
        class << self
          def from_library(path, symbol: nil, name: nil)
            # Derive symbol from path if not provided using shared utility
            symbol ||= LibraryPathUtils.derive_symbol_from_path(path)
            from_path(path, symbol: symbol, name: name)
          end

          private

          # Load a language from a shared library path (internal implementation)
          #
          # @param path [String] absolute path to the language shared library
          # @param symbol [String] the exported symbol name (e.g., "tree_sitter_json")
          # @param name [String, nil] optional language name
          # @return [Language] wrapped language handle
          # @api private
          def from_path(path, symbol: nil, name: nil)
            raise TreeHaver::NotAvailable, 'ruby_tree_sitter not available' unless MRI.available?

            # ruby_tree_sitter's TreeSitter::Language.load takes (language_name, path_to_so)
            # where language_name is the language identifier (e.g., "toml", "json")
            # NOT the full symbol name (e.g., NOT "tree_sitter_toml")
            # and path_to_so is the full path to the .so file
            #
            # If name is not provided, derive it from symbol using shared utility
            language_name = (name || LibraryPathUtils.derive_language_name_from_symbol(symbol)).to_s
            ts_lang = ::TreeSitter::Language.load(language_name, path)
            new(ts_lang, path: path, symbol: symbol)
          rescue NameError => e
            # TreeSitter constant doesn't exist - backend not loaded
            raise TreeHaver::NotAvailable, "ruby_tree_sitter not available: #{e.message}"
          rescue Exception => e # rubocop:disable Lint/RescueException
            # TreeSitter errors inherit from Exception (not StandardError) in ruby_tree_sitter v2+
            # We rescue Exception and check the class name dynamically to avoid NameError
            # at parse time when TreeSitter constant isn't loaded yet
            if defined?(TreeSitter::TreeSitterError) && e.is_a?(TreeSitter::TreeSitterError)
              raise TreeHaver::NotAvailable, "Could not load language: #{e.message}"
            end

            raise # Re-raise if it's not a TreeSitter error
          end
        end
      end

      # Wrapper for ruby_tree_sitter Parser
      #
      # This is a thin pass-through to ::TreeSitter::Parser from ruby_tree_sitter.
      class Parser
        # Create a new parser instance
        #
        # @raise [TreeHaver::NotAvailable] if ruby_tree_sitter is not available
        def initialize
          raise TreeHaver::NotAvailable, 'ruby_tree_sitter not available' unless MRI.available?

          @parser = ::TreeSitter::Parser.new
        rescue NameError => e
          # TreeSitter constant doesn't exist - backend not loaded
          raise TreeHaver::NotAvailable, "ruby_tree_sitter not available: #{e.message}"
        rescue Exception => e # rubocop:disable Lint/RescueException
          # TreeSitter errors inherit from Exception (not StandardError) in ruby_tree_sitter v2+
          # We rescue Exception and check the class name dynamically to avoid NameError
          # at parse time when TreeSitter constant isn't loaded yet
          if defined?(TreeSitter::TreeSitterError) && e.is_a?(TreeSitter::TreeSitterError)
            raise TreeHaver::NotAvailable, "Could not create parser: #{e.message}"
          end

          raise # Re-raise if it's not a TreeSitter error
        end

        # Set the language for this parser
        #
        # @param lang [::TreeSitter::Language, TreeHaver::Backends::MRI::Language] the language to use
        # @return [::TreeSitter::Language, TreeHaver::Backends::MRI::Language] the language that was set
        # @raise [TreeHaver::NotAvailable] if setting language fails
        def language=(lang)
          # Unwrap if it's a TreeHaver wrapper
          inner_lang = lang.respond_to?(:inner_language) ? lang.inner_language : lang
          @parser.language = inner_lang
          # Verify it was set
          raise TreeHaver::NotAvailable, 'Language not set correctly' if @parser.language.nil?

          # Return the original language object (wrapped or unwrapped)
          lang
        rescue Exception => e # rubocop:disable Lint/RescueException
          # TreeSitter errors inherit from Exception (not StandardError) in ruby_tree_sitter v2+
          # We rescue Exception and check the class name dynamically to avoid NameError
          # at parse time when TreeSitter constant isn't loaded yet
          if defined?(TreeSitter::TreeSitterError) && e.is_a?(TreeSitter::TreeSitterError)
            raise TreeHaver::NotAvailable, "Could not set language: #{e.message}"
          end

          raise # Re-raise if it's not a TreeSitter error
        end

        # Parse source code
        #
        # ruby_tree_sitter provides parse_string for string input
        #
        # @param source [String] the source code to parse
        # @return [::TreeSitter::Tree] raw tree (NOT wrapped - wrapping happens in TreeHaver::Parser)
        # @raise [TreeHaver::NotAvailable] if parsing returns nil (usually means language not set)
        def parse(source)
          # ruby_tree_sitter's parse_string(old_tree, string) method
          # Pass nil for old_tree (initial parse)
          # Return raw tree - TreeHaver::Parser will wrap it
          tree = @parser.parse_string(nil, source)
          raise TreeHaver::NotAvailable, 'Parse returned nil - is language set?' if tree.nil?

          tree
        rescue Exception => e # rubocop:disable Lint/RescueException
          # TreeSitter errors inherit from Exception (not StandardError) in ruby_tree_sitter v2+
          # We rescue Exception and check the class name dynamically to avoid NameError
          # at parse time when TreeSitter constant isn't loaded yet
          if defined?(TreeSitter::TreeSitterError) && e.is_a?(TreeSitter::TreeSitterError)
            raise TreeHaver::NotAvailable, "Could not parse source: #{e.message}"
          end

          raise # Re-raise if it's not a TreeSitter error
        end

        # Parse source code with optional incremental parsing
        #
        # Note: old_tree should already be unwrapped by TreeHaver::Parser before reaching this method.
        # The backend receives the raw inner tree (::TreeSitter::Tree or nil), not a wrapped TreeHaver::Tree.
        #
        # @param old_tree [::TreeSitter::Tree, nil] previous tree for incremental parsing (already unwrapped)
        # @param source [String] the source code to parse
        # @return [::TreeSitter::Tree] raw tree (NOT wrapped - wrapping happens in TreeHaver::Parser)
        # @raise [TreeHaver::NotAvailable] if parsing fails
        def parse_string(old_tree, source)
          # old_tree is already unwrapped by TreeHaver::Parser, pass it directly
          # Return raw tree - TreeHaver::Parser will wrap it
          @parser.parse_string(old_tree, source)
        rescue Exception => e # rubocop:disable Lint/RescueException
          # TreeSitter errors inherit from Exception (not StandardError) in ruby_tree_sitter v2+
          # We rescue Exception and check the class name dynamically to avoid NameError
          # at parse time when TreeSitter constant isn't loaded yet
          if defined?(TreeSitter::TreeSitterError) && e.is_a?(TreeSitter::TreeSitterError)
            raise TreeHaver::NotAvailable, "Could not parse source: #{e.message}"
          end

          raise # Re-raise if it's not a TreeSitter error
        end
      end

      # Register the availability checker for RSpec dependency tags
      TreeHaver::BackendRegistry.register_availability_checker(:mri) do
        available?
      end
    end
  end
end
