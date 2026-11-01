# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TypeScript::Merge::RustHostProvider, 'oxc_parser backend' do
  subject(:provider) { described_class.new }

  before do
    skip 'compiled typed core is unavailable' unless described_class.available?
    skip 'oxc parser registration is unavailable' unless
      defined?(StructuredmergeCore) && StructuredmergeCore.respond_to?(:register_typescript_oxc_parser)
    TypeScript::Merge.register_rust_host_provider!(replace: true)
  end

  let(:base_source) do
    "import { x } from 'x';\n// header\n/** left docs */\nexport function left(): number { return 1; }\n" \
      "function right(): number { return 1; }\n"
  end
  let(:ours_source) { base_source.sub('left(): number { return 1; }', 'left(): number { return 2; }') }
  let(:theirs_source) { base_source.sub('right(): number { return 1; }', 'right(): number { return 2; }') }

  def request(backend, extra)
    { family: :typescript, dialect: :typescript, backend: backend, profile_id: :source_preserving }.merge(extra)
  end

  def comparable(result)
    result.slice(:ok, :output).merge(
      changes: result[:changes]&.map { |change| change.slice(:subject_ref, :path, :change) },
      diagnostics: result[:diagnostics]&.map { |diagnostic| diagnostic[:category] },
      conflicts: result[:conflicts]&.length
    )
  end

  it 'selects the oxc parser and matches the Tree-sitter backend for every operation' do
    requests = {
      analyze: { source: base_source },
      diff2: { before_source: base_source, after_source: ours_source },
      merge2: { incoming_source: ours_source, current_source: base_source },
      merge3: { base_source: base_source, ours_source: ours_source, theirs_source: theirs_source }
    }

    requests.each do |operation, payload|
      oxc = provider.public_send(operation, request(:typescript_oxc, payload))
      tree_sitter = provider.public_send(operation, request(:rust_tslp, payload))

      expect(oxc.fetch(:provider)).to include(provider_id: 'rust.typescript', backend: :typescript_oxc)
      expect(oxc.fetch(:ok)).to be(true), oxc.inspect
      expect(comparable(oxc)).to eq(comparable(tree_sitter)), operation.to_s
    end
  end

  it 'fails closed on syntax errors without falling back to Tree-sitter' do
    result = provider.analyze(request(:typescript_oxc, source: "function (\n"))

    expect(result.fetch(:ok)).to be(false)
    expect(result.fetch(:diagnostics).first.fetch(:category).to_s).to eq('parse_error')
  end

  it 'merges the shared documented-owner deletion cleanly like the Tree-sitter backend' do
    fixture_id = 'typescript_merge3_delete_documented_owner_with_independent_edit'
    path = File.expand_path("../../../../../fixtures/polyglot/typed-core/#{fixture_id}.json", __dir__)
    fixture = JSON.parse(File.read(path))
    input = fixture.fetch('input')
    payload = { base_source: input.fetch('base'), ours_source: input.fetch('ours'),
                theirs_source: input.fetch('theirs') }

    %i[typescript_oxc rust_tslp].each do |backend|
      result = provider.merge3(request(backend, payload))

      expect(result.fetch(:ok)).to be(true), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(fixture.dig('rust_host_expected', 'output'))
    end
  end
end
