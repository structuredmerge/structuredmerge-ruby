# frozen_string_literal: true

require "toml"
require "toml-rb"
require "tree_haver"

module Toml
  module Merge
    PACKAGE_NAME = "toml-merge"
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: "array",
      name: "destination_wins_array"
    }.freeze
    BACKEND_REFERENCES = {
      "citrus" => TreeHaver::CITRUS_BACKEND,
      "parslet" => TreeHaver::PARSLET_BACKEND
    }.freeze

    module_function

    def toml_feature_profile
      {
        family: "toml",
        supported_dialects: ["toml"],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def toml_backend_feature_profile(backend: nil)
      resolved_backend = resolve_backend(backend)
      backend_ref = backend_reference_for(resolved_backend)
      return unsupported_feature_result("Unsupported TOML backend #{resolved_backend}.") unless backend_ref

      toml_feature_profile.merge(
        backend: backend_ref.id,
        backend_ref: backend_ref.to_h
      )
    end

    def available_toml_backends
      BACKEND_REFERENCES.values
    end

    def parse_toml(source, dialect, backend: nil)
      return unsupported_feature_result("Unsupported TOML dialect #{dialect}.") unless dialect == "toml"

      resolved_backend = resolve_backend(backend)
      syntax_result = parse_toml_syntax(source, resolved_backend)
      return { ok: false, diagnostics: syntax_result[:diagnostics] } unless syntax_result[:ok]

      parsed = load_toml_document(source, resolved_backend)
      validated = validate_toml_node(parsed, "")
      return { ok: false, diagnostics: [validated[:diagnostic]] } unless validated[:ok]
      return parse_error_result("TOML documents must parse to a table root.") unless validated[:value].is_a?(Hash)

      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: "toml",
          dialect: "toml",
          normalized_source: canonical_toml(validated[:value]),
          root_kind: "table",
          owners: collect_toml_owners(validated[:value])
        },
        policies: []
      }
    rescue StandardError => e
      parse_error_result(e.message)
    end

    def match_toml_owners(template, destination)
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

    def merge_toml(template_source, destination_source, dialect, backend: nil)
      resolved_backend = resolve_backend(backend)
      template = parse_toml(template_source, dialect, backend: resolved_backend)
      return { ok: false, diagnostics: template[:diagnostics], policies: [] } unless template[:ok]

      destination = parse_toml(destination_source, dialect, backend: resolved_backend)
      unless destination[:ok]
        return {
          ok: false,
          diagnostics: destination[:diagnostics].map do |diagnostic|
            diagnostic[:category] == "parse_error" ? diagnostic.merge(category: "destination_parse_error") : diagnostic
          end,
          policies: []
        }
      end

      merged = merge_toml_tables(
        load_toml_document(template.dig(:analysis, :normalized_source), resolved_backend),
        load_toml_document(destination.dig(:analysis, :normalized_source), resolved_backend)
      )

      {
        ok: true,
        diagnostics: [],
        output: canonical_toml(merged),
        policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    rescue StandardError => e
      {
        ok: false,
        diagnostics: [{ severity: "error", category: "destination_parse_error", message: e.message }],
        policies: []
      }
    end

    def backend_reference_for(name)
      BACKEND_REFERENCES[name.to_s]
    end
    private_class_method :backend_reference_for

    def resolve_backend(backend)
      backend.to_s.empty? ? (TreeHaver.current_backend_id || "citrus") : backend.to_s
    end
    private_class_method :resolve_backend

    def load_toml_document(source, backend)
      case backend.to_s
      when "citrus"
        normalize_toml_value(TomlRB.parse(source))
      when "parslet"
        normalize_toml_value(TOML.load(source))
      else
        raise ArgumentError, "Unsupported TOML backend #{backend}."
      end
    end
    private_class_method :load_toml_document

    def parse_toml_syntax(source, backend)
      case backend.to_s
      when "citrus"
        TreeHaver.parse_with_citrus(source, grammar_module: TomlRB::Document)
      when "parslet"
        TreeHaver.parse_with_parslet(source, grammar_class: TOML::Parslet)
      else
        { ok: false, diagnostics: [{ severity: "error", category: "unsupported_feature", message: "Unsupported TOML backend #{backend}." }] }
      end
    end
    private_class_method :parse_toml_syntax

    def normalize_toml_value(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), memo|
          memo[key.to_s] = normalize_toml_value(child)
        end
      when Array
        value.map { |child| normalize_toml_value(child) }
      else
        value
      end
    end
    private_class_method :normalize_toml_value

    def validate_toml_node(value, path)
      if scalar?(value)
        { ok: true, value: value }
      elsif value.is_a?(Array)
        if value.all? { |item| scalar?(item) }
          { ok: true, value: value }
        else
          unsupported_feature_result("Unsupported TOML array value at #{display_path(path)}. Only scalar arrays are supported.")
        end
      elsif value.is_a?(Hash)
        value.keys.sort.each_with_object({ ok: true, value: {} }) do |key, memo|
          validated = validate_toml_node(value[key], "#{path}/#{key}")
          return validated unless validated[:ok]

          memo[:value][key] = validated[:value]
        end
      else
        unsupported_feature_result("Unsupported TOML value at #{display_path(path)}. Only tables, scalar values, and scalar arrays are supported.")
      end
    end
    private_class_method :validate_toml_node

    def scalar?(value)
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
    end
    private_class_method :scalar?

    def display_path(path)
      path.empty? ? "/" : path
    end
    private_class_method :display_path

    def render_toml_scalar(value)
      if value.is_a?(String)
        JSON.generate(value)
      elsif value == true || value == false
        value ? "true" : "false"
      else
        value.to_s
      end
    end
    private_class_method :render_toml_scalar

    def render_toml_value(value)
      return "[#{value.map { |item| render_toml_scalar(item) }.join(', ')}]" if value.is_a?(Array)

      render_toml_scalar(value)
    end
    private_class_method :render_toml_value

    def render_toml_table(table, path = [])
      lines = []
      keys = table.keys.sort
      value_keys = keys.select { |key| !table[key].is_a?(Hash) }
      table_keys = keys.select { |key| table[key].is_a?(Hash) }

      lines << "[#{path.join('.')}]" unless path.empty?
      value_keys.each do |key|
        lines << "#{key} = #{render_toml_value(table[key])}"
      end
      table_keys.each do |key|
        lines << "" unless lines.empty?
        lines.concat(render_toml_table(table[key], path + [key]))
      end
      lines
    end
    private_class_method :render_toml_table

    def canonical_toml(table)
      "#{render_toml_table(table).join("\n")}\n"
    end
    private_class_method :canonical_toml

    def collect_toml_owners(table, prefix = "")
      table.keys.sort.flat_map do |key|
        path = "#{prefix}/#{key}"
        value = table[key]
        if value.is_a?(Array)
          [{ path: path, owner_kind: "key_value", match_key: key }] +
            value.each_index.map { |index| { path: "#{path}/#{index}", owner_kind: "array_item" } }
        elsif value.is_a?(Hash)
          [{ path: path, owner_kind: "table", match_key: key }] + collect_toml_owners(value, path)
        else
          [{ path: path, owner_kind: "key_value", match_key: key }]
        end
      end
    end
    private_class_method :collect_toml_owners

    def merge_toml_tables(template, destination)
      (template.keys | destination.keys).sort.each_with_object({}) do |key, merged|
        if !template.key?(key)
          merged[key] = destination[key]
        elsif !destination.key?(key)
          merged[key] = template[key]
        elsif template[key].is_a?(Hash) && destination[key].is_a?(Hash)
          merged[key] = merge_toml_tables(template[key], destination[key])
        else
          merged[key] = destination[key]
        end
      end
    end
    private_class_method :merge_toml_tables

    def parse_error_result(message)
      { ok: false, diagnostics: [{ severity: "error", category: "parse_error", message: message }] }
    end
    private_class_method :parse_error_result

    def unsupported_feature_result(message)
      { ok: false, diagnostics: [{ severity: "error", category: "unsupported_feature", message: message }] }
    end
    private_class_method :unsupported_feature_result
  end
end
