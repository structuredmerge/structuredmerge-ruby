# frozen_string_literal: true

# Shared example for testing merge scenarios with idempotency
#
# This example tests that:
# 1. Merging template + destination produces the expected result
# 2. The merge is idempotent (merging again produces the same result)
#
# Required let blocks that must be defined by the including spec:
# - fixtures_path: Path to the fixtures directory
# - merger_class: The SmartMerger class to use (e.g., Ast::Merge::Text::SmartMerger)
#
# Optional let blocks:
# - file_extension: File extension for fixtures (default: "" for no extension)
#                   Set to "rb" for Ruby, "txt" for text, etc.
#
# The shared example accepts:
# - scenario: Name of the fixture subdirectory (e.g., "01_top_level_removed")
# - options: Hash of merge options to pass to the merger (default: {})
#
# Fixture directory structure:
#   fixtures_path/
#     scenario/
#       template.{ext}    - The template file
#       destination.{ext} - The destination file
#       result.{ext}      - The expected merge result
#
# @example Basic usage with .txt files
#   let(:fixtures_path) { File.expand_path("../fixtures/text", __dir__) }
#   let(:merger_class) { Ast::Merge::Text::SmartMerger }
#
#   context "when a top-level node is removed in destination" do
#     it_behaves_like "a reproducible merge", "01_top_level_removed"
#   end
#
# @example With Ruby files
#   let(:fixtures_path) { File.expand_path("../fixtures/ruby", __dir__) }
#   let(:merger_class) { Prism::Merge::SmartMerger }
#   let(:file_extension) { "rb" }
#
# @example With no extension
#   let(:file_extension) { "" }
#
# @example With merge options
#   context "with preference: :template" do
#     it_behaves_like "a reproducible merge", "config_preference_template", {
#       preference: :template
#     }
#   end
#
RSpec.shared_examples('a reproducible merge') do |scenario, options = {}|
  let(:scenario_name) { scenario }
  let(:merge_options) { options }
  # file_extension should be defined by the including spec
  # Default: "" (no extension). Override with let(:file_extension) { "rb" } etc.
  let(:file_extension) do
    super()
  rescue NoMethodError
    ''
  end
  let(:fixture_filename) do
    ->(name) { file_extension.to_s.empty? ? name : "#{name}.#{file_extension}" }
  end
  let(:fixture) do
    template = File.read(File.join(fixtures_path, scenario_name, fixture_filename.call('template')))
    destination = File.read(File.join(fixtures_path, scenario_name, fixture_filename.call('destination')))
    expected_result = File.read(File.join(fixtures_path, scenario_name, fixture_filename.call('result')))
    { template: template, destination: destination, expected: expected_result }
  end

  it 'produces the expected result' do
    merger = merger_class.new(
      fixture[:template],
      fixture[:destination],
      **merge_options
    )
    result = merger.merge

    # Normalize trailing newlines for comparison
    # Different backends may or may not add a trailing newline
    expected = fixture[:expected].chomp
    actual = result.to_s.chomp

    expect(actual).to(
      eq(expected),
      "Merge result did not match expected.\n" \
        "Expected:\n#{expected.inspect}\n" \
        "Got:\n#{actual.inspect}"
    )
  end

  it 'is idempotent (merging again produces same result)' do
    # First merge
    merger1 = merger_class.new(
      fixture[:template],
      fixture[:destination],
      **merge_options
    )
    result1 = merger1.merge

    # Second merge: use result1 as new destination
    merger2 = merger_class.new(
      fixture[:template],
      result1,
      **merge_options
    )
    result2 = merger2.merge

    expect(result2).to(
      eq(result1),
      "Merge is not idempotent!\n" \
        "First merge:\n#{result1.inspect}\n" \
        "Second merge:\n#{result2.inspect}"
    )
  end
end
