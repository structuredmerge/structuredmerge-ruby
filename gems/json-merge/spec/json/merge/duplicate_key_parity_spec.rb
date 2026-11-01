# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'JSON duplicate member parity boundary' do
  let(:fixture_path) do
    File.expand_path('../../../../../../fixtures/polyglot/typed-core/json_duplicate_object_keys.json', __dir__)
  end
  let(:fixture) { JSON.parse(File.read(fixture_path)) }
  let(:input) { fixture.fetch('input') }
  let(:native) { Json::Merge::Provider.new }
  let(:rust) { Json::Merge::RustHostProvider.new }

  before { skip 'compiled Rust host unavailable' unless Json::Merge::RustHostProvider.available? }

  it 'records analysis and merge2 ambiguity separately from Ruby native acceptance' do
    expected = fixture.fetch('expected')
    base = input.fetch('base')
    ours = input.fetch('ours')

    expect(native.analyze(source: base, dialect: :json)).to include(ok: expected.dig('ruby_native', 'analyze', 'ok'))
    expect(native.diff2(before_source: base, after_source: ours, dialect: :json)).to include(
      ok: expected.dig('ruby_native', 'diff2', 'ok')
    )

    rust_analysis = rust.analyze(source: base, dialect: :json)
    rust_diff = rust.diff2(before_source: base, after_source: ours, dialect: :json)
    expect(rust_analysis).to include(ok: false)
    expect(rust_diff).to include(ok: false)
    expect(rust_analysis.dig(:diagnostics, 0, :category).to_s).to eq(
      expected.dig('rust_tslp', 'analyze', 'diagnostic_category')
    )
    expect(rust_diff.dig(:diagnostics, 0, :category).to_s).to eq(
      expected.dig('rust_tslp', 'diff2', 'diagnostic_category')
    )

    native_merge = native.merge2(incoming_source: ours, current_source: base, dialect: :json)
    expect(native_merge).to include(
      ok: true,
      output: expected.dig('ruby_native', 'merge2', 'output')
    )
    rust_merge = rust.merge2(incoming_source: ours, current_source: base, dialect: :json)
    expect(rust_merge).to include(ok: false)
    expect(rust_merge.dig(:diagnostics, 0, :category).to_s).to eq(
      expected.dig('rust_tslp', 'merge2', 'diagnostic_category')
    )
  end

  it 'preserves exact and one-sided revisions, and reports competing duplicate-key edits as a conflict' do
    expected = fixture.fetch('expected')
    input = fixture.fetch('input')

    {
      merge3_exact: [input.fetch('base'), input.fetch('base'), input.fetch('base')],
      merge3_one_sided: [input.fetch('base'), input.fetch('ours'), input.fetch('base')]
    }.each do |case_name, (base, ours, theirs)|
      native_result = native.merge3(base_source: base, ours_source: ours, theirs_source: theirs, dialect: :json)
      rust_result = rust.merge3(base_source: base, ours_source: ours, theirs_source: theirs, dialect: :json)
      expected_output = expected.dig('rust_tslp', case_name.to_s, 'output')
      expect(native_result).to include(ok: true, output: expected.dig('ruby_native', case_name.to_s, 'output'))
      expect(rust_result).to include(ok: true, output: expected_output)
    end

    conflict_input = [
      input.fetch('base'),
      input.fetch('ours'),
      input.fetch('theirs')
    ]
    native_conflict = native.merge3(
      base_source: conflict_input[0], ours_source: conflict_input[1],
      theirs_source: conflict_input[2], dialect: :json
    )
    rust_conflict = rust.merge3(
      base_source: conflict_input[0], ours_source: conflict_input[1],
      theirs_source: conflict_input[2], dialect: :json
    )
    expected_conflict = expected.dig('rust_tslp', 'merge3_conflicting')
    expect(native_conflict).to include(ok: false)
    expect(rust_conflict).to include(ok: false)
    expect(native_conflict.dig(:conflicts, 0, :path)).to eq(
      expected.dig('ruby_native', 'merge3_conflicting', 'conflict_path')
    )
    expect(rust_conflict.dig(:conflicts, 0, 'path')).to eq(expected_conflict.fetch('conflict_path'))
    expect(rust_conflict.dig(:conflicts, 0, 'category').to_s).to eq(
      expected_conflict.fetch('conflict_category')
    )
  end
end
