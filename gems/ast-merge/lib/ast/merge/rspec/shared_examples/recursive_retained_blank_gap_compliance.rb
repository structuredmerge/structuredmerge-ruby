# frozen_string_literal: true

# Shared example for validating retained blank-line preservation in recursive
# merge scopes.
#
# Required let blocks:
# - merger_class: The SmartMerger class to use
# - recursive_retained_blank_gap_case: Hash with :template, :destination,
#   :expected, and optional :options.
#
# Optional let blocks:
# - unsupported_recursive_retained_blank_gap_reason: Reason string for formats
#   that expose the shared contract but do not support recursive owner scopes.
RSpec.shared_examples('Ast::Merge::RecursiveRetainedBlankGapCompliance') do
  def merge_recursive_retained_blank_gap_case(example_case, destination_override: nil)
    merger_class.new(
      example_case.fetch(:template),
      destination_override || example_case.fetch(:destination),
      **example_case.fetch(:options, {})
    ).merge.to_s
  end

  it 'preserves retained blank gaps inside recursive owner scopes' do
    if respond_to?(:unsupported_recursive_retained_blank_gap_reason)
      skip unsupported_recursive_retained_blank_gap_reason
    end

    example_case = recursive_retained_blank_gap_case

    expect(merge_recursive_retained_blank_gap_case(example_case)).to(eq(example_case.fetch(:expected)))
  end

  it 'preserves retained blank gaps inside recursive owner scopes idempotently' do
    if respond_to?(:unsupported_recursive_retained_blank_gap_reason)
      skip unsupported_recursive_retained_blank_gap_reason
    end

    example_case = recursive_retained_blank_gap_case
    first_result = merge_recursive_retained_blank_gap_case(example_case)

    expect(merge_recursive_retained_blank_gap_case(example_case,
                                                   destination_override: first_result)).to(eq(first_result))
  end
end
