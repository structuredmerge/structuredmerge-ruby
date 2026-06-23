# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::Line do
  let(:style) { Ast::Merge::Comment::Style.for(:hash_comment) }

  describe '#initialize' do
    it 'sets text' do
      line = described_class.new(text: '# hello', line_number: 1)
      expect(line.text).to eq('# hello')
    end

    it 'converts nil text to empty string' do
      line = described_class.new(text: nil, line_number: 1)
      expect(line.text).to eq('')
    end

    it 'sets line_number' do
      line = described_class.new(text: '# hello', line_number: 5)
      expect(line.line_number).to eq(5)
    end

    it 'defaults style to hash_comment' do
      line = described_class.new(text: '# hello', line_number: 1)
      expect(line.style.name).to eq(:hash_comment)
    end

    it 'accepts Style instance' do
      c_style = Ast::Merge::Comment::Style.for(:c_style_line)
      line = described_class.new(text: '// hello', line_number: 1, style: c_style)
      expect(line.style.name).to eq(:c_style_line)
    end

    it 'accepts Symbol for style' do
      line = described_class.new(text: '// hello', line_number: 1, style: :c_style_line)
      expect(line.style.name).to eq(:c_style_line)
    end

    it 'raises ArgumentError for invalid style' do
      expect do
        described_class.new(text: '# hello', line_number: 1, style: 123)
      end.to raise_error(ArgumentError, /Invalid style/)
    end

    it 'sets correct location' do
      line = described_class.new(text: '# hello world', line_number: 10)
      expect(line.location.start_line).to eq(10)
      expect(line.location.end_line).to eq(10)
      expect(line.location.start_column).to eq(0)
      expect(line.location.end_column).to eq(13)
    end
  end

  describe '#type' do
    it "returns 'comment_line'" do
      line = described_class.new(text: '# hello', line_number: 1)
      expect(line.type).to eq('comment_line')
    end
  end

  describe '#content' do
    it 'extracts content without delimiter' do
      line = described_class.new(text: '# hello world', line_number: 1)
      expect(line.content).to eq('hello world')
    end

    it 'caches content' do
      line = described_class.new(text: '# hello', line_number: 1)
      content1 = line.content
      content2 = line.content
      expect(content1).to equal(content2)
    end
  end

  describe '#signature' do
    it 'returns array with type and normalized content' do
      line = described_class.new(text: '# Hello World', line_number: 1)
      expect(line.signature).to eq([:comment_line, 'hello world'])
    end
  end

  describe '#normalized_content' do
    it 'returns stripped content' do
      line = described_class.new(text: '#   spaced  ', line_number: 1)
      expect(line.normalized_content).to eq('spaced')
    end
  end

  describe '#contains_token?' do
    let(:line) { described_class.new(text: '# foo:freeze some content', line_number: 1) }

    it 'returns true when token is found' do
      expect(line.contains_token?('foo')).to be true
    end

    it 'returns false when token is not found' do
      expect(line.contains_token?('bar')).to be false
    end

    it 'returns false for nil token' do
      expect(line.contains_token?(nil)).to be false
    end

    it 'matches token with action' do
      expect(line.contains_token?('foo', action: 'freeze')).to be true
      expect(line.contains_token?('foo', action: 'unfreeze')).to be false
    end
  end

  describe '#freeze_marker?' do
    it 'returns true for freeze marker' do
      line = described_class.new(text: '# mytoken:freeze', line_number: 1)
      expect(line.freeze_marker?('mytoken')).to be true
    end

    it 'returns true for unfreeze marker' do
      line = described_class.new(text: '# mytoken:unfreeze', line_number: 1)
      expect(line.freeze_marker?('mytoken')).to be true
    end

    it 'returns false when no freeze marker' do
      line = described_class.new(text: '# regular comment', line_number: 1)
      expect(line.freeze_marker?('mytoken')).to be false
    end

    it 'returns false for nil freeze_token' do
      line = described_class.new(text: '# mytoken:freeze', line_number: 1)
      expect(line.freeze_marker?(nil)).to be false
    end
  end

  describe '#freeze_action / #freeze? / #unfreeze?' do
    it 'classifies freeze directives explicitly' do
      line = described_class.new(text: '# mytoken:freeze', line_number: 1)

      expect(line.freeze_action('mytoken')).to eq(:freeze)
      expect(line.freeze?('mytoken')).to be(true)
      expect(line.unfreeze?('mytoken')).to be(false)
    end

    it 'classifies unfreeze directives explicitly' do
      line = described_class.new(text: '# mytoken:unfreeze', line_number: 1)

      expect(line.freeze_action('mytoken')).to eq(:unfreeze)
      expect(line.freeze?('mytoken')).to be(false)
      expect(line.unfreeze?('mytoken')).to be(true)
    end

    it 'returns nil when no freeze directive is present' do
      line = described_class.new(text: '# regular comment', line_number: 1)

      expect(line.freeze_action('mytoken')).to be_nil
    end
  end

  describe '#inspect' do
    it 'returns human-readable representation' do
      line = described_class.new(text: '# test', line_number: 42, style: :hash_comment)
      expect(line.inspect).to eq('#<Comment::Line line=42 style=hash_comment "# test">')
    end
  end
end
