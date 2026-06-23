# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::Augmenter do
  before { stub_const('Owner', Struct.new(:start_line, :end_line, :label, keyword_init: true)) }

  describe '.call' do
    it 'builds a passive augmenter result' do
      augmenter = described_class.call(lines: [], comments: [], owners: [])

      expect(augmenter).to be_a(described_class)
      expect(augmenter.capability).to be_source_augmented
      expect(augmenter.capability.details).to include(source: :tracked_hash, owner_count: 0, comment_count: 0)
    end
  end

  describe 'attachment inference' do
    let(:owners) do
      [
        Owner.new(start_line: 4, end_line: 4, label: :defaults),
        Owner.new(start_line: 7, end_line: 7, label: :tokens)
      ]
    end

    let(:lines) do
      [
        '# Header comment',
        '',
        '# Defaults comment',
        'defaults:',
        '  key: value',
        '# Tokens comment',
        'tokens: # inline tokens',
        '# trailing doc comment'
      ]
    end

    let(:comments) do
      [
        { line: 1, indent: 0, text: 'Header comment', full_line: true, raw: '# Header comment' },
        { line: 3, indent: 0, text: 'Defaults comment', full_line: true, raw: '# Defaults comment' },
        { line: 6, indent: 0, text: 'Tokens comment', full_line: true, raw: '# Tokens comment' },
        { line: 7, indent: 9, text: 'inline tokens', full_line: false, raw: 'tokens: # inline tokens' },
        { line: 8, indent: 0, text: 'trailing doc comment', full_line: true, raw: '# trailing doc comment' }
      ]
    end

    it 'infers leading, inline, and trailing comments without duplicating them into postlude' do
      augmenter = described_class.new(lines: lines, comments: comments, owners: owners)

      first_attachment = augmenter.attachment_for(owners.first)
      second_attachment = augmenter.attachment_for(owners.last)

      # Line-1 "Header comment" is preamble (gap separates it from node)
      expect(augmenter.preamble_region).not_to be_nil
      expect(augmenter.preamble_region.normalized_content).to eq('Header comment')

      expect(first_attachment.leading_region).not_to be_nil
      expect(first_attachment.leading_region).to be_leading
      expect(first_attachment.leading_region.nodes.map(&:class)).to eq([
                                                                         Ast::Merge::Comment::Line
                                                                       ])
      expect(first_attachment.leading_region.normalized_content).to eq('Defaults comment')

      expect(second_attachment.leading_region).not_to be_nil
      expect(second_attachment.leading_region.normalized_content).to eq('Tokens comment')

      expect(second_attachment.inline_region).not_to be_nil
      expect(second_attachment.inline_region).to be_inline
      expect(second_attachment.inline_region.normalized_content).to eq('inline tokens')

      expect(second_attachment.trailing_region).not_to be_nil
      expect(second_attachment.trailing_region).to be_trailing
      expect(second_attachment.trailing_region.normalized_content).to eq('trailing doc comment')

      expect(augmenter.postlude_region).to be_nil
    end

    it 'keeps separated comments after the last owner as postlude instead of trailing ownership' do
      augmenter = described_class.new(
        lines: [
          'tokens: value',
          '',
          '# postlude docs'
        ],
        comments: [
          { line: 3, indent: 0, text: 'postlude docs', full_line: true, raw: '# postlude docs' }
        ],
        owners: [Owner.new(start_line: 1, end_line: 1, label: :tokens)]
      )

      attachment = augmenter.attachment_for(augmenter.owners.first)

      expect(attachment.trailing_region).to be_nil
      expect(augmenter.postlude_region).not_to be_nil
      expect(augmenter.postlude_region.normalized_content).to eq('postlude docs')
    end

    it 'wires shared layout gaps onto comment attachments when owners are separated by blank lines' do
      gap_owners = [
        Owner.new(start_line: 2, end_line: 2, label: :first),
        Owner.new(start_line: 5, end_line: 5, label: :second)
      ]

      augmenter = described_class.new(
        lines: [
          '# First docs',
          'first:',
          '',
          '',
          'second:'
        ],
        comments: [
          { line: 1, indent: 0, text: 'First docs', full_line: true, raw: '# First docs' }
        ],
        owners: gap_owners
      )

      first_attachment = augmenter.attachment_for(gap_owners.first)
      second_attachment = augmenter.attachment_for(gap_owners.last)

      expect(first_attachment.trailing_gap).not_to be_nil
      expect(first_attachment.trailing_gap.start_line).to eq(3)
      expect(first_attachment.trailing_gap.end_line).to eq(4)
      expect(second_attachment.leading_gap).to equal(first_attachment.trailing_gap)
    end

    it 'preserves blank lines inside a leading region span' do
      owner = Owner.new(start_line: 5, end_line: 5, label: :settings)
      augmenter = described_class.new(
        lines: [
          'intro',
          '# First leading',
          '',
          '# Second leading',
          'settings:'
        ],
        comments: [
          { line: 2, indent: 0, text: 'First leading', full_line: true, raw: '# First leading' },
          { line: 4, indent: 0, text: 'Second leading', full_line: true, raw: '# Second leading' }
        ],
        owners: [owner]
      )

      leading = augmenter.attachment_for(owner).leading_region

      expect(leading.nodes.map(&:class)).to eq([
                                                 Ast::Merge::Comment::Line,
                                                 Ast::Merge::Comment::Empty,
                                                 Ast::Merge::Comment::Line
                                               ])
      expect(leading.normalized_content).to eq("First leading\n\nSecond leading")
    end

    it 'marks a gap-separated leading region as floating' do
      owner = Owner.new(start_line: 5, end_line: 5, label: :settings)
      augmenter = described_class.new(
        lines: [
          'intro',
          '# Floating comment block',
          '',
          '',
          'settings:'
        ],
        comments: [
          { line: 2, indent: 0, text: 'Floating comment block', full_line: true, raw: '# Floating comment block' }
        ],
        owners: [owner]
      )

      leading = augmenter.attachment_for(owner).leading_region
      expect(leading).to be_floating
    end

    it 'marks an adjacent leading region as non-floating' do
      owner = Owner.new(start_line: 3, end_line: 3, label: :settings)
      augmenter = described_class.new(
        lines: [
          'intro',
          '# Attached comment',
          'settings:'
        ],
        comments: [
          { line: 2, indent: 0, text: 'Attached comment', full_line: true, raw: '# Attached comment' }
        ],
        owners: [owner]
      )

      leading = augmenter.attachment_for(owner).leading_region
      expect(leading).not_to be_floating
    end

    it 'exposes attachments by owner' do
      augmenter = described_class.new(lines: lines, comments: comments, owners: owners)

      expect(augmenter.attachments_by_owner.keys).to eq(owners)
      expect(augmenter.attachment_for(owners.first)).to be_a(Ast::Merge::Comment::Attachment)
    end
  end

  describe 'preamble and orphan inference' do
    let(:owners) do
      [
        Owner.new(start_line: 3, end_line: 3, label: :first),
        Owner.new(start_line: 7, end_line: 7, label: :second)
      ]
    end

    let(:lines) do
      [
        '# Document header',
        'intro text',
        'first:',
        'bridge text',
        '# Orphan between owners',
        'more bridge text',
        'second:'
      ]
    end

    let(:comments) do
      [
        { line: 1, indent: 0, text: 'Document header', full_line: true, raw: '# Document header' },
        { line: 5, indent: 0, text: 'Orphan between owners', full_line: true, raw: '# Orphan between owners' }
      ]
    end

    it 'distinguishes preamble from later orphan regions' do
      augmenter = described_class.new(lines: lines, comments: comments, owners: owners)

      preamble = augmenter.preamble_region
      expect(preamble).not_to be_nil
      expect(preamble).to be_preamble
      expect(preamble&.normalized_content).to eq('Document header')

      expect(augmenter.orphan_regions.size).to eq(1)
      expect(augmenter.orphan_regions.first).to be_orphan
      expect(augmenter.orphan_regions.first.normalized_content).to eq('Orphan between owners')
    end
  end

  describe 'validation' do
    it 'raises when an owner does not expose start_line and end_line' do
      expect do
        described_class.new(lines: [], comments: [], owners: [Object.new])
      end.to raise_error(ArgumentError, /owner must respond to #start_line and #end_line/)
    end

    it 'raises when a comment is not a hash' do
      expect do
        described_class.new(lines: [], comments: ['not a hash'], owners: [])
      end.to raise_error(ArgumentError, /comment must be a Hash/)
    end
  end
end
