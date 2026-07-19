# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Ruby::Merge::GemspecSupport do
  it 'normalizes gemspec block variable receivers to the shared placeholder' do
    expect(described_class.effective_receiver('gem', 'gem')).to eq(described_class::GEMSPEC_VAR_PLACEHOLDER)
    expect(described_class.effective_receiver('spec.metadata', 'spec')).to eq('spec.metadata')
  end

  it 'chooses the template block variable when both sides use different variables' do
    expect(described_class.preferred_block_var('spec', 'gem')).to eq('spec')
    expect(described_class.preferred_block_var('spec', 'spec')).to be_nil
  end

  it 'rewrites destination opening lines to the preferred block variable' do
    expect(
      described_class.opening_line_with_preferred_block_var(
        'Gem::Specification.new do |gem|',
        dest_var: 'gem',
        preferred_var: 'spec',
        node_preference: :destination
      )
    ).to eq('Gem::Specification.new do |spec|')
  end
end
