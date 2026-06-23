# frozen_string_literal: true

# Shared examples for reviewable unresolved runtime debug payloads.
#
# Usage:
#   let(:unresolved_runtime_merger) { described_class.new(template, destination, resolution_mode: :unresolved) }
#   let(:expected_unresolved_surface_path) { 'document[0] > pair["name"]' }
#   let(:expected_unresolved_output_fragment) { '"destination"' }
#   it_behaves_like "Ast::Merge::UnresolvedRuntimeDebugContract"
RSpec.shared_examples('Ast::Merge::UnresolvedRuntimeDebugContract') do
  let(:unresolved_debug_result) { unresolved_runtime_merger.merge_with_debug }
  let(:unresolved_debug_root_tree) { unresolved_debug_result.dig(:runtime, :operation_trees, 0) }
  let(:expected_unresolved_case_count) { 1 }
  let(:expected_unresolved_provisional_winner) { :destination }

  it 'projects unresolved runtime state through merge_with_debug' do
    expect(unresolved_debug_result.dig(:runtime, :summary)).to(include(
                                                                 unresolved_operation_count: 1,
                                                                 unresolved_case_count: expected_unresolved_case_count
                                                               ))
    expect(unresolved_debug_root_tree[:status]).to(eq(:unresolved))
    expect(unresolved_debug_root_tree.dig(:result, :unresolved_cases)&.length).to(eq(expected_unresolved_case_count))
    expect(unresolved_debug_root_tree.dig(:result, :unresolved_cases, 0)).to(include(
                                                                               reason: :conflict,
                                                                               provisional_winner: expected_unresolved_provisional_winner,
                                                                               surface_path: expected_unresolved_surface_path
                                                                             ))
  end

  it 'keeps provisional output visible through debug content' do
    expect(unresolved_debug_result[:content]).to(include(expected_unresolved_output_fragment))
  end
end
