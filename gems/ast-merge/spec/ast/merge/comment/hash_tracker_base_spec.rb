# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::HashTrackerBase do
  # Concrete subclass for testing — implements extract_comments
  # using the standard full-line + inline hash-comment scanner.
  subject(:tracker) { tracker_class.new(source) }

  let(:tracker_class) do
    Class.new(described_class) do
      def initialize(source, tree_haver_comments: nil)
        @source = source
        super(source.lines.map(&:chomp), tree_haver_comments: tree_haver_comments)
      end

      private

      def inline_comment_regex
        /\s+#\s?(?<text>.*)$/
      end

      def extract_comments
        comments = []
        @lines.each_with_index do |line, idx|
          line_num = idx + 1
          if (m = line.match(self.class.superclass::FULL_LINE_COMMENT_REGEX))
            comments << {
              line: line_num,
              indent: m[:indent].length,
              text: m[:text].to_s.rstrip,
              full_line: true,
              raw: line
            }
          elsif (m = line.match(inline_comment_regex))
            before_hash = line.split('#').first
            if before_hash.count("'").even? && before_hash.count('"').even?
              comments << {
                line: line_num,
                indent: line.index('#'),
                text: m[:text].to_s.rstrip,
                full_line: false,
                raw: line
              }
            end
          end
        end
        comments
      end
    end
  end

  let(:source) do
    <<~SRC
      # Leading comment
      key: value
      # Another comment
      other: data # inline note
    SRC
  end

  describe '#comments' do
    it 'extracts all comments' do
      expect(tracker.comments.length).to eq(3)
    end

    it 'marks full-line comments correctly' do
      full_line = tracker.comments.select { |c| c[:full_line] }
      expect(full_line.length).to eq(2)
    end

    it 'marks inline comments correctly' do
      inline = tracker.comments.reject { |c| c[:full_line] }
      expect(inline.length).to eq(1)
      expect(inline.first[:text]).to eq('inline note')
    end
  end

  describe '#comment_at' do
    it 'returns comment at line 1' do
      comment = tracker.comment_at(1)
      expect(comment).not_to be_nil
      expect(comment[:text]).to eq('Leading comment')
    end

    it 'returns nil for non-comment line' do
      expect(tracker.comment_at(2)).to be_nil
    end

    it 'returns inline comment at line 4' do
      comment = tracker.comment_at(4)
      expect(comment).not_to be_nil
      expect(comment[:full_line]).to be false
    end
  end

  describe '#comment_nodes' do
    it 'returns Ast::Merge::Comment::Line instances' do
      nodes = tracker.comment_nodes
      expect(nodes).to all(be_a(Ast::Merge::Comment::Line))
      expect(nodes.length).to eq(3)
    end
  end

  describe '#comment_node_at' do
    it 'returns a comment node at a valid line' do
      node = tracker.comment_node_at(1)
      expect(node).to be_a(Ast::Merge::Comment::Line)
    end

    it 'returns nil for non-comment line' do
      expect(tracker.comment_node_at(2)).to be_nil
    end
  end

  describe '#comments_in_range' do
    it 'returns comments within the range' do
      result = tracker.comments_in_range(1..3)
      expect(result.length).to eq(2)
    end

    it 'returns empty array for range with no comments' do
      expect(tracker.comments_in_range(2..2)).to be_empty
    end
  end

  describe '#comment_region_for_range' do
    it 'returns a comment region' do
      region = tracker.comment_region_for_range(1..4, kind: :orphan)
      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.kind).to eq(:orphan)
    end

    it 'filters to full_line_only when requested' do
      region = tracker.comment_region_for_range(1..4, kind: :orphan, full_line_only: true)
      expect(region.nodes.length).to eq(2)
    end
  end

  describe '#leading_comments_before' do
    it 'collects leading full-line comments' do
      leading = tracker.leading_comments_before(2)
      expect(leading.length).to eq(1)
      expect(leading.first[:text]).to eq('Leading comment')
    end

    it 'returns empty when no leading comments exist' do
      expect(tracker.leading_comments_before(1)).to be_empty
    end
  end

  describe '#leading_comment_region_before' do
    it 'returns a leading region' do
      region = tracker.leading_comment_region_before(2)
      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.kind).to eq(:leading)
    end

    it 'returns nil when no leading comments' do
      expect(tracker.leading_comment_region_before(1)).to be_nil
    end
  end

  describe '#inline_comment_at' do
    it 'returns inline comment' do
      comment = tracker.inline_comment_at(4)
      expect(comment).not_to be_nil
      expect(comment[:full_line]).to be false
    end

    it 'returns nil for full-line comment line' do
      expect(tracker.inline_comment_at(1)).to be_nil
    end
  end

  describe '#inline_comment_region_at' do
    it 'returns an inline region' do
      region = tracker.inline_comment_region_at(4)
      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.kind).to eq(:inline)
    end

    it 'returns nil when no inline comment' do
      expect(tracker.inline_comment_region_at(1)).to be_nil
    end
  end

  describe '#comment_attachment_for' do
    let(:owner) { double('Owner', start_line: 4, end_line: 4) }

    it 'returns an Attachment' do
      attachment = tracker.comment_attachment_for(owner)
      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(attachment.owner).to eq(owner)
    end

    it 'includes leading and inline regions' do
      attachment = tracker.comment_attachment_for(owner)
      expect(attachment.leading_region).to be_a(Ast::Merge::Comment::Region)
      expect(attachment.inline_region).to be_a(Ast::Merge::Comment::Region)
    end

    context 'with adjacent trailing docs after the owner' do
      let(:source) do
        <<~SRC
          key: value # inline note
          # Trailing docs
        SRC
      end

      let(:owner) { double('Owner', start_line: 1, end_line: 1) }

      it 'includes a trailing region' do
        attachment = tracker.comment_attachment_for(owner)
        expect(attachment.trailing_region).to be_a(Ast::Merge::Comment::Region)
        expect(attachment.trailing_region.kind).to eq(:trailing)
        expect(attachment.trailing_region.normalized_content).to eq('Trailing docs')
      end
    end
  end

  describe '#full_line_comment?' do
    it 'returns true for full-line comment' do
      expect(tracker.full_line_comment?(1)).to be true
    end

    it 'returns false for non-comment line' do
      expect(tracker.full_line_comment?(2)).to be false
    end

    it 'returns false for inline comment' do
      expect(tracker.full_line_comment?(4)).to be false
    end
  end

  describe '#blank_line?' do
    let(:source) do
      <<~SRC
        # comment

        key: value
      SRC
    end

    it 'returns true for blank line' do
      expect(tracker.blank_line?(2)).to be true
    end

    it 'returns false for non-blank line' do
      expect(tracker.blank_line?(1)).to be false
    end

    it 'returns false for out-of-range lines' do
      expect(tracker.blank_line?(0)).to be false
      expect(tracker.blank_line?(100)).to be false
    end
  end

  describe '#line_at' do
    it 'returns the raw line' do
      expect(tracker.line_at(1)).to eq('# Leading comment')
    end

    it 'returns nil for out-of-range' do
      expect(tracker.line_at(0)).to be_nil
      expect(tracker.line_at(100)).to be_nil
    end
  end

  describe '#augment' do
    it 'returns a Comment::Augmenter' do
      augmenter = tracker.augment
      expect(augmenter).to be_a(Ast::Merge::Comment::Augmenter)
    end
  end

  describe 'tree_haver comment input' do
    let(:tree_comment_class) do
      Struct.new(:text, :start_line, :start_point, :attachment_hint, keyword_init: true)
    end

    it 'preserves trailing spaces from the tracked source line' do
      source = "# Leading comment  \nkey: value\n"
      tree_comment = tree_comment_class.new(
        text: '# Leading comment',
        start_line: 1,
        start_point: { column: 0 },
        attachment_hint: :leading
      )

      tracker = tracker_class.new(source, tree_haver_comments: [tree_comment])

      expect(tracker.comment_at(1)[:raw]).to eq('# Leading comment  ')
    end

    it 'raises when a tree_haver comment line is outside the tracked source' do
      source = "# Leading comment\n"
      tree_comment = tree_comment_class.new(
        text: '# Leading comment',
        start_line: 2,
        start_point: { column: 0 },
        attachment_hint: :leading
      )

      expect do
        tracker_class.new(source, tree_haver_comments: [tree_comment])
      end.to raise_error(
        described_class::MissingTrackedLineError,
        /could not be mapped back to tracker source lines/
      )
    end
  end

  describe 'extract_comments must be overridden' do
    it 'raises NotImplementedError for the base class directly' do
      expect do
        described_class.new(['# test'])
      end.to raise_error(NotImplementedError, /extract_comments must be implemented/)
    end
  end

  context 'with blank lines between comments' do
    let(:source) do
      <<~SRC
        # First block

        # Second block
        key: value
      SRC
    end

    it 'strips preamble when comments reach line 1 and a gap separates them' do
      leading = tracker.leading_comments_before(4)
      expect(leading.length).to eq(1)
      expect(leading.first[:text]).to eq('Second block')
    end
  end
end
