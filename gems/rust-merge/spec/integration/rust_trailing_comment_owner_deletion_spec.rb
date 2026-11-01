# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust native trailing-comment ownership on owner deletion' do
  it "keeps a deleted owner line comment with it and merges the independent edit through syn" do
    compare_fixture('rust_merge3_delete_owner_trailing_comment_with_independent_edit')
  end

  it "keeps a deleted owner block comment with it and merges the independent edit through syn" do
    compare_fixture('rust_merge3_delete_owner_trailing_block_comment_with_independent_edit')
  end

  def compare_fixture(fixture_id)
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture = JSON.parse(File.read(File.expand_path(
      "../../../../../fixtures/polyglot/typed-core/#{fixture_id}.json",
      __dir__
    )))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }

    native_expected = fixture.fetch('ruby_native_expected')
    native = Rust::Merge::Provider.new.merge3(request)
    expect(native.fetch(:ok)).to eq(false)
    expect(native.fetch(:diagnostics).first.fetch(:category).to_s)
      .to eq(native_expected.fetch('diagnostic_category'))
    expect(native.fetch(:conflicts).first.fetch(:category).to_s)
      .to eq(native_expected.fetch('conflict_category'))

    StructuredmergeCore.register_rust_syn_parser("rust.syn.#{fixture_id}")
    %i[rust_tslp rust_syn].each do |backend|
      result = Rust::Merge::RustHostProvider.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      expected = fixture.fetch('rust_host_expected').fetch(backend.to_s)
      expect(result.fetch(:ok)).to eq(expected.fetch('outcome') == 'clean'), "#{backend}: #{result.inspect}"
      if expected.fetch('outcome') == 'clean'
        expect(result.fetch(:output)).to eq(expected.fetch('output'))
        expect(result.fetch(:conflicts)).to be_empty
      else
        expect(result.fetch(:output, nil)).to be_nil
        expect(result.fetch(:diagnostics).first.fetch(:category).to_s)
          .to eq(expected.fetch('diagnostic_category'))
        expect(result.fetch(:diagnostics).first.fetch(:code)).to eq(expected.fetch('diagnostic_code'))
        expect(result.fetch(:conflicts).first.dig(:typed_record, :canonical, :category).to_s)
          .to eq(expected.fetch('conflict_category'))
      end
    end
  end
end
