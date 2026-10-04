# frozen_string_literal: true

require 'json'

RSpec.describe Ast::Template::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled typed core is unavailable' unless described_class.available? }

  def fixture_root(slice, name)
    File.expand_path("../../../../../fixtures/diagnostics/slice-#{slice}-#{name}", __dir__)
  end

  def fixture(slice, name)
    JSON.parse(File.read(File.join(fixture_root(slice, name), "#{name}.json")))
  end

  def defaults
    { 'mode' => 'plan', 'template_root' => '', 'destination_root' => '', 'context' => {},
      'default_strategy' => 'merge', 'overrides' => [], 'replacements' => {}, 'allowed_families' => nil }
  end

  it 'preserves full valid and invalid options/profile reports from Slice 367' do
    data = fixture(367, 'template-directory-session-request-report')
    %w[options_valid options_invalid].each do |name|
      test_case = data.fetch(name)
      request = { kind: :options, options: test_case.fetch('options') }
      before = Marshal.dump(request)
      expect(provider.report(request)).to eq(test_case.fetch('expected').transform_keys(&:to_sym))
      expect(Marshal.dump(request)).to eq(before)
    end
    %w[profile_valid profile_invalid].each do |name|
      test_case = data.fetch(name)
      expect(provider.report(kind: 'profile', profile_name: test_case.fetch('profile'),
        profiles: data.fetch('profiles'), options: defaults.merge(test_case.fetch('overrides'))))
        .to eq(test_case.fetch('expected').transform_keys(&:to_sym))
    end
  end

  it 'preserves the complete Slice 362 directory plan and leaves both trees unchanged' do
    name = 'template-directory-session-options-report'
    root = fixture_root(362, name)
    test_case = fixture(362, name).fetch('plan_run')
    snapshot = lambda do
      Dir.glob(File.join(root, 'dry-run', '**', '*'), File::FNM_DOTMATCH)
        .select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
    end
    before = snapshot.call
    options = test_case.fetch('options').merge(
      'template_root' => File.join(root, 'dry-run', 'template'),
      'destination_root' => File.join(root, 'dry-run', 'destination'))
    expect(provider.plan(options: options))
      .to eq(test_case.fetch('expected').fetch('session_report').transform_keys(&:to_sym))
    expect(snapshot.call).to eq(before)
  end

  it 'preserves token configuration and optional-field omission without JSON transport' do
    config = { pre: '{{', post: '}}', separators: ['|'], min_segments: 1, max_segments: nil, segment_pattern: '[A-Z_]+' }
    options = defaults.merge('template_root' => '/not-read/templates', 'destination_root' => '/not-read/destination',
      'context' => { project_name: nil }, 'config' => config, 'allowed_families' => [])
    report = provider.report(kind: :options, options: options)
    expect(report.fetch(:resolved_options).fetch('context')).to eq({})
    expect(report.fetch(:resolved_options).fetch('config')).to eq(config.transform_keys(&:to_s).reject { |key, _| key == 'max_segments' })
    expect(report.fetch(:resolved_options).fetch('allowed_families')).to eq([])
    expect(Gem.loaded_specs.keys.grep(/host_prototype/)).to be_empty
  end

  it 'rejects malformed requests and refuses apply mode in the plan API' do
    expect { provider.report(kind: 'unknown', options: defaults) }.to raise_error(RuntimeError)
    expect { provider.report(kind: 'options', options: {}) }.to raise_error(RuntimeError)
    [nil, [], { kind: 'options', options: nil },
      { kind: 'options', options: defaults.merge('context' => nil) },
      { kind: 'options', options: defaults.merge('overrides' => {}) },
      { kind: 'options', options: defaults.merge('config' => false) },
      { kind: 'profile', profiles: nil, profile_name: 'x', options: defaults }].each do |request|
      expect { provider.report(request) }.to raise_error(RuntimeError)
    end
    expect { provider.plan(options: defaults.merge('mode' => 'apply')) }
      .to raise_error(RuntimeError, /template.request.invalid/)
  end
end
