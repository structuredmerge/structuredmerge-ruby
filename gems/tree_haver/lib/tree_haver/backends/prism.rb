# frozen_string_literal: true

module TreeHaver
  module Backends
    # Prism backend using Ruby's built-in Prism parser
    #
    # This backend wraps Prism, Ruby's official parser (stdlib in Ruby 3.4+,
    # available as a gem for 3.2+). Unlike tree-sitter backends which are
    # language-agnostic runtime parsers, Prism is specifically designed for
    # parsing Ruby source code.
    #
    # Prism provides excellent error recovery, detailed location information,
    # and is the future of Ruby parsing (used by CRuby, JRuby, TruffleRuby).
    #
    # @note This backend only parses Ruby source code
    # @see https://github.com/ruby/prism Prism parser
    #
    # @example Basic usage
    #   parser = TreeHaver::Parser.new
    #   parser.language = TreeHaver::Backends::Prism::Language.ruby
    #   tree = parser.parse(ruby_source)
    #   root = tree.root_node
    #   puts root.type  # => "program_node"
    module Prism
      @load_attempted = false
      @loaded = false

      # Check if the Prism backend is available
      #
      # Attempts to require prism on first call and caches the result.
      # On Ruby 3.4+, Prism is in stdlib. On 3.2-3.3, it's a gem.
      #
      # @return [Boolean] true if prism is available
      # @example
      #   if TreeHaver::Backends::Prism.available?
      #     puts "Prism backend is ready"
      #   end
      class << self
        def available?
          return @loaded if @load_attempted

          @load_attempted = true
          begin
            require 'prism'
            @loaded = true
          rescue LoadError
            @loaded = false
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
        #   TreeHaver::Backends::Prism.capabilities
        #   # => { backend: :prism, query: false, bytes_field: true, incremental: false, ruby_only: true, comment_support: :partial }
        def capabilities
          return {} unless available?

          {
            backend: :prism,
            query: false,           # Prism doesn't have tree-sitter-style queries (has pattern matching)
            bytes_field: true,      # Prism provides byte offsets via Location
            incremental: false,     # Prism doesn't support incremental parsing (yet)
            pure_ruby: false,       # Prism has native C extension (but also pure Ruby mode)
            ruby_only: true,        # Prism only parses Ruby source code
            error_tolerant: true,   # Prism has excellent error recovery
            comment_support: :partial,
            comment_attachment_hints: true
          }
        end
      end

      # Prism language wrapper
      #
      # Unlike tree-sitter which supports many languages via grammar files,
      # Prism only parses Ruby. This class exists for API compatibility with
      # other tree_haver backends.
      #
      # @example
      #   language = TreeHaver::Backends::Prism::Language.ruby
      #   parser.language = language
      class Language < TreeHaver::Base::Language
        # @param name [Symbol] language name (should be :ruby)
        # @param options [Hash] Prism parsing options (e.g., frozen_string_literal, version)
        def initialize(name = :ruby, options: {})
          super(name, backend: :prism, options: options)

          return if self.name == :ruby

          raise TreeHaver::NotAvailable,
                'Prism only supports Ruby parsing. ' \
                  "Got language: #{name.inspect}"
        end

        # Compare languages for equality by options (since name is always :ruby)
        #
        # @param other [Object] object to compare with
        # @return [Integer, nil] -1, 0, 1, or nil if not comparable
        def <=>(other)
          return unless other.is_a?(TreeHaver::Base::Language)
          return unless other.backend == backend

          options.to_a.sort <=> other.options.to_a.sort
        end

        class << self
          # Create a Ruby language instance (convenience method)
          #
          # @param options [Hash] Prism parsing options
          # @option options [Boolean] :frozen_string_literal frozen string literal pragma
          # @option options [String] :version Ruby version to parse as (e.g., "3.3.0")
          # @option options [Symbol] :command_line command line option (-e, -n, etc.)
          # @return [Language]
          # @example
          #   lang = TreeHaver::Backends::Prism::Language.ruby
          #   lang = TreeHaver::Backends::Prism::Language.ruby(frozen_string_literal: true)
          def ruby(options = {})
            new(:ruby, options: options)
          end

          # Load language from library path (API compatibility)
          #
          # Prism only supports Ruby, so path and symbol parameters are ignored.
          #
          # @param _path [String] Ignored - Prism doesn't load external grammars
          # @param symbol [String, nil] Ignored - Prism only supports Ruby
          # @param name [String, nil] Language name hint (defaults to :ruby)
          # @return [Language] Ruby language
          # @raise [TreeHaver::NotAvailable] if requested language is not Ruby
          def from_library(_path = nil, symbol: nil, name: nil)
            lang_name = name || :ruby

            unless lang_name == :ruby
              raise TreeHaver::NotAvailable,
                    "Prism backend only supports Ruby, not #{lang_name}. " \
                      "Use a tree-sitter backend for #{lang_name} support."
            end

            ruby
          end

          alias from_path from_library
        end
      end

      # Prism parser wrapper
      #
      # Wraps Prism to provide a tree-sitter-like API for parsing Ruby code.
      class Parser < TreeHaver::Base::Parser
        # Create a new Prism parser instance
        #
        # @raise [TreeHaver::NotAvailable] if prism is not available
        def initialize
          super
          raise TreeHaver::NotAvailable, 'prism not available' unless TreeHaver::Backends::Prism.available?

          @options = {}
        end

        # Set the language for this parser
        #
        # Note: TreeHaver::Parser unwraps language objects before calling this method.
        # This backend receives the Language wrapper (since Prism::Language stores options).
        #
        # @param lang [Language, Symbol] Prism language (should be :ruby or Language instance)
        # @return [void]
        def language=(lang)
          case lang
          when Language
            @language = lang
            @options = lang.options
          when Symbol, String
            if lang.to_sym == :ruby
              @language = Language.ruby
              @options = {}
            else
              raise ArgumentError,
                    "Prism only supports Ruby parsing. Got: #{lang.inspect}"
            end
          else
            raise ArgumentError,
                  "Expected Prism::Language or :ruby, got #{lang.class}"
          end
        end

        # Parse source code
        #
        # @param source [String] the Ruby source code to parse
        # @return [Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        # @raise [TreeHaver::NotAvailable] if no language is set
        def parse(source)
          raise TreeHaver::NotAvailable, 'No language loaded (use parser.language = :ruby)' unless @language

          # Use Prism.parse with options
          prism_result = ::Prism.parse(source, **@options)
          Tree.new(prism_result, source)
        end

        # Parse source code (compatibility with tree-sitter API)
        #
        # Prism doesn't support incremental parsing, so old_tree is ignored.
        #
        # @param old_tree [TreeHaver::Tree, nil] ignored (no incremental parsing support)
        # @param source [String] the Ruby source code to parse
        # @return [Tree] raw backend tree (wrapping happens in TreeHaver::Parser)
        def parse_string(old_tree, source) # rubocop:disable Lint/UnusedMethodArgument
          parse(source) # Prism doesn't support incremental parsing
        end
      end

      # Prism tree wrapper
      #
      # Wraps a Prism::ParseResult to provide tree-sitter-compatible API.
      #
      # @api private
      class Tree < TreeHaver::Base::Tree
        # @return [::Prism::ParseResult] the underlying Prism parse result
        attr_reader :parse_result

        def initialize(parse_result, source)
          super(parse_result, source: source)
          @parse_result = parse_result
        end

        # Get the root node of the parse tree
        #
        # @return [Node] wrapped root node
        def root_node
          Node.new(@parse_result.value, source)
        end

        # Check if the parse had errors
        #
        # @return [Boolean]
        def has_errors?
          @parse_result.failure?
        end

        # Get parse errors
        #
        # @return [Array<::Prism::ParseError>]
        def errors
          @parse_result.errors
        end

        # Get parse warnings
        #
        # @return [Array<::Prism::ParseWarning>]
        def warnings
          @parse_result.warnings
        end

        # Get comments from the parse
        #
        # @return [Array<Comment>]
        def comments
          @comments ||= begin
            hint_map = comment_hint_map
            @parse_result.comments.map do |comment|
              Comment.new(comment, source: source, attachment_hint: hint_map[comment.object_id])
            end
          end
        end

        # Get magic comments (e.g., frozen_string_literal)
        #
        # @return [Array<::Prism::MagicComment>]
        def magic_comments
          @parse_result.magic_comments
        end

        # Get data locations (__END__ section)
        #
        # @return [::Prism::Location, nil]
        def data_loc
          @parse_result.data_loc
        end

        private

        def comment_hint_map
          comments = @parse_result.comments
          lines = source&.lines || []

          comments.each_with_object({}) do |comment, hints|
            hints[comment.object_id] = classify_comment_hint(comment, lines)
          end
        end

        def classify_comment_hint(comment, lines)
          line = lines[comment.location.start_line - 1].to_s
          prefix = line[0...comment.location.start_column]
          return :inline if prefix.match?(/\S/)

          remaining_nonempty = Array(lines[comment.location.end_line..]).reject { |candidate| candidate.strip.empty? }
          return :trailing if remaining_nonempty.empty? || remaining_nonempty.all? do |candidate|
            candidate.lstrip.start_with?('#')
          end

          :leading
        end
      end

      # Prism comment wrapper.
      #
      # Prism exposes native Ruby comments via Prism::Comment subclasses and
      # Prism::Location objects. This wrapper normalizes those objects onto a
      # small parser-facing contract for downstream consumers.
      class Comment < TreeHaver::Base::Comment
        def location
          inner_comment.location
        end

        def type
          self.class.comment_type_for(inner_comment.class)
        end

        def text
          inner_comment.slice
        end

        def start_byte
          location.start_offset
        end

        def end_byte
          location.end_offset
        end

        def start_point
          {
            row: location.start_line - 1,
            column: location.start_column
          }
        end

        def end_point
          {
            row: location.end_line - 1,
            column: location.end_column
          }
        end

        def style
          :line
        end

        def opening_delimiter
          '#'
        end

        class << self
          def comment_type_for(klass)
            klass.name.split('::').last
                 .gsub(/([a-z\d])([A-Z])/, '\\1_\\2')
                 .downcase
          end
        end
      end

      # Prism node wrapper
      #
      # Wraps Prism::Node objects to provide tree-sitter-compatible node API.
      #
      # Prism nodes provide:
      # - type: class name without "Node" suffix (e.g., ProgramNode → "program")
      # - location: ::Prism::Location with start/end offsets and line/column
      # - child_nodes: array of child nodes
      # - Various node-specific accessors
      #
      # @api private
      class Node < TreeHaver::Base::Node
        def initialize(node, source)
          super(node, source: source)
        end

        # Get node type from Prism class name
        #
        # Converts PrismClassName to tree-sitter-style type string.
        # Example: CallNode → "call_node", ProgramNode → "program_node"
        #
        # @return [String] node type in snake_case
        def type
          return 'nil' if inner_node.nil?

          # Convert class name to snake_case type
          class_name = inner_node.class.name.split('::').last
          class_name.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
        end

        # Alias for type (API compatibility)
        # @return [String] node type
        def kind
          type
        end

        # Get byte offset where the node starts
        #
        # @return [Integer]
        def start_byte
          return 0 if inner_node.nil? || !inner_node.respond_to?(:location)

          loc = inner_node.location
          loc&.start_offset || 0
        end

        # Get byte offset where the node ends
        #
        # @return [Integer]
        def end_byte
          return 0 if inner_node.nil? || !inner_node.respond_to?(:location)

          loc = inner_node.location
          loc&.end_offset || 0
        end

        # Get the start position as row/column (0-based)
        #
        # @return [Hash{Symbol => Integer}]
        def start_point
          return { row: 0, column: 0 } if inner_node.nil? || !inner_node.respond_to?(:location)

          loc = inner_node.location
          return { row: 0, column: 0 } unless loc

          { row: (loc.start_line - 1), column: loc.start_column }
        end

        # Get the end position as row/column (0-based)
        #
        # @return [Hash{Symbol => Integer}]
        def end_point
          return { row: 0, column: 0 } if inner_node.nil? || !inner_node.respond_to?(:location)

          loc = inner_node.location
          return { row: 0, column: 0 } unless loc

          { row: (loc.end_line - 1), column: loc.end_column }
        end

        # Get all child nodes
        #
        # @return [Array<Node>] array of wrapped child nodes
        def children
          return [] if inner_node.nil?
          return [] unless inner_node.respond_to?(:child_nodes)

          inner_node.child_nodes.compact.map { |n| Node.new(n, source) }
        end

        # Get the text content of this node
        #
        # @return [String]
        def text
          return '' if inner_node.nil?

          if inner_node.respond_to?(:slice)
            inner_node.slice
          else
            super
          end
        end

        # Alias for Prism compatibility
        alias slice text

        # Check if this node has errors
        #
        # @return [Boolean]
        def has_error?
          return false if inner_node.nil?

          # Check if this is an error node type
          return true if type.include?('missing') || type.include?('error')

          # Check children recursively (Prism error nodes are usually children)
          return false unless inner_node.respond_to?(:child_nodes)

          inner_node.child_nodes.compact.any? { |n| n.class.name.to_s.include?('Missing') }
        end

        # Check if this node is a "missing" node (error recovery)
        #
        # @return [Boolean]
        def missing?
          return false if inner_node.nil?

          type.include?('missing')
        end

        # Get a child by field name (Prism node accessor)
        #
        # Prism nodes have specific accessors for their children.
        #
        # @param name [String, Symbol] field/accessor name
        # @return [Node, nil] wrapped child node
        def child_by_field_name(name)
          return if inner_node.nil?
          return unless inner_node.respond_to?(name)

          result = inner_node.public_send(name)
          return if result.nil?

          # Wrap if it's a node
          result.is_a?(::Prism::Node) ? Node.new(result, source) : nil
        end

        alias field child_by_field_name

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
          return false if inner_node.nil?

          inner_node.respond_to?(method_name, include_private) || super
        end

        # Delegate unknown methods to the underlying Prism node
        #
        # This provides passthrough access for Prism-specific node methods
        # like `receiver`, `message`, `arguments`, etc.
        #
        # @param method_name [Symbol] method to call
        # @param args [Array] arguments to pass
        # @param kwargs [Hash] keyword arguments
        # @param block [Proc] block to pass
        # @return [Object] result from the underlying node
        def method_missing(method_name, *args, **kwargs, &block)
          if inner_node.respond_to?(method_name)
            inner_node.public_send(method_name, *args, **kwargs, &block)
          else
            super
          end
        end
      end

      # Register the availability checker for RSpec dependency tags
      TreeHaver::BackendRegistry.register_availability_checker(:prism) do
        available?
      end
    end
  end
end
