# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe 'RBS shared kernel fixture' do
  let(:fixture) do
    path = Pathname(__dir__).join(
      '..', '..', '..', '..', '..', 'fixtures', 'rbs',
      'slice-1036-shared-kernel', 'declarations-comments.json'
    ).expand_path
    JSON.parse(path.binread)
  end

  def merged_with(backend)
    TreeHaver.with_backend(backend) do
      Rbs::Merge::SmartMerger.new(
        fixture.dig('merge', 'template'),
        fixture.dig('merge', 'destination'),
        add_template_only_nodes: true
      ).merge.to_s
    end
  end

  it 'matches the shared exact result through the native RBS backend', :rbs_backend do
    expect(merged_with(:rbs)).to eq(fixture.dig('merge', 'expected'))
  end

  it 'matches the shared exact result through TSLP' do
    skip 'tree-sitter-rbs grammar is unavailable' unless TreeHaver::GrammarFinder.new(:rbs).available?

    expect(merged_with(:tslp)).to eq(fixture.dig('merge', 'expected'))
  end
end
