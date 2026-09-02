# frozen_string_literal: true

require 'json'
require 'tree_haver'
require 'ast/merge'
require_relative 'merge/version'

module Yaml
  # The YAML language layer owns this parser-neutral contract. Keep this
  # facade co-located so psych-merge can depend on it without a reverse edge.
  # rubocop:disable Metrics/ModuleLength -- the public YAML facade owns this structural boundary
  module Merge
    PACKAGE_NAME = 'yaml-merge'
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: 'array',
      name: 'destination_wins_array'
    }.freeze
    BACKEND_REFERENCE = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)
    YAML_TREE_NODE_HANDLERS = {
      child: :yaml_value_from_tree_child_node,
      mapping: :yaml_mapping_from_tree_node,
      sequence: :yaml_sequence_from_tree_node,
      scalar: :yaml_scalar_from_tree_node
    }.freeze
    YAML_DOUBLE_QUOTE_ESCAPES = {
      '"' => '"',
      '\\' => '\\',
      '/' => '/',
      'b' => "\b",
      'f' => "\f",
      'n' => "\n",
      'r' => "\r",
      't' => "\t"
    }.freeze

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
    autoload :SourcePreservingProvider, 'yaml/merge/source_preserving_provider'
    autoload :Provider, 'yaml/merge/provider'

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

      parse_yaml_tree(source, dialect, requested)
    rescue TreeHaver::Error, StandardError => e
      parse_error_result(e.message)
    end

    def parse_yaml_tree(source, dialect, backend)
      tree = parse_tree_sitter_source(:yaml, source, backend: backend)
      collect_parse_errors(tree.root_node)
      analyze_yaml_document(yaml_value_from_tree(tree.root_node, source), dialect)
    end
    private_class_method :parse_yaml_tree

    def analyze_yaml_document(parsed, dialect)
      return unsupported_feature_parse_result("Unsupported YAML dialect #{dialect}.") unless dialect == 'yaml'
      return parse_error_result('YAML documents must parse to a mapping root.') unless parsed.is_a?(Hash)

      validated = validate_yaml_node(parsed, '')
      return invalid_yaml_analysis(validated) unless validated[:ok]

      yaml_analysis_result(validated[:value])
    end

    def yaml_analysis_result(value)
      {
        ok: true,
        diagnostics: [],
        analysis: yaml_document_analysis(value),
        policies: []
      }
    end
    private_class_method :yaml_analysis_result

    def yaml_document_analysis(value)
      {
        kind: 'yaml',
        dialect: 'yaml',
        normalized_source: canonical_yaml(value),
        document: value,
        root_kind: 'mapping',
        owners: collect_yaml_owners(value)
      }
    end
    private_class_method :yaml_document_analysis

    def invalid_yaml_analysis(validated)
      { ok: false, diagnostics: [validated[:diagnostic]], policies: [] }
    end
    private_class_method :invalid_yaml_analysis

    def match_yaml_owners(template, destination)
      Ast::Merge::OwnerSelection.match_by_path(template, destination)
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
      return parser_failure_result(template, :template) unless template[:ok]

      destination = yield(destination_source, dialect)
      return parser_failure_result(destination, :destination) unless destination[:ok]

      return parse_error_merge_result('YAML documents must parse to a mapping root.') unless
        yaml_parse_results_valid?(template, destination)

      yaml_merge_result(template_source, destination_source, backend)
    rescue StandardError => e
      parser_exception_result(e)
    end

    def parser_exception_result(error)
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'destination_parse_error', message: error.message }],
        policies: []
      }
    end
    private_class_method :parser_exception_result

    def parser_failure_result(result, role)
      diagnostics = result[:diagnostics]
      if role == :destination
        diagnostics = diagnostics.map do |diagnostic|
          diagnostic[:category] == 'parse_error' ? diagnostic.merge(category: 'destination_parse_error') : diagnostic
        end
      end

      { ok: false, diagnostics: diagnostics, policies: [] }
    end
    private_class_method :parser_failure_result

    def yaml_documents?(template_document, destination_document)
      template_document.is_a?(Hash) && destination_document.is_a?(Hash)
    end
    private_class_method :yaml_documents?

    def yaml_parse_results_valid?(template, destination)
      yaml_documents?(template.dig(:analysis, :document), destination.dig(:analysis, :document))
    end
    private_class_method :yaml_parse_results_valid?

    def yaml_merge_result(template_source, destination_source, backend)
      {
        ok: true,
        diagnostics: [],
        output: yaml_merge_output(template_source, destination_source, backend),
        policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end
    private_class_method :yaml_merge_result

    def yaml_merge_output(template_source, destination_source, backend)
      with_tree_sitter_backend(backend) do
        SmartMerger.new(
          template_source,
          destination_source,
          add_template_only_nodes: true,
          merge_sequences: false
        ).merge_result.to_yaml
      end
    end
    private_class_method :yaml_merge_output

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
      handler = YAML_TREE_NODE_HANDLERS[yaml_tree_node_kind(node.type)]
      return send(handler, node, named, source) if handler

      yaml_value_from_unknown_tree(node, named, source)
    end
    private_class_method :yaml_value_from_tree

    def yaml_tree_node_kind(type)
      case type
      when 'stream', 'document', 'block_node', 'flow_node', 'block_sequence_item' then :child
      when 'block_mapping', 'flow_mapping' then :mapping
      when 'block_sequence', 'flow_sequence' then :sequence
      when 'plain_scalar', 'string_scalar', 'double_quote_scalar', 'single_quote_scalar' then :scalar
      end
    end
    private_class_method :yaml_tree_node_kind

    def yaml_value_from_tree_child(named, source)
      value_node = named.first
      value_node ? yaml_value_from_tree(value_node, source) : nil
    end
    private_class_method :yaml_value_from_tree_child

    def yaml_value_from_tree_child_node(_node, named, source)
      yaml_value_from_tree_child(named, source)
    end
    private_class_method :yaml_value_from_tree_child_node

    def yaml_mapping_from_tree_node(node, _named, source)
      yaml_mapping_from_node(node, source)
    end
    private_class_method :yaml_mapping_from_tree_node

    def yaml_sequence_from_tree_node(node, _named, source)
      yaml_sequence_from_node(node, source)
    end
    private_class_method :yaml_sequence_from_tree_node

    def yaml_scalar_from_tree_node(node, _named, source)
      yaml_scalar_from_tree(node, source)
    end
    private_class_method :yaml_scalar_from_tree_node

    def yaml_scalar_from_tree(node, source)
      yaml_scalar_from_text(source[node.start_byte...node.end_byte])
    end
    private_class_method :yaml_scalar_from_tree

    def yaml_value_from_unknown_tree(node, named, source)
      return yaml_value_from_tree(named.first, source) if named.length == 1

      yaml_scalar_from_text(source[node.start_byte...node.end_byte])
    end
    private_class_method :yaml_value_from_unknown_tree

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
      case stripped.downcase
      when '', '~', 'null' then nil
      when 'true' then true
      when 'false' then false
      else yaml_numeric_or_quoted_scalar(stripped)
      end
    end
    private_class_method :yaml_scalar_from_text

    def yaml_numeric_or_quoted_scalar(stripped)
      return stripped.to_i if stripped.match?(/\A[-+]?\d+\z/)
      return stripped.to_f if stripped.match?(/\A[-+]?(?:\d+\.\d*|\d*\.\d+)(?:[eE][-+]?\d+)?\z/)
      if stripped.start_with?('"') && stripped.end_with?('"')
        return unescape_yaml_double_quoted_scalar(stripped[1...-1])
      end
      return stripped[1...-1].gsub("''", "'") if stripped.start_with?("'") && stripped.end_with?("'")

      stripped
    end
    private_class_method :yaml_numeric_or_quoted_scalar

    def unescape_yaml_double_quoted_scalar(value)
      value.gsub(%r{\\(["\\/bfnrt])}) { YAML_DOUBLE_QUOTE_ESCAPES.fetch(Regexp.last_match(1)) }
    end
    private_class_method :unescape_yaml_double_quoted_scalar

    def validate_yaml_node(value, path)
      return { ok: true, value: value } if scalar?(value)
      return validate_yaml_collection(value, path) if value.is_a?(Array) || value.is_a?(Hash)

      unsupported_feature_result(
        "Unsupported YAML value at #{display_path(path)}. " \
        'Only mappings, scalar values, and sequences are supported.'
      )
    end
    private_class_method :validate_yaml_node

    def validate_yaml_collection(value, path)
      value.is_a?(Array) ? validate_yaml_array(value, path) : validate_yaml_hash(value, path)
    end
    private_class_method :validate_yaml_collection

    def validate_yaml_array(value, path)
      value.each_with_index.each_with_object({ ok: true, value: [] }) do |(item, index), memo|
        validated = validate_yaml_node(item, "#{path}/#{index}")
        return validated unless validated[:ok]

        memo[:value] << validated[:value]
      end
    end
    private_class_method :validate_yaml_array

    def validate_yaml_hash(value, path)
      value.each_with_object({ ok: true, value: {} }) do |(key, item), memo|
        validated = validate_yaml_node(item, "#{path}/#{key}")
        return validated unless validated[:ok]

        memo[:value][key] = validated[:value]
      end
    end
    private_class_method :validate_yaml_hash

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
      sequence.flat_map { |item| render_yaml_sequence_item(item, prefix, indent) }
    end
    private_class_method :render_yaml_sequence

    def render_yaml_sequence_item(item, prefix, indent)
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
    private_class_method :render_yaml_sequence_item

    def canonical_yaml(mapping)
      "#{render_yaml_mapping(mapping).join("\n")}\n"
    end
    private_class_method :canonical_yaml

    def collect_yaml_owners(mapping, prefix = '')
      mapping.keys.sort.flat_map { |key| collect_yaml_owners_for_value(key, mapping[key], prefix) }
    end
    private_class_method :collect_yaml_owners

    def collect_yaml_owners_for_value(key, value, prefix)
      path = "#{prefix}/#{key}"
      case value
      when Array then collect_yaml_sequence_owners(key, value, path)
      when Hash then [{ path: path, owner_kind: 'mapping', match_key: key }] + collect_yaml_owners(value, path)
      else [{ path: path, owner_kind: 'key_value', match_key: key }]
      end
    end
    private_class_method :collect_yaml_owners_for_value

    def collect_yaml_sequence_owners(key, value, path)
      [{ path: path, owner_kind: 'key_value', match_key: key }] +
        value.each_with_index.flat_map do |item, index|
          item_path = "#{path}/#{index}"
          nested = item.is_a?(Hash) ? collect_yaml_owners(item, item_path) : []
          [{ path: item_path, owner_kind: 'sequence_item' }] + nested
        end
    end
    private_class_method :collect_yaml_sequence_owners

    def merge_yaml_mappings(template, destination)
      ordered_merge_keys(template, destination).each_with_object({}) do |key, merged|
        merged[key] = merge_yaml_mapping_value(template, destination, key)
      end
    end
    private_class_method :merge_yaml_mappings

    def merge_yaml_mapping_value(template, destination, key)
      return destination[key] unless template.key?(key)
      return template[key] unless destination.key?(key)
      if template[key].is_a?(Hash) && destination[key].is_a?(Hash)
        return merge_yaml_mappings(template[key],
                                   destination[key])
      end

      destination[key]
    end
    private_class_method :merge_yaml_mapping_value

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
  # rubocop:enable Metrics/ModuleLength
end

Yaml::Merge.register_backend!
require_relative 'merge/provider'
Yaml::Merge.register_provider!
