# frozen_string_literal: true

require 'spec_helper'
require 'citrus/toml/merge'
require 'toml/merge'

# rubocop:disable Metrics/BlockLength -- shared safe corpus compares complete merge classifications
RSpec.describe 'source-preserving TOML backend parity' do
  subject(:providers) do
    {
      citrus: Citrus::Toml::Merge::Provider.new,
      parslet: Parslet::Toml::Merge::Provider.new,
      klp: Toml::Merge::Provider.new
    }
  end

  def parity_projection(result)
    {
      ok: result[:ok],
      output: result[:output],
      conflicted_output: result[:conflicted_output],
      changes: result[:changes],
      conflicts: result[:conflicts],
      fallbacks: result[:fallbacks],
      strategy: result.dig(:render_report, :strategy),
      base_participated: result.dig(:verification, :base_participated)
    }
  end

  let(:safe_corpus) do
    [
      {
        base_source: "stable = true\n",
        ours_source: "stable = true\nours = \"left\"\n",
        theirs_source: "stable = true\ntheirs = [1, 2]\n"
      },
      {
        base_source: "delete = true\nedit = \"base\"\nstable = true\n",
        ours_source: "edit = \"base\"\nstable = true\n",
        theirs_source: "delete = true\nedit = \"theirs\"\nstable = true\n"
      },
      {
        base_source: "stable = true\n# docs\nvalue = 1\n",
        ours_source: "stable = true\n# left\nvalue = 2_000\n",
        theirs_source: "stable = true\n# right\nvalue = 3\n"
      },
      {
        base_source: "# heading\nvalue = 1\n",
        ours_source: "# left heading\nvalue = 2\n",
        theirs_source: "# right heading\nvalue = 3\n"
      },
      {
        base_source: "stable = true\n",
        ours_source: "stable = true\npublished = 1979-05-27T07:32:00Z\n",
        theirs_source: "stable = true\nnumbers = [1, 2_000]\n"
      }
    ]
  end

  it 'produces identical output, conflict classifications, and base participation' do
    safe_corpus.each do |request|
      results = providers.transform_values { |provider| parity_projection(provider.merge3(request)) }

      expect(results[:parslet]).to eq(results[:citrus]), request.inspect
      expect(results[:klp]).to eq(results[:citrus]), request.inspect
    end
  end

  it 'retains backend identity and native AST attributes outside the parity projection' do
    source = "published = 1979-05-27T07:32:00Z\nnumbers = [1, 2]\n"
    analyses = providers.transform_values { |provider| provider.analyze(source: source) }

    expect(analyses.transform_values { |result| result.dig(:analysis, :backend) }).to eq(
      citrus: 'citrus',
      parslet: 'parslet',
      klp: 'kreuzberg-language-pack'
    )
    expect(analyses.values).to all(include(ok: true))
    expect(analyses.values.map { |result| result.dig(:analysis, :entries, 1, :source_lines) }).to all(eq([2, 2]))
    expect(analyses.values.map { |result| result.dig(:analysis, :entries, 1, :attributes) }).to all(
      include(canonical_type: 'array')
    )
  end
end
# rubocop:enable Metrics/BlockLength
