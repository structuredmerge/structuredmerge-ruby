# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Bash Rust line ownership parity' do
  subject(:provider) { Bash::Merge::RustHostProvider.new }

  before { skip 'compiled typed core is unavailable' unless described_class_available? }

  def described_class_available?
    Bash::Merge::RustHostProvider.available?
  end

  it 'matches the shared merge2 contract for attached and inline comments' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/bash_merge2_comments.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    expected = fixture.dig('ruby_native_expected', 'output')
    request = {
      family: :bash,
      dialect: :bash,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      incoming_source: input.fetch('incoming'),
      current_source: input.fetch('current')
    }

    native = Bash::Merge::SmartMerger.new(
      input.fetch('incoming'),
      input.fetch('current'),
      add_template_only_nodes: true
    ).merge
    ruby_provider = Bash::Merge::Provider.new.merge2(
      incoming_source: input.fetch('incoming'),
      current_source: input.fetch('current')
    )
    rust = provider.merge2(request)

    expect(native).to eq(expected)
    expect(ruby_provider).to include(ok: true, output: expected)
    expect(rust).to include(ok: true, output: expected)
  end

  it 'keeps inline assignment comments through independently edited merge3 owners' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/bash_merge3_inline_comment_owner_edits.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    expected = fixture.fetch('expected')
    request = {
      family: :bash,
      dialect: :bash,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to eq(expected.fetch('ruby_native_ok'))
    expect(native.dig(:diagnostics, 0, :category).to_s).to eq(expected.fetch('ruby_native_category'))
    expect(rust).to include(ok: true, output: expected.fetch('output'))
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

  it 'matches Ruby when removed-owner comments rehome to the surviving function' do
    fixture_ids = %w[
      bash_merge3_removed_owner_layout
      bash_merge3_multiple_removed_owner_rehome
    ]
    fixture_ids.each do |fixture_id|
      fixture_path = File.expand_path(
        "../../../../../fixtures/polyglot/typed-core/#{fixture_id}.json",
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

      expect(native).to include(ok: true, output: expected), fixture_id
      expect(rust).to include(ok: true, output: expected), fixture_id
    end
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
