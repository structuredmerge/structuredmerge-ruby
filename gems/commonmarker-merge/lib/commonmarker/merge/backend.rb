# frozen_string_literal: true

module Commonmarker
  module Merge
    # Commonmarker backend using the Commonmarker gem (comrak Rust parser)
    #
    # This backend wraps Commonmarker, a Ruby gem that provides bindings to
    # comrak, a fast CommonMark-compliant Markdown parser written in Rust.
    #
    # @note This backend only parses Markdown source code
    # @see https://github.com/gjtorikian/commonmarker Commonmarker gem
    #
    # @example Basic usage
    #   parser = TreeHaver::Parser.new
    #   parser.language = Commonmarker::Merge::Backend::Language.markdown
    #   tree = parser.parse(markdown_source)
    #   root = tree.root_node
    #   puts root.type  # => "document"
    module Backend
      Markdown::Merge::BackendSupport.install!(
        backend_module: self,
        backend_name: :commonmarker,
        gem_name: 'commonmarker',
        require_path: 'commonmarker/merge'
      )

      # Commonmarker language wrapper
      #
      # Commonmarker only parses Markdown. This class exists for API compatibility.
      #
      # @example
      #   language = Commonmarker::Merge::Backend::Language.markdown
      #   parser.language = language
      class Language < TreeHaver::Base::Language
        # Create a new Commonmarker language instance
        #
        # @param name [Symbol] Language name (should be :markdown)
        # @param options [Hash] Commonmarker parse options
        def initialize(name = :markdown, options: {})
          super(name, backend: :commonmarker, options: options)
        end

        class << self
          # Create a Markdown language instance
          #
          # @param options [Hash] Commonmarker parse options
          # @return [Language] Markdown language
          def markdown(options: {})
            new(:markdown, options: options)
          end

          # Load language from library path (API compatibility)
          #
          # @param _path [String] Ignored - Commonmarker doesn't load external grammars
          # @param symbol [String, nil] Ignored
          # @param name [String, nil] Language name hint (defaults to :markdown)
          # @return [Language] Markdown language
          # @raise [TreeHaver::NotAvailable] if requested language is not Markdown
        end

        Markdown::Merge::BackendSupport.configure_markdown_only_language_class!(
          self,
          backend_label: 'Commonmarker'
        )
      end

      # Commonmarker parser wrapper
      class Parser < TreeHaver::Base::Parser
        # Parse Markdown source code
        #
        # @param source [String] Markdown source to parse
        # @return [Tree] Parsed tree
        def parse(source)
          raise 'Language not set' unless language

          Backend.available? or raise 'Commonmarker not available'

          opts = language.options || {}
          doc = ::Commonmarker.parse(source, options: opts)
          Tree.new(doc, source)
        end
      end

      # Commonmarker node wrapper
      #
      # Wraps Commonmarker::Node to provide TreeHaver::Node-compatible interface.
      class Node < TreeHaver::Base::Node
        Markdown::Merge::BackendSupport.configure_node_link_and_navigation!(
          self,
          next_sibling_selector: :next_sibling,
          prev_sibling_selector: :previous_sibling
        )
        Markdown::Merge::BackendSupport.configure_node_heading_and_code_block_helpers!(
          self,
          heading_matcher: ->(node) { node.type == 'heading' },
          code_block_matcher: ->(node) { node.type == 'code_block' }
        )

        # Get the node type as a string
        #
        # @return [String] Node type
        def type
          inner_node.type.to_s
        end

        # Alias for TreeHaver compatibility
        alias kind type

        # Get the text content of this node
        #
        # @return [String] Node text
        def text
          if inner_node.respond_to?(:string_content)
            begin
              content = inner_node.string_content.to_s
              return content unless content.empty?
            rescue TypeError
              # Container node - fall through
            end
          end
          children.map(&:text).join
        end

        # Get child nodes
        #
        # @return [Array<Node>] Child nodes
        def children
          return [] unless inner_node.respond_to?(:each)

          result = []
          inner_node.each { |child| result << Node.new(child, source: source, lines: lines) }
          result
        end

        # Get start byte offset
        def start_byte
          sp = start_point
          calculate_byte_offset(sp[:row], sp[:column])
        end

        # Get end byte offset
        def end_byte
          ep = end_point
          calculate_byte_offset(ep[:row], ep[:column])
        end

        # Get start point (0-based row/column)
        # @return [Point] Start position
        def start_point
          if inner_node.respond_to?(:source_position)
            begin
              pos = inner_node.source_position
              return Point.new(pos[:start_line] - 1, (pos[:start_column] || 1) - 1) if pos && pos[:start_line]
            rescue StandardError
              nil
            end
          end

          # Fallback: check sourcepos (old API)
          begin
            pos = inner_node.sourcepos
            return Point.new(pos[0] - 1, pos[1] - 1) if pos
          rescue StandardError
            nil
          end

          Point.new(0, 0)
        end

        # Get end point (0-based row/column)
        # @return [Point] End position
        def end_point
          if inner_node.respond_to?(:source_position)
            begin
              pos = inner_node.source_position
              return Point.new(pos[:end_line] - 1, (pos[:end_column] || 1) - 1) if pos && pos[:end_line]
            rescue StandardError
              nil
            end
          end

          begin
            pos = inner_node.sourcepos
            return Point.new(pos[2] - 1, pos[3] - 1) if pos
          rescue StandardError
            nil
          end

          Point.new(0, 0)
        end
      end
    end
  end
end
