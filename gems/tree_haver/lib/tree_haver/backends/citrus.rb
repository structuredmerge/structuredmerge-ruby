# frozen_string_literal: true

module TreeHaver
  module Backends
    # Citrus backend using pure Ruby PEG parser
    #
    # This backend wraps Citrus-based parsers (like toml-rb) to provide a
    # pure Ruby alternative to tree-sitter. Citrus is a PEG (Parsing Expression
    # Grammar) parser generator written in Ruby.
    #
    # Unlike tree-sitter backends which are language-agnostic runtime parsers,
    # Citrus parsers are grammar-specific and compiled into Ruby code. Each
    # language needs its own Citrus grammar (e.g., toml-rb for TOML).
    #
    # @note This backend requires a Citrus grammar for the specific language
    # @see https://github.com/mjackson/citrus Citrus parser generator
    # @see https://github.com/emancu/toml-rb toml-rb (TOML Citrus grammar)
    #
    # @example Using with toml-rb
    #   require "toml-rb"
    #
    #   parser = TreeHaver::Parser.new
    #   # For Citrus, "language" is actually a grammar module
    #   parser.language = TomlRB::Document
    #   tree = parser.parse(toml_source)
    module Citrus
      @load_attempted = false
      @loaded = false

      # Check if the Citrus backend is available
      #
      # Attempts to require citrus on first call and caches the result.
      #
      # @return [Boolean] true if citrus gem is available
      # @example
      #   if TreeHaver::Backends::Citrus.available?
      #     puts "Citrus backend is ready"
      #   end
      class << self
        def available?
          return @loaded if @load_attempted

          @load_attempted = true
          begin
            require 'citrus'
            @loaded = true
          rescue LoadError
            @loaded = false
            # simplecov:disable defensive code - StandardError during require is extremely rare
          rescue StandardError
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
        #   TreeHaver::Backends::Citrus.capabilities
        #   # => { backend: :citrus, query: false, bytes_field: true, incremental: false, comment_support: :none }
        def capabilities
          return {} unless available?

          {
            backend: :citrus,
            query: false,          # Citrus doesn't have a query API like tree-sitter
            bytes_field: true,     # Citrus::Match provides offset and length
            incremental: false,    # Citrus doesn't support incremental parsing
            pure_ruby: true,       # Citrus is pure Ruby (portable)
            comment_support: :none
          }
        end
      end

      # Citrus grammar wrapper
      #
      # Unlike tree-sitter which loads compiled .so files, Citrus uses Ruby modules
      # that define grammars. This class wraps a Citrus grammar module.
      #
      # @example
      #   # For TOML, use toml-rb's grammar
      #   language = TreeHaver::Backends::Citrus::Language.new(TomlRB::Document)
      class Language
        include Comparable

        # The Citrus grammar module
        # @return [Module] Citrus grammar module (e.g., TomlRB::Document)
        attr_reader :grammar_module

        # The backend this language is for
        # @return [Symbol]
        attr_reader :backend

        # @param grammar_module [Module] A Citrus grammar module with a parse method
        def initialize(grammar_module)
          unless grammar_module.respond_to?(:parse)
            raise TreeHaver::NotAvailable,
                  'Grammar module must respond to :parse. ' \
                    'Expected a Citrus grammar module (e.g., TomlRB::Document).'
          end
          @grammar_module = grammar_module
          @backend = :citrus
        end

        # Get the language name
        #
        # Derives a name from the grammar module name.
        #
        # @return [Symbol] language name
        def language_name
          # Derive name from grammar module (e.g., TomlRB::Document -> :toml)
          return :unknown unless @grammar_module.respond_to?(:name) && @grammar_module.name

          name = @grammar_module.name.to_s.split('::').first.downcase
          name.sub(/rb$/, '').to_sym
        end

        # Alias for language_name (API compatibility)
        alias name language_name

        # Compare languages for equality
        #
        # Citrus languages are equal if they have the same backend and grammar_module.
        # Grammar module uniquely identifies a Citrus language.
        #
        # @param other [Object] object to compare with
        # @return [Integer, nil] -1, 0, 1, or nil if not comparable
        def <=>(other)
          return unless other.is_a?(Language)
          return unless other.backend == @backend

          # Compare by grammar_module name (modules are compared by object_id by default)
          @grammar_module.name <=> other.grammar_module.name
        end

        # Hash value for this language (for use in Sets/Hashes)
        # @return [Integer]
        def hash
          [@backend, @grammar_module.name].hash
        end

        # Alias eql? to ==
        alias eql? ==

        # Load language from library path (API compatibility)
        #
        # Citrus grammars are Ruby modules, not shared libraries. This method
        # provides API compatibility with tree-sitter backends by looking up
        # registered Citrus grammars by name.
        #
        # For full API consistency, register a Citrus grammar with:
        #   TreeHaver.register_language(:toml, grammar_module: TomlRB::Document)
        #
        # Then this method will find it when called via `TreeHaver.parser_for(:toml)`.
        #
        # @param path [String, nil] Ignored for Citrus (used to derive language name)
        # @param symbol [String, nil] Used to derive language name if path not provided
        # @param name [String, Symbol, nil] Language name to look up
        # @return [Language] Citrus language wrapper
        # @raise [TreeHaver::NotAvailable] if no Citrus grammar is registered for the language
        class << self
          def from_library(path = nil, symbol: nil, name: nil)
            # Derive language name from path, symbol, or explicit name
            lang_name = name&.to_sym ||
                        symbol&.to_s&.sub(/^tree_sitter_/, '')&.to_sym ||
                        path && TreeHaver::LibraryPathUtils.derive_language_name_from_path(path)&.to_sym

            unless lang_name
              raise TreeHaver::NotAvailable,
                    'Citrus backend requires a language name. ' \
                      'Provide name: parameter or register a grammar with TreeHaver.register_language.'
            end

            # Look up registered Citrus grammar
            registration = TreeHaver::LanguageRegistry.registered(lang_name, :citrus)

            unless registration
              raise TreeHaver::NotAvailable,
                    "No Citrus grammar registered for #{lang_name.inspect}. " \
                      "Register one with: TreeHaver.register_language(:#{lang_name}, grammar_module: YourGrammar)"
            end

            grammar_module = registration[:grammar_module]
            new(grammar_module)
          end

          alias from_path from_library
        end
      end

      # Citrus parser wrapper
      #
      # Wraps Citrus grammar modules to provide a tree-sitter-like API.
      class Parser
        # Create a new Citrus parser instance
        #
        # @raise [TreeHaver::NotAvailable] if citrus gem is not available
        def initialize
          raise TreeHaver::NotAvailable, 'citrus gem not available' unless Citrus.available?

          @grammar = nil
          @backend = :citrus
        end

        attr_reader :backend

        # Set the grammar for this parser
        #
        # Accepts either a Citrus::Language wrapper or a raw Citrus grammar module.
        # When passed a Language wrapper, extracts the grammar_module from it.
        # When passed a raw grammar module, uses it directly.
        #
        # This flexibility allows both patterns:
        #   parser.language = TreeHaver::Backends::Citrus::Language.new(TomlRB::Document)
        #   parser.language = TomlRB::Document  # Also works
        #
        # @param grammar [Language, Module] Citrus Language wrapper or grammar module
        # @return [void]
        def language=(grammar)
          # Accept Language wrapper or raw grammar module
          actual_grammar = case grammar
                           when Language
                             grammar.grammar_module
                           else
                             grammar
                           end

          unless actual_grammar.respond_to?(:parse)
            raise ArgumentError,
                  'Expected Citrus grammar module with parse method or Language wrapper, ' \
                    "got #{grammar.class}"
          end
          @grammar = actual_grammar
        end

        # Parse source code
        #
        # @param source [String] the source code to parse
        # @return [Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        # @raise [TreeHaver::NotAvailable] if no grammar is set
        # @raise [::Citrus::ParseError] if parsing fails
        def parse(source)
          raise TreeHaver::NotAvailable, 'No grammar loaded' unless @grammar

          begin
            citrus_match = @grammar.parse(source)
            # Return raw Citrus::Tree - TreeHaver::Parser will wrap it
            Tree.new(citrus_match, source)
          rescue ::Citrus::ParseError => e
            # Re-raise with more context
            raise TreeHaver::Error, "Parse error: #{e.message}"
          end
        end

        # Parse source code (compatibility with tree-sitter API)
        #
        # Citrus doesn't support incremental parsing, so old_tree is ignored.
        #
        # @param old_tree [TreeHaver::Tree, nil] ignored (no incremental parsing support)
        # @param source [String] the source code to parse
        # @return [Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        def parse_string(old_tree, source) # rubocop:disable Lint/UnusedMethodArgument
          parse(source) # Citrus doesn't support incremental parsing
        end
      end

      # Citrus tree wrapper
      #
      # Wraps a Citrus::Match (which represents the parse tree) to provide
      # tree-sitter-compatible API.
      #
      # Inherits from Base::Tree to get shared methods like #errors, #warnings,
      # #comments, #has_error?, and #inspect.
      #
      # @api private
      class Tree < TreeHaver::Base::Tree
        # The raw Citrus::Match root
        # @return [Citrus::Match] The root match
        attr_reader :root_match

        def initialize(root_match, source)
          @root_match = root_match
          super(root_match, source: source)
        end

        def root_node
          Node.new(@root_match, @source)
        end
      end

      # Citrus node wrapper
      #
      # Wraps Citrus::Match objects to provide tree-sitter-compatible node API.
      #
      # Citrus::Match provides:
      # - events[0]: rule name (Symbol) - used as type
      # - offset: byte position
      # - length: byte length
      # - string: matched text
      # - matches: child matches
      # - captures: named groups
      #
      # Inherits from Base::Node to get shared methods like #first_child, #last_child,
      # #to_s, #inspect, #==, #<=>, #source_position, #start_line, #end_line, etc.
      #
      # Language-specific helpers can be mixed in for convenience:
      #   require "tree_haver/backends/citrus/toml_helpers"
      #   TreeHaver::Backends::Citrus::Node.include(TreeHaver::Backends::Citrus::TomlHelpers)
      #
      # @api private
      class Node < TreeHaver::Base::Node
        attr_reader :match

        def initialize(match, source)
          @match = match
          super(match, source: source)
        end

        # -- Required API Methods (from Base::Node) ----------------------------

        # Get node type from Citrus rule name
        #
        # Uses Citrus grammar introspection to dynamically determine node types.
        # Works with any Citrus grammar without language-specific knowledge.
        #
        # Strategy:
        # 1. Check if first event has a .name method (returns Symbol) - use that
        # 2. If first event is a Symbol directly - use that
        # 3. For compound rules (Repeat, Choice), recurse into first match
        #
        # @return [String] rule name from grammar
        def type
          return 'unknown' unless @match.respond_to?(:events)
          return 'unknown' unless @match.events.is_a?(Array)
          return 'unknown' if @match.events.empty?

          extract_type_from_event(@match.events.first)
        end

        def start_byte
          @match.offset
        end

        def end_byte
          @match.offset + @match.length
        end

        def children
          return [] unless @match.respond_to?(:matches)

          @match.matches.map { |m| Node.new(m, @source) }
        end

        # -- Overridden Methods ------------------------------------------------

        # Override start_point to calculate from source
        def start_point
          calculate_point(@match.offset)
        end

        # Override end_point to calculate from source
        def end_point
          calculate_point(@match.offset + @match.length)
        end

        # Override text to use Citrus match string
        def text
          @match.string
        end

        # Override child_count for efficiency (avoid building full children array)
        def child_count
          @match.respond_to?(:matches) ? @match.matches.size : 0
        end

        # Override child to handle negative indices properly
        def child(index)
          return if index.negative?
          return unless @match.respond_to?(:matches)
          return if index >= @match.matches.size

          Node.new(@match.matches[index], @source)
        end

        # Check if this node represents a structural element vs a terminal/token
        #
        # Uses Citrus grammar's terminal? method to determine if this is
        # a structural rule (like "table", "keyvalue") vs a terminal token
        # (like "[", "=", whitespace).
        #
        # @return [Boolean] true if this is a structural (non-terminal) node
        def structural?
          return false unless @match.respond_to?(:events)
          return false if @match.events.empty?

          first_event = @match.events.first

          # Check if event has terminal? method (Citrus rule object)
          return !first_event.terminal? if first_event.respond_to?(:terminal?)

          # For Symbol events, try to look up in grammar
          if first_event.is_a?(Symbol) && @match.respond_to?(:grammar)
            grammar = @match.grammar
            if grammar.respond_to?(:rules) && grammar.rules.key?(first_event)
              rule = grammar.rules[first_event]
              return !rule.terminal? if rule.respond_to?(:terminal?)
            end
          end

          # Default: assume structural if not a simple string/regex terminal
          true
        end

        private

        # Extract type name from a Citrus event object
        #
        # Handles different event types:
        # - Objects with .name method (Citrus rule objects) -> use .name
        # - Symbol -> use directly
        # - Compound rules (Repeat, Choice) -> check string representation
        #
        # @param event [Object] Citrus event object
        # @return [String] type name
        def extract_type_from_event(event)
          # Case 1: Event has .name method (returns Symbol)
          if event.respond_to?(:name)
            name = event.name
            return name.to_s if name.is_a?(Symbol)
          end

          # Case 2: Event is a Symbol directly (most common for child nodes)
          return event.to_s if event.is_a?(Symbol)

          # Case 3: Event is a String
          return event if event.is_a?(String)

          # Case 4: For compound rules (Repeat, Choice), try string parsing first
          # This avoids recursion issues
          str = event.to_s

          # Try to extract rule name from string representation
          # Examples: "table", "(comment | table)*", "space?", etc.
          return ::Regexp.last_match(1) if str =~ /^([a-z_][a-z0-9_]*)/i

          # If we have a pattern like "(rule1 | rule2)*", we can't determine
          # the type without looking at actual matches, but that causes recursion
          # So just return a generic type based on the pattern
          case str
          when /^\(.*\)\*$/
            return 'repeat'
          when /^\(.*\)\?$/
            return 'optional'
          when /^.*\|.*$/
            return 'choice'
          end

          'unknown'
        end

        def calculate_point(offset)
          return { row: 0, column: 0 } if offset <= 0

          lines_before = @source[0...offset].count("\n")
          # Find the newline before this offset (or -1 if we're on line 0)
          line_start = (@source.rindex("\n", offset - 1) if offset.positive?)
          line_start ||= -1
          column = offset - line_start - 1
          { row: lines_before, column: column }
        end
      end

      # Register the availability checker for RSpec dependency tags
      TreeHaver::BackendRegistry.register_availability_checker(:citrus) do
        available?
      end
    end
  end
end
