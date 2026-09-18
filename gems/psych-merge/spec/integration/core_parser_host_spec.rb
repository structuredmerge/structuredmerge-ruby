# frozen_string_literal: true

require 'digest'

RSpec.describe 'Installed Psych parser host for the typed kernel' do
  before(:context) do
    begin
      require 'psych/merge/core_parser_host'
    rescue LoadError
      raise if ENV['STRUCTUREDMERGE_TYPED_PSYCH_TEST'] == 'true'

      skip 'Optional generated structuredmerge-core is not installed'
    end
    unless Psych::Merge::CoreParserHost::SUPPORTED_PSYCH.satisfied_by?(Gem::Version.new(Psych::VERSION))
      raise 'Typed Psych artifact gate requires Psych 5.5.x' if ENV['STRUCTUREDMERGE_TYPED_PSYCH_TEST'] == 'true'

      skip 'Optional typed provider requires Psych 5.5.x'
    end
    expect(StructuredmergeCore.parser_registry_inventory.providers).to be_empty
    if ENV['STRUCTUREDMERGE_TYPED_PSYCH_TEST'] == 'true'
      %w[psych-merge structuredmerge-core].each do |name|
        expect(File.realpath(Gem.loaded_specs.fetch(name).full_gem_path)).to start_with(File.realpath(ENV.fetch('GEM_HOME')) + '/')
      end
    end
  end

  let(:core) { StructuredmergeCore }
  let(:host) { Psych::Merge::CoreParserHost.new }
  let(:limits) { core::ParseLimits.new(max_batch_items: 3, max_input_bytes: 100000, max_nodes: 10000, max_diagnostics: 20) }

  before { core.register_parser_host(host) }
  after { core.unregister_parser_host('ruby.psych') }

  def request(operation, texts)
    roles = {'analyze' => %w[source], 'diff2' => %w[before after], 'merge2' => %w[incoming current], 'merge3' => %w[base ours theirs]}.fetch(operation)
    sources = roles.zip(texts).to_h do |role, text|
      [role, core::OperationSource.new(source_id: role, role: role, content: text, encoding: 'utf-8',
        byte_length: text.bytesize, sha256: Digest::SHA256.hexdigest(text), extra: {})]
    end
    policy = case operation
    when 'analyze' then core::OperationPolicy.from_analyze(core::AnalyzePolicy.new(extra: {}))
    when 'diff2' then core::OperationPolicy.from_diff2(core::DiffPolicy.new(extra: {}))
    when 'merge2' then core::OperationPolicy.from_merge2(core::DirectionalMergePolicy.new(
      directional_merge: 'template-into-current', render_policy: 'source-preserving', extra: {}))
    else core::OperationPolicy.from_merge3(core::ThreeWayMergePolicy.new(
      render_policy: 'source-preserving', fallback_policy: 'none', extra: {}))
    end
    core::OperationRequest.new(schema: 'structuredmerge.operation-request/v1', request_id: operation,
      operation: policy, sources: sources, extensions: [], metadata: {}, extra: {},
      provider_selection: core::MergeProviderSelection.new(provider_id: 'kernel.yaml', family: 'yaml',
        profile_id: 'kernel.yaml.native_mapping.v1', required_capabilities: [operation], extra: {}),
      parser_selection: core::OperationParserSelection.new(backend: 'ruby.psych', preference: [], required_capabilities: [], extra: {}))
  end

  def parse_request(text, extensions: true, **options)
    descriptor = core::SourceDescriptor.new(source_id: 'source', role: :source, byte_length: text.bytesize,
      sha256: Digest::SHA256.hexdigest(text), encoding: :utf8, bom: text.b.start_with?("\xEF\xBB\xBF".b),
      final_newline: text.end_with?("\n"), line_endings: core::LineEndings.new(
        lf: text.count("\n") - text.scan("\r\n").size, crlf: text.scan("\r\n").size,
        bare_cr: text.count("\r") - text.scan("\r\n").size))
    core::ParseRequest.new(schema: 'structuredmerge.parse-request/v1', request_id: 'native',
      source: core::SourceInput.new(descriptor: descriptor, bytes: text.bytes), language: 'yaml',
      options: core::ParseOptions.new(native_extensions: extensions, **options),
      selection: core::ParserSelection.new(backend_id: 'ruby.psych', preference: [], required_capabilities: []), metadata: {}, extra: {})
  end

  it 'identifies the native-layer package separately from its parser and rejects unsupported probes' do
    descriptor = host.descriptor
    expect([descriptor.package, descriptor.package_version]).to eq(['psych-merge', Psych::Merge::Version::VERSION])
    expect([descriptor.parser, descriptor.parser_version]).to eq(['psych', Psych::VERSION])
    result = host.probe_batch(core::ProbeBatchRequest.new(items: [core::ParserProbeRequest.new(language: 'yaml'),
      core::ParserProbeRequest.new(language: 'python'), core::ParserProbeRequest.new(language: 'yaml', dialect: 'unknown')]))
    expect(result.items.map(&:available)).to eq([true, false, false])
  end

  it 'composes independent YAML edits in Rust and reparses the output through Psych' do
    result = core.execute_operation(request('merge3', ["a: 1\nb: 2\n", "a: 3\nb: 2\n", "a: 1\nb: 4\n"]), limits)
    expect(result.ok).to be(true), result.diagnostics.map { |entry| (entry.canonical || entry.migration).message }.inspect
    expect(result.output).to eq("a: 3\nb: 4\n")
    expect(result.provider.provider_id).to eq('kernel.yaml')
    expect(result.profile.parser.selected_backend).to eq('ruby.psych')
    expect(result.verification.output_reparsed).to be(true)
  end

  it 'rejects unverified Psych versions before invoking the native parser' do
    stub_const('Psych::VERSION', '5.3.1')
    expect(Psych).not_to receive(:parse_stream)
    probe = host.probe_batch(core::ProbeBatchRequest.new(items: [core::ParserProbeRequest.new(language: 'yaml')]))
    expect(probe.items.first.available).to be(false)
    result = host.parse_batch(core::ParseBatchRequest.new(items: [parse_request("a: 1\n")])).items.first
    expect(result.ok).to be(false)
    expect(result.diagnostics.first.code).to eq('psych.unsupported_version')
  end

  it 'reports competing edits as conflicts rather than a clean result' do
    result = core.execute_operation(request('merge3', ["a: 1\n", "a: 2\n", "a: 3\n"]), limits)
    expect(result.ok).to be(false)
    expect(result.output).to be_nil
    expect(result.conflicts).not_to be_empty
    expect(result.fallbacks).to be_empty
  end

  it 'executes a guarded kernel batch and rejects stale state and cancellation before callbacks' do
    workflows = core.workflow_registry_inventory
    parsers = core.parser_registry_inventory
    expected = core::WorkflowRegistryExpectation.new(provider_generation: workflows.generation,
      provider_digest: workflows.descriptor_digest, parser_generation: parsers.generation, parser_digest: parsers.descriptor_digest)
    batch = core::WorkflowBatchRequest.new(items: [core::WorkflowOperation.new(
      operation: request('analyze', ["a: 1\n"]), parser_language: 'yaml',
      parse_options: core::ParseOptions.new(native_extensions: true))])
    budget = core::WorkflowLimits.new(max_operations: 1, max_request_bytes: 1000000, max_response_bytes: 1000000, parse: limits)
    result = core.execute_workflow_batch_at_registry('kernel.yaml', batch, expected, budget)
    expect(result.execution_owner.to_s).to eq('kernel')
    expect(result.results.first.ok).to be(true)
    expect(result.approved_as_default).to be(false)
    core.unregister_parser_host('ruby.psych')
    core.register_parser_host(host)
    expect(host).not_to receive(:probe_batch)
    expect(host).not_to receive(:parse_batch)
    expect { core.execute_workflow_batch_at_registry('kernel.yaml', batch, expected, budget) }.to raise_error(RuntimeError, /workflow.registry_stale/)
    control = core.create_operation_control
    control.cancel
    expect { core.execute_workflow_batch_at_registry_controlled('kernel.yaml', batch, expected, budget, control) }.to raise_error(RuntimeError, /execution.cancelled/)
  end

  it 'preserves BOM, multibyte text, CRLF and absent final newline' do
    base = "\uFEFFé: one\r\nlast: old"
    Psych.parse_stream(base)
    parsed = core.parse_sources([parse_request(base)], limits).first.parsed
    expect(parsed.ok).to be(true), parsed.diagnostics.map { |diagnostic| [diagnostic.code, diagnostic.message] }.inspect
    result = core.execute_operation(request('merge3', [base, base.sub('one', 'two'), base.sub('old', 'new')]), limits)
    expect(result.ok).to be(true), result.diagnostics.map { |entry| (entry.canonical || entry.migration).message }.inspect
    expect(result.output.bytes).to eq("\uFEFFé: two\r\nlast: new".bytes)
  end

  it 'supplies native extensions only when requested and retains typed source identity' do
    batch = core::ParseBatchRequest.new(items: [parse_request("key: value\n", extensions: false)])
    result = host.parse_batch(batch).items.first
    expect(result.ok).to be(true)
    expect(result.source.sha256).to eq(batch.items.first.source.descriptor.sha256)
    expect(result.nodes).not_to be_empty
    expect(result.nodes.flat_map(&:extensions)).to be_empty
    extended = host.parse_batch(core::ParseBatchRequest.new(items: [parse_request("key: value\n")])).items.first
    expect(extended.nodes.flat_map(&:extensions)).not_to be_empty
  end

  it 'redacts malformed source and rejects unsupported coordinate and option modes' do
    [parse_request("private_secret: [\n"), parse_request("a: 1\rb: 2\r"),
      parse_request("a: 1\n", comments: true), parse_request("a: 1\n", tokens: true),
      parse_request("a: \xFF".b)].each do |item|
      result = host.parse_batch(core::ParseBatchRequest.new(items: [item])).items.first
      expect(result.ok).to be(false)
      expect(result.nodes).to be_empty
      expect(result.diagnostics.first.blocking).to be(true)
      expect(result.diagnostics.first.message).not_to include('private_secret')
    end
  end

  it 'performs analysis and diff in Rust without synthesizing unsupported merge2' do
    %w[analyze diff2].each do |operation|
      texts = operation == 'analyze' ? ["a: 1\n"] : ["a: 1\n", "a: 2\n"]
      result = core.execute_operation(request(operation, texts), limits)
      expect(result.ok).to be(true)
      expect(result.provider.provider_id).to eq('kernel.yaml')
    end
    unsupported = core.execute_operation(request('merge2', ["a: 1\n", "a: 2\n"]), limits)
    expect(unsupported.ok).to be(false)
    expect(unsupported.output).to be_nil
    expect(unsupported.diagnostics).not_to be_empty
    expect(unsupported.fallbacks).to be_empty
  end
end
