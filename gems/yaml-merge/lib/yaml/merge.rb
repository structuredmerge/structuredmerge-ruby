# frozen_string_literal: true

require "yaml"

module Yaml
  module Merge
    PACKAGE_NAME = "yaml-merge"
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: "array",
      name: "destination_wins_array"
    }.freeze

    module_function

    def yaml_feature_profile
      {
        family: "yaml",
        supported_dialects: ["yaml"],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def parse_yaml(source, dialect)
      return unsupported_feature_result("Unsupported YAML dialect #{dialect}.") unless dialect == "yaml"

      parsed = Psych.safe_load(source, permitted_classes: [], aliases: false)
      return parse_error_result("YAML documents must parse to a mapping root.") unless parsed.is_a?(Hash)

      validated = validate_yaml_node(parsed, "")
      return { ok: false, diagnostics: [validated[:diagnostic]] } unless validated[:ok]

      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: "yaml",
          dialect: "yaml",
          normalized_source: canonical_yaml(validated[:value]),
          root_kind: "mapping",
          owners: collect_yaml_owners(validated[:value])
        },
        policies: []
      }
    rescue StandardError => e
      parse_error_result(e.message)
    end

    def match_yaml_owners(template, destination)
      destination_paths = destination[:owners].to_h { |owner| [owner[:path], true] }
      template_paths = template[:owners].to_h { |owner| [owner[:path], true] }

      {
        matched: template[:owners]
          .filter { |owner| destination_paths[owner[:path]] }
          .map { |owner| { template_path: owner[:path], destination_path: owner[:path] } },
        unmatched_template: template[:owners].map { |owner| owner[:path] }.reject { |path| destination_paths[path] },
        unmatched_destination: destination[:owners].map { |owner| owner[:path] }.reject { |path| template_paths[path] }
      }
    end

    def merge_yaml(template_source, destination_source, dialect)
      template = parse_yaml(template_source, dialect)
      return { ok: false, diagnostics: template[:diagnostics], policies: [] } unless template[:ok]

      destination = parse_yaml(destination_source, dialect)
      unless destination[:ok]
        return {
          ok: false,
          diagnostics: destination[:diagnostics].map do |diagnostic|
            diagnostic[:category] == "parse_error" ? diagnostic.merge(category: "destination_parse_error") : diagnostic
          end,
          policies: []
        }
      end

      {
        ok: true,
        diagnostics: [],
        output: canonical_yaml(
          merge_yaml_mappings(
            Psych.safe_load(template.dig(:analysis, :normalized_source), permitted_classes: [], aliases: false),
            Psych.safe_load(destination.dig(:analysis, :normalized_source), permitted_classes: [], aliases: false)
          )
        ),
        policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def validate_yaml_node(value, path)
      if scalar?(value)
        { ok: true, value: value }
      elsif value.is_a?(Array)
        if value.all? { |item| scalar?(item) }
          { ok: true, value: value }
        else
          unsupported_feature_result("Unsupported YAML sequence value at #{display_path(path)}. Only scalar sequences are supported.")
        end
      elsif value.is_a?(Hash)
        value.keys.sort.each_with_object({ ok: true, value: {} }) do |key, memo|
          validated = validate_yaml_node(value[key], "#{path}/#{key}")
          return validated unless validated[:ok]

          memo[:value][key] = validated[:value]
        end
      else
        unsupported_feature_result("Unsupported YAML value at #{display_path(path)}. Only mappings, scalar values, and scalar sequences are supported.")
      end
    end
    private_class_method :validate_yaml_node

    def scalar?(value)
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
    end
    private_class_method :scalar?

    def display_path(path)
      path.empty? ? "/" : path
    end
    private_class_method :display_path

    def render_yaml_scalar(value)
      if value.is_a?(String)
        value.match?(/\A[A-Za-z0-9_.-]+\z/) ? value : JSON.generate(value)
      elsif value == true || value == false
        value ? "true" : "false"
      else
        value.to_s
      end
    end
    private_class_method :render_yaml_scalar

    def render_yaml_node(key, value, indent)
      prefix = " " * indent
      if value.is_a?(Array)
        ["#{prefix}#{key}:"] + value.map { |item| "#{" " * (indent + 2)}- #{render_yaml_scalar(item)}" }
      elsif value.is_a?(Hash)
        ["#{prefix}#{key}:"] + render_yaml_mapping(value, indent + 2)
      else
        ["#{prefix}#{key}: #{render_yaml_scalar(value)}"]
      end
    end
    private_class_method :render_yaml_node

    def render_yaml_mapping(mapping, indent = 0)
      mapping.keys.sort.flat_map do |key|
        render_yaml_node(key, mapping[key], indent)
      end
    end
    private_class_method :render_yaml_mapping

    def canonical_yaml(mapping)
      "#{render_yaml_mapping(mapping).join("\n")}\n"
    end
    private_class_method :canonical_yaml

    def collect_yaml_owners(mapping, prefix = "")
      mapping.keys.sort.flat_map do |key|
        path = "#{prefix}/#{key}"
        value = mapping[key]
        if value.is_a?(Array)
          [{ path: path, owner_kind: "key_value", match_key: key }] +
            value.each_index.map { |index| { path: "#{path}/#{index}", owner_kind: "sequence_item" } }
        elsif value.is_a?(Hash)
          [{ path: path, owner_kind: "mapping", match_key: key }] + collect_yaml_owners(value, path)
        else
          [{ path: path, owner_kind: "key_value", match_key: key }]
        end
      end
    end
    private_class_method :collect_yaml_owners

    def merge_yaml_mappings(template, destination)
      (template.keys | destination.keys).sort.each_with_object({}) do |key, merged|
        if !template.key?(key)
          merged[key] = destination[key]
        elsif !destination.key?(key)
          merged[key] = template[key]
        elsif template[key].is_a?(Hash) && destination[key].is_a?(Hash)
          merged[key] = merge_yaml_mappings(template[key], destination[key])
        else
          merged[key] = destination[key]
        end
      end
    end
    private_class_method :merge_yaml_mappings

    def parse_error_result(message)
      { ok: false, diagnostics: [{ severity: "error", category: "parse_error", message: message }] }
    end
    private_class_method :parse_error_result

    def unsupported_feature_result(message)
      { ok: false, diagnostic: { severity: "error", category: "unsupported_feature", message: message } }
    end
    private_class_method :unsupported_feature_result
  end
end
