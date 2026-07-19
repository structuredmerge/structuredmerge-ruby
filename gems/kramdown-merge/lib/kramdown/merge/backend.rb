# frozen_string_literal: true

module Kramdown
  module Merge
    module Backend
      Markdown::Merge::BackendSupport.install!(
        backend_module: self,
        backend_name: :kramdown,
        gem_name: 'kramdown',
        require_path: 'kramdown/merge'
      )

      class Language < ::TreeHaver::Base::Language
        def initialize(name = :markdown, options: {})
          super(name, backend: :kramdown, options: options)
        end

        class << self
          def markdown(options: {})
            new(:markdown, options: options)
          end
        end

        Markdown::Merge::BackendSupport.configure_markdown_only_language_class!(
          self,
          backend_label: 'Kramdown'
        )
      end

      class Parser < ::TreeHaver::Base::Parser
        def parse(source)
          raise 'Language not set' unless language

          Backend.available? or raise 'Kramdown not available'

          document = ::Kramdown::Document.new(source, **(language.options || {}))
          Tree.new(document.root, source)
        end
      end

      class Node < ::TreeHaver::Base::Node
        TYPE_MAP = {
          root: 'document',
          header: 'heading',
          codeblock: 'code_block',
          p: 'paragraph'
        }.freeze

        Markdown::Merge::BackendSupport.configure_node_link_and_navigation!(
          self,
          next_sibling_selector: :next,
          prev_sibling_selector: :previous,
          parent_selector: :parent
        )
        Markdown::Merge::BackendSupport.configure_node_heading_and_code_block_helpers!(
          self,
          heading_matcher: ->(node) { node.raw_type == 'header' },
          code_block_matcher: ->(node) { node.raw_type == 'codeblock' }
        )

        def type
          TYPE_MAP.fetch(raw_type.to_sym, raw_type)
        end

        alias kind type

        def raw_type
          inner_node.type.to_s
        end

        def text
          return inner_node.value.to_s if inner_node.value
          return inner_node.options[:raw_text].to_s if inner_node.options.key?(:raw_text)

          children.map(&:text).join
        end

        def children
          Array(inner_node.children).map { |child| self.class.new(child, source: source, lines: lines) }
        end

        def header_level
          return unless raw_type == 'header'

          inner_node.options[:level]
        end

        def fence_info
          return unless raw_type == 'codeblock'

          inner_node.options[:lang]
        end

        def start_point
          line = [inner_node.options.fetch(:location, 1).to_i - 1, 0].max
          Point.new(line, 0)
        end

        def end_point
          Point.new([start_point.row + text.lines.count - 1, start_point.row].max, 0)
        end

        def start_byte
          calculate_byte_offset(start_point.row, start_point.column)
        end

        def end_byte
          calculate_byte_offset(end_point.row, end_point.column)
        end
      end
    end
  end
end
