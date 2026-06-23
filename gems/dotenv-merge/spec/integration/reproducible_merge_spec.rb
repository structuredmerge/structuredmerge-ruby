# frozen_string_literal: true

require 'dotenv/merge'
require 'ast/merge/rspec/shared_examples'

RSpec.describe 'Dotenv reproducible merge' do
  let(:fixtures_path) { File.expand_path('../fixtures/reproducible', __dir__) }
  let(:merger_class) { Dotenv::Merge::SmartMerger }
  let(:file_extension) { 'env' }

  describe 'basic merge scenarios (destination wins by default)' do
    context 'when an environment variable is removed in destination' do
      it_behaves_like 'a reproducible merge', '01_var_removed'
    end

    context 'when an environment variable is added in destination' do
      it_behaves_like 'a reproducible merge', '02_var_added'
    end

    context 'when a value is changed in destination' do
      it_behaves_like 'a reproducible merge', '03_value_changed'
    end
  end

  describe 'comment-heavy grouped scenarios' do
    context 'when exported settings keep destination headings, inline notes, and section spacing' do
      it_behaves_like 'a reproducible merge', '04_grouped_export_comments_template_preference', {
        preference: :template
      }
    end

    context 'when duplicate keys require stable sequential comment association' do
      it_behaves_like 'a reproducible merge', '05_duplicate_keys_comment_association', {
        preference: :template
      }
    end

    context 'when quoted values containing # remain values rather than promoted comments' do
      it_behaves_like 'a reproducible merge', '06_quoted_hash_values_grouped_comments', {
        preference: :template
      }
    end
  end
end
