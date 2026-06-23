# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples/file_analyzable'

# Minimal test implementation of FileAnalyzable for testing shared examples
class TestFileAnalysis
  include Ast::Merge::FileAnalyzable

  # NOTE: :source, :lines, :freeze_token, :signature_generator are provided by FileAnalyzable
  attr_reader :statements

  def initialize(source, freeze_token: 'test-merge', signature_generator: nil)
    @source = source
    @lines = source.lines.map(&:chomp)
    @freeze_token = freeze_token
    @signature_generator = signature_generator
    @statements = parse_statements
    @freeze_blocks = nil
  end

  def freeze_blocks
    @freeze_blocks ||= detect_freeze_blocks
  end

  def in_freeze_block?(line_num)
    freeze_blocks.any? { |block| block.location.cover?(line_num) }
  end

  def freeze_block_at(line_num)
    freeze_blocks.find { |block| block.location.cover?(line_num) }
  end

  def compute_node_signature(node)
    case node
    when Ast::Merge::FreezeNodeBase
      node.signature
    when Hash
      [:hash, node[:type], node[:value]]
    else
      [:unknown, node.hash]
    end
  end

  private

  def parse_statements
    # Simple parser: each non-blank, non-comment line is a statement
    result = []
    @lines.each_with_index do |line, idx|
      next if line.strip.empty?
      next if line.strip.start_with?('#') && !line.include?(':freeze') && !line.include?(':unfreeze')

      result << { type: :statement, value: line, line: idx + 1 }
    end
    result
  end

  def detect_freeze_blocks
    blocks = []
    in_freeze = false
    start_line = nil
    start_marker = nil
    content_lines = []

    @lines.each_with_index do |line, idx|
      line_num = idx + 1

      if !in_freeze && Ast::Merge::FreezeNodeBase.freeze_start?(line, :hash_comment)
        in_freeze = true
        start_line = line_num
        start_marker = line
        content_lines = [line]
      elsif in_freeze
        content_lines << line
        if Ast::Merge::FreezeNodeBase.freeze_end?(line, :hash_comment)
          blocks << Ast::Merge::FreezeNodeBase.new(
            start_line: start_line,
            end_line: line_num,
            content: content_lines.join("\n"),
            start_marker: start_marker,
            end_marker: line,
            pattern_type: :hash_comment
          )
          in_freeze = false
          start_line = nil
          start_marker = nil
          content_lines = []
        end
      end
    end

    blocks
  end
end

# Minimal FreezeNode class for testing (wraps FreezeNodeBase)
class TestFreezeNode < Ast::Merge::FreezeNodeBase
  def covers_line?(line_num)
    line_num.between?(start_line, end_line)
  end
end

# - This file tests shared examples, not a single class
RSpec.describe 'FileAnalyzable shared examples' do
  it_behaves_like 'Ast::Merge::FileAnalyzable' do
    let(:file_analysis_class) { TestFileAnalysis }
    let(:freeze_node_class) { Ast::Merge::FreezeNodeBase }

    let(:sample_source) do
      <<~SOURCE
        # A sample file
        def hello
          puts "world"
        end
      SOURCE
    end

    let(:sample_source_with_freeze) do
      <<~SOURCE
        # Header comment
        def before
          puts "before"
        end
        # test-merge:freeze
        frozen content here
        # test-merge:unfreeze
        def after
          puts "after"
        end
      SOURCE
    end

    let(:build_file_analysis) do
      ->(source, **opts) { TestFileAnalysis.new(source, **opts) }
    end

    let(:analysis_expected_feature_profile) do
      {
        owner_selector: :shared_default,
        match_key: :signature,
        read_strategy: nil,
        attachment_strategy: :layout_only,
        comment_style: nil,
        render_family: nil,
        capabilities: { layout_aware: true, logical_owner: false },
        logical_owners: {},
        repair_policies: [],
        surfaces: [],
        delegation_policies: []
      }
    end
  end
end
