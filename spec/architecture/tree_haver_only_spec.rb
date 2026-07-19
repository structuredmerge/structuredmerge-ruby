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
    YAML\.(?:safe_load|safe_load_file|load|load_file|parse)\( |
    Psych\.(?:parse|parse_stream|safe_load|safe_load_file|load|load_file)\( |
    Prism\.parse(?:_file)?\( |
    RBS::Parser\.parse_signature\( |
    TomlRB::Document\.parse\( |
    TOML::(?:Parser|Parslet)\.parse\(
  /x

  KNOWN_PARSER_BYPASS_REFERENCES = Set.new(
    [
    ]
  ).freeze

  def current_parser_bypass_references
    Dir.glob(ROOT.join('gems', '{*-merge,*-merge-git}', 'lib', '**', '*.rb')).each_with_object(Set.new) do |path, matches|
      relative_path = Pathname.new(path).relative_path_from(ROOT).to_s
      next if relative_path.include?('/rspec/')
      next if relative_path.include?('/backends/')
      next if relative_path.start_with?('gems/ast-merge/lib/ast/merge/recipe/')

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
