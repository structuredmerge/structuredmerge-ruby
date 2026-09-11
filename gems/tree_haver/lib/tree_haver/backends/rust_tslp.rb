# frozen_string_literal: true

require 'json'

module TreeHaver
  module Backends
    # Explicit Magnus bridge to the canonical Rust TreeHaver/TSLP substrate.
    #
    # This backend deliberately exposes only the normalized tree contract. It
    # does not replace the direct Ruby language-pack or tree_stump backends.
    module RustTslp
      class << self
        attr_reader :unavailable_reason

        def available?
          return @loaded if @load_attempted

          @load_attempted = true
          @loaded = load_host
        end

        def reset!
          @load_attempted = false
          @loaded = false
          @unavailable_reason = nil
        end

        def capabilities
          return {} unless available?

          {
            backend: :rust_tslp,
            query: false,
            bytes_field: true,
            incremental: false,
            comment_support: :nodes_only,
            language_pack: true,
            provenance: :rust_tree_haver
          }
        end

        private

        # rubocop:disable Metrics/MethodLength
        def load_host
          unless RUBY_ENGINE == 'ruby'
            @unavailable_reason = 'the Rust TreeHaver Magnus bridge requires MRI Ruby'
            return false
          end

          require 'structuredmerge_host_prototype' unless defined?(::StructuredmergeHostPrototype)
          unless ::StructuredmergeHostPrototype.respond_to?(:parse_normalized_with_tslp)
            @unavailable_reason = 'the Rust TreeHaver host does not expose normalized TSLP parsing'
            return false
          end

          true
        rescue LoadError => e
          @unavailable_reason = e.message
          false
        rescue StandardError => e
          @unavailable_reason = e.message
          false
        end
        # rubocop:enable Metrics/MethodLength
      end

      # Identifies a language parsed by the canonical Rust substrate.
      class Language < TreeHaver::Base::Language
        def initialize(name)
          super(name, backend: :rust_tslp, options: {})
        end

        class << self
          def from_library(_path = nil, symbol: nil, name: nil) # rubocop:disable Lint/UnusedMethodArgument
            new(name || :unknown)
          end
        end
      end

      # Parses source into the Rust normalized tree representation.
      class Parser < TreeHaver::Base::Parser
        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def parse(source)
          raise TreeHaver::NotAvailable, unavailable_message unless RustTslp.available?
          raise TreeHaver::NotAvailable, 'Rust TSLP language is not set' unless language

          normalized_source = normalize_source_encoding(source)
          result = JSON.parse(
            ::StructuredmergeHostPrototype.parse_normalized_with_tslp(
              language.name.to_s,
              normalized_source,
              language.name.to_s
            )
          )
          Tree.new(result, source: normalized_source, language: language.name)
        rescue JSON::ParserError => e
          raise TreeHaver::Error, "Rust TreeHaver returned invalid normalized JSON: #{e.message}"
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        private

        def normalize_source_encoding(source)
          return source unless source.encoding == Encoding::BINARY

          utf8 = source.dup.force_encoding(Encoding::UTF_8)
          return utf8 if utf8.valid_encoding?

          raise TreeHaver::NotAvailable, 'Rust TreeHaver normalized parsing requires valid UTF-8 source bytes'
        end

        def unavailable_message
          detail = RustTslp.unavailable_reason.to_s
          detail = 'unknown reason' if detail.empty?
          "Rust TreeHaver normalized parser is unavailable: #{detail}"
        end
      end

      # Wraps one validated Rust normalized parse result.
      class Tree < TreeHaver::Base::Tree
        attr_reader :diagnostics, :language, :provenance

        def initialize(result, source:, language:)
          validate_result!(result)
          super(result, source: source)
          @language = language.to_s
          @nodes_by_id = result.fetch('nodes').to_h { |node| [node.fetch('id'), node] }
          @root_id = result.fetch('root_id')
          @diagnostics = result.fetch('diagnostics', [])
          @provenance = result.fetch('backend_capability', {})
        end

        def root_node
          Node.new(
            @nodes_by_id.fetch(@root_id),
            nodes_by_id: @nodes_by_id,
            source: source,
            lines: lines,
            language: language
          )
        end

        def errors
          diagnostics
        end

        private

        def validate_result!(result)
          raise TreeHaver::Error, 'Rust TreeHaver returned a non-object normalized result' unless result.is_a?(Hash)

          nodes = result['nodes']
          root_id = result['root_id']
          valid_root = nodes.is_a?(Array) && root_id.is_a?(String) &&
                       nodes.any? { |node| node.is_a?(Hash) && node['id'] == root_id }
          return if valid_root

          raise TreeHaver::Error, 'Rust TreeHaver returned an invalid normalized tree'
        end
      end

      # Adapts normalized node records to TreeHaver's node contract.
      class Node < TreeHaver::Base::Node
        # Preserve the established TreeHaver surface when the two language-pack
        # implementations expose equivalent JSON5 grammar nodes under different
        # native names.
        NODE_TYPE_ALIASES = {
          'json5' => {
            'file' => 'document',
            'member' => 'pair'
          }
        }.freeze

        attr_reader :language

        def initialize(node, nodes_by_id:, source: nil, lines: nil, language: nil)
          super(node, source: source, lines: lines)
          @nodes_by_id = nodes_by_id
          @language = language.to_s
        end

        def type
          NODE_TYPE_ALIASES.fetch(language, {}).fetch(native_type, native_type)
        end

        def native_type = inner_node.fetch('kind')

        def start_byte = span.fetch('range').fetch('start_byte')
        def end_byte = span.fetch('range').fetch('end_byte')
        def start_point = symbolize_point(span.fetch('start_point'))
        def end_point = symbolize_point(span.fetch('end_point'))
        def child_count = inner_node.fetch('child_ids', []).length
        def named? = inner_node.fetch('named', false)
        def has_error? = role == 'error' || backend_roles.include?('error') # rubocop:disable Naming/PredicatePrefix
        def error? = has_error?
        def missing? = backend_roles.include?('missing')
        def extra? = backend_roles.include?('extra')

        def text
          return inner_node.fetch('source_fragment') if inner_node.fetch('has_source_text', false)

          raise TreeHaver::Error, "Rust TreeHaver has no source fragment for node #{inner_node.fetch('id')}"
        end

        def child(index)
          child_id = inner_node.fetch('child_ids', [])[index]
          child_id && wrap(@nodes_by_id.fetch(child_id))
        end

        def children
          inner_node.fetch('child_ids', []).map { |child_id| wrap(@nodes_by_id.fetch(child_id)) }
        end

        def child_by_field_name(name)
          children.find { |child| child.inner_node['field_name'] == name.to_s }
        end

        def parent
          parent_id = inner_node['parent_id']
          parent_id && wrap(@nodes_by_id.fetch(parent_id))
        end

        def next_sibling
          sibling_at(1)
        end

        def prev_sibling
          sibling_at(-1)
        end

        private

        def span = inner_node.fetch('span')
        def role = inner_node.fetch('role', '')
        def backend_roles = inner_node.fetch('backend_roles', [])

        def symbolize_point(point)
          { row: point.fetch('row'), column: point.fetch('column') }
        end

        def wrap(node)
          self.class.new(node, nodes_by_id: @nodes_by_id, source: source, lines: lines, language: language)
        end

        def sibling_at(offset)
          parent_node = parent
          return unless parent_node

          siblings = parent_node.inner_node.fetch('child_ids', [])
          index = siblings.index(inner_node.fetch('id'))
          sibling_index = index&.+(offset)
          return unless sibling_index&.between?(0, siblings.length - 1)

          sibling_id = siblings[sibling_index]
          sibling_id && wrap(@nodes_by_id.fetch(sibling_id))
        end
      end
    end
  end
end
