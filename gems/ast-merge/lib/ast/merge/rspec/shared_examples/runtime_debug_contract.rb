# frozen_string_literal: true

# Shared examples for runtime-aware #merge_with_debug payloads.
#
# Usage:
#   let(:runtime_debug_merger) { described_class.new(template, destination, **options) }
#   it_behaves_like "Ast::Merge::RuntimeDebugContract"
RSpec.shared_examples('Ast::Merge::RuntimeDebugContract') do
  let(:debug_result) { runtime_debug_merger.merge_with_debug }

  it 'returns content, debug metadata, runtime data, and statistics' do
    expect(debug_result).to(include(
                              :content,
                              :debug,
                              :runtime,
                              :statistics,
                              :decisions,
                              :template_analysis,
                              :dest_analysis
                            ))
    expect(debug_result[:content]).to(be_a(String))
    expect(debug_result[:debug]).to(be_a(Hash))
    expect(debug_result[:runtime]).to(be_a(Hash))
    expect(debug_result[:statistics]).to(be_a(Hash))
    expect(debug_result[:decisions]).to(be_a(Hash))
    expect(debug_result[:template_analysis]).to(be_a(Hash))
    expect(debug_result[:dest_analysis]).to(be_a(Hash))
  end

  it 'includes a consumable runtime summary' do
    expect(debug_result.dig(:runtime, :summary)).to(include(
                                                      :operation_count,
                                                      :root_operation_count,
                                                      :status_counts,
                                                      :diagnostic_count,
                                                      :diagnostic_severity_counts,
                                                      :delegate_names,
                                                      :surface_kinds,
                                                      :effective_languages,
                                                      :capabilities_used,
                                                      :capabilities_missing,
                                                      :unresolved_operation_count,
                                                      :unresolved_case_count
                                                    ))
  end

  it 'includes a nested runtime operation tree projection' do
    expect(debug_result.dig(:runtime, :operation_trees)).to(be_a(Array))
    expect(debug_result.dig(:runtime, :operation_trees)).not_to(be_empty)
    expect(debug_result.dig(:runtime, :operation_trees, 0)).to(include(:operation_id, :frame, :children))
  end

  it 'keeps debug runtime counters aligned with the runtime summary' do
    summary = debug_result.dig(:runtime, :summary)

    expect(debug_result.dig(:debug, :runtime_operation_count)).to(eq(summary[:operation_count]))
    expect(debug_result.dig(:debug, :runtime_diagnostic_count)).to(eq(summary[:diagnostic_count]))
  end

  it 'surfaces corruption handling through debug metadata' do
    expect(debug_result.dig(:debug, :corruption_handling)).to(eq(:heal))
  end
end
