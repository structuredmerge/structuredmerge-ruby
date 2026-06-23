# frozen_string_literal: true

RSpec.shared_examples('Ast::Crispr::StructureProfile contract') do
  it 'exposes the expected structure-profile metadata' do
    expect(profile.owner_scope).to(eq(expected_owner_scope))
    expect(profile.owner_selector).to(eq(expected_owner_selector))
    expect(profile.owner_selector_family).to(eq(expected_owner_selector_family))
    expect(profile.known_owner_selector?).to(eq(expected_known_owner_selector))
    expect(profile.supported_comment_regions).to(eq(expected_supported_comment_regions))
    expect(profile.to_h).to(include(
                              owner_scope: expected_owner_scope,
                              owner_selector: expected_owner_selector,
                              owner_selector_family: expected_owner_selector_family,
                              known_owner_selector: expected_known_owner_selector,
                              supported_comment_regions: expected_supported_comment_regions
                            ))
  end
end
