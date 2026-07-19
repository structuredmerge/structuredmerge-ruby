# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Ruby::Merge::ScaffoldChunkSupport do
  it 'defines the bundle-gem Rakefile scaffold chunks' do
    expect(described_class::ALL_SPECS.map(&:anchor_value)).to include(
      'bundler/gem_tasks',
      'rspec/core/rake_task',
      'rubocop/rake_task',
      'default'
    )
  end

  it 'uses token-based similarity for scaffold satellite detection' do
    pattern_tokens = described_class.jaccard_tokens('RSpec::Core::RakeTask.new')
    node_tokens = described_class.jaccard_tokens('RSpec::Core::RakeTask.new(:spec)')

    expect(described_class.jaccard(pattern_tokens, node_tokens)).to be >= 0.75
  end

  it 'matches default task anchors fuzzily' do
    expect(described_class.task_anchor_match?('task default: :spec', 'default', 0.35)).to be(true)
  end
end
