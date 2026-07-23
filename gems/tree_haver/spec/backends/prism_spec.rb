# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe TreeHaver::Backends::Prism::Parser do
  it 'uses TreeHaver backend availability instead of the upstream Prism.available? API' do
    stub_const('Prism', Module.new)
    allow(TreeHaver::Backends::Prism).to receive(:available?).and_return(true)

    expect { described_class.new }.not_to raise_error
  end
end
