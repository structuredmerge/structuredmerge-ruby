# frozen_string_literal: true

require 'json'

# Shared examples for persisted unresolved-review-state export, replay, and JSON-safe transport.
#
# Usage:
#   let(:unresolved_runtime_merger) { described_class.new(template, destination, resolution_mode: :unresolved) }
#   let(:build_fresh_unresolved_merge_result) do
#     -> { described_class.new(template, destination, resolution_mode: :unresolved).merge_result }
#   end
#   let(:expected_replayed_output_fragment) { 'name = "template"' }
#   it_behaves_like "Ast::Merge::UnresolvedReviewStateTransportContract"
RSpec.shared_examples('Ast::Merge::UnresolvedReviewStateTransportContract') do
  let(:persisted_review_state_result) { unresolved_runtime_merger.merge_result }
  let(:persisted_review_state_case) { persisted_review_state_result.unresolved_cases.fetch(0) }
  let(:persisted_review_state_selection) { :template }
  let(:review_state_hash) do
    persisted_review_state_result.to_unresolved_review_state(
      selections: { persisted_review_state_case.case_id => persisted_review_state_selection }
    ).to_h
  end
  let(:transported_review_state_hash) { JSON.parse(JSON.generate(review_state_hash)) }

  it 'emits stable review identity metadata for persisted unresolved review state' do
    persisted_review_identity = selection_identities_for(review_state_hash).fetch(persisted_review_state_case.case_id)

    expect(persisted_review_identity).to(be_a(String))
    expect(persisted_review_identity).not_to(be_empty)
  end

  it 'rejects persisted review state when review identity drifts' do
    stale_review_state = deep_copy(review_state_hash)
    mutable_selection_identities_for(stale_review_state)[persisted_review_state_case.case_id] = 'stale-identity'

    expect do
      build_fresh_unresolved_merge_result!.apply_unresolved_review_state!(stale_review_state)
    end.to(raise_error(ArgumentError, /no longer matches the current unresolved surface/))
  end

  it 'round-trips persisted review state against a fresh merge result' do
    fresh_result = build_fresh_unresolved_merge_result!
    fresh_result.apply_unresolved_review_state!(review_state_hash)

    expect(fresh_result.review_required?).to(be(false))
    expect(fresh_result.to_s).to(include(expected_replayed_output_fragment!))
  end

  it 'replays persisted review state after JSON serialization' do
    fresh_result = build_fresh_unresolved_merge_result!
    fresh_result.apply_unresolved_review_state!(transported_review_state_hash)

    expect(fresh_result.review_required?).to(be(false))
    expect(fresh_result.to_s).to(include(expected_replayed_output_fragment!))
  end

  def selection_identities_for(payload)
    mutable_selection_identities_for(payload).transform_keys(&:to_s)
  end

  def mutable_selection_identities_for(payload)
    fetch_path(payload, selection_identity_metadata_path_for_contract)
  end

  def fetch_path(payload, path)
    path.reduce(payload) do |memo, key|
      next {} unless memo.respond_to?(:key?)

      if memo.key?(key)
        memo[key]
      elsif memo.key?(key.to_s)
        memo[key.to_s]
      elsif memo.key?(key.to_sym)
        memo[key.to_sym]
      else
        {}
      end
    end
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def selection_identity_metadata_path_for_contract
    return selection_identity_metadata_path if respond_to?(:selection_identity_metadata_path)

    %i[metadata review_state selection_identities]
  end

  def build_fresh_unresolved_merge_result!
    return build_fresh_unresolved_merge_result.call if respond_to?(:build_fresh_unresolved_merge_result)

    raise ArgumentError, "define build_fresh_unresolved_merge_result for #{self.class.description}"
  end

  def expected_replayed_output_fragment!
    return expected_replayed_output_fragment if respond_to?(:expected_replayed_output_fragment)

    raise ArgumentError, "define expected_replayed_output_fragment for #{self.class.description}"
  end
end
