# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::Style do
  describe '.register' do
    # NOTE: The .register method modifies a frozen constant which is hard to test
    # without actually modifying global state. We test the behavior indirectly.

    it 'raises ArgumentError for duplicate style name' do
      expect do
        described_class.register(:hash_comment, line_start: '#')
      end.to raise_error(ArgumentError, /already registered/)
    end
  end

  describe '.available_styles' do
    it 'returns array of style names' do
      styles = described_class.available_styles
      expect(styles).to include(:hash_comment, :c_style_line, :html_comment, :c_style_block)
      expect(styles).to all(be_a(Symbol))
    end
  end

  describe '.supports_line_comments?' do
    it 'returns truthy for hash_comment style' do
      result = described_class.supports_line_comments?(:hash_comment)
      expect(result).to be_truthy
    end

    it 'returns truthy for c_style_line style' do
      result = described_class.supports_line_comments?(:c_style_line)
      expect(result).to be_truthy
    end

    it 'returns falsy for block-only styles' do
      result = described_class.supports_line_comments?(:c_style_block)
      expect(result).to be_falsy
    end

    it 'returns nil for unknown styles' do
      result = described_class.supports_line_comments?(:unknown)
      expect(result).to be_nil
    end
  end

  describe '.supports_block_comments?' do
    it 'returns truthy for c_style_block style' do
      result = described_class.supports_block_comments?(:c_style_block)
      expect(result).to be_truthy
    end

    it 'returns truthy for html_comment style' do
      result = described_class.supports_block_comments?(:html_comment)
      expect(result).to be_truthy
    end

    it 'returns falsy for line-only styles' do
      result = described_class.supports_block_comments?(:hash_comment)
      expect(result).to be_falsy
    end

    it 'returns nil for unknown styles' do
      result = described_class.supports_block_comments?(:unknown)
      expect(result).to be_nil
    end
  end

  describe '#match_block_start?' do
    it 'returns true for block start' do
      style = described_class.for(:c_style_block)
      expect(style.match_block_start?('/* comment')).to be true
    end

    it 'returns false for non-block-start' do
      style = described_class.for(:c_style_block)
      expect(style.match_block_start?('regular text')).to be false
    end

    it 'returns false when style has no block_start_pattern' do
      style = described_class.for(:hash_comment)
      expect(style.match_block_start?('/* comment')).to be false
    end
  end

  describe '#match_block_end?' do
    it 'returns true for block end' do
      style = described_class.for(:c_style_block)
      expect(style.match_block_end?('comment */')).to be true
    end

    it 'returns false for non-block-end' do
      style = described_class.for(:c_style_block)
      expect(style.match_block_end?('regular text')).to be false
    end

    it 'returns false when style has no block_end_pattern' do
      style = described_class.for(:hash_comment)
      expect(style.match_block_end?('*/')).to be false
    end
  end

  describe '#match_line?' do
    it 'returns false when style has no line_pattern' do
      style = described_class.for(:c_style_block)
      expect(style.match_line?('# comment')).to be false
    end
  end

  describe '#extract_line_content' do
    it 'handles nil line_start gracefully' do
      style = described_class.for(:c_style_block)
      expect(style.extract_line_content('some text')).to eq('some text')
    end

    it 'handles line_end stripping' do
      style = described_class.for(:html_comment)
      content = style.extract_line_content('<!-- hello world -->')
      expect(content).to eq('hello world')
    end
  end

  describe '#inspect' do
    it 'returns readable representation' do
      style = described_class.for(:hash_comment)
      expect(style.inspect).to eq('#<Comment::Style:hash_comment>')
    end
  end
end
