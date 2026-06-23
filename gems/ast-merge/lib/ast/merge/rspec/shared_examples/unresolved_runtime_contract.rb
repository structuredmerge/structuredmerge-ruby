# frozen_string_literal: true

# Shared examples for reviewable unresolved runtime payloads.
#
# Usage:
#   let(:unresolved_runtime_merger) { described_class.new(template, destination, resolution_mode: :unresolved) }
#   let(:expected_unresolved_surface_path) { 'document[0] > pair["name"]' }
#   let(:expected_unresolved_output_fragment) { '"destination"' }
#   it_behaves_like "Ast::Merge::UnresolvedRuntimeContract"
RSpec.shared_examples('Ast::Merge::UnresolvedRuntimeContract') do
  let(:unresolved_runtime_result) { unresolved_runtime_merger.merge_result }
  let(:unresolved_runtime_root_operation) do
    unresolved_runtime_result
    unresolved_runtime_merger.runtime_session.root_operations.fetch(0)
  end
  let(:expected_unresolved_case_count) { 1 }
  let(:expected_unresolved_provisional_winner) { :destination }
  let(:expected_unresolved_policy) do
    {
      enabled_kinds: :all,
      provisional_winner_by_kind: {},
      metadata: {}
    }
  end

  it 'surfaces unresolved cases through merge result and root runtime state' do
    expect(unresolved_runtime_result.review_required?).to(be(true))
    expect(unresolved_runtime_result.unresolved_cases.length).to(eq(expected_unresolved_case_count))
    expect(unresolved_runtime_result.unresolved_cases.first.to_h).to(include(
                                                                       reason: :conflict,
                                                                       provisional_winner: expected_unresolved_provisional_winner,
                                                                       surface_path: expected_unresolved_surface_path
                                                                     ))
    expect(unresolved_runtime_root_operation.status).to(eq(:unresolved))
    expect(unresolved_runtime_root_operation.result.unresolved_cases.map(&:to_h))
      .to(eq(unresolved_runtime_result.unresolved_cases.map(&:to_h)))
    expect(unresolved_runtime_merger.runtime_session.summary).to(include(
                                                                   unresolved_operation_count: 1,
                                                                   unresolved_case_count: expected_unresolved_case_count
                                                                 ))
  end

  it 'surfaces unresolved policy through runtime metadata' do
    unresolved_runtime_result

    expect(unresolved_runtime_merger.runtime_session.policy_context[:unresolved_policy]).to(eq(expected_unresolved_policy))
    expect(unresolved_runtime_root_operation.options[:unresolved_policy]).to(eq(expected_unresolved_policy))
  end

  it 'keeps runtime option and provisional output aligned' do
    if unresolved_runtime_merger.respond_to?(:options)
      expect(unresolved_runtime_merger.options[:resolution_mode]).to(eq(:unresolved))
      expect(unresolved_runtime_merger.options[:unresolved_policy]).to(eq(expected_unresolved_policy))
    end

    expect(unresolved_runtime_root_operation.result.replacement_text).to(include(expected_unresolved_output_fragment))
  end
end
