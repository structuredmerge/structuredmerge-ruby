# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples'

RSpec.describe 'TOML reproducible merge fixtures', :toml_parsing do
  let(:fixtures_path) { File.expand_path('fixtures/reproducible', __dir__) }
  let(:merger_class) { Toml::Merge::SmartMerger }
  let(:file_extension) { 'toml' }

  context 'when template preference keeps destination docs on an adjacent matched table' do
    it_behaves_like 'a reproducible merge', '01_adjacent_table_comment_template_preference', {
      preference: :template
    }
  end

  context 'when template preference keeps destination docs on a matched array of tables' do
    it_behaves_like 'a reproducible merge', '02_array_of_tables_comment_template_preference', {
      preference: :template
    }
  end

  context 'when unicode string values precede native comment-shaped parser trivia' do
    it_behaves_like 'a reproducible merge', '03_unicode_string_values_do_not_create_invalid_native_comments', {
      preference: :destination,
      add_template_only_nodes: true
    }
  end
end
