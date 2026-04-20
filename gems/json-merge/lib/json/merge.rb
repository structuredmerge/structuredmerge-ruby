# frozen_string_literal: true

require "json"
require "tree_haver"

module Json
  module Merge
    PACKAGE_NAME = "json-merge"
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: "array",
      name: "destination_wins_array"
    }.freeze
    TRAILING_COMMA_FALLBACK_POLICY = {
      surface: "fallback",
      name: "trailing_comma_destination_fallback"
    }.freeze

    module_function

    def json_feature_profile
      {
        family: "json",
        supported_dialects: %w[json jsonc],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY, TRAILING_COMMA_FALLBACK_POLICY]
      }
    end

    def json_parse_request(source, dialect)
      TreeHaver::ParserRequest.new(source: source, language: "json", dialect: dialect)
    end

    def parse_json_with_language_pack(source, dialect)
      return unsupported_jsonc_language_pack_result if dialect != "json"

      backend_result = TreeHaver.parse_with_language_pack(json_parse_request(source, dialect))
      return { ok: false, diagnostics: backend_result[:diagnostics] } unless backend_result[:ok]

      parse_json(source, dialect)
    end

    def parse_json(source, dialect)
      normalized_source = dialect == "jsonc" ? strip_json_comments(source) : source
      allows_comments = dialect == "jsonc"
      return parse_failure("Trailing commas are not supported for #{dialect}.") if detect_trailing_comma(normalized_source)

      parsed = JSON.parse(normalized_source)
      canonical = JSON.generate(parsed)
      analysis = {
        kind: "json",
        dialect: dialect,
        allows_comments: allows_comments,
        normalized_source: canonical,
        root_kind: json_root_kind(parsed),
        owners: collect_json_owners(parsed)
      }
      {
        ok: true,
        diagnostics: [],
        analysis: analysis
      }
    rescue JSON::ParserError => e
      parse_failure(e.message)
    end

    def match_json_owners(template, destination)
      destination_paths = destination[:owners].to_h { |owner| [owner[:path], true] }
      template_paths = template[:owners].to_h { |owner| [owner[:path], true] }

      {
        matched: template[:owners].filter_map do |owner|
          next unless destination_paths[owner[:path]]

          { template_path: owner[:path], destination_path: owner[:path] }
        end,
        unmatched_template: template[:owners].map { |owner| owner[:path] }.reject { |path| destination_paths[path] },
        unmatched_destination: destination[:owners].map { |owner| owner[:path] }.reject { |path| template_paths[path] }
      }
    end

    def merge_json(template_source, destination_source, dialect)
      template_result = parse_json(template_source, dialect)
      return { ok: false, diagnostics: template_result[:diagnostics] } unless template_result[:ok]

      destination_result = parse_json(destination_source, dialect)
      if destination_result[:ok]
        output = JSON.generate(
          merge_json_values(
            JSON.parse(template_result.dig(:analysis, :normalized_source)),
            JSON.parse(destination_result.dig(:analysis, :normalized_source))
          )
        )
        return {
          ok: true,
          diagnostics: [],
          output: output,
          policies: [DESTINATION_WINS_ARRAY_POLICY]
        }
      end

      fallback_source = try_destination_trailing_comma_fallback(destination_source)
      if fallback_source
        retried = parse_json(fallback_source, dialect)
        if retried[:ok]
          output = JSON.generate(
            merge_json_values(
              JSON.parse(template_result.dig(:analysis, :normalized_source)),
              JSON.parse(retried.dig(:analysis, :normalized_source))
            )
          )
          return {
            ok: true,
            diagnostics: [
              fallback_applied("stripped trailing commas from destination before retrying json merge.")
            ],
            output: output,
            policies: [DESTINATION_WINS_ARRAY_POLICY, TRAILING_COMMA_FALLBACK_POLICY]
          }
        end
      end

      {
        ok: false,
        diagnostics: destination_result[:diagnostics].map do |diagnostic|
          diagnostic[:category] == "parse_error" ? diagnostic.merge(category: "destination_parse_error") : diagnostic
        end
      }
    end

    def parse_failure(message)
      {
        ok: false,
        diagnostics: [parse_error(message)]
      }
    end
    private_class_method :parse_failure

    def unsupported_jsonc_language_pack_result
      {
        ok: false,
        diagnostics: [
          unsupported_feature("tree-sitter-language-pack json parsing currently supports only the json dialect.")
        ]
      }
    end
    private_class_method :unsupported_jsonc_language_pack_result

    def parse_error(message)
      { severity: "error", category: "parse_error", message: message }
    end
    private_class_method :parse_error

    def unsupported_feature(message)
      { severity: "error", category: "unsupported_feature", message: message }
    end
    private_class_method :unsupported_feature

    def fallback_applied(message)
      { severity: "warning", category: "fallback_applied", message: message }
    end
    private_class_method :fallback_applied

    def json_root_kind(value)
      return "object" if value.is_a?(Hash)
      return "array" if value.is_a?(Array)

      "scalar"
    end
    private_class_method :json_root_kind

    def collect_json_owners(value, path = "")
      if value.is_a?(Hash)
        value.keys.sort.flat_map do |key|
          next_path = "#{path}/#{key}"
          [{ path: next_path, owner_kind: "member", match_key: key }] + collect_json_owners(value[key], next_path)
        end
      elsif value.is_a?(Array)
        value.each_with_index.flat_map do |item, index|
          next_path = "#{path}/#{index}"
          [{ path: next_path, owner_kind: "element" }] + collect_json_owners(item, next_path)
        end
      else
        []
      end
    end
    private_class_method :collect_json_owners

    def merge_json_values(template, destination)
      if template.is_a?(Hash) && destination.is_a?(Hash)
        (template.keys | destination.keys).sort.each_with_object({}) do |key, merged|
          if !template.key?(key)
            merged[key] = destination[key]
          elsif !destination.key?(key)
            merged[key] = template[key]
          else
            merged[key] = merge_json_values(template[key], destination[key])
          end
        end
      else
        destination
      end
    end
    private_class_method :merge_json_values

    def detect_trailing_comma(source)
      state = scanner_state
      source.each_char.with_index do |char, index|
        next_char = source[index + 1]
        advance_scanner_state(state, char, next_char)
        next if state[:in_line_comment] || state[:in_block_comment] || state[:in_string]

        if char == ","
          lookahead = source[(index + 1)..]
          next unless lookahead

          trimmed = lookahead.lstrip
          return true if trimmed.start_with?("]", "}")
        end
      end
      false
    end
    private_class_method :detect_trailing_comma

    def strip_json_comments(source)
      result = +""
      state = scanner_state
      index = 0
      while index < source.length
        char = source[index]
        next_char = source[index + 1]

        if state[:in_line_comment]
          if char == "\n"
            state[:in_line_comment] = false
            result << "\n"
          end
          index += 1
          next
        end

        if state[:in_block_comment]
          if char == "*" && next_char == "/"
            state[:in_block_comment] = false
            index += 2
            next
          end
          index += 1
          next
        end

        if state[:in_string]
          result << char
          if state[:escaped]
            state[:escaped] = false
          elsif char == "\\"
            state[:escaped] = true
          elsif char == "\""
            state[:in_string] = false
          end
          index += 1
          next
        end

        if char == "\""
          state[:in_string] = true
          result << char
          index += 1
          next
        end

        if char == "/" && next_char == "/"
          state[:in_line_comment] = true
          index += 2
          next
        end

        if char == "/" && next_char == "*"
          state[:in_block_comment] = true
          index += 2
          next
        end

        result << char
        index += 1
      end
      result
    end
    private_class_method :strip_json_comments

    def try_destination_trailing_comma_fallback(source)
      stripped = strip_trailing_commas(source)
      return nil if stripped == source

      stripped
    end
    private_class_method :try_destination_trailing_comma_fallback

    def strip_trailing_commas(source)
      result = +""
      state = scanner_state
      source.each_char.with_index do |char, index|
        next_char = source[index + 1]

        if state[:in_line_comment]
          result << char
          state[:in_line_comment] = false if char == "\n"
          next
        end

        if state[:in_block_comment]
          result << char
          if char == "*" && next_char == "/"
            result << next_char
            state[:in_block_comment] = false
          end
          next
        end

        if state[:in_string]
          result << char
          if state[:escaped]
            state[:escaped] = false
          elsif char == "\\"
            state[:escaped] = true
          elsif char == "\""
            state[:in_string] = false
          end
          next
        end

        if char == "\""
          state[:in_string] = true
          result << char
          next
        end

        if char == "/" && next_char == "/"
          state[:in_line_comment] = true
          result << char
          next
        end

        if char == "/" && next_char == "*"
          state[:in_block_comment] = true
          result << char
          next
        end

        if char == ","
          lookahead = source[(index + 1)..]
          trimmed = lookahead&.lstrip
          next if trimmed&.start_with?("]", "}")
        end

        result << char
      end
      result
    end
    private_class_method :strip_trailing_commas

    def scanner_state
      {
        in_string: false,
        in_line_comment: false,
        in_block_comment: false,
        escaped: false
      }
    end
    private_class_method :scanner_state

    def advance_scanner_state(state, char, next_char)
      if state[:in_line_comment]
        state[:in_line_comment] = false if char == "\n"
        return
      end

      if state[:in_block_comment]
        state[:in_block_comment] = false if char == "*" && next_char == "/"
        return
      end

      if state[:in_string]
        if state[:escaped]
          state[:escaped] = false
        elsif char == "\\"
          state[:escaped] = true
        elsif char == "\""
          state[:in_string] = false
        end
        return
      end

      if char == "\""
        state[:in_string] = true
      elsif char == "/" && next_char == "/"
        state[:in_line_comment] = true
      elsif char == "/" && next_char == "*"
        state[:in_block_comment] = true
      end
    end
    private_class_method :advance_scanner_state
  end
end
