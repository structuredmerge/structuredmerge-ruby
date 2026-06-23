# frozen_string_literal: true

RSpec.shared_examples('Ast::Crispr::SelectionProfile contract') do
  it 'exposes the expected selector-intent metadata' do
    expect(selection_profile.owner_scope).to(eq(expected_selection_owner_scope))
    expect(selection_profile.owner_selector).to(eq(expected_selection_owner_selector))
    expect(selection_profile.owner_selector_family).to(eq(expected_selection_owner_selector_family))
    expect(selection_profile.selector_kind).to(eq(expected_selector_kind))
    expect(selection_profile.selection_intent).to(eq(expected_selection_intent))
    expect(selection_profile.selection_intent_family).to(eq(expected_selection_intent_family))
    expect(selection_profile.known_selection_intent?).to(eq(expected_known_selection_intent))
    expect(selection_profile.comment_region).to(eq(expected_comment_region))
    expect(selection_profile.include_trailing_gap).to(eq(expected_include_trailing_gap))
    expect(selection_profile.comment_anchored?).to(eq(expected_comment_anchored))
    expect(selection_profile.to_h).to(include(
                                        owner_scope: expected_selection_owner_scope,
                                        owner_selector: expected_selection_owner_selector,
                                        owner_selector_family: expected_selection_owner_selector_family,
                                        selector_kind: expected_selector_kind,
                                        selection_intent: expected_selection_intent,
                                        selection_intent_family: expected_selection_intent_family,
                                        known_selection_intent: expected_known_selection_intent,
                                        comment_region: expected_comment_region,
                                        include_trailing_gap: expected_include_trailing_gap,
                                        comment_anchored: expected_comment_anchored
                                      ))
  end
end
