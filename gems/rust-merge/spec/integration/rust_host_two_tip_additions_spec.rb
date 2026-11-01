# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Rust::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  before(:context) do
    if File.basename(ENV.fetch('BUNDLE_GEMFILE', '')) == 'typed_core.gemfile' && !described_class.available?
      raise 'The typed-core artifact test bundle must load structuredmerge-core'
    end
  end

  before { skip 'compiled typed core is unavailable' unless described_class.available? }

  it 'matches native output for independent additions from both tips' do
    path = File.expand_path('../../../../../fixtures/polyglot/typed-core/rust_merge3_two_tip_additions.json', __dir__)
    fixture = JSON.parse(File.read(path))
    input = fixture.fetch('input')
    request = {
      family: :rust,
      dialect: :rust,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }

    native = Rust::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)
    expected = fixture.fetch('expected')

    expect(native.fetch(:ok)).to eq(expected.fetch('ok')), native.inspect
    expect(rust.fetch(:ok)).to eq(expected.fetch('ok')), rust.inspect
    expect(native.fetch(:output)).to eq(expected.fetch('output'))
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end
end
