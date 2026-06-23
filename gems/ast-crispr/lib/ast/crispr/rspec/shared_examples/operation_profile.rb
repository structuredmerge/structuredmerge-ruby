# frozen_string_literal: true

RSpec.shared_examples('Ast::Crispr::OperationProfile contract') do
  it 'exposes the expected operation metadata' do
    expect(operation_profile.operation_kind).to(eq(expected_operation_kind))
    expect(operation_profile.operation_family).to(eq(expected_operation_family))
    expect(operation_profile.known_operation_kind?).to(eq(expected_known_operation_kind))
    expect(operation_profile.source_requirement).to(eq(expected_source_requirement))
    expect(operation_profile.destination_requirement).to(eq(expected_destination_requirement))
    expect(operation_profile.replacement_source).to(eq(expected_replacement_source))
    expect(operation_profile.captures_source_text?).to(eq(expected_captures_source_text))
    expect(operation_profile.supports_if_missing?).to(eq(expected_supports_if_missing))
    expect(operation_profile.selects_source?).to(eq(expected_selects_source))
    expect(operation_profile.requires_source?).to(eq(expected_requires_source))
    expect(operation_profile.supports_destination?).to(eq(expected_supports_destination))
    expect(operation_profile.requires_destination?).to(eq(expected_requires_destination))
    expect(operation_profile.explicit_replacement?).to(eq(expected_explicit_replacement))
    expect(operation_profile.may_reuse_captured_text?).to(eq(expected_may_reuse_captured_text))
    expect(operation_profile.to_h).to(include(
                                        operation_kind: expected_operation_kind,
                                        operation_family: expected_operation_family,
                                        known_operation_kind: expected_known_operation_kind,
                                        source_requirement: expected_source_requirement,
                                        destination_requirement: expected_destination_requirement,
                                        replacement_source: expected_replacement_source,
                                        captures_source_text: expected_captures_source_text,
                                        supports_if_missing: expected_supports_if_missing
                                      ))
  end
end
