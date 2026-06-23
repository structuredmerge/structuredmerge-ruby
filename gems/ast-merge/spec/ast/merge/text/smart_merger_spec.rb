# frozen_string_literal: true

RSpec.describe Ast::Merge::Text::SmartMerger do
  describe '#initialize' do
    let(:template) { "line one\nline two" }
    let(:dest) { "line one\nline three" }

    it 'creates a merger with default options' do
      merger = described_class.new(template, dest)
      expect(merger).to be_a(described_class)
    end

    it 'inherits from SmartMergerBase' do
      expect(described_class.superclass).to eq(Ast::Merge::SmartMergerBase)
    end

    it 'has the default freeze token' do
      merger = described_class.new(template, dest)
      expect(merger.freeze_token).to eq(Ast::Merge::Text::SmartMerger::DEFAULT_FREEZE_TOKEN)
    end

    it 'accepts resolution_mode' do
      merger = described_class.new(template, dest, resolution_mode: :unresolved)
      expect(merger.resolution_mode).to eq(:unresolved)
    end

    it 'accepts unresolved_policy' do
      merger = described_class.new(
        template,
        dest,
        unresolved_policy: { enabled_kinds: [:matched_line], provisional_winner: :template }
      )

      expect(merger.unresolved_policy.to_h).to include(
        enabled_kinds: [:matched_line],
        provisional_winner: :template
      )
    end
  end

  describe '#merge' do
    let(:template) { "line one\nline two" }
    let(:dest) { "line one\nline three" }

    it 'returns merged content as a string' do
      merger = described_class.new(template, dest)
      result = merger.merge
      expect(result).to be_a(String)
    end

    it 'preserves destination lines by default' do
      merger = described_class.new(template, dest)
      result = merger.merge
      expect(result).to include('line three')
    end
  end

  describe '#merge_result' do
    let(:template) { "line one\nline two" }
    let(:dest) { "line one\nline three" }

    it 'returns a MergeResult object' do
      merger = described_class.new(template, dest)
      result = merger.merge_result
      expect(result).to be_a(Ast::Merge::Text::MergeResult)
    end

    it 'surfaces unresolved matched differences when requested' do
      merger = described_class.new(
        "same slot\n",
        "changed slot\n",
        resolution_mode: :unresolved,
        signature_generator: ->(_node) { [:same_slot] }
      )
      result = merger.merge_result

      expect(result.unresolved?).to be(true)
      expect(result.unresolved_cases.length).to eq(1)
      expect(result.unresolved_cases.first.to_h).to include(
        reason: :conflict,
        provisional_winner: :destination
      )
      expect(result.conflicts.first).to include(
        reason: :conflict,
        provisional_winner: :destination
      )
      expect(result.to_s).to eq("changed slot\n")
    end

    it 'uses unresolved_policy provisional winner overrides' do
      merger = described_class.new(
        "same slot\n",
        "changed slot\n",
        resolution_mode: :unresolved,
        unresolved_policy: { provisional_winner_by_kind: { matched_line: :template } },
        signature_generator: ->(_node) { [:same_slot] }
      )

      result = merger.merge_result

      expect(result.unresolved_cases.first.provisional_winner).to eq(:template)
      expect(result.to_s).to eq("same slot\n")
    end

    it 'keeps eager resolution for kinds excluded by unresolved_policy' do
      merger = described_class.new(
        "same slot\n",
        "changed slot\n",
        resolution_mode: :unresolved,
        unresolved_policy: { enabled_kinds: [:other_kind] },
        signature_generator: ->(_node) { [:same_slot] }
      )

      result = merger.merge_result

      expect(result.unresolved?).to be(false)
      expect(result.conflicts).to be_empty
      expect(result.to_s).to eq("changed slot\n")
    end

    it 'applies caller-selected unresolved resolutions to finalize the output' do
      merger = described_class.new(
        "same slot\n",
        "changed slot\n",
        resolution_mode: :unresolved,
        signature_generator: ->(_node) { [:same_slot] }
      )

      result = merger.merge_result
      result.apply_unresolved_resolutions!('text-line-1' => :template)

      expect(result.review_required?).to be(false)
      expect(result.to_s).to eq("same slot\n")
      expect(result.decision_summary[:kept_template]).to eq(1)
    end

    it 'emits stable review identity metadata for persisted unresolved review state' do
      merger = described_class.new(
        "same slot\n",
        "changed slot\n",
        resolution_mode: :unresolved,
        signature_generator: ->(_node) { [:same_slot] }
      )

      result = merger.merge_result
      resolution_case = result.unresolved_cases.fetch(0)

      expect(resolution_case.metadata[:review_identity]).to be_a(String)
      expect(resolution_case.metadata[:review_identity]).not_to be_empty

      state = result.to_unresolved_review_state(selections: { 'text-line-1' => :template })
      fresh_result = described_class.new(
        "same slot\n",
        "changed slot\n",
        resolution_mode: :unresolved,
        signature_generator: ->(_node) { [:same_slot] }
      ).merge_result

      fresh_result.apply_unresolved_review_state!(state.to_h)

      expect(fresh_result.review_required?).to be(false)
      expect(fresh_result.to_s).to eq("same slot\n")
    end

    it 'rejects persisted review state when text review identity drifts' do
      merger = described_class.new(
        "same slot\n",
        "changed slot\n",
        resolution_mode: :unresolved,
        signature_generator: ->(_node) { [:same_slot] }
      )
      result = merger.merge_result
      state = result.to_unresolved_review_state(selections: { 'text-line-1' => :template }).to_h
      state[:metadata][:review_state][:selection_identities]['text-line-1'] = 'stale-identity'

      expect do
        described_class.new(
          "same slot\n",
          "changed slot\n",
          resolution_mode: :unresolved,
          signature_generator: ->(_node) { [:same_slot] }
        ).merge_result.apply_unresolved_review_state!(state)
      end.to raise_error(ArgumentError, /no longer matches the current unresolved surface/)
    end
  end

  describe 'protected methods' do
    let(:template) { 'line one' }
    let(:dest) { 'line two' }

    describe '#analysis_class' do
      it 'returns FileAnalysis' do
        merger = described_class.new(template, dest)
        expect(merger.send(:analysis_class)).to eq(Ast::Merge::Text::FileAnalysis)
      end
    end

    describe '#default_freeze_token' do
      it 'returns the DEFAULT_FREEZE_TOKEN constant' do
        merger = described_class.new(template, dest)
        expect(merger.send(:default_freeze_token)).to eq(Ast::Merge::Text::SmartMerger::DEFAULT_FREEZE_TOKEN)
      end
    end

    describe '#resolver_class' do
      it 'returns ConflictResolver' do
        merger = described_class.new(template, dest)
        expect(merger.send(:resolver_class)).to eq(Ast::Merge::Text::ConflictResolver)
      end
    end

    describe '#result_class' do
      it 'returns MergeResult' do
        merger = described_class.new(template, dest)
        expect(merger.send(:result_class)).to eq(Ast::Merge::Text::MergeResult)
      end
    end
  end

  describe 'with regions' do
    let(:yaml_detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    let(:template) do
      <<~MD
        ---
        title: Template
        ---
        Body line one
        Body line two
      MD
    end

    let(:dest) do
      <<~MD
        ---
        title: Destination
        author: Jane
        ---
        Body line one
        Modified body
      MD
    end

    it 'accepts regions configuration' do
      merger = described_class.new(
        template,
        dest,
        regions: [{ detector: yaml_detector }]
      )

      expect(merger.regions_configured?).to be true
    end

    # NOTE: Full region merging with Text::SmartMerger requires the result's
    # content method to return a String, but MergeResultBase.content returns
    # an Array. Region merging works correctly with other mergers that return
    # String content.
  end
end
