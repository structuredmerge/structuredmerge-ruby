# frozen_string_literal: true

# Shared example for validating generic remove_template_missing_nodes behavior.
#
# Required let blocks that must be defined by the including spec:
# - merger_class: The SmartMerger class to use
# - removal_mode_leading_comments_case: Hash describing a top-level leading-comment case
# - removal_mode_separator_blank_line_case: Hash describing a separator blank-line case
#
# Optional let blocks:
# - removal_mode_inline_comments_case: Hash describing a top-level inline-comment case
# - removal_mode_recursive_case: Hash describing a nested / recursive removal case
# - unsupported_removal_mode_case_reasons: Hash of case-name => reason for unsupported / N/A cases
#
# Each case hash must include:
# - :template     Template content
# - :destination  Destination content
# - :expected     Expected merge output
#
# Optional per-case keys:
# - :options      Additional merge options (remove_template_missing_nodes: true is forced)
#
# The shared example validates both exact output and idempotency for each case.
RSpec.shared_examples('Ast::Merge::RemovalModeCompliance') do
  def merge_removal_mode_case(example_case, destination_override: nil)
    options = { remove_template_missing_nodes: true }.merge(example_case.fetch(:options, {}))

    merger_class.new(
      example_case.fetch(:template),
      destination_override || example_case.fetch(:destination),
      **options
    ).merge.to_s
  end

  def removal_mode_case_for(case_name)
    public_send(case_name) if respond_to?(case_name)
  end

  def unsupported_removal_mode_case_reason(case_name)
    return 'case not applicable for this merger' unless respond_to?(:unsupported_removal_mode_case_reasons)

    unsupported_removal_mode_case_reasons.fetch(case_name, 'case not applicable for this merger')
  end

  {
    'promotes leading comments for removed destination-only nodes' => :removal_mode_leading_comments_case,
    'promotes inline comments for removed destination-only nodes' => :removal_mode_inline_comments_case,
    'preserves separator blank lines around promoted removed-node comments' => :removal_mode_separator_blank_line_case,
    'applies the same removal-mode comment preservation rules in recursive scopes' => :removal_mode_recursive_case
  }.each do |description, case_name|
    it description do
      example_case = removal_mode_case_for(case_name)
      skip unsupported_removal_mode_case_reason(case_name) unless example_case

      expect(merge_removal_mode_case(example_case)).to(eq(example_case.fetch(:expected)))
    end

    it "#{description} idempotently" do
      example_case = removal_mode_case_for(case_name)
      skip unsupported_removal_mode_case_reason(case_name) unless example_case
      first_result = merge_removal_mode_case(example_case)

      expect(merge_removal_mode_case(example_case, destination_override: first_result)).to(eq(first_result))
    end
  end
end
