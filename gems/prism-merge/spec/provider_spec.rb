# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- provider behavior and portable conformance share one executable surface
RSpec.describe Prism::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) do
    <<~RUBY
      # exact preamble
      def alpha
        :base
      end

      def beta
        :base
      end
    RUBY
  end
  let(:ours) do
    <<~RUBY
      # exact preamble
      def alpha
        :ours
      end

      def beta
        :base
      end
    RUBY
  end
  let(:theirs) do
    <<~RUBY
      # exact preamble
      def alpha
        :base
      end

      def beta
        :theirs
      end
    RUBY
  end

  it 'advertises the Prism Ruby backend identity and complete provider API' do
    expect(provider.provider_id).to eq('ruby.ruby.prism')
    expect(provider.family).to eq('ruby')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[ruby],
      backends: %i[prism],
      profiles: %i[source_preserving],
      role: :backend
    )
  end

  it 'registers and resolves all Ruby selectors' do
    Prism::Merge.register_provider!(replace: true)

    resolved = Ast::Merge.resolve_provider(
      provider_id: 'ruby.ruby.prism',
      family: :ruby,
      operation: :merge3,
      dialect: :ruby,
      backend: :prism,
      profile_id: :source_preserving
    )

    expect(resolved).to equal(Prism::Merge.merge_provider)
  end

  it 'reports unbalanced block directives as a structured parse failure' do
    result = provider.analyze(
      source: "class Demo\n  # :nocov:\n  def call = :ok\nend\n",
      dialect: :ruby,
      backend: :prism
    )

    expect(result).to include(ok: false, operation: :analyze, source_role: :source)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :parse_error, message: /unclosed coverage directive/)
    )
  end

  it 'preserves the shared leading gap for a template-only method' do
    result = provider.merge2(
      incoming_source: <<~'RUBY',
        class Greeter
          def greet(name)
            "Hello #{name}"
          end

          def wave
            :wave
          end
        end
      RUBY
      current_source: <<~RUBY,
        class Greeter
          def greet(name)
            name.upcase
          end
        end
      RUBY
      backend: :prism
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to eq(<<~RUBY)
      class Greeter
        def greet(name)
          name.upcase
        end

        def wave
          :wave
        end
      end
    RUBY
  end

  it 'merges independent top-level owner edits with exact source fragments' do
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true, operation: :merge3)
    expect(result.fetch(:output)).to eq(ours.sub(":base\nend\n", ":theirs\nend\n"))
    expect(result.dig(:render_report, :strategy)).to eq(:exact_owner_composite)
    expect(result.dig(:render_report, :line_records)).to include(
      hash_including(revision: :ours),
      hash_including(revision: :theirs)
    )
    expect(result.dig(:verification, :output_reparsed)).to be(true)
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'merges independent additions that overlap under ordinary line merge' do
    stable = "VALUE = 0\n"
    left = "VALUE = 0\nOURS = 1\n"
    right = "VALUE = 0\nTHEIRS = 2\n"

    result = provider.merge3(base_source: stable, ours_source: left, theirs_source: right)

    expect(result).to include(ok: true, output: "VALUE = 0\nOURS = 1\nTHEIRS = 2\n")
    expect(result.dig(:render_report, :synthesized_fragments)).to be_empty
    expect(result.dig(:render_report, :line_records)).to include(
      hash_including(revision: :ours),
      hash_including(revision: :theirs)
    )
  end

  it 'synthesizes only the required separator for additions after a source without a final newline' do
    result = provider.merge3(
      base_source: "VALUE = 0\n",
      ours_source: "VALUE = 0\nOURS = 1",
      theirs_source: "VALUE = 0\nTHEIRS = 2\n"
    )

    expect(result).to include(ok: true, output: "VALUE = 0\nOURS = 1\nTHEIRS = 2\n")
    expect(result.dig(:render_report, :synthesized_fragments)).to include(
      hash_including(reason: :owner_separator, metadata: hash_including(copied_source: true))
    )
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'returns exact revision bytes when only theirs changed' do
    exact = "# encoding: UTF-8\nVALUE  =  'theirs' # spacing retained\n"

    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'verifies exact revisions using the selected revision owner order' do
    reordered = base.sub(/(def alpha.*?end\n\n)(def beta.*?end\n)/m, "\\2\n\\1")

    result = provider.merge3(base_source: base, ours_source: base, theirs_source: reordered)

    expect(result).to include(ok: true, output: reordered)
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'localizes incompatible edits to their top-level owner' do
    left = base.sub(':base', ':ours')
    right = base.sub(':base', ':theirs')

    result = provider.merge3(base_source: base, ours_source: left, theirs_source: right)

    expect(result).to include(ok: false, operation: :merge3)
    expect(result.fetch(:conflicted_output)).to start_with("# exact preamble\n<<<<<<< ours\n")
    expect(result.fetch(:conflicted_output)).to include(
      "def alpha\n  :ours\nend\n||||||| base\ndef alpha\n  :base\nend\n=======\ndef alpha\n  :theirs\nend\n"
    )
    expect(result.fetch(:conflicted_output)).to end_with("def beta\n  :base\nend\n")
    expect(result.dig(:render_report, :strategy)).to eq(:owner_localized_conflict)
    expect(result.dig(:render_report, :conflicts).first.fetch(:conflict_id)).to match(
      /\Aruby-owner-[0-9a-f]{16}\z/
    )
  end

  it 'conflicts rather than dropping source changes outside owned ranges' do
    ours = base.sub(':base', ':ours')
    theirs = base.sub('# exact preamble', '# changed preamble')

    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(
      hash_including(category: :unmanaged_source_change, path: '<unmanaged-source>')
    )
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
    expect(result.fetch(:fallbacks)).to include(
      hash_including(reason: :owner_not_addressable)
    )
  end

  it 'identifies the source role for parse failures' do
    result = provider.merge3(base_source: base, ours_source: "def broken(\n", theirs_source: theirs)

    expect(result).to include(ok: false, source_role: :ours)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :parse_error, message: /ours parse error/)
    )
  end
end

RSpec.describe 'Prism::Merge provider conformance' do
  subject(:provider) { Prism::Merge.merge_provider }

  def parsed_owners(source)
    Prism.parse(source).value.statements.body.map do |node|
      [node.type, (node.name if node.respond_to?(:name)), node.slice]
    end
  end

  let(:stable) { "STABLE = true\n" }
  let(:ours_add) { "STABLE = true\nOURS = 1\n" }
  let(:theirs_add) { "STABLE = true\nTHEIRS = 2\n" }
  let(:provider_conformance) do
    {
      dialect: :ruby,
      backend: :prism,
      profile_id: :source_preserving,
      role: :backend,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: ours_add },
        merge2: { current_source: ours_add, incoming_source: theirs_add },
        merge3: { base_source: stable, ours_source: ours_add, theirs_source: theirs_add }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "class Broken\n",
        theirs_source: theirs_add,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "OBSOLETE = true\nSTABLE = true\n",
          ours_source: "OBSOLETE = true\nSTABLE = true\n",
          theirs_source: stable
        },
        expected_value: parsed_owners(stable)
      },
      parse_output: method(:parsed_owners)
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
