# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rbs::Merge::CommentTracker do
  let(:owner_struct) { Struct.new(:start_line, :end_line, keyword_init: true) }

  describe '#initialize' do
    it 'extracts full-line hash comments with indentation metadata' do
      lines = [
        '# top level',
        'class Foo',
        '  # nested note',
        '  def bar: () -> void'
      ]

      tracker = described_class.new(lines)

      expect(tracker.comments).to match([
                                          include(line: 1, indent: 0, text: 'top level', full_line: true,
                                                  raw: '# top level'),
                                          include(line: 3, indent: 2, text: 'nested note', full_line: true,
                                                  raw: '  # nested note')
                                        ])
    end

    it 'ignores inline hash characters and non-comment lines' do
      lines = [
        'class Foo # not tracked inline',
        'type tag = "#still not a comment"'
      ]

      tracker = described_class.new(lines)

      expect(tracker.comments).to be_empty
    end

    it 'ignores freeze control markers for the default freeze token' do
      lines = [
        '# rbs-merge:freeze',
        '# real docs',
        '# rbs-merge:unfreeze'
      ]

      tracker = described_class.new(lines)

      expect(tracker.comments.map { |comment| [comment[:line], comment[:text]] }).to eq([
                                                                                          [2, 'real docs']
                                                                                        ])
    end

    it 'ignores reason-bearing freeze control markers for the default freeze token' do
      lines = [
        '# rbs-merge:freeze keep local customization',
        '# real docs',
        '# rbs-merge:unfreeze resume normal merge'
      ]

      tracker = described_class.new(lines)

      expect(tracker.comments.map { |comment| [comment[:line], comment[:text]] }).to eq([
                                                                                          [2, 'real docs']
                                                                                        ])
    end

    it 'ignores freeze control markers for a custom freeze token' do
      lines = [
        '# custom-token:freeze',
        '# real docs',
        '# custom-token:unfreeze'
      ]

      tracker = described_class.new(lines, freeze_token: 'custom-token')

      expect(tracker.comments.map { |comment| [comment[:line], comment[:text]] }).to eq([
                                                                                          [2, 'real docs']
                                                                                        ])
    end

    it 'ignores reason-bearing freeze control markers for a custom freeze token' do
      lines = [
        '# custom-token:freeze keep local customization',
        '# real docs',
        '# custom-token:unfreeze resume normal merge'
      ]

      tracker = described_class.new(lines, freeze_token: 'custom-token')

      expect(tracker.comments.map { |comment| [comment[:line], comment[:text]] }).to eq([
                                                                                          [2, 'real docs']
                                                                                        ])
    end
  end

  describe 'shared Ast::Merge comment accessors' do
    let(:lines) do
      [
        '# preamble',
        '',
        '# docs line 1',
        '# docs line 2',
        'class Foo',
        'end',
        '',
        '# postlude'
      ]
    end

    let(:tracker) { described_class.new(lines) }

    it 'builds shared comment nodes and line lookup' do
      expect(tracker.comment_nodes).to all(be_a(Ast::Merge::Comment::Line))
      expect(tracker.comment_nodes.map(&:line_number)).to eq([1, 3, 4, 8])
      expect(tracker.comment_node_at(3)&.content).to eq('docs line 1')
      expect(tracker.comment_node_at(5)).to be_nil
    end

    it 'builds shared comment regions for a range' do
      region = tracker.comment_region_for_range(1..4, kind: :leading)

      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.leading?).to be(true)
      expect(region.nodes.map(&:line_number)).to eq([1, 3, 4])
      expect(region.normalized_content).to eq("preamble\ndocs line 1\ndocs line 2")
      expect(region.metadata[:range]).to eq(1..4)
      expect(region.metadata[:full_line_only]).to be(false)
    end
  end

  describe '#comments_in_range' do
    it 'returns tracked comments in the requested line range' do
      tracker = described_class.new([
                                      '# one',
                                      'class Foo',
                                      '# three',
                                      '# four'
                                    ])

      expect(tracker.comments_in_range(3..4).map { |comment| comment[:text] }).to eq(%w[three four])
    end
  end

  describe '#leading_comments_before' do
    it 'strips line-1 preamble, keeps only post-gap comments' do
      tracker = described_class.new([
                                      '# preamble',
                                      '',
                                      '# class docs',
                                      'class Foo'
                                    ])

      leading = tracker.leading_comments_before(4)

      # Line-1 comment separated by a gap is preamble, not a leading comment
      expect(leading.map { |comment| comment[:line] }).to eq([3])
      expect(leading.map { |comment| comment[:text] }).to eq(['class docs'])
    end

    it 'stops when it reaches a non-comment line' do
      tracker = described_class.new([
                                      '# preamble',
                                      'class Earlier',
                                      '',
                                      '# class docs',
                                      'class Foo'
                                    ])

      leading = tracker.leading_comments_before(5)

      expect(leading.map { |comment| comment[:line] }).to eq([4])
      expect(leading.map { |comment| comment[:text] }).to eq(['class docs'])
    end

    it 'does not treat freeze markers as attachable leading docs' do
      tracker = described_class.new([
                                      '# rbs-merge:freeze',
                                      'type custom = String',
                                      '# rbs-merge:unfreeze',
                                      'class Foo'
                                    ])

      expect(tracker.leading_comments_before(4)).to be_empty
    end
  end

  describe '#leading_comment_region_before' do
    it 'returns a leading region when comments are present' do
      tracker = described_class.new([
                                      '# docs',
                                      'class Foo'
                                    ])

      region = tracker.leading_comment_region_before(2)

      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.leading?).to be(true)
      expect(region.nodes.map(&:line_number)).to eq([1])
    end

    it 'returns nil when no leading comments are present' do
      tracker = described_class.new([
                                      'class Foo'
                                    ])

      expect(tracker.leading_comment_region_before(1)).to be_nil
    end
  end

  describe '#comment_attachment_for' do
    it 'attaches leading comments using the owner start line' do
      tracker = described_class.new([
                                      '# docs',
                                      'class Foo',
                                      'end'
                                    ])
      owner = owner_struct.new(start_line: 2, end_line: 3)

      attachment = tracker.comment_attachment_for(owner, role: :declaration)

      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(attachment.leading_region&.normalized_content).to eq('docs')
      expect(attachment.metadata[:line_num]).to eq(2)
      expect(attachment.metadata[:role]).to eq(:declaration)
      expect(attachment.metadata[:source]).to eq(:comment_tracker)
    end

    it 'supports an explicit line number override for owners without start_line' do
      tracker = described_class.new([
                                      '# docs',
                                      'class Foo'
                                    ])
      owner = Object.new

      attachment = tracker.comment_attachment_for(owner, line_num: 2)

      expect(attachment.leading_region&.nodes&.map(&:line_number)).to eq([1])
      expect(attachment.metadata[:line_num]).to eq(2)
    end

    it 'returns an empty attachment when the owner line cannot be resolved' do
      tracker = described_class.new(['# docs', 'class Foo'])
      owner = Object.new

      attachment = tracker.comment_attachment_for(owner)

      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(attachment).to be_empty
      expect(attachment.metadata[:line_num]).to be_nil
    end

    it 'does not attach freeze control markers to the declaration after a freeze block' do
      tracker = described_class.new([
                                      '# rbs-merge:freeze',
                                      'type custom = String',
                                      '# rbs-merge:unfreeze',
                                      'class Foo',
                                      'end'
                                    ])
      owner = owner_struct.new(start_line: 4, end_line: 5)

      attachment = tracker.comment_attachment_for(owner)

      expect(attachment.leading_region).to be_nil
      expect(attachment).to be_empty
    end

    it 'does not attach reason-bearing freeze control markers to the declaration after a freeze block' do
      tracker = described_class.new([
                                      '# rbs-merge:freeze keep local customization',
                                      'type custom = String',
                                      '# rbs-merge:unfreeze resume normal merge',
                                      'class Foo',
                                      'end'
                                    ])
      owner = owner_struct.new(start_line: 4, end_line: 5)

      attachment = tracker.comment_attachment_for(owner)

      expect(attachment.leading_region).to be_nil
      expect(attachment).to be_empty
    end

    it 'attaches docs immediately above a custom-token freeze marker to the freeze block owner' do
      tracker = described_class.new(
        [
          '# keep custom freeze docs',
          '# custom-token:freeze',
          'type custom = String',
          '# custom-token:unfreeze',
          'class Foo',
          'end'
        ],
        freeze_token: 'custom-token'
      )
      freeze_owner = owner_struct.new(start_line: 2, end_line: 4)
      following_owner = owner_struct.new(start_line: 5, end_line: 6)

      freeze_attachment = tracker.comment_attachment_for(freeze_owner)
      following_attachment = tracker.comment_attachment_for(following_owner)

      expect(freeze_attachment.leading_region&.normalized_content).to eq('keep custom freeze docs')
      expect(following_attachment.leading_region).to be_nil
    end

    it 'attaches docs immediately above a reason-bearing freeze marker to the freeze block owner' do
      tracker = described_class.new([
                                      '# keep freeze docs',
                                      '# rbs-merge:freeze keep local customization',
                                      'type custom = String',
                                      '# rbs-merge:unfreeze resume normal merge',
                                      'class Foo',
                                      'end'
                                    ])
      freeze_owner = owner_struct.new(start_line: 2, end_line: 4)
      following_owner = owner_struct.new(start_line: 5, end_line: 6)

      freeze_attachment = tracker.comment_attachment_for(freeze_owner)
      following_attachment = tracker.comment_attachment_for(following_owner)

      expect(freeze_attachment.leading_region&.normalized_content).to eq('keep freeze docs')
      expect(following_attachment.leading_region).to be_nil
    end

    it 'attaches docs immediately above a reason-bearing custom-token freeze marker to the freeze block owner' do
      tracker = described_class.new(
        [
          '# keep custom freeze docs',
          '# custom-token:freeze keep local customization',
          'type custom = String',
          '# custom-token:unfreeze resume normal merge',
          'class Foo',
          'end'
        ],
        freeze_token: 'custom-token'
      )
      freeze_owner = owner_struct.new(start_line: 2, end_line: 4)
      following_owner = owner_struct.new(start_line: 5, end_line: 6)

      freeze_attachment = tracker.comment_attachment_for(freeze_owner)
      following_attachment = tracker.comment_attachment_for(following_owner)

      expect(freeze_attachment.leading_region&.normalized_content).to eq('keep custom freeze docs')
      expect(following_attachment.leading_region).to be_nil
    end
  end

  describe '#blank_line?' do
    it 'detects blank lines and out-of-range lookups' do
      tracker = described_class.new(['# docs', '', 'class Foo'])

      expect(tracker.blank_line?(1)).to be(false)
      expect(tracker.blank_line?(2)).to be(true)
      expect(tracker.blank_line?(0)).to be(false)
      expect(tracker.blank_line?(10)).to be(false)
    end
  end

  describe '#augment' do
    it 'builds a source-augmented shared augmenter with attachments and postlude comments' do
      lines = [
        '# docs',
        'class Foo',
        'end',
        '',
        '# postlude'
      ]
      tracker = described_class.new(lines)
      owner = owner_struct.new(start_line: 2, end_line: 3)

      augmenter = tracker.augment(owners: [owner], repository: :rbs_merge)

      expect(augmenter).to be_a(Ast::Merge::Comment::Augmenter)
      expect(augmenter.capability).to be_a(Ast::Merge::Comment::Capability)
      expect(augmenter.capability.source_augmented?).to be(true)
      expect(augmenter.capability.details[:repository]).to eq(:rbs_merge)
      expect(augmenter.attachment_for(owner).leading_region&.normalized_content).to eq('docs')
      expect(augmenter.postlude_region&.normalized_content).to eq('postlude')
    end
  end
end
