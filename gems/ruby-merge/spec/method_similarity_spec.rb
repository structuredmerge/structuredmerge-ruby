# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Ruby::Merge::MethodSimilarity do
  subject(:similarity) { described_class.new }

  it 'scores identical method names and parameters as identical' do
    expect(
      similarity.call(
        template_name: 'process_user',
        template_params: %i[user options],
        dest_name: 'process_user',
        dest_params: %i[user options]
      )
    ).to eq(1.0)
  end

  it 'gives related method names credit without requiring exact spelling' do
    expect(similarity.string_similarity('process_user', 'process_users')).to be > 0.9
  end

  it 'combines parameter name overlap and arity similarity' do
    expect(similarity.param_similarity(%i[user options], %i[user config])).to be_within(0.001).of(0.65)
  end
end
