# frozen_string_literal: true

require 'version_gem'
require_relative 'merge/version'

require 'json'
require 'tree_haver'
require 'ast/merge'

module Json
  module Merge
    PACKAGE_NAME = 'json-merge'
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: 'array',
      name: 'destination_wins_array'
    }.freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    class Error < Ast::Merge::Error; end

    class ParseError < Ast::Merge::ParseError
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    class TemplateParseError < ParseError; end
    class DestinationParseError < ParseError; end
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

    class << self
      def register_backend!
        BACKEND_REGISTRY.mutex.synchronize do
          return if BACKEND_REGISTRY.registered

          grammar_finder = TreeHaver::GrammarFinder.new(:json)
          grammar_finder.register! if grammar_finder.available?

          BACKEND_REGISTRY.registered = true
        end
      end
    end

    module_function

    def json_feature_profile
      {
        family: 'json',
        supported_dialects: %w[json jsonc],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def parse_json(source, dialect)
      if detect_trailing_comma(source)
        return parse_failure("Trailing commas are not supported for #{dialect}.")
      end
      if dialect.to_s != 'jsonc' && detect_json_comments(source)
        return parse_failure("Comments are not supported for #{dialect}.")
      end

      register_backend!
      analysis = FileAnalysis.new(source)
      unless analysis.valid?
        return parse_failure(analysis.errors.map { |error| error.respond_to?(:message) ? error.message : error.inspect }.join(', '))
      end

      {
        ok: true,
        diagnostics: [],
        analysis: {
          dialect: dialect,
          allows_comments: dialect == 'jsonc',
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

    def merge_json(template_source, destination_source, dialect)
      template_result = parse_json(template_source, dialect)
      return { ok: false, diagnostics: template_result[:diagnostics] } unless template_result[:ok]

      destination_result = parse_json(destination_source, dialect)
      if destination_result[:ok]
        return {
          ok: true,
          diagnostics: [],
          output: merge_json_sources(template_source, destination_source),
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

    def merge_json_sources(template_source, destination_source)
      SmartMerger.new(
        template_source,
        destination_source,
        add_template_only_nodes: true,
        merge_arrays: false,
        preserve_atomic_formatting: true
      ).merge_result.to_json
    end
    private_class_method :merge_json_sources

    def json_value_for_source(source, dialect: 'json')
      if detect_trailing_comma(source)
        raise ParseError, "Trailing commas are not supported for #{dialect}."
      end
      if dialect.to_s != 'jsonc' && detect_json_comments(source)
        raise ParseError, "Comments are not supported for #{dialect}."
      end

      register_backend!
      analysis = FileAnalysis.new(source)
      unless analysis.valid?
        message = analysis.errors.map { |error| error.respond_to?(:message) ? error.message : error.inspect }.join(', ')
        raise ParseError, message
      end

      json_value_for_node(analysis.root_node)
    end

    def json_value_for_node(node)
      case node.type.to_s
      when 'document'
        child = node.semantic_children.first
        child ? json_value_for_node(NodeWrapper.new(child, lines: node.lines, source: node.source)) : nil
      when 'object'
        node.pairs.each_with_object({}) do |pair, object|
          key = pair.key_name
          next unless key

          object[key] = json_value_for_node(pair.value_node)
        end
      when 'array'
        node.elements.map { |element| json_value_for_node(element) }
      when 'string'
        decode_json_string_literal(node.text)
      when 'number'
        parse_json_number(node.text)
      when 'true'
        true
      when 'false'
        false
      when 'null'
        nil
      else
        nil
      end
    end

    def decode_json_string_literal(text)
      literal = text.to_s
      literal = literal[1...-1] if literal.start_with?('"') && literal.end_with?('"')
      literal.gsub(/\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4})/) do |escape|
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

    def parse_error(message)
      { severity: 'error', category: 'parse_error', message: message }
    end
    private_class_method :parse_error

    def unsupported_feature(message)
      { severity: 'error', category: 'unsupported_feature', message: message }
    end
    private_class_method :unsupported_feature

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

Json::Merge::Version.class_eval do
  extend VersionGem::Basic
end
