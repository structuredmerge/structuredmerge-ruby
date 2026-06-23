# frozen_string_literal: true

RSpec.shared_examples('Ast::Crispr::MatchProfile contract') do
  it 'exposes the expected match-boundary metadata' do
    expect(match_profile.start_boundary).to(eq(expected_start_boundary))
    expect(match_profile.start_boundary_family).to(eq(expected_start_boundary_family))
    expect(match_profile.known_start_boundary?).to(eq(expected_known_start_boundary))
    expect(match_profile.end_boundary).to(eq(expected_end_boundary))
    expect(match_profile.end_boundary_family).to(eq(expected_end_boundary_family))
    expect(match_profile.known_end_boundary?).to(eq(expected_known_end_boundary))
    expect(match_profile.payload_kind).to(eq(expected_payload_kind))
    expect(match_profile.payload_family).to(eq(expected_payload_family))
    expect(match_profile.known_payload_kind?).to(eq(expected_known_payload_kind))
    expect(match_profile.comment_anchored?).to(eq(expected_match_comment_anchored))
    expect(match_profile.trailing_gap_extended?).to(eq(expected_trailing_gap_extended))
    expect(match_profile.to_h).to(include(
                                    start_boundary: expected_start_boundary,
                                    start_boundary_family: expected_start_boundary_family,
                                    known_start_boundary: expected_known_start_boundary,
                                    end_boundary: expected_end_boundary,
                                    end_boundary_family: expected_end_boundary_family,
                                    known_end_boundary: expected_known_end_boundary,
                                    payload_kind: expected_payload_kind,
                                    payload_family: expected_payload_family,
                                    known_payload_kind: expected_known_payload_kind,
                                    comment_anchored: expected_match_comment_anchored,
                                    trailing_gap_extended: expected_trailing_gap_extended
                                  ))
  end
end
