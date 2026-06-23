# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::QuotedHashLineParser do
  subject(:parser) { described_class.new }

  describe '#parse' do
    it 'parses full-line hash comments' do
      result = parser.parse('  # docs here')

      expect(result).not_to be_nil
      expect(result.full_line?).to be(true)
      expect(result.indent).to eq(2)
      expect(result.text).to eq('docs here')
      expect(result.raw).to eq('  # docs here')
    end

    it 'parses inline hash comments after content' do
      result = parser.parse('key: value # inline docs')

      expect(result).not_to be_nil
      expect(result.inline?).to be(true)
      expect(result.column).to eq(11)
      expect(result.text).to eq('inline docs')
      expect(result.raw).to eq('# inline docs')
    end

    it 'ignores hash characters inside double quotes' do
      result = parser.parse('key: "value # inside quotes"')

      expect(result).to be_nil
    end

    it 'ignores hash characters inside single quotes' do
      result = parser.parse("key: 'value # inside quotes'")

      expect(result).to be_nil
    end

    it 'parses trailing comments after quoted content' do
      result = parser.parse('key: "value # inside quotes" # trailing docs')

      expect(result).not_to be_nil
      expect(result.inline?).to be(true)
      expect(result.text).to eq('trailing docs')
      expect(result.raw).to eq('# trailing docs')
    end

    it 'rejects hashes that are not separated by whitespace' do
      result = parser.parse('PASSWORD=abc#123')

      expect(result).to be_nil
    end

    it 'treats escaped hash characters as content' do
      result = parser.parse('value \# literal # real comment')

      expect(result).not_to be_nil
      expect(result.inline?).to be(true)
      expect(result.text).to eq('real comment')
    end
  end
end
