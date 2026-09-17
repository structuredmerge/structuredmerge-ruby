# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Go::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  before(:context) do
    if File.basename(ENV.fetch('BUNDLE_GEMFILE', '')) == 'typed_core.gemfile' && !Go::Merge::RustHostProvider.available?
      raise 'The typed-core artifact test bundle must load structuredmerge-core'
    end
  end

  before { skip 'compiled typed core is unavailable' unless described_class.available? }

  before { Go::Merge.register_rust_host_provider!(replace: true) }

  let(:request_base) do
    {
      family: :go,
      dialect: :go,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }
  end
  let(:base_source) { "package main\n\nfunc left() int { return 1 }\n\nfunc right() int { return 1 }\n" }
  let(:ours_source) { "package main\n\nfunc left() int { return 2 }\n\nfunc right() int { return 1 }\n" }
  let(:theirs_source) { "package main\n\nfunc left() int { return 1 }\n\nfunc right() int { return 2 }\n" }

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
      expect(result.fetch(:provider)).to include(provider_id: 'rust.go', backend: :rust_tslp)
      expect(result.fetch(:verification)).to include(rust_core: true)
      expect(result.fetch(:ok)).to be(true), result.inspect
    end
  end

  it 'dispatches an explicitly selected Rust provider through the registry' do
    result = Ast::Merge.dispatch_provider(
      :merge2,
      request_base.merge(
        provider_id: 'rust.go',
        incoming_source: ours_source,
        current_source: base_source
      )
    )

    expect(result.fetch(:provider)).to include(provider_id: 'rust.go')
    expect(result.fetch(:verification)).to include(rust_core: true)
    expect(result.fetch(:ok)).to be(true), result.inspect
  end

  it 'preserves native merge3 output for independent function edits' do
    request = request_base.merge(
      base_source: base_source,
      ours_source: ours_source,
      theirs_source: theirs_source
    )

    native = Go::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'records the intentional current-preferred policy difference from native merge2' do
    request = request_base.merge(incoming_source: ours_source, current_source: base_source)
    native = Go::Merge::Provider.new.merge2(request)
    rust = provider.merge2(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(native.fetch(:output)).to eq(ours_source)
    expect(rust.fetch(:output)).to eq(base_source)
    expect(rust.fetch(:verification)).to include(directional_roles_preserved: true, output_reparsed: true)
  end

  it 'reports edits when declaration identity is unchanged' do
    result = provider.diff2(request_base.merge(before_source: base_source, after_source: ours_source))

    expect(result.fetch(:ok)).to be(true), result.inspect
    change = result.fetch(:changes).find { |entry| entry[:path] == '/function:left' }
    expect(change).to include(
      before: hash_including(present: true, source_role: :before, line_range: [3, 3]),
      after: hash_including(present: true, source_role: :after, line_range: [3, 3]),
      change: :edited
    )
  end

  it 'reports added and deleted declarations with explicit presence records' do
    after_source = "package main\n\nfunc left() int { return 1 }\n\nfunc added() int { return 4 }\n"
    result = provider.diff2(request_base.merge(before_source: base_source, after_source: after_source))

    expect(result.fetch(:ok)).to be(true), result.inspect
    deleted = result.fetch(:changes).find { |entry| entry[:path] == '/function:right' }
    added = result.fetch(:changes).find { |entry| entry[:path] == '/function:added' }
    expect(deleted).to include(
      before: hash_including(present: true, source_role: :before, line_range: [5, 5]),
      after: { present: false, source_role: :after, line_range: [nil, nil] },
      change: :deleted
    )
    expect(added).to include(
      before: { present: false, source_role: :before, line_range: [nil, nil] },
      after: hash_including(present: true, source_role: :after, line_range: [5, 5]),
      change: :added
    )
  end

  it 'fails closed on malformed source with a normalized parse diagnostic' do
    request = request_base.merge(source: "package main\nfunc {")
    result = provider.analyze(request)

    expect(result.fetch(:ok)).to be(false)
    expect(result.fetch(:provider)).to include(provider_id: 'rust.go')
    expect(result.fetch(:diagnostics).first).to include(category: :parse_error, blocking: true)
  end

  it 'preserves a localized conflict envelope for incompatible edits' do
    conflicting_theirs = base_source.sub('func left() int { return 1 }', 'func left() int { return 3 }')
    result = provider.merge3(
      request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: conflicting_theirs)
    )

    expect(result.fetch(:ok)).to be(false)
    expect(result.fetch(:provider)).to include(provider_id: 'rust.go')
    expect(result.fetch(:conflicts)).not_to be_empty
  end

  it 'matches native behavior for independently edited reordered declarations' do
    reordered_ours = base_source.sub(
      "func left() int { return 1 }\n\nfunc right() int { return 1 }",
      "func right() int { return 1 }\n\nfunc left() int { return 2 }"
    )
    reordered_theirs = base_source.sub(
      "func left() int { return 1 }\n\nfunc right() int { return 1 }",
      "func right() int { return 3 }\n\nfunc left() int { return 1 }"
    )
    request = request_base.merge(
      base_source: base_source,
      ours_source: reordered_ours,
      theirs_source: reordered_theirs
    )
    native = Go::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'preserves native comment and layout ownership for independent edits' do
    base = "package main\n\n// left documentation\nfunc left() int { return 1 }\n\n// right documentation\nfunc right() int { return 1 }\n"
    ours = base.sub('func left() int { return 1 }', 'func left() int { return 2 }')
    theirs = base.sub('func right() int { return 1 }', 'func right() int { return 2 }')
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Go::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
    expect(rust.fetch(:output)).to include('// left documentation', '// right documentation')
  end

  it 'matches native behavior for one-sided owner addition' do
    base = "package main\n\nfunc left() int { return 1 }\n\nfunc right() int { return 1 }\n"
    ours = base.sub('func left() int { return 1 }', 'func left() int { return 2 }')
    theirs = base.sub("func right() int { return 1 }\n", "func right() int { return 1 }\n\nfunc added() int { return 3 }\n")
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Go::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(false), native.inspect
    expect(rust.fetch(:ok)).to be(false), rust.inspect
    expect(native.fetch(:conflicts)).not_to be_empty
    expect(rust.fetch(:conflicts)).not_to be_empty
  end

  it 'projects native identities and byte spans after Unicode without host source lookup' do
    source = "package main\n// é\nfunc f() {}\n"
    result = provider.analyze(source: source)
    expect(result).to include(ok: true)
    expect(result.dig(:analysis, :declarations)).to contain_exactly(
      hash_including(path: '/function:f', line_range: [3, 3], byte_range: { 'start_byte' => 19, 'end_byte' => 30 })
    )
    expect(result.dig(:analysis, :facts, 'owners', 0, 'node_ids')).not_to be_empty
    expect(Ast::Merge::ProviderContract.validate_result!(:analyze, result)).to include(ok: true)
    expect(Gem.loaded_specs.keys).not_to include('structuredmerge_host_prototype')
  end

  it 'imports function comments into package-only current source without losing its footer' do
    result = provider.merge2(incoming_source: "package main\n\n// é new\nfunc f() {}\n",
      current_source: "// module\npackage main\n// footer\n")
    expect(result).to include(ok: true, output: "// module\npackage main\n\n// é new\nfunc f() {}\n// footer\n")
    expect(result.fetch(:verification)).to include(output_reparsed: true, directional_roles_preserved: true)
    rejected = provider.merge2(incoming_source: "package main\nimport \"fmt\"\nfunc f() { fmt.Println(1) }\n",
      current_source: "package main\n")
    expect(rejected).to include(ok: false, output: nil)
  end

  it 'retains full-document guard evidence without claiming an owner decision' do
    result = provider.merge3(base_source: base_source, ours_source: ours_source,
      theirs_source: base_source + "func added() {}\n")
    expect(result).to include(ok: false, output: nil)
    conflict = result.dig(:typed_result, :conflicts, 0, :canonical)
    expect(conflict).to include(code: 'go.membership_with_owner_edit', decision_ids: [])
    expect(conflict.fetch(:subject)).to include(whole_document: true)
    expect(conflict.fetch(:alternatives).length).to eq(3)
    expect(conflict.fetch(:classification)).to include(base_participated: true, decision_ids: [])
    expect(result.dig(:typed_result, :verification, :extra, 'owner_classification')).to be_nil
    expect(JSON.generate(result)).not_to include('#<StructuredmergeCore::')
  end

  it 'preserves trivia diffs and reparses exact no-op bytes deterministically' do
    source = "package main\n// é\nfunc f() {}"
    diff = provider.diff2(before_source: source, after_source: source.sub('// é', '// changed'))
    expect(diff).to include(ok: true)
    expect(diff.fetch(:changes)).to contain_exactly(hash_including(subject_ref: 'document', change: :edited))
    request = { base_source: source, ours_source: source, theirs_source: source }
    result = provider.merge3(request)
    expect(result).to include(ok: true, output: source)
    expect(result.fetch(:verification)).to include(output_reparsed: true)
    expect(JSON.generate(result)).to eq(JSON.generate(provider.merge3(request)))
  end

  it 'rejects unsupported selectors and marker policies while accepting neutral Git framing' do
    expect(provider.analyze(source: base_source, dialect: :bash)).to include(ok: false)
    expect(provider.analyze(source: base_source, comments: true)).to include(ok: false)
    request = { base_source: base_source, ours_source: base_source, theirs_source: base_source }
    expect(provider.merge3(request.merge(path_name: 'file.go', labels: {}, conflict_marker_size: '7'))).to include(ok: true)
    expect(provider.merge3(request.merge(conflict_marker_size: 8))).to include(ok: false)
    expect(provider.merge3(request.merge(labels: { ours: 'custom' }))).to include(ok: false)
    expect(provider.analyze(source: "\xFF".b)).to include(ok: false)
    bytes = base_source.b
    expect(provider.analyze(source: bytes)).to include(ok: true)
    expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)
  end
end
