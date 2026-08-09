# frozen_string_literal: true

require 'json'

module Ast
  module Merge
    # Parser-neutral semantic analysis shared by YAML backend providers.
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ModuleLength, Metrics/PerceivedComplexity -- recursive YAML validation, rendering, and ownership are one parser-neutral semantic boundary
    module YamlDocument
      module_function

      def analyze(parsed, dialect)
        return unsupported("Unsupported YAML dialect #{dialect}.") unless dialect == 'yaml'
        return parse_error('YAML documents must parse to a mapping root.') unless parsed.is_a?(Hash)

        validated = validate_node(parsed, '')
        return { ok: false, diagnostics: [validated[:diagnostic]], policies: [] } unless validated[:ok]

        {
          ok: true,
          diagnostics: [],
          analysis: {
            kind: 'yaml',
            dialect: 'yaml',
            normalized_source: canonical_yaml(validated[:value]),
            document: validated[:value],
            root_kind: 'mapping',
            owners: collect_owners(validated[:value])
          },
          policies: []
        }
      end

      def match_owners(template, destination)
        destination_paths = destination[:owners].to_h { |owner| [owner[:path], true] }
        template_paths = template[:owners].to_h { |owner| [owner[:path], true] }

        {
          matched: template[:owners]
                   .filter { |owner| destination_paths[owner[:path]] }
                   .map { |owner| { template_path: owner[:path], destination_path: owner[:path] } },
          unmatched_template: template[:owners].map { |owner| owner[:path] }.reject { |path| destination_paths[path] },
          unmatched_destination: destination[:owners]
                                 .map { |owner| owner[:path] }
                                 .reject { |path| template_paths[path] }
        }
      end

      def validate_node(value, path)
        if scalar?(value)
          { ok: true, value: value }
        elsif value.is_a?(Array)
          value.each_with_index.each_with_object({ ok: true, value: [] }) do |(item, index), memo|
            validated = validate_node(item, "#{path}/#{index}")
            return validated unless validated[:ok]

            memo[:value] << validated[:value]
          end
        elsif value.is_a?(Hash)
          value.each_with_object({ ok: true, value: {} }) do |(key, item), memo|
            validated = validate_node(item, "#{path}/#{key}")
            return validated unless validated[:ok]

            memo[:value][key] = validated[:value]
          end
        else
          unsupported("Unsupported YAML value at #{path.empty? ? '/' : path}. " \
                      'Only mappings, scalar values, and sequences are supported.')
        end
      end
      private_class_method :validate_node

      def scalar?(value)
        value.nil? || value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
      end
      private_class_method :scalar?

      def canonical_yaml(mapping)
        "#{render_mapping(mapping).join("\n")}\n"
      end
      private_class_method :canonical_yaml

      def render_mapping(mapping, indent = 0)
        mapping.flat_map do |key, value|
          prefix = ' ' * indent
          if value.is_a?(Array)
            ["#{prefix}#{key}:"] + render_sequence(value, indent + 2)
          elsif value.is_a?(Hash)
            ["#{prefix}#{key}:"] + render_mapping(value, indent + 2)
          elsif value.nil?
            ["#{prefix}#{key}:"]
          else
            ["#{prefix}#{key}: #{render_scalar(value)}"]
          end
        end
      end
      private_class_method :render_mapping

      def render_sequence(sequence, indent)
        prefix = ' ' * indent
        sequence.flat_map do |item|
          if scalar?(item)
            ["#{prefix}- #{render_scalar(item)}"]
          elsif item.is_a?(Hash)
            ["#{prefix}-"] + render_mapping(item, indent + 2)
          elsif item.is_a?(Array)
            ["#{prefix}-"] + render_sequence(item, indent + 2)
          end
        end
      end
      private_class_method :render_sequence

      def render_scalar(value)
        return '' if value.nil?
        return value ? 'true' : 'false' if [true, false].include?(value)
        return value.to_s unless value.is_a?(String)

        value.match?(/\A[A-Za-z0-9_.-]+\z/) ? value : JSON.generate(value)
      end
      private_class_method :render_scalar

      def collect_owners(mapping, prefix = '')
        mapping.keys.sort.flat_map do |key|
          path = "#{prefix}/#{key}"
          value = mapping[key]
          if value.is_a?(Array)
            [{ path: path, owner_kind: 'key_value', match_key: key }] +
              value.each_with_index.flat_map do |item, index|
                item_path = "#{path}/#{index}"
                nested = item.is_a?(Hash) ? collect_owners(item, item_path) : []
                [{ path: item_path, owner_kind: 'sequence_item' }] + nested
              end
          elsif value.is_a?(Hash)
            [{ path: path, owner_kind: 'mapping', match_key: key }] + collect_owners(value, path)
          else
            [{ path: path, owner_kind: 'key_value', match_key: key }]
          end
        end
      end
      private_class_method :collect_owners

      def parse_error(message)
        { ok: false, diagnostics: [{ severity: 'error', category: 'parse_error', message: message }], policies: [] }
      end
      private_class_method :parse_error

      def unsupported(message)
        {
          ok: false,
          diagnostic: { severity: 'error', category: 'unsupported_feature', message: message },
          diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: message }],
          policies: []
        }
      end
      private_class_method :unsupported
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ModuleLength, Metrics/PerceivedComplexity
  end
end
