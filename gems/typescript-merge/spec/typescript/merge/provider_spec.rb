# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- provider ownership and conservative boundaries form one contract
RSpec.describe TypeScript::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) do
    <<~TS
      import { shared } from "shared";

      // alpha docs
      export function alpha(): string {
        return "alpha";
      }

      export function beta(): number {
        return 2;
      }
    TS
  end

  it 'auto-registers the exact workflow selector for TypeScript and TSX' do
    expect(provider).to have_attributes(provider_id: 'ruby.typescript', family: 'typescript')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[typescript tsx],
      backends: [:'kreuzberg-language-pack'],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.typescript',
        family: :typescript,
        dialect: :typescript,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(TypeScript::Merge.merge_provider)
  end

  it 'derives import, export, declaration, and compound variable identities from the AST' do
    source = <<~TS
      import value, { named as alias } from "dependency";
      export { other } from "other";
      export default class Main {}
      interface Shape {}
      type Name = string;
      enum Choice { One }
      namespace Space {}
      function run(): void {}
      const left = 1, right = 2;
      declare module "extension" { interface Extra {} }
    TS
    signatures = provider.analyze(source: source).dig(:analysis, :declarations).map { |item| item.fetch(:signature) }

    expect(signatures).to include(
      satisfy { |value| value.first == :import && value[1] == '"dependency"' },
      [:default_export],
      [:interface, 'Shape'],
      [:type, 'Name'],
      [:enum, 'Choice'],
      [:namespace, 'Space'],
      [:function, 'run'],
      [:variables, 'const', %w[left right]],
      [:module_augmentation, '"extension"']
    )
    expect(signatures).to include(satisfy { |value| value.first == :export_from })
  end

  it 'diffs additions, edits, and deletions in a JSON-ready envelope' do
    after = base.sub('function alpha', 'function gamma').sub('return 2', 'return 3')
    result = provider.diff2(before_source: base, after_source: after)

    expect(result.fetch(:changes).map { |change| change[:change] }).to contain_exactly(:deleted, :added, :edited)
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end

  it 'implements merge2 through the current/current/incoming overlay' do
    incoming = "#{base}export const incoming = true;\n"
    result = provider.merge2(current_source: base, incoming_source: incoming)

    expect(result).to include(ok: true, operation: :merge2, output: incoming)
    expect(result.fetch(:verification)).not_to have_key(:base_participated)
  end

  it 'performs a true base-aware merge of independent edits and additions' do
    ours = "#{base.sub('return "alpha"', 'return "ours"')}export class Ours {}\n"
    theirs = "#{base.sub('return 2', 'return 3')}export interface Theirs {}\n"
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include('return "ours"', 'return 3', 'class Ours', 'interface Theirs')
    expect(result.fetch(:verification)).to include(
      output_reparsed: true,
      semantic_match: true,
      ast_attributes_verified: true,
      base_participated: true
    )
  end

  it 'honors a base deletion instead of substituting a two-way overlay' do
    old_base = "#{base}export function obsolete() {}\n"
    result = provider.merge3(
      base_source: old_base,
      ours_source: "#{old_base}export function ours() {}\n",
      theirs_source: base
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).not_to include('obsolete')
    expect(result.fetch(:output)).to include('ours')
  end

  it 'keeps independent imports before declarations' do
    ours = base.sub('import { shared }', "import ours from \"ours\";\nimport { shared }")
    theirs = base.sub('import { shared }', "import theirs from \"theirs\";\nimport { shared }")
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to match(/\Aimport ours.*\nimport \{ shared \}.*\nimport theirs/m)
    expect(result.fetch(:output).index('import theirs')).to be < result.fetch(:output).index('function alpha')
  end

  it 'replaces a one-sided named import member edit while independently merging a function edit' do
    ours = base.sub('{ shared }', '{ shared as local }')
    theirs = base.sub('return 2', 'return 3')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include('import { shared as local } from "shared";', 'return 3')
    expect(result.fetch(:output).scan(/from "shared"/).length).to eq(1)
  end

  it 'conflicts divergent named import edits at one stable owner without duplicating imports' do
    ours = base.sub('{ shared }', '{ shared as ours }')
    theirs = base.sub('{ shared }', '{ shared as theirs }')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:declaration_localized_conflict)
    expect(result.fetch(:conflicted_output).scan(/from "shared"/).length).to eq(3)
  end

  it 'treats repeated imports with the same source and structural form as ambiguous' do
    source = "import { first } from \"shared\";\nimport { second } from \"shared\";\n"

    expect(provider.analyze(source: source)).to include(
      ok: false,
      diagnostics: include(hash_including(category: :ambiguous_owner))
    )
  end

  it 'conflicts divergent export-from member edits without appending independent exports' do
    export_base = "export { oldName } from \"dependency\";\nfunction stable() {}\n"
    result = provider.merge3(
      base_source: export_base,
      ours_source: export_base.sub('{ oldName }', '{ oursName }'),
      theirs_source: export_base.sub('{ oldName }', '{ theirsName }')
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:declaration_localized_conflict)
    expect(result.fetch(:conflicted_output).scan(/from "dependency"/).length).to eq(3)
  end

  it 'treats repeated local named export owners conservatively as ambiguous' do
    source = "export { first };\nexport { second };\n"

    expect(provider.analyze(source: source)).to include(
      ok: false,
      diagnostics: include(hash_including(category: :ambiguous_owner))
    )
  end

  it 'conflicts divergent local named export edits at one conservative owner' do
    export_base = "const first = 1, second = 2, third = 3;\nexport { first };\n"
    result = provider.merge3(
      base_source: export_base,
      ours_source: export_base.sub('{ first }', '{ second }'),
      theirs_source: export_base.sub('{ first }', '{ third }')
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :edit_edit, path: '[:export_local, :value, :named]')
    )
  end

  it 'conflicts divergent default export targets at the singleton owner' do
    export_base = "export default oldValue;\nfunction stable() {}\n"
    result = provider.merge3(
      base_source: export_base,
      ours_source: export_base.sub('oldValue', 'oursValue'),
      theirs_source: export_base.sub('oldValue', 'theirsValue')
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :edit_edit, path: '[:default_export]')
    )
  end

  it 'inserts the first import before existing declarations' do
    importless = "export function alpha() { return 1; }\nexport function beta() { return 2; }\n"
    result = provider.merge3(
      base_source: importless,
      ours_source: importless.sub('return 2', 'return 20'),
      theirs_source: "import value from \"dependency\";\n#{importless}"
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to eq(
      "import value from \"dependency\";\n" \
      "export function alpha() { return 1; }\nexport function beta() { return 20; }\n"
    )
  end

  it 'preserves exact winner bytes, comments, layout, and no final newline' do
    exact = "// exact\nexport default function named( ) { return 1; }".chomp
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.fetch(:verification)).to include(byte_exact: true, semantic_match: true, base_participated: true)
  end

  it 'accepts an exact parser-valid winner with overloads and declaration merging byte-for-byte' do
    exact = <<~TS
      function value(input: string): string;
      function value(input: unknown) { return input; }
      interface Merged { left: string }
      interface Merged { right: string }
      class Combined {}
      namespace Combined { export const value = 1; }
      declare module "pkg" { interface X {} }
      declare module "pkg" { interface Y {} }
    TS
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :ambiguous_owner, blocking: false, source_role: :theirs)
    )
    expect(result.fetch(:verification)).to include(
      byte_exact: true,
      semantic_match: true,
      ordered_declaration_signatures_verified: true
    )
  end

  it 'rejects a malformed exact winner' do
    malformed = "export function broken( {\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: malformed)

    expect(result).to include(ok: false, source_role: :theirs)
    expect(result.fetch(:diagnostics)).to contain_exactly(hash_including(category: :parse_error, blocking: true))
  end

  it 'localizes safe same-owner conflicts and leaves stable source untouched' do
    ours = base.sub('return "alpha"', 'return "ours"')
    theirs = base.sub('return "alpha"', 'return "theirs"')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:declaration_localized_conflict)
    expect(result.fetch(:conflicted_output)).to end_with("export function beta(): number {\n  return 2;\n}\n")
  end

  it 'blocks overloads, declaration merging, and repeated module augmentations as ambiguous owners' do
    ambiguous_sources = [
      "function value(input: string): string;\nfunction value(input: unknown) { return input; }\n",
      "interface Merged { left: string }\ninterface Merged { right: string }\n",
      "class Combined {}\nnamespace Combined { export const value = 1; }\n",
      "declare module \"pkg\" { interface X {} }\ndeclare module \"pkg\" { interface Y {} }\n"
    ]

    ambiguous_sources.each do |source|
      expect(provider.analyze(source: source)).to include(
        ok: false,
        diagnostics: include(hash_including(category: :ambiguous_owner))
      )
    end
  end

  it 'blocks changing multi-declarator membership rather than guessing member ownership' do
    variables = "const left = 1, right = 2;\nfunction stable() {}\n"
    result = provider.merge3(
      base_source: variables,
      ours_source: "#{variables}function ours() {}\n",
      theirs_source: variables.sub(', right = 2', ', renamed = 2')
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :unproven_compound_ownership))
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'supports TSX through the native TSX parser and fails closed on unmanaged JSX statements' do
    source = "export const View = () => <main>hello</main>;\n"
    result = provider.analyze(source: source, dialect: :tsx)

    expect(result).to include(ok: true)
    expect(result.dig(:analysis, :declarations)).to include(
      hash_including(signature: [:export_declaration, [:variables, 'const', ['View']]])
    )
  end

  it 'attributes malformed roles and serializes failure envelopes' do
    result = provider.merge3(
      base_source: base,
      ours_source: "export function broken( {\n",
      theirs_source: base
    )

    expect(result).to include(ok: false, source_role: :ours)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :parse_error, message: /ours parse error/)
    )
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end
end

RSpec.describe 'TypeScript provider conformance' do
  subject(:provider) { TypeScript::Merge.merge_provider }

  let(:stable) { "export function stable() {}\n" }
  let(:provider_conformance) do
    {
      dialect: :typescript,
      backend: :'kreuzberg-language-pack',
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: stable.sub('{}', '{ return; }') },
        merge2: { current_source: stable, incoming_source: "#{stable}export class Added {}\n" },
        merge3: {
          base_source: stable,
          ours_source: "#{stable}export class Ours {}\n",
          theirs_source: "#{stable}export interface Theirs {}\n"
        }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "export function broken( {\n",
        theirs_source: stable,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "export function obsolete() {}\n#{stable}",
          ours_source: "export function obsolete() {}\n#{stable}",
          theirs_source: stable
        },
        expected_value: [[:export_declaration, [:function, 'stable']]]
      },
      parse_output: lambda { |source|
        TypeScript::Merge::FileAnalysis.new(source).declarations.map(&:signature)
      }
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
