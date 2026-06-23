# frozen_string_literal: true

require 'commonmarker/merge'
require 'ast/merge/rspec/shared_examples'

RSpec.describe 'Commonmarker reproducible merge' do
  let(:fixtures_path) { File.expand_path('fixtures/reproducible', __dir__) }
  let(:merger_class) { Commonmarker::Merge::SmartMerger }
  let(:file_extension) { 'md' }

  describe 'basic merge scenarios (destination wins by default)' do
    context 'when a heading section is removed in destination' do
      it_behaves_like 'a reproducible merge', '01_heading_removed'
    end

    context 'when a heading section is added in destination' do
      it_behaves_like 'a reproducible merge', '02_heading_added'
    end

    context 'when content is changed in destination' do
      it_behaves_like 'a reproducible merge', '03_content_changed'
    end
  end
end
