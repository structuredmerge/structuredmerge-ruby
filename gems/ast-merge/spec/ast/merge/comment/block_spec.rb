# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::Block do
  let(:style) { Ast::Merge::Comment::Style.for(:hash_comment) }
  let(:first_line) { Ast::Merge::Comment::Line.new(text: '# First line', line_number: 1) }
  let(:second_line) { Ast::Merge::Comment::Line.new(text: '# Second line', line_number: 2) }

  describe '#initialize with children' do
    let(:block) { described_class.new(children: [first_line, second_line]) }

    it 'sets children' do
      expect(block.children).to eq([first_line, second_line])
    end

    it 'sets start_line from first child' do
      expect(block.location.start_line).to eq(1)
    end

    it 'sets end_line from last child' do
      expect(block.location.end_line).to eq(2)
    end

    it 'defaults style to hash_comment' do
      expect(block.style.name).to eq(:hash_comment)
    end

    it 'accepts Symbol for style' do
      b = described_class.new(children: [first_line], style: :c_style_line)
      expect(b.style.name).to eq(:c_style_line)
    end

    it 'accepts Style instance' do
      c_style = Ast::Merge::Comment::Style.for(:c_style_line)
      b = described_class.new(children: [first_line], style: c_style)
      expect(b.style.name).to eq(:c_style_line)
    end

    it 'raises ArgumentError for invalid style' do
      expect do
        described_class.new(children: [first_line], style: 123)
      end.to raise_error(ArgumentError, /Invalid style/)
    end
  end

  describe '#initialize with raw_content' do
    let(:raw_block) do
      described_class.new(
        raw_content: "/* Multi-line\n * comment\n */",
        start_line: 5,
        end_line: 7,
        style: :c_style_block
      )
    end

    it 'sets raw_content' do
      expect(raw_block.raw_content).to eq("/* Multi-line\n * comment\n */")
    end

    it 'sets start_line' do
      expect(raw_block.location.start_line).to eq(5)
    end

    it 'sets end_line' do
      expect(raw_block.location.end_line).to eq(7)
    end

    it 'sets children to empty array' do
      expect(raw_block.children).to eq([])
    end
  end

  describe '#initialize with empty children' do
    it 'handles empty children array' do
      block = described_class.new(children: [])
      expect(block.children).to eq([])
      expect(block.location.start_line).to eq(1)
      expect(block.location.end_line).to eq(1)
    end

    it 'handles nil children' do
      block = described_class.new(children: nil)
      expect(block.children).to eq([])
    end
  end

  describe '#type' do
    it "returns 'comment_block'" do
      block = described_class.new(children: [first_line])
      expect(block.type).to eq('comment_block')
    end
  end

  describe '#signature' do
    context 'with children' do
      let(:block) { described_class.new(children: [first_line, second_line]) }

      it 'returns array with type and first meaningful content' do
        sig = block.signature
        expect(sig[0]).to eq(:comment_block)
        expect(sig[1]).to eq('first line')
      end
    end

    context 'with raw_content' do
      let(:raw_block) do
        described_class.new(
          raw_content: '/* Hello world */',
          start_line: 1,
          end_line: 1,
          style: :c_style_block
        )
      end

      it 'extracts signature from raw content' do
        sig = raw_block.signature
        expect(sig[0]).to eq(:comment_block)
        expect(sig[1]).to include('hello world')
      end
    end

    context 'with very long content' do
      let(:long_line) do
        Ast::Merge::Comment::Line.new(text: '# ' + 'a' * 200, line_number: 1)
      end
      let(:block) { described_class.new(children: [long_line]) }

      it 'truncates signature content' do
        sig = block.signature
        expect(sig[1].length).to be <= 121
      end
    end
  end

  describe '#normalized_content' do
    context 'with children' do
      let(:block) { described_class.new(children: [first_line, second_line]) }

      it 'joins children content' do
        expect(block.normalized_content).to eq("First line\nSecond line")
      end
    end

    context 'with raw_content' do
      let(:raw_block) do
        described_class.new(
          raw_content: '/* Hello */',
          start_line: 1,
          end_line: 1,
          style: :c_style_block
        )
      end

      it 'extracts block content' do
        expect(raw_block.normalized_content).to eq('Hello')
      end
    end
  end

  describe '#freeze_marker?' do
    context 'with children' do
      it 'returns true if any child has freeze marker' do
        freeze_line = Ast::Merge::Comment::Line.new(text: '# mytoken:freeze', line_number: 1)
        block = described_class.new(children: [freeze_line, second_line])
        expect(block.freeze_marker?('mytoken')).to be true
      end

      it 'returns false if no child has freeze marker' do
        block = described_class.new(children: [first_line, second_line])
        expect(block.freeze_marker?('mytoken')).to be false
      end

      it 'returns false for nil freeze_token' do
        block = described_class.new(children: [first_line])
        expect(block.freeze_marker?(nil)).to be false
      end
    end

    context 'with raw_content' do
      it 'returns true if raw_content contains freeze marker' do
        raw_block = described_class.new(
          raw_content: '/* mytoken:freeze */',
          start_line: 1,
          end_line: 1,
          style: :c_style_block
        )
        expect(raw_block.freeze_marker?('mytoken')).to be true
      end

      it 'returns false if raw_content does not contain freeze marker' do
        raw_block = described_class.new(
          raw_content: '/* regular comment */',
          start_line: 1,
          end_line: 1,
          style: :c_style_block
        )
        expect(raw_block.freeze_marker?('mytoken')).to be false
      end
    end
  end

  describe '#freeze_action / #freeze? / #unfreeze?' do
    it 'classifies child-based freeze directives' do
      freeze_line = Ast::Merge::Comment::Line.new(text: '# mytoken:freeze', line_number: 1)
      block = described_class.new(children: [freeze_line, second_line])

      expect(block.freeze_action('mytoken')).to eq(:freeze)
      expect(block.freeze?('mytoken')).to be(true)
      expect(block.unfreeze?('mytoken')).to be(false)
    end

    it 'classifies raw-content unfreeze directives' do
      raw_block = described_class.new(
        raw_content: '/* mytoken:unfreeze */',
        start_line: 1,
        end_line: 1,
        style: :c_style_block
      )

      expect(raw_block.freeze_action('mytoken')).to eq(:unfreeze)
      expect(raw_block.freeze?('mytoken')).to be(false)
      expect(raw_block.unfreeze?('mytoken')).to be(true)
    end
  end

  describe '#inspect' do
    context 'with children' do
      it 'returns readable representation' do
        block = described_class.new(children: [first_line, second_line])
        expect(block.inspect).to eq('#<Comment::Block lines=1..2 style=hash_comment children=2>')
      end
    end

    context 'with raw_content' do
      it 'returns readable representation for block comment' do
        raw_block = described_class.new(
          raw_content: '/* comment */',
          start_line: 5,
          end_line: 7,
          style: :c_style_block
        )
        expect(raw_block.inspect).to eq('#<Comment::Block lines=5..7 style=c_style_block block_comment>')
      end
    end
  end

  describe 'first_meaningful_content (private)' do
    context 'with empty children' do
      it 'returns empty string' do
        # Create empty lines
        empty = Ast::Merge::Comment::Empty.new(line_number: 1)
        empty_line = Ast::Merge::Comment::Line.new(text: '#', line_number: 2)
        block = described_class.new(children: [empty, empty_line])
        # The signature calls first_meaningful_content
        sig = block.signature
        expect(sig[1]).to eq('')
      end
    end

    context 'with raw_content that has no lines' do
      it 'returns empty string for empty block comment' do
        raw_block = described_class.new(
          raw_content: '/**/',
          start_line: 1,
          end_line: 1,
          style: :c_style_block
        )
        sig = raw_block.signature
        expect(sig[1]).to eq('')
      end
    end
  end

  describe 'extract_block_content (private)' do
    it 'handles multi-line block comments with asterisks' do
      raw_block = described_class.new(
        raw_content: "/* First line\n * Second line\n * Third line\n */",
        start_line: 1,
        end_line: 4,
        style: :c_style_block
      )
      content = raw_block.normalized_content
      expect(content).to include('First line')
      expect(content).to include('Second line')
      expect(content).to include('Third line')
    end

    it 'returns empty string for nil raw_content' do
      raw_block = described_class.new(
        raw_content: nil,
        start_line: 1,
        end_line: 1,
        style: :c_style_block
      )
      expect(raw_block.normalized_content).to eq('')
    end
  end
end
