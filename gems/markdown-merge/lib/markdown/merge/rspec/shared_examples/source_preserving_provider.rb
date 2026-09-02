# frozen_string_literal: true

require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- the conservative provider safety contract is intentionally executable as one matrix
RSpec.shared_examples 'Markdown::Merge::SourcePreservingProvider' do
  let(:base) { "# Alpha\n\nalpha\n\n# Beta\n\nbeta\n" }
  let(:stable) { "# Stable\n\nstable\n" }
  let(:provider_conformance) do
    {
      dialect: provider_dialect,
      backend: provider_backend,
      profile_id: :source_preserving,
      role: provider_role,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: stable.sub('stable', 'changed') },
        merge2: { current_source: stable, incoming_source: "#{stable}# Added\n\nadded\n" },
        merge3: {
          base_source: base,
          ours_source: base.sub('alpha', 'ours'),
          theirs_source: base.sub('beta', 'theirs')
        }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "# Broken\0\n",
        theirs_source: stable,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "# Obsolete\n\nold\n\n#{stable}",
          ours_source: "# Obsolete\n\nold\n\n#{stable}",
          theirs_source: stable
        },
        expected_value: [[1, 'Stable']]
      },
      parse_output: lambda { |source|
        provider.analyze(source: source).dig(:analysis, :owners).map { |owner| owner.fetch(:signature) }
      }
    }
  end

  it 'passes the shared provider contract for every operation and exact selector' do
    Ast::Merge.register_provider(provider, replace: true)
    registration = Ast::Merge::ProviderContract.validate_provider!(provider)
    selectors = {
      provider_id: provider.provider_id,
      family: provider.family,
      dialect: provider_dialect,
      backend: provider_backend,
      profile_id: :source_preserving
    }

    expect(registration.dig(:capabilities, :role)).to eq(provider_role)
    expect(Ast::Merge.resolve_provider(**selectors, operation: :merge3)).to equal(provider)
    provider_conformance.fetch(:requests).each do |operation, request|
      result = Ast::Merge.dispatch_provider(operation, selectors.merge(request))
      expect(Ast::Merge::ProviderContract.validate_result!(operation, result)).to include(ok: true)
    end
    unsupported = Ast::Merge.dispatch_provider(
      :merge3,
      selectors.merge(provider_conformance.dig(:requests, :merge3), dialect: :unadvertised)
    )
    expect(unsupported).to include(
      ok: false,
      diagnostics: contain_exactly(hash_including(category: :unsupported_capability))
    )
  end

  it 'advertises and resolves its exact selector' do
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: include(provider_dialect),
      backends: [provider_backend],
      profiles: %i[source_preserving],
      role: provider_role
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: provider.provider_id,
        family: :markdown,
        dialect: provider_dialect,
        backend: provider_backend,
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(provider)
  end

  it 'analyzes unique parser-proven heading identities and emits JSON-ready results' do
    result = provider.analyze(source: base)

    expect(result).to include(ok: true)
    expect(result.dig(:analysis, :owners).map { |owner| owner.fetch(:signature) }).to eq(
      [[1, 'Alpha'], [1, 'Beta']]
    )
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end

  it 'matches the shared safe-subset semantics at its explicit backend boundary' do
    result = provider.analyze(source: "# One\n\nbody\n\n# Two\n\nbody\n")

    expect(result.dig(:analysis, :backend)).to eq(provider_backend)
    expect(result.dig(:analysis, :delegated_backend)).to eq(provider_backend)
    expect(result.dig(:analysis, :owners).map { |owner| owner.fetch(:signature) }).to eq(
      [[1, 'One'], [1, 'Two']]
    )
  end

  it 'diffs and merges independent section edits, additions, and deletions' do
    ours = base.sub('alpha', 'ours alpha')
    theirs = base.sub("# Beta\n\nbeta\n", '')
    deletion = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    addition_base = "#{base}\n"
    ours_addition = "#{addition_base}# Ours\n\nours addition\n\n"
    theirs_addition = "#{addition_base}# Theirs\n\ntheirs addition\n\n"
    additions = provider.merge3(
      base_source: addition_base,
      ours_source: ours_addition,
      theirs_source: theirs_addition
    )
    edit_diff = provider.diff2(before_source: base, after_source: ours)
    addition_diff = provider.diff2(before_source: addition_base, after_source: ours_addition)

    expect(edit_diff.fetch(:changes).map { |change| change.fetch(:change) }).to contain_exactly(:edited)
    expect(addition_diff.fetch(:changes).map { |change| change.fetch(:change) }).to contain_exactly(:added)
    expect(deletion).to include(ok: true)
    expect(deletion.fetch(:output)).to include('ours alpha')
    expect(deletion.fetch(:output)).not_to include('# Beta')
    expect(additions).to include(ok: true)
    expect(additions.fetch(:output)).to include('# Ours', '# Theirs')
    expect(additions.fetch(:verification)).to include(
      base_participated: true,
      output_reparsed: true,
      semantic_match: true,
      byte_provenance_verified: true,
      delegated_backend_verified: true,
      backend: provider_backend
    )
  end

  it 'preserves current section customizations while inserting incoming-only sections in order' do
    current = "# Title\n\ncurrent body\n\n# Last\n\ncurrent ending\n"
    incoming = "# Title\n\ntemplate body\n\n# Added\n\nnew section\n\n# Last\n\ntemplate ending\n"
    expected = "# Title\n\ncurrent body\n\n# Added\n\nnew section\n\n# Last\n\ncurrent ending\n"

    result = provider.merge2(current_source: current, incoming_source: incoming)

    expect(result).to include(ok: true, operation: :merge2, output: expected)
    expect(result.fetch(:changes)).to contain_exactly(hash_including(change: :added))
    expect(result.dig(:render_report, :provenance)).to contain_exactly(
      hash_including(source_role: :current, copied_source: true),
      hash_including(source_role: :incoming, copied_source: true),
      hash_including(source_role: :current, copied_source: true)
    )
    expect(result.fetch(:verification)).to include(
      output_reparsed: true,
      semantic_match: true,
      byte_provenance_verified: true,
      delegated_backend_verified: true,
      backend: provider_backend
    )
  end

  it 'localizes a same-section conflict to the parser-proven owner range' do
    result = provider.merge3(
      base_source: base,
      ours_source: base.sub('alpha', 'ours'),
      theirs_source: base.sub('alpha', 'theirs')
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:section_localized_conflict)
    expect(result.fetch(:conflicted_output)).to include('# Beta', 'beta')
  end

  it 'fails closed for duplicate, renamed, level-changed, nested, and headingless ownership' do
    duplicate = "# Alpha\n\none\n\n# Alpha\n\ntwo\n"
    expect(provider.analyze(source: duplicate)).to include(
      ok: false,
      diagnostics: include(hash_including(category: :ambiguous_owner))
    )

    {
      rename: base.sub('# Alpha', '# Renamed'),
      rename_with_body_edit: base.sub("# Alpha\n\nalpha", "# Renamed\n\nrewritten"),
      level: base.sub('# Alpha', '## Alpha')
    }.each_value do |ours|
      result = provider.merge3(base_source: base, ours_source: ours, theirs_source: base.sub('beta', 'theirs'))
      expect(result).to include(ok: false)
      expect(result.fetch(:diagnostics)).to include(hash_including(blocking: true))
      expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
    end

    expect(provider.analyze(source: "# Alpha\n\n## Nested\n\ntext\n")).to include(
      ok: false,
      diagnostics: include(hash_including(category: :unsafe_source_range))
    )
    expect(provider.analyze(source: "headingless prose\n")).to include(
      ok: false,
      diagnostics: include(hash_including(category: :unsafe_source_range))
    )
  end

  it 'fails closed for setext headings and non-whitespace prose outside sections' do
    expect(provider.analyze(source: "Alpha\n=====\n\ntext\n")).to include(
      ok: false,
      diagnostics: include(hash_including(category: :unsafe_source_range))
    )
    expect(provider.analyze(source: "preamble\n\n# Alpha\n\ntext\n")).to include(
      ok: false,
      diagnostics: include(hash_including(category: :unsafe_source_range))
    )
    expect(provider.analyze(source: "\n# Alpha\n\ntext\n")).to include(
      ok: false,
      diagnostics: include(hash_including(category: :unsafe_source_range))
    )
  end

  it 'does not promote headings nested inside block containers to document section owners' do
    quoted = "# Alpha\n\n> # Quoted\n> body\n\n# Beta\n\nbeta\n"
    result = provider.analyze(source: quoted)

    expect(result).to include(ok: true)
    expect(result.dig(:analysis, :owners).map { |owner| owner.fetch(:signature) }).to eq(
      [[1, 'Alpha'], [1, 'Beta']]
    )
  end

  it 'cleanly composes independent deletions that remove every owned section' do
    ours = "# Beta\n\nbeta\n"
    theirs = "# Alpha\n\nalpha\n\n"
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true, output: '')
    expect(result.fetch(:verification)).to include(
      output_reparsed: true,
      semantic_match: true,
      planned_owner_count: 0,
      output_owner_count: 0
    )
  end

  it 'exactly preserves complex Markdown and a missing final newline for one-sided winners' do
    exact = <<~'MARKDOWN'.chomp.sub('<HARD_BREAK>', '  ')
      ---
      title: Exact
      ---
      # Alpha

      - list
      - item
      3. numbered
      - [x] task

      > quoted<HARD_BREAK>
      > hard break &amp; \*escaped\*

      ```ruby
      puts "# not a heading"
      ```

      | a | b |
      |---|---|
      | 1 | 2 |

      <div data-x='1'>inline HTML</div>

      [ref]: https://example.test "Title"
      [use][ref]

      Footnote[^1].
      [^1]: exact footnote

      :::note
      extension directive
      :::
    MARKDOWN
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.fetch(:verification)).to include(byte_exact: true, semantic_match: true, base_participated: true)
  end

  it 'copies complex independently selected section fragments byte-for-byte in a composite' do
    alpha = <<~'MARKDOWN'
      # Alpha

      - [ ] task
      7. numbered

      > quoted

      ~~~~ruby extra
      puts "&amp;"
      ~~~~

      | a | b |
      |---|---|
      | 1 | 2 |

      <span data-x='1'>html</span>

      [ref]: https://example.test
      [use][ref] and footnote[^1].
      [^1]: exact
    MARKDOWN
    beta = "# Beta\n\nbeta\n"
    composite_base = "#{alpha}\n#{beta}"
    ours_alpha = alpha.sub('- [ ] task', '- [x] task')
    theirs_beta = beta.sub('beta', 'theirs')
    result = provider.merge3(
      base_source: composite_base,
      ours_source: "#{ours_alpha}\n#{beta}",
      theirs_source: "#{alpha}\n#{theirs_beta}"
    )

    expect(result).to include(ok: true, output: "#{ours_alpha}\n#{theirs_beta}")
    expect(result.dig(:render_report, :provenance)).to all(include(copied_source: true))
  end

  it 'accepts parser-valid ambiguous exact winners with nonblocking diagnostics' do
    duplicate = "# Same\n\none\n\n# Same\n\ntwo\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: duplicate)

    expect(result).to include(ok: true, output: duplicate)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :ambiguous_owner, blocking: false, source_role: :theirs)
    )
  end

  it 'rejects malformed exact winners with selected-role attribution' do
    malformed = "# Broken\0\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: malformed)

    expect(result).to include(ok: false, source_role: :theirs)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :parse_error, blocking: true)
    )
  end

  it 'uses the base in adversarial deletion merges' do
    old_base = "# Obsolete\n\nold\n\n#{base}"
    result = provider.merge3(base_source: old_base, ours_source: old_base, theirs_source: base)

    expect(result).to include(ok: true, output: base)
    expect(result.fetch(:output)).not_to include('Obsolete')
    expect(result.dig(:verification, :base_participated)).to be(true)
  end

  it 'preserves standalone and legacy APIs' do
    expect(legacy_assertion.call).to be(true)
  end
end
# rubocop:enable Metrics/BlockLength
