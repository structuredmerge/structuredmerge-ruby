# frozen_string_literal: true

require 'pathname'
require 'set'

RSpec.describe 'TreeHaver-only merge architecture' do
  ROOT = Pathname.new(__dir__).join('..', '..').expand_path

  PARSER_BYPASS_PATTERN = /
    TreeHaver\.(?:parse_with_language_pack|process_with_language_pack|parse_with_citrus|parse_with_parslet) |
    Json::Merge::SyntheticParser |
    (?<!:)SyntheticParser |
    JSON\.parse\( |
    YAML\.safe_load\( |
    TomlRB |
    TOML::Parslet
  /x

  KNOWN_PARSER_BYPASS_REFERENCES = Set.new(
    [
      "gems/bash-merge/lib/bash/merge.rb:result = TreeHaver.process_with_language_pack(",
      "gems/citrus-toml-merge/lib/citrus/toml/merge.rb:syntax_result = TreeHaver.parse_with_citrus(source, grammar_module: TomlRB::Document)",
      "gems/go-merge/lib/go/merge.rb:parsed = TreeHaver.parse_with_language_pack(TreeHaver::ParserRequest.new(source: source, language: 'go',",
      "gems/go-merge/lib/go/merge.rb:processed = TreeHaver.process_with_language_pack(TreeHaver::ProcessRequest.new(source: source, language: 'go'))",
      "gems/json-merge/lib/json/merge.rb:backend_result = TreeHaver.parse_with_language_pack(json_parse_request(source, dialect))",
      "gems/json-merge/lib/json/merge.rb:parsed = JSON.parse(normalized_source)",
      "gems/json-merge/lib/json/merge/file_analysis.rb:JSON.parse(Json::Merge.send(:strip_trailing_commas, normalized))",
      "gems/json-merge/lib/json/merge/file_analysis.rb:@ast = SyntheticParser.new(@source).parse",
      "gems/json-merge/lib/json/merge/synthetic_parser.rb:class SyntheticParser",
      "gems/markdown-merge/lib/markdown/merge.rb:syntax = TreeHaver.parse_with_language_pack(",
      "gems/parslet-toml-merge/lib/parslet/toml/merge.rb:syntax_result = TreeHaver.parse_with_parslet(source, grammar_class: TOML::Parslet)",
      "gems/psych-merge/lib/psych/merge.rb:parsed = YAML.safe_load(source, permitted_classes: [], aliases: false)",
      "gems/ruby-merge/lib/ruby/merge.rb:process = TreeHaver.process_with_language_pack(request)",
      "gems/ruby-merge/lib/ruby/merge.rb:syntax = TreeHaver.parse_with_language_pack(request)",
      "gems/rust-merge/lib/rust/merge.rb:parsed = TreeHaver.parse_with_language_pack(TreeHaver::ParserRequest.new(source: source, language: 'rust',",
      "gems/rust-merge/lib/rust/merge.rb:processed = TreeHaver.process_with_language_pack(TreeHaver::ProcessRequest.new(source: source, language: 'rust'))",
      "gems/toml-merge/lib/toml/merge.rb:grammar_class: TOML::Parslet,",
      "gems/toml-merge/lib/toml/merge.rb:grammar_module: TomlRB::Document,",
      "gems/toml-merge/lib/toml/merge.rb:return unless defined?(TOML::Parslet)",
      "gems/toml-merge/lib/toml/merge.rb:return unless defined?(TomlRB::Document)",
      "gems/typescript-merge/lib/typescript/merge.rb:parsed = TreeHaver.parse_with_language_pack(TreeHaver::ParserRequest.new(source: source, language: 'typescript',",
      "gems/typescript-merge/lib/typescript/merge.rb:processed = TreeHaver.process_with_language_pack(TreeHaver::ProcessRequest.new(source: source,",
      "gems/yaml-merge/lib/yaml/merge.rb:destination_document = YAML.safe_load(destination.dig(:analysis, :normalized_source), permitted_classes: [],",
      "gems/yaml-merge/lib/yaml/merge.rb:parsed = YAML.safe_load(source, permitted_classes: [], aliases: false)",
      "gems/yaml-merge/lib/yaml/merge.rb:syntax_result = TreeHaver.parse_with_language_pack(",
      "gems/yaml-merge/lib/yaml/merge.rb:template_document = YAML.safe_load(template.dig(:analysis, :normalized_source), permitted_classes: [],"
    ]
  ).freeze

  def current_parser_bypass_references
    Dir.glob(ROOT.join('gems', '*-merge', 'lib', '**', '*.rb')).each_with_object(Set.new) do |path, matches|
      relative_path = Pathname.new(path).relative_path_from(ROOT).to_s
      next if relative_path.include?('/rspec/')

      File.foreach(path) do |line|
        stripped = line.strip
        next if stripped.start_with?('#')
        next unless stripped.match?(PARSER_BYPASS_PATTERN)

        matches << "#{relative_path}:#{stripped}"
      end
    end
  end

  it 'does not add new merge-gem parser bypasses outside TreeHaver parser_for' do
    current = current_parser_bypass_references
    new_references = current - KNOWN_PARSER_BYPASS_REFERENCES

    expect(new_references.to_a.sort).to eq([])
  end

  it 'keeps the parser bypass debt snapshot current' do
    current = current_parser_bypass_references
    removed_references = KNOWN_PARSER_BYPASS_REFERENCES - current

    expect(removed_references.to_a.sort).to eq([])
  end
end
