# frozen_string_literal: true

require 'json'
require 'tree_haver'
require 'ast/merge'
require_relative 'merge/version'

module Json
  module Merge
    PACKAGE_NAME = 'json-merge'
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: 'array',
      name: 'destination_wins_array'
    }.freeze
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    class Error < Ast::Merge::Error; end

    class ParseError < Ast::Merge::ParseError
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    class TemplateParseError < ParseError; end
    class DestinationParseError < ParseError; end
    class JsoncDialectError < ParseError; end
    class CorruptionDetectedError < Error; end

    autoload :CommentTracker, 'json/merge/comment_tracker'
    autoload :DebugLogger, 'json/merge/debug_logger'
    autoload :Emitter, 'json/merge/emitter'
    autoload :FileAnalysis, 'json/merge/file_analysis'
    autoload :FreezeNode, 'json/merge/freeze_node'
    autoload :MergeResult, 'json/merge/merge_result'
    autoload :NodeWrapper, 'json/merge/node_wrapper'
    autoload :ConflictResolver, 'json/merge/conflict_resolver'
    autoload :SmartMerger, 'json/merge/smart_merger'
    autoload :ObjectMatchRefiner, 'json/merge/object_match_refiner'
    autoload :Provider, 'json/merge/provider'
    autoload :ThreeWayDecision, 'json/merge/three_way_decision'

    class << self
      def register_backend!
        BACKEND_REGISTRY.mutex.synchronize do
          return if BACKEND_REGISTRY.registered

          TreeHaver::BackendRegistry.register(TREE_SITTER_BACKEND)

          grammar_finder = TreeHaver::GrammarFinder.new(:json)
          grammar_finder.register! if grammar_finder.available?

          json5_grammar_finder = TreeHaver::GrammarFinder.new(:json5)
          json5_grammar_finder.register! if json5_grammar_finder.available?

          BACKEND_REGISTRY.registered = true
        end
      end
    end

    module_function

    def json_feature_profile
      {
        family: 'json',
        supported_dialects: %w[json jsonc json5],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def merge_provider
      @merge_provider ||= Provider.new
    end

    def register_provider!(replace: false)
      Ast::Merge.register_provider(merge_provider, replace: replace)
    end

    def available_json_backends
      json_backend_available_for_analysis?(TREE_SITTER_BACKEND.id) ? [TREE_SITTER_BACKEND] : []
    end

    def json_backend_feature_profile(backend: nil)
      requested = requested_json_backend_id(backend)
      unless available_json_backends.any? { |backend_ref| backend_ref.id == requested }
        return unsupported_feature_result("Unsupported JSON backend #{requested}.")
      end

      json_feature_profile.merge(
        backend: requested,
        backend_ref: TREE_SITTER_BACKEND.to_h
      )
    end

    def json_plan_context(backend: nil)
      profile = json_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: json_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_json(source, dialect, backend: nil)
      dialect = normalize_json_dialect(dialect)
      requested = requested_json_backend_id(backend)
      unless json_backend_available_for_analysis?(requested, dialect: dialect)
        return unsupported_feature_result("Unsupported JSON backend #{requested}.")
      end

      if dialect == :json && detect_trailing_comma(source)
        return parse_failure("Trailing commas are not supported for #{dialect}.")
      end
      if dialect == :json && detect_json_comments(source)
        return parse_failure("Comments are not supported for #{dialect}.")
      end

      register_backend!
      analysis = TreeHaver.with_backend(requested) { FileAnalysis.new(source, dialect: dialect) }
      unless analysis.valid?
        return parse_failure(analysis.errors.map do |error|
          error.respond_to?(:message) ? error.message : error.inspect
        end.join(', '))
      end

      {
        ok: true,
        diagnostics: [],
        analysis: {
          dialect: dialect.to_s,
          allows_comments: %i[jsonc json5].include?(dialect),
          root_kind: json_analysis_root_kind(analysis),
          owners: collect_file_analysis_owners(analysis)
        },
        policies: []
      }
    rescue TreeHaver::Error, StandardError => e
      parse_failure(e.message)
    end

    def match_json_owners(template, destination)
      Ast::Merge::OwnerSelection.match_by_path(template, destination)
    end

    def merge_json(template_source, destination_source, dialect, backend: nil)
      dialect = normalize_json_dialect(dialect)
      requested = requested_json_backend_id(backend)
      unless json_backend_available_for_analysis?(requested, dialect: dialect)
        return unsupported_feature_result("Unsupported JSON backend #{requested}.")
      end

      template_result = parse_json(template_source, dialect, backend: requested)
      return { ok: false, diagnostics: template_result[:diagnostics] } unless template_result[:ok]

      destination_result = parse_json(destination_source, dialect, backend: requested)
      if destination_result[:ok]
        return {
          ok: true,
          diagnostics: [],
          output: TreeHaver.with_backend(requested) do
            merge_json_sources(template_source, destination_source, dialect: dialect)
          end,
          policies: [DESTINATION_WINS_ARRAY_POLICY]
        }
      end

      {
        ok: false,
        diagnostics: destination_result[:diagnostics].map do |diagnostic|
          diagnostic[:category] == 'parse_error' ? diagnostic.merge(category: 'destination_parse_error') : diagnostic
        end
      }
    end

    def merge_json_sources(template_source, destination_source, dialect:)
      SmartMerger.new(
        template_source,
        destination_source,
        dialect: dialect,
        add_template_only_nodes: true,
        merge_arrays: false,
        preserve_atomic_formatting: true
      ).merge_result.to_json
    end
    private_class_method :merge_json_sources

    def json_value_for_source(source, dialect: 'json', backend: nil)
      dialect = normalize_json_dialect(dialect)
      requested = requested_json_backend_id(backend)
      unless json_backend_available_for_analysis?(requested, dialect: dialect)
        raise ParseError, "Unsupported JSON backend #{requested}."
      end

      if dialect == :json && detect_trailing_comma(source)
        raise ParseError,
              "Trailing commas are not supported for #{dialect}."
      end
      raise ParseError, "Comments are not supported for #{dialect}." if dialect == :json && detect_json_comments(source)

      register_backend!
      analysis = TreeHaver.with_backend(requested) { FileAnalysis.new(source, dialect: dialect) }
      unless analysis.valid?
        message = analysis.errors.map { |error| error.respond_to?(:message) ? error.message : error.inspect }.join(', ')
        raise ParseError, message
      end

      json_value_for_node(analysis.root_node, dialect: dialect)
    end

    def json_value_for_node(node, dialect: :json)
      case node.type.to_s
      when 'document'
        child = node.semantic_children.first
        if child
          json_value_for_node(NodeWrapper.new(child, lines: node.lines, source: node.source, dialect: dialect),
                              dialect: dialect)
        end
      when 'object'
        node.pairs.each_with_object({}) do |pair, object|
          key = pair.key_name
          next unless key

          object[key] = json_value_for_node(pair.value_node, dialect: dialect)
        end
      when 'array'
        node.elements.map { |element| json_value_for_node(element, dialect: dialect) }
      when 'string'
        decode_string_literal(node.text, dialect: dialect)
      when 'number'
        parse_number_literal(node.text, dialect: dialect)
      when 'true'
        true
      when 'false'
        false
      when 'null'
        nil
      end
    end

    def object_key_for_literal(text, dialect: :json)
      literal = text.to_s
      return literal if dialect == :json5 && !%w[' "].include?(literal[0])

      decode_string_literal(literal, dialect: dialect)
    end

    def decode_string_literal(text, dialect: :json)
      return decode_json_string_literal(text) unless dialect == :json5

      decode_json5_string_literal(text)
    end

    def decode_json_string_literal(text)
      literal = text.to_s
      literal = literal[1...-1] if literal.start_with?('"') && literal.end_with?('"')
      literal.gsub(%r{\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4})}) do |escape|
        case escape
        when '\\"' then '"'
        when '\\\\' then '\\'
        when '\\/' then '/'
        when '\\b' then "\b"
        when '\\f' then "\f"
        when '\\n' then "\n"
        when '\\r' then "\r"
        when '\\t' then "\t"
        else
          [escape[2..].to_i(16)].pack('U')
        end
      end
    end
    private_class_method :decode_json_string_literal

    def decode_json5_string_literal(text)
      literal = text.to_s
      return literal unless literal.length >= 2 && %w[' "].include?(literal[0]) && literal[-1] == literal[0]

      body = literal[1...-1]
      result = +''
      index = 0
      while index < body.length
        char = body[index]
        unless char == '\\'
          result << char
          index += 1
          next
        end

        index += 1
        escape = body[index]
        break unless escape

        case escape
        when "\n"
          # JSON5 line continuations contribute no character.
        when "\r"
          index += 1 if body[index + 1] == "\n"
        when 'b' then result << "\b"
        when 'f' then result << "\f"
        when 'n' then result << "\n"
        when 'r' then result << "\r"
        when 't' then result << "\t"
        when 'v' then result << "\v"
        when '0' then result << "\0"
        when 'x'
          hex = body[(index + 1), 2]
          result << hex.to_i(16).chr(Encoding::UTF_8) if hex&.match?(/\A[0-9a-fA-F]{2}\z/)
          index += 2
        when 'u'
          hex = body[(index + 1), 4]
          result << [hex.to_i(16)].pack('U') if hex&.match?(/\A[0-9a-fA-F]{4}\z/)
          index += 4
        else
          result << escape
        end
        index += 1
      end
      result
    end
    private_class_method :decode_json5_string_literal

    def parse_number_literal(text, dialect: :json)
      return parse_json_number(text) unless dialect == :json5

      literal = text.to_s.delete('_')
      return Float::INFINITY if ['Infinity', '+Infinity'].include?(literal)
      return -Float::INFINITY if literal == '-Infinity'
      return Float::NAN if %w[NaN +NaN -NaN].include?(literal)

      Integer(literal, 0)
    rescue ArgumentError
      Float(literal)
    end

    def parse_json_number(text)
      number = text.to_s
      return number.to_f if number.match?(/[.eE]/)

      number.to_i
    end
    private_class_method :parse_json_number

    def parse_failure(message)
      {
        ok: false,
        diagnostics: [parse_error(message)]
      }
    end
    private_class_method :parse_failure

    def requested_json_backend_id(backend)
      return backend.to_s unless backend.to_s.empty?

      current = TreeHaver.current_backend_id
      return current if json_backend_available_for_analysis?(current)

      available_json_backends.find do |backend_ref|
        json_backend_available_for_analysis?(backend_ref.id)
      end&.id || TREE_SITTER_BACKEND.id
    end
    private_class_method :requested_json_backend_id

    def json_backend_available_for_analysis?(backend_id, dialect: :json)
      register_backend!
      languages = %i[jsonc json5].include?(dialect) ? [:json5] : [:json]
      case backend_id.to_s
      when TREE_SITTER_BACKEND.id
        languages.all? do |language|
          registrations = TreeHaver.registered_languages(language)
          registrations.key?(:tree_sitter) || registrations.key?(:tslp)
        end
      else
        false
      end
    end
    private_class_method :json_backend_available_for_analysis?

    def normalize_json_dialect(dialect)
      normalized = dialect.to_s.downcase
      return normalized.to_sym if %w[json jsonc json5].include?(normalized)

      raise ArgumentError, "Unsupported JSON dialect #{dialect.inspect}. Expected json, jsonc, or json5."
    end
    private_class_method :normalize_json_dialect

    def parse_error(message)
      { severity: 'error', category: 'parse_error', message: message }
    end
    private_class_method :parse_error

    def unsupported_feature(message)
      { severity: 'error', category: 'unsupported_feature', message: message }
    end
    private_class_method :unsupported_feature

    def unsupported_feature_result(message)
      { ok: false, diagnostics: [unsupported_feature(message)], policies: [] }
    end
    private_class_method :unsupported_feature_result

    def json_analysis_root_kind(analysis)
      root = analysis.root_object || analysis.root_node
      return 'object' if root&.object?
      return 'array' if root&.array?

      'scalar'
    end
    private_class_method :json_analysis_root_kind

    def collect_file_analysis_owners(analysis)
      root = analysis.root_object || analysis.root_node
      return [] unless root

      collect_json_node_owners(root, '')
        .sort_by { |owner| owner.fetch(:path) }
    end
    private_class_method :collect_file_analysis_owners

    def collect_json_node_owners(node, path)
      if node.object?
        node.pairs.flat_map do |pair|
          key = pair.key_name
          next [] unless key

          owner_path = "#{path}/#{key}"
          value = pair.value_node
          [{ path: owner_path, owner_kind: 'member', match_key: key }] +
            (value ? collect_json_node_owners(value, owner_path) : [])
        end
      elsif node.array?
        node.elements.each_with_index.flat_map do |element, index|
          owner_path = "#{path}/#{index}"
          [{ path: owner_path, owner_kind: 'element' }] +
            collect_json_node_owners(element, owner_path)
        end
      else
        []
      end
    end
    private_class_method :collect_json_node_owners

    def detect_trailing_comma(source)
      state = scanner_state
      source.each_char.with_index do |char, index|
        next_char = source[index + 1]
        advance_scanner_state(state, char, next_char)
        next if state[:in_line_comment] || state[:in_block_comment] || state[:in_string]

        if char == ','
          lookahead = source[(index + 1)..]
          next unless lookahead

          trimmed = lookahead.lstrip
          return true if trimmed.start_with?(']', '}')
        end
      end
      false
    end
    private_class_method :detect_trailing_comma

    def detect_json_comments(source)
      state = scanner_state
      source.each_char.with_index do |char, index|
        next_char = source[index + 1]
        return true if !state[:in_string] && char == '/' && %w[/ *].include?(next_char)

        advance_scanner_state(state, char, next_char)
      end
      false
    end
    private_class_method :detect_json_comments

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
        state[:in_block_comment] = false if char == '*' && next_char == '/'
        return
      end

      if state[:in_string]
        if state[:escaped]
          state[:escaped] = false
        elsif char == '\\'
          state[:escaped] = true
        elsif char == '"'
          state[:in_string] = false
        end
        return
      end

      if char == '"'
        state[:in_string] = true
      elsif char == '/' && next_char == '/'
        state[:in_line_comment] = true
      elsif char == '/' && next_char == '*'
        state[:in_block_comment] = true
      end
    end
    private_class_method :advance_scanner_state
  end
end

Json::Merge.register_backend!

if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :json_merge,
    require_path: 'json/merge',
    merger_class: 'Json::Merge::SmartMerger',
    test_source: '{"key": "value"}',
    category: :data
  )
end
