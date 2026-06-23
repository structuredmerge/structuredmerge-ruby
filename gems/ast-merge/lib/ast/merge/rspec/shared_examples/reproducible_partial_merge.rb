# frozen_string_literal: true

RSpec.shared_examples('a reproducible partial merge') do
  let(:partial_merge_options) { {} }
  let(:expected_target_found) { true }
  let(:expect_second_merge_unchanged) { true }

  it 'produces the expected partial-merge result' do
    result = build_partial_merger(destination: destination_content).merge

    expect(partial_merge_result_content(result)).to(eq(expected_merged_content))
  end

  it 'is idempotent (merging the merged content again produces the same result)' do
    first_result = build_partial_merger(destination: destination_content).merge
    second_result = build_partial_merger(destination: partial_merge_result_content(first_result)).merge

    expect(partial_merge_result_content(second_result)).to(eq(partial_merge_result_content(first_result)))

    second_changed = partial_merge_result_changed(second_result)
    expect(second_changed).to(be(false)) if expect_second_merge_unchanged && !second_changed.nil?
  end

  it 'reports partial-target discovery consistently when the result exposes it' do
    result = build_partial_merger(destination: destination_content).merge
    discovered_target = partial_merge_target_found(result)

    skip 'Partial merge result does not expose a target-found indicator' if discovered_target.nil?
    skip 'Target-found assertions intentionally skipped for this contract consumer' if expected_target_found == :skip

    expect(discovered_target).to(eq(expected_target_found))
  end

  def build_partial_merger(destination:)
    partial_merger_class.new(
      template: template_content,
      destination: destination,
      **partial_merge_options
    )
  end

  def partial_merge_result_content(result)
    return result.content if result.respond_to?(:content)
    return result.to_s if result.respond_to?(:to_s)

    raise ArgumentError, 'Partial merge result must expose #content or #to_s'
  end

  def partial_merge_result_changed(result)
    return result.changed if result.respond_to?(:changed)

    nil
  end

  def partial_merge_target_found(result)
    return result.section_found? if result.respond_to?(:section_found?)
    return result.key_path_found? if result.respond_to?(:key_path_found?)
    return result.has_section if result.respond_to?(:has_section)
    return result.has_key_path if result.respond_to?(:has_key_path)

    nil
  end
end
