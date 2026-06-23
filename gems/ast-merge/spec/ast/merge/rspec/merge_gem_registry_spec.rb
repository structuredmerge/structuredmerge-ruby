# frozen_string_literal: true

require_relative '../../../spec_helper'

RSpec.describe Ast::Merge::RSpec::MergeGemRegistry do
  describe '.register_known_gem' do
    it 'lets spec bootstraps predeclare tags without hardcoding them in runtime code' do
      tag_name = :example_merge

      described_class.register_known_gem(
        tag_name,
        require_path: 'example/merge',
        merger_class: 'Example::Merge::SmartMerger',
        test_source: 'example'
      )

      expect(described_class.known_gems).to include(tag_name)
      expect(described_class.info(tag_name)).to include(
        require_path: 'example/merge',
        merger_class: 'Example::Merge::SmartMerger',
        category: :other
      )
    end
  end
end
