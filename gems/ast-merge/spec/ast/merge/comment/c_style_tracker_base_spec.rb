# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::CStyleTrackerBase do
  subject(:tracker) { tracker_class.new(source) }

  let(:tracker_class) do
    Class.new(described_class) do
      def initialize(source)
        @source = source
        super(source.lines.map(&:chomp))
      end
    end
  end

  let(:source) do
    <<~SRC
      // Header docs
      {
        /* This is a
           multi-line
           block comment */
        "key": "value" // inline note
      }
    SRC
  end

  describe '#comments' do
    it 'extracts line, block, and inline comments' do
      expect(tracker.comments.map { |comment| [comment[:block], comment[:full_line]] }).to eq([
                                                                                                [false, true],
                                                                                                [true, true],
                                                                                                [false, false]
                                                                                              ])
    end

    it 'preserves the raw inline comment slice exactly' do
      source = <<~SRC
        {
          "key": "value" // inline note#{'  '}
        }
      SRC

      tracker = tracker_class.new(source)
      inline_comment = tracker.comments.find { |comment| !comment[:full_line] }

      expect(inline_comment).to include(
        indent: 17,
        raw: '// inline note  '
      )
    end

    it 'tracks end_line for multi-line block comments' do
      block_comment = tracker.comments.find { |comment| comment[:block] }
      expect(block_comment).to include(line: 3, end_line: 5)
    end
  end

  describe '#comment_at' do
    it 'returns the leading line comment at its own line' do
      expect(tracker.comment_at(1)).to include(text: 'Header docs', block: false)
    end

    it 'returns the same multi-line block comment for covered lines' do
      expect(tracker.comment_at(4)).to include(block: true, line: 3, end_line: 5)
      expect(tracker.comment_at(5)).to include(block: true, line: 3, end_line: 5)
    end
  end

  describe '#comments_in_range' do
    it 'returns comments whose spans overlap the range' do
      comments = tracker.comments_in_range(4..4)
      expect(comments.map { |comment| [comment[:line], comment[:end_line], comment[:block]] }).to eq([
                                                                                                       [3, 5, true]
                                                                                                     ])
    end
  end

  describe '#leading_comments_before' do
    it 'walks backward by whole multi-line block spans' do
      leading = tracker.leading_comments_before(6)
      expect(leading.map { |comment| [comment[:line], comment[:end_line], comment[:block]] }).to eq([
                                                                                                      [3, 5, true]
                                                                                                    ])
    end
  end

  describe 'shared line-comment adapter boundary' do
    it 'exposes only line comments through shared nodes' do
      expect(tracker.comment_nodes.map(&:content)).to eq(['Header docs', 'inline note'])
      expect(tracker.comment_node_at(4)).to be_nil
    end

    it 'exposes only line comments through shared regions' do
      region = tracker.comment_region_for_range(1..6, kind: :orphan)
      expect(region.nodes.map(&:content)).to eq(['Header docs', 'inline note'])
      expect(region.metadata[:tracked_hashes].map { |comment| comment[:block] }).to eq([false, false])
    end
  end

  describe '#comment_attachment_for' do
    let(:owner) { Struct.new(:start_line, :end_line).new(6, 6) }

    it 'filters block leading comments while preserving shared inline comments' do
      attachment = tracker.comment_attachment_for(owner)
      expect(attachment.leading_region).to be_nil
      expect(attachment.inline_region).not_to be_nil
      expect(attachment.inline_region.normalized_content).to eq('inline note')
    end

    it 'preserves trailing spaces in shared inline region text' do
      source = <<~SRC
        {
          "key": "value" // inline note#{'  '}
        }
      SRC

      tracker = tracker_class.new(source)
      owner = Struct.new(:start_line, :end_line).new(2, 2)
      attachment = tracker.comment_attachment_for(owner)

      expect(attachment.inline_region.text).to eq('// inline note  ')
    end

    context 'with an adjacent trailing line comment after the owner' do
      let(:source) do
        <<~SRC
          {
            "key": "value"
            // trailing docs
          }
        SRC
      end

      let(:owner) { Struct.new(:start_line, :end_line).new(2, 2) }

      it 'includes a trailing region' do
        attachment = tracker.comment_attachment_for(owner)
        expect(attachment.trailing_region).not_to be_nil
        expect(attachment.trailing_region.kind).to eq(:trailing)
        expect(attachment.trailing_region.normalized_content).to eq('trailing docs')
      end
    end
  end

  describe '#augment' do
    let(:owner) { Struct.new(:start_line, :end_line).new(2, 6) }

    it 'reports only line comments to the shared augmenter while preserving counts' do
      augmenter = tracker.augment(owners: [owner])

      expect(augmenter.capability.source_augmented?).to be true
      expect(augmenter.capability.details[:style]).to eq(:c_style_line)
      expect(augmenter.capability.details).to include(total_comment_count: 3, block_comment_count: 1)
    end
  end

  describe 'extract_comments must be overrideable' do
    it 'can be instantiated directly with source lines' do
      expect { described_class.new(['// test']) }.not_to raise_error
    end
  end
end
