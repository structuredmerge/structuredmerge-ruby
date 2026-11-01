# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Go membership conflict review output' do
  it "matches each provider conflict rendering for shared fixtures" do
    skip 'compiled typed core is unavailable' unless Go::Merge::RustHostProvider.available?
    fixture_ids = %w[go_merge3_membership_edit_conflict]

    fixture_ids.each do |fixture_id|
      fixture = JSON.parse(File.read(File.expand_path(
        "../../../../../fixtures/polyglot/typed-core/#{fixture_id}.json",
        __dir__
      )))
      input = fixture.fetch('input')
      request = {
        family: :go,
        dialect: :go,
        backend: :rust_tslp,
        profile_id: :source_preserving,
        base_source: input.fetch('base'),
        ours_source: input.fetch('ours'),
        theirs_source: input.fetch('theirs')
      }
      native = Go::Merge::Provider.new.merge3(request)
      rust = Go::Merge::RustHostProvider.new.merge3(request)

      expect(native.fetch(:conflicted_output)).to eq(
        fixture.dig('expected_conflicted_output', 'ruby_native')
      )
      expect(rust.fetch(:conflicted_output)).to eq(
        fixture.dig('expected_conflicted_output', 'rust_host')
      )
    end
  end
end
