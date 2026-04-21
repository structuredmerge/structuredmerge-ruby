# frozen_string_literal: true

require "json"
require "tree_haver"

module Toml
  module Merge
    PACKAGE_NAME = "toml-merge"
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: "array",
      name: "destination_wins_array"
    }.freeze

    class ParseError < StandardError; end

    module_function

    def toml_feature_profile
      {
        family: "toml",
        supported_dialects: ["toml"],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def available_toml_backends
      [TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND]
    end

    def toml_backend_feature_profile(backend: nil)
      resolved_backend = resolve_backend(backend)
      return unsupported_feature_result("Unsupported TOML backend #{resolved_backend}.") unless resolved_backend == TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND.id

      toml_feature_profile.merge(
        backend: TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND.id,
        backend_ref: TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND.to_h
      )
    end

    def toml_plan_context(backend: nil)
      profile = toml_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: toml_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: false,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def analyze_toml_source(source, dialect)
      return unsupported_feature_result("Unsupported TOML dialect #{dialect}.") unless dialect == "toml"

      parsed = parse_toml_document(source)
      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: "toml",
          dialect: "toml",
          normalized_source: canonical_toml(parsed),
          root_kind: "table",
          owners: collect_toml_owners(parsed)
        },
        policies: []
      }
    rescue StandardError => e
      parse_error_result(e.message)
    end

    def parse_toml(source, dialect, backend: nil)
      return unsupported_feature_result("Unsupported TOML dialect #{dialect}.") unless dialect == "toml"

      resolved_backend = resolve_backend(backend)
      return unsupported_feature_result("Unsupported TOML backend #{resolved_backend}.") unless resolved_backend == TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND.id

      syntax_result = TreeHaver.parse_with_language_pack(
        TreeHaver::ParserRequest.new(source: source, language: "toml", dialect: dialect)
      )
      return { ok: false, diagnostics: syntax_result[:diagnostics] } unless syntax_result[:ok]

      analyze_toml_source(source, dialect)
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

    def merge_toml_with_parser(template_source, destination_source, dialect, &parser)
      template = parser.call(template_source, dialect)
      return { ok: false, diagnostics: template[:diagnostics], policies: [] } unless template[:ok]

      destination = parser.call(destination_source, dialect)
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
        parse_toml_document(template.dig(:analysis, :normalized_source)),
        parse_toml_document(destination.dig(:analysis, :normalized_source))
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

    def merge_toml(template_source, destination_source, dialect, backend: nil)
      resolved_backend = resolve_backend(backend)
      return unsupported_feature_result("Unsupported TOML backend #{resolved_backend}.") unless resolved_backend == TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND.id

      merge_toml_with_parser(template_source, destination_source, dialect) do |source, parse_dialect|
        parse_toml(source, parse_dialect, backend: resolved_backend)
      end
    end

    def resolve_backend(backend)
      backend.to_s.empty? ? TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND.id : backend.to_s
    end
    private_class_method :resolve_backend

    def normalize_toml_source(source)
      source.gsub(/\r\n?/, "\n")
    end
    private_class_method :normalize_toml_source

    def strip_toml_comment(line)
      result = +""
      in_string = false
      escaped = false

      line.each_char do |char|
        if in_string
          result << char
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        if char == '"'
          in_string = true
          result << char
          next
        end

        break if char == "#"

        result << char
      end

      raise ParseError, "Unterminated TOML string." if in_string

      result.strip
    end
    private_class_method :strip_toml_comment

    def split_outside_quotes(value, separator)
      parts = []
      current = +""
      in_string = false
      escaped = false
      depth = 0

      value.each_char do |char|
        if in_string
          current << char
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
          current << char
        when "["
          depth += 1
          current << char
        when "]"
          depth -= 1
          current << char
        else
          if char == separator && depth.zero?
            parts << current.strip
            current = +""
          else
            current << char
          end
        end
      end

      raise ParseError, "Unterminated TOML string or array." if in_string || !depth.zero?

      parts << current.strip
      parts
    end
    private_class_method :split_outside_quotes

    def parse_toml_key_path(value)
      trimmed = value.strip
      raise ParseError, "Missing TOML key path." if trimmed.empty?

      parts = trimmed.split(".").map(&:strip)
      raise ParseError, "Unsupported TOML key path #{trimmed}." unless parts.all? { |part| part.match?(/\A[A-Za-z0-9_-]+\z/) }

      parts
    end
    private_class_method :parse_toml_key_path

    def parse_toml_scalar_value(value)
      case value
      when /\A".*"\z/m
        JSON.parse(value)
      when "true"
        true
      when "false"
        false
      when /\A-?\d+\z/
        value.to_i
      when /\A-?\d+\.\d+\z/
        value.to_f
      else
        raise ParseError, "Unsupported TOML value #{value}."
      end
    rescue JSON::ParserError
      raise ParseError, "Invalid TOML string #{value}."
    end
    private_class_method :parse_toml_scalar_value

    def parse_toml_value(value)
      stripped = value.strip
      if stripped.start_with?("[")
        raise ParseError, "Invalid TOML array #{value}." unless stripped.end_with?("]")

        inner = stripped[1..-2].strip
        return [] if inner.empty?

        split_outside_quotes(inner, ",").map { |entry| parse_toml_scalar_value(entry) }
      else
        parse_toml_scalar_value(stripped)
      end
    end
    private_class_method :parse_toml_value

    def ensure_toml_table(root, path)
      current = root
      path.each do |segment|
        existing = current[segment]
        if existing.nil?
          current[segment] = {}
          current = current[segment]
        elsif existing.is_a?(Hash)
          current = existing
        else
          raise ParseError, "TOML table path /#{path.join('/')} conflicts with a value."
        end
      end
      current
    end
    private_class_method :ensure_toml_table

    def assign_toml_value(root, path, value)
      raise ParseError, "Missing TOML assignment path." if path.empty?

      table = ensure_toml_table(root, path[0..-2])
      key = path[-1]
      existing = table[key]
      raise ParseError, "TOML key /#{path.join('/')} conflicts with a table." if existing.is_a?(Hash)

      table[key] = value
    end
    private_class_method :assign_toml_value

    def parse_toml_document(source)
      lines = normalize_toml_source(source).split("\n")
      root = {}
      current_table_path = []

      lines.each do |raw_line|
        line = strip_toml_comment(raw_line)
        next if line.empty?

        if line.start_with?("[")
          raise ParseError, "Invalid TOML table header #{line}." unless line.end_with?("]")

          current_table_path = parse_toml_key_path(line[1..-2])
          ensure_toml_table(root, current_table_path)
          next
        end

        parts = split_outside_quotes(line, "=")
        raise ParseError, "Invalid TOML assignment #{line}." unless parts.length == 2

        key_path = parse_toml_key_path(parts[0])
        value = parse_toml_value(parts[1])
        assign_toml_value(root, current_table_path + key_path, value)
      end

      root
    end
    private_class_method :parse_toml_document

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
      value_keys = keys.reject { |key| table[key].is_a?(Hash) }
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
      { ok: false, diagnostics: [{ severity: "error", category: "unsupported_feature", message: message }], policies: [] }
    end
    private_class_method :unsupported_feature_result
  end
end
