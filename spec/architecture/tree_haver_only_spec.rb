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

  OWNERSHIP_SCAN_PATTERN = /
    comment_line\? |
    standalone_comment_line\? |
    coverage_directive_comment_line\? |
    blank_line_count_before |
    strip\.empty\? |
    rstrip\.empty\?
  /x

  MERGE_EMISSION_FILE_PATTERN = %r{
    /
    (?:smart_merger|conflict_resolver|emitter|merge_result|top_level_merge_runner|
       recursive_node_body_merger|node_emission_support|wrapper_comment_support)
    \.rb\z
  }x

  KNOWN_OWNERSHIP_SCAN_REFERENCES = Set.new(
    [
      "gems/bash-merge/lib/bash/merge/smart_merger.rb:if line.strip.empty?",
      "gems/bash-merge/lib/bash/merge/smart_merger.rb:trimmed_remainder_entries = remainder_entries.drop_while { |entry| entry[:line].strip.empty? }",
      "gems/dotenv-merge/lib/dotenv/merge/smart_merger.rb:if line.strip.empty?",
      "gems/dotenv-merge/lib/dotenv/merge/smart_merger.rb:leading_segment_lines_for(node, analysis).any? { |line| !line.to_s.strip.empty? }",
      "gems/json-merge/lib/json/merge/conflict_resolver.rb:return if before_comment.strip.empty?",
      "gems/json-merge/lib/json/merge/conflict_resolver.rb:return unless after_comment.strip.empty?",
      "gems/json-merge/lib/json/merge/emitter.rb:def comment_line?(stripped_line)",
      "gems/json-merge/lib/json/merge/emitter.rb:if stripped.empty? || comment_line?(stripped)",
      "gems/json-merge/lib/json/merge/emitter.rb:return line if line.strip.empty?",
      "gems/prism-merge/lib/prism/merge/node_emission_support.rb:analysis.line_at(line_num).to_s.strip.empty?",
      "gems/prism-merge/lib/prism/merge/node_emission_support.rb:if trailing_content && trailing_content.strip.empty?",
      "gems/prism-merge/lib/prism/merge/node_emission_support.rb:if trailing_content && trailing_content.strip.empty? && template_node_controls_trailing_gap?(template_node,",
      "gems/prism-merge/lib/prism/merge/node_emission_support.rb:lines.any? && lines.all? { |line| line.strip.empty? }",
      "gems/prism-merge/lib/prism/merge/node_emission_support.rb:next unless gap_line.strip.empty?",
      "gems/prism-merge/lib/prism/merge/node_emission_support.rb:next unless line.strip.empty?",
      "gems/prism-merge/lib/prism/merge/node_emission_support.rb:prefix_has_code = !prefix.strip.empty?",
      "gems/prism-merge/lib/prism/merge/recursive_node_body_merger.rb:elsif trailing_content && trailing_content.strip.empty?",
      "gems/prism-merge/lib/prism/merge/recursive_node_body_merger.rb:next unless line.strip.empty?",
      "gems/prism-merge/lib/prism/merge/smart_merger.rb:def ruby_magic_comment_line?(line)",
      "gems/prism-merge/lib/prism/merge/top_level_merge_runner.rb:next unless line.strip.empty?",
      "gems/prism-merge/lib/prism/merge/top_level_merge_runner.rb:return updated_last_output_dest_line unless dest_trailing && dest_trailing.strip.empty?",
      "gems/prism-merge/lib/prism/merge/top_level_merge_runner.rb:return updated_last_output_dest_line unless trailing_content && trailing_content.strip.empty?",
      "gems/prism-merge/lib/prism/merge/wrapper_comment_support.rb:next unless line.strip.empty?",
      "gems/prism-merge/lib/prism/merge/wrapper_comment_support.rb:return [] if line.strip.empty? || line.lstrip.start_with?('#')",
      "gems/psych-merge/lib/psych/merge/conflict_resolver.rb:blank_line_count_before(anchor_line, analysis)",
      "gems/psych-merge/lib/psych/merge/conflict_resolver.rb:blank_line_count_before(node_content_start_line(node), analysis)",
      "gems/psych-merge/lib/psych/merge/conflict_resolver.rb:first_content_line = lines.find { |line| !line.strip.empty? }",
      "gems/psych-merge/lib/psych/merge/conflict_resolver.rb:lines << line if line && line.strip.empty?",
      "gems/psych-merge/lib/psych/merge/conflict_resolver.rb:next false if line.strip.empty?",
      "gems/psych-merge/lib/psych/merge/conflict_resolver.rb:return blank_line_count_before(leading_region.start_line, source_analysis)",
      "gems/psych-merge/lib/psych/merge/conflict_resolver.rb:trimmed_lines.pop while next_node.nil? && trimmed_lines.any? && trimmed_lines.last.strip.empty?",
      "gems/rbs-merge/lib/rbs/merge/conflict_resolver.rb:blank_line_count_before(region_start, analysis)",
      "gems/rbs-merge/lib/rbs/merge/merge_result.rb:break if line.strip.empty?",
      "gems/rbs-merge/lib/rbs/merge/merge_result.rb:break unless standalone_comment_line?(line)",
      "gems/rbs-merge/lib/rbs/merge/merge_result.rb:def standalone_comment_line?(line)",
      "gems/rbs-merge/lib/rbs/merge/merge_result.rb:return [] if @lines.last.to_s.strip.empty?",
      "gems/rbs-merge/lib/rbs/merge/merge_result.rb:while leading_blank_count < lines.length && lines[leading_blank_count].to_s.strip.empty?",
      "gems/rbs-merge/lib/rbs/merge/smart_merger.rb:if line.strip.empty?",
      "gems/toml-merge/lib/toml/merge/conflict_resolver.rb:break unless line && line.strip.empty?",
      "gems/toml-merge/lib/toml/merge/conflict_resolver.rb:lines << line if line && line.strip.empty?"
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

  def current_ownership_scan_references
    Dir.glob(ROOT.join('gems', '*-merge', 'lib', '**', '*.rb')).each_with_object(Set.new) do |path, matches|
      relative_path = Pathname.new(path).relative_path_from(ROOT).to_s
      next unless relative_path.match?(MERGE_EMISSION_FILE_PATTERN)

      File.foreach(path) do |line|
        stripped = line.strip
        next if stripped.start_with?('#')
        next unless stripped.match?(OWNERSHIP_SCAN_PATTERN)

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

  it 'does not add new merge-emission comment or blank-line ownership scans' do
    current = current_ownership_scan_references
    new_references = current - KNOWN_OWNERSHIP_SCAN_REFERENCES

    expect(new_references.to_a.sort).to eq([])
  end

  it 'keeps the merge-emission ownership scan debt snapshot current' do
    current = current_ownership_scan_references
    removed_references = KNOWN_OWNERSHIP_SCAN_REFERENCES - current

    expect(removed_references.to_a.sort).to eq([])
  end
end
