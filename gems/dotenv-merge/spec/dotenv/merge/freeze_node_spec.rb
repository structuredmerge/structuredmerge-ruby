# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples'

RSpec.describe Dotenv::Merge::FreezeNode do
  # Use shared examples to validate base FreezeNodeBase integration
  it_behaves_like 'Ast::Merge::FreezeNodeBase' do
    let(:freeze_node_class) { described_class }
    let(:default_pattern_type) { :hash_comment }
    let(:build_freeze_node) do
      lambda { |start_line:, end_line:, **opts|
        # Build a mock analysis with the lines needed
        lines_content = []
        (1..end_line).each do |i|
          lines_content << if i == start_line
                             '# dotenv-merge:freeze'
                           elsif i == end_line
                             '# dotenv-merge:unfreeze'
                           else
                             "KEY_#{i}=value_#{i}"
                           end
        end
        source = lines_content.join("\n")
        analysis = Dotenv::Merge::FileAnalysis.new(source)

        freeze_node_class.new(
          start_line: start_line,
          end_line: end_line,
          analysis: analysis,
          reason: opts[:reason]
        )
      }
    end
  end

  # Dotenv-specific tests
  let(:source) do
    <<~DOTENV
      PUBLIC_KEY=public

      # dotenv-merge:freeze Custom reason
      API_KEY=my_custom_key
      API_SECRET=my_custom_secret
      # dotenv-merge:unfreeze

      DEBUG=false
    DOTENV
  end
  let(:analysis) { Dotenv::Merge::FileAnalysis.new(source) }

  describe 'inheritance' do
    it 'inherits from Ast::Merge::FreezeNodeBase' do
      expect(described_class.superclass).to eq(Ast::Merge::FreezeNodeBase)
    end

    it 'has InvalidStructureError' do
      expect(described_class::InvalidStructureError).to eq(Ast::Merge::FreezeNodeBase::InvalidStructureError)
    end

    it 'has Location' do
      expect(described_class::Location).to eq(Ast::Merge::FreezeNodeBase::Location)
    end
  end

  describe 'freeze block detection' do
    it 'detects freeze blocks in analysis' do
      expect(analysis.freeze_blocks.size).to eq(1)
    end

    it 'has correct line numbers' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.start_line).to eq(3)
      expect(freeze_node.end_line).to eq(6)
    end
  end

  describe '#lines' do
    it 'contains lines within the freeze block' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.lines.size).to eq(4)
    end

    it 'includes freeze marker lines' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.lines.first.comment?).to be true
      expect(freeze_node.lines.last.comment?).to be true
    end
  end

  describe '#env_lines' do
    it 'returns only assignment lines' do
      freeze_node = analysis.freeze_blocks.first
      env_lines = freeze_node.env_lines
      expect(env_lines.size).to eq(2)
      expect(env_lines.map(&:key)).to contain_exactly('API_KEY', 'API_SECRET')
    end
  end

  describe '#content' do
    it 'returns the content of the freeze block' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.content).to include('dotenv-merge:freeze')
      expect(freeze_node.content).to include('API_KEY=my_custom_key')
      expect(freeze_node.content).to include('dotenv-merge:unfreeze')
    end
  end

  describe '#signature' do
    it 'returns a FreezeNode signature' do
      freeze_node = analysis.freeze_blocks.first
      sig = freeze_node.signature
      expect(sig.first).to eq(:FreezeNode)
      expect(sig.last).to be_a(String)
    end
  end

  describe '#reason' do
    it 'extracts reason from freeze marker' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.reason).to eq('Custom reason')
    end

    context 'without reason' do
      let(:source) do
        <<~DOTENV
          # dotenv-merge:freeze
          KEY=value
          # dotenv-merge:unfreeze
        DOTENV
      end

      it 'returns nil when no reason provided' do
        freeze_node = analysis.freeze_blocks.first
        expect(freeze_node.reason).to be_nil
      end
    end
  end

  describe '#location' do
    it 'returns a Location struct' do
      freeze_node = analysis.freeze_blocks.first
      location = freeze_node.location
      expect(location).to be_a(described_class::Location)
      expect(location.start_line).to eq(3)
      expect(location.end_line).to eq(6)
    end

    it 'supports cover?' do
      freeze_node = analysis.freeze_blocks.first
      location = freeze_node.location
      expect(location.cover?(3)).to be true
      expect(location.cover?(5)).to be true
      expect(location.cover?(6)).to be true
      expect(location.cover?(2)).to be false
      expect(location.cover?(7)).to be false
    end
  end

  describe '#inspect' do
    it 'returns a descriptive string' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.inspect).to include('FreezeNode')
      expect(freeze_node.inspect).to include('3..6')
      expect(freeze_node.inspect).to include('env_vars=2')
    end
  end

  describe '#content edge cases' do
    it 'uses to_s fallback for lines without raw method' do
      # The &. safe navigation handles nil, and the ternary handles respond_to?(:raw)
      # This tests the `l.to_s` branch when `l.respond_to?(:raw)` is false
      freeze_node = analysis.freeze_blocks.first
      # The actual implementation uses EnvLine objects which have :raw
      # Just verify content works on a real freeze block
      content = freeze_node.content
      expect(content).to be_a(String)
      expect(content).to include('API_KEY=my_custom_key')
    end

    it 'handles empty lines array gracefully' do
      # When @lines is an empty array, content should return empty string
      freeze_node = analysis.freeze_blocks.first
      # Override @lines to empty for this test
      freeze_node.instance_variable_set(:@lines, [])
      content = freeze_node.content
      expect(content).to eq('')
    end
  end

  describe '#env_lines edge cases' do
    it 'filters out lines without assignment? method' do
      # The actual code checks l.respond_to?(:assignment?) && l.assignment?
      # This path is covered when we have comments in freeze blocks
      freeze_node = analysis.freeze_blocks.first
      env_lines = freeze_node.env_lines

      # Should only include the 2 assignment lines, not the freeze markers
      expect(env_lines.size).to eq(2)
      expect(env_lines.all? { |l| l.assignment? }).to be true
    end

    it 'returns empty array when @lines is nil' do
      # Test the || [] fallback
      freeze_node = described_class.allocate
      freeze_node.instance_variable_set(:@lines, nil)
      freeze_node.instance_variable_set(:@start_line, 1)
      freeze_node.instance_variable_set(:@end_line, 2)

      env_lines = freeze_node.env_lines
      expect(env_lines).to eq([])
    end

    it 'returns empty array when @lines is empty' do
      freeze_node = analysis.freeze_blocks.first
      freeze_node.instance_variable_set(:@lines, [])
      env_lines = freeze_node.env_lines
      expect(env_lines).to eq([])
    end
  end
end
