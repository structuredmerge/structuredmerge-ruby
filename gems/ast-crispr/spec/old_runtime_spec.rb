# frozen_string_literal: true

require 'json'

RSpec.describe Ast::Crispr do
  FakeLocation = Struct.new(:start_line, :end_line, keyword_init: true)
  FakeCommentRegion = Struct.new(:location, :text, keyword_init: true)
  FakeOwner = Struct.new(:location, :key, keyword_init: true)

  class FakeAdapter
    attr_reader :read_count

    def initialize(owners:, comments:)
      @owners = owners
      @comments = comments
      @read_count = 0
    end

    def read_ast(_document)
      @read_count += 1
      { owners: @owners, comments: @comments }
    end

    def structural_owners(document, owner_scope: :shared_default)
      document.ast.fetch(:owners)
    end

    def comment_regions_for(document, owner, region: :leading, owner_scope: :shared_default)
      document.ast.fetch(:comments).fetch(owner.key, [])
    end

    def comment_region_text(_document, comment_region)
      comment_region.text
    end

    def structure_profile(owner_scope: :shared_default)
      Ast::Crispr::StructureProfile.new(
        owner_scope: owner_scope,
        owner_selector: (owner_scope == :shared_default ? :line_bound_statements : owner_scope),
        supported_comment_regions: [:leading],
        metadata: { adapter: :fake }
      )
    end
  end

  let(:owners) do
    [
      FakeOwner.new(location: FakeLocation.new(start_line: 1, end_line: 3), key: :managed_one),
      FakeOwner.new(location: FakeLocation.new(start_line: 5, end_line: 6), key: :managed_two),
      FakeOwner.new(location: FakeLocation.new(start_line: 8, end_line: 9), key: :stable)
    ]
  end
  let(:comments) do
    {
      managed_one: [FakeCommentRegion.new(location: FakeLocation.new(start_line: 1, end_line: 1),
                                          text: '### MANAGED SNIPPET')],
      managed_two: [FakeCommentRegion.new(location: FakeLocation.new(start_line: 5, end_line: 5),
                                          text: '### MANAGED SNIPPET')],
      stable: [FakeCommentRegion.new(location: FakeLocation.new(start_line: 8, end_line: 8), text: '### STABLE')]
    }
  end
  let(:adapter) { FakeAdapter.new(owners: owners, comments: comments) }

  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  it 'has a version number' do
    expect(Ast::Crispr::VERSION).not_to be_nil
  end

  describe described_class::Limit do
    it 'normalizes operator-string arrays into a cardinality predicate' do
      limit = described_class.new(['>= 1', '<= 3'])

      expect(limit.allows?(0)).to be(false)
      expect(limit.allows?(2)).to be(true)
      expect(limit.allows?(4)).to be(false)
      expect(limit.describe).to eq('>= 1 and <= 3')
    end
  end

  describe described_class::Selectors do
    it 'surfaces adapter structure-profile metadata through the selector' do
      content = <<~TEXT
        ### MANAGED SNIPPET
        puts "one"
      TEXT

      target = described_class.owner_filter(
        id: 'managed',
        adapter: adapter
      ) { |_context, owner| owner.key == :managed_one }

      context = Ast::Crispr::DocumentContext.new(content: content, source_label: 'snippet.rb', adapter: adapter)
      profile = target.structure_profile(context)

      expect(target.owner_scope).to eq(:shared_default)
      expect(profile.supports_comment_region?(:leading)).to be(true)
    end

    context 'with an owner-filter selection profile' do
      let(:content) { "### MANAGED SNIPPET\nputs \"one\"\n" }
      let(:target) do
        described_class.owner_filter(
          id: 'managed',
          adapter: adapter,
          include_trailing_gap: true
        ) { |_context, owner| owner.key == :managed_one }
      end
      let(:context) { Ast::Crispr::DocumentContext.new(content: content, source_label: 'snippet.rb', adapter: adapter) }
      let(:selection_profile) { target.selection_profile(context) }
      let(:expected_selection_owner_scope) { :shared_default }
      let(:expected_selection_owner_selector) { :line_bound_statements }
      let(:expected_selection_owner_selector_family) { :line_oriented }
      let(:expected_selector_kind) { :owner_filter }
      let(:expected_selection_intent) { :predicate_filter }
      let(:expected_selection_intent_family) { :predicate }
      let(:expected_known_selection_intent) { true }
      let(:expected_comment_region) { nil }
      let(:expected_include_trailing_gap) { true }
      let(:expected_comment_anchored) { false }

      it_behaves_like 'Ast::Crispr::SelectionProfile contract'
    end

    context 'with an owner-filter match profile' do
      let(:content) { "### MANAGED SNIPPET\nputs \"one\"\n\n" }
      let(:target) do
        described_class.owner_filter(
          id: 'managed',
          adapter: adapter,
          include_trailing_gap: true
        ) { |_context, owner| owner.key == :managed_one }
      end
      let(:context) { Ast::Crispr::DocumentContext.new(content: content, source_label: 'snippet.rb', adapter: adapter) }
      let(:match_profile) { target.locate_matches(context).first.match_profile }
      let(:expected_start_boundary) { :owner_start }
      let(:expected_start_boundary_family) { :structural_owner }
      let(:expected_known_start_boundary) { true }
      let(:expected_end_boundary) { :owner_end_plus_trailing_gap }
      let(:expected_end_boundary_family) { :gap_extension }
      let(:expected_known_end_boundary) { true }
      let(:expected_payload_kind) { :structural_owner_body }
      let(:expected_payload_family) { :owner_body }
      let(:expected_known_payload_kind) { true }
      let(:expected_match_comment_anchored) { false }
      let(:expected_trailing_gap_extended) { true }

      it_behaves_like 'Ast::Crispr::MatchProfile contract'
    end

    it 'finds a structurally owned span via owner_filter' do
      content = <<~TEXT
        ### MANAGED SNIPPET
        puts "one"

        ### MANAGED SNIPPET
        puts "two"
        puts "still managed"

        ### STABLE
        puts "stable"
      TEXT

      target = described_class.owner_filter(
        id: 'stable-owner',
        adapter: adapter
      ) { |_context, owner| owner.key == :stable }

      context = Ast::Crispr::DocumentContext.new(content: content, source_label: 'snippet.rb', adapter: adapter)
      matches = target.locate_matches(context)

      expect(matches.size).to eq(1)
      expect(matches.first.start_line).to eq(8)
      expect(matches.first.end_line).to eq(9)
    end

    it 'finds the comment-region-owned structural owner span' do
      content = <<~TEXT
        ### MANAGED SNIPPET
        puts "one"

        ### MANAGED SNIPPET
        puts "two"
        puts "still managed"

        ### STABLE
        puts "stable"
      TEXT

      target = described_class.comment_region_owned_owner(
        marker: '### STABLE',
        adapter: adapter,
        limit: { exactly: 1 }
      )
      context = Ast::Crispr::DocumentContext.new(content: content, source_label: 'snippet.rb', adapter: adapter)
      matches = target.locate_matches(context)

      expect(matches.size).to eq(1)
      expect(matches.first.start_line).to eq(8)
      expect(matches.first.end_line).to eq(9)
      expect(matches.first.slice_from(content)).to include('puts "stable"')
    end

    it 'finds the outer text line block between repeated exact markers' do
      content = <<~TEXT
        # before
        # <<tool:generated>>
        one
        # <</tool:generated>>
        # <<tool:generated>>
        two
        # <</tool:generated>>
        # after
      TEXT

      target = described_class.line_block(
        start_line_text: '# <<tool:generated>>',
        end_line_text: '# <</tool:generated>>',
        limit: { exactly: 1 }
      )
      context = Ast::Crispr::DocumentContext.new(content: content, source_label: 'plain.txt')
      matches = target.locate_matches(context)

      expect(matches.size).to eq(1)
      expect(matches.first.start_line).to eq(2)
      expect(matches.first.end_line).to eq(7)
      expect(matches.first.slice_from(content)).to include('one')
      expect(matches.first.slice_from(content)).to include('two')
      expect(matches.first.slice_from(content)).not_to include('# after')
    end

    it 'can include the blank trailing gap after a text line block' do
      content = <<~TEXT
        # <<tool:generated>>
        one
        # <</tool:generated>>

        # after
      TEXT

      target = described_class.line_block(
        start_line_text: '# <<tool:generated>>',
        end_line_text: '# <</tool:generated>>',
        include_trailing_gap: true,
        limit: { exactly: 1 }
      )
      context = Ast::Crispr::DocumentContext.new(content: content, source_label: 'plain.txt')
      match = target.locate_matches(context).first

      expect(match.end_line).to eq(4)
      expect(match.slice_from(content)).to end_with("\n\n")
      expect(match.slice_from(content)).not_to include('# after')
    end

    context 'with a comment-region-owned selection profile' do
      let(:target) do
        described_class.comment_region_owned_owner(
          marker: '### STABLE',
          adapter: adapter,
          limit: { exactly: 1 }
        )
      end
      let(:context) { Ast::Crispr::DocumentContext.new(content: "### STABLE\nputs \"stable\"\n", source_label: 'snippet.rb', adapter: adapter) }
      let(:selection_profile) { target.selection_profile(context) }
      let(:expected_selection_owner_scope) { :shared_default }
      let(:expected_selection_owner_selector) { :line_bound_statements }
      let(:expected_selection_owner_selector_family) { :line_oriented }
      let(:expected_selector_kind) { :comment_region_owned_owner }
      let(:expected_selection_intent) { :comment_anchored_owner }
      let(:expected_selection_intent_family) { :comment_anchor }
      let(:expected_known_selection_intent) { true }
      let(:expected_comment_region) { :leading }
      let(:expected_include_trailing_gap) { true }
      let(:expected_comment_anchored) { true }

      it_behaves_like 'Ast::Crispr::SelectionProfile contract'
    end

    context 'with a comment-region-owned match profile' do
      let(:target) do
        described_class.comment_region_owned_owner(
          marker: '### STABLE',
          adapter: adapter,
          limit: { exactly: 1 }
        )
      end
      let(:context) { Ast::Crispr::DocumentContext.new(content: "### STABLE\nputs \"stable\"\n\n", source_label: 'snippet.rb', adapter: adapter) }
      let(:match_profile) { target.locate_matches(context).first.match_profile }
      let(:expected_start_boundary) { :comment_region_start }
      let(:expected_start_boundary_family) { :comment_anchor }
      let(:expected_known_start_boundary) { true }
      let(:expected_end_boundary) { :owner_end_plus_trailing_gap }
      let(:expected_end_boundary_family) { :gap_extension }
      let(:expected_known_end_boundary) { true }
      let(:expected_payload_kind) { :comment_owned_body }
      let(:expected_payload_family) { :comment_owned }
      let(:expected_known_payload_kind) { true }
      let(:expected_match_comment_anchored) { true }
      let(:expected_trailing_gap_extended) { true }

      it_behaves_like 'Ast::Crispr::MatchProfile contract'
    end
  end

  describe described_class::DocumentContext do
    let(:context) { described_class.new(content: "puts :ok\n", source_label: 'snippet.rb', adapter: adapter) }
    let(:profile) { context.structure_profile(owner_scope: :shared_default) }
    let(:expected_owner_scope) { :shared_default }
    let(:expected_owner_selector) { :line_bound_statements }
    let(:expected_owner_selector_family) { :line_oriented }
    let(:expected_known_owner_selector) { true }
    let(:expected_supported_comment_regions) { [:leading] }

    it_behaves_like 'Ast::Crispr::StructureProfile contract'

    it 'answers comment-region support' do
      expect(profile.supports_comment_region?(:leading)).to be(true)
    end
  end

  describe 'operation profiles' do
    describe Ast::Crispr::Replace do
      let(:operation_profile) { described_class.operation_profile }
      let(:expected_operation_kind) { :replace }
      let(:expected_operation_family) { :rewrite }
      let(:expected_known_operation_kind) { true }
      let(:expected_source_requirement) { :required }
      let(:expected_destination_requirement) { :none }
      let(:expected_replacement_source) { :explicit_text }
      let(:expected_captures_source_text) { true }
      let(:expected_supports_if_missing) { false }
      let(:expected_selects_source) { true }
      let(:expected_requires_source) { true }
      let(:expected_supports_destination) { false }
      let(:expected_requires_destination) { false }
      let(:expected_explicit_replacement) { true }
      let(:expected_may_reuse_captured_text) { false }

      it_behaves_like 'Ast::Crispr::OperationProfile contract'
    end

    describe Ast::Crispr::MergeReplace do
      let(:operation_profile) { described_class.operation_profile }
      let(:expected_operation_kind) { :merge_replace }
      let(:expected_operation_family) { :rewrite }
      let(:expected_known_operation_kind) { true }
      let(:expected_source_requirement) { :required }
      let(:expected_destination_requirement) { :none }
      let(:expected_replacement_source) { :merge_template_text }
      let(:expected_captures_source_text) { true }
      let(:expected_supports_if_missing) { false }
      let(:expected_selects_source) { true }
      let(:expected_requires_source) { true }
      let(:expected_supports_destination) { false }
      let(:expected_requires_destination) { false }
      let(:expected_explicit_replacement) { false }
      let(:expected_may_reuse_captured_text) { false }

      it_behaves_like 'Ast::Crispr::OperationProfile contract'
    end

    describe Ast::Crispr::Delete do
      let(:operation_profile) { described_class.operation_profile }
      let(:expected_operation_kind) { :delete }
      let(:expected_operation_family) { :removal }
      let(:expected_known_operation_kind) { true }
      let(:expected_source_requirement) { :required }
      let(:expected_destination_requirement) { :none }
      let(:expected_replacement_source) { :none }
      let(:expected_captures_source_text) { true }
      let(:expected_supports_if_missing) { false }
      let(:expected_selects_source) { true }
      let(:expected_requires_source) { true }
      let(:expected_supports_destination) { false }
      let(:expected_requires_destination) { false }
      let(:expected_explicit_replacement) { false }
      let(:expected_may_reuse_captured_text) { false }

      it_behaves_like 'Ast::Crispr::OperationProfile contract'
    end

    describe Ast::Crispr::DeleteBatch do
      let(:operation_profile) { described_class.operation_profile }
      let(:expected_operation_kind) { :delete_batch }
      let(:expected_operation_family) { :removal }
      let(:expected_known_operation_kind) { true }
      let(:expected_source_requirement) { :required }
      let(:expected_destination_requirement) { :none }
      let(:expected_replacement_source) { :none }
      let(:expected_captures_source_text) { true }
      let(:expected_supports_if_missing) { false }
      let(:expected_selects_source) { true }
      let(:expected_requires_source) { true }
      let(:expected_supports_destination) { false }
      let(:expected_requires_destination) { false }
      let(:expected_explicit_replacement) { false }
      let(:expected_may_reuse_captured_text) { false }

      it_behaves_like 'Ast::Crispr::OperationProfile contract'
    end

    describe Ast::Crispr::Insert do
      let(:operation_profile) { described_class.operation_profile }
      let(:expected_operation_kind) { :insert }
      let(:expected_operation_family) { :insertion }
      let(:expected_known_operation_kind) { true }
      let(:expected_source_requirement) { :none }
      let(:expected_destination_requirement) { :optional }
      let(:expected_replacement_source) { :explicit_text }
      let(:expected_captures_source_text) { false }
      let(:expected_supports_if_missing) { true }
      let(:expected_selects_source) { false }
      let(:expected_requires_source) { false }
      let(:expected_supports_destination) { true }
      let(:expected_requires_destination) { false }
      let(:expected_explicit_replacement) { true }
      let(:expected_may_reuse_captured_text) { false }

      it_behaves_like 'Ast::Crispr::OperationProfile contract'
    end

    describe Ast::Crispr::Move do
      let(:operation_profile) { described_class.operation_profile }
      let(:expected_operation_kind) { :move }
      let(:expected_operation_family) { :relocation }
      let(:expected_known_operation_kind) { true }
      let(:expected_source_requirement) { :optional }
      let(:expected_destination_requirement) { :optional }
      let(:expected_replacement_source) { :captured_text_or_explicit }
      let(:expected_captures_source_text) { true }
      let(:expected_supports_if_missing) { true }
      let(:expected_selects_source) { true }
      let(:expected_requires_source) { false }
      let(:expected_supports_destination) { true }
      let(:expected_requires_destination) { false }
      let(:expected_explicit_replacement) { false }
      let(:expected_may_reuse_captured_text) { true }

      it_behaves_like 'Ast::Crispr::OperationProfile contract'
    end
  end

  describe described_class::Replace do
    it 'fails closed when target cardinality is out of bounds' do
      content = <<~TEXT
        ### MANAGED SNIPPET
        puts "one"

        ### MANAGED SNIPPET
        puts "two"
        puts "still managed"
      TEXT

      target = Ast::Crispr::Selectors.comment_region_owned_owner(
        marker: '### MANAGED SNIPPET',
        adapter: adapter
      )
      actor = described_class.result(content: content, target: target, replacement: "puts \"fresh\"\n")

      expect(actor.failure?).to be(true)
      expect(actor.error).to include('matched 2 node(s); expected == 1')
      expect(actor.operation_profile.operation_kind).to eq(:replace)
    end
  end

  describe described_class::DeleteBatch do
    it 'deletes matches from multiple selectors using one document context' do
      content = <<~TEXT
        ### MANAGED SNIPPET
        puts "one"

        ### MANAGED SNIPPET
        puts "two"
        puts "still managed"

        ### STABLE
        puts "stable"
      TEXT
      selector_one = Ast::Crispr::Selectors.owner_filter(
        id: 'managed-one',
        adapter: adapter,
        limit: { exactly: 1 }
      ) { |_context, owner| owner.key == :managed_one }
      selector_two = Ast::Crispr::Selectors.owner_filter(
        id: 'stable',
        adapter: adapter,
        limit: { exactly: 1 }
      ) { |_context, owner| owner.key == :stable }

      actor = described_class.call(content: content, targets: [selector_one, selector_two])

      expect(actor.changed).to be(true)
      expect(actor.match_count).to eq(2)
      expect(actor.captured_text).to include('puts "one"')
      expect(actor.captured_text).to include('puts "stable"')
      expect(actor.updated_content).to eq("\n### MANAGED SNIPPET\nputs \"two\"\nputs \"still managed\"\n\n")
      expect(adapter.read_count).to eq(1)
    end
  end

  describe described_class::MergeReplace do
    it 'merges replacement text into the selected slice before splicing it back' do
      fixture = read_json(fixtures_root.join('diagnostics', 'slice-1018-crispr-slice-merge',
                                             'crispr-slice-merge.json'))
      operation = fixture.fetch(:operation)
      selector = operation.fetch(:selector)
      merge = operation.fetch(:merge)
      target = Ast::Crispr::Selectors.line_block(
        start_line_text: selector.fetch(:start_line_text),
        end_line_text: selector.fetch(:end_line_text),
        limit: selector.fetch(:limit)
      )

      actor = described_class.call(
        content: operation.fetch(:content),
        target: target,
        replacement: operation.fetch(:replacement),
        merger_class: Ast::Merge::Text::SmartMerger,
        merger_options: {
          preference: merge.fetch(:preference).to_sym,
          add_template_only_nodes: merge.fetch(:add_template_only_nodes)
        }
      )

      expected = fixture.fetch(:expected)
      expect(actor.changed).to eq(expected.fetch(:changed))
      expect(actor.match_count).to eq(expected.fetch(:match_count))
      expect(actor.captured_text).to include(expected.fetch(:captured_text_contains))
      expect(actor.merge_results.first.fetch(:stats)).not_to be_empty
      expect(actor.updated_content).to eq(expected.fetch(:output))
    end
  end

  describe described_class::Insert do
    it 'appends when configured and no destination is resolved' do
      content = <<~RUBY
        task :default do
          puts "ok"
        end
      RUBY

      actor = described_class.call(
        content: content,
        text: "### MANAGED SNIPPET\nputs \"managed\"\n",
        destination: nil,
        if_missing: :append
      )

      expect(actor.updated_content.rstrip).to end_with(<<~RUBY.rstrip)
        ### MANAGED SNIPPET
        puts "managed"
      RUBY
      expect(actor.operation_profile.supports_if_missing?).to be(true)
    end

    context 'with an append-fallback destination profile' do
      let(:actor) do
        described_class.call(
          content: "task :default do\n  puts \"ok\"\nend\n",
          text: "### MANAGED SNIPPET\nputs \"managed\"\n",
          destination: nil,
          if_missing: :append
        )
      end
      let(:destination_profile) { actor.destination_profile }
      let(:expected_resolution_kind) { :append_fallback }
      let(:expected_resolution_family) { :append }
      let(:expected_known_resolution_kind) { true }
      let(:expected_resolution_source) { :none }
      let(:expected_resolution_source_family) { :implicit }
      let(:expected_known_resolution_source) { true }
      let(:expected_anchor_boundary) { :none }
      let(:expected_anchor_boundary_family) { :none }
      let(:expected_known_anchor_boundary) { true }
      let(:expected_used_if_missing) { true }
      let(:expected_append_fallback) { true }
      let(:expected_destination_anchored) { false }

      it_behaves_like 'Ast::Crispr::DestinationProfile contract'
    end
  end
end
