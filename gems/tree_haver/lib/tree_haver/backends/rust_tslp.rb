# frozen_string_literal: true

require 'json'
require 'digest'

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

        def register_language_parser(language)
          return unless available?
          # Cache only registrations made by this adapter, never adopt a foreign
          # duplicate ID. An external removal therefore fails closed on parse.
          REGISTRATION_MUTEX.synchronize do
            @registrations ||= {}
            key = [::StructuredmergeCore, language.to_s]
            @registrations[key] ||= ::StructuredmergeCore.register_language_pack_parser(
              "tree_haver.rust_tslp.#{language}", language.to_s
            ).id
          end
        end

        private

        # rubocop:disable Metrics/MethodLength
        def load_host
          unless RUBY_ENGINE == 'ruby'
            @unavailable_reason = 'the Rust TreeHaver Magnus bridge requires MRI Ruby'
            return false
          end

          require 'structuredmerge_core' unless defined?(::StructuredmergeCore)
          unless ::StructuredmergeCore.respond_to?(:parse_sources) && ::StructuredmergeCore.respond_to?(:register_language_pack_parser)
            @unavailable_reason = 'structuredmerge-core does not expose typed Rust parser registration'
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

      REGISTRATION_MUTEX = Mutex.new

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
          core = ::StructuredmergeCore
          provider_id = RustTslp.register_language_parser(language.name)
          crlf = normalized_source.scan("\r\n").length
          descriptor = core::SourceDescriptor.new(
            source_id: 'tree_haver.source', role: 'source', byte_length: normalized_source.bytesize,
            sha256: Digest::SHA256.hexdigest(normalized_source), encoding: 'utf8',
            bom: normalized_source.start_with?("\uFEFF"), final_newline: normalized_source.end_with?("\n", "\r"),
            line_endings: core::LineEndings.new(lf: normalized_source.count("\n") - crlf,
              crlf: crlf, bare_cr: normalized_source.count("\r") - crlf)
          )
          request = core::ParseRequest.new(
            schema: 'structuredmerge.parse-request/v1', request_id: 'tree_haver.parse',
            source: core::SourceInput.new(descriptor: descriptor, bytes: normalized_source.bytes),
            language: language.name.to_s, dialect: nil,
            selection: core::ParserSelection.new(backend_id: provider_id, preference: [], required_capabilities: []),
            options: core::ParseOptions.new(comments: true, diagnostics: true, tokens: false, native_extensions: true),
            metadata: {}, extra: {}
          )
          limits = core::ParseLimits.new(max_batch_items: 1, max_input_bytes: 64 * 1024 * 1024,
            max_nodes: 1_000_000, max_diagnostics: 1000)
          result = core.parse_sources([request], limits).fetch(0)
          Tree.new(result, source: normalized_source, language: language.name)
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        private

        def normalize_source_encoding(source)
          if [Encoding::UTF_8, Encoding::BINARY, Encoding::US_ASCII].include?(source.encoding)
            utf8 = source.dup.force_encoding(Encoding::UTF_8)
            return utf8.freeze if utf8.valid_encoding?
          end

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
          @nodes_by_id = result.parsed.nodes.to_h { |node| [node.id, node] }
          @root_id = result.parsed.root_id
          @diagnostics = result.parsed.diagnostics.map(&:message)
          @provenance = {
            'backend_ref' => { 'id' => result.backend.id },
            'language' => @language, 'runtime' => result.backend.runtime,
            'parser' => result.backend.parser, 'parser_version' => result.backend.parser_version
          }
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
          nodes = result.parsed.nodes
          root_id = result.parsed.root_id
          valid_root = root_id.is_a?(String) && nodes.any? { |node| node.id == root_id }
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

        def native_type = inner_node.native_type

        def start_byte = span.range.start_byte
        def end_byte = span.range.end_byte
        def start_point = symbolize_point(span.start_point)
        def end_point = symbolize_point(span.end_point)
        def child_count = inner_node.children.length
        def named? = inner_node.named
        def has_error? # rubocop:disable Naming/PredicatePrefix
          inner_node.has_error
        end
        def error? = has_error?
        def missing? = inner_node.missing
        def extra?
          extension = inner_node.extensions.find { |item| item.schema == 'tree-haver.tree-sitter.node/v1' && item.namespace == 'tree-sitter' }
          raise TreeHaver::Error, 'Rust TreeHaver omitted native node flags' unless extension

          # Alef transports only the open extension payload as JSON, not the tree.
          JSON.parse(extension.payload).fetch('extra')
        end

        def text
          source.byteslice(start_byte...end_byte)
        end

        def child(index)
          edge = inner_node.children[index]
          edge && wrap(@nodes_by_id.fetch(edge.node_id))
        end

        def children
          inner_node.children.map { |edge| wrap(@nodes_by_id.fetch(edge.node_id)) }
        end

        def child_by_field_name(name)
          edge = inner_node.children.find { |item| item.field_name == name.to_s }
          edge && wrap(@nodes_by_id.fetch(edge.node_id))
        end

        def parent
          parent_id = inner_node.parent_id
          parent_id && wrap(@nodes_by_id.fetch(parent_id))
        end

        def next_sibling
          sibling_at(1)
        end

        def prev_sibling
          sibling_at(-1)
        end

        private

        def span = inner_node.span

        def symbolize_point(point)
          { row: point.row, column: point.column }
        end

        def wrap(node)
          self.class.new(node, nodes_by_id: @nodes_by_id, source: source, lines: lines, language: language)
        end

        def sibling_at(offset)
          parent_node = parent
          return unless parent_node

          siblings = parent_node.inner_node.children.map(&:node_id)
          index = siblings.index(inner_node.id)
          sibling_index = index&.+(offset)
          return unless sibling_index&.between?(0, siblings.length - 1)

          sibling_id = siblings[sibling_index]
          sibling_id && wrap(@nodes_by_id.fetch(sibling_id))
        end
      end
    end
  end
end
