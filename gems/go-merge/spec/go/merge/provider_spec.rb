# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- provider ownership, preservation, and conservative boundaries form one contract
RSpec.describe Go::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) do
    <<~GO
      package demo

      // Alpha docs.
      func Alpha() string {
        return "alpha"
      }

      func Beta() int {
        return 2
      }
    GO
  end

  it 'auto-registers ruby.go with the native source-preserving selector' do
    expect(provider).to have_attributes(provider_id: 'ruby.go', family: 'go')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[go],
      backends: [:'kreuzberg-language-pack'],
      profiles: %i[source_preserving],
      role: :workflow,
      grouped_declaration_ownership: :whole_declaration_with_stable_member_identity
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.go',
        family: :go,
        dialect: :go,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Go::Merge.merge_provider)
  end

  it 'analyzes package, import, declarations, and method receiver ownership without source regexes' do
    source = <<~GO
      package demo

      import alias "example.com/dependency"

      type Thing struct{}
      const Answer = 42
      var Name = "demo"
      func Top() {}
      func (receiver *Thing) Value() int { return 1 }
    GO
    signatures = provider.analyze(source: source).dig(:analysis, :declarations).map { |item| item.fetch(:signature) }

    expect(signatures).to eq(
      [
        [:package, 'demo'],
        [:import, ['alias', 'example.com/dependency']],
        [:type, 'Thing'],
        [:const, 'Answer'],
        [:var, 'Name'],
        [:function, 'Top'],
        [:method, 'Thing', 'Value']
      ]
    )
  end

  it 'analyzes every parenthesized declaration form as one whole owner' do
    source = <<~GO
      package demo
      import (
        "os"
        format "fmt"
      )
      type (
        Left struct{}
        Right struct{}
      )
      const (
        First = 1
        Second = 2
      )
      var (
        One, Two = 1, 2
        Three = 3
      )
    GO
    signatures = provider.analyze(source: source).dig(:analysis, :declarations).map { |item| item.fetch(:signature) }

    expect(signatures).to eq(
      [
        [:package, 'demo'],
        [:import_group, [[nil, 'os'], %w[format fmt]]],
        [:type_group, [%w[Left], %w[Right]]],
        [:const_group, [%w[First], %w[Second]]],
        [:var_group, [%w[One Two], ['Three']]]
      ]
    )
  end

  it 'uses the receiver type, not receiver variable or pointer marker, for method identity' do
    left = base.sub(
      'func Beta() int {',
      "type Thing struct{}\n\nfunc (left *Thing) Value() int { return 1 }\n\nfunc Beta() int {"
    )
    right = left.sub('(left *Thing)', '(right Thing)').sub('return 1', 'return 2')
    changes = provider.diff2(before_source: left, after_source: right).fetch(:changes)

    expect(changes).to include(hash_including(path: '[:method, "Thing", "Value"]', change: :edited))
  end

  it 'diffs additions, edits, and deletions with source roles and ranges' do
    after = base.sub('func Alpha', 'func Gamma').sub('return 2', 'return 3')
    result = provider.diff2(before_source: base, after_source: after)

    expect(result).to include(ok: true, operation: :diff2)
    expect(result.fetch(:changes).map { |change| change[:change] }).to contain_exactly(:deleted, :added, :edited)
    expect(result.fetch(:changes)).to include(
      hash_including(after: hash_including(source_role: :after, line_range: [8, 10]))
    )
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end

  it 'implements merge2 as the documented current/current/incoming overlay' do
    incoming = "#{base}func Incoming() {}\n"
    result = provider.merge2(current_source: base, incoming_source: incoming)

    expect(result).to include(ok: true, operation: :merge2, output: incoming)
    expect(result.dig(:verification, :semantic_match)).to be(true)
    expect(result.fetch(:verification)).not_to have_key(:base_participated)
  end

  it 'performs a true base-aware merge of independent top-level edits' do
    ours = base.sub('return "alpha"', 'return "ours"')
    theirs = base.sub('return 2', 'return 3')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true, output: ours.sub('return 2', 'return 3'))
    expect(result.dig(:render_report, :strategy)).to eq(:exact_declaration_composite)
    expect(result.fetch(:verification)).to include(
      output_reparsed: true,
      semantic_match: true,
      ast_attributes_verified: true,
      base_participated: true
    )
  end

  it 'honors an adversarial base deletion rather than substituting a two-way overlay' do
    obsolete = "func Obsolete() {}\n"
    old_base = base.sub("func Beta() int {\n", "#{obsolete}func Beta() int {\n")
    ours = "#{old_base}func Ours() {}\n"
    theirs = base
    result = provider.merge3(base_source: old_base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).not_to include('Obsolete')
    expect(result.fetch(:output)).to include('Ours')
  end

  it 'inserts independent imports before declarations and verifies the resulting Go AST' do
    imported_base = base.sub("package demo\n", "package demo\n\nimport \"fmt\"\n")
    ours = imported_base.sub('import "fmt"', "import \"fmt\"\nimport \"os\"")
    theirs = imported_base.sub('import "fmt"', "import \"fmt\"\nimport alias \"example.com/x\"")
    result = provider.merge3(base_source: imported_base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to start_with(
      "package demo\n\nimport \"fmt\"\nimport \"os\"\nimport alias \"example.com/x\"\n"
    )
    expect(result.dig(:verification, :output_reparsed)).to be(true)
  end

  it 'uses an existing import group as the insertion anchor without duplicating it' do
    imported_base = <<~GO
      package demo

      import (
        "fmt"
        "os"
      )

      func Alpha() { fmt.Println(os.Args) }
    GO
    ours = imported_base.sub('fmt.Println(os.Args)', 'fmt.Println(len(os.Args))')
    theirs = imported_base.sub(")\n", ")\nimport \"strings\"\n")
    result = provider.merge3(base_source: imported_base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to match(/\Apackage demo.*import \(\n.*\n\)\nimport "strings"\n\nfunc Alpha/m)
    expect(result.fetch(:output).scan("import (\n").length).to eq(1)
    expect(result.fetch(:output)).to include('fmt.Println(len(os.Args))')
  end

  it 'merges an import addition beside a same-line declaration replacement without cursor regression' do
    compact = "package demo\nimport \"fmt\"\nfunc Alpha() { fmt.Println(1) }\nfunc Beta() {}\n"
    ours = "#{compact}func Ours() {}\n"
    theirs = compact.sub(
      "import \"fmt\"\nfunc Alpha() { fmt.Println(1) }",
      "import \"fmt\"\nimport \"os\"\nfunc Alpha() { fmt.Println(os.Args) }"
    )
    result = provider.merge3(base_source: compact, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to eq(
      "package demo\nimport \"fmt\"\nimport \"os\"\nfunc Alpha() { fmt.Println(os.Args) }\n" \
      "func Beta() {}\nfunc Ours() {}\n"
    )
  end

  it 'owns trailing inline comments with the preceding declaration' do
    commented = "package demo\n\nfunc Alpha() {} // base docs\nfunc Beta() {}\n"
    ours = commented.sub('// base docs', '// ours docs')
    theirs = commented.sub('func Beta() {}', 'func Beta() { println("theirs") }')
    result = provider.merge3(base_source: commented, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to eq(
      "package demo\n\nfunc Alpha() {} // ours docs\nfunc Beta() { println(\"theirs\") }\n"
    )
  end

  it 'keeps same-named legacy method owners distinct by receiver' do
    source = <<~GO
      package demo
      type Left struct{}
      type Right struct{}
      func (left *Left) Value() {}
      func (right *Right) Value() {}
    GO
    analysis = Go::Merge.parse_go(source, 'go')

    expect(analysis.dig(:analysis, :declarations).map { |item| item[:path] }).to include(
      '/declarations/Left.Value',
      '/declarations/Right.Value'
    )
  end

  it 'preserves comments, blank layout, and a missing final newline for an exact winner' do
    exact = <<~'GO'.chomp
      // Package docs.
      package exact

      import "fmt"

      // spaced declaration
      func   Value( ) string { return fmt.Sprint("x") }
    GO
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.fetch(:verification)).to include(byte_exact: true, semantic_match: true, base_participated: true)
  end

  it 'keeps a grouped exact winner byte-exact without an exact-only diagnostic' do
    exact = <<~GO
      package demo

      import (
        "fmt"
        "os"
      )

      var (
        Left = fmt.Sprint("left")
        Right = os.Args
      )
    GO
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.fetch(:diagnostics)).to be_empty
    expect(result.dig(:verification, :byte_exact)).to be(true)
  end

  it 'merges independent function edits around an unchanged grouped import' do
    grouped = <<~GO
      package demo

      import (
        "fmt"
        "os"
      )

      func Alpha() { fmt.Println("alpha") }
      func Beta() { fmt.Println(os.Args) }
    GO
    result = provider.merge3(
      base_source: grouped,
      ours_source: grouped.sub('"alpha"', '"ours"'),
      theirs_source: grouped.sub('fmt.Println(os.Args)', 'fmt.Println(len(os.Args))')
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include('fmt.Println("ours")', 'fmt.Println(len(os.Args))')
  end

  it 'replaces an unchanged-membership var group as one whole owner for a one-sided edit' do
    grouped = <<~GO
      package demo

      var (
        Left = 1
        Right = 2
      )
    GO
    result = provider.merge3(
      base_source: grouped,
      ours_source: "#{grouped}func Ours() {}\n",
      theirs_source: grouped.sub('Right = 2', 'Right = 3')
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include("Right = 3\n", "func Ours() {}\n")
  end

  it 'replaces an unchanged-membership import group as one whole owner for a one-sided edit' do
    grouped = <<~GO
      package demo

      import (
        "fmt"
        // dependency used by Value
        alias "example.com/dependency"
      )

      func Value() { fmt.Println(alias.Value) }
    GO
    theirs = grouped.sub('// dependency used by Value', '// shared dependency used by Value')
    result = provider.merge3(
      base_source: grouped,
      ours_source: "#{grouped}func Ours() {}\n",
      theirs_source: theirs
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include('// shared dependency used by Value', "func Ours() {}\n")
  end

  it 'localizes divergent edits to the unchanged-membership group owner' do
    grouped = "package demo\n\nvar (\n  Left = 1\n  Right = 2\n)\n\nfunc Stable() {}\n"
    result = provider.merge3(
      base_source: grouped,
      ours_source: grouped.sub('Left = 1', 'Left = 10'),
      theirs_source: grouped.sub('Right = 2', 'Right = 20')
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :edit_edit, path: include(':var_group'))
    )
    expect(result.dig(:render_report, :strategy)).to eq(:declaration_localized_conflict)
    expect(result.fetch(:conflicted_output)).to end_with("func Stable() {}\n")
  end

  it 'blocks the full file with an explicit category when grouped membership changes' do
    grouped = "package demo\n\nvar (\n  Left = 1\n  Right = 2\n)\n"
    changed_memberships = [
      grouped.sub("  Right = 2\n", ''),
      grouped.sub("  Right = 2\n", "  Right = 2\n  Added = 3\n"),
      grouped.sub('Right = 2', 'Renamed = 2')
    ]

    changed_memberships.each do |theirs|
      result = provider.merge3(
        base_source: grouped,
        ours_source: "#{grouped}func Ours() {}\n",
        theirs_source: theirs
      )

      expect(result).to include(ok: false)
      expect(result.fetch(:conflicts)).to include(hash_including(category: :unproven_grouped_ownership))
      expect(result.fetch(:fallbacks)).to include(hash_including(reason: :grouped_member_identity_changed))
      expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
    end
  end

  it 'blocks grouped import path or alias identity changes instead of adding another group' do
    grouped = <<~GO
      package demo

      import (
        "fmt"
        alias "example.com/dependency"
      )

      func Value() { fmt.Println(alias.Value) }
    GO
    revisions = [
      grouped.sub('example.com/dependency', 'example.com/replacement'),
      grouped.sub('alias "example.com/dependency"', 'renamed "example.com/dependency"')
    ]

    revisions.each do |theirs|
      result = provider.merge3(
        base_source: grouped,
        ours_source: "#{grouped}func Ours() {}\n",
        theirs_source: theirs
      )

      expect(result).to include(ok: false)
      expect(result.fetch(:conflicts)).to contain_exactly(
        hash_including(category: :unproven_grouped_ownership)
      )
      expect(result.fetch(:conflicted_output).scan("import (\n").length).to eq(3)
    end
  end

  it 'allows multiple uniquely identifiable groups and rejects duplicate group owners' do
    unique = <<~GO
      package demo

      var (
        Left = 1
      )

      var (
        Right = 2
      )
    GO
    expect(provider.analyze(source: unique)).to include(ok: true)

    duplicate = unique.sub('Right = 2', 'Left = 2')
    result = provider.analyze(source: duplicate)
    expect(result).to include(ok: false, source_role: :source)
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :ambiguous_owner))
  end

  it 'diffs a grouped declaration as one whole owner' do
    before = "package demo\n\nconst (\n  Left = 1\n  Right = 2\n)\n"
    after = before.sub('Right = 2', 'Right = 3')
    result = provider.diff2(before_source: before, after_source: after)

    expect(result).to include(ok: true)
    expect(result.fetch(:changes)).to contain_exactly(
      hash_including(path: include(':const_group'), change: :edited)
    )
  end

  it 'analyzes even a single-member parenthesized declaration as a whole group owner' do
    source = "package demo\n\nvar (\n  Only = 1\n)\n"
    result = provider.analyze(source: source)

    expect(result).to include(ok: true)
    expect(result.dig(:analysis, :declarations)).to include(
      hash_including(signature: [:var_group, [['Only']]])
    )
  end

  it 'localizes a same-owner edit/edit conflict without touching stable source' do
    ours = base.sub('return "alpha"', 'return "ours"')
    theirs = base.sub('return "alpha"', 'return "theirs"')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.fetch(:conflicted_output)).to start_with("package demo\n\n<<<<<<< ours\n")
    expect(result.fetch(:conflicted_output)).to end_with("func Beta() int {\n  return 2\n}\n")
  end

  it 'fully conflicts an edit/delete because absent source cannot prove a localized replacement' do
    ours = base.lines.first(2).join + base.lines.drop(6).join
    theirs = base.sub('return "alpha"', 'return "theirs"')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :delete_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'conflicts unmanaged standalone comments or layout changes in a composite' do
    unmanaged = base.sub("package demo\n\n", "package demo\n\n// standalone\n\n")
    ours = unmanaged.sub('// standalone', '// changed standalone')
    theirs = unmanaged.sub('return 2', 'return 3')
    result = provider.merge3(base_source: unmanaged, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :unmanaged_source_change))
  end

  it 'rejects duplicate identities rather than auto-merging ambiguous declarations' do
    duplicate = "#{base}func Beta() int { return 4 }\n"
    result = provider.merge3(
      base_source: base,
      ours_source: duplicate,
      theirs_source: base.sub('return "alpha"', 'return "theirs"')
    )

    expect(result).to include(ok: false, source_role: :ours)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :ambiguous_owner))
  end

  it 'rejects package identity divergence as an unowned file boundary' do
    result = provider.merge3(
      base_source: base,
      ours_source: base.sub('package demo', 'package left'),
      theirs_source: base.sub('return 2', 'return 3')
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :package_identity_change))
  end

  it 'attributes malformed roles and keeps failures JSON serializable' do
    result = provider.merge3(
      base_source: base,
      ours_source: "package demo\nfunc Broken( {\n",
      theirs_source: base
    )

    expect(result).to include(ok: false, source_role: :ours)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :parse_error, message: /ours parse error/)
    )
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end
end

RSpec.describe 'Go::Merge provider conformance' do
  subject(:provider) { Go::Merge.merge_provider }

  let(:stable) { "package demo\n\nfunc Stable() {}\n" }
  let(:provider_conformance) do
    {
      dialect: :go,
      backend: :'kreuzberg-language-pack',
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: stable.sub('{}', '{ println("x") }') },
        merge2: { current_source: stable, incoming_source: "#{stable}func Added() {}\n" },
        merge3: {
          base_source: stable,
          ours_source: "#{stable}func Ours() {}\n",
          theirs_source: "#{stable}func Theirs() {}\n"
        }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "package demo\nfunc Broken( {\n",
        theirs_source: stable,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "package demo\n\nfunc Obsolete() {}\nfunc Stable() {}\n",
          ours_source: "package demo\n\nfunc Obsolete() {}\nfunc Stable() {}\n",
          theirs_source: stable
        },
        expected_value: [[:package, 'demo'], [:function, 'Stable']]
      },
      parse_output: lambda { |source|
        Go::Merge::FileAnalysis.new(source).declarations.map(&:signature)
      }
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
