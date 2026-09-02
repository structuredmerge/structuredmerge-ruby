# frozen_string_literal: true

module Psych
  # Psych-backed YAML provider integration.
  module Merge
    # Native Psych projection for the shared YAML source-preserving provider.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- native AST validation and projection remain one adapter boundary
    class Provider < ::Yaml::Merge::SourcePreservingProvider
      PROVIDER_ID = 'ruby.yaml.psych'
      BACKEND = BACKEND_REFERENCE
      PACKAGE_NAME = Merge::PACKAGE_NAME
      PACKAGE_VERSION = Version::VERSION
      ROLE = :backend

      private

      def analyze_role(role, source)
        analysis = FileAnalysis.new(source)
        stream = analysis.ast
        documents = stream&.children || []
        issues = []
        issues << issue(:multiple_documents, 'YAML input must contain exactly one document') unless documents.one?
        document = documents.first
        issues.concat(document_issues(document))
        root = document&.children&.first
        unless root.is_a?(::Psych::Nodes::Mapping)
          issues << issue(:non_mapping_root, 'YAML document root must be a mapping')
        end
        issues.concat(node_issues(root)) if root

        entries = root.is_a?(::Psych::Nodes::Mapping) ? mapping_entries(analysis, source, role) : []
        duplicate = entries.group_by(&:key).find { |_key, matches| matches.length > 1 }
        issues << issue(:duplicate_key, "Duplicate YAML key #{duplicate.first}", key: duplicate.first) if duplicate

        Document.new(
          role: role,
          source: source,
          analysis: analysis,
          entries: entries.freeze,
          by_key: entries.to_h { |entry| [entry.key, entry] }.freeze,
          issues: issues.freeze,
          document_attributes: document ? ast_attributes(document) : {}
        )
      rescue ::Psych::SyntaxError, Psych::Merge::ParseError => e
        invalid_document(role, source, :parse_error, e.message)
      rescue StandardError => e
        invalid_document(role, source, :structural_error, e.message)
      end

      def document_issues(document)
        return [] unless document

        issues = []
        unless Array(document.version).empty? && Array(document.tag_directives).empty?
          issues << issue(:directive, 'YAML directives require an exact one-sided merge')
        end
        issues
      end

      def node_issues(node)
        issues = []
        walk_nodes(node) do |current|
          if current.is_a?(::Psych::Nodes::Alias)
            issues << issue(:alias, 'YAML aliases require an exact one-sided merge')
          end
          if current.respond_to?(:anchor) && !current.anchor.to_s.empty?
            issues << issue(:anchor, 'YAML anchors require an exact one-sided merge')
          end
          if flow_collection?(current)
            issues << issue(:flow_collection, 'Flow-style collections require an exact one-sided merge')
          end
          next unless current.is_a?(::Psych::Nodes::Mapping)

          keys = current.children.each_slice(2).map(&:first).compact
          if current.equal?(node) && keys.any? { |key| !key.is_a?(::Psych::Nodes::Scalar) }
            issues << issue(:complex_key, 'Top-level YAML keys must be scalars')
          end
          if keys.any? { |key| key.is_a?(::Psych::Nodes::Scalar) && key.value == '<<' }
            issues << issue(:merge_key, 'YAML merge keys require an exact one-sided merge')
          end
          duplicate = keys.group_by { |key| semantic_key(key) }.find { |_key, matches| matches.length > 1 }
          issues << issue(:duplicate_key, 'Duplicate YAML mapping key') if duplicate
        end
        issues.uniq.freeze
      end

      def walk_nodes(node, &block)
        yield node
        Array(node.respond_to?(:children) ? node.children : []).each { |child| walk_nodes(child, &block) }
      end

      def flow_collection?(node)
        case node
        when ::Psych::Nodes::Mapping
          node.style == ::Psych::Nodes::Mapping::FLOW
        when ::Psych::Nodes::Sequence
          node.style == ::Psych::Nodes::Sequence::FLOW
        else
          false
        end
      end

      def mapping_entries(analysis, source, role)
        analysis.root_mapping_entries.filter_map.with_index do |(key, value), index|
          next unless key && value

          unless key.node.is_a?(::Psych::Nodes::Scalar)
            next invalid_top_level_entry(analysis, key, value, source, role, index)
          end

          build_entry(analysis, key, value, source, role, index)
        end
      end

      def invalid_top_level_entry(analysis, key, value, source, role, index)
        entry = build_entry(analysis, key, value, source, role, index)
        Entry.new(**entry.to_h.merge(key: "<complex-key-#{index}>", ownership_provable: false))
      end

      def build_entry(analysis, key, value, source, role, index)
        lines = source.lines
        mapping = MappingEntry.new(key: key, value: value, lines: lines, comment_tracker: analysis.comment_tracker)
        key_line = key.start_line || 1
        value_end = [value.end_line || key.end_line || key_line, key_line].max
        leading_start = owned_leading_start(analysis, mapping, index, key_line)
        Entry.new(
          key: key.node.value.to_s,
          start_line: leading_start,
          end_line: value_end,
          fragment: source_lines(source, leading_start, value_end),
          semantic: NativeProjection.semantic(value.node),
          attributes: NativeProjection.attribute_tree(value.node),
          role: role,
          ownership_provable: ownership_provable?(analysis, mapping, index, key_line, leading_start)
        )
      end

      def owned_leading_start(analysis, mapping, index, key_line)
        return key_line if index.zero?

        region = analysis.comment_attachment_for(mapping)&.leading_region
        return key_line unless region && region.end_line == key_line - 1
        return key_line if region.metadata[:floating]

        region.start_line
      end

      def ownership_provable?(analysis, mapping, index, key_line, leading_start)
        return true if leading_start == key_line
        return false if index.zero?

        region = analysis.comment_attachment_for(mapping)&.leading_region
        region && !region.metadata[:floating] && region.start_line == leading_start
      end

      def semantic_key(node)
        return [:complex, NativeProjection.semantic(node)] unless node.is_a?(::Psych::Nodes::Scalar)

        [node.value, node.tag]
      end

      def ast_attributes(node)
        NativeProjection.attributes(node)
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
