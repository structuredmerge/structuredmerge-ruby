# frozen_string_literal: true

module TreeHaver
  module Backends
    # TSLP backend using tree_sitter_language_pack's on-demand parser API.
    #
    # This backend intentionally requires the real parser API. The language-pack
    # process API is not a TreeHaver parser backend and must not be used as a
    # merge-gem integration surface.
    module Tslp
      @load_attempted = false
      @loaded = false
      @unavailable_reason = nil

      class << self
        attr_reader :unavailable_reason

        def available?
          return @loaded if @load_attempted

          @load_attempted = true
          begin
            require 'tree_sitter_language_pack'
            @loaded = parser_api_available?
            @unavailable_reason = 'tree_sitter_language_pack parser API is not exposed' unless @loaded
          rescue LoadError => e
            @loaded = false
            @unavailable_reason = e.message
          rescue StandardError => e
            @loaded = false
            @unavailable_reason = e.message
          end
          @loaded
        end

        def reset!
          @load_attempted = false
          @loaded = false
          @unavailable_reason = nil
        end

        def capabilities
          return {} unless available?

          {
            backend: :tslp,
            query: false,
            bytes_field: true,
            incremental: false,
            comment_support: :nodes_only,
            language_pack: true
          }
        end

        private

        def parser_api_available?
          return false unless ::TreeSitterLanguagePack.respond_to?(:get_parser)
          return false unless defined?(::TreeSitterLanguagePack::Parser)

          ::TreeSitterLanguagePack::Parser.instance_methods.include?(:parse)
        rescue StandardError => e
          @unavailable_reason = e.message
          false
        end
      end

      class Language < TreeHaver::Base::Language
        def initialize(name)
          super(name.to_sym, backend: :tslp, options: {})
        end

        class << self
          def from_library(_path = nil, symbol: nil, name: nil) # rubocop:disable Lint/UnusedMethodArgument
            new(name || :unknown)
          end
        end
      end

      class Parser < TreeHaver::Base::Parser
        def parse(source)
          raise TreeHaver::NotAvailable, unavailable_message unless Tslp.available?
          raise TreeHaver::NotAvailable, 'TSLP language is not set' unless language

          parser = ::TreeSitterLanguagePack.get_parser(language.name.to_s)
          raise TreeHaver::NotAvailable, "TSLP did not return a parser for #{language.name}" unless parser

          raw_tree = parser.parse(source)
          raise TreeHaver::NotAvailable, "TSLP did not return a parse tree for #{language.name}" unless raw_tree

          Tree.new(raw_tree, source: source)
        end

        private

        def unavailable_message
          reason = Tslp.unavailable_reason
          detail = reason.to_s.empty? ? 'unknown reason' : reason
          "tree_sitter_language_pack parser API is unavailable: #{detail}"
        end
      end

      class Tree < TreeHaver::Base::Tree
        def root_node
          Node.new(inner_tree.root_node, source: source, lines: lines)
        end
      end

      class Node < TreeHaver::Base::Node
        def type
          inner_node.kind
        end

        def start_byte
          inner_node.start_byte
        end

        def end_byte
          inner_node.end_byte
        end

        def children
          Array.new(inner_node.child_count) do |index|
            child = inner_node.child(index)
            child && self.class.new(child, source: source, lines: lines)
          end.compact
        end

        def named?
          inner_node.is_named
        end

        def has_error?
          inner_node.has_error
        end

        def error?
          inner_node.is_error
        end

        def missing?
          inner_node.is_missing
        end

        def extra?
          inner_node.is_extra
        end
      end
    end
  end
end
