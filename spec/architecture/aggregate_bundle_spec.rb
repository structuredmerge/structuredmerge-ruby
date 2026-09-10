# frozen_string_literal: true

RSpec.describe 'aggregate family bundle context' do
  it 'exports the root Gemfile for subprocesses that run outside the monorepo' do
    expect(ENV.fetch('KETTLE_FAMILY_BUNDLE_GEMFILE')).to eq(
      File.expand_path('../../Gemfile', __dir__)
    )
  end
end
