# frozen_string_literal: true

module TreeHaver
  module Backends
    # Java backend for JRuby using jtreesitter (java-tree-sitter)
    #
    # This backend integrates with jtreesitter JARs on JRuby,
    # leveraging JRuby's native Java integration for optimal performance.
    #
    # == Features
    #
    # jtreesitter (java-tree-sitter) provides Java bindings to tree-sitter and supports:
    # - Parsing source code into syntax trees
    # - Incremental parsing via Parser.parse(Tree, String)
    # - The Query API for pattern matching
    # - Tree editing for incremental re-parsing
    #
    # == Tree/Node Architecture
    #
    # This backend defines Ruby wrapper classes (`Java::Language`, `Java::Parser`,
    # `Java::Tree`, `Java::Node`) that wrap the raw jtreesitter Java objects via
    # JRuby's Java interop. These are **raw backend wrappers** not intended for
    # direct use by application code.
    #
    # The wrapping hierarchy is:
    #   Java::Tree/Node (this backend) → TreeHaver::Tree/Node → Base::Tree/Node
    #
    # When you use `TreeHaver::Parser#parse`:
    # 1. `Java::Parser#parse` returns a `Java::Tree` (wrapper around jtreesitter Tree)
    # 2. `TreeHaver::Parser` wraps it in `TreeHaver::Tree` (adds source storage)
    # 3. `TreeHaver::Tree#root_node` wraps `Java::Node` in `TreeHaver::Node`
    #
    # The `TreeHaver::Tree` and `TreeHaver::Node` wrappers provide the full unified
    # API including `#children`, `#text`, `#source`, `#source_position`, etc.
    #
    # This differs from pure-Ruby backends (Citrus, Parslet, Prism, Psych) which
    # define Tree/Node classes that directly inherit from Base::Tree/Base::Node.
    #
    # @see TreeHaver::Tree The wrapper class users should interact with
    # @see TreeHaver::Node The wrapper class users should interact with
    # @see TreeHaver::Base::Tree Base class documenting the Tree API contract
    # @see TreeHaver::Base::Node Base class documenting the Node API contract
    #
    # == Version Requirements
    #
    # - jtreesitter >= 0.26.0 (required)
    # - tree-sitter runtime library >= 0.26.0 (must match jtreesitter version)
    #
    # Older versions of jtreesitter are NOT supported due to API changes.
    #
    # == Platform Compatibility
    #
    # - MRI Ruby: ✗ Not available (no JVM)
    # - JRuby: ✓ Full support (native Java integration)
    # - TruffleRuby: ✗ Not available (jtreesitter requires JRuby's Java interop)
    #
    # == Installation
    #
    # 1. Download jtreesitter 0.26.0+ JAR from Maven Central:
    #    https://central.sonatype.com/artifact/io.github.tree-sitter/jtreesitter
    #
    # 2. Set the environment variable to point to the JAR directory:
    #    export TREE_SITTER_JAVA_JARS_DIR=/path/to/jars
    #
    # 3. Use JRuby to run your code:
    #    jruby -e "require 'tree_haver'; puts TreeHaver::Backends::Java.available?"
    #
    # @see https://github.com/tree-sitter/java-tree-sitter source
    # @see https://tree-sitter.github.io/java-tree-sitter jtreesitter documentation
    # @see https://central.sonatype.com/artifact/io.github.tree-sitter/jtreesitter Maven Central
    module Java
      # The Java package for java-tree-sitter
      JAVA_PACKAGE = "io.github.treesitter.jtreesitter"

      @load_attempted = false
      @loaded = false
      @java_classes = {} # rubocop:disable ThreadSafety/MutableClassInstanceVariable
      @runtime_lookup = nil  # Cached SymbolLookup for libtree-sitter.so

      module_function

      # Get the cached runtime library SymbolLookup
      # @return [Object, nil] the SymbolLookup for libtree-sitter.so
      # @api private
      def runtime_lookup
        @runtime_lookup
      end

      # Set the cached runtime library SymbolLookup
      # @param lookup [Object] the SymbolLookup
      # @api private
      def runtime_lookup=(lookup)
        @runtime_lookup = lookup
      end

      # Attempt to append JARs from TREE_SITTER_JAVA_JARS_DIR to JRuby classpath
      # and configure native library path from TREE_SITTER_RUNTIME_LIB
      #
      # If the environment variable is set and points to a directory, all .jar files
      # in that directory (recursively) are added to the JRuby classpath.
      #
      # @return [void]
      # @example
      #   ENV["TREE_SITTER_JAVA_JARS_DIR"] = "/path/to/java-tree-sitter/jars"
      #   TreeHaver::Backends::Java.add_jars_from_env!
      def add_jars_from_env!
        # simplecov:disable
        # This method requires JRuby and cannot be tested on MRI/CRuby.
        # JRuby-specific CI jobs would test this code.
        require "java"

        # Add JARs to classpath
        dir = ENV["TREE_SITTER_JAVA_JARS_DIR"]
        if dir && Dir.exist?(dir)
          Dir[File.join(dir, "**", "*.jar")].each do |jar|
            next if $CLASSPATH.include?(jar)
            $CLASSPATH << jar
          end
        end

        # Configure native library path for libtree-sitter
        # java-tree-sitter uses JNI and needs to find the native library
        configure_native_library_path!
        # simplecov:enable
      rescue LoadError
        # ignore; not JRuby or Java bridge not available
      end

      # Configure java.library.path to include the directory containing libtree-sitter
      #
      # @return [void]
      # @api private
      def configure_native_library_path!
        # simplecov:disable
        # This method requires JRuby and cannot be tested on MRI/CRuby.
        lib_path = ENV["TREE_SITTER_RUNTIME_LIB"]
        return unless lib_path && File.exist?(lib_path)

        lib_dir = File.dirname(lib_path)
        current_path = java.lang.System.getProperty("java.library.path") || ""

        unless current_path.include?(lib_dir)
          new_path = current_path.empty? ? lib_dir : "#{lib_dir}:#{current_path}"
          java.lang.System.setProperty("java.library.path", new_path)

          # Also set jna.library.path in case it uses JNA
          java.lang.System.setProperty("jna.library.path", new_path)
        end
        # simplecov:enable
      rescue => _error
        # Ignore errors setting library path
      end

      # Check if the Java backend is available
      #
      # Checks if:
      # 1. We're running on JRuby
      # 2. Environment variable TREE_SITTER_JAVA_JARS_DIR is set
      # 3. Required JARs (jtreesitter, tree-sitter) are present in that directory
      #
      # @return [Boolean] true if Java backend is available
      # @example
      #   if TreeHaver::Backends::Java.available?
      #     puts "Java backend ready"
      #   end
      class << self
        def available?
          return @loaded if @load_attempted # rubocop:disable ThreadSafety/ClassInstanceVariable
          @load_attempted = true # rubocop:disable ThreadSafety/ClassInstanceVariable
          @loaded = check_availability # rubocop:disable ThreadSafety/ClassInstanceVariable
        end

        # Reset the load state (primarily for testing)
        #
        # @return [void]
        # @api private
        def reset!
          @load_attempted = false # rubocop:disable ThreadSafety/ClassInstanceVariable
          @loaded = false # rubocop:disable ThreadSafety/ClassInstanceVariable
          @load_error = nil # rubocop:disable ThreadSafety/ClassInstanceVariable
          @loader = nil # rubocop:disable ThreadSafety/ClassInstanceVariable
          @java_classes = {} # rubocop:disable ThreadSafety/ClassInstanceVariable
        end

        private

        def check_availability
          # 1. Check Ruby engine
          return false unless RUBY_ENGINE == "jruby"

          # 2. Check for required JARs via environment variable
          jars_dir = ENV["TREE_SITTER_JAVA_JARS_DIR"]
          return false unless jars_dir && Dir.exist?(jars_dir)

          # 3. Check if we can load the classes
          begin
            ensure_loader_initialized!
            true
          rescue LoadError, NameError
            false
          end
        end
      end

      # Get the last load error message (for debugging)
      #
      # @return [String, nil] the error message or nil if no error
      def load_error
        @load_error
      end

      # Get the loaded Java classes
      #
      # @return [Hash] the Java class references
      # @api private
      def java_classes
        @java_classes
      end

      # Get capabilities supported by this backend
      #
      # @return [Hash{Symbol => Object}] capability map
      # @example
      #   TreeHaver::Backends::Java.capabilities
      #   # => { backend: :java, parse: true, query: true, bytes_field: true, incremental: true, comment_support: :nodes_only }
      def capabilities
        # simplecov:disable
        # This method returns meaningful data only on JRuby when java-tree-sitter is available.
        return {} unless available?
        {
          backend: :java,
          parse: true,
          query: true, # java-tree-sitter supports the Query API
          bytes_field: true,
          incremental: true, # java-tree-sitter supports Parser.parse(Tree, String)
          comment_support: :nodes_only,
        }
        # simplecov:enable
      end

      # Java backend language wrapper (raw backend language)
      #
      # This is a **raw backend language** that wraps a jtreesitter Language object
      # via JRuby's Java interop. It is used to configure the parser for a specific
      # grammar (e.g., TOML, JSON, etc.).
      #
      # Unlike `TreeHaver::Language` (which is a module with factory methods), this
      # class holds the actual loaded language data from a grammar shared library.
      #
      # @api private
      # @see TreeHaver::Language The factory module users should interact with
      # @see https://tree-sitter.github.io/java-tree-sitter/io/github/treesitter/jtreesitter/Language.html
      #
      # simplecov:disable
      # All Java backend implementation classes require JRuby and cannot be tested on MRI/CRuby.
      # JRuby-specific CI jobs would test this code.
      class Language
        include Comparable

        attr_reader :impl

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
        def initialize(impl, path: nil, symbol: nil)
          @impl = impl
          @backend = :java
          @path = path
          @symbol = symbol
        end

        # Compare languages for equality
        #
        # Java languages are equal if they have the same backend, path, and symbol.
        # Path and symbol uniquely identify a loaded language.
        #
        # @param other [Object] object to compare with
        # @return [Integer, nil] -1, 0, 1, or nil if not comparable
        def <=>(other)
          return unless other.is_a?(Language)
          return unless other.backend == @backend

          # Compare by path first, then symbol
          cmp = (@path || "") <=> (other.path || "")
          return cmp if cmp.nonzero?

          (@symbol || "") <=> (other.symbol || "")
        end

        # Hash value for this language (for use in Sets/Hashes)
        # @return [Integer]
        def hash
          [@backend, @path, @symbol].hash
        end

        # Alias eql? to ==
        alias_method :eql?, :==

        # Load a language from a shared library
        #
        # There are three ways java-tree-sitter can load shared libraries:
        #
        # 1. Libraries in OS library search path (LD_LIBRARY_PATH on Linux,
        #    DYLD_LIBRARY_PATH on macOS, PATH on Windows) - loaded via
        #    SymbolLookup.libraryLookup(String, Arena)
        #
        # 2. Libraries in java.library.path - loaded via SymbolLookup.loaderLookup()
        #
        # 3. Custom NativeLibraryLookup implementation (e.g., for JARs)
        #
        # @param path [String] path to language shared library (.so/.dylib) or library name
        # @param symbol [String, nil] exported symbol name (e.g., "tree_sitter_toml")
        # @param name [String, nil] logical name (used to derive symbol if not provided)
        # @return [Language] the loaded language
        # @raise [TreeHaver::NotAvailable] if Java backend is not available
        # @example Load by path
        #   lang = TreeHaver::Backends::Java::Language.from_library(
        #     "/usr/lib/libtree-sitter-toml.so",
        #     symbol: "tree_sitter_toml"
        #   )
        # @example Load by name (searches LD_LIBRARY_PATH)
        #   lang = TreeHaver::Backends::Java::Language.from_library(
        #     "tree-sitter-toml",
        #     symbol: "tree_sitter_toml"
        #   )
        class << self
          def from_library(path, symbol: nil, name: nil)
            raise TreeHaver::NotAvailable, "Java backend not available" unless Java.available?

            # Use shared utility for consistent symbol derivation across backends
            # If symbol not provided, derive from name or path
            sym = symbol || LibraryPathUtils.derive_symbol_from_path(path)
            # If name was provided, use it to override the derived symbol
            sym = "tree_sitter_#{name}" if name && !symbol

            begin
              arena = ::Java::JavaLangForeign::Arena.global
              symbol_lookup_class = ::Java::JavaLangForeign::SymbolLookup

              # IMPORTANT: Load libtree-sitter.so FIRST by name so its symbols are available
              # Grammar libraries need symbols like ts_language_version from the runtime
              # We cache this lookup at the module level
              unless Java.runtime_lookup
                # Use libraryLookup(String, Arena) to search LD_LIBRARY_PATH
                Java.runtime_lookup = symbol_lookup_class.libraryLookup("libtree-sitter.so", arena)
              end

              # Now load the grammar library
              if File.exist?(path)
                # Explicit path provided - use libraryLookup(Path, Arena)
                java_path = ::Java::JavaNioFile::Paths.get(path)
                grammar_lookup = symbol_lookup_class.libraryLookup(java_path, arena)
              else
                # Library name provided - use libraryLookup(String, Arena) to search
                # LD_LIBRARY_PATH / DYLD_LIBRARY_PATH / PATH
                grammar_lookup = symbol_lookup_class.libraryLookup(path, arena)
              end

              # Chain the lookups: grammar first, then runtime library for ts_* symbols
              # This makes ts_language_version available when Language.load() needs it
              combined_lookup = grammar_lookup.or(Java.runtime_lookup)

              java_lang = Java.java_classes[:Language].load(combined_lookup, sym)
              new(java_lang, path: path, symbol: symbol)
            rescue ::Java::JavaLang::RuntimeException => e
              cause = e.cause
              root_cause = cause&.cause || cause

              error_msg = "Failed to load language '#{sym}' from #{path}: #{e.message}"
              if root_cause.is_a?(::Java::JavaLang::UnsatisfiedLinkError)
                unresolved = root_cause.message.to_s
                if unresolved.include?("ts_language_version")
                  # This specific symbol was renamed in tree-sitter 0.24
                  error_msg += "\n\nVersion mismatch detected: The grammar was built against " \
                    "tree-sitter < 0.24 (uses ts_language_version), but your runtime library " \
                    "is tree-sitter >= 0.24 (uses ts_language_abi_version).\n\n" \
                    "Solutions:\n" \
                    "1. Rebuild the grammar against your version of tree-sitter\n" \
                    "2. Install a matching version of tree-sitter (< 0.24)\n" \
                    "3. Find a pre-built grammar compatible with tree-sitter 0.24+"
                elsif unresolved.include?("ts_language") || unresolved.include?("ts_parser")
                  error_msg += "\n\nThe grammar library has unresolved tree-sitter symbols. " \
                    "Ensure libtree-sitter.so is in LD_LIBRARY_PATH and version-compatible " \
                    "with the grammar."
                end
              end
              raise TreeHaver::NotAvailable, error_msg
            rescue ::Java::JavaLang::UnsatisfiedLinkError => e
              raise TreeHaver::NotAvailable,
                "Native library error loading #{path}: #{e.message}. " \
                  "Ensure the library is in LD_LIBRARY_PATH."
            rescue ::Java::JavaLang::IllegalArgumentException => e
              raise TreeHaver::NotAvailable,
                "Could not find library '#{path}': #{e.message}. " \
                  "Ensure it's in LD_LIBRARY_PATH or provide an absolute path."
            end
          end

          # Load a language by name from java-tree-sitter grammar JARs
          #
          # This method loads grammars that are packaged as java-tree-sitter JARs
          # from Maven Central. These JARs include the native grammar library
          # pre-built for Java's Foreign Function API.
          #
          # @param name [String] the language name (e.g., "java", "python", "toml")
          # @return [Language] the loaded language
          # @raise [TreeHaver::NotAvailable] if the language JAR is not available
          #
          # @example
          #   # First, add the grammar JAR to TREE_SITTER_JAVA_JARS_DIR:
          #   # tree-sitter-toml-0.23.2.jar from Maven Central
          #   lang = TreeHaver::Backends::Java::Language.load_by_name("toml")
          def load_by_name(name)
            raise TreeHaver::NotAvailable, "Java backend not available" unless Java.available?

            # Try to find the grammar library in standard locations
            # Look for library names like "tree-sitter-toml" or "libtree-sitter-toml"
            lib_names = [
              "tree-sitter-#{name}",
              "libtree-sitter-#{name}",
              "tree_sitter_#{name}",
            ]

            begin
              arena = ::Java::JavaLangForeign::Arena.global
              symbol_lookup_class = ::Java::JavaLangForeign::SymbolLookup

              # Ensure runtime lookup is available
              unless Java.runtime_lookup
                Java.runtime_lookup = symbol_lookup_class.libraryLookup("libtree-sitter.so", arena)
              end

              # Try each library name
              grammar_lookup = nil
              lib_names.each do |lib_name|
                grammar_lookup = symbol_lookup_class.libraryLookup(lib_name, arena)
                break
              rescue ::Java::JavaLang::IllegalArgumentException
                # Library not found in search path, try next name
                next
              end

              unless grammar_lookup
                raise TreeHaver::NotAvailable,
                  "Failed to load language '#{name}': Library not found. " \
                    "Ensure the grammar library (e.g., libtree-sitter-#{name}.so) " \
                    "is in LD_LIBRARY_PATH."
              end

              combined_lookup = grammar_lookup.or(Java.runtime_lookup)
              sym = "tree_sitter_#{name}"
              java_lang = Java.java_classes[:Language].load(combined_lookup, sym)
              new(java_lang, symbol: sym)
            rescue ::Java::JavaLang::RuntimeException => e
              raise TreeHaver::NotAvailable,
                "Failed to load language '#{name}': #{e.message}. " \
                  "Ensure the grammar library (e.g., libtree-sitter-#{name}.so) " \
                  "is in LD_LIBRARY_PATH."
            end
          end
        end

        class << self
          alias_method :from_path, :from_library
        end
      end

      # Java backend parser wrapper (raw backend parser)
      #
      # This is a **raw backend parser** that wraps a jtreesitter Parser object via
      # JRuby's Java interop. It is NOT intended for direct use by application code.
      #
      # Users should use `TreeHaver::Parser` which wraps this class and provides:
      # - Automatic backend selection
      # - Language wrapper unwrapping
      # - Tree wrapping with source storage
      # - Unified API across all backends
      #
      # @api private
      # @see TreeHaver::Parser The wrapper class users should interact with
      # @see https://tree-sitter.github.io/java-tree-sitter/io/github/treesitter/jtreesitter/Parser.html
      class Parser
        # Create a new parser instance
        #
        # @raise [TreeHaver::NotAvailable] if Java backend is not available
        def initialize
          raise TreeHaver::NotAvailable, "Java backend not available" unless Java.available?
          @parser = Java.java_classes[:Parser].new
        end

        # Set the language for this parser
        #
        # Note: TreeHaver::Parser unwraps language objects before calling this method.
        # This backend receives the Language wrapper's inner impl (java Language object).
        #
        # @param lang [Object] the Java language object (already unwrapped)
        # @return [void]
        def language=(lang)
          # lang is already unwrapped by TreeHaver::Parser
          @parser.language = lang
        end

        # Parse source code
        #
        # @param source [String] the source code to parse
        # @return [Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        def parse(source)
          java_result = @parser.parse(source)
          # jtreesitter 0.26.0 returns Optional<Tree>
          java_tree = unwrap_optional(java_result)
          raise TreeHaver::Error, "Parser returned no tree" unless java_tree
          Tree.new(java_tree)
        end

        # Parse source code with optional incremental parsing
        #
        # Note: old_tree is already unwrapped by TreeHaver::Parser before reaching this method.
        # The backend receives the raw Tree wrapper's impl, not a TreeHaver::Tree.
        #
        # When old_tree is provided and has been edited, tree-sitter will reuse
        # unchanged nodes for better performance.
        #
        # @param old_tree [Tree, nil] previous backend tree for incremental parsing (already unwrapped)
        # @param source [String] the source code to parse
        # @return [Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        # @see https://tree-sitter.github.io/java-tree-sitter/io/github/treesitter/jtreesitter/Parser.html#parse(java.lang.String,io.github.treesitter.jtreesitter.Tree)
        def parse_string(old_tree, source)
          # old_tree is already unwrapped to Tree wrapper's impl by TreeHaver::Parser
          if old_tree
            # Get the actual Java Tree object
            java_old_tree = if old_tree.is_a?(Tree)
              old_tree.impl
            else
              unwrap_optional(old_tree)
            end

            java_result = if java_old_tree
              # jtreesitter 0.26.0 API: parse(String source, Tree oldTree)
              @parser.parse(source, java_old_tree)
            else
              @parser.parse(source)
            end
          else
            java_result = @parser.parse(source)
          end
          # jtreesitter 0.26.0 returns Optional<Tree>
          java_tree = unwrap_optional(java_result)
          raise TreeHaver::Error, "Parser returned no tree" unless java_tree
          Tree.new(java_tree)
        end

        private

        # Unwrap Java Optional
        #
        # jtreesitter 0.26.0 returns Optional<T> from many methods.
        #
        # @param value [Object] an Optional or direct value
        # @return [Object, nil] unwrapped value or nil if empty
        def unwrap_optional(value)
          return value unless value.respond_to?(:isPresent)
          value.isPresent ? value.get : nil
        end
      end

      # Java backend tree wrapper (raw backend tree)
      #
      # This is a **raw backend tree** that wraps a jtreesitter Tree object via
      # JRuby's Java interop. It is NOT intended for direct use by application code.
      #
      # == Architecture Note
      #
      # Unlike pure-Ruby backends (Citrus, Parslet, Prism, Psych) which define Tree
      # classes that inherit from `TreeHaver::Base::Tree`, tree-sitter backends (MRI,
      # Rust, FFI, Java) define raw wrapper classes that get wrapped by `TreeHaver::Tree`.
      #
      # The wrapping hierarchy is:
      #   Java::Tree (this class) → TreeHaver::Tree → Base::Tree
      #
      # When you use `TreeHaver::Parser#parse`, the returned tree is already wrapped
      # in `TreeHaver::Tree`, which provides the full unified API including:
      # - `#source` - The original source text
      # - `#root_node` - Returns a `TreeHaver::Node` (not raw `Java::Node`)
      # - `#errors`, `#warnings`, `#comments` - Parse diagnostics
      # - `#edit` - Mark tree as edited for incremental parsing
      # - `#to_s`, `#inspect` - String representations
      #
      # This raw class only implements methods that require direct calls to jtreesitter.
      # The wrapper adds Ruby-level conveniences and stores the source text needed for
      # `Node#text` extraction.
      #
      # @api private
      # @see TreeHaver::Tree The wrapper class users should interact with
      # @see TreeHaver::Base::Tree The base class documenting the full Tree API
      # @see https://tree-sitter.github.io/java-tree-sitter/io/github/treesitter/jtreesitter/Tree.html
      class Tree
        attr_reader :impl

        # @api private
        def initialize(impl)
          @impl = impl
        end

        # Get the root node of the tree
        #
        # @return [Node] the root node
        # @raise [TreeHaver::Error] if tree has no root node
        def root_node
          result = @impl.rootNode
          # jtreesitter 0.26.0: rootNode() may return Optional<Node> or Node directly
          java_node = if result.respond_to?(:isPresent)
            raise TreeHaver::Error, "Tree has no root node" unless result.isPresent
            result.get
          else
            result
          end
          raise TreeHaver::Error, "Tree has no root node" unless java_node
          Node.new(java_node)
        end

        # Mark the tree as edited for incremental re-parsing
        #
        # @param start_byte [Integer] byte offset where the edit starts
        # @param old_end_byte [Integer] byte offset where the old text ended
        # @param new_end_byte [Integer] byte offset where the new text ends
        # @param start_point [Hash] starting position as `{ row:, column: }`
        # @param old_end_point [Hash] old ending position as `{ row:, column: }`
        # @param new_end_point [Hash] new ending position as `{ row:, column: }`
        # @return [void]
        def edit(start_byte:, old_end_byte:, new_end_byte:, start_point:, old_end_point:, new_end_point:)
          point_class = Java.java_classes[:Point]
          input_edit_class = Java.java_classes[:InputEdit]

          start_pt = point_class.new(start_point[:row], start_point[:column])
          old_end_pt = point_class.new(old_end_point[:row], old_end_point[:column])
          new_end_pt = point_class.new(new_end_point[:row], new_end_point[:column])

          input_edit = input_edit_class.new(
            start_byte,
            old_end_byte,
            new_end_byte,
            start_pt,
            old_end_pt,
            new_end_pt,
          )

          @impl.edit(input_edit)
        end
      end

      # Java backend node wrapper (raw backend node)
      #
      # This is a **raw backend node** that wraps a jtreesitter Node object via
      # JRuby's Java interop. It provides the minimal interface needed for tree-sitter
      # operations but is NOT intended for direct use by application code.
      #
      # == Architecture Note
      #
      # Unlike pure-Ruby backends (Citrus, Parslet, Prism, Psych) which define Node
      # classes that inherit from `TreeHaver::Base::Node`, tree-sitter backends (MRI,
      # Rust, FFI, Java) define raw wrapper classes that get wrapped by `TreeHaver::Node`.
      #
      # The wrapping hierarchy is:
      #   Java::Node (this class) → TreeHaver::Node → Base::Node
      #
      # When you use `TreeHaver::Parser#parse`, the returned tree's nodes are already
      # wrapped in `TreeHaver::Node`, which provides the full unified API including:
      # - `#children` - Array of child nodes
      # - `#text` - Extract text from source
      # - `#first_child`, `#last_child` - Convenience accessors
      # - `#start_line`, `#end_line` - 1-based line numbers
      # - `#source_position` - Hash with position info
      # - `#each`, `#map`, etc. - Enumerable methods
      # - `#to_s`, `#inspect` - String representations
      #
      # This raw class only implements methods that require direct calls to jtreesitter.
      # The wrapper adds Ruby-level conveniences.
      #
      # @api private
      # @see TreeHaver::Node The wrapper class users should interact with
      # @see TreeHaver::Base::Node The base class documenting the full Node API
      # @see https://tree-sitter.github.io/java-tree-sitter/io/github/treesitter/jtreesitter/Node.html
      class Node
        attr_reader :impl

        # @api private
        def initialize(impl)
          @impl = impl
        end

        # Get the type of this node
        #
        # @return [String] the node type
        def type
          @impl.type
        end

        # Get the number of children
        #
        # @return [Integer] child count
        def child_count
          @impl.childCount
        end

        # Get a child by index
        #
        # @param index [Integer] the child index
        # @return [Node, nil] the child node or nil if index out of bounds
        def child(index)
          # jtreesitter 0.26.0: getChild returns Optional<Node> or throws IndexOutOfBoundsException
          result = @impl.getChild(index)
          return if result.nil?

          # Handle Java Optional
          if result.respond_to?(:isPresent)
            return unless result.isPresent
            java_node = result.get
          else
            # Direct Node return (some jtreesitter versions)
            java_node = result
          end

          Node.new(java_node)
        rescue ::Java::JavaLang::IndexOutOfBoundsException
          nil
        end

        # Get a child by field name
        #
        # @param name [String] the field name
        # @return [Node, nil] the child node or nil if not found
        def child_by_field_name(name)
          # jtreesitter 0.26.0: getChildByFieldName returns Optional<Node>
          # However, some versions or scenarios may return null directly
          result = @impl.getChildByFieldName(name)
          return if result.nil?

          # Handle Java Optional
          if result.respond_to?(:isPresent)
            return unless result.isPresent
            java_node = result.get
          else
            # Direct Node return (some jtreesitter versions)
            java_node = result
          end

          Node.new(java_node)
        end

        # Iterate over children
        #
        # @yield [Node] each child node
        # @return [void]
        def each
          return enum_for(:each) unless block_given?
          child_count.times do |i|
            yield child(i)
          end
        end

        # Get the start byte position
        #
        # @return [Integer] start byte
        def start_byte
          @impl.startByte
        end

        # Get the end byte position
        #
        # @return [Integer] end byte
        def end_byte
          @impl.endByte
        end

        # Get the start point (row, column)
        #
        # @return [Hash] with :row and :column keys
        def start_point
          pt = @impl.startPoint
          {row: pt.row, column: pt.column}
        end

        # Get the end point (row, column)
        #
        # @return [Hash] with :row and :column keys
        def end_point
          pt = @impl.endPoint
          {row: pt.row, column: pt.column}
        end

        # Check if this node has an error
        #
        # @return [Boolean] true if the node or any descendant has an error
        def has_error?
          @impl.hasError
        end

        # Check if this node is missing
        #
        # @return [Boolean] true if this is a MISSING node
        def missing?
          @impl.isMissing
        end

        # Check if this is a named node
        #
        # @return [Boolean] true if this is a named node
        def named?
          @impl.isNamed
        end

        # Get the parent node
        #
        # @return [Node, nil] the parent node or nil if this is the root
        def parent
          # jtreesitter 0.26.0: getParent returns Optional<Node>
          result = @impl.getParent
          return if result.nil?

          # Handle Java Optional
          if result.respond_to?(:isPresent)
            return unless result.isPresent
            java_node = result.get
          else
            java_node = result
          end

          Node.new(java_node)
        end

        # Get the next sibling node
        #
        # @return [Node, nil] the next sibling or nil if none
        def next_sibling
          # jtreesitter 0.26.0: getNextSibling returns Optional<Node>
          result = @impl.getNextSibling
          return if result.nil?

          # Handle Java Optional
          if result.respond_to?(:isPresent)
            return unless result.isPresent
            java_node = result.get
          else
            java_node = result
          end

          Node.new(java_node)
        end

        # Get the previous sibling node
        #
        # @return [Node, nil] the previous sibling or nil if none
        def prev_sibling
          # jtreesitter 0.26.0: getPrevSibling returns Optional<Node>
          result = @impl.getPrevSibling
          return if result.nil?

          # Handle Java Optional
          if result.respond_to?(:isPresent)
            return unless result.isPresent
            java_node = result.get
          else
            java_node = result
          end

          Node.new(java_node)
        end

        # Get the text of this node
        #
        # @return [String] the source text
        def text
          @impl.text.to_s
        end
      end
      # simplecov:enable

      # Register the availability checker for RSpec dependency tags
      TreeHaver::BackendRegistry.register_availability_checker(:java) do
        available?
      end
    end
  end
end
