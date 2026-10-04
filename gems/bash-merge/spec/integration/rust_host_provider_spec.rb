# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bash::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  before(:context) do
    if File.basename(ENV.fetch('BUNDLE_GEMFILE', '')) == 'typed_core.gemfile' && !Bash::Merge::RustHostProvider.available?
      raise 'The typed-core artifact test bundle must load structuredmerge-core'
    end
  end

  before { skip 'compiled typed core is unavailable' unless described_class.available? }

  let(:request_base) do
    {
      family: :bash,
      dialect: :bash,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }
  end
  let(:base_source) { "left() { echo one; }\nright() { echo one; }\n" }
  let(:ours_source) { "left() { echo two; }\nright() { echo one; }\n" }
  let(:theirs_source) { "left() { echo one; }\nright() { echo two; }\n" }

  it 'satisfies the provider contract through the typed core without the prototype' do
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
      expect(result.fetch(:provider)).to include(provider_id: 'rust.bash', backend: :rust_tslp)
      expect(result.fetch(:verification)).to include(rust_core: true)
      expect(result.fetch(:ok)).to be(true), result.inspect
    end
  end

  it 'reports the ownership boundary for its portable subset' do
    expect(provider.capabilities.fetch(:ast_ownership)).to eq(:top_level_functions_assignments_and_literal_test_titles)
  end

  it 'dispatches an explicitly selected Rust Bash provider' do
    Bash::Merge.register_rust_host_provider!(replace: true)
    result = Ast::Merge.dispatch_provider(
      :merge2,
      request_base.merge(
        provider_id: 'rust.bash',
        incoming_source: ours_source,
        current_source: base_source
      )
    )

    expect(result.fetch(:provider)).to include(provider_id: 'rust.bash')
    expect(result.fetch(:verification)).to include(rust_core: true)
    expect(result.fetch(:ok)).to be(true), result.inspect
  end

  it 'preserves native output for independent function edits' do
    native = Bash::Merge::Provider.new.merge3(
      request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: theirs_source)
    )
    rust = provider.merge3(
      request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: theirs_source)
    )

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'preserves native output for independent variable and function edits' do
    base = "VALUE=one\nleft() { echo one; }\n"
    ours = "VALUE=two\nleft() { echo one; }\n"
    theirs = "VALUE=one\nleft() { echo two; }\n"
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'preserves native output for independent edits with leading comments' do
    base = "# left documentation\nleft() { echo one; }\n\n# right documentation\nright() { echo one; }\n"
    ours = base.sub('left() { echo one; }', 'left() { echo two; }')
    theirs = base.sub('right() { echo one; }', 'right() { echo two; }')
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
    expect(rust.fetch(:output)).to include('# left documentation', '# right documentation')
  end

  it 'preserves native output for comments and blank-line gaps between owners' do
    base = "# left documentation\nleft() { echo one; }\n\n# right documentation\nright() { echo one; }\n"
    ours = base.sub('left() { echo one; }', 'left() { echo two; }')
    theirs = base.sub('right() { echo one; }', 'right() { echo two; }')
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
    expect(rust.fetch(:output)).to include("\n\n# right documentation")
  end

  it 'preserves native output for literal test-harness edits' do
    base = "test_expect_success 'works' 'echo one'\n"
    ours = "test_expect_success 'works' 'echo two'\n"
    theirs = "test_expect_success 'works' 'echo one'\n"
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'preserves native output for literal test-harness prerequisites' do
    base = "test_expect_success PERL 'works' 'echo one'\n"
    ours = "test_expect_success PERL 'works' 'echo two'\n"
    theirs = base
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'projects native owner identities and spans without JSON assumptions' do
    source = "# é\nx=1\n\nf() { :; }\n"
    result = provider.analyze(source: source)
    expect(result).to include(ok: true)
    expect(result.dig(:analysis, :declarations)).to include(
      hash_including(path: '/variable:x', line_range: [2, 2]),
      hash_including(path: '/function:f', line_range: [4, 4])
    )
    expect(result.dig(:analysis, :facts, 'owners').map { |owner| owner.fetch('node_ids') }).to all(be_an(Array))
    diff = provider.diff2(before_source: source, after_source: source.sub('x=1', 'x=2'))
    expect(diff).to include(ok: true)
    owner = diff.fetch(:changes).find { |change| change[:path] == '/variable:x' }
    expect(owner).to include(change: :edited, before: hash_including(line_range: [2, 2]), after: hash_including(line_range: [2, 2]))
    expect(owner.dig(:before, :byte_range)).to eq('start_byte' => 5, 'end_byte' => 8)
    expect(diff.fetch(:changes)).to include(hash_including(subject_ref: 'document'))
    expect(JSON.generate(diff)).not_to include('#<StructuredmergeCore::')
    additions = provider.diff2(before_source: "x=1\n", after_source: "y=2\n")
    expect(additions).to include(ok: true)
    expect(additions.fetch(:changes)).to include(
      hash_including(path: '/variable:x', change: :deleted, after: hash_including(present: false)),
      hash_including(path: '/variable:y', change: :added, before: hash_including(present: false))
    )
  end

  it 'keeps current edits and imports only incoming additions with native comments' do
    result = provider.merge2(incoming_source: "x=1\n# é new\ny=2 # incoming\n",
      current_source: "x=9 # current\nz=3\n# footer\n")
    expect(result).to include(ok: true, output: "x=9 # current\nz=3\n# é new\ny=2 # incoming\n# footer\n")
    expect(result.fetch(:verification)).to include(directional_roles_preserved: true, output_reparsed: true)
    empty = provider.merge2(incoming_source: "x=1\n", current_source: '')
    expect(empty).to include(ok: true, output: "x=1\n")
  end

  it 'retains trivia-only diffs and reparses exact no-op output' do
    source = "# é\nx=1"
    diff = provider.diff2(before_source: source, after_source: "# changed\nx=1")
    expect(diff).to include(ok: true)
    expect(diff.fetch(:changes)).to contain_exactly(hash_including(subject_ref: 'document', change: :edited))
    result = provider.merge3(base_source: source, ours_source: source, theirs_source: source)
    expect(result).to include(ok: true, output: source)
    expect(result.fetch(:verification)).to include(output_reparsed: true, base_participated: true)
    expect(JSON.generate(result)).to eq(JSON.generate(provider.merge3(base_source: source, ours_source: source, theirs_source: source)))
  end

  it 'preserves canonical conflicts and rejects unsupported syntax and selectors' do
    conflict = provider.merge3(base_source: "x=1\n", ours_source: "x=2\n", theirs_source: "x=3\n")
    expect(conflict).to include(ok: false, output: nil)
    expect(conflict.fetch(:conflicts).length).to eq(1)
    expect(conflict.dig(:typed_result, :conflicts, 0, :canonical, :alternatives).length).to eq(3)
    expect(JSON.generate(conflict)).not_to include('#<StructuredmergeCore::')
    expect(provider.analyze(source: "echo unsupported\n")).to include(ok: false)
    expect(provider.analyze(source: "x=1\n", dialect: :json)).to include(ok: false)
    expect(provider.analyze(source: "x=1\n", comments: true)).to include(ok: false)
    expect(provider.merge3(base_source: "x=1\n", ours_source: "x=1\n", theirs_source: "x=1\n",
      path_name: 'script.sh', labels: {}, conflict_marker_size: '7')).to include(ok: true)
    expect(provider.merge3(base_source: "x=1\n", ours_source: "x=1\n", theirs_source: "x=1\n",
      conflict_marker_size: 8)).to include(ok: false)
    expect(provider.merge3(base_source: "x=1\n", ours_source: "x=1\n", theirs_source: "x=1\n",
      labels: { ours: 'custom' })).to include(ok: false)
    expect(provider.merge2(incoming_source: "b=2\nnew=3\na=1\n", current_source: "a=9\nb=9\n")).to include(ok: false, output: nil)
    expect(provider.analyze(source: "\xFF".b)).to include(ok: false)
    bytes = "# é\nx=1\n".b
    expect(provider.analyze(source: bytes)).to include(ok: true)
    expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)
    expect(Gem.loaded_specs.keys).not_to include('structuredmerge_host_prototype')
  end
end
