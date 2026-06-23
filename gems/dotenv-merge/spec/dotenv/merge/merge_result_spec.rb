# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples'

RSpec.describe Dotenv::Merge::MergeResult do
  let(:template_source) do
    <<~DOTENV
      API_KEY=template_key
      DATABASE_URL=postgres://template
      NEW_VAR=new_value
    DOTENV
  end

  let(:dest_source) do
    <<~DOTENV
      API_KEY=dest_key
      DATABASE_URL=postgres://dest
      CUSTOM_VAR=custom_value
    DOTENV
  end

  let(:template_analysis) { Dotenv::Merge::FileAnalysis.new(template_source) }
  let(:dest_analysis) { Dotenv::Merge::FileAnalysis.new(dest_source) }
  let(:result) { described_class.new(template_analysis, dest_analysis) }

  # Use shared examples - dotenv-merge's MergeResult requires analysis args
  it_behaves_like 'Ast::Merge::MergeResultBase' do
    let(:merge_result_class) { described_class }
    let(:build_merge_result) { -> { described_class.new(template_analysis, dest_analysis) } }
  end

  describe '#initialize' do
    it 'initializes with empty content and decisions' do
      expect(result.content).to be_empty
      expect(result.decisions).to be_empty
    end

    it 'stores template and dest analysis' do
      expect(result.template_analysis).to eq(template_analysis)
      expect(result.dest_analysis).to eq(dest_analysis)
    end
  end

  describe '#add_from_template' do
    it 'adds content from template' do
      result.add_from_template(0)
      expect(result.to_s).to include('API_KEY=template_key')
    end

    it 'records decision' do
      result.add_from_template(0, decision: described_class::DECISION_ADDED)
      expect(result.decisions.first[:decision]).to eq(described_class::DECISION_ADDED)
      expect(result.decisions.first[:source]).to eq(:template)
    end

    it 'handles nil statement gracefully' do
      result.add_from_template(999)
      expect(result.content).to be_empty
    end
  end

  describe '#add_from_destination' do
    it 'adds content from destination' do
      result.add_from_destination(0)
      expect(result.to_s).to include('API_KEY=dest_key')
    end

    it 'records decision' do
      result.add_from_destination(0)
      expect(result.decisions.first[:decision]).to eq(described_class::DECISION_DESTINATION)
      expect(result.decisions.first[:source]).to eq(:destination)
    end

    it 'handles nil statement gracefully' do
      result.add_from_destination(999)
      expect(result.content).to be_empty
    end
  end

  describe '#add_freeze_block' do
    let(:dest_with_freeze) do
      <<~DOTENV
        # dotenv-merge:freeze
        SECRET=frozen_value
        # dotenv-merge:unfreeze
      DOTENV
    end
    let(:dest_analysis_frozen) { Dotenv::Merge::FileAnalysis.new(dest_with_freeze) }
    let(:result_frozen) { described_class.new(template_analysis, dest_analysis_frozen) }

    it 'adds freeze block content' do
      freeze_node = dest_analysis_frozen.freeze_blocks.first
      result_frozen.add_freeze_block(freeze_node)
      expect(result_frozen.to_s).to include('dotenv-merge:freeze')
      expect(result_frozen.to_s).to include('SECRET=frozen_value')
      expect(result_frozen.to_s).to include('dotenv-merge:unfreeze')
    end

    it 'records freeze block decision' do
      freeze_node = dest_analysis_frozen.freeze_blocks.first
      result_frozen.add_freeze_block(freeze_node)
      expect(result_frozen.decisions.first[:decision]).to eq(described_class::DECISION_FREEZE_BLOCK)
    end
  end

  describe '#add_raw' do
    it 'adds raw lines' do
      result.add_raw(['# Custom content', 'RAW_VAR=raw_value'], decision: :custom)
      expect(result.to_s).to include('# Custom content')
      expect(result.to_s).to include('RAW_VAR=raw_value')
    end

    it 'records raw decision' do
      result.add_raw(['# line'], decision: :custom)
      expect(result.decisions.first[:decision]).to eq(:custom)
      expect(result.decisions.first[:source]).to eq(:raw)
    end
  end

  describe '#to_s' do
    it 'returns empty string for empty result' do
      expect(result.to_s).to eq('')
    end

    it 'joins content with newlines' do
      result.add_from_template(0)
      result.add_from_template(1)
      output = result.to_s
      expect(output).to include("\n")
      expect(output).to end_with("\n")
    end
  end

  describe '#empty?' do
    it 'returns true when no content' do
      expect(result.empty?).to be true
    end

    it 'returns false when content exists' do
      result.add_from_template(0)
      expect(result.empty?).to be false
    end
  end

  describe '#summary' do
    it 'returns summary hash' do
      result.add_from_template(0, decision: described_class::DECISION_TEMPLATE)
      result.add_from_destination(0, decision: described_class::DECISION_DESTINATION)

      summary = result.summary
      expect(summary[:total_decisions]).to eq(2)
      expect(summary[:by_decision]).to include(described_class::DECISION_TEMPLATE => 1)
      expect(summary[:by_decision]).to include(described_class::DECISION_DESTINATION => 1)
    end
  end

  describe 'decision constants' do
    it 'defines DECISION_FREEZE_BLOCK' do
      expect(described_class::DECISION_FREEZE_BLOCK).to eq(:freeze_block)
    end

    it 'defines DECISION_TEMPLATE' do
      expect(described_class::DECISION_TEMPLATE).to eq(:template)
    end

    it 'defines DECISION_DESTINATION' do
      expect(described_class::DECISION_DESTINATION).to eq(:destination)
    end

    it 'defines DECISION_ADDED' do
      expect(described_class::DECISION_ADDED).to eq(:added)
    end
  end

  describe '#extract_lines (private)' do
    it 'returns empty array for unknown statement types' do
      unknown_stmt = Object.new
      lines = result.send(:extract_lines, unknown_stmt)
      expect(lines).to eq([])
    end

    it 'extracts raw from EnvLine' do
      env_line = template_analysis.statements.first
      lines = result.send(:extract_lines, env_line)
      expect(lines).to eq(['API_KEY=template_key'])
    end

    it 'extracts multiple lines from FreezeNode' do
      dest_with_freeze = <<~DOTENV
        # dotenv-merge:freeze
        KEY1=val1
        KEY2=val2
        # dotenv-merge:unfreeze
      DOTENV
      analysis = Dotenv::Merge::FileAnalysis.new(dest_with_freeze)
      freeze_node = analysis.freeze_blocks.first

      lines = result.send(:extract_lines, freeze_node)
      expect(lines.size).to eq(4)
      expect(lines).to include('# dotenv-merge:freeze')
      expect(lines).to include('KEY1=val1')
    end
  end
end
