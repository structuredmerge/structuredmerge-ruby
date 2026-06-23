# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples/feature_profile'

RSpec.describe 'FeatureProfile shared examples' do
  let(:feature_profile) do
    Ast::Merge::Ruleset::FeatureProfile.new(
      owner_selector: :line_bound_statements,
      match_key: :signature,
      read_strategy: :source_augmented_portable_write,
      attachment_strategy: :augmenter_preferred_tracker_layout,
      comment_style: :hash_comment,
      render_family: :bash_script_statements,
      capabilities: { layout_aware: true, logical_owner: false },
      logical_owners: {},
      repair_policies: [],
      surfaces: [],
      delegation_policies: []
    )
  end

  let(:expected_feature_profile) do
    {
      owner_selector: :line_bound_statements,
      match_key: :signature,
      read_strategy: :source_augmented_portable_write,
      attachment_strategy: :augmenter_preferred_tracker_layout,
      comment_style: :hash_comment,
      render_family: :bash_script_statements,
      capabilities: { layout_aware: true, logical_owner: false },
      logical_owners: {},
      repair_policies: [],
      surfaces: [],
      delegation_policies: []
    }
  end

  it_behaves_like 'Ast::Merge::Ruleset::FeatureProfile'
end
