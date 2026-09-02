# frozen_string_literal: true

require 'spec_helper'
require 'json'

# rubocop:disable Metrics/BlockLength -- provider behavior and parser-family boundaries form one executable surface
RSpec.describe Ruby::Merge::Provider do
  subject(:provider) { described_class.new }

  it 'advertises a workflow for every TreeHaver tree-sitter runtime' do
    expect(provider).to have_attributes(provider_id: 'ruby.ruby', family: 'ruby')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[ruby],
      backends: %i[mri rust ffi java tslp kreuzberg-language-pack],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(provider.capabilities.dig(:parser_requirements, :allowed_backend_families)).to eq(['tree-sitter'])
    expect(provider.capabilities.dig(:parser_requirements, :denied_backend_ids)).to eq(['prism'])
  end

  it 'auto-registers independently of the Prism backend provider' do
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.ruby',
        family: :ruby,
        dialect: :ruby,
        backend: :tslp,
        profile_id: :source_preserving,
        operation: :merge2
      )
    ).to equal(Ruby::Merge.merge_provider)
  end

  it 'routes merge2 through the shared Ruby substrate and selected TreeHaver backend' do
    fixture = JSON.parse(
      File.read(
        File.expand_path(
          '../../../../fixtures/ruby/slice-941-template-only-class-method-merge/class-method-merge.json',
          __dir__
        )
      ),
      symbolize_names: true
    )

    result = provider.merge2(
      incoming_source: fixture.fetch(:template),
      current_source: fixture.fetch(:destination),
      dialect: :ruby,
      backend: :tslp
    )

    expect(result).to include(ok: true, operation: :merge2, output: fixture.dig(:expected, :output))
    expect(result.dig(:provider, :backend)).to eq(:tslp)
    expect(result.dig(:verification, :output_reparsed)).to be(true)
  end

  it 'returns byte-exact one-sided merge3 results and fails closed for unproven composites' do
    base = "class Demo\nend\n"
    theirs = "class Demo\n  def call = :ok\nend\n"
    exact = provider.merge3(base_source: base, ours_source: base, theirs_source: theirs, backend: :tslp)

    expect(exact).to include(ok: true, operation: :merge3, output: theirs)
    expect(exact.dig(:verification, :base_participated)).to be(true)
    expect(exact.dig(:verification, :byte_exact)).to be(true)

    composite = provider.merge3(
      base_source: base,
      ours_source: "class Demo\n  LEFT = 1\nend\n",
      theirs_source: "class Demo\n  RIGHT = 2\nend\n",
      backend: :tslp
    )
    expect(composite).to include(ok: false, operation: :merge3)
    expect(composite.fetch(:diagnostics)).to include(hash_including(category: :unsupported_capability))
  end

  it 'reports malformed selected input instead of switching parser families' do
    result = provider.merge2(
      incoming_source: "class Demo\n",
      current_source: "class Demo\nend\n",
      backend: :tslp
    )

    expect(result).to include(ok: false, operation: :merge2)
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :parse_error))
  end
end
# rubocop:enable Metrics/BlockLength
