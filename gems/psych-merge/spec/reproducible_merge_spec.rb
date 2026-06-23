# frozen_string_literal: true

RSpec.describe 'Psych reproducible merge fixtures' do
  FixtureCase = Struct.new(:name, :options, keyword_init: true)

  CASES = [
    FixtureCase.new(name: '01_key_removed', options: {}),
    FixtureCase.new(name: '02_key_added', options: {}),
    FixtureCase.new(name: '03_value_changed', options: {}),
    FixtureCase.new(name: '05_deep_nested_comment_block_template_preference', options: { preference: :template }),
    FixtureCase.new(name: '06_recursive_mixed_siblings_comment_only_section_blank_lines', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '07_recursive_sequence_mapping_items_comment_promotion_blank_lines', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '08_recursive_nested_sequence_groups_comment_promotion', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '09_sequence_item_nested_mapping_comment_sections', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '10_sequence_item_nested_mapping_nested_sequence_comments', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '11_sequence_item_nested_mapping_nested_sequence_mapping_comments', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '12_sequence_item_nested_mapping_nested_sequence_multiple_keeps_removed_comments_stable_identity', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '13_sequence_item_nested_mapping_nested_sequence_duplicate_inner_id_comments_order_stability', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '14_sequence_mapping_items_match_on_orcid_email_and_value', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '15_preferred_document_boundary_comments_are_preserved', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true,
                      remove_template_missing_nodes: true
                    }),
    FixtureCase.new(name: '16_sequence_item_nested_mapping_parent_gap_stability', options: {
                      preference: :template,
                      recursive: true,
                      add_template_only_nodes: true
                    }),
    FixtureCase.new(name: '17_destination_preference_trailing_comments_preserved', options: {
                      preference: :destination,
                      add_template_only_nodes: true
                    }),
    FixtureCase.new(name: '18_compact_mapping_trailing_comment_not_duplicated', options: {
                      preference: :destination,
                      add_template_only_nodes: true
                    }),
    FixtureCase.new(name: '19_attached_trailing_comment_not_duplicated', options: {
                      preference: :destination,
                      add_template_only_nodes: true
                    }),
    FixtureCase.new(name: '20_bare_dash_sequence_item_keeps_dash_with_template_comments', options: {
                      preference: :destination,
                      recursive: true,
                      add_template_only_nodes: true,
                      add_template_only_sequence_items: false,
                      comment_merge_policy: :template_fallback_when_missing
                    })
  ].freeze

  def fixture_root
    Pathname(__dir__).join('fixtures', 'reproducible')
  end

  def fixture_text(case_name, file_name)
    fixture_root.join(case_name, file_name).read
  end

  CASES.each do |fixture_case|
    it "matches reference fixture #{fixture_case.name}" do
      template = fixture_text(fixture_case.name, 'template.yml')
      destination = fixture_text(fixture_case.name, 'destination.yml')
      expected = fixture_text(fixture_case.name, 'result.yml')

      actual = Psych::Merge::SmartMerger.new(template, destination, **fixture_case.options).merge

      expect(actual).to eq(expected)
      expect(Psych::Merge::SmartMerger.new(template, actual, **fixture_case.options).merge).to eq(expected)
    end
  end
end
