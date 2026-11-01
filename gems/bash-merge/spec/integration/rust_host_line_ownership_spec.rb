# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Bash Rust line ownership parity' do
  subject(:provider) { Bash::Merge::RustHostProvider.new }

  before { skip 'compiled typed core is unavailable' unless described_class_available? }

  def described_class_available?
    Bash::Merge::RustHostProvider.available?
  end

  it 'matches Ruby when an independently edited merge includes an added owner' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/bash_merge3_added_owner_layout.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input').to_h { |role, source| ["#{role}_source".to_sym, source] }
    request = {
      family: :bash,
      dialect: :bash,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }.merge(input)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)
    expected = fixture.dig('expected', 'output')

    expect(native).to include(ok: true, output: expected)
    expect(rust).to include(ok: true, output: expected)
  end

  it 'matches Ruby when a removed owner comment attaches to the surviving function' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/bash_merge3_removed_owner_layout.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input').to_h { |role, source| ["#{role}_source".to_sym, source] }
    request = {
      family: :bash,
      dialect: :bash,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }.merge(input)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)
    expected = fixture.dig('expected', 'output')

    expect(native).to include(ok: true, output: expected)
    expect(rust).to include(ok: true, output: expected)
  end

  it 'matches Ruby when both tips add independent owners' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/bash_merge3_additions_from_both_tips.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input').to_h { |role, source| ["#{role}_source".to_sym, source] }
    request = {
      family: :bash,
      dialect: :bash,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }.merge(input)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)
    expected = fixture.dig('expected', 'output')

    expect(native).to include(ok: true, output: expected)
    expect(rust).to include(ok: true, output: expected)
  end
end
