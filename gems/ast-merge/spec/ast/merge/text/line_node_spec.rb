# frozen_string_literal: true

require 'ast/merge/text'

RSpec.describe Ast::Merge::Text::LineNode do
  describe '#initialize' do
    it 'sets content and line_number' do
      line = described_class.new('Hello world', line_number: 5)

      expect(line.content).to eq('Hello world')
      expect(line.line_number).to eq(5)
    end

    it 'parses words from content' do
      line = described_class.new('Hello world foo', line_number: 1)

      expect(line.words.size).to eq(3)
      expect(line.words.map(&:content)).to eq(%w[Hello world foo])
    end

    it 'handles empty content' do
      line = described_class.new('', line_number: 1)

      expect(line.words).to be_empty
    end
  end

  describe '#signature' do
    it 'returns signature array with normalized content' do
      line = described_class.new('  Hello world  ', line_number: 1)

      expect(line.signature).to eq([:line, 'Hello world'])
    end
  end

  describe '#normalized_content' do
    it 'strips whitespace from content' do
      line = described_class.new('  Hello world  ', line_number: 1)

      expect(line.normalized_content).to eq('Hello world')
    end
  end

  describe '#type' do
    it "returns 'line_node'" do
      line = described_class.new('Hello', line_number: 1)

      expect(line.type).to eq('line_node')
    end
  end

  describe '#children' do
    it 'returns the words array' do
      line = described_class.new('Hello world', line_number: 1)

      expect(line.children).to eq(line.words)
      expect(line.children.size).to eq(2)
    end

    it 'returns empty array for blank line' do
      line = described_class.new('', line_number: 1)

      expect(line.children).to eq([])
    end
  end

  describe '#blank?' do
    it 'returns true for empty content' do
      line = described_class.new('', line_number: 1)

      expect(line.blank?).to be true
    end

    it 'returns true for whitespace-only content' do
      line = described_class.new("   \t  ", line_number: 1)

      expect(line.blank?).to be true
    end

    it 'returns false for non-blank content' do
      line = described_class.new('Hello', line_number: 1)

      expect(line.blank?).to be false
    end
  end

  describe '#comment?' do
    it 'returns true for lines starting with #' do
      line = described_class.new('# This is a comment', line_number: 1)

      expect(line.comment?).to be true
    end

    it 'returns true for lines starting with # after whitespace' do
      line = described_class.new('  # Indented comment', line_number: 1)

      expect(line.comment?).to be true
    end

    it 'returns false for non-comment lines' do
      line = described_class.new('Hello world', line_number: 1)

      expect(line.comment?).to be false
    end
  end

  describe '#start_line' do
    it 'returns the line number' do
      line = described_class.new('Hello', line_number: 42)

      expect(line.start_line).to eq(42)
    end
  end

  describe '#end_line' do
    it 'returns the line number (same as start_line for single line)' do
      line = described_class.new('Hello', line_number: 42)

      expect(line.end_line).to eq(42)
    end
  end

  describe '#==' do
    it 'returns true for nodes with same content' do
      line1 = described_class.new('Hello', line_number: 1)
      line2 = described_class.new('Hello', line_number: 2)

      expect(line1 == line2).to be true
    end

    it 'returns false for nodes with different content' do
      line1 = described_class.new('Hello', line_number: 1)
      line2 = described_class.new('World', line_number: 1)

      expect(line1 == line2).to be false
    end

    it 'returns false when comparing with non-LineNode' do
      line = described_class.new('Hello', line_number: 1)

      expect(line == 'Hello').to be false
    end
  end

  describe '#eql?' do
    it 'is aliased to ==' do
      line1 = described_class.new('Hello', line_number: 1)
      line2 = described_class.new('Hello', line_number: 2)

      expect(line1.eql?(line2)).to be true
    end
  end

  describe '#hash' do
    it 'returns content hash' do
      line = described_class.new('Hello', line_number: 1)

      expect(line.hash).to eq('Hello'.hash)
    end

    it 'is consistent for equal objects' do
      line1 = described_class.new('Hello', line_number: 1)
      line2 = described_class.new('Hello', line_number: 2)

      expect(line1.hash).to eq(line2.hash)
    end
  end

  describe '#inspect' do
    it 'returns a debug representation' do
      line = described_class.new('Hello world', line_number: 5)

      expect(line.inspect).to eq('#<LineNode line=5 "Hello world" words=2>')
    end
  end

  describe '#to_s' do
    it 'returns the content' do
      line = described_class.new('Hello world', line_number: 1)

      expect(line.to_s).to eq('Hello world')
    end
  end
end
