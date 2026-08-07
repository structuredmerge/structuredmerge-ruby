# frozen_string_literal: true

RSpec.describe Ast::Merge::EmitterBase do
  before { stub_const('LayoutOwner', Struct.new(:start_line, :end_line, :label, keyword_init: true)) }

  let(:emitter_class) do
    Class.new(described_class) do
      def emit_tracked_comment(comment)
        indent = ' ' * (comment[:indent] || 0)
        @lines << "#{indent}# #{comment[:text]}"
      end

      def emit_comment(text, inline: false)
        if inline
          return if @lines.empty?

          @lines[-1] = "#{@lines[-1]} # #{text}"
        else
          @lines << "#{current_indent}# #{text}"
        end
      end
    end
  end

  let(:emitter) { emitter_class.new }
  let(:before_owner) { LayoutOwner.new(start_line: 1, end_line: 1, label: :before) }
  let(:owner) { LayoutOwner.new(start_line: 3, end_line: 3, label: :owner) }
  let(:after_owner) { LayoutOwner.new(start_line: 4, end_line: 4, label: :after) }

  describe '#blank_lines?' do
    it 'returns true when every provided line is blank' do
      expect(emitter.blank_lines?(['', '  '])).to be(true)
    end

    it 'returns false when any provided line has content' do
      expect(emitter.blank_lines?(['', 'value'])).to be(false)
    end
  end

  describe '#ends_with_blank_line?' do
    it 'returns true when the output ends with a blank line' do
      emitter.emit_raw_lines(['value', ''])

      expect(emitter.ends_with_blank_line?).to be(true)
    end

    it 'returns false when the output is empty or ends with content' do
      expect(emitter.ends_with_blank_line?).to be(false)

      emitter.emit_raw_lines(['value'])

      expect(emitter.ends_with_blank_line?).to be(false)
    end
  end

  describe '#emit_comment_region' do
    it 'emits full-line regions and preserves blank gaps from source lines' do
      region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :leading,
        comments: [
          { line: 1, indent: 0, text: 'Header', full_line: true, raw: '# Header' },
          { line: 3, indent: 0, text: 'More docs', full_line: true, raw: '# More docs' }
        ]
      )

      emitter.emit_comment_region(region, source_lines: ['# Header', '', '# More docs'])

      expect(emitter.lines).to eq(['# Header', '', '# More docs'])
    end

    it 'appends inline regions to the current line' do
      region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :inline,
        comments: [
          { line: 2, indent: 11, text: 'inline note', full_line: false, raw: 'key: value # inline note' }
        ]
      )

      emitter.emit_raw_lines(['key: value'])
      emitter.emit_comment_region(region)

      expect(emitter.lines).to eq(['key: value # inline note'])
    end

    it 'preserves trailing spaces in inline comment text when emitting a shared region' do
      region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :inline,
        comments: [
          { line: 2, indent: 11, text: 'inline note', full_line: false, raw: 'key: value # inline note  ' }
        ]
      )

      emitter.emit_raw_lines(['key: value'])
      emitter.emit_comment_region(region)

      expect(emitter.lines).to eq(['key: value # inline note  '])
    end

    it 'raises when asked to emit a full-line region with unsupported node shapes' do
      region = Ast::Merge::Comment::Region.new(
        kind: :leading,
        nodes: [Struct.new(:normalized_content).new('normalized only')]
      )

      expect do
        emitter.emit_comment_region(region)
      end.to raise_error(
        Ast::Merge::EmitterBase::UnsupportedCommentNodeError,
        /without raw text/
      )
    end

    it 'raises when asked to emit an inline region with unsupported node shapes' do
      region = Ast::Merge::Comment::Region.new(
        kind: :inline,
        nodes: [Struct.new(:normalized_content).new('normalized only')]
      )

      emitter.emit_raw_lines(['key: value'])

      expect do
        emitter.emit_comment_region(region)
      end.to raise_error(
        Ast::Merge::EmitterBase::UnsupportedCommentNodeError,
        /without raw slice and style/
      )
    end

    it 'lets subclasses normalize region nodes before emission' do
      deduplicating_emitter_class = Class.new(emitter_class) do
        private

        def comment_region_nodes(region)
          nodes = Array(region.nodes)
          midpoint = nodes.length / 2
          midpoint.positive? && nodes.first(midpoint) == nodes.last(midpoint) ? nodes.first(midpoint) : nodes
        end
      end

      region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :leading,
        comments: [
          { line: 1, indent: 0, text: 'Header', full_line: true, raw: '# Header' },
          { line: 2, indent: 0, text: 'Details', full_line: true, raw: '# Details' },
          { line: 1, indent: 0, text: 'Header', full_line: true, raw: '# Header' },
          { line: 2, indent: 0, text: 'Details', full_line: true, raw: '# Details' }
        ]
      )

      deduplicating_emitter = deduplicating_emitter_class.new
      deduplicating_emitter.emit_comment_region(region)

      expect(deduplicating_emitter.lines).to eq(['# Header', '# Details'])
    end

    it 'lets subclasses align inline comment placement' do
      aligning_emitter_class = Class.new(emitter_class) do
        private

        def inline_comment_region_target_column(_region, current_line: _current_line)
          16
        end

        def emit_inline_comment_text(text, region:, target_column: nil)
          base = @lines[-1].to_s.rstrip
          @lines[-1] = base.ljust(target_column) + "# #{text}"
        end
      end

      region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :inline,
        comments: [
          { line: 1, indent: 16, text: 'note', full_line: false, raw: 'key = 1 # note' }
        ]
      )

      aligning_emitter = aligning_emitter_class.new
      aligning_emitter.emit_raw_lines(['key = 1'])
      aligning_emitter.emit_comment_region(region, inline: true)

      expect(aligning_emitter.lines).to eq(['key = 1         # note'])
    end
  end

  describe '#emit_comment_attachment' do
    it 'emits selected leading and inline regions from a shared attachment' do
      attachment = Ast::Merge::Comment::Attachment.new(
        leading_region: Ast::Merge::Comment::TrackedHashAdapter.region(
          kind: :leading,
          comments: [{ line: 1, indent: 0, text: 'Header', full_line: true, raw: '# Header' }]
        ),
        inline_region: Ast::Merge::Comment::TrackedHashAdapter.region(
          kind: :inline,
          comments: [{ line: 2, indent: 11, text: 'inline', full_line: false, raw: 'key: value # inline' }]
        )
      )

      emitter.emit_comment_attachment(attachment, leading: true, source_lines: ['# Header'])
      emitter.emit_raw_lines(['key: value'])
      emitter.emit_comment_attachment(attachment, leading: false, inline: true)

      expect(emitter.lines).to eq(['# Header', 'key: value # inline'])
    end

    it 'can also emit trailing and orphan regions in order' do
      attachment = Ast::Merge::Comment::Attachment.new(
        trailing_region: Ast::Merge::Comment::TrackedHashAdapter.region(
          kind: :trailing,
          comments: [{ line: 3, indent: 0, text: 'Trailing', full_line: true, raw: '# Trailing' }]
        ),
        orphan_regions: [
          Ast::Merge::Comment::TrackedHashAdapter.region(
            kind: :orphan,
            comments: [{ line: 5, indent: 0, text: 'Orphan', full_line: true, raw: '# Orphan' }]
          )
        ]
      )

      emitter.emit_raw_lines(['key: value'])
      emitter.emit_comment_attachment(
        attachment,
        leading: false,
        trailing: true,
        orphan: true,
        source_lines: ['key: value', '', '# Trailing', '', '# Orphan']
      )

      expect(emitter.lines).to eq(['key: value', '# Trailing', '', '# Orphan'])
    end
  end

  describe '#emit_layout_gap' do
    it 'emits controller-owned interstitial gaps for the requesting owner' do
      gap = Ast::Merge::Layout::Gap.new(
        kind: :interstitial,
        start_line: 2,
        end_line: 3,
        lines: ['', ''],
        before_owner: before_owner,
        after_owner: after_owner
      )

      emitted_line = emitter.emit_layout_gap(gap, owner: after_owner)

      expect(emitted_line).to eq(3)
      expect(emitter.lines).to eq(['', ''])
    end

    it 'does not emit shared gaps for a non-controlling owner' do
      gap = Ast::Merge::Layout::Gap.new(
        kind: :interstitial,
        start_line: 2,
        end_line: 2,
        lines: [''],
        before_owner: before_owner,
        after_owner: after_owner
      )

      emitted_line = emitter.emit_layout_gap(gap, owner: before_owner)

      expect(emitted_line).to be_nil
      expect(emitter.lines).to eq([])
    end

    it 'lets the fallback owner emit when the primary controller was removed' do
      gap = Ast::Merge::Layout::Gap.new(
        kind: :interstitial,
        start_line: 2,
        end_line: 2,
        lines: [''],
        before_owner: before_owner,
        after_owner: after_owner
      )

      emitted_line = emitter.emit_layout_gap(gap, owner: before_owner, removed_owners: [after_owner])

      expect(emitted_line).to eq(2)
      expect(emitter.lines).to eq([''])
    end

    it 'preserves exact whitespace-only lines from source lines' do
      gap = Ast::Merge::Layout::Gap.new(
        kind: :preamble,
        start_line: 1,
        end_line: 2,
        lines: ['', ''],
        after_owner: owner
      )

      emitter.emit_layout_gap(gap, owner: owner, source_lines: ['  ', "\t", 'body'])

      expect(emitter.lines).to eq(['  ', "\t"])
    end

    it 'can resume emitting a gap after earlier source lines were already emitted' do
      gap = Ast::Merge::Layout::Gap.new(
        kind: :preamble,
        start_line: 2,
        end_line: 4,
        lines: ['', '', ''],
        after_owner: owner
      )

      emitted_line = emitter.emit_layout_gap(gap, owner: owner, last_emitted_source_line: 2)

      expect(emitted_line).to eq(4)
      expect(emitter.lines).to eq(['', ''])
    end
  end

  describe '#emit_layout_attachment' do
    it 'emits selected leading and trailing gaps from a shared attachment' do
      attachment = Ast::Merge::Layout::Attachment.new(
        owner: owner,
        leading_gap: Ast::Merge::Layout::Gap.new(
          kind: :preamble,
          start_line: 1,
          end_line: 2,
          lines: ['', ''],
          after_owner: owner
        ),
        trailing_gap: Ast::Merge::Layout::Gap.new(
          kind: :postlude,
          start_line: 4,
          end_line: 5,
          lines: ['', ''],
          before_owner: owner
        )
      )

      emitted_lines = emitter.emit_layout_attachment(attachment, leading: true, trailing: true)

      expect(emitted_lines).to eq({ leading: 2, trailing: 5 })
      expect(emitter.lines).to eq(['', '', '', ''])
    end
  end

  describe 'layout-owned removed owners' do
    it 'prunes an already emitted leading gap controlled by a removed owner' do
      result = Ast::Merge::MergeResultBase.new
      result.content = "before\n"
      gap = Ast::Merge::Layout::Gap.new(
        kind: :interstitial,
        start_line: 2,
        end_line: 2,
        lines: [''],
        before_owner: before_owner,
        after_owner: owner
      )
      attachment = Ast::Merge::Layout::Attachment.new(owner: owner, leading_gap: gap)

      removed = Ast::Merge::Layout.prune_emitted_leading_gap_for_removed_owner(
        result: result,
        attachment: attachment
      )

      expect(removed).to eq(1)
      expect(result.lines).to eq(['before'])
    end

    it 'normalizes impossible repeated blank runs after ownership-aware emission' do
      result = Ast::Merge::MergeResultBase.new
      result.content = "before\n\n\nafter\n"

      removed = result.normalize_blank_line_runs!(max: 1)

      expect(removed).to eq(1)
      expect(result.to_s).to eq("before\n\nafter\n")
    end
  end
end
