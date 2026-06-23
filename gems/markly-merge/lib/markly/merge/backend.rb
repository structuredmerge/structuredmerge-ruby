# frozen_string_literal: true

module Markly
  module Merge
    # Markly backend using the Markly gem (cmark-gfm C library)
    #
    # This backend wraps Markly, a Ruby gem that provides bindings to
    # cmark-gfm, GitHub's fork of the CommonMark C library with extensions.
    #
    # @note This backend only parses Markdown source code
    # @see https://github.com/ioquatix/markly Markly gem
    #
    # @example Basic usage
    #   parser = TreeHaver::Parser.new
    #   parser.language = Markly::Merge::Backend::Language.markdown(
    #     flags: Markly::DEFAULT,
    #     extensions: [:table, :strikethrough]
    #   )
    #   tree = parser.parse(markdown_source)
    #   root = tree.root_node
    #   puts root.type  # => "document"
    module Backend
      Markdown::Merge::BackendSupport.install!(
        backend_module: self,
        backend_name: :markly,
        gem_name: 'markly',
        require_path: 'markly/merge',
        capabilities: {
          gfm_extensions: true
        }
      )

      # Markly language wrapper
      #
      # Markly only parses Markdown. This class exists for API compatibility
      # and to pass through Markly-specific options (flags, extensions).
      #
      # @example
      #   language = Markly::Merge::Backend::Language.markdown(
      #     flags: Markly::DEFAULT | Markly::FOOTNOTES,
      #     extensions: [:table, :strikethrough]
      #   )
      #   parser.language = language
      class Language < ::TreeHaver::Base::Language
        # Markly parse flags
        # @return [Integer]
        attr_reader :flags

        # Markly extensions to enable
        # @return [Array<Symbol>]
        attr_reader :extensions

        # Create a new Markly language instance
        #
        # @param name [Symbol] Language name (should be :markdown)
        # @param flags [Integer] Markly parse flags (default: Markly::DEFAULT)
        # @param extensions [Array<Symbol>] Extensions to enable (default: [:table])
        # @param options [Hash] parsing options (reserved for future use)
        def initialize(name = :markdown, flags: nil, extensions: [:table], options: {})
          super(name, backend: :markly, options: options.merge({ flags: flags, extensions: extensions }))
          @flags = flags # Will use Markly::DEFAULT if nil at parse time
          @extensions = extensions

          return if @name == :markdown

          raise TreeHaver::NotAvailable,
                'Markly backend only supports Markdown parsing. ' \
                  "Got language: #{name.inspect}"
        end

        class << self
          # Create a Markdown language instance
          #
          # @param flags [Integer] Markly parse flags
          # @param extensions [Array<Symbol>] Extensions to enable
          # @param options [Hash] parsing options (reserved for future use)
          # @return [Language] Markdown language
          def markdown(flags: nil, extensions: [:table], options: {})
            new(:markdown, flags: flags, extensions: extensions, options: options)
          end

          # Load language from library path (API compatibility)
          #
          # @param _path [String] Ignored - Markly doesn't load external grammars
          # @param symbol [String, nil] Ignored
          # @param name [String, nil] Language name hint (defaults to :markdown)
          # @return [Language] Markdown language
          # @raise [TreeHaver::NotAvailable] if requested language is not Markdown
        end

        Markdown::Merge::BackendSupport.configure_markdown_only_language_class!(
          self,
          backend_label: 'Markly',
          unsupported_language_message: lambda { |lang_name|
            "Markly backend only supports Markdown, not #{lang_name}. " \
              "Use a tree-sitter backend for #{lang_name} support."
          }
        )
      end

      # Markly parser wrapper
      class Parser < ::TreeHaver::Base::Parser
        # Create a new RBS parser instance
        #
        # @raise [TreeHaver::NotAvailable] if rbs gem is not available
        def initialize
          super()
          raise TreeHaver::NotAvailable, 'markly gem not available' unless Backend.available?
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
            if lang.to_sym == :markdown
              @language = Language.markdown
            else
              raise ArgumentError,
                    "Markly backend only supports Markdown parsing. Got: #{lang.inspect}"
            end
          else
            raise ArgumentError,
                  "Expected Backend::Language or :markdown, got #{lang.class}"
          end
        end

        # Parse Markdown source code
        #
        # @param source [String] Markdown source to parse
        # @return [Tree] Parsed tree
        def parse(source)
          raise 'Language not set' unless language

          Backend.available? or raise 'Markly not available'

          flags = language.flags || ::Markly::DEFAULT
          exts = language.extensions || [:table]
          doc = ::Markly.parse(source, flags: flags, extensions: exts)
          Tree.new(doc, source)
        end
      end

      # Markly node wrapper
      #
      # Wraps Markly::Node to provide TreeHaver::Node-compatible interface.
      class Node < ::TreeHaver::Base::Node
        # Type normalization map (Markly → canonical)
        TYPE_MAP = {
          header: 'heading',
          hrule: 'thematic_break',
          html: 'html_block'
        }.freeze

        Markdown::Merge::BackendSupport.configure_node_link_and_navigation!(
          self,
          next_sibling_selector: :next,
          prev_sibling_selector: :previous
        )
        Markdown::Merge::BackendSupport.configure_node_heading_and_code_block_helpers!(
          self,
          heading_matcher: ->(node) { node.raw_type == 'header' },
          code_block_matcher: ->(node) { node.type == 'code_block' }
        )

        # Default source position for nodes that don't have position info
        DEFAULT_SOURCE_POSITION = {
          start_line: 1,
          start_column: 1,
          end_line: 1,
          end_column: 1
        }.freeze

        # Get source position from the inner Markly node
        #
        # @return [Hash{Symbol => Integer}] Source position from Markly
        # @api private
        def inner_source_position
          @inner_source_position ||= if inner_node.respond_to?(:source_position)
                                       inner_node.source_position || DEFAULT_SOURCE_POSITION
                                     else
                                       DEFAULT_SOURCE_POSITION
                                     end
        end

        # Get the node type as a string (normalized)
        #
        # @return [String] Node type
        def type
          raw = inner_node.type.to_s
          TYPE_MAP[raw.to_sym]&.to_s || raw
        end

        # Get the raw (non-normalized) type
        # @return [String]
        def raw_type
          inner_node.type.to_s
        end

        # Get the text content of this node
        #
        # @return [String] Node text
        def text
          if inner_node.respond_to?(:string_content)
            content = inner_node.string_content.to_s
            return content unless content.empty?
          end

          if inner_node.respond_to?(:to_plaintext)
            begin
              inner_node.to_plaintext
            rescue StandardError
              children.map(&:text).join
            end
          else
            children.map(&:text).join
          end
        end

        # Get child nodes (Markly uses first_child/next pattern)
        #
        # @return [Array<Node>] Child nodes
        def children
          result = []
          child = begin
            inner_node.first_child
          rescue StandardError
            nil
          end
          while child
            result << Node.new(child, source: source, lines: lines)
            child = begin
              child.next
            rescue StandardError
              nil
            end
          end
          result
        end

        # Position information

        def start_byte
          pos = inner_source_position
          calculate_byte_offset(pos[:start_line] - 1, pos[:start_column] - 1)
        end

        def end_byte
          pos = inner_source_position
          calculate_byte_offset(pos[:end_line] - 1, pos[:end_column] - 1)
        end

        def start_point
          pos = inner_source_position
          { row: pos[:start_line] - 1, column: pos[:start_column] - 1 }
        end

        def end_point
          pos = inner_source_position
          { row: pos[:end_line] - 1, column: pos[:end_column] - 1 }
        end

        # Convert node to CommonMark/Markdown/HTML/plaintext
        def to_commonmark
          inner_node.to_commonmark
        end

        def to_markdown
          inner_node.to_markdown
        end

        def to_plaintext
          inner_node.to_plaintext
        end

        def to_html
          inner_node.to_html
        end

        # Markly-specific methods
      end
    end
  end
end
