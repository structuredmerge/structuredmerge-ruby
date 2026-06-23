# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bash::Merge::MergeResult do
  let(:result) { described_class.new }

  describe 'decision constants' do
    it 'defines DECISION_KEPT_TEMPLATE' do
      expect(described_class::DECISION_KEPT_TEMPLATE).to eq(Ast::Merge::MergeResultBase::DECISION_KEPT_TEMPLATE)
    end

    it 'defines DECISION_KEPT_DEST' do
      expect(described_class::DECISION_KEPT_DEST).to eq(Ast::Merge::MergeResultBase::DECISION_KEPT_DEST)
    end

    it 'defines DECISION_MERGED' do
      expect(described_class::DECISION_MERGED).to eq(Ast::Merge::MergeResultBase::DECISION_MERGED)
    end

    it 'defines DECISION_ADDED' do
      expect(described_class::DECISION_ADDED).to eq(Ast::Merge::MergeResultBase::DECISION_ADDED)
    end

    it 'defines DECISION_FREEZE_BLOCK' do
      expect(described_class::DECISION_FREEZE_BLOCK).to eq(Ast::Merge::MergeResultBase::DECISION_FREEZE_BLOCK)
    end
  end

  describe '#initialize' do
    it 'starts with empty lines' do
      expect(result.lines).to be_empty
    end

    it 'initializes statistics' do
      expect(result.statistics).to be_a(Hash)
      expect(result.statistics[:total_decisions]).to eq(0)
    end
  end

  describe '#add_line' do
    it 'adds a line with decision and source' do
      result.add_line("echo 'hello'", decision: :kept_template, source: :template)

      expect(result.lines.size).to eq(1)
      expect(result.lines.first[:content]).to eq("echo 'hello'")
      expect(result.lines.first[:decision]).to eq(:kept_template)
    end

    it 'tracks statistics' do
      result.add_line('line', decision: described_class::DECISION_KEPT_TEMPLATE, source: :template)

      expect(result.statistics[:template_lines]).to eq(1)
      expect(result.statistics[:total_decisions]).to eq(1)
    end
  end

  describe '#add_lines' do
    it 'adds multiple lines' do
      result.add_lines(
        %w[line1 line2],
        decision: :kept_dest,
        source: :destination,
        start_line: 5
      )

      expect(result.lines.size).to eq(2)
      expect(result.lines.first[:original_line]).to eq(5)
      expect(result.lines.last[:original_line]).to eq(6)
    end
  end

  describe '#add_blank_line' do
    it 'adds an empty line' do
      result.add_blank_line

      expect(result.lines.size).to eq(1)
      expect(result.lines.first[:content]).to eq('')
    end
  end

  describe '#add_freeze_block' do
    let(:lines) do
      [
        '# bash-merge:freeze',
        'SECRET="value"',
        '# bash-merge:unfreeze'
      ]
    end
    let(:freeze_node) do
      Bash::Merge::FreezeNode.new(
        start_line: 1,
        end_line: 3,
        lines: lines
      )
    end

    it 'adds all lines from the freeze block' do
      result.add_freeze_block(freeze_node)

      expect(result.lines.size).to eq(3)
    end

    it 'marks lines as freeze block decisions' do
      result.add_freeze_block(freeze_node)

      result.lines.each do |line|
        expect(line[:decision]).to eq(described_class::DECISION_FREEZE_BLOCK)
      end
    end

    it 'tracks freeze block statistics' do
      result.add_freeze_block(freeze_node)

      expect(result.statistics[:freeze_preserved_lines]).to eq(3)
    end
  end

  describe '#to_bash' do
    it 'joins lines with newlines' do
      result.add_line('line1', decision: :kept_template, source: :template)
      result.add_line('line2', decision: :kept_template, source: :template)

      expect(result.to_bash).to eq("line1\nline2\n")
    end

    it 'ensures trailing newline' do
      result.add_line('line', decision: :kept_template, source: :template)

      expect(result.to_bash).to end_with("\n")
    end
  end

  describe '#content' do
    it 'is an alias for #to_bash' do
      result.add_line('test', decision: :kept_template, source: :template)

      expect(result.content).to eq(result.to_bash)
    end
  end

  describe '#add_node', :bash_grammar do
    let(:source) { "echo 'hello'" }
    let(:analysis) { Bash::Merge::FileAnalysis.new(source) }

    it 'adds lines from a node wrapper' do
      node = analysis.nodes.first

      result.add_node(
        node,
        decision: described_class::DECISION_KEPT_DEST,
        source: :destination,
        analysis: analysis
      )

      expect(result.lines).not_to be_empty
    end

    it 'skips nodes without line information' do
      # Create a mock node without line info
      mock_node = double('NodeWrapper', start_line: nil, end_line: nil)

      result.add_node(
        mock_node,
        decision: described_class::DECISION_KEPT_DEST,
        source: :destination,
        analysis: analysis
      )

      expect(result.lines).to be_empty
    end

    it 'skips lines that return nil from analysis' do
      node = analysis.nodes.first

      # Create a mock analysis that returns nil for lines
      mock_analysis = double('FileAnalysis', line_at: nil)

      result.add_node(
        node,
        decision: described_class::DECISION_KEPT_DEST,
        source: :destination,
        analysis: mock_analysis
      )

      expect(result.lines).to be_empty
    end
  end

  describe 'statistics tracking' do
    it 'tracks template lines' do
      result.add_line('line', decision: described_class::DECISION_KEPT_TEMPLATE, source: :template)
      expect(result.statistics[:template_lines]).to eq(1)
    end

    it 'tracks destination lines' do
      result.add_line('line', decision: described_class::DECISION_KEPT_DEST, source: :destination)
      expect(result.statistics[:dest_lines]).to eq(1)
    end

    it 'tracks freeze block lines' do
      result.add_line('line', decision: described_class::DECISION_FREEZE_BLOCK, source: :destination)
      expect(result.statistics[:freeze_preserved_lines]).to eq(1)
    end

    it 'tracks merged lines for other decisions' do
      result.add_line('line', decision: described_class::DECISION_MERGED, source: :merged)
      expect(result.statistics[:merged_lines]).to eq(1)
    end

    it 'tracks added lines as merged' do
      result.add_line('line', decision: described_class::DECISION_ADDED, source: :template)
      expect(result.statistics[:merged_lines]).to eq(1)
    end
  end

  describe '#line_count' do
    it 'returns the number of lines' do
      result.add_line('line1', decision: :kept, source: :template)
      result.add_line('line2', decision: :kept, source: :template)

      expect(result.line_count).to eq(2)
    end
  end

  describe '#decision_summary' do
    it 'returns a hash of decision counts' do
      result.add_line('line1', decision: described_class::DECISION_KEPT_TEMPLATE, source: :template)
      result.add_line('line2', decision: described_class::DECISION_KEPT_DEST, source: :destination)
      result.add_line('line3', decision: described_class::DECISION_KEPT_DEST, source: :destination)

      summary = result.decision_summary
      expect(summary).to be_a(Hash)
      expect(summary[described_class::DECISION_KEPT_TEMPLATE]).to eq(1)
      expect(summary[described_class::DECISION_KEPT_DEST]).to eq(2)
    end
  end

  describe 'empty content handling' do
    it 'handles empty result gracefully' do
      expect(result.to_bash).to eq('')
    end

    it 'returns empty string for content when no lines' do
      expect(result.content).to eq('')
    end
  end
end
