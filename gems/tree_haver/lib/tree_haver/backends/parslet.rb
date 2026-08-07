# frozen_string_literal: true

module TreeHaver
  module Backends
    # Parslet backend using pure Ruby PEG parser
    #
    # This backend wraps Parslet-based parsers (like the toml gem) to provide a
    # pure Ruby alternative to tree-sitter. Parslet is a PEG (Parsing Expression
    # Grammar) parser generator written in Ruby that produces Hash/Array/Slice
    # results rather than a traditional AST.
    #
    # Unlike tree-sitter backends which are language-agnostic runtime parsers,
    # Parslet parsers are grammar-specific and defined as Ruby classes. Each
    # language needs its own Parslet grammar (e.g., TOML::Parslet for TOML).
    #
    # @note This backend requires a Parslet grammar class for the specific language
    # @see https://github.com/kschiess/parslet Parslet parser generator
    # @see https://github.com/jm/toml toml gem (TOML Parslet grammar)
    #
    # @example Using with toml gem
    #   require "toml"
    #
    #   parser = TreeHaver::Parser.new
    #   # For Parslet, "language" is actually a grammar class
    #   parser.language = TOML::Parslet
    #   tree = parser.parse(toml_source)
    module Parslet
      @load_attempted = false
      @loaded = false

      # Check if the Parslet backend is available
      #
      # Attempts to require parslet on first call and caches the result.
      #
      # @return [Boolean] true if parslet gem is available
      # @example
      #   if TreeHaver::Backends::Parslet.available?
      #     puts "Parslet backend is ready"
      #   end
      class << self
        def available?
          return @loaded if @load_attempted

          @load_attempted = true
          begin
            require 'parslet'
            @loaded = true
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
        #   TreeHaver::Backends::Parslet.capabilities
        #   # => { backend: :parslet, query: false, bytes_field: true, incremental: false, comment_support: :none }
        def capabilities
          return {} unless available?

          {
            backend: :parslet,
            query: false,          # Parslet doesn't have a query API like tree-sitter
            bytes_field: true,     # Parslet::Slice provides offset and length
            incremental: false,    # Parslet doesn't support incremental parsing
            pure_ruby: true,       # Parslet is pure Ruby (portable)
            comment_support: :none
          }
        end
      end

      # Parslet grammar wrapper
      #
      # Unlike tree-sitter which loads compiled .so files, Parslet uses Ruby classes
      # that define grammars. This class wraps a Parslet grammar class.
      #
      # @example
      #   # For TOML, use toml gem's grammar
      #   language = TreeHaver::Backends::Parslet::Language.new(TOML::Parslet)
      class Language
        include Comparable

        # The Parslet grammar class
        # @return [Class] Parslet grammar class (e.g., TOML::Parslet)
        attr_reader :grammar_class

        # The backend this language is for
        # @return [Symbol]
        attr_reader :backend

        # @param grammar_class [Class] A Parslet grammar class (inherits from ::Parslet::Parser)
        def initialize(grammar_class)
          unless valid_grammar_class?(grammar_class)
            raise TreeHaver::NotAvailable,
                  'Grammar class must be a Parslet::Parser subclass or respond to :new and return a parser with :parse. ' \
                    'Expected a Parslet grammar class (e.g., TOML::Parslet).'
          end
          @grammar_class = grammar_class
          @backend = :parslet
        end

        # Get the language name
        #
        # Derives a name from the grammar class name.
        #
        # @return [Symbol] language name
        def language_name
          # Derive name from grammar class (e.g., TOML::Parslet -> :toml)
          return :unknown unless @grammar_class.respond_to?(:name) && @grammar_class.name

          name = @grammar_class.name.to_s.split('::').first.downcase
          name.to_sym
        end

        # Alias for language_name (API compatibility)
        alias name language_name

        # Compare languages for equality
        #
        # Parslet languages are equal if they have the same backend and grammar_class.
        # Grammar class uniquely identifies a Parslet language.
        #
        # @param other [Object] object to compare with
        # @return [Integer, nil] -1, 0, 1, or nil if not comparable
        def <=>(other)
          return unless other.is_a?(Language)
          return unless other.backend == @backend

          # Compare by grammar_class name (classes are compared by object_id by default)
          @grammar_class.name <=> other.grammar_class.name
        end

        # Hash value for this language (for use in Sets/Hashes)
        # @return [Integer]
        def hash
          [@backend, @grammar_class.name].hash
        end

        # Alias eql? to ==
        alias eql? ==

        # Load language from library path (API compatibility)
        #
        # Parslet grammars are Ruby classes, not shared libraries. This method
        # provides API compatibility with tree-sitter backends by looking up
        # registered Parslet grammars by name.
        #
        # For full API consistency, register a Parslet grammar with:
        #   TreeHaver.register_language(:toml, grammar_class: TOML::Parslet)
        #
        # Then this method will find it when called via `TreeHaver.parser_for(:toml)`.
        #
        # @param path [String, nil] Ignored for Parslet (used to derive language name)
        # @param symbol [String, nil] Used to derive language name if path not provided
        # @param name [String, Symbol, nil] Language name to look up
        # @return [Language] Parslet language wrapper
        # @raise [TreeHaver::NotAvailable] if no Parslet grammar is registered for the language
        class << self
          def from_library(path = nil, symbol: nil, name: nil)
            # Derive language name from path, symbol, or explicit name
            lang_name = name&.to_sym ||
                        symbol&.to_s&.sub(/^tree_sitter_/, '')&.to_sym ||
                        path && TreeHaver::LibraryPathUtils.derive_language_name_from_path(path)&.to_sym

            unless lang_name
              raise TreeHaver::NotAvailable,
                    'Parslet backend requires a language name. ' \
                      'Provide name: parameter or register a grammar with TreeHaver.register_language.'
            end

            # Look up registered Parslet grammar
            registration = TreeHaver::LanguageRegistry.registered(lang_name, :parslet)

            unless registration
              raise TreeHaver::NotAvailable,
                    "No Parslet grammar registered for #{lang_name.inspect}. " \
                      "Register one with: TreeHaver.register_language(:#{lang_name}, grammar_class: YourGrammar)"
            end

            grammar_class = registration[:grammar_class]
            new(grammar_class)
          end

          alias from_path from_library
        end

        private

        def valid_grammar_class?(klass)
          return false unless klass.respond_to?(:new)

          # Check if it's a Parslet::Parser subclass
          return true if defined?(::Parslet::Parser) && (klass < ::Parslet::Parser)

          # Fallback: check if it can create an instance that responds to parse
          begin
            instance = klass.new
            instance.respond_to?(:parse)
          rescue StandardError
            false
          end
        end
      end

      # Parslet parser wrapper
      #
      # Wraps Parslet grammar classes to provide a tree-sitter-like API.
      class Parser
        # Create a new Parslet parser instance
        #
        # @raise [TreeHaver::NotAvailable] if parslet gem is not available
        def initialize
          raise TreeHaver::NotAvailable, 'parslet gem not available' unless Parslet.available?

          @grammar = nil
          @backend = :parslet
        end

        attr_reader :backend

        # Set the grammar for this parser
        #
        # Accepts either a Parslet::Language wrapper or a raw Parslet grammar class.
        # When passed a Language wrapper, extracts the grammar_class from it.
        # When passed a raw grammar class, uses it directly.
        #
        # This flexibility allows both patterns:
        #   parser.language = TreeHaver::Backends::Parslet::Language.new(TOML::Parslet)
        #   parser.language = TOML::Parslet  # Also works
        #
        # @param grammar [Language, Class] Parslet Language wrapper or grammar class
        # @return [void]
        def language=(grammar)
          # Accept Language wrapper or raw grammar class
          actual_grammar = case grammar
                           when Language
                             grammar.grammar_class
                           else
                             grammar
                           end

          unless actual_grammar.respond_to?(:new)
            raise ArgumentError,
                  'Expected Parslet grammar class with new method or Language wrapper, ' \
                    "got #{grammar.class}"
          end
          @grammar = actual_grammar
        end

        # Parse source code
        #
        # @param source [String] the source code to parse
        # @return [Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        # @raise [TreeHaver::NotAvailable] if no grammar is set
        # @raise [::Parslet::ParseFailed] if parsing fails
        def parse(source)
          raise TreeHaver::NotAvailable, 'No grammar loaded' unless @grammar

          begin
            parser_instance = @grammar.new
            parslet_result = parser_instance.parse(source)
            # Return raw Parslet result wrapped in Tree - TreeHaver::Parser will wrap it
            Tree.new(parslet_result, source)
          rescue ::Parslet::ParseFailed => e
            # Re-raise with more context
            raise TreeHaver::Error, "Parse error: #{e.message}"
          end
        end

        # Parse source code (compatibility with tree-sitter API)
        #
        # Parslet doesn't support incremental parsing, so old_tree is ignored.
        #
        # @param old_tree [TreeHaver::Tree, nil] ignored (no incremental parsing support)
        # @param source [String] the source code to parse
        # @return [Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        def parse_string(old_tree, source) # rubocop:disable Lint/UnusedMethodArgument
          parse(source) # Parslet doesn't support incremental parsing
        end
      end

      # Parslet tree wrapper
      #
      # Wraps Parslet parse results (Hash/Array/Slice) to provide
      # tree-sitter-compatible API.
      #
      # Inherits from Base::Tree to get shared methods like #errors, #warnings,
      # #comments, #has_error?, and #inspect.
      #
      # @api private
      class Tree < TreeHaver::Base::Tree
        # The raw Parslet parse result
        # @return [Hash, Array, Parslet::Slice] The parse result
        attr_reader :parslet_result

        def initialize(parslet_result, source)
          @parslet_result = parslet_result
          super(parslet_result, source: source)
        end

        def root_node
          Node.new(@parslet_result, @source, type: 'document')
        end
      end

      # Parslet node wrapper
      #
      # Wraps Parslet parse results (Hash/Array/Slice) to provide tree-sitter-compatible node API.
      #
      # Parslet produces different result types:
      # - Hash: Named captures like {:key => value, :value => ...}
      # - Array: Repeated captures like [{...}, {...}]
      # - Parslet::Slice: Terminal string values with position info
      # - String: Plain strings (less common)
      #
      # This wrapper normalizes these into a tree-sitter-like node structure.
      #
      # Inherits from Base::Node to get shared methods like #first_child, #last_child,
      # #to_s, #inspect, #==, #<=>, #source_position, #start_line, #end_line, etc.
      #
      # @api private
      class Node < TreeHaver::Base::Node
        attr_reader :value, :node_type

        def initialize(value, source, type: nil, key: nil)
          @value = value
          @node_type = type || infer_type(key)
          @key = key
          super(value, source: source)
        end

        # -- Required API Methods (from Base::Node) ----------------------------

        # Get node type
        #
        # For Parslet results:
        # - Hash keys become node types for their values
        # - Arrays become "sequence" type
        # - Slices use their parent's key as type
        #
        # @return [String] the node type
        def type
          @node_type
        end

        # Get position information from Parslet::Slice if available
        #
        # @return [Integer] byte offset where this node starts
        def start_byte
          case @value
          when ::Parslet::Slice
            @value.offset
          when Hash
            # Find first slice in hash values
            first_slice = find_first_slice(@value)
            first_slice&.offset || 0
          when Array
            # Find first slice in array
            first_slice = find_first_slice(@value)
            first_slice&.offset || 0
          else
            0
          end
        end

        # @return [Integer] byte offset where this node ends
        def end_byte
          case @value
          when ::Parslet::Slice
            @value.offset + @value.size
          when Hash
            # Find last slice in hash values
            last_slice = find_last_slice(@value)
            last_slice ? (last_slice.offset + last_slice.size) : @source.length
          when Array
            # Find last slice in array
            last_slice = find_last_slice(@value)
            last_slice ? (last_slice.offset + last_slice.size) : @source.length
          else
            @source.length
          end
        end

        # Get all children
        #
        # @return [Array<Node>] child nodes
        def children
          case @value
          when Hash
            @value.map { |k, v| Node.new(v, @source, key: k) }
          when Array
            @value.map.with_index { |v, i| Node.new(v, @source, type: "element_#{i}") }
          else
            []
          end
        end

        # -- Overridden Methods ------------------------------------------------

        # Override start_point to calculate from source
        # @return [Hash{Symbol => Integer}] {row: 0, column: 0}
        def start_point
          calculate_point(start_byte)
        end

        # Override end_point to calculate from source
        # @return [Hash{Symbol => Integer}] {row: 0, column: 0}
        def end_point
          calculate_point(end_byte)
        end

        # Override text to handle Parslet-specific value types
        # @return [String] matched text
        def text
          case @value
          when ::Parslet::Slice
            @value.to_s
          when String
            @value
          when Hash, Array
            @source[start_byte...end_byte] || ''
          else
            @value.to_s
          end
        end

        # Override child to handle negative indices properly
        # @param index [Integer] child index
        # @return [Node, nil] child node or nil
        def child(index)
          return if index.negative?

          case @value
          when Hash
            keys = @value.keys
            return if index >= keys.size

            key = keys[index]
            Node.new(@value[key], @source, key: key)
          when Array
            return if index >= @value.size

            Node.new(@value[index], @source, type: 'element')
          end
        end

        # Override child_count for efficiency (avoid building full children array)
        # @return [Integer] child count
        def child_count
          case @value
          when Hash
            @value.keys.size
          when Array
            @value.size
          else
            0
          end
        end

        # Check if node is named
        #
        # Hash keys in Parslet results are "named" in tree-sitter terminology.
        #
        # @return [Boolean] true if this node has a key
        def named?
          !@key.nil? || @value.is_a?(Hash)
        end

        # Check if this node represents a structural element vs a terminal/token
        #
        # @return [Boolean] true if this is a structural (non-terminal) node
        def structural?
          @value.is_a?(Hash) || @value.is_a?(Array)
        end

        private

        def calculate_point(offset)
          return { row: 0, column: 0 } if offset <= 0

          lines_before = @source[0...offset].count("\n")
          line_start = (@source.rindex("\n", offset - 1) if offset.positive?)
          line_start ||= -1
          column = offset - line_start - 1
          { row: lines_before, column: column }
        end

        def infer_type(key)
          return key.to_s if key

          case @value
          when ::Parslet::Slice
            'slice'
          when Hash
            'hash'
          when Array
            'array'
          when String
            'string'
          else
            'unknown'
          end
        end

        # Find the first Parslet::Slice in a nested structure
        def find_first_slice(obj)
          case obj
          when ::Parslet::Slice
            obj
          when Hash
            obj.each_value do |v|
              result = find_first_slice(v)
              return result if result
            end
            nil
          when Array
            obj.each do |v|
              result = find_first_slice(v)
              return result if result
            end
            nil
          end
        end

        # Find the last Parslet::Slice in a nested structure
        def find_last_slice(obj)
          case obj
          when ::Parslet::Slice
            obj
          when Hash
            obj.values.reverse_each do |v|
              result = find_last_slice(v)
              return result if result
            end
            nil
          when Array
            obj.reverse_each do |v|
              result = find_last_slice(v)
              return result if result
            end
            nil
          end
        end
      end

      # Register the availability checker for RSpec dependency tags
      TreeHaver::BackendRegistry.register_availability_checker(:parslet) do
        available?
      end
    end
  end
end
