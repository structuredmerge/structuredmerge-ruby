# frozen_string_literal: true

require 'ast/merge/text'

RSpec.describe Ast::Merge::Text::WordNode do
  describe '#initialize' do
    it 'sets all attributes' do
      word = described_class.new('hello', line_number: 1, word_index: 0, start_col: 5, end_col: 10)

      expect(word.content).to eq('hello')
      expect(word.line_number).to eq(1)
      expect(word.word_index).to eq(0)
      expect(word.start_col).to eq(5)
      expect(word.end_col).to eq(10)
    end
  end

  describe '#type' do
    it "returns 'word_node'" do
      word = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)

      expect(word.type).to eq('word_node')
    end
  end

  describe '#normalized_content' do
    it 'returns the content unchanged' do
      word = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)

      expect(word.normalized_content).to eq('hello')
    end
  end

  describe '#signature' do
    it 'returns signature array with content' do
      word = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)

      expect(word.signature).to eq([:word, 'hello'])
    end
  end

  describe '#==' do
    it 'returns true for nodes with same content' do
      word1 = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)
      word2 = described_class.new('hello', line_number: 2, word_index: 1, start_col: 10, end_col: 15)

      expect(word1 == word2).to be true
    end

    it 'returns false for nodes with different content' do
      word1 = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)
      word2 = described_class.new('world', line_number: 1, word_index: 0, start_col: 0, end_col: 5)

      expect(word1 == word2).to be false
    end

    it 'returns false when comparing with non-WordNode' do
      word = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)

      expect(word == 'hello').to be false
    end
  end

  describe '#eql?' do
    it 'is aliased to ==' do
      word1 = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)
      word2 = described_class.new('hello', line_number: 2, word_index: 1, start_col: 10, end_col: 15)

      expect(word1.eql?(word2)).to be true
    end
  end

  describe '#hash' do
    it 'returns content hash' do
      word = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)

      expect(word.hash).to eq('hello'.hash)
    end

    it 'is consistent for equal objects' do
      word1 = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)
      word2 = described_class.new('hello', line_number: 2, word_index: 1, start_col: 10, end_col: 15)

      expect(word1.hash).to eq(word2.hash)
    end
  end

  describe '#inspect' do
    it 'returns a debug representation' do
      word = described_class.new('hello', line_number: 5, word_index: 2, start_col: 10, end_col: 15)

      expect(word.inspect).to eq('#<WordNode "hello" line=5 col=10..15>')
    end
  end

  describe '#to_s' do
    it 'returns the content' do
      word = described_class.new('hello', line_number: 1, word_index: 0, start_col: 0, end_col: 5)

      expect(word.to_s).to eq('hello')
    end
  end
end
