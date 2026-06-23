# frozen_string_literal: true

module Rbs
  module Merge
    module Backends
      # RBS gem backend using Ruby's official RBS parser
      #
      # This backend wraps the RBS gem, Ruby's official type signature parser.
      # The RBS gem is specifically designed for parsing RBS type signature files.
      #
      # The RBS gem provides:
      # - Rich AST with declaration types (Class, Module, Interface, TypeAlias, etc.)
      # - Member types (MethodDefinition, Alias, AttrReader, etc.)
      # - Location information for all nodes
      # - Full RBS language support including generics, type aliases, etc.
      #
      # @note This backend only works on MRI Ruby (the RBS gem has C extensions)
      # @note This backend only parses RBS type signature files
      # @see https://github.com/ruby/rbs RBS gem
      #
      # @example Basic usage via TreeHaver
      #   TreeHaver.register_language(:rbs,
      #     backend_module: Rbs::Merge::Backends::RbsBackend,
      #     backend_type: :rbs,
      #     gem_name: "rbs")
      #   parser = TreeHaver.parser_for(:rbs)
      #   tree = parser.parse(rbs_source)
      #   root = tree.root_node
      #
      # @example Direct usage
      #   parser = Rbs::Merge::Backends::RbsBackend::Parser.new
      #   parser.language = Rbs::Merge::Backends::RbsBackend::Language.rbs
      #   tree = parser.parse(rbs_source)
      module RbsBackend
        @load_attempted = false
        @loaded = false

        class << self
          # Check if the RBS backend is available
          #
          # Attempts to require rbs on first call and caches the result.
          #
          # @return [Boolean] true if rbs gem is available
          # @example
          #   if Rbs::Merge::Backends::RbsBackend.available?
          #     puts "RBS backend is ready"
          #   end
          def available?
            return @loaded if @load_attempted

            @load_attempted = true
            begin
              require 'rbs'
              # Verify it can actually parse - just requiring isn't enough
              buffer = ::RBS::Buffer.new(name: 'test.rbs', content: 'class Foo end')
              ::RBS::Parser.parse_signature(buffer)
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
          #   Rbs::Merge::Backends::RbsBackend.capabilities
          #   # => { backend: :rbs, query: false, rbs_only: true, ... }
          def capabilities
            return {} unless available?

            {
              backend: :rbs,
              query: false,           # RBS doesn't have tree-sitter-style queries
              bytes_field: true,      # RBS provides byte offsets via Location
              incremental: false,     # RBS doesn't support incremental parsing
              pure_ruby: false,       # RBS gem has native C extension
              rbs_only: true,         # RBS gem only parses RBS type signatures
              error_tolerant: false,  # RBS parser raises on errors
              mri_only: true # RBS gem C extension only works on MRI
            }
          end
        end

        # RBS language wrapper
        #
        # The RBS gem only parses RBS type signature files.
        # This wrapper satisfies the current TreeHaver language contract.
        #
        # @example
        #   language = Rbs::Merge::Backends::RbsBackend::Language.rbs
        #   parser.language = language
        class Language < ::TreeHaver::Base::Language
          # @param name [Symbol] language name (should be :rbs)
          # @param options [Hash] parsing options (reserved for future use)
          def initialize(name = :rbs, options: {})
            super(name, backend: :rbs, options: options)

            return if @name == :rbs

            raise TreeHaver::NotAvailable,
                  'RBS backend only supports RBS parsing. ' \
                    "Got language: #{name.inspect}"
          end

          class << self
            # Create an RBS language instance (convenience method)
            #
            # @param options [Hash] parsing options (reserved for future use)
            # @return [Language]
            # @example
            #   lang = Rbs::Merge::Backends::RbsBackend::Language.rbs
            def rbs(options = {})
              new(:rbs, options: options)
            end

            # Load language from a grammar path.
            #
            # RBS gem only supports RBS, so path and symbol parameters are ignored.
            # This keeps the backend aligned with TreeHaver's language API.
            #
            # @param _path [String] Ignored - RBS gem doesn't load external grammars
            # @param symbol [String, nil] Ignored
            # @param name [String, nil] Language name hint (defaults to :rbs)
            # @return [Language] RBS language
            # @raise [TreeHaver::NotAvailable] if requested language is not RBS
            def from_library(_path = nil, symbol: nil, name: nil)
              # Derive language name from symbol if provided
              lang_name = name || symbol&.to_s&.sub(/^tree_sitter_/, '')&.to_sym || :rbs

              unless lang_name == :rbs
                raise TreeHaver::NotAvailable,
                      "RBS backend only supports RBS, not #{lang_name}. " \
                        "Use a tree-sitter backend for #{lang_name} support."
              end

              rbs
            end

            alias from_path from_library
          end
        end

        # RBS parser wrapper
        #
        # Wraps the RBS gem parser behind the current TreeHaver parser API.
        class Parser < ::TreeHaver::Base::Parser
          # Create a new RBS parser instance
          #
          # @raise [TreeHaver::NotAvailable] if rbs gem is not available
          def initialize
            super()
            raise TreeHaver::NotAvailable, 'rbs gem not available' unless RbsBackend.available?
          end

          # Set the language for this parser
          #
          # @param lang [Language, Symbol] RBS language (should be :rbs or Language instance)
          # @return [void]
          def language=(lang)
            case lang
            when Language
              @language = lang
            when Symbol, String
              if lang.to_sym == :rbs
                @language = Language.rbs
              else
                raise ArgumentError,
                      "RBS backend only supports RBS parsing. Got: #{lang.inspect}"
              end
            else
              raise ArgumentError,
                    "Expected RbsBackend::Language or :rbs, got #{lang.class}"
            end
          end

          # Parse source code
          #
          # @param source [String] the RBS source code to parse
          # @return [Tree] parse result tree
          # @raise [TreeHaver::NotAvailable] if no language is set
          def parse(source)
            raise TreeHaver::NotAvailable, 'No language loaded (use parser.language = :rbs)' unless @language

            buffer = ::RBS::Buffer.new(name: 'merge.rbs', content: source)
            _buffer, directives, declarations = ::RBS::Parser.parse_signature(buffer)
            Tree.new(declarations, source: source, directives: directives)
          rescue ::RBS::ParsingError => e
            # Return a tree with errors instead of raising
            Tree.new([], source: source, directives: [], errors: [e])
          end
        end

        # RBS tree wrapper
        #
        # Wraps RBS parse results behind the current TreeHaver tree API.
        #
        # @api private
        class Tree < ::TreeHaver::Base::Tree
          # @return [Array<::RBS::AST::Declarations::Base>] the declarations
          attr_reader :declarations

          # @return [Array<::RBS::AST::Directives::Base>] the directives
          attr_reader :directives

          # @return [Array] parse errors
          attr_reader :errors

          def initialize(declarations, source: nil, directives: [], errors: [])
            super(declarations, source: source)
            @declarations = declarations
            @directives = directives
            @errors = errors
          end

          # Get the root node of the parse tree
          #
          # Returns a synthetic "program" node that contains all declarations.
          #
          # @return [Node] wrapped root node
          def root_node
            Node.new_root(@declarations, source: source, lines: lines)
          end

          # Check if the parse had errors
          #
          # @return [Boolean]
          def has_errors?
            @errors.any?
          end

          # Access the underlying declarations (passthrough)
          # Overrides inner_tree to return declarations
          #
          # @return [Array<::RBS::AST::Declarations::Base>]
          def inner_tree
            @declarations
          end
        end

        # RBS node wrapper
        #
        # Wraps RBS AST nodes behind the current TreeHaver node API.
        #
        # RBS nodes provide:
        # - Various declaration types (Class, Module, Interface, TypeAlias, etc.)
        # - Member types (MethodDefinition, Alias, AttrReader, etc.)
        # - Location information via .location
        #
        # @api private
        class Node < ::TreeHaver::Base::Node
          # @return [Array<Object>] child nodes (for synthetic root)
          attr_reader :children_array

          def initialize(node, source: nil, lines: nil, children_array: nil)
            super(node, source: source, lines: lines)
            @children_array = children_array
          end

          class << self
            # Create a synthetic root node containing all declarations
            #
            # @param declarations [Array] the declarations
            # @param source [String] the source code
            # @param lines [Array<String>] pre-split source lines
            # @return [Node] synthetic root node
            def new_root(declarations, source: nil, lines: nil)
              new(nil, source: source, lines: lines, children_array: declarations)
            end
          end

          # Get node type from RBS class name
          #
          # Maps RBS::AST class names to tree-sitter-style type strings.
          # For synthetic root, returns "program".
          #
          # @return [String] node type
          def type
            return 'program' if root_node?

            return 'unknown' if @inner_node.nil?

            # Map RBS class to canonical type
            case @inner_node
            when ::RBS::AST::Declarations::Class then 'class_decl'
            when ::RBS::AST::Declarations::Module then 'module_decl'
            when ::RBS::AST::Declarations::Interface then 'interface_decl'
            when ::RBS::AST::Declarations::TypeAlias then 'type_alias_decl'
            when ::RBS::AST::Declarations::Constant then 'const_decl'
            when ::RBS::AST::Declarations::Global then 'global_decl'
            when ::RBS::AST::Declarations::ClassAlias then 'class_alias_decl'
            when ::RBS::AST::Declarations::ModuleAlias then 'module_alias_decl'
            when ::RBS::AST::Members::MethodDefinition then 'method_member'
            when ::RBS::AST::Members::Alias then 'alias_member'
            when ::RBS::AST::Members::AttrReader then 'attr_reader_member'
            when ::RBS::AST::Members::AttrWriter then 'attr_writer_member'
            when ::RBS::AST::Members::AttrAccessor then 'attr_accessor_member'
            when ::RBS::AST::Members::Include then 'include_member'
            when ::RBS::AST::Members::Extend then 'extend_member'
            when ::RBS::AST::Members::Prepend then 'prepend_member'
            when ::RBS::AST::Members::InstanceVariable then 'ivar_member'
            when ::RBS::AST::Members::ClassInstanceVariable then 'civar_member'
            when ::RBS::AST::Members::ClassVariable then 'cvar_member'
            when ::RBS::AST::Members::Public then 'public_member'
            when ::RBS::AST::Members::Private then 'private_member'
            else
              # Fallback to class name conversion
              @inner_node.class.name.split('::').last
                         .gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
            end
          end

          # Alias for the TreeHaver node contract
          alias kind type

          # Get byte offset where the node starts
          #
          # @return [Integer]
          def start_byte
            return 0 if root_node?
            return 0 unless @inner_node.respond_to?(:location) && @inner_node.location

            @inner_node.location.start_pos
          end

          # Get byte offset where the node ends
          #
          # @return [Integer]
          def end_byte
            return source.bytesize if root_node? && source
            return 0 if root_node?
            return 0 unless @inner_node.respond_to?(:location) && @inner_node.location

            @inner_node.location.end_pos
          end

          # Get the start position as row/column (0-based)
          #
          # @return [Hash{Symbol => Integer}] with :row and :column keys
          def start_point
            return { row: 0, column: 0 } if root_node?
            return { row: 0, column: 0 } unless @inner_node.respond_to?(:location) && @inner_node.location

            loc = @inner_node.location
            { row: loc.start_line - 1, column: loc.start_column }
          end

          # Get the end position as row/column (0-based)
          #
          # @return [Hash{Symbol => Integer}] with :row and :column keys
          def end_point
            if root_node? && source
              last_line = lines.size - 1
              last_col = lines.last&.size || 0
              return { row: last_line, column: last_col }
            end
            return { row: 0, column: 0 } if root_node?
            return { row: 0, column: 0 } unless @inner_node.respond_to?(:location) && @inner_node.location

            loc = @inner_node.location
            { row: loc.end_line - 1, column: loc.end_column }
          end

          # Get the 1-based line number where this node starts
          #
          # @return [Integer] 1-based line number
          def start_line
            return 1 if root_node?
            return 1 unless @inner_node.respond_to?(:location) && @inner_node.location

            @inner_node.location.start_line
          end

          # Get the 1-based line number where this node ends
          #
          # @return [Integer] 1-based line number
          def end_line
            return lines.size if root_node? && lines.any?
            return 1 if root_node?
            return 1 unless @inner_node.respond_to?(:location) && @inner_node.location

            @inner_node.location.end_line
          end

          # Get position information as a hash
          #
          # @return [Hash{Symbol => Integer}] Position hash
          def source_position
            {
              start_line: start_line,
              end_line: end_line,
              start_column: start_point[:column],
              end_column: end_point[:column]
            }
          end

          # Check if this is a synthetic root node
          #
          # @return [Boolean]
          def root_node?
            @inner_node.nil? && @children_array
          end

          # Get the text content of this node
          #
          # @return [String]
          def text
            return source.to_s if root_node?
            return '' unless @inner_node.respond_to?(:location) && @inner_node.location

            loc = @inner_node.location
            source.byteslice(loc.start_pos, loc.end_pos - loc.start_pos) || ''
          end

          # Get all child nodes
          #
          # @return [Array<Node>] array of wrapped child nodes
          def children
            return @children_array.map { |n| Node.new(n, source: source, lines: lines) } if root_node?

            return [] unless @inner_node.respond_to?(:members)

            @inner_node.members.map { |n| Node.new(n, source: source, lines: lines) }
          end

          # Get a child by field name (RBS node accessor)
          #
          # RBS nodes have specific accessors for their children.
          # This method tries to call that accessor.
          #
          # @param name [String, Symbol] field/accessor name
          # @return [Node, nil] wrapped child node
          def child_by_field_name(name)
            return if @inner_node.nil?
            return unless @inner_node.respond_to?(name)

            result = @inner_node.public_send(name)
            return if result.nil?

            # Wrap if it's a node, otherwise return nil
            return unless result.respond_to?(:location)

            Node.new(result, source: source, lines: lines)
          end

          alias field child_by_field_name

          # Get the name of this declaration/member
          #
          # @return [String, nil]
          def name
            return if @inner_node.nil?
            return unless @inner_node.respond_to?(:name)

            n = @inner_node.name
            n.respond_to?(:to_s) ? n.to_s : n
          end

          # String representation for debugging
          #
          # @return [String]
          def inspect
            "#<#{self.class} type=#{type} lines=#{start_line}..#{end_line}>"
          end

          # String representation
          #
          # @return [String]
          def to_s
            text
          end

          # Check if node responds to a method (includes delegation to inner_node)
          #
          # @param method_name [Symbol] method to check
          # @param include_private [Boolean] include private methods
          # @return [Boolean]
          def respond_to_missing?(method_name, include_private = false)
            return false if @inner_node.nil?

            @inner_node.respond_to?(method_name, include_private) || super
          end

          # Delegate unknown methods to the underlying RBS node
          #
          # @param method_name [Symbol] method to call
          # @param args [Array] arguments to pass
          # @param kwargs [Hash] keyword arguments
          # @param block [Proc] block to pass
          # @return [Object] result from the underlying node
          def method_missing(method_name, *args, **kwargs, &block)
            if @inner_node&.respond_to?(method_name)
              @inner_node.public_send(method_name, *args, **kwargs, &block)
            else
              super
            end
          end
        end

        # Register this backend with TreeHaver
        ::TreeHaver.register_language(
          :rbs,
          backend_type: :rbs,
          backend_module: self,
          gem_name: 'rbs'
        )

        # Register the availability checker for RSpec dependency tags.
        TreeHaver::BackendRegistry.register_availability_checker(:rbs_gem) do
          available?
        end
      end
    end
  end
end
