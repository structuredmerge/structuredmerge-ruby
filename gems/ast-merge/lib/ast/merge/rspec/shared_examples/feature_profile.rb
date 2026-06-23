# frozen_string_literal: true

# Shared examples for validating spec-aligned feature profiles.
#
# Usage in your spec:
#   require "ast/merge/rspec/shared_examples/feature_profile"
#
#   RSpec.describe MyMerge::FileAnalysis do
#     describe "#feature_profile" do
#       let(:feature_profile) { described_class.new(sample_source).feature_profile }
#       let(:expected_feature_profile) do
#         {
#           owner_selector: :line_bound_statements,
#           match_key: :signature,
#           read_strategy: :source_augmented_portable_write,
#           attachment_strategy: :augmenter_preferred_tracker_layout,
#           comment_style: :hash_comment,
#           render_family: :bash_script_statements,
#           capabilities: {layout_aware: true, logical_owner: false},
#           logical_owners: {},
#           repair_policies: [],
#           surfaces: [],
#           delegation_policies: [],
#         }
#       end
#
#       it_behaves_like "Ast::Merge::Ruleset::FeatureProfile"
#     end
#   end
RSpec.shared_examples('Ast::Merge::Ruleset::FeatureProfile') do
  it 'exposes the expected ruleset-shaped axes' do
    expect(feature_profile).to(be_a(Ast::Merge::Ruleset::FeatureProfile))
    expect(feature_profile.owner_selector).to(eq(expected_feature_profile.fetch(:owner_selector)))
    expect(feature_profile.match_key).to(eq(expected_feature_profile.fetch(:match_key)))
    expect(feature_profile.read_strategy).to(eq(expected_feature_profile.fetch(:read_strategy)))
    expect(feature_profile.attachment_strategy).to(eq(expected_feature_profile.fetch(:attachment_strategy)))
    expect(feature_profile.comment_style).to(eq(expected_feature_profile.fetch(:comment_style)))
    expect(feature_profile.render_family).to(eq(expected_feature_profile.fetch(:render_family)))
    expect(feature_profile.capabilities).to(eq(expected_feature_profile.fetch(:capabilities)))
    expect(feature_profile.logical_owners).to(eq(expected_feature_profile.fetch(:logical_owners)))
    expect(feature_profile.repair_policies.map(&:to_h)).to(eq(expected_feature_profile.fetch(:repair_policies)))
    expect(feature_profile.surfaces.map(&:to_h)).to(eq(expected_feature_profile.fetch(:surfaces)))
    expect(feature_profile.delegation_policies.map(&:to_h)).to(eq(expected_feature_profile.fetch(:delegation_policies)))
  end

  it 'derives vocabulary metadata from the shared registry' do
    owner_selector_metadata = Ast::Merge::Ruleset::ProfileVocabulary.owner_selector_metadata(
      expected_feature_profile.fetch(:owner_selector)
    )
    match_key_metadata = Ast::Merge::Ruleset::ProfileVocabulary.match_key_metadata(
      expected_feature_profile.fetch(:match_key)
    )
    attachment_strategy_metadata = Ast::Merge::Ruleset::ProfileVocabulary.attachment_strategy_metadata(
      expected_feature_profile.fetch(:attachment_strategy)
    )

    expect(feature_profile.owner_selector_metadata).to(eq(owner_selector_metadata))
    expect(feature_profile.owner_selector_family).to(eq(owner_selector_metadata&.fetch(:family, nil)))
    expect(feature_profile.match_key_metadata).to(eq(match_key_metadata))
    expect(feature_profile.match_key_family).to(eq(match_key_metadata&.fetch(:family, nil)))
    expect(feature_profile.attachment_strategy_metadata).to(eq(attachment_strategy_metadata))
    expect(feature_profile.attachment_strategy_family).to(eq(attachment_strategy_metadata&.fetch(:family, nil)))
  end

  it 'surfaces derived awareness booleans consistently' do
    attachment_strategy_metadata = Ast::Merge::Ruleset::ProfileVocabulary.attachment_strategy_metadata(
      expected_feature_profile.fetch(:attachment_strategy)
    ) || {}

    expect(feature_profile.layout_aware?).to(eq(expected_feature_profile.fetch(:capabilities).fetch(:layout_aware,
                                                                                                    false)))
    expect(feature_profile.logical_owner?).to(eq(
                                                expected_feature_profile.fetch(:capabilities).fetch(:logical_owner,
                                                                                                    false) ||
                                                  expected_feature_profile.fetch(:logical_owners).any?
                                              ))
    expect(feature_profile.repair_aware?).to(eq(expected_feature_profile.fetch(:repair_policies).any?))
    expect(feature_profile.surface_aware?).to(eq(expected_feature_profile.fetch(:surfaces).any?))
    expect(feature_profile.delegated_surface_aware?).to(eq(expected_feature_profile.fetch(:delegation_policies).any?))
    expect(feature_profile.tracked_attachment?).to(eq(attachment_strategy_metadata.fetch(:tracked_comments, false)))
    expect(feature_profile.normalized_attachment?).to(eq(attachment_strategy_metadata.fetch(:normalized, false)))
    expect(feature_profile.augmenter_preferred_attachment?).to(eq(
                                                                 attachment_strategy_metadata.fetch(
                                                                   :augmenter_preferred, false
                                                                 )
                                                               ))
  end
end
