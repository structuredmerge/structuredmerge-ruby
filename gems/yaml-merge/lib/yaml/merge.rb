# frozen_string_literal: true

require 'json'
require 'tree_haver'
require 'ast/merge'
require_relative 'merge/version'

module Yaml
  module Merge
    PACKAGE_NAME = 'yaml-merge'
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: 'array',
      name: 'destination_wins_array'
    }.freeze
    BACKEND_REFERENCE = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    class Error < Ast::Merge::Error; end
    class ParseError < Ast::Merge::ParseError; end
    class TemplateParseError < ParseError; end
    class DestinationParseError < ParseError; end

    autoload :DebugLogger, 'yaml/merge/debug_logger'
    autoload :Emitter, 'yaml/merge/emitter'
    autoload :FileAnalysis, 'yaml/merge/file_analysis'
    autoload :MergeResult, 'yaml/merge/merge_result'
    autoload :NodeWrapper, 'yaml/merge/node_wrapper'
    autoload :SmartMerger, 'yaml/merge/smart_merger'

    module_function

    def register_backend!
      BACKEND_REGISTRY.mutex.synchronize do
        return if BACKEND_REGISTRY.registered && TreeHaver.registered_languages(:yaml).any?

        TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)

        grammar_finder = TreeHaver::GrammarFinder.new(:yaml)
        grammar_finder.register! if grammar_finder.available?

        BACKEND_REGISTRY.registered = true
      end
    end

    def yaml_feature_profile
      {
        family: 'yaml',
        supported_dialects: ['yaml'],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def available_yaml_backends
      yaml_backend_available_for_analysis?(BACKEND_REFERENCE.id) ? [BACKEND_REFERENCE] : []
    end

    def yaml_backend_feature_profile(backend: nil)
      resolved_backend = resolve_backend(backend)
      unless resolved_backend == BACKEND_REFERENCE.id && yaml_backend_available_for_analysis?(resolved_backend)
        return unsupported_feature_result("Unsupported YAML backend #{resolved_backend}.")
      end

      yaml_feature_profile.merge(
        backend: BACKEND_REFERENCE.id,
        backend_ref: BACKEND_REFERENCE.to_h
      )
    end

    def yaml_plan_context(backend: nil)
      profile = yaml_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: yaml_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: false,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_yaml(source, dialect, backend: nil)
      return unsupported_feature_parse_result("Unsupported YAML dialect #{dialect}.") unless dialect == 'yaml'

      requested = backend.to_s.empty? ? nil : backend.to_s
      unless yaml_backend_available_for_analysis?(requested)
        diagnostic_backend = requested || TreeHaver.current_backend_id || 'tree-sitter'
        return unsupported_feature_parse_result("Unsupported YAML backend #{diagnostic_backend}.")
      end

      tree = parse_tree_sitter_source(:yaml, source, backend: requested)
      collect_parse_errors(tree.root_node)

      analyze_yaml_document(yaml_value_from_tree(tree.root_node, source), dialect)
    rescue TreeHaver::Error, StandardError => e
      parse_error_result(e.message)
    end

    def analyze_yaml_document(parsed, dialect)
      return unsupported_feature_parse_result("Unsupported YAML dialect #{dialect}.") unless dialect == 'yaml'
      return parse_error_result('YAML documents must parse to a mapping root.') unless parsed.is_a?(Hash)

      validated = validate_yaml_node(parsed, '')
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
          owners: collect_yaml_owners(validated[:value])
        },
        policies: []
      }
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

    def merge_yaml(template_source, destination_source, dialect, backend: nil)
      requested = backend.to_s.empty? ? nil : backend.to_s
      unless yaml_backend_available_for_analysis?(requested)
        diagnostic_backend = requested || TreeHaver.current_backend_id || 'tree-sitter'
        return unsupported_feature_merge_result("Unsupported YAML backend #{diagnostic_backend}.")
      end

      merge_yaml_with_parser(template_source, destination_source, dialect,
                             backend: requested) do |source, parse_dialect|
        parse_yaml(source, parse_dialect, backend: requested)
      end
    end

    def merge_yaml_with_parser(template_source, destination_source, dialect, backend: nil)
      template = yield(template_source, dialect)
      return { ok: false, diagnostics: template[:diagnostics], policies: [] } unless template[:ok]

      destination = yield(destination_source, dialect)
      unless destination[:ok]
        return {
          ok: false,
          diagnostics: destination[:diagnostics].map do |diagnostic|
            diagnostic[:category] == 'parse_error' ? diagnostic.merge(category: 'destination_parse_error') : diagnostic
          end,
          policies: []
        }
      end

      template_document = template.dig(:analysis, :document)
      destination_document = destination.dig(:analysis, :document)
      unless template_document.is_a?(Hash) && destination_document.is_a?(Hash)
        return parse_error_merge_result('YAML documents must parse to a mapping root.')
      end

      {
        ok: true,
        diagnostics: [],
        output: with_tree_sitter_backend(backend) do
          SmartMerger.new(
            template_source,
            destination_source,
            add_template_only_nodes: true,
            merge_sequences: false
          ).merge_result.to_yaml
        end,
        policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    rescue StandardError => e
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'destination_parse_error', message: e.message }],
        policies: []
      }
    end

    def resolve_backend(backend)
      return backend.to_s unless backend.to_s.empty?

      contextual = TreeHaver.current_backend_id || ENV['TREE_HAVER_BACKEND']
      contextual.to_s.empty? || contextual.to_s == 'auto' ? BACKEND_REFERENCE.id : contextual.to_s
    end
    private_class_method :resolve_backend

    def yaml_backend_available_for_analysis?(backend_id)
      register_backend!

      if backend_id.to_s.empty?
        TreeHaver.parser_for(:yaml, backend_type: :tree_sitter)
      else
        TreeHaver.with_backend(backend_id) { TreeHaver.parser_for(:yaml, backend_type: :tree_sitter) }
      end
      true
    rescue TreeHaver::Error, ArgumentError
      false
    end
    private_class_method :yaml_backend_available_for_analysis?

    def parse_tree_sitter_source(language, source, backend: nil)
      with_tree_sitter_backend(backend) do
        TreeHaver.parser_for(language, backend_type: :tree_sitter).parse(source)
      end
    end
    private_class_method :parse_tree_sitter_source

    def with_tree_sitter_backend(backend, &block)
      if backend.to_s.empty?
        yield
      else
        TreeHaver.with_backend(backend, &block)
      end
    end
    private_class_method :with_tree_sitter_backend

    def collect_parse_errors(node)
      raise TreeHaver::NotAvailable, 'YAML parse returned no root node' unless node
      return unless node.respond_to?(:has_error?) && node.has_error?

      raise TreeHaver::NotAvailable,
            'YAML parse contains syntax errors'
    end
    private_class_method :collect_parse_errors

    def yaml_value_from_tree(node, source)
      named = yaml_named_children(node)
      case node.type
      when 'stream', 'document', 'block_node', 'flow_node'
        return nil if named.empty?

        yaml_value_from_tree(named.first, source)
      when 'block_mapping', 'flow_mapping'
        yaml_mapping_from_node(node, source)
      when 'block_sequence', 'flow_sequence'
        yaml_sequence_from_node(node, source)
      when 'block_sequence_item'
        value_node = named.first
        value_node ? yaml_value_from_tree(value_node, source) : nil
      when 'plain_scalar', 'string_scalar', 'double_quote_scalar', 'single_quote_scalar'
        yaml_scalar_from_text(source[node.start_byte...node.end_byte])
      else
        if named.length == 1
          yaml_value_from_tree(named.first, source)
        else
          yaml_scalar_from_text(source[node.start_byte...node.end_byte])
        end
      end
    end
    private_class_method :yaml_value_from_tree

    def yaml_mapping_from_node(node, source)
      yaml_named_children(node).each_with_object({}) do |child, mapping|
        next unless child.type.end_with?('mapping_pair')

        pair_children = yaml_named_children(child)
        key_node = pair_children.first
        next unless key_node

        value_node = pair_children[1]
        mapping[yaml_value_from_tree(key_node, source).to_s] =
          value_node ? yaml_value_from_tree(value_node, source) : nil
      end
    end
    private_class_method :yaml_mapping_from_node

    def yaml_sequence_from_node(node, source)
      yaml_named_children(node).filter_map do |child|
        next unless %w[block_sequence_item flow_node].include?(child.type)

        yaml_value_from_tree(child, source)
      end
    end
    private_class_method :yaml_sequence_from_node

    def yaml_named_children(node)
      node.children.select do |child|
        (!child.respond_to?(:named?) || child.named?) && child.type != 'comment'
      end
    end
    private_class_method :yaml_named_children

    def yaml_scalar_from_text(text)
      stripped = text.to_s.strip
      return nil if stripped.empty? || stripped == '~' || stripped.casecmp('null').zero?
      return true if stripped.casecmp('true').zero?
      return false if stripped.casecmp('false').zero?
      return stripped.to_i if stripped.match?(/\A[-+]?\d+\z/)
      return stripped.to_f if stripped.match?(/\A[-+]?(?:\d+\.\d*|\d*\.\d+)(?:[eE][-+]?\d+)?\z/)

      if stripped.start_with?('"') && stripped.end_with?('"')
        return unescape_yaml_double_quoted_scalar(stripped[1...-1])
      end
      return stripped[1...-1].gsub("''", "'") if stripped.start_with?("'") && stripped.end_with?("'")

      stripped
    end
    private_class_method :yaml_scalar_from_text

    def unescape_yaml_double_quoted_scalar(value)
      value.gsub(%r{\\(["\\/bfnrt])}) do
        {
          '"' => '"',
          '\\' => '\\',
          '/' => '/',
          'b' => "\b",
          'f' => "\f",
          'n' => "\n",
          'r' => "\r",
          't' => "\t"
        }.fetch(Regexp.last_match(1))
      end
    end
    private_class_method :unescape_yaml_double_quoted_scalar

    def validate_yaml_node(value, path)
      if scalar?(value)
        { ok: true, value: value }
      elsif value.is_a?(Array)
        value.each_with_index.each_with_object({ ok: true, value: [] }) do |(item, index), memo|
          validated = validate_yaml_node(item, "#{path}/#{index}")
          return validated unless validated[:ok]

          memo[:value] << validated[:value]
        end
      elsif value.is_a?(Hash)
        value.keys.each_with_object({ ok: true, value: {} }) do |key, memo|
          validated = validate_yaml_node(value[key], "#{path}/#{key}")
          return validated unless validated[:ok]

          memo[:value][key] = validated[:value]
        end
      else
        unsupported_feature_result("Unsupported YAML value at #{display_path(path)}. Only mappings, scalar values, and sequences are supported.")
      end
    end
    private_class_method :validate_yaml_node

    def scalar?(value)
      value.nil? || value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
    end
    private_class_method :scalar?

    def display_path(path)
      path.empty? ? '/' : path
    end
    private_class_method :display_path

    def render_yaml_scalar(value)
      if value.nil?
        ''
      elsif value.is_a?(String)
        value.match?(/\A[A-Za-z0-9_.-]+\z/) ? value : JSON.generate(value)
      elsif [true, false].include?(value)
        value ? 'true' : 'false'
      else
        value.to_s
      end
    end
    private_class_method :render_yaml_scalar

    def render_yaml_node(key, value, indent)
      prefix = ' ' * indent
      if value.is_a?(Array)
        ["#{prefix}#{key}:"] + render_yaml_sequence(value, indent + 2)
      elsif value.is_a?(Hash)
        ["#{prefix}#{key}:"] + render_yaml_mapping(value, indent + 2)
      elsif value.nil?
        ["#{prefix}#{key}:"]
      else
        ["#{prefix}#{key}: #{render_yaml_scalar(value)}"]
      end
    end
    private_class_method :render_yaml_node

    def render_yaml_mapping(mapping, indent = 0)
      mapping.keys.flat_map do |key|
        render_yaml_node(key, mapping[key], indent)
      end
    end
    private_class_method :render_yaml_mapping

    def render_yaml_sequence(sequence, indent)
      prefix = ' ' * indent
      sequence.flat_map do |item|
        if scalar?(item)
          ["#{prefix}- #{render_yaml_scalar(item)}"]
        elsif item.is_a?(Hash)
          ["#{prefix}-"] + render_yaml_mapping(item, indent + 2)
        elsif item.is_a?(Array)
          ["#{prefix}-"] + render_yaml_sequence(item, indent + 2)
        else
          ["#{prefix}- #{render_yaml_scalar(item)}"]
        end
      end
    end
    private_class_method :render_yaml_sequence

    def canonical_yaml(mapping)
      "#{render_yaml_mapping(mapping).join("\n")}\n"
    end
    private_class_method :canonical_yaml

    def collect_yaml_owners(mapping, prefix = '')
      mapping.keys.sort.flat_map do |key|
        path = "#{prefix}/#{key}"
        value = mapping[key]
        if value.is_a?(Array)
          [{ path: path, owner_kind: 'key_value', match_key: key }] +
            value.each_with_index.flat_map do |item, index|
              item_path = "#{path}/#{index}"
              nested = item.is_a?(Hash) ? collect_yaml_owners(item, item_path) : []
              [{ path: item_path, owner_kind: 'sequence_item' }] + nested
            end
        elsif value.is_a?(Hash)
          [{ path: path, owner_kind: 'mapping', match_key: key }] + collect_yaml_owners(value, path)
        else
          [{ path: path, owner_kind: 'key_value', match_key: key }]
        end
      end
    end
    private_class_method :collect_yaml_owners

    def merge_yaml_mappings(template, destination)
      ordered_merge_keys(template, destination).each_with_object({}) do |key, merged|
        merged[key] = if !template.key?(key)
                        destination[key]
                      elsif !destination.key?(key)
                        template[key]
                      elsif template[key].is_a?(Hash) && destination[key].is_a?(Hash)
                        merge_yaml_mappings(template[key], destination[key])
                      else
                        destination[key]
                      end
      end
    end
    private_class_method :merge_yaml_mappings

    def ordered_merge_keys(template, destination)
      template.keys + destination.keys.reject { |key| template.key?(key) }
    end
    private_class_method :ordered_merge_keys

    def parse_error_result(message)
      { ok: false, diagnostics: [{ severity: 'error', category: 'parse_error', message: message }], policies: [] }
    end
    private_class_method :parse_error_result

    def unsupported_feature_parse_result(message)
      { ok: false, diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: message }],
        policies: [] }
    end
    private_class_method :unsupported_feature_parse_result

    def unsupported_feature_merge_result(message)
      { ok: false, diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: message }],
        policies: [] }
    end
    private_class_method :unsupported_feature_merge_result

    def parse_error_merge_result(message)
      { ok: false, diagnostics: [{ severity: 'error', category: 'parse_error', message: message }], policies: [] }
    end
    private_class_method :parse_error_merge_result

    def unsupported_feature_result(message)
      { ok: false, diagnostic: { severity: 'error', category: 'unsupported_feature', message: message } }
    end
    private_class_method :unsupported_feature_result
  end
end

Yaml::Merge.register_backend!
