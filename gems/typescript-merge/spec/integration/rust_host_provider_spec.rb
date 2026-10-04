# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TypeScript::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  before(:context) do
    if File.basename(ENV.fetch('BUNDLE_GEMFILE', '')) == 'typed_core.gemfile' && !TypeScript::Merge::RustHostProvider.available?
      raise 'The typed-core artifact test bundle must load structuredmerge-core'
    end
  end

  before { skip 'compiled typed core is unavailable' unless described_class.available? }

  before { TypeScript::Merge.register_rust_host_provider!(replace: true) }

  let(:request_base) do
    {
      family: :typescript,
      dialect: :typescript,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }
  end
  let(:base_source) do
    "function left(): number { return 1; }\nfunction right(): number { return 1; }\n"
  end
  let(:ours_source) do
    "function left(): number { return 2; }\nfunction right(): number { return 1; }\n"
  end
  let(:theirs_source) do
    "function left(): number { return 1; }\nfunction right(): number { return 2; }\n"
  end

  it 'satisfies the provider contract for every operation through the typed core' do
    expect(described_class.ancestors).not_to include(Ast::Merge::RustHostProvider)
    requests = {
      analyze: request_base.merge(source: base_source),
      diff2: request_base.merge(before_source: base_source, after_source: ours_source),
      merge2: request_base.merge(incoming_source: ours_source, current_source: base_source),
      merge3: request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: theirs_source)
    }

    requests.each do |operation, request|
      result = provider.public_send(operation, request)
      expect(Ast::Merge::ProviderContract.validate_result!(operation, result)).to eq(result)
      expect(result.fetch(:provider)).to include(provider_id: 'rust.typescript', backend: :rust_tslp)
      expect(result.fetch(:verification)).to include(rust_core: true)
      expect(result.fetch(:ok)).to be(true), result.inspect
    end
  end

  it 'dispatches an explicitly selected Rust provider through the registry' do
    result = Ast::Merge.dispatch_provider(
      :merge2,
      request_base.merge(
        provider_id: 'rust.typescript',
        incoming_source: ours_source,
        current_source: base_source
      )
    )

    expect(result.fetch(:provider)).to include(provider_id: 'rust.typescript')
    expect(result.fetch(:verification)).to include(rust_core: true)
    expect(result.fetch(:ok)).to be(true), result.inspect
  end

  it 'preserves native merge3 output for independent function edits' do
    request = request_base.merge(
      base_source: base_source,
      ours_source: ours_source,
      theirs_source: theirs_source
    )

    native = TypeScript::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'records the intentional current-preferred difference from native merge2' do
    request = request_base.merge(incoming_source: ours_source, current_source: base_source)
    native = TypeScript::Merge::Provider.new.merge2(request)
    rust = provider.merge2(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(native.fetch(:output)).to eq(ours_source)
    expect(rust.fetch(:output)).to eq(base_source)
    expect(rust.fetch(:verification)).to include(directional_roles_preserved: true, output_reparsed: true)
  end

  it 'preserves native comment and layout ownership for independent edits' do
    base = "// left documentation\nfunction left(): number { return 1; }\n\n// right documentation\nfunction right(): number { return 1; }\n"
    ours = base.sub('function left(): number { return 1; }', 'function left(): number { return 2; }')
    theirs = base.sub('function right(): number { return 1; }', 'function right(): number { return 2; }')
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = TypeScript::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
    expect(rust.fetch(:output)).to include('// left documentation', '// right documentation')
  end

  it 'supports the advertised TSX dialect through the typed core' do
    source = "interface Props { value: string }\nfunction Component(props: Props) { return <div>{props.value}</div>; }\n"
    result = provider.analyze(request_base.merge(dialect: :tsx, source: source))

    expect(result.fetch(:ok)).to be(true), result.inspect
    expect(result.fetch(:provider)).to include(dialect: :tsx)
    expect(result.fetch(:analysis).fetch(:declarations)).to include(
      include(path: '/function:Component'),
      include(path: '/interface:Props')
    )
  end

  it 'preserves native output for independent TSX edits' do
    base = <<~TSX
      interface Props { value: string }
      function left(props: Props) { return <div>{props.value}</div>; }
      function right() { return <span />; }
    TSX
    ours = base.sub('props.value', 'props.value.toUpperCase()')
    theirs = base.sub('return <span />;', 'return <strong />;')
    request = request_base.merge(
      dialect: :tsx,
      base_source: base,
      ours_source: ours,
      theirs_source: theirs
    )

    native = TypeScript::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'preserves native output for imports and declaration membership' do
    base = <<~TS
      import { value } from './shared';

      interface Props { value: string }
      function left(props: Props) { return props.value; }
      function right() { return value; }
    TS
    ours = base.sub('return props.value;', 'return props.value.toUpperCase();')
    theirs = base.sub('return value;', 'return value.trim();')
    request = request_base.merge(
      base_source: base,
      ours_source: ours,
      theirs_source: theirs
    )

    native = TypeScript::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
    expect(rust.fetch(:output)).to include("import { value } from './shared';", 'interface Props')
  end

  it 'preserves native output for independent single-variable edits' do
    base = "const left = 1;\n\nconst right = 1;\n"
    ours = base.sub('const left = 1', 'const left = 2')
    theirs = base.sub('const right = 1', 'const right = 2')
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = TypeScript::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
    expect(rust.fetch(:output)).to eq("const left = 2;\n\nconst right = 2;\n")
  end

  it 'fails closed when native ownership treats a multi-variable declaration as one owner' do
    base = "const left = 1, right = 2;\n"
    ours = base.sub('left = 1', 'left = 3')
    theirs = base.sub('right = 2', 'right = 4')
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = TypeScript::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(false), native.inspect
    expect(rust.fetch(:ok)).to be(false), rust.inspect
    expect(native.fetch(:conflicts)).not_to be_empty
    expect(rust.fetch(:diagnostics)).not_to be_empty
  end

  it 'reports edits when declaration identity is unchanged' do
    result = provider.diff2(request_base.merge(before_source: base_source, after_source: ours_source))

    expect(result.fetch(:ok)).to be(true), result.inspect
    change = result.fetch(:changes).find { |entry| entry[:path] == '/function:left' }
    expect(change).to include(
      before: hash_including(present: true, source_role: :before, line_range: [1, 1]),
      after: hash_including(present: true, source_role: :after, line_range: [1, 1]),
      change: :edited
    )
  end

  it 'fails closed on malformed source with a normalized parse diagnostic' do
    result = provider.analyze(request_base.merge(source: "function broken(: number { return 1; }\n"))

    expect(result.fetch(:ok)).to be(false)
    expect(result.fetch(:provider)).to include(provider_id: 'rust.typescript')
    expect(result.fetch(:diagnostics).first).to include(category: :parse_error, blocking: true)
  end

  it 'preserves a localized conflict envelope for incompatible edits' do
    conflicting_theirs = base_source.sub('return 1;', 'return 3;')
    result = provider.merge3(
      request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: conflicting_theirs)
    )

    expect(result.fetch(:ok)).to be(false)
    expect(result.fetch(:provider)).to include(provider_id: 'rust.typescript')
    expect(result.fetch(:conflicts)).not_to be_empty
    expect(result.dig(:typed_result, :conflicts, 0, :canonical)).not_to be_nil
    expect(JSON.generate(result)).not_to include('#<StructuredmergeCore::')
  end

  it 'retains native wrapper identities and UTF-8 spans without loading the prototype' do
    result = provider.analyze(source: "// é\nexport function f() {}\n")
    expect(result).to include(ok: true)
    expect(result.dig(:analysis, :declarations)).to contain_exactly(
      hash_including(path: '/function:f', byte_range: { 'start_byte' => 6, 'end_byte' => 28 })
    )
    expect(result.dig(:analysis, :facts, 'owners', 0, 'node_ids')).not_to be_empty
    expect(Gem.loaded_specs.keys).not_to include('structuredmerge_host_prototype')
  end

  it 'runs all four operations with the TSX grammar and rejects JSX as TypeScript' do
    source = "function View() { return <div>one</div>; }\n"
    changed = source.sub('>one<', '>two<')
    requests = {
      analyze: { source: source },
      diff2: { before_source: source, after_source: changed },
      merge2: { incoming_source: source, current_source: '' },
      merge3: { base_source: source, ours_source: source, theirs_source: changed }
    }
    requests.each do |operation, request|
      result = provider.public_send(operation, request.merge(dialect: :tsx))
      expect(result).to include(ok: true)
      expect(result.fetch(:provider)).to include(dialect: :tsx)
      expect(Ast::Merge::ProviderContract.validate_result!(operation, result)).to eq(result)
      expect(provider.public_send(operation, request.merge(dialect: :typescript))).to include(ok: false)
    end
  end

  it 'preserves document headers and copies native comments only with compatible imports' do
    incoming = "import { x } from 'x';\n/** é added */\nexport class Added {}\n"
    current = "// @ts-nocheck\nimport { x } from 'x';\n// footer\n"
    result = provider.merge2(incoming_source: incoming, current_source: current)
    expect(result).to include(ok: true, output: "// @ts-nocheck\nimport { x } from 'x';\n/** é added */\nexport class Added {}\n// footer\n")
    expect(result.fetch(:verification)).to include(output_reparsed: true, directional_roles_preserved: true)
    expect(provider.merge2(incoming_source: incoming.sub("'x'", "'y'"), current_source: current)).to include(ok: false, output: nil)
  end

  it 'reports import layout changes and deterministically reparses unchanged source' do
    source = "import { x } from 'x';\nfunction f() {}"
    diff = provider.diff2(before_source: source, after_source: source.sub("'x'", "'y'"))
    expect(diff).to include(ok: true)
    expect(diff.fetch(:changes)).to contain_exactly(hash_including(subject_ref: 'document', change: :edited))
    request = { base_source: source, ours_source: source, theirs_source: source }
    result = provider.merge3(request)
    expect(result).to include(ok: true, output: source)
    expect(result.fetch(:verification)).to include(output_reparsed: true)
    expect(JSON.generate(result)).to eq(JSON.generate(provider.merge3(request)))
  end

  it 'rejects unsupported selectors, syntax and framing without mutating caller bytes' do
    expect(provider.analyze(source: base_source, dialect: :javascript)).to include(ok: false)
    expect(provider.analyze(source: base_source, comments: true)).to include(ok: false)
    expect(provider.analyze(source: 'export const a = 1;')).to include(ok: false)
    request = { base_source: base_source, ours_source: base_source, theirs_source: base_source }
    expect(provider.merge3(request.merge(path_name: 'file.ts', labels: {}, conflict_marker_size: '7'))).to include(ok: true)
    expect(provider.merge3(request.merge(conflict_marker_size: 8))).to include(ok: false)
    expect(provider.merge3(request.merge(labels: { ours: 'custom' }))).to include(ok: false)
    expect(provider.analyze(source: "\xFF".b)).to include(ok: false)
    bytes = base_source.b
    expect(provider.analyze(source: bytes)).to include(ok: true)
    expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)
  end
end
