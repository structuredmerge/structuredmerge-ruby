# frozen_string_literal: true

module Yaml
  # YAML workflow provider integration.
  module Merge
    # TSLP projection for the shared YAML source-preserving provider.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- tree-sitter YAML validation and projection remain one adapter boundary
    class Provider < SourcePreservingProvider
      PROVIDER_ID = 'ruby.yaml'
      BACKEND = BACKEND_REFERENCE
      PACKAGE_NAME = Merge::PACKAGE_NAME
      PACKAGE_VERSION = Version::VERSION
      ROLE = :workflow

      private

      def analyze_role(role, source)
        analysis = TreeHaver.with_backend(backend_id) { FileAnalysis.new(source) }
        return invalid_analysis(role, source, analysis) unless analysis.valid?

        documents = analysis.documents
        issues = []
        issues << issue(:multiple_documents, 'YAML input must contain exactly one document') unless documents.one?
        document = documents.first
        root = document&.body_node
        issues << issue(:non_mapping_root, 'YAML document root must be a mapping') unless root&.mapping?
        issues.concat(node_issues(root)) if root

        parsed = Yaml::Merge.parse_yaml(source, 'yaml', backend: backend_id)
        unless parsed[:ok]
          diagnostic = parsed.fetch(:diagnostics).first || {}
          return invalid_document(role, source, diagnostic[:category] || :parse_error, diagnostic[:message])
        end

        entries = root&.mapping? ? mapping_entries(analysis, root, parsed.dig(:analysis, :document), source, role) : []
        duplicate = entries.group_by(&:key).find { |_key, matches| matches.length > 1 }
        issues << issue(:duplicate_key, "Duplicate YAML key #{duplicate.first}", key: duplicate.first) if duplicate

        Document.new(
          role: role,
          source: source,
          analysis: analysis,
          entries: entries.freeze,
          by_key: entries.to_h { |entry| [entry.key, entry] }.freeze,
          issues: issues.uniq.freeze,
          document_attributes: document ? node_attributes(document) : {}
        )
      rescue TreeHaver::Error => e
        invalid_document(role, source, :parse_error, e.message)
      rescue StandardError => e
        invalid_document(role, source, :structural_error, e.message)
      end

      def invalid_analysis(role, source, analysis)
        message = analysis.errors.map(&:to_s).join('; ')
        invalid_document(role, source, :parse_error, message.empty? ? 'YAML parse failed' : message)
      end

      def node_issues(root)
        issues = []
        walk_nodes(root.node) do |node|
          type = node.type.to_s
          issues << issue(:alias, 'YAML aliases require an exact one-sided merge') if type == 'alias'
          issues << issue(:anchor, 'YAML anchors require an exact one-sided merge') if type == 'anchor'
          issues << issue(:directive, 'YAML directives require an exact one-sided merge') if type.include?('directive')
          if %w[flow_mapping flow_sequence].include?(type)
            issues << issue(:flow_collection, 'Flow-style collections require an exact one-sided merge')
          end
        end
        issues.uniq.freeze
      end

      def walk_nodes(node, &block)
        yield node
        node.children.each { |child| walk_nodes(child, &block) }
      end

      def mapping_entries(analysis, root, semantic_document, source, role)
        root.mapping_pairs.filter_map.with_index do |pair, index|
          key = pair.key_name
          next invalid_top_level_entry(pair, source, role, index) unless key

          build_entry(analysis, pair, key, semantic_document[key], source, role, index)
        end
      end

      def invalid_top_level_entry(pair, source, role, index)
        Entry.new(
          key: "<complex-key-#{index}>",
          start_line: pair.start_line,
          end_line: pair.end_line,
          fragment: source_lines(source, pair.start_line, pair.end_line),
          semantic: nil,
          attributes: node_attributes(pair.value_node),
          role: role,
          ownership_provable: false
        )
      end

      def build_entry(analysis, pair, key, semantic, source, role, index)
        key_line = pair.start_line
        value_end = pair.end_line
        leading_start = owned_leading_start(analysis, pair, index, key_line)
        Entry.new(
          key: key,
          start_line: leading_start,
          end_line: value_end,
          fragment: source_lines(source, leading_start, value_end),
          semantic: semantic,
          attributes: node_attributes(pair.value_node),
          role: role,
          ownership_provable: ownership_provable?(analysis, pair, index, key_line, leading_start)
        )
      end

      def owned_leading_start(analysis, pair, index, key_line)
        return key_line if index.zero?

        region = analysis.comment_attachment_for(pair)&.leading_region
        return key_line unless region && region.end_line == key_line - 1
        return key_line if region.metadata[:floating]

        region.start_line
      end

      def ownership_provable?(analysis, pair, index, key_line, leading_start)
        return true if leading_start == key_line
        return false if index.zero?

        region = analysis.comment_attachment_for(pair)&.leading_region
        region && !region.metadata[:floating] && region.start_line == leading_start
      end

      def node_attributes(node)
        return {} unless node

        {
          type: node.type.to_s,
          canonical_type: node.type.to_s,
          signature: public_value(node.signature),
          children: node.semantic_children.map do |child|
            node_attributes(NodeWrapper.new(child, lines: node.lines, source: node.source))
          end
        }
      end

      def public_value(value)
        case value
        when Array then value.map { |item| public_value(item) }
        when Hash then value.to_h { |key, item| [key.to_s, public_value(item)] }
        when String, Integer, Float, TrueClass, FalseClass, NilClass then value
        else value.to_s
        end
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity

    class << self
      def merge_provider
        @merge_provider ||= Provider.new
      end

      def register_provider!(replace: false)
        Ast::Merge.register_provider(merge_provider, replace: replace)
      end
    end
  end
end
