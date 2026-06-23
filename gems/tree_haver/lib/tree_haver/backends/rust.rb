# frozen_string_literal: true

module TreeHaver
  module Backends
    # Rust backend using the tree_stump gem
    #
    # This backend wraps the tree_stump gem, which provides Ruby bindings to
    # tree-sitter written in Rust. It offers native performance with Rust's
    # safety guarantees and includes precompiled binaries for common platforms.
    #
    # tree_stump supports incremental parsing and the Query API, making it
    # suitable for editor/IDE use cases where performance is critical.
    #
    # == Tree/Node Architecture
    #
    # This backend (like all tree-sitter backends: MRI, Rust, FFI, Java) does NOT
    # define its own Tree or Node classes. Instead:
    #
    # - Parser#parse returns raw `::TreeStump::Tree` objects
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
    # - MRI Ruby: ✓ Full support
    # - JRuby: ✗ Cannot load native extensions (runs on JVM)
    # - TruffleRuby: ✗ magnus/rb-sys incompatible with TruffleRuby's C API emulation
    #
    # @see https://github.com/joker1007/tree_stump tree_stump
    module Rust
      @load_attempted = false
      @loaded = false

      # Check if the Rust backend is available
      #
      # Attempts to require tree_stump on first call and caches the result.
      #
      # @return [Boolean] true if tree_stump is available
      # @example
      #   if TreeHaver::Backends::Rust.available?
      #     puts "Rust backend is ready"
      #   end
      class << self
        def available?
          return @loaded if @load_attempted

          @load_attempted = true
          begin
            # tree_stump uses magnus which requires MRI's C API
            # It doesn't work on JRuby or TruffleRuby
            if RUBY_ENGINE == 'ruby'
              require 'tree_stump'
              @loaded = true
            else
              @loaded = false
            end
          rescue LoadError
            @loaded = false
          rescue StandardError
            @loaded = false
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
        #   TreeHaver::Backends::Rust.capabilities
        #   # => { backend: :rust, query: true, bytes_field: true, incremental: false, comment_support: :nodes_only }
        def capabilities
          return {} unless available?

          {
            backend: :rust,
            query: true,
            bytes_field: true,
            incremental: false, # TreeStump doesn't currently expose incremental parsing to Ruby
            comment_support: :nodes_only
          }
        end
      end

      # Wrapper for tree_stump Language
      #
      # Provides TreeHaver-compatible interface to tree_stump's language loading.
      # tree_stump uses a registration-based API where languages are registered
      # by name, then referenced by that name when setting parser language.
      class Language
        include Comparable

        # The registered language name
        # @return [String]
        attr_reader :name

        # The backend this language is for
        # @return [Symbol]
        attr_reader :backend

        # The path this language was loaded from (if known)
        # @return [String, nil]
        attr_reader :path

        # @api private
        # @param name [String] the registered language name
        # @param path [String, nil] path language was loaded from
        def initialize(name, path: nil)
          @name = name
          @backend = :rust
          @path = path
        end

        # Compare languages for equality
        #
        # Rust languages are equal if they have the same backend and name.
        # Name uniquely identifies a registered language in TreeStump.
        #
        # @param other [Object] object to compare with
        # @return [Integer, nil] -1, 0, 1, or nil if not comparable
        def <=>(other)
          return unless other.is_a?(Language)
          return unless other.backend == @backend

          @name <=> other.name
        end

        # Hash value for this language (for use in Sets/Hashes)
        # @return [Integer]
        def hash
          [@backend, @name].hash
        end

        # Alias eql? to ==
        alias eql? ==

        # Load a language from a shared library path
        #
        # @param path [String] absolute path to the language shared library
        # @param symbol [String, nil] the symbol name (accepted for API consistency, but tree_stump derives it from name)
        # @param name [String, nil] logical name for the language (optional, derived from path if not provided)
        # @return [Language] a wrapper holding the registered language name
        # @raise [TreeHaver::NotAvailable] if tree_stump is not available
        # @example
        #   lang = TreeHaver::Backends::Rust::Language.from_library("/usr/local/lib/libtree-sitter-toml.so")
        class << self
          def from_library(path, symbol: nil, name: nil) # rubocop:disable Lint/UnusedMethodArgument
            raise TreeHaver::NotAvailable, 'tree_stump not available' unless Rust.available?

            # Validate the path exists before calling register_lang to provide a clear error
            raise TreeHaver::NotAvailable, "Language library not found: #{path}" unless File.exist?(path)

            # tree_stump uses TreeStump.register_lang(name, path) to register languages
            # The name is used to derive the symbol automatically (tree_sitter_<name>)
            # Use shared utility for consistent path parsing across backends
            lang_name = name || LibraryPathUtils.derive_language_name_from_path(path)
            ::TreeStump.register_lang(lang_name, path)
            new(lang_name, path: path)
          rescue RuntimeError => e
            raise TreeHaver::NotAvailable, "Failed to load language from #{path}: #{e.message}"
          end

          # Backward-compatible alias for from_library
          alias from_path from_library
        end
      end

      # Wrapper for tree_stump Parser
      #
      # Provides TreeHaver-compatible interface to tree_stump's parser.
      class Parser
        # Create a new parser instance
        #
        # @raise [TreeHaver::NotAvailable] if tree_stump is not available
        def initialize
          raise TreeHaver::NotAvailable, 'tree_stump not available' unless Rust.available?

          @parser = ::TreeStump::Parser.new
        end

        # Set the language for this parser
        #
        # Note: TreeHaver::Parser unwraps language objects before calling this method.
        # When called from TreeHaver::Parser, receives String (language name).
        # For backward compatibility and backend tests, also handles Language wrapper.
        #
        # @param lang [Language, String] the language wrapper or name string
        # @return [Language, String] the language that was set
        def language=(lang)
          # Extract language name (handle both wrapper and raw string)
          lang_name = lang.respond_to?(:name) ? lang.name : lang.to_s
          # tree_stump uses set_language with a string name
          @parser.set_language(lang_name)
          lang # rubocop:disable Lint/Void (intentional return value)
        end

        # Parse source code
        #
        # @param source [String] the source code to parse
        # @return [TreeStump::Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        def parse(source)
          # Return raw tree_stump tree - TreeHaver::Parser will wrap it
          @parser.parse(source)
        end

        # Parse source code with optional incremental parsing
        #
        # Note: TreeStump does not currently expose incremental parsing to Ruby.
        # The parse method always does a full parse, ignoring old_tree.
        #
        # @param old_tree [TreeHaver::Tree, nil] previous tree for incremental parsing (ignored)
        # @param source [String] the source code to parse
        # @return [TreeStump::Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        def parse_string(old_tree, source) # rubocop:disable Lint/UnusedMethodArgument
          # TreeStump's parse method only accepts source as a single argument
          # and internally always passes None for the old tree (no incremental parsing support)
          @parser.parse(source)
        end
      end

      # Register the availability checker for RSpec dependency tags
      TreeHaver::BackendRegistry.register_availability_checker(:rust) do
        available?
      end
    end
  end
end
