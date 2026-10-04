# frozen_string_literal: true

# Explicit opt-in: the normal psych/merge entry point does not load the core or
# mutate its registry. Install a compatible generated core artifact separately.
require 'psych'
require 'json'
require 'structuredmerge_core'
require_relative 'version'

module Psych
  module Merge
    # Native syntax projection only. Rust owns semantic analysis and merging.
    # Derived from the retained Psych conformance projector in the kernel.
    class CoreParserHost
      CORE = ::StructuredmergeCore
      PROVIDER_ID = 'ruby.psych'
      # Psych 5.3.1 rejects valid BOM-prefixed Unicode fixtures. Keep the native
      # profile on the verified series until other versions pass the same gate.
      SUPPORTED_PSYCH = Gem::Requirement.new('~> 5.5.0')
      BOM_COLUMN_WIDTH = Psych.parse_stream("\uFEFFx: 1\n").children.first.start_column
      raise 'Unsupported Psych BOM column convention' unless [0, 1].include?(BOM_COLUMN_WIDTH)

      def descriptor
        CORE::ParserProviderDescriptor.new(id: PROVIDER_ID, family: 'native', runtime: RUBY_ENGINE,
          package: 'psych-merge', package_version: Version::VERSION, parser: 'psych', parser_version: Psych::VERSION,
          languages: ['yaml'], dialects: [], contracts: ['structuredmerge.parse-result/v1'],
          capabilities: %w[diagnostics native_extensions source_spans], probe_id: 'psych.loaded',
          priority: 0, metadata: {}, extensions: [])
      end

      def probe_batch(request)
        raise TypeError, 'Expected typed ProbeBatchRequest' unless request.is_a?(CORE::ProbeBatchRequest)

        CORE::ProbeBatchResult.new(items: request.items.map do |item|
          CORE::ParserProbeResult.new(available: compatible? && item.language == 'yaml' && item.dialect.nil?, loadable: true)
        end)
      end

      def parse_batch(request)
        raise TypeError, 'Expected typed ParseBatchRequest' unless request.is_a?(CORE::ParseBatchRequest)

        CORE::ParseBatchResult.new(items: request.items.map { |item| parse(item) })
      end

      private

      def compatible? = SUPPORTED_PSYCH.satisfied_by?(Gem::Version.new(Psych::VERSION))

      def parse(item)
        text = item.source.bytes.pack('C*').force_encoding(Encoding::UTF_8)
        code = if !compatible?
          'psych.unsupported_version'
        elsif item.language != 'yaml' || !item.dialect.nil?
          'psych.unsupported_language'
        elsif item.options.comments || item.options.tokens
          'psych.unsupported_options'
        elsif !text.valid_encoding? || item.source.descriptor.encoding.to_s != 'utf8'
          'psych.unsupported_source'
        end
        # Bare CR has different native coordinate semantics. Inspect bytes, not
        # source syntax; comments and ownership are never inferred from text.
        code = 'psych.unsupported_source' if text.b.gsub("\r\n", '').include?("\r")
        return failure(item, code) if code

        nodes = project(Psych.parse_stream(text), text, item.options.native_extensions)
        CORE::ParseOutput.new(request_id: item.request_id, source: item.source.descriptor,
          ok: true, root_id: nodes.first.id, nodes: nodes, comments: [], diagnostics: [],
          extensions: [], metadata: {}, extra: {})
      rescue Psych::SyntaxError
        # Psych exception messages can contain private source. Never forward them.
        failure(item, 'psych.syntax')
      end

      def failure(item, code)
        message = case code
        when 'psych.syntax' then 'Psych syntax error'
        when 'psych.unsupported_version' then 'Psych provider requires the verified Psych 5.5.x series'
        else 'Unsupported Psych provider input'
        end
        diagnostic = CORE::ParseDiagnostic.new(id: code, severity: :error, category: 'parse_error', code: code,
          message: message,
          source_role: item.source.descriptor.role, blocking: true, metadata: {}, extra: {})
        CORE::ParseOutput.new(request_id: item.request_id, source: item.source.descriptor, ok: false,
          nodes: [], comments: [], diagnostics: [diagnostic], extensions: [], metadata: {}, extra: {})
      end

      def project(stream, text, native_extensions)
        lines = text.split("\n", -1)
        bom_bytes = text.start_with?("\uFEFF") ? 3 : 0
        lines[0] = lines[0].delete_prefix("\uFEFF") if bom_bytes.positive?
        starts = [0]
        text.bytes.each_with_index { |byte, index| starts << index + 1 if byte == 10 }
        offset = lambda do |row, column|
          next text.bytesize if row == lines.length && column.zero?

          column -= BOM_COLUMN_WIDTH if row.zero? && bom_bytes.positive?
          line = lines.fetch(row)
          raise 'Invalid Psych character column' if column.negative? || column > line.length

          starts.fetch(row) + (row.zero? ? bom_bytes : 0) + line[0, column].bytesize
        end
        point = lambda do |byte|
          row = starts.bsearch_index { |start| start > byte }
          row = row ? row - 1 : starts.length - 1
          CORE::SourcePoint.new(row: row, column: byte - starts.fetch(row))
        end
        # Allocate stable preorder IDs before constructing immutable typed nodes.
        # Iterative traversal avoids adding a Ruby recursion limit to native ASTs.
        entries = []
        stack = [[stream, nil]]
        until stack.empty?
          node, parent = stack.pop
          id = "n#{entries.length}"
          entries << [node, parent, id]
          (node.children || []).reverse_each { |child| stack << [child, id] }
        end
        ids = entries.to_h { |node, _parent, id| [node.object_id, id] }
        entries.map do |node, parent, id|
          kind = node.class.name.split('::').last.downcase
          first = kind == 'stream' ? 0 : offset.call(node.start_line, node.start_column)
          last = kind == 'stream' ? text.bytesize : offset.call(node.end_line, node.end_column)
          facts = %i[value style plain quoted anchor tag implicit implicit_end].each_with_object({}) do |attribute, result|
            result[attribute] = node.public_send(attribute) if node.respond_to?(attribute)
          end
          extensions = native_extensions ? [CORE::NativeExtension.new(schema: 'structuredmerge.extension/ruby-psych/v1',
            namespace: 'ruby-psych', capabilities: [], payload: ::JSON.generate(facts), extra: {})] : []
          CORE::ParseNode.new(id: id, kind: kind, native_type: node.class.name, role: :structural,
            named: true, missing: false, has_error: false, parent_id: parent,
            span: CORE::SourceSpan.new(range: CORE::ByteRange.new(start_byte: first, end_byte: last),
              start_point: point.call(first), end_point: point.call(last)),
            children: (node.children || []).each_with_index.map do |child, index|
              CORE::ChildEdge.new(node_id: ids.fetch(child.object_id), index: index,
                field_name: kind == 'mapping' ? (index.even? ? 'key' : 'value') : nil)
            end,
            semantic_roles: [], unsupported_features: [], extensions: extensions, metadata: {}, extra: {})
        end
      end
    end
  end
end
