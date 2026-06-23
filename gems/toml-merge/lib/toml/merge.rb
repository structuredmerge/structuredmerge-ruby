# frozen_string_literal: true

# std libs
require 'json'

# External gems
# TreeHaver provides a unified cross-Ruby interface to tree-sitter.
# Toml::Merge registers TOML-specific backends with TreeHaver when loaded so
# parser_for(:toml) can resolve registered grammars and backends consistently.
require 'tree_haver'
require 'version_gem'

# Shared merge infrastructure
require 'ast/merge'

# This gem
require_relative 'merge/version'

# Toml::Merge provides a TOML file smart merge system using tree-sitter AST analysis.
# It intelligently merges template and destination TOML files by identifying matching
# keys and resolving differences using structural signatures.
#
# @example Basic usage
#   template = File.read("template.toml")
#   destination = File.read("destination.toml")
#   merger = Toml::Merge::SmartMerger.new(template, destination)
#   result = merger.merge
#
# @example With debug information
#   merger = Toml::Merge::SmartMerger.new(template, destination)
#   debug_result = merger.merge_with_debug
#   puts debug_result[:content]
#   puts debug_result[:statistics]
module Toml
  # Smart merge system for TOML files using tree-sitter AST analysis.
  # Provides intelligent merging by understanding TOML structure
  # rather than treating files as plain text.
  #
  # @see SmartMerger Main entry point for merge operations
  # @see FileAnalysis Analyzes TOML structure
  # @see ConflictResolver Resolves content conflicts
  module Merge
    PACKAGE_NAME = 'toml-merge'
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: 'array',
      name: 'destination_wins_array'
    }.freeze
    TREE_SITTER_BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: 'kreuzberg-language-pack',
                                                                    family: 'tree-sitter').freeze
    CITRUS_BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: 'citrus', family: 'peg').freeze
    PARSLET_BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: 'parslet', family: 'peg').freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    class InlineTable < Hash
    end

    # Base error class for Toml::Merge
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    class Error < Ast::Merge::Error; end

    # Raised when a TOML file has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    #
    # @example Handling parse errors
    #   begin
    #     analysis = FileAnalysis.new(toml_content)
    #   rescue ParseError => e
    #     puts "TOML syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error}" }
    #   end
    class ParseError < Ast::Merge::ParseError
      # @param message [String, nil] Error message (auto-generated if nil)
      # @param content [String, nil] The TOML source that failed to parse
      # @param errors [Array] Parse errors from tree-sitter
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    # Raised when the template file has syntax errors.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class TemplateParseError < ParseError; end

    # Raised when the destination file has syntax errors.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class DestinationParseError < ParseError; end

    class CorruptionDetectedError < Error; end

    autoload :CommentTracker, 'toml/merge/comment_tracker'
    autoload :DebugLogger, 'toml/merge/debug_logger'
    autoload :Emitter, 'toml/merge/emitter'
    autoload :FileAnalysis, 'toml/merge/file_analysis'
    autoload :KeySorter, 'toml/merge/key_sorter'
    autoload :MergeResult, 'toml/merge/merge_result'
    autoload :NodeTypeNormalizer, 'toml/merge/node_type_normalizer'
    autoload :NodeWrapper, 'toml/merge/node_wrapper'
    autoload :ConflictResolver, 'toml/merge/conflict_resolver'
    autoload :SmartMerger, 'toml/merge/smart_merger'
    autoload :TableMatchRefiner, 'toml/merge/table_match_refiner'

    class << self
      def toml_feature_profile
        {
          family: 'toml',
          supported_dialects: ['toml'],
          supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
        }
      end

      def available_toml_backends
        [TREE_SITTER_BACKEND_REFERENCE, CITRUS_BACKEND_REFERENCE, PARSLET_BACKEND_REFERENCE]
      end

      def toml_backend_feature_profile(backend: nil)
        requested = backend.to_s.empty? ? TREE_SITTER_BACKEND_REFERENCE.id : backend.to_s
        backend_ref = available_toml_backends.find { |candidate| candidate.id == requested }
        return unsupported_feature_result("Unsupported TOML backend #{requested}.") unless backend_ref

        toml_feature_profile.merge(
          backend: backend_ref.id,
          backend_ref: backend_ref.to_h
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

      def parse_toml(source, dialect, backend: nil)
        return unsupported_feature_parse_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'

        requested = backend.to_s.empty? ? TREE_SITTER_BACKEND_REFERENCE.id : backend.to_s
        return unsupported_feature_parse_result("Unsupported TOML backend #{requested}.") unless available_toml_backends.any? do |candidate|
          candidate.id == requested
        end

        analyze_toml_source(source, dialect)
      rescue StandardError => e
        parse_error_result(e.message)
      end

      def analyze_toml_source(source, dialect)
        return unsupported_feature_parse_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'

        parsed = parse_toml_document(source)
        {
          ok: true,
          diagnostics: [],
          analysis: {
            kind: 'toml',
            dialect: 'toml',
            normalized_source: canonical_toml(parsed),
            root_kind: 'table',
            owners: collect_toml_owners(parsed)
          },
          policies: []
        }
      rescue StandardError => e
        parse_error_result(e.message)
      end

      def match_toml_owners(template, destination)
        Ast::Merge::OwnerSelection.match_by_path(template, destination)
      end

      def merge_toml(template_source, destination_source, dialect, backend: nil)
        return unsupported_feature_merge_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'

        requested = backend.to_s.empty? ? TREE_SITTER_BACKEND_REFERENCE.id : backend.to_s
        return unsupported_feature_merge_result("Unsupported TOML backend #{requested}.") unless available_toml_backends.any? do |candidate|
          candidate.id == requested
        end

        unless template_source.match?(/^\s*#/) || destination_source.match?(/^\s*#/)
          merged = merge_toml_tables(parse_toml_document(template_source), parse_toml_document(destination_source))
          return {
            ok: true,
            diagnostics: [],
            output: canonical_toml(merged),
            policies: [DESTINATION_WINS_ARRAY_POLICY]
          }
        end

        output = SmartMerger.new(
          template_source,
          destination_source,
          preference: :destination,
          add_template_only_nodes: true
        ).merge_result.to_toml

        {
          ok: true,
          diagnostics: [],
          output: output,
          policies: [DESTINATION_WINS_ARRAY_POLICY]
        }
      rescue TemplateParseError => e
        { ok: false, diagnostics: [diagnostic('error', 'template_parse_error', e.message)], policies: [] }
      rescue DestinationParseError => e
        { ok: false, diagnostics: [diagnostic('error', 'destination_parse_error', e.message)], policies: [] }
      rescue StandardError => e
        { ok: false, diagnostics: [diagnostic('error', 'merge_error', e.message)], policies: [] }
      end

      def merge_toml_with_parser(template_source, destination_source, dialect)
        return unsupported_feature_merge_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'
        raise ArgumentError, 'merge_toml_with_parser requires a parser block' unless block_given?

        template_parse = yield(template_source, dialect)
        return provider_parse_failure(:template_parse_error, template_parse) unless template_parse[:ok]

        destination_parse = yield(destination_source, dialect)
        return provider_parse_failure(:destination_parse_error, destination_parse) unless destination_parse[:ok]

        unless template_source.match?(/^\s*#/) || destination_source.match?(/^\s*#/)
          merged = merge_toml_tables(parse_toml_document(template_source), parse_toml_document(destination_source))
          return {
            ok: true,
            diagnostics: [],
            output: canonical_toml(merged),
            policies: [DESTINATION_WINS_ARRAY_POLICY]
          }
        end

        output = SmartMerger.new(
          template_source,
          destination_source,
          preference: :destination,
          add_template_only_nodes: true
        ).merge_result.to_toml

        {
          ok: true,
          diagnostics: [],
          output: output,
          policies: [DESTINATION_WINS_ARRAY_POLICY]
        }
      rescue TemplateParseError => e
        { ok: false, diagnostics: [diagnostic('error', 'template_parse_error', e.message)], policies: [] }
      rescue DestinationParseError => e
        { ok: false, diagnostics: [diagnostic('error', 'destination_parse_error', e.message)], policies: [] }
      rescue StandardError => e
        { ok: false, diagnostics: [diagnostic('error', 'merge_error', e.message)], policies: [] }
      end

      def register_backend!
        BACKEND_REGISTRY.mutex.synchronize do
          return if BACKEND_REGISTRY.registered

          TreeHaver::BackendRegistry.register(TREE_SITTER_BACKEND_REFERENCE)
          TreeHaver::BackendRegistry.register(CITRUS_BACKEND_REFERENCE)
          TreeHaver::BackendRegistry.register(PARSLET_BACKEND_REFERENCE)

          register_tree_sitter_backend!
          register_citrus_backend!
          register_parslet_backend!

          BACKEND_REGISTRY.registered = true
        end
      end

      private

      def register_tree_sitter_backend!
        grammar_finder = TreeHaver::GrammarFinder.new(:toml)
        grammar_finder.register! if grammar_finder.available?
      end

      def register_citrus_backend!
        require 'toml-rb'
        return unless defined?(TomlRB::Document)

        TreeHaver.register_language(
          :toml,
          grammar_module: TomlRB::Document,
          gem_name: 'toml-rb'
        )
      rescue LoadError, NameError
        nil
      end

      def register_parslet_backend!
        require 'toml'
        return unless defined?(TOML::Parslet)

        TreeHaver.register_language(
          :toml,
          grammar_class: TOML::Parslet,
          gem_name: 'toml'
        )
      rescue LoadError, NameError
        nil
      end

      def diagnostic(severity, category, message)
        { severity: severity, category: category, message: message }
      end

      def parse_error_result(message)
        { ok: false, diagnostics: [diagnostic('error', 'parse_error', message)], policies: [] }
      end

      def provider_parse_failure(category, parse_result)
        diagnostics = Array(parse_result[:diagnostics])
        message = diagnostics.map { |diagnostic| diagnostic[:message] || diagnostic['message'] }.compact.join('; ')
        message = 'provider parse failed' if message.empty?
        { ok: false, diagnostics: [diagnostic('error', category.to_s, message)], policies: [] }
      end

      def normalize_toml_source(source)
        source.gsub(/\r\n?/, "\n")
      end

      def strip_toml_comment(line)
        result = +''
        in_string = false
        escaped = false

        line.each_char do |char|
          if in_string
            result << char
            if escaped
              escaped = false
            elsif char == '\\'
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

          break if char == '#'

          result << char
        end

        raise ParseError, 'Unterminated TOML string.' if in_string

        result.strip
      end

      def split_outside_quotes(value, separator)
        parts = []
        current = +''
        in_string = false
        escaped = false
        depth = 0

        value.each_char do |char|
          if in_string
            current << char
            if escaped
              escaped = false
            elsif char == '\\'
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
          when '[', '{'
            depth += 1
            current << char
          when ']', '}'
            depth -= 1
            current << char
          else
            if char == separator && depth.zero?
              parts << current.strip
              current = +''
            else
              current << char
            end
          end
        end

        raise ParseError, 'Unterminated TOML string, array, or inline table.' if in_string || !depth.zero?

        parts << current.strip
        parts
      end

      def parse_toml_key_path(value)
        trimmed = value.strip
        raise ParseError, 'Missing TOML key path.' if trimmed.empty?

        parts = trimmed.split('.').map(&:strip)
        raise ParseError, "Unsupported TOML key path #{trimmed}." unless parts.all? do |part|
          part.match?(/\A[A-Za-z0-9_-]+\z/)
        end

        parts
      end

      def parse_toml_scalar_value(value)
        case value
        when /\A".*"\z/m
          JSON.parse(value)
        when 'true'
          true
        when 'false'
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

      def parse_toml_value(value)
        stripped = value.strip
        if stripped.start_with?('[')
          raise ParseError, "Invalid TOML array #{value}." unless stripped.end_with?(']')

          inner = stripped[1..-2].strip
          return [] if inner.empty?

          split_outside_quotes(inner, ',').map { |entry| parse_toml_scalar_value(entry) }
        elsif stripped.start_with?('{')
          raise ParseError, "Invalid TOML inline table #{value}." unless stripped.end_with?('}')

          inner = stripped[1..-2].strip
          table = InlineTable.new
          return table if inner.empty?

          split_outside_quotes(inner, ',').each do |entry|
            pair = split_outside_quotes(entry, '=')
            raise ParseError, "Invalid TOML inline table entry #{entry}." unless pair.length == 2

            assign_toml_value(table, parse_toml_key_path(pair[0]), parse_toml_value(pair[1]))
          end
          table
        else
          parse_toml_scalar_value(stripped)
        end
      end

      def ensure_toml_table(root, path)
        current = root
        path.each do |segment|
          existing = current[segment]
          if existing.nil?
            current[segment] = {}
            current = current[segment]
          elsif toml_table_value?(existing)
            current = existing
          else
            raise ParseError, "TOML table path /#{path.join('/')} conflicts with a value."
          end
        end
        current
      end

      def assign_toml_value(root, path, value)
        raise ParseError, 'Missing TOML assignment path.' if path.empty?

        table = ensure_toml_table(root, path[0..-2])
        key = path[-1]
        existing = table[key]
        raise ParseError, "TOML key /#{path.join('/')} conflicts with a table." if toml_table_value?(existing)

        table[key] = value
      end

      def parse_toml_document(source)
        lines = normalize_toml_source(source).split("\n")
        root = {}
        current_table_path = []

        lines.each do |raw_line|
          line = strip_toml_comment(raw_line)
          next if line.empty?

          if line.start_with?('[')
            raise ParseError, "Invalid TOML table header #{line}." unless line.end_with?(']')

            current_table_path = parse_toml_key_path(line[1..-2])
            ensure_toml_table(root, current_table_path)
            next
          end

          parts = split_outside_quotes(line, '=')
          raise ParseError, "Invalid TOML assignment #{line}." unless parts.length == 2

          key_path = parse_toml_key_path(parts[0])
          value = parse_toml_value(parts[1])
          assign_toml_value(root, current_table_path + key_path, value)
        end

        root
      end

      def render_toml_scalar(value)
        if value.is_a?(String)
          JSON.generate(value)
        elsif [true, false].include?(value)
          value ? 'true' : 'false'
        else
          value.to_s
        end
      end

      def render_toml_value(value)
        return "[#{value.map { |item| render_toml_scalar(item) }.join(', ')}]" if value.is_a?(Array)

        if value.is_a?(InlineTable)
          pairs = value.keys.sort.map { |key| "#{key} = #{render_toml_value(value[key])}" }
          return "{ #{pairs.join(', ')} }"
        end

        render_toml_scalar(value)
      end

      def render_toml_table(table, path = [])
        lines = []
        keys = table.keys.sort
        value_keys = keys.reject { |key| toml_table_value?(table[key]) }
        table_keys = keys.select { |key| toml_table_value?(table[key]) }

        lines << "[#{path.join('.')}]" unless path.empty?
        value_keys.each do |key|
          lines << "#{key} = #{render_toml_value(table[key])}"
        end
        table_keys.each do |key|
          lines << '' unless lines.empty?
          lines.concat(render_toml_table(table[key], path + [key]))
        end
        lines
      end

      def canonical_toml(table)
        "#{render_toml_table(table).join("\n")}\n"
      end

      def collect_toml_owners(table, prefix = '')
        table.keys.sort.flat_map do |key|
          path = "#{prefix}/#{key}"
          value = table[key]
          if value.is_a?(Array)
            [{ path: path, owner_kind: 'key_value', match_key: key }] +
              value.each_index.map { |index| { path: "#{path}/#{index}", owner_kind: 'array_item' } }
          elsif toml_table_value?(value)
            [{ path: path, owner_kind: 'table', match_key: key }] + collect_toml_owners(value, path)
          else
            [{ path: path, owner_kind: 'key_value', match_key: key }]
          end
        end
      end

      def merge_toml_tables(template, destination)
        (template.keys | destination.keys).sort.each_with_object({}) do |key, merged|
          merged[key] = if !template.key?(key)
                          destination[key]
                        elsif !destination.key?(key)
                          template[key]
                        elsif toml_table_value?(template[key]) && toml_table_value?(destination[key])
                          merge_toml_tables(template[key], destination[key])
                        else
                          destination[key]
                        end
        end
      end

      def toml_table_value?(value)
        value.is_a?(Hash) && !value.is_a?(InlineTable)
      end

      def unsupported_feature_parse_result(message)
        { ok: false, diagnostics: [diagnostic('error', 'unsupported_feature', message)], policies: [] }
      end

      def unsupported_feature_merge_result(message)
        { ok: false, diagnostics: [diagnostic('error', 'unsupported_feature', message)], policies: [] }
      end

      def unsupported_feature_result(message)
        { ok: false, diagnostic: diagnostic('error', 'unsupported_feature', message) }
      end
    end
  end
end

Toml::Merge.register_backend!

# Register with ast-merge's MergeGemRegistry for RSpec dependency tags
# Only register if MergeGemRegistry is loaded (i.e., in test environment)
if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :toml_merge,
    require_path: 'toml/merge',
    merger_class: 'Toml::Merge::SmartMerger',
    test_source: "[section]\nkey = \"value\"",
    category: :config
  )
end

Toml::Merge::Version.class_eval do
  extend VersionGem::Basic
end
