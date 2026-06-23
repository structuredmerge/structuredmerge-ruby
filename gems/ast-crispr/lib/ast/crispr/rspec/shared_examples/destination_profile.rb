# frozen_string_literal: true

RSpec.shared_examples('Ast::Crispr::DestinationProfile contract') do
  it 'exposes the expected destination-resolution metadata' do
    expect(destination_profile.resolution_kind).to(eq(expected_resolution_kind))
    expect(destination_profile.resolution_family).to(eq(expected_resolution_family))
    expect(destination_profile.known_resolution_kind?).to(eq(expected_known_resolution_kind))
    expect(destination_profile.resolution_source).to(eq(expected_resolution_source))
    expect(destination_profile.resolution_source_family).to(eq(expected_resolution_source_family))
    expect(destination_profile.known_resolution_source?).to(eq(expected_known_resolution_source))
    expect(destination_profile.anchor_boundary).to(eq(expected_anchor_boundary))
    expect(destination_profile.anchor_boundary_family).to(eq(expected_anchor_boundary_family))
    expect(destination_profile.known_anchor_boundary?).to(eq(expected_known_anchor_boundary))
    expect(destination_profile.used_if_missing?).to(eq(expected_used_if_missing))
    expect(destination_profile.append_fallback?).to(eq(expected_append_fallback))
    expect(destination_profile.anchored?).to(eq(expected_destination_anchored))
    expect(destination_profile.to_h).to(include(
                                          resolution_kind: expected_resolution_kind,
                                          resolution_family: expected_resolution_family,
                                          known_resolution_kind: expected_known_resolution_kind,
                                          resolution_source: expected_resolution_source,
                                          resolution_source_family: expected_resolution_source_family,
                                          known_resolution_source: expected_known_resolution_source,
                                          anchor_boundary: expected_anchor_boundary,
                                          anchor_boundary_family: expected_anchor_boundary_family,
                                          known_anchor_boundary: expected_known_anchor_boundary,
                                          used_if_missing: expected_used_if_missing,
                                          append_fallback: expected_append_fallback,
                                          anchored: expected_destination_anchored
                                        ))
  end
end
