# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- provider safety boundaries are one executable contract
RSpec.describe Bash::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) do
    <<~BASH
      #!/usr/bin/env bash
      shared() {
        echo base
      }
    BASH
  end

  it 'registers the exact Bash workflow selector with every provider operation' do
    expect(provider).to have_attributes(provider_id: 'ruby.bash', family: 'bash')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[bash],
      backends: [:'kreuzberg-language-pack'],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.bash',
        family: :bash,
        dialect: :bash,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Bash::Merge.merge_provider)
  end

  it 'analyzes stable function, assignment, and literal test identities and emits JSON-ready diffs' do
    source = "VALUE=one\nalpha() { echo alpha; }\ntest_expect_success 'works' 'echo one'\n"
    signatures = provider.analyze(source: source).dig(:analysis, :declarations).map { |item| item.fetch(:signature) }
    result = provider.diff2(before_source: source, after_source: source.gsub('one', 'two'))

    expect(signatures).to eq(
      [
        [:variable_assignment, 'VALUE'],
        [:function, 'alpha'],
        [:test_harness_call, :test_expect_success, "'works'"]
      ]
    )
    expect(result.fetch(:changes)).to contain_exactly(
      hash_including(path: include('variable_assignment'), change: :edited),
      hash_including(path: include('test_harness_call'), change: :edited)
    )
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end

  it 'analyzes repeated unstable owners and diffs their semantic edits positionally' do
    source = "printf '%s' repeated\nprintf '%s' repeated\nif ready; then echo base; fi\n"
    analysis = provider.analyze(source: source)
    result = provider.diff2(before_source: source, after_source: source.sub('echo base', 'echo changed'))

    expect(analysis.dig(:analysis, :declarations).map { |item| item.fetch(:signature) }).to eq(
      [
        [:command, 'printf', ["'%s'", 'repeated'], nil],
        [:command, 'printf', ["'%s'", 'repeated'], nil],
        [:if_statement, nil]
      ]
    )
    expect(result.fetch(:changes)).to contain_exactly(hash_including(change: :edited))
  end

  it 'implements merge2 and a true base-aware merge3 with exact source fragments' do
    incoming = "#{base}incoming() { echo incoming; }\n"
    expect(provider.merge2(current_source: base, incoming_source: incoming)).to include(
      ok: true,
      operation: :merge2,
      output: incoming
    )

    ours = "#{base}ours() { echo ours; }\n"
    theirs = "#{base}theirs() { echo theirs; }\n"
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true, output: "#{base}ours() { echo ours; }\ntheirs() { echo theirs; }\n")
    expect(result.fetch(:verification)).to include(
      output_reparsed: true,
      semantic_match: true,
      ast_attributes_verified: true,
      base_participated: true
    )
  end

  it 'attests base participation by honoring a base deletion' do
    old_base = "#{base}obsolete() { echo old; }\n"
    result = provider.merge3(
      base_source: old_base,
      ours_source: "#{old_base}ours() { echo ours; }\n",
      theirs_source: base
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).not_to include('obsolete')
    expect(result.dig(:verification, :base_participated)).to be(true)
  end

  it 'merges independent function edits while preserving comments and the shebang exactly' do
    two_functions = <<~BASH
      #!/usr/bin/env bash
      # executable preamble
      alpha() { echo alpha; }
      beta() { echo beta; }
    BASH
    result = provider.merge3(
      base_source: two_functions,
      ours_source: two_functions.sub('echo alpha', 'echo ours'),
      theirs_source: two_functions.sub('echo beta', 'echo theirs')
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to eq(
      two_functions.sub('echo alpha', 'echo ours').sub('echo beta', 'echo theirs')
    )
  end

  it 'keeps assignment ownership distinct from command and compound-statement boundaries' do
    structural = <<~BASH
      VALUE=base
      export VALUE
      printf '%s' "$VALUE" | cat
      if test -n "$VALUE"; then echo set; fi
    BASH
    result = provider.merge3(
      base_source: structural,
      ours_source: structural.sub('VALUE=base', 'VALUE=ours'),
      theirs_source: "#{structural}added() { :; }\n"
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include("VALUE=ours\n", "export VALUE\n", "| cat\n", 'if test')

    unsafe_command_edit = provider.merge3(
      base_source: structural,
      ours_source: structural.sub('export VALUE', 'export OTHER'),
      theirs_source: "#{structural}added() { :; }\n"
    )
    expect(unsafe_command_edit.fetch(:conflicts)).to include(hash_including(category: :unproven_ast_ownership))
  end

  it 'preserves a one-sided exact winner byte for byte, including no final newline' do
    exact = "chosen( ) {\n  printf '%s' chosen\n}".chomp
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.fetch(:verification)).to include(byte_exact: true, semantic_match: true)
  end

  it 'exact-copies parser-valid repeated commands and heredocs with conservative diagnostics' do
    exact = "printf '%s' repeated\nprintf '%s' repeated\ncat <<EOF\nvalue\nEOF"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :ambiguous_owner, blocking: false, source_role: :theirs)
    )
    expect(result.fetch(:verification)).to include(byte_exact: true, semantic_match: true)
  end

  it 'validates only the selected exact winner while reporting malformed nonwinners nonblockingly' do
    exact = "chosen() { :; }\n"
    result = provider.merge3(base_source: "broken() {\n", ours_source: exact, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :parse_error, blocking: false, source_role: :base)
    )

    malformed_winner = provider.merge3(base_source: exact, ours_source: exact, theirs_source: "broken() {\n")
    expect(malformed_winner).to include(ok: false, source_role: :theirs)
    expect(malformed_winner.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :parse_error, blocking: true)
    )
  end

  it 'localizes divergent edits to one function and leaves stable source outside markers' do
    ours = base.sub('echo base', 'echo ours')
    theirs = base.sub('echo base', 'echo theirs')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:declaration_localized_conflict)
    expect(result.fetch(:conflicted_output)).to start_with("#!/usr/bin/env bash\n<<<<<<<")
  end

  it 'fails closed with full-file fallback for duplicate identities and heredocs' do
    duplicate = "same() { :; }\nsame() { :; }\n"
    duplicate_result = provider.merge3(
      base_source: base,
      ours_source: duplicate,
      theirs_source: "#{base}theirs() { :; }\n"
    )
    expect(duplicate_result).to include(ok: false, source_role: :ours)
    expect(duplicate_result.fetch(:conflicts)).to include(hash_including(category: :ambiguous_owner))
    expect(duplicate_result.dig(:render_report, :strategy)).to eq(:full_file_conflict)

    heredoc = "cat <<EOF\nvalue\nEOF\n"
    heredoc_result = provider.merge3(
      base_source: base,
      ours_source: heredoc,
      theirs_source: "#{base}theirs() { :; }\n"
    )
    expect(heredoc_result).to include(ok: false, source_role: :ours)
    expect(heredoc_result.fetch(:conflicts)).to include(hash_including(category: :unsafe_source_range))
    expect(heredoc_result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'uses full-file fallback when unstable or unmanaged source changes independently' do
    command_base = "printf '%s' base\nstable() { :; }\n"
    unstable = provider.merge3(
      base_source: command_base,
      ours_source: command_base.sub('base', 'ours'),
      theirs_source: "#{command_base}theirs() { :; }\n"
    )
    expect(unstable.fetch(:conflicts)).to include(hash_including(category: :unproven_ast_ownership))
    expect(unstable.dig(:render_report, :strategy)).to eq(:full_file_conflict)

    unmanaged = provider.merge3(
      base_source: base,
      ours_source: base.sub('env bash', 'bash'),
      theirs_source: "#{base}theirs() { :; }\n"
    )
    expect(unmanaged.fetch(:conflicts)).to include(hash_including(category: :unmanaged_source_change))
    expect(unmanaged.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'rejects every unstable top-level owner mutation before merging stable owners' do
    command_base = "printf '%s' base\nstable() { echo base; }\n"
    added_command = provider.merge3(
      base_source: command_base,
      ours_source: "printf '%s' base\nprintf '%s' added\nstable() { echo base; }\n",
      theirs_source: command_base.sub('echo base', 'echo theirs')
    )
    expect(added_command.fetch(:conflicts)).to include(hash_including(category: :unproven_ast_ownership))
    expect(added_command.dig(:render_report, :strategy)).to eq(:full_file_conflict)

    conditional_base = "if ready; then echo base; fi\nstable() { echo base; }\n"
    edited_conditional = provider.merge3(
      base_source: conditional_base,
      ours_source: conditional_base.sub('echo base; fi', 'echo ours; fi'),
      theirs_source: conditional_base.sub('stable() { echo base;', 'stable() { echo theirs;')
    )
    expect(edited_conditional.fetch(:conflicts)).to include(hash_including(category: :unproven_ast_ownership))

    reordered_base = "first one\nsecond two\nstable() { echo base; }\n"
    reordered = provider.merge3(
      base_source: reordered_base,
      ours_source: "second two\nfirst one\nstable() { echo base; }\n",
      theirs_source: reordered_base.sub('echo base', 'echo theirs')
    )
    expect(reordered.fetch(:conflicts)).to include(hash_including(category: :unproven_ast_ownership))
  end

  it 'recognizes append-only literal-title tests but conflicts until ordered insertion rendering exists' do
    test_base = "test_expect_success 'base test' 'echo base'\ntest_done\n"
    ours = test_base.sub("test_done\n", "test_expect_success 'ours test' 'echo ours'\ntest_done\n")
    theirs = test_base.sub("test_done\n", "test_expect_success 'theirs test' 'echo theirs'\ntest_done\n")
    result = provider.merge3(base_source: test_base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(
      hash_including(
        category: :unproven_ast_ownership,
        reason: :test_harness_addition_requires_ordered_rendering
      )
    )
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'fails closed for ambiguous, dynamic, reordered, deleted, and inserted test ownership' do
    test_base = <<~BASH
      test_expect_success 'first test' 'echo first'
      test_expect_success 'second test' 'echo second'
      test_done
    BASH
    stable_edit = test_base.sub('echo first', 'echo theirs')

    duplicate = provider.merge3(
      base_source: test_base,
      ours_source: test_base.sub(
        "test_done\n",
        "test_expect_success 'second test' 'echo duplicate'\ntest_done\n"
      ),
      theirs_source: stable_edit
    )
    expect(duplicate.fetch(:conflicts)).to include(hash_including(category: :ambiguous_owner))

    dynamic = provider.merge3(
      base_source: test_base,
      ours_source: test_base.sub(
        "test_done\n",
        "test_expect_success \"dynamic $title\" 'echo dynamic'\ntest_done\n"
      ),
      theirs_source: stable_edit
    )
    expect(dynamic.fetch(:conflicts)).to include(hash_including(category: :unproven_ast_ownership))

    redirected = provider.merge3(
      base_source: test_base,
      ours_source: test_base.sub(
        "test_done\n",
        "test_expect_success 'redirected test' 'echo redirected' >result\ntest_done\n"
      ),
      theirs_source: stable_edit
    )
    expect(redirected.fetch(:conflicts)).to include(hash_including(category: :unproven_ast_ownership))

    reordered = provider.merge3(
      base_source: test_base,
      ours_source: test_base.lines.values_at(1, 0, 2).join,
      theirs_source: stable_edit
    )
    deleted = provider.merge3(
      base_source: test_base,
      ours_source: test_base.lines.values_at(0, 2).join,
      theirs_source: stable_edit
    )
    inserted = provider.merge3(
      base_source: test_base,
      ours_source: test_base.sub(
        "test_expect_success 'second test'",
        "test_expect_success 'inserted test' 'echo inserted'\ntest_expect_success 'second test'"
      ),
      theirs_source: stable_edit
    )

    [reordered, deleted, inserted].each do |unsafe|
      expect(unsafe.fetch(:conflicts)).to include(
        hash_including(category: :unproven_ast_ownership, reason: :non_append_only_test_harness_change)
      )
      expect(unsafe.dig(:render_report, :strategy)).to eq(:full_file_conflict)
    end
  end

  it 'localizes divergent edits to the same literal-title test owner' do
    test_base = "test_expect_success 'same test' 'echo base'\n"
    result = provider.merge3(
      base_source: test_base,
      ours_source: test_base.sub('echo base', 'echo ours'),
      theirs_source: test_base.sub('echo base', 'echo theirs')
    )

    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:declaration_localized_conflict)
  end

  it 'allows identical unstable owners beside independent stable-owner edits' do
    commands = "printf '%s' repeated\nprintf '%s' repeated\n"
    functions = "alpha() { echo base; }\nbeta() { echo base; }\n"
    result = provider.merge3(
      base_source: commands + functions,
      ours_source: commands + functions.sub('alpha() { echo base;', 'alpha() { echo ours;'),
      theirs_source: commands + functions.sub('beta() { echo base;', 'beta() { echo theirs;')
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to eq(
      commands + functions.sub('alpha() { echo base;', 'alpha() { echo ours;')
                          .sub('beta() { echo base;', 'beta() { echo theirs;')
    )
  end

  it 'continues to merge independent assignment edits' do
    assignments = "LEFT=base\nRIGHT=base\n"
    result = provider.merge3(
      base_source: assignments,
      ours_source: assignments.sub('LEFT=base', 'LEFT=ours'),
      theirs_source: assignments.sub('RIGHT=base', 'RIGHT=theirs')
    )

    expect(result).to include(ok: true, output: "LEFT=ours\nRIGHT=theirs\n")
  end

  it 'reports malformed source by revision and preserves the legacy SmartMerger API' do
    malformed = provider.merge3(base_source: base, ours_source: "broken() {\n", theirs_source: base)
    expect(malformed).to include(ok: false, source_role: :ours)
    expect(malformed.fetch(:diagnostics)).to contain_exactly(hash_including(category: :parse_error, blocking: true))

    legacy = Bash::Merge::SmartMerger.new("added() { :; }\n", base, add_template_only_nodes: true).merge
    expect(legacy).to include('shared()', 'added()')
  end
end

RSpec.describe 'Bash provider conformance' do
  subject(:provider) { Bash::Merge.merge_provider }

  let(:stable) { "stable() { :; }\n" }
  let(:provider_conformance) do
    {
      dialect: :bash,
      backend: :'kreuzberg-language-pack',
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: stable.sub(':;', 'echo changed;') },
        merge2: { current_source: stable, incoming_source: "#{stable}added() { :; }\n" },
        merge3: {
          base_source: stable,
          ours_source: "#{stable}ours() { :; }\n",
          theirs_source: "#{stable}theirs() { :; }\n"
        }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "broken() {\n",
        theirs_source: stable,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "obsolete() { :; }\n#{stable}",
          ours_source: "obsolete() { :; }\n#{stable}",
          theirs_source: stable
        },
        expected_value: [[:function, 'stable']]
      },
      parse_output: lambda { |source|
        provider.analyze(source: source).dig(:analysis, :declarations).map { |item| item.fetch(:signature) }
      }
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
