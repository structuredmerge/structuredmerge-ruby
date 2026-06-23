# frozen_string_literal: true

RSpec.describe Ast::Merge::FileAnalyzable do
  let(:analysis_class) do
    Class.new do
      include Ast::Merge::FileAnalyzable

      def initialize(source, statements: [])
        @source = source
        @lines = source.lines.map(&:chomp)
        @freeze_token = 'test-merge'
        @signature_generator = nil
        @statements = statements
      end

      def compute_node_signature(node)
        [:owner, node.start_line, node.end_line]
      end
    end
  end

  let(:owner) { Struct.new(:start_line, :end_line).new(2, 2) }
  let(:analysis) { analysis_class.new("header\nbody\nfooter", statements: [owner]) }

  describe 'default shared comment hooks' do
    it 'reports no comment capability by default' do
      expect(analysis.comment_capability).to be_a(Ast::Merge::Comment::Capability)
      expect(analysis.comment_capability.none?).to be(true)
    end

    it 'returns no comment nodes' do
      expect(analysis.comment_nodes).to eq([])
      expect(analysis.comment_node_at(2)).to be_nil
    end

    it 'builds a shared source-augmented support style' do
      support_style = analysis.shared_comment_support_style(
        source: :fixture_source,
        style: :hash_comment,
        read_strategy: :source_augmented_portable_write,
        capability: :full
      )

      expect(support_style.source_augmented_portable_write?).to be(true)
      expect(support_style.details[:style]).to eq(:hash_comment)
      expect(support_style.details[:source]).to eq(:fixture_source)
    end

    it 'builds a shared native-read support style' do
      support_style = analysis.shared_comment_support_style(
        source: :fixture_native,
        style: :hash_comment,
        read_strategy: :native_read_portable_write,
        capability: :full
      )

      expect(support_style.native_read_portable_write?).to be(true)
      expect(support_style.details[:style]).to eq(:hash_comment)
      expect(support_style.details[:source]).to eq(:fixture_native)
    end

    it 'rejects old source-augmented support-style names' do
      expect do
        analysis.shared_comment_support_style(
          source: :fixture_source,
          style: :hash_comment,
          read_strategy: :source_augmented_synthetic,
          capability: :full
        )
      end.to raise_error(ArgumentError, /Unknown comment support read strategy/)
    end

    it 'rejects old native-read support-style names' do
      expect do
        analysis.shared_comment_support_style(
          source: :fixture_native,
          style: :hash_comment,
          read_strategy: :native_read_synthetic_write,
          capability: :full
        )
      end.to raise_error(ArgumentError, /Unknown comment support read strategy/)
    end

    it 'builds source-augmented portable-write support styles' do
      support_style = analysis.shared_comment_support_style(
        source: :fixture_source,
        style: :hash_comment,
        read_strategy: :source_augmented_portable_write,
        capability: :full
      )

      expect(support_style).to be_source_augmented_portable_write
    end

    it 'builds native-read portable-write support styles' do
      support_style = analysis.shared_comment_support_style(
        source: :fixture_native,
        style: :hash_comment,
        read_strategy: :native_read_portable_write,
        capability: :full
      )

      expect(support_style).to be_native_read_portable_write
    end

    it 'raises for an unknown shared support-style strategy' do
      expect do
        analysis.shared_comment_support_style(
          source: :fixture_source,
          style: :hash_comment,
          read_strategy: :mystery_strategy,
          capability: :full
        )
      end.to raise_error(ArgumentError, /Unknown comment support read strategy/)
    end

    it 'returns an empty region for any requested range' do
      region = analysis.comment_region_for_range(1..2, kind: :leading, repository: :ast_merge)

      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.kind).to eq(:leading)
      expect(region.empty?).to be(true)
      expect(region.metadata[:source]).to eq(:file_analyzable_default)
      expect(region.metadata[:repository]).to eq(:ast_merge)
    end

    it 'returns an empty attachment for any owner' do
      attachment = analysis.comment_attachment_for(owner, repository: :ast_merge)

      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(attachment.owner).to eq(owner)
      expect(attachment.empty?).to be(true)
      expect(attachment.metadata[:source]).to eq(:file_analyzable_default)
      expect(attachment.metadata[:repository]).to eq(:ast_merge)
    end

    it 'wires adjacent layout gaps into the default comment attachment' do
      owner_with_gap = Struct.new(:start_line, :end_line).new(3, 3)
      gap_analysis = analysis_class.new("header\n\nbody\n", statements: [owner_with_gap])

      attachment = gap_analysis.comment_attachment_for(owner_with_gap)

      expect(attachment.leading_gap).not_to be_nil
      expect(attachment.leading_gap).to be_preamble
      expect(attachment.layout_gaps).to eq([attachment.leading_gap])
      expect(attachment).to be_empty
    end

    it 'can merge inferred layout gaps into an existing comment attachment' do
      owner_with_gap = Struct.new(:start_line, :end_line).new(3, 3)
      gap_analysis = analysis_class.new("header\n\nbody\n", statements: [owner_with_gap])
      comment_attachment = Ast::Merge::Comment::Attachment.new(
        owner: owner_with_gap,
        leading_region: Ast::Merge::Comment::Region.new(
          kind: :leading,
          nodes: [Ast::Merge::Comment::Line.new(text: '# docs', line_number: 1)]
        ),
        metadata: { source: :custom_tracker }
      )

      attachment = gap_analysis.merge_comment_attachment_with_layout(owner_with_gap, comment_attachment,
                                                                     repository: :ast_merge)

      expect(attachment.leading_region&.normalized_content).to eq('docs')
      expect(attachment.leading_gap).not_to be_nil
      expect(attachment.leading_gap).to be_preamble
      expect(attachment.metadata[:source]).to eq(:custom_tracker)
      expect(attachment.metadata[:repository]).to eq(:ast_merge)
    end

    it 'reports the default shared attachment strategy' do
      expect(analysis.comment_attachment_strategy).to eq(:layout_only)
    end

    it 'dispatches the layout-only shared attachment strategy' do
      allow(analysis).to receive(:merge_comment_attachment_with_layout)
        .with(owner, nil, repository: :ast_merge)
        .and_return(:layout_only_attachment)

      result = analysis.shared_comment_attachment_for(owner, repository: :ast_merge)

      expect(result).to eq(:layout_only_attachment)
    end

    it 'dispatches the tracker-layout shared attachment strategy' do
      tracker_attachment = double(:tracker_attachment)

      allow(analysis).to receive(:merge_comment_attachment_with_layout)
        .with(owner, tracker_attachment, repository: :ast_merge)
        .and_return(:tracker_layout_attachment)

      result = analysis.shared_comment_attachment_for(
        owner,
        tracker_attachment: tracker_attachment,
        strategy: :tracker_layout_merge,
        repository: :ast_merge
      )

      expect(result).to eq(:tracker_layout_attachment)
    end

    it 'builds a feature profile from the shared hooks' do
      profile = analysis.feature_profile

      expect(profile).to be_a(Ast::Merge::Ruleset::FeatureProfile)
      expect(profile.owner_selector).to eq(:shared_default)
      expect(profile.match_key).to eq(:signature)
      expect(profile.attachment_strategy).to eq(:layout_only)
      expect(profile.layout_aware?).to be(true)
      expect(profile.logical_owner?).to be(false)
      expect(profile.repair_policies).to eq([])
      expect(profile.surfaces).to eq([])
      expect(profile.delegation_policies).to eq([])
    end

    it 'dispatches the augmenter-preferred shared attachment strategy' do
      tracker_attachment = double(:tracker_attachment)

      allow(analysis).to receive(:merge_augmented_comment_attachment_with_layout)
        .with(owner, tracker_attachment: tracker_attachment, repository: :ast_merge)
        .and_return(:augmenter_attachment)

      result = analysis.shared_comment_attachment_for(
        owner,
        tracker_attachment: tracker_attachment,
        strategy: :augmenter_preferred_tracker_layout,
        repository: :ast_merge
      )

      expect(result).to eq(:augmenter_attachment)
    end

    it 'dispatches the normalized tracked-layout shared attachment strategy' do
      tracker_attachment = double(:tracker_attachment)

      allow(analysis).to receive(:normalize_tracked_comment_attachment_with_layout)
        .with(owner, tracker_attachment: tracker_attachment, repository: :ast_merge)
        .and_return(:normalized_attachment)

      result = analysis.shared_comment_attachment_for(
        owner,
        tracker_attachment: tracker_attachment,
        strategy: :normalize_tracked_layout_merge,
        repository: :ast_merge
      )

      expect(result).to eq(:normalized_attachment)
    end

    it 'raises for an unknown shared attachment strategy' do
      expect do
        analysis.shared_comment_attachment_for(owner, strategy: :mystery_strategy)
      end.to raise_error(ArgumentError, /Unknown comment attachment strategy/)
    end

    it 'builds an empty augmenter that preserves the no-comment capability' do
      augmenter = analysis.comment_augmenter(repository: :ast_merge)

      expect(augmenter).to be_a(Ast::Merge::Comment::Augmenter)
      expect(augmenter.capability.none?).to be(true)
      expect(augmenter.attachment_for(owner)).to be_a(Ast::Merge::Comment::Attachment)
      expect(augmenter.attachment_for(owner).empty?).to be(true)
      expect(augmenter.preamble_region).to be_nil
      expect(augmenter.postlude_region).to be_nil
      expect(augmenter.orphan_regions).to eq([])
    end

    it 'reports no leading freeze directives by default' do
      expect(analysis.owner_leading_comment_freeze?(owner)).to be(false)
      expect(analysis.owner_leading_comment_unfreeze?(owner)).to be(false)
    end
  end

  describe 'default shared layout hooks' do
    it 'returns an empty layout attachment for any owner' do
      attachment = analysis.layout_attachment_for(owner, repository: :ast_merge)

      expect(attachment).to be_a(Ast::Merge::Layout::Attachment)
      expect(attachment.owner).to eq(owner)
      expect(attachment.empty?).to be(true)
      expect(attachment.metadata[:source]).to eq(:file_analyzable_default)
      expect(attachment.metadata[:repository]).to eq(:ast_merge)
    end

    it 'builds an empty layout augmenter when no adjacent blank-line runs exist' do
      augmenter = analysis.layout_augmenter(repository: :ast_merge)

      expect(augmenter).to be_a(Ast::Merge::Layout::Augmenter)
      expect(augmenter.attachment_for(owner)).to be_a(Ast::Merge::Layout::Attachment)
      expect(augmenter.attachment_for(owner)).to be_empty
      expect(augmenter.preamble_gap).to be_nil
      expect(augmenter.postlude_gap).to be_nil
      expect(augmenter.interstitial_gaps).to eq([])
    end
  end

  describe 'owner-leading freeze helpers' do
    let(:analysis_class) do
      Class.new do
        include Ast::Merge::FileAnalyzable

        def initialize(source, statements: [])
          @source = source
          @lines = source.lines.map(&:chomp)
          @freeze_token = 'test-merge'
          @signature_generator = nil
          @statements = statements
        end

        def compute_node_signature(node)
          [:owner, node.start_line, node.end_line]
        end

        def comment_attachment_for(owner, **options)
          Ast::Merge::Comment::Attachment.new(
            owner: owner,
            leading_region: Ast::Merge::Comment::Region.new(
              kind: :leading,
              nodes: [Ast::Merge::Comment::Line.new(text: '# test-merge:freeze', line_number: 1)],
              metadata: options
            )
          )
        end
      end
    end

    let(:analysis) { analysis_class.new("# test-merge:freeze\nbody", statements: [owner]) }

    it 'detects leading freeze directives through comment attachments' do
      expect(analysis.owner_leading_comment_freeze?(owner)).to be(true)
      expect(analysis.owner_leading_comment_unfreeze?(owner)).to be(false)
    end
  end
end
