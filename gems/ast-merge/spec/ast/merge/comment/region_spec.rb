# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::Region do
  let(:line_one) { Ast::Merge::Comment::Line.new(text: '# First', line_number: 3) }
  let(:line_two) { Ast::Merge::Comment::Line.new(text: '# Second', line_number: 4) }
  let(:empty_line) { Ast::Merge::Comment::Empty.new(line_number: 5) }

  describe 'kind predicates' do
    it 'recognizes region kinds' do
      region = described_class.new(kind: :leading, nodes: [line_one])

      expect(region).to be_leading
      expect(region).not_to be_inline
      expect(region).not_to be_trailing
    end

    it 'accepts string kinds' do
      region = described_class.new(kind: 'postlude', nodes: [line_one])

      expect(region).to be_postlude
    end

    it 'raises for unknown kinds' do
      expect do
        described_class.new(kind: :mystery, nodes: [line_one])
      end.to raise_error(ArgumentError, /Unknown comment region kind/)
    end
  end

  describe '#floating?' do
    it 'returns true when metadata[:floating] is true' do
      region = described_class.new(kind: :leading, nodes: [line_one], metadata: { floating: true })

      expect(region).to be_floating
    end

    it 'returns false when metadata[:floating] is absent' do
      region = described_class.new(kind: :leading, nodes: [line_one])

      expect(region).not_to be_floating
    end

    it 'returns false when metadata[:floating] is false' do
      region = described_class.new(kind: :leading, nodes: [line_one], metadata: { floating: false })

      expect(region).not_to be_floating
    end
  end

  describe 'location and content' do
    it 'derives line range from child node locations' do
      region = described_class.new(kind: :leading, nodes: [line_one, line_two, empty_line])

      expect(region.start_line).to eq(3)
      expect(region.end_line).to eq(5)
      expect(region.location).to have_attributes(start_line: 3, end_line: 5)
    end

    it 'joins normalized content from child nodes' do
      region = described_class.new(kind: :leading, nodes: [line_one, line_two, empty_line])

      expect(region.normalized_content).to eq("First\nSecond\n")
    end

    it 'joins raw text from child nodes' do
      region = described_class.new(kind: :leading, nodes: [line_one, line_two])

      expect(region.text).to eq("# First\n# Second")
    end

    it 'handles empty regions' do
      region = described_class.new(kind: :orphan, nodes: [])

      expect(region).to be_empty
      expect(region.location).to be_nil
      expect(region.normalized_content).to eq('')
    end
  end

  describe '#signature' do
    it 'includes the kind and normalized content' do
      region = described_class.new(kind: :inline, nodes: [line_one])

      expect(region.signature).to eq([:comment_region, :inline, 'First'])
    end
  end

  describe '#freeze_marker?' do
    it 'delegates freeze marker detection to child nodes' do
      marker = Ast::Merge::Comment::Line.new(text: '# prism-merge:freeze', line_number: 10)
      region = described_class.new(kind: :leading, nodes: [line_one, marker])

      expect(region.freeze_marker?('prism-merge')).to be(true)
      expect(region.freeze_marker?('psych-merge')).to be(false)
    end
  end

  describe '#freeze? / #unfreeze?' do
    it 'detects freeze directives separately from unfreeze directives' do
      region = described_class.new(
        kind: :leading,
        nodes: [
          Ast::Merge::Comment::Line.new(text: '# prism-merge:freeze', line_number: 10),
          Ast::Merge::Comment::Line.new(text: '# docs', line_number: 11)
        ]
      )

      expect(region.freeze?('prism-merge')).to be(true)
      expect(region.unfreeze?('prism-merge')).to be(false)
    end

    it 'detects unfreeze directives separately from freeze directives' do
      region = described_class.new(
        kind: :leading,
        nodes: [Ast::Merge::Comment::Line.new(text: '# prism-merge:unfreeze', line_number: 10)]
      )

      expect(region.freeze?('prism-merge')).to be(false)
      expect(region.unfreeze?('prism-merge')).to be(true)
    end
  end
end
