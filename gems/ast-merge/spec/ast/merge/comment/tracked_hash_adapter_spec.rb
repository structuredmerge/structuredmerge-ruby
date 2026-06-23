# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::TrackedHashAdapter do
  describe '.node' do
    it 'converts a full-line tracked hash into a Comment::Line' do
      comment = described_class.node({
                                       line: 7,
                                       indent: 2,
                                       text: 'Header comment',
                                       full_line: true,
                                       raw: '  # Header comment'
                                     })

      expect(comment).to be_a(Ast::Merge::Comment::Line)
      expect(comment.line_number).to eq(7)
      expect(comment.text).to eq('  # Header comment')
      expect(comment.content).to eq('Header comment')
    end

    it 'reconstructs inline comment text when raw contains the full source line' do
      comment = described_class.node({
                                       line: 9,
                                       indent: 18,
                                       text: 'inline note',
                                       full_line: false,
                                       raw: 'key: value # inline note'
                                     })

      expect(comment.text).to eq('                  # inline note')
      expect(comment.content).to eq('inline note')
    end

    it 'preserves trailing spaces when reconstructing inline comment text from a full source line' do
      comment = described_class.node({
                                       line: 9,
                                       indent: 11,
                                       text: 'inline note',
                                       full_line: false,
                                       raw: 'key: value # inline note  '
                                     })

      expect(comment.text).to eq('           # inline note  ')
    end

    it 'accepts symbolized or stringified keys' do
      comment = described_class.node({
                                       'line' => 2,
                                       'indent' => 0,
                                       'text' => 'From strings',
                                       'full_line' => true,
                                       'raw' => '# From strings'
                                     })

      expect(comment.line_number).to eq(2)
      expect(comment.content).to eq('From strings')
    end

    it 'raises when required keys are missing' do
      expect do
        described_class.node({ text: 'Missing line' })
      end.to raise_error(ArgumentError, /include :line/)

      expect do
        described_class.node({ line: 1 })
      end.to raise_error(ArgumentError, /include :text or :raw/)
    end

    it 'raises for unsupported block comment hashes' do
      expect do
        described_class.node({ line: 1, text: 'block', block: true })
      end.to raise_error(ArgumentError, /block comment hashes are not yet supported/)
    end

    it 'raises for non-line comment styles' do
      expect do
        described_class.node({ line: 1, text: 'block' }, style: :c_style_block)
      end.to raise_error(ArgumentError, /only supports line-comment styles/)
    end
  end

  describe '.region' do
    it 'converts multiple tracked hashes into a Region' do
      region = described_class.region(
        kind: :leading,
        comments: [
          { line: 1, indent: 0, text: 'First', full_line: true, raw: '# First' },
          { line: 2, indent: 0, text: 'Second', full_line: true, raw: '# Second' }
        ]
      )

      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region).to be_leading
      expect(region.nodes.length).to eq(2)
      expect(region.normalized_content).to eq("First\nSecond")
      expect(region.metadata[:source]).to eq(:tracked_hash)
      expect(region.metadata[:tracked_hashes].length).to eq(2)
    end

    it 'preserves caller metadata' do
      region = described_class.region(
        kind: :inline,
        comments: [{ line: 5, indent: 8, text: 'Note', full_line: false }],
        metadata: { owner: :example },
        producer: :psych_merge
      )

      expect(region.metadata).to include(owner: :example, producer: :psych_merge, source: :tracked_hash)
    end

    it 'returns an empty region when comments are empty' do
      region = described_class.region(kind: :orphan, comments: [])

      expect(region).to be_orphan
      expect(region).to be_empty
      expect(region.metadata[:tracked_hashes]).to eq([])
    end
  end
end
