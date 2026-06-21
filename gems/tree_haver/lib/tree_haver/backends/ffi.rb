# frozen_string_literal: true

module TreeHaver
  module Backends
    # FFI-based backend for calling libtree-sitter directly
    #
    # This backend uses Ruby FFI (JNR-FFI on JRuby) to call the native tree-sitter
    # C library without requiring MRI C extensions.
    #
    # The FFI backend currently supports:
    # - Parsing source code
    # - AST node traversal
    # - Accessing node types and children
    #
    # Not yet supported:
    # - Query API (tree-sitter queries/patterns)
    #
    # == Tree/Node Architecture
    #
    # This backend defines raw `FFI::Tree` and `FFI::Node` wrapper classes that
    # provide minimal FFI bindings to the tree-sitter C structs. These are **not**
    # intended for direct use by application code.
    #
    # The wrapping hierarchy is:
    #   FFI::Tree/Node (raw FFI wrappers) → TreeHaver::Tree/Node → Base::Tree/Node
    #
    # When you use `TreeHaver::Parser#parse`:
    # 1. `FFI::Parser#parse` returns an `FFI::Tree` (raw pointer wrapper)
    # 2. `TreeHaver::Parser` wraps it in `TreeHaver::Tree` (adds source storage)
    # 3. `TreeHaver::Tree#root_node` wraps `FFI::Node` in `TreeHaver::Node`
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
    # == Platform Compatibility
    #
    # - MRI Ruby: ✓ Full support
    # - JRuby: ✓ Full support (uses JNR-FFI)
    # - TruffleRuby: ✗ TruffleRuby's FFI doesn't support STRUCT_BY_VALUE return types
    #   (used by ts_tree_root_node, ts_node_child, ts_node_start_point, etc.)
    #
    # @note Requires the `ffi` gem and libtree-sitter shared library to be installed
    # @see https://github.com/ffi/ffi Ruby FFI
    # @see https://tree-sitter.github.io/tree-sitter/ tree-sitter
    module FFI
      # Module-level availability and capability methods
      #
      # These methods provide API consistency with other backends.
      class << self
        # Check if the FFI backend is available
        #
        # The FFI backend requires:
        # - The ffi gem to be installed
        # - NOT running on TruffleRuby (STRUCT_BY_VALUE limitation)
        # - MRI backend (ruby_tree_sitter) not already loaded (symbol conflicts)
        #
        # @return [Boolean] true if FFI backend can be used
        # @example
        #   if TreeHaver::Backends::FFI.available?
        #     puts "FFI backend is ready"
        #   end
        def available?
          return false unless ffi_gem_available?

          # Check if MRI backend has been loaded (which blocks FFI)
          !defined?(::TreeSitter::Parser)
        end

        # Check if the FFI gem can be loaded and is usable for tree-sitter
        #
        # @return [Boolean] true if FFI gem can be loaded and works with tree-sitter
        # @api private
        # @note Returns false on TruffleRuby because TruffleRuby's FFI doesn't support
        #   STRUCT_BY_VALUE return types (used by ts_tree_root_node, ts_node_child, etc.)
        def ffi_gem_available?
          return @loaded if @load_attempted # rubocop:disable ThreadSafety/ClassInstanceVariable
          @load_attempted = true # rubocop:disable ThreadSafety/ClassInstanceVariable

          @loaded = begin # rubocop:disable ThreadSafety/ClassInstanceVariable
            # TruffleRuby's FFI doesn't support STRUCT_BY_VALUE return types
            # which tree-sitter uses extensively (ts_tree_root_node, ts_node_child, etc.)
            # simplecov:disable TruffleRuby returns false early - subsequent FFI code paths unreachable on TruffleRuby
            if RUBY_ENGINE == "truffleruby"
              false
            # simplecov:enable
            else
              require "ffi"
              true
            end
          rescue LoadError
            false
            # simplecov:disable defensive code - StandardError during require is extremely rare
          rescue StandardError
            false
            # simplecov:enable
          end
          @loaded # rubocop:disable ThreadSafety/ClassInstanceVariable
        end

        # Reset the load state (primarily for testing)
        #
        # @return [void]
        # @api private
        def reset!
          @load_attempted = false # rubocop:disable ThreadSafety/ClassInstanceVariable
          @loaded = false # rubocop:disable ThreadSafety/ClassInstanceVariable
        end

        # Get capabilities supported by this backend
        #
        # @return [Hash{Symbol => Object}] capability map
        # @example
        #   TreeHaver::Backends::FFI.capabilities
        #   # => { backend: :ffi, parse: true, query: false, bytes_field: true, comment_support: :nodes_only }
        def capabilities
          return {} unless available?
          {
            backend: :ffi,
            parse: true,
            query: false, # Query API not yet implemented in FFI backend
            bytes_field: true,
            incremental: false,
            comment_support: :nodes_only,
          }
        end
      end

      # Native FFI bindings to libtree-sitter
      #
      # This module handles loading the tree-sitter runtime library and defining
      # FFI function attachments for the core tree-sitter API.
      #
      # All FFI operations are lazy - nothing is loaded until actually needed.
      # This prevents polluting the Ruby environment at require time.
      #
      # @api private
      module Native
        class << self
          # Lazily extend with FFI::Library only when needed
          #
          # @return [Boolean] true if FFI was successfully extended
          def ensure_ffi_extended!
            return true if @ffi_extended

            unless FFI.ffi_gem_available?
              raise TreeHaver::NotAvailable, "FFI gem is not available"
            end

            extend(::FFI::Library)

            define_ts_point_struct!
            define_ts_node_struct!
            @ffi_extended = true
          end

          # Define the TSPoint struct lazily
          # @api private
          def define_ts_point_struct!
            return if const_defined?(:TSPoint, false)

            # FFI struct representation of TSPoint
            # Mirrors the C struct layout: struct { uint32_t row; uint32_t column; }
            ts_point_class = Class.new(::FFI::Struct) do
              layout :row,
                :uint32,
                :column,
                :uint32
            end
            const_set(:TSPoint, ts_point_class)
            typedef(ts_point_class.by_value, :ts_point)
          end

          # Define the TSNode struct lazily
          # @api private
          def define_ts_node_struct!
            return if const_defined?(:TSNode, false)

            # FFI struct representation of TSNode
            # Mirrors the C struct layout used by tree-sitter
            ts_node_class = Class.new(::FFI::Struct) do
              layout :context,
                [:uint32, 4],
                :id,
                :pointer,
                :tree,
                :pointer
            end
            const_set(:TSNode, ts_node_class)
            typedef(ts_node_class.by_value, :ts_node)
          end

          # Get the TSNode class, ensuring it's defined
          # @return [Class] the TSNode FFI struct class
          def ts_node_class
            ensure_ffi_extended!
            const_get(:TSNode)
          end

          # Get list of candidate library names for loading libtree-sitter
          #
          # The list is built dynamically to respect environment variables set at runtime.
          # If TREE_SITTER_RUNTIME_LIB is set, it is tried first.
          #
          # @note TREE_SITTER_LIB is intentionally NOT supported
          # @return [Array<String>] list of library names to try
          def lib_candidates
            [
              ENV["TREE_SITTER_RUNTIME_LIB"],
              "tree-sitter",
              "libtree-sitter.so.0",
              "libtree-sitter.so",
              "libtree-sitter.dylib",
              "libtree-sitter.dll",
            ].compact
          end

          # Load the tree-sitter runtime library
          #
          # Tries each candidate library name in order until one succeeds.
          # After loading, attaches FFI function definitions for the tree-sitter API.
          #
          # @raise [TreeHaver::NotAvailable] if no library can be loaded
          # @return [void]
          def try_load!
            return if @loaded

            ensure_ffi_extended!

            # Warn about potential conflicts with MRI backend
            if defined?(::TreeSitter) && defined?(::TreeSitter::Parser)
              warn("TreeHaver: FFI backend loading after ruby_tree_sitter (MRI backend). " \
                "This may cause symbol conflicts due to different libtree-sitter versions. " \
                "Consider using only one backend per process, or set TREE_SITTER_RUNTIME_LIB " \
                "to match the version used by ruby_tree_sitter.") if $VERBOSE
            end

            last_error = nil
            candidates = lib_candidates
            lib_loaded = false
            candidates.each do |name|
              ffi_lib(name)
              lib_loaded = true
              break
            rescue LoadError => e
              # Note: FFI::NotFoundError inherits from LoadError, so it's caught here too
              last_error = e
            end

            unless lib_loaded
              # simplecov:disable
              tried = candidates.join(", ")
              env_hint = ENV["TREE_SITTER_RUNTIME_LIB"] ? " TREE_SITTER_RUNTIME_LIB=#{ENV["TREE_SITTER_RUNTIME_LIB"]}." : ""
              msg = if last_error
                "Could not load libtree-sitter (tried: #{tried}).#{env_hint} #{last_error.class}: #{last_error.message}"
              else
                "Could not load libtree-sitter (tried: #{tried}).#{env_hint}"
              end
              raise TreeHaver::NotAvailable, msg
              # simplecov:enable
            end

            # Attach functions after lib is selected
            # Note: TruffleRuby's FFI doesn't support STRUCT_BY_VALUE return types,
            # so these attach_function calls will fail on TruffleRuby.
            attach_function(:ts_parser_new, [], :pointer)
            attach_function(:ts_parser_delete, [:pointer], :void)
            attach_function(:ts_parser_set_language, [:pointer, :pointer], :bool)
            attach_function(:ts_parser_parse_string, [:pointer, :pointer, :string, :uint32], :pointer)

            attach_function(:ts_tree_delete, [:pointer], :void)
            attach_function(:ts_tree_root_node, [:pointer], :ts_node)

            attach_function(:ts_node_type, [:ts_node], :string)
            attach_function(:ts_node_child_count, [:ts_node], :uint32)
            attach_function(:ts_node_child, [:ts_node, :uint32], :ts_node)
            attach_function(:ts_node_child_by_field_name, [:ts_node, :string, :uint32], :ts_node)
            attach_function(:ts_node_start_byte, [:ts_node], :uint32)
            attach_function(:ts_node_end_byte, [:ts_node], :uint32)
            attach_function(:ts_node_start_point, [:ts_node], :ts_point)
            attach_function(:ts_node_end_point, [:ts_node], :ts_point)
            attach_function(:ts_node_is_null, [:ts_node], :bool)
            attach_function(:ts_node_is_named, [:ts_node], :bool)
            attach_function(:ts_node_is_missing, [:ts_node], :bool)
            attach_function(:ts_node_has_error, [:ts_node], :bool)

            # Node navigation functions
            attach_function(:ts_node_parent, [:ts_node], :ts_node)
            attach_function(:ts_node_next_sibling, [:ts_node], :ts_node)
            attach_function(:ts_node_prev_sibling, [:ts_node], :ts_node)
            attach_function(:ts_node_next_named_sibling, [:ts_node], :ts_node)
            attach_function(:ts_node_prev_named_sibling, [:ts_node], :ts_node)
            attach_function(:ts_node_named_child, [:ts_node, :uint32], :ts_node)
            attach_function(:ts_node_named_child_count, [:ts_node], :uint32)

            # Descendant lookup functions
            attach_function(:ts_node_descendant_for_byte_range, [:ts_node, :uint32, :uint32], :ts_node)
            attach_function(:ts_node_descendant_for_point_range, [:ts_node, :ts_point, :ts_point], :ts_node)
            attach_function(:ts_node_named_descendant_for_byte_range, [:ts_node, :uint32, :uint32], :ts_node)
            attach_function(:ts_node_named_descendant_for_point_range, [:ts_node, :ts_point, :ts_point], :ts_node)

            # Only mark as fully loaded after all attach_function calls succeed
            @loaded = true
          end

          def loaded?
            !!@loaded
          end
        end
      end

      # Represents a tree-sitter language loaded via FFI
      #
      # Holds a pointer to a TSLanguage struct from a loaded shared library.
      class Language
        include Comparable

        # The FFI pointer to the TSLanguage struct
        # @return [FFI::Pointer]
        attr_reader :pointer

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
        # @param ptr [FFI::Pointer] pointer to TSLanguage
        # @param lib [FFI::DynamicLibrary, nil] the opened dynamic library
        #   (kept as an instance variable to prevent it being GC'd/unloaded)
        # @param path [String, nil] path language was loaded from
        # @param symbol [String, nil] symbol name
        def initialize(ptr, lib = nil, path: nil, symbol: nil)
          @pointer = ptr
          @backend = :ffi
          @path = path
          @symbol = symbol
          # Keep a reference to the DynamicLibrary that produced the language
          # pointer so it isn't garbage-collected and unloaded while the
          # pointer is still in use by the parser. Not keeping this reference
          # can lead to the language pointer becoming invalid and causing
          # segmentation faults when passed to native functions.
          @library = lib
        end

        # Compare languages for equality
        #
        # FFI languages are equal if they have the same backend, path, and symbol.
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

        # Get the language name
        #
        # Derives a name from the symbol or path.
        #
        # @return [Symbol] language name
        def language_name
          # Try to derive from symbol (e.g., "tree_sitter_toml" -> :toml)
          if @symbol
            name = @symbol.to_s.sub(/^tree_sitter_/, "")
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
        alias_method :name, :language_name

        # Convert to FFI pointer for passing to native functions
        #
        # @return [FFI::Pointer]
        def to_ptr
          @pointer
        end

        # Load a language from a shared library
        #
        # The library must export a function that returns a pointer to a TSLanguage struct.
        # Symbol resolution uses this precedence (when symbol: not provided):
        # 1. ENV["TREE_SITTER_LANG_SYMBOL"]
        # 2. Guessed from filename (e.g., "libtree-sitter-toml.so" → "tree_sitter_toml")
        # 3. Default fallback ("tree_sitter_toml")
        #
        # @param path [String] absolute path to the language shared library
        # @param symbol [String, nil] explicit exported function name (highest precedence)
        # @param name [String, nil] optional logical name (accepted for compatibility, not used)
        # @return [Language] loaded language handle
        # @raise [TreeHaver::NotAvailable] if FFI not available or library cannot be loaded
        # @example
        #   lang = TreeHaver::Backends::FFI::Language.from_library(
        #     "/usr/local/lib/libtree-sitter-toml.so",
        #     symbol: "tree_sitter_toml"
        #   )
        class << self
          def from_library(path, symbol: nil, name: nil)
            raise TreeHaver::NotAvailable, "FFI not available" unless Backends::FFI.available?

            # Check for MRI backend conflict BEFORE loading the grammar
            # If ruby_tree_sitter has already loaded this grammar file, the dynamic
            # linker will return the cached library with symbols resolved against
            # MRI's statically-linked tree-sitter, causing segfaults when FFI
            # tries to use the pointer with its dynamically-linked libtree-sitter.
            if defined?(::TreeSitter::Language)
              # MRI backend has been loaded - check if it might have loaded this grammar
              # We can't reliably detect which grammars MRI loaded, so we warn and
              # attempt to proceed. The segfault will occur when setting language on parser.
              warn("TreeHaver: FFI backend loading grammar after ruby_tree_sitter (MRI backend). " \
                "This may cause segfaults due to tree-sitter symbol conflicts. " \
                "For reliable operation, use only one backend per process.") if $VERBOSE
            end

            # Ensure the core libtree-sitter runtime is loaded first so
            # the language shared library resolves its symbols against the
            # same runtime. This prevents cases where the language pointer
            # is incompatible with the parser (different lib instances).
            Native.try_load!

            begin
              # Prefer resolving symbols immediately and globally so the
              # language library links to the already-loaded libtree-sitter
              # (RTLD_NOW | RTLD_GLOBAL). If those constants are not present
              # fall back to RTLD_LAZY for maximum compatibility.
              flags = if defined?(::FFI::DynamicLibrary::RTLD_NOW) && defined?(::FFI::DynamicLibrary::RTLD_GLOBAL)
                ::FFI::DynamicLibrary::RTLD_NOW | ::FFI::DynamicLibrary::RTLD_GLOBAL
              else
                ::FFI::DynamicLibrary::RTLD_LAZY
              end

              dl = ::FFI::DynamicLibrary.open(path, flags)
            rescue LoadError, RuntimeError => e
              # TruffleRuby raises RuntimeError instead of LoadError when a shared library cannot be opened
              raise TreeHaver::NotAvailable, "Could not open language library at #{path}: #{e.message}"
            end

            requested = symbol || ENV["TREE_SITTER_LANG_SYMBOL"]
            # Use shared utility for consistent symbol derivation across backends
            guessed_symbol = LibraryPathUtils.derive_symbol_from_path(path)
            # If an override was provided (arg or ENV), treat it as strict and do not fall back.
            # Only when no override is provided do we attempt guessed and default candidates.
            candidates = if requested && !requested.to_s.empty?
              [requested]
            else
              [guessed_symbol, "tree_sitter_toml"].compact.uniq
            end

            func = nil
            last_err = nil
            candidates.each do |name|
              addr = dl.find_function(name)
              func = ::FFI::Function.new(:pointer, [], addr)
              break
            rescue StandardError => e
              last_err = e
            end
            unless func
              env_used = []
              env_used << "TREE_SITTER_LANG_SYMBOL=#{ENV["TREE_SITTER_LANG_SYMBOL"]}" if ENV["TREE_SITTER_LANG_SYMBOL"]
              detail = env_used.empty? ? "" : " Env overrides: #{env_used.join(", ")}."
              raise TreeHaver::NotAvailable, "Could not resolve language symbol in #{path} (tried: #{candidates.join(", ")}).#{detail} #{last_err&.message}"
            end

            # Only ensure the core lib is loaded when we actually need to interact with it
            # (e.g., during parsing). Creating the Language handle does not require core to be loaded.
            ptr = func.call
            raise TreeHaver::NotAvailable, "Language factory returned NULL for #{path}" if ptr.null?
            # Pass the opened DynamicLibrary into the Language instance so the
            # library handle remains alive for the lifetime of the Language.
            new(ptr, dl, path: path, symbol: symbol)
          end

          # Backward-compatible alias
          alias_method :from_path, :from_library
        end
      end

      # FFI-based tree-sitter parser
      #
      # Wraps a TSParser pointer and manages its lifecycle with a finalizer.
      class Parser
        # Create a new parser instance
        #
        # @raise [TreeHaver::NotAvailable] if FFI not available or parser creation fails
        def initialize
          raise TreeHaver::NotAvailable, "FFI not available" unless Backends::FFI.available?

          Native.try_load!
          @parser = Native.ts_parser_new
          raise TreeHaver::NotAvailable, "Failed to create ts_parser" if @parser.null?

          # Note: We intentionally do NOT register a finalizer here because:
          # 1. ts_parser_delete can segfault if called during certain GC scenarios
          # 2. The native library may be unloaded before finalizers run
          # 3. Parser cleanup happens automatically on process exit
          # 4. Long-running processes should explicitly manage parser lifecycle
          #
          # If you need explicit cleanup in long-running processes, store the
          # parser in an instance variable and call a cleanup method explicitly
          # when done, rather than relying on GC finalizers.
        end

        # Set the language for this parser
        #
        # Note: FFI backend is special - it receives the wrapped Language object
        # because it needs to call to_ptr to get the FFI pointer. TreeHaver::Parser
        # detects FFI Language wrappers (respond_to?(:to_ptr)) and passes them through.
        #
        # @param lang [Language] the FFI language wrapper (not unwrapped)
        # @return [Language] the language that was set
        # @raise [TreeHaver::NotAvailable] if setting the language fails
        def language=(lang)
          # Defensive check: ensure we received an FFI Language wrapper
          unless lang.is_a?(Language)
            raise TreeHaver::NotAvailable,
              "FFI backend expected FFI::Language wrapper, got #{lang.class}. " \
                "This usually means TreeHaver::Parser#unwrap_language passed the wrong type. " \
                "Check that language caching respects backend boundaries."
          end

          # Additional check: verify the language is actually for FFI backend
          if lang.respond_to?(:backend) && lang.backend != :ffi
            raise TreeHaver::NotAvailable,
              "FFI backend received Language for wrong backend: #{lang.backend}. " \
                "Expected :ffi backend. Class: #{lang.class}. " \
                "Path: #{lang.path.inspect}, Symbol: #{lang.symbol.inspect}"
          end

          # Verify the DynamicLibrary is still valid (not GC'd)
          # The Language stores @library to prevent this, but let's verify
          lib = lang.instance_variable_get(:@library)
          if lib.nil?
            raise TreeHaver::NotAvailable,
              "FFI Language has no library reference. The dynamic library may have been unloaded. " \
                "Path: #{lang.path.inspect}, Symbol: #{lang.symbol.inspect}"
          end

          # Verify the language has a valid pointer
          ptr = lang.to_ptr

          # Check ptr is actually an FFI::Pointer
          unless ptr.is_a?(::FFI::Pointer)
            raise TreeHaver::NotAvailable,
              "FFI Language#to_ptr returned #{ptr.class}, expected FFI::Pointer. " \
                "Language class: #{lang.class}. " \
                "Path: #{lang.path.inspect}, Symbol: #{lang.symbol.inspect}"
          end

          ptr_address = ptr.address

          # Check for NULL (0x0)
          if ptr.nil? || ptr_address.zero?
            raise TreeHaver::NotAvailable,
              "FFI Language has NULL pointer. Language may not have loaded correctly. " \
                "Path: #{lang.path.inspect}, Symbol: #{lang.symbol.inspect}"
          end

          # Check for small invalid addresses (< 4KB are typically unmapped memory)
          # Common invalid addresses like 0x40 (64) indicate corrupted or uninitialized pointers
          if ptr_address < 4096
            raise TreeHaver::NotAvailable,
              "FFI Language has invalid pointer (address 0x#{ptr_address.to_s(16)}). " \
                "This usually indicates the language library was unloaded or never loaded correctly. " \
                "Path: #{lang.path.inspect}, Symbol: #{lang.symbol.inspect}"
          end

          # Note: MRI backend conflict is now handled by TreeHaver::BackendConflict
          # at a higher level (in TreeHaver.resolve_backend_module)

          # lang is a wrapped FFI::Language that has to_ptr method
          ok = Native.ts_parser_set_language(@parser, ptr)
          raise TreeHaver::NotAvailable, "Failed to set language on parser" unless ok

          lang # rubocop:disable Lint/Void (intentional return value)
        end

        # Parse source code into a syntax tree
        #
        # @param source [String] the source code to parse (should be UTF-8)
        # @return [Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        # @raise [TreeHaver::NotAvailable] if parsing fails
        def parse(source)
          src = String(source)
          tree_ptr = Native.ts_parser_parse_string(@parser, ::FFI::Pointer::NULL, src, src.bytesize)
          raise TreeHaver::NotAvailable, "Parse returned NULL" if tree_ptr.null?

          # Return raw FFI::Tree - TreeHaver::Parser will wrap it
          Tree.new(tree_ptr)
        end
      end

      # FFI-based tree-sitter tree
      #
      # Wraps a TSTree pointer and manages its lifecycle with a finalizer.
      #
      # Note: Tree objects DO use finalizers (unlike Parser objects) because:
      # 1. Trees are typically short-lived and numerous (one per parse)
      # 2. ts_tree_delete is safer than ts_parser_delete during GC
      # 3. Memory leaks from accumulated trees are more problematic
      # 4. The finalizer silently ignores errors for safety
      class Tree
        # @api private
        # @param ptr [FFI::Pointer] pointer to TSTree
        def initialize(ptr)
          @ptr = ptr
          ObjectSpace.define_finalizer(self, self.class.finalizer(@ptr))
        end

        # @api private
        # @param ptr [FFI::Pointer] pointer to TSTree
        class << self
          # Returns a finalizer proc that deletes the tree
          #
          # This is public API for testing purposes, but not intended for
          # direct use. The finalizer is automatically registered when
          # creating a Tree object.
          #
          # @return [Proc] finalizer that deletes the tree
          def finalizer(ptr)
            proc {
              begin
                Native.ts_tree_delete(ptr)
              rescue StandardError
                # Silently ignore errors during finalization to prevent crashes
                # during GC. If the library is unloaded or ptr is invalid, we
                # don't want to crash the entire process.
                nil
              end
            }
          end
        end

        # Get the root node of the syntax tree
        #
        # @return [Node] the root node
        def root_node
          node_val = Native.ts_tree_root_node(@ptr)
          Node.new(node_val)
        end
      end

      # FFI-based tree-sitter node (raw backend node)
      #
      # This is a **raw backend node** that wraps a TSNode by-value struct from the
      # tree-sitter C API. It provides the minimal interface needed for tree-sitter
      # operations but is NOT intended for direct use by application code.
      #
      # == Architecture Note
      #
      # Unlike pure-Ruby backends (Citrus, Parslet, Prism, Psych) which define Node
      # classes that inherit from `TreeHaver::Base::Node`, tree-sitter backends (MRI,
      # Rust, FFI, Java) define raw wrapper classes that get wrapped by `TreeHaver::Node`.
      #
      # The wrapping hierarchy is:
      #   FFI::Node (this class) → TreeHaver::Node → Base::Node
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
      # This raw class only implements methods that require direct FFI calls to the
      # tree-sitter C library. The wrapper adds Ruby-level conveniences.
      #
      # @api private
      # @see TreeHaver::Node The wrapper class users should interact with
      # @see TreeHaver::Base::Node The base class documenting the full Node API
      class Node
        include Enumerable

        # @api private
        # @param ts_node_value [Native::TSNode] the TSNode struct (by value)
        def initialize(ts_node_value)
          # Store by-value struct (FFI will copy); methods pass it back by value
          @val = ts_node_value
        end

        # Get the type name of this node
        #
        # @return [String] the node type (e.g., "document", "table", "pair")
        def type
          Native.ts_node_type(@val)
        end

        # Get the number of children
        #
        # @return [Integer] child count
        def child_count
          Native.ts_node_child_count(@val)
        end

        # Get a child by index
        #
        # @param index [Integer] child index
        # @return [Node, nil] child node or nil if index out of bounds
        def child(index)
          return if index >= child_count || index < 0
          child_node = Native.ts_node_child(@val, index)
          Node.new(child_node)
        end

        # Get a child node by field name
        #
        # Tree-sitter grammars define named fields for certain child positions.
        # For example, in JSON, a "pair" node has "key" and "value" fields.
        #
        # @param field_name [String] the field name to look up
        # @return [Node, nil] the child node, or nil if no child has that field
        # @example Get the key from a JSON pair
        #   pair.child_by_field_name("key") #=> Node (type: "string")
        #   pair.child_by_field_name("value") #=> Node (type: "string" or "number", etc.)
        def child_by_field_name(field_name)
          name = String(field_name)
          child_node = Native.ts_node_child_by_field_name(@val, name, name.bytesize)
          # ts_node_child_by_field_name returns a null node if field not found
          return if Native.ts_node_is_null(child_node)

          Node.new(child_node)
        end

        # Get start byte offset
        #
        # @return [Integer]
        def start_byte
          Native.ts_node_start_byte(@val)
        end

        # Get end byte offset
        #
        # @return [Integer]
        def end_byte
          Native.ts_node_end_byte(@val)
        end

        # Get start point
        #
        # @return [TreeHaver::Point] with row and column
        def start_point
          point = Native.ts_node_start_point(@val)
          # TSPoint is returned by value as an FFI::Struct with :row and :column fields
          TreeHaver::Point.new(point[:row], point[:column])
        end

        # Get end point
        #
        # @return [TreeHaver::Point] with row and column
        def end_point
          point = Native.ts_node_end_point(@val)
          # TSPoint is returned by value as an FFI::Struct with :row and :column fields
          TreeHaver::Point.new(point[:row], point[:column])
        end

        # Check if node has error
        #
        # Returns true if this node or any of its descendants have a syntax error.
        # This is the FFI equivalent of tree-sitter's ts_node_has_error.
        #
        # @return [Boolean] true if node subtree contains errors
        def has_error?
          # Explicit boolean conversion ensures consistent behavior across Ruby versions
          # FFI :bool return type may behave differently on some platforms
          !!Native.ts_node_has_error(@val)
        end

        # Check if this is a MISSING node
        #
        # A MISSING node represents a token that was expected by the grammar
        # but was not found in the source. Tree-sitter inserts MISSING nodes
        # to allow parsing to continue despite syntax errors.
        #
        # @return [Boolean] true if this is a MISSING node
        def missing?
          !!Native.ts_node_is_missing(@val)
        end

        # Check if this is a named node
        #
        # Named nodes represent syntactic constructs (e.g., "pair", "object").
        # Anonymous nodes represent syntax/punctuation (e.g., "{", ",").
        #
        # @return [Boolean] true if this is a named node
        def named?
          !!Native.ts_node_is_named(@val)
        end

        # Get the parent node
        #
        # @return [Node, nil] parent node or nil if this is the root
        def parent
          parent_node = Native.ts_node_parent(@val)
          return if Native.ts_node_is_null(parent_node)

          Node.new(parent_node)
        end

        # Get the next sibling node
        #
        # @return [Node, nil] next sibling or nil if none
        def next_sibling
          sibling = Native.ts_node_next_sibling(@val)
          return if Native.ts_node_is_null(sibling)

          Node.new(sibling)
        end

        # Get the previous sibling node
        #
        # @return [Node, nil] previous sibling or nil if none
        def prev_sibling
          sibling = Native.ts_node_prev_sibling(@val)
          return if Native.ts_node_is_null(sibling)

          Node.new(sibling)
        end

        # Get the next named sibling node
        #
        # @return [Node, nil] next named sibling or nil if none
        def next_named_sibling
          sibling = Native.ts_node_next_named_sibling(@val)
          return if Native.ts_node_is_null(sibling)

          Node.new(sibling)
        end

        # Get the previous named sibling node
        #
        # @return [Node, nil] previous named sibling or nil if none
        def prev_named_sibling
          sibling = Native.ts_node_prev_named_sibling(@val)
          return if Native.ts_node_is_null(sibling)

          Node.new(sibling)
        end

        # Get a named child by index
        #
        # @param index [Integer] named child index (0-based)
        # @return [Node, nil] named child or nil if index out of bounds
        def named_child(index)
          return if index < 0 || index >= named_child_count

          child_node = Native.ts_node_named_child(@val, index)
          return if Native.ts_node_is_null(child_node)

          Node.new(child_node)
        end

        # Get the count of named children
        #
        # @return [Integer] number of named children
        def named_child_count
          Native.ts_node_named_child_count(@val)
        end

        # Find the smallest descendant that spans the given byte range
        #
        # @param start_byte [Integer] start byte offset
        # @param end_byte [Integer] end byte offset
        # @return [Node, nil] descendant node or nil if not found
        def descendant_for_byte_range(start_byte, end_byte)
          node = Native.ts_node_descendant_for_byte_range(@val, start_byte, end_byte)
          return if Native.ts_node_is_null(node)

          Node.new(node)
        end

        # Find the smallest named descendant that spans the given byte range
        #
        # @param start_byte [Integer] start byte offset
        # @param end_byte [Integer] end byte offset
        # @return [Node, nil] named descendant node or nil if not found
        def named_descendant_for_byte_range(start_byte, end_byte)
          node = Native.ts_node_named_descendant_for_byte_range(@val, start_byte, end_byte)
          return if Native.ts_node_is_null(node)

          Node.new(node)
        end

        # Find the smallest descendant that spans the given point range
        #
        # @param start_point [TreeHaver::Point, Hash] start point with :row and :column
        # @param end_point [TreeHaver::Point, Hash] end point with :row and :column
        # @return [Node, nil] descendant node or nil if not found
        def descendant_for_point_range(start_point, end_point)
          start_pt = Native::TSPoint.new
          start_pt[:row] = start_point.respond_to?(:row) ? start_point.row : start_point[:row]
          start_pt[:column] = start_point.respond_to?(:column) ? start_point.column : start_point[:column]

          end_pt = Native::TSPoint.new
          end_pt[:row] = end_point.respond_to?(:row) ? end_point.row : end_point[:row]
          end_pt[:column] = end_point.respond_to?(:column) ? end_point.column : end_point[:column]

          node = Native.ts_node_descendant_for_point_range(@val, start_pt, end_pt)
          return if Native.ts_node_is_null(node)

          Node.new(node)
        end

        # Find the smallest named descendant that spans the given point range
        #
        # @param start_point [TreeHaver::Point, Hash] start point with :row and :column
        # @param end_point [TreeHaver::Point, Hash] end point with :row and :column
        # @return [Node, nil] named descendant node or nil if not found
        def named_descendant_for_point_range(start_point, end_point)
          start_pt = Native::TSPoint.new
          start_pt[:row] = start_point.respond_to?(:row) ? start_point.row : start_point[:row]
          start_pt[:column] = start_point.respond_to?(:column) ? start_point.column : start_point[:column]

          end_pt = Native::TSPoint.new
          end_pt[:row] = end_point.respond_to?(:row) ? end_point.row : end_point[:row]
          end_pt[:column] = end_point.respond_to?(:column) ? end_point.column : end_point[:column]

          node = Native.ts_node_named_descendant_for_point_range(@val, start_pt, end_pt)
          return if Native.ts_node_is_null(node)

          Node.new(node)
        end

        # Iterate over child nodes
        #
        # @yieldparam child [Node] each child node
        # @return [Enumerator, nil] an enumerator if no block given, nil otherwise
        def each
          return enum_for(:each) unless block_given?

          count = child_count
          i = 0
          while i < count
            child = Native.ts_node_child(@val, i)
            yield Node.new(child)
            i += 1
          end
          nil
        end

        # Compare nodes for ordering (used by Comparable module)
        #
        # Nodes are ordered by their position in the source:
        # 1. First by start_byte (earlier nodes come first)
        # 2. Then by end_byte for tie-breaking (shorter spans come first)
        # 3. Then by type for deterministic ordering
        #
        # @param other [Node] node to compare with
        # @return [Integer, nil] -1, 0, 1, or nil if not comparable
        def <=>(other)
          return unless other.is_a?(Node)

          cmp = start_byte <=> other.start_byte
          return cmp if cmp.nonzero?

          cmp = end_byte <=> other.end_byte
          return cmp if cmp.nonzero?

          type <=> other.type
        end
      end

      # Register the availability checker for RSpec dependency tags
      TreeHaver::BackendRegistry.register_availability_checker(:ffi) do
        available?
      end
    end
  end
end
