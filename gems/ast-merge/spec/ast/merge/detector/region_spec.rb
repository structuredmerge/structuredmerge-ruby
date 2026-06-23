# frozen_string_literal: true

RSpec.describe Ast::Merge::Detector::Region do
  describe '#initialize' do
    subject(:region) do
      described_class.new(
        type: :yaml_frontmatter,
        content: "title: Test\nauthor: Jane",
        start_line: 1,
        end_line: 4,
        delimiters: ['---', '---'],
        metadata: { format: :yaml }
      )
    end

    it 'sets type' do
      expect(region.type).to eq(:yaml_frontmatter)
    end

    it 'sets content' do
      expect(region.content).to eq("title: Test\nauthor: Jane")
    end

    it 'sets start_line' do
      expect(region.start_line).to eq(1)
    end

    it 'sets end_line' do
      expect(region.end_line).to eq(4)
    end

    it 'sets delimiters' do
      expect(region.delimiters).to eq(['---', '---'])
    end

    it 'sets metadata' do
      expect(region.metadata).to eq({ format: :yaml })
    end
  end

  describe '#line_range' do
    subject(:region) do
      described_class.new(
        type: :code_block,
        content: "def hello\n  puts 'hi'\nend",
        start_line: 5,
        end_line: 9,
        delimiters: ['```ruby', '```'],
        metadata: {}
      )
    end

    it 'returns a Range from start_line to end_line' do
      expect(region.line_range).to eq(5..9)
    end
  end

  describe '#full_text' do
    context 'with delimiters' do
      subject(:region) do
        described_class.new(
          type: :yaml_frontmatter,
          content: "title: Test\n",
          start_line: 1,
          end_line: 3,
          delimiters: ['---', '---'],
          metadata: {}
        )
      end

      it 'includes opening delimiter, content, and closing delimiter' do
        expect(region.full_text).to eq("---\ntitle: Test\n---")
      end
    end

    context 'without delimiters' do
      subject(:region) do
        described_class.new(
          type: :raw,
          content: 'just content',
          start_line: 1,
          end_line: 1,
          delimiters: nil,
          metadata: {}
        )
      end

      it 'returns just the content' do
        expect(region.full_text).to eq('just content')
      end
    end

    context 'with empty delimiters' do
      subject(:region) do
        described_class.new(
          type: :raw,
          content: 'content only',
          start_line: 1,
          end_line: 1,
          delimiters: [],
          metadata: {}
        )
      end

      it 'returns just the content' do
        expect(region.full_text).to eq('content only')
      end
    end
  end

  describe '#to_s' do
    subject(:region) do
      described_class.new(
        type: :code_block,
        content: 'code here',
        start_line: 10,
        end_line: 15,
        delimiters: ['```', '```'],
        metadata: { language: :ruby }
      )
    end

    it 'returns a descriptive string' do
      expect(region.to_s).to eq('Region<code_block:10-15>')
    end
  end

  describe '#inspect' do
    subject(:region) do
      described_class.new(
        type: :yaml_frontmatter,
        content: 'title: A Very Long Title That Should Be Truncated In Inspect Output',
        start_line: 1,
        end_line: 3,
        delimiters: ['---', '---'],
        metadata: { format: :yaml }
      )
    end

    it 'includes type, line range, and truncated content' do
      result = region.inspect
      expect(result).to include('Region<yaml_frontmatter:1-3>')
      expect(result).to include('title: A Very Long Title That')
      expect(result).to include('...')
    end

    context 'with short content' do
      subject(:region) do
        described_class.new(
          type: :code_block,
          content: 'short',
          start_line: 1,
          end_line: 1,
          delimiters: nil,
          metadata: {}
        )
      end

      it 'includes full content without truncation' do
        result = region.inspect
        expect(result).to include('"short"')
        expect(result).not_to include('...')
      end
    end
  end

  describe 'struct behavior' do
    it 'is a Struct' do
      expect(described_class).to be < Struct
    end

    it 'supports keyword arguments' do
      region = described_class.new(type: :test, content: 'c', start_line: 1, end_line: 2)
      expect(region.type).to eq(:test)
    end

    it 'uses keyword_init so positional arguments are not supported' do
      # keyword_init: true means positional args don't work
      expect do
        described_class.new(:test, 'c', 1, 2, nil, {})
      end.to raise_error(ArgumentError)
    end

    it 'is comparable by value' do
      r1 = described_class.new(type: :a, content: 'x', start_line: 1, end_line: 2)
      r2 = described_class.new(type: :a, content: 'x', start_line: 1, end_line: 2)
      expect(r1).to eq(r2)
    end
  end

  describe '#line_count' do
    it 'returns 1 for single-line region' do
      region = described_class.new(
        type: :single,
        content: 'one line',
        start_line: 5,
        end_line: 5,
        delimiters: nil,
        metadata: {}
      )
      expect(region.line_count).to eq(1)
    end

    it 'returns correct count for multi-line region' do
      region = described_class.new(
        type: :multi,
        content: "line1\nline2\nline3",
        start_line: 10,
        end_line: 14,
        delimiters: ['---', '---'],
        metadata: {}
      )
      expect(region.line_count).to eq(5)
    end
  end

  describe '#contains_line?' do
    subject(:region) do
      described_class.new(
        type: :block,
        content: 'content',
        start_line: 5,
        end_line: 10,
        delimiters: nil,
        metadata: {}
      )
    end

    it 'returns true for start_line' do
      expect(region.contains_line?(5)).to be true
    end

    it 'returns true for end_line' do
      expect(region.contains_line?(10)).to be true
    end

    it 'returns true for middle line' do
      expect(region.contains_line?(7)).to be true
    end

    it 'returns false for line before region' do
      expect(region.contains_line?(4)).to be false
    end

    it 'returns false for line after region' do
      expect(region.contains_line?(11)).to be false
    end
  end

  describe '#overlaps?' do
    subject(:region) do
      described_class.new(
        type: :block,
        content: 'content',
        start_line: 10,
        end_line: 20,
        delimiters: nil,
        metadata: {}
      )
    end

    it 'returns true when other starts inside this region' do
      other = described_class.new(
        type: :other,
        content: 'c',
        start_line: 15,
        end_line: 25,
        delimiters: nil,
        metadata: {}
      )
      expect(region.overlaps?(other)).to be true
    end

    it 'returns true when other ends inside this region' do
      other = described_class.new(
        type: :other,
        content: 'c',
        start_line: 5,
        end_line: 15,
        delimiters: nil,
        metadata: {}
      )
      expect(region.overlaps?(other)).to be true
    end

    it 'returns true when other contains this region' do
      other = described_class.new(
        type: :other,
        content: 'c',
        start_line: 5,
        end_line: 25,
        delimiters: nil,
        metadata: {}
      )
      expect(region.overlaps?(other)).to be true
    end

    it 'returns true when this region contains other' do
      other = described_class.new(
        type: :other,
        content: 'c',
        start_line: 12,
        end_line: 18,
        delimiters: nil,
        metadata: {}
      )
      expect(region.overlaps?(other)).to be true
    end

    it 'returns false when other is completely before' do
      other = described_class.new(
        type: :other,
        content: 'c',
        start_line: 1,
        end_line: 5,
        delimiters: nil,
        metadata: {}
      )
      expect(region.overlaps?(other)).to be false
    end

    it 'returns false when other is completely after' do
      other = described_class.new(
        type: :other,
        content: 'c',
        start_line: 25,
        end_line: 30,
        delimiters: nil,
        metadata: {}
      )
      expect(region.overlaps?(other)).to be false
    end
  end
end
