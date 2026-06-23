# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::Empty do
  describe '#initialize' do
    it 'sets line_number' do
      empty = described_class.new(line_number: 5)
      expect(empty.line_number).to eq(5)
    end

    it 'defaults text to empty string' do
      empty = described_class.new(line_number: 5)
      expect(empty.text).to eq('')
    end

    it 'sets text when provided' do
      empty = described_class.new(line_number: 5, text: '   ')
      expect(empty.text).to eq('   ')
    end

    it 'converts non-string text to string' do
      empty = described_class.new(line_number: 5, text: nil)
      expect(empty.text).to eq('')
    end

    it 'sets slice to the text value' do
      empty = described_class.new(line_number: 5, text: '  ')
      expect(empty.slice).to eq('  ')
    end

    it 'sets location correctly' do
      empty = described_class.new(line_number: 5, text: '   ')
      expect(empty.location.start_line).to eq(5)
      expect(empty.location.end_line).to eq(5)
      expect(empty.location.start_column).to eq(0)
      expect(empty.location.end_column).to eq(3)
    end
  end

  describe '#type' do
    it "returns 'empty_line'" do
      empty = described_class.new(line_number: 1)
      expect(empty.type).to eq('empty_line')
    end
  end

  describe '#signature' do
    it 'returns [:empty_line]' do
      empty = described_class.new(line_number: 1)
      expect(empty.signature).to eq([:empty_line])
    end

    it 'returns the same signature for all empty lines regardless of content' do
      empty1 = described_class.new(line_number: 1)
      empty2 = described_class.new(line_number: 10, text: '   ')
      expect(empty1.signature).to eq(empty2.signature)
    end
  end

  describe '#normalized_content' do
    it 'returns empty string' do
      empty = described_class.new(line_number: 1)
      expect(empty.normalized_content).to eq('')
    end

    it 'returns empty string even with whitespace text' do
      empty = described_class.new(line_number: 1, text: '   ')
      expect(empty.normalized_content).to eq('')
    end
  end

  describe '#freeze_marker?' do
    it 'returns false regardless of freeze_token' do
      empty = described_class.new(line_number: 1)
      expect(empty.freeze_marker?('freeze')).to be false
      expect(empty.freeze_marker?('frozen')).to be false
      expect(empty.freeze_marker?(nil)).to be false
    end
  end

  describe '#inspect' do
    it 'returns human-readable representation' do
      empty = described_class.new(line_number: 42)
      expect(empty.inspect).to eq('#<Comment::Empty line=42>')
    end
  end
end
