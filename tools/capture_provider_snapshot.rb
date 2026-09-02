# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'optparse'
require 'rbconfig'
require 'ast/merge/rspec/provider_snapshot'

# Captures one Slice 1029 Ruby golden-master provider target. One invocation is
# one replay process; admission compares complete outputs from two invocations.
# rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists -- target orchestration mirrors the seven-row fixture manifest
class CaptureProviderSnapshot
  ADAPTER_ID = 'ruby.provider-contract-capture'
  ADAPTER_VERSION = '1'
  SNAPSHOT_SCHEMA = 'structuredmerge.provider-snapshot/v1'
  TARGETS = %w[
    snapshot.tslp.json
    snapshot.prism.ruby
    snapshot.psych.yaml
    snapshot.rbs.native
    snapshot.markdown.markly
    snapshot.toml.tslp
    snapshot.yaml.tslp
  ].freeze
  TARGET_BUILDERS = {
    'snapshot.tslp.json' => :json_definition,
    'snapshot.prism.ruby' => :prism_definition,
    'snapshot.psych.yaml' => :psych_definition,
    'snapshot.rbs.native' => :rbs_definition,
    'snapshot.markdown.markly' => :markly_definition,
    'snapshot.toml.tslp' => :toml_definition,
    'snapshot.yaml.tslp' => :yaml_definition
  }.freeze

  def initialize(argv)
    @options = { fixture_root: File.expand_path('../../fixtures', __dir__), allow_dirty: false }
    parser.parse!(argv)
    @target = argv.shift
    abort parser.to_s unless TARGETS.include?(@target)
    @ruby_root = File.expand_path('..', __dir__)
    assert_clean_producer!
  end

  def call
    definition = target_definition
    captures = definition.fetch(:sources).map do |source_definition|
      snapshot_for(definition, source_definition).capture
    end
    differential_replays = Array(definition[:merge2]).map do |request|
      snapshot_for(definition, definition.fetch(:sources).first).differential_replay(
        operation: :merge2,
        request: request.merge(
          provider_id: definition.fetch(:provider).provider_id,
          family: definition.fetch(:provider).family,
          dialect: definition.fetch(:dialect),
          backend: definition.fetch(:backend_id),
          profile_id: :source_preserving
        )
      )
    end

    document = {
      schema: SNAPSHOT_SCHEMA,
      snapshot_id: @target,
      producer: producer,
      workflow_provider: provider_identity(definition.fetch(:provider)),
      parser_backend: definition.fetch(:backend_identity),
      captures: captures,
      differential_replays: differential_replays,
      metadata: {
        fixture_repository_revision: git_output(@options.fetch(:fixture_root), 'rev-parse', 'HEAD'),
        capture_command: "bundle exec ruby tools/capture_provider_snapshot.rb #{@target}"
      }
    }
    puts Ast::Merge::RSpec::ProviderSnapshot.canonical_json(document)
  end

  private

  def parser
    @parser ||= OptionParser.new do |options|
      options.banner = 'Usage: bundle exec ruby tools/capture_provider_snapshot.rb TARGET [options]'
      options.on('--fixture-root PATH') { |path| @options[:fixture_root] = File.expand_path(path) }
      options.on('--allow-dirty') { @options[:allow_dirty] = true }
    end
  end

  def target_definition
    __send__(TARGET_BUILDERS.fetch(@target))
  end

  def json_definition
    require 'json/merge'
    fixture = fixture_json('diagnostics/slice-1024-normalized-parse-analysis-boundary/contract.json')
    source = fixture.dig('parse_request', 'source', 'content')
    tslp_definition(
      provider: Json::Merge.merge_provider,
      language: :json,
      dialect: :json,
      parser: 'tree-sitter-json',
      sources: [{ source_id: 'source:json:001', content: source }],
      merge2: [{ incoming_source: source, current_source: source }]
    )
  end

  def prism_definition
    require 'prism/merge'
    require 'prism/merge/rspec/provider_snapshot_extension'
    paths = %w[
      ruby/slice-935-prism-normalized-parse/class-method-normalized-tree.json
      ruby/slice-936-prism-comment-directive-metadata/comment-directives-normalized-tree.json
    ]
    {
      provider: Prism::Merge.merge_provider,
      language: :ruby,
      dialect: :ruby,
      backend_id: :prism,
      backend_identity: native_identity(
        :prism,
        'prism',
        'Prism',
        %w[comments directives exact_source_spans native_node_access normalized_tree]
      ),
      extension_builder: Prism::Merge::RSpec::ProviderSnapshotExtension.method(:call),
      sources: paths.map do |path|
        { source_id: "fixture:#{File.basename(path, '.json')}", content: fixture_json(path).fetch('source') }
      end,
      merge2: [{ incoming_source: fixture_json(paths.first).fetch('source'),
                 current_source: fixture_json(paths.first).fetch('source') }]
    }
  end

  def psych_definition
    require 'psych/merge'
    require 'psych/merge/rspec/provider_snapshot_extension'
    fixture = fixture_json('yaml/slice-721-formatting-preservation/comments-anchors-documents-sequences.json')
    {
      provider: Psych::Merge.merge_provider,
      language: :yaml,
      dialect: :yaml,
      backend_id: :psych,
      backend_identity: native_identity(
        :psych,
        'psych',
        'Psych',
        %w[aliases anchors documents native_extensions normalized_tree scalar_styles tags]
      ),
      extension_builder: Psych::Merge::RSpec::ProviderSnapshotExtension.method(:call),
      sources: [{ source_id: 'fixture:yaml:comments-anchors-documents-sequences', content: fixture.fetch('template') }],
      merge2: [{ incoming_source: fixture.fetch('template'), current_source: fixture.fetch('destination') }]
    }
  end

  def rbs_definition
    require 'rbs/merge'
    require 'rbs/merge/rspec/provider_snapshot_extension'
    {
      provider: Rbs::Merge.merge_provider,
      language: :rbs,
      dialect: :rbs,
      backend_id: :rbs,
      backend_identity: native_identity(
        :rbs,
        'rbs',
        'RBS::Parser',
        %w[native_extensions normalized_tree source_spans type_nodes]
      ),
      extension_builder: Rbs::Merge::RSpec::ProviderSnapshotExtension.method(:call),
      sources: [{
        source_id: 'fixture.rbs.class-method',
        content: "class User\n  def name: () -> String\nend\n"
      }],
      merge2: [{
        incoming_source: "class User\n  def name: () -> String\nend\n",
        current_source: "class User\n  def name: () -> String\nend\n"
      }]
    }
  end

  def markly_definition
    require 'markly/merge'
    require 'markly/merge/rspec/provider_snapshot_extension'
    fixture = fixture_json(
      'markdown/slice-721-provider-parity/headings-lists-tables-fences-links-frontmatter-comments.json'
    )
    source = fixture.fetch('source')
    {
      provider: Markly::Merge.merge_provider,
      language: :markdown,
      dialect: :markdown,
      backend_id: :markly,
      backend_identity: native_identity(
        :markly,
        'markly',
        'Markly',
        %w[attributes native_extensions normalized_tree source_positions]
      ),
      extension_builder: Markly::Merge::RSpec::ProviderSnapshotExtension.method(:call),
      sources: [{ source_id: 'fixture:markdown:provider-parity', content: source }],
      merge2: [{ incoming_source: source, current_source: source }]
    }
  end

  def toml_definition
    require 'toml/merge'
    fixture = fixture_json('toml/slice-721-formatting-preservation/dotted-inline-comments-arrays.json')
    tslp_definition(
      provider: Toml::Merge.merge_provider,
      language: :toml,
      dialect: :toml,
      parser: 'tree-sitter-toml',
      sources: [{ source_id: 'fixture:toml:dotted-inline-comments-arrays', content: fixture.fetch('template') }],
      merge2: [{ incoming_source: fixture.fetch('template'), current_source: fixture.fetch('destination') }]
    )
  end

  def yaml_definition
    require 'yaml/merge'
    fixture = fixture_json('yaml/slice-721-formatting-preservation/comments-anchors-documents-sequences.json')
    tslp_definition(
      provider: Yaml::Merge.merge_provider,
      language: :yaml,
      dialect: :yaml,
      parser: 'tree-sitter-yaml',
      sources: [{ source_id: 'fixture:yaml:comments-anchors-documents-sequences', content: fixture.fetch('template') }],
      merge2: [{ incoming_source: fixture.fetch('template'), current_source: fixture.fetch('destination') }]
    )
  end

  def tslp_definition(provider:, language:, dialect:, parser:, sources:, merge2: nil)
    backend_id = provider.capabilities.fetch(:backends).fetch(0)
    {
      provider: provider,
      language: language,
      dialect: dialect,
      backend_id: backend_id,
      backend_identity: {
        id: backend_id.to_s,
        family: 'tree-sitter',
        host_runtime: 'ruby',
        package: 'tree_sitter_language_pack',
        package_version: gem_version('tree_sitter_language_pack'),
        parser: parser,
        capabilities: %w[exact_source_spans native_extensions normalized_tree]
      },
      extension_builder: Ast::Merge::RSpec::ProviderSnapshot.method(:tree_sitter_extension),
      sources: sources,
      merge2: merge2
    }
  end

  def native_identity(id, package, parser, capabilities)
    {
      id: id.to_s,
      family: 'native',
      host_runtime: 'ruby',
      package: package,
      package_version: gem_version(package),
      parser: parser,
      capabilities: capabilities
    }
  end

  def snapshot_for(definition, source_definition)
    Ast::Merge::RSpec::ProviderSnapshot.new(
      snapshot_id: @target,
      source_id: source_definition.fetch(:source_id),
      provider: definition.fetch(:provider),
      source: source_definition.fetch(:content),
      language: definition.fetch(:language),
      dialect: definition.fetch(:dialect),
      backend_id: definition.fetch(:backend_id),
      backend_identity: definition.fetch(:backend_identity),
      extension_builder: definition.fetch(:extension_builder)
    )
  end

  def fixture_json(relative_path)
    JSON.parse(File.binread(File.join(@options.fetch(:fixture_root), relative_path)))
  end

  def provider_identity(provider)
    capabilities = provider.capabilities
    {
      provider_id: provider.provider_id,
      family: provider.family,
      role: capabilities.fetch(:role),
      capabilities: capabilities
    }
  end

  def producer
    loaded_specs = Gem.loaded_specs.values.sort_by(&:name).to_h do |specification|
      [specification.name, specification.version.to_s]
    end
    adapter_path = File.expand_path(__FILE__)
    {
      ruby_gm_release: gem_version('ast-merge'),
      ruby_gm_source_sha: git_output(@ruby_root, 'rev-parse', 'HEAD'),
      clean_source_state: git_status.empty?,
      dependency_versions: loaded_specs,
      ruby: {
        engine: RUBY_ENGINE,
        version: RUBY_VERSION,
        platform: RUBY_PLATFORM,
        host_os: RbConfig::CONFIG.fetch('host_os'),
        host_cpu: RbConfig::CONFIG.fetch('host_cpu')
      },
      environment_sha256: Digest::SHA256.hexdigest(
        Ast::Merge::RSpec::ProviderSnapshot.canonical_json(
          ENV.slice('TREE_HAVER_BACKEND', 'TREE_HAVER_NATIVE_BACKEND', 'TREE_HAVER_RUBY_BACKEND')
        )
      ),
      capture_adapter: {
        id: ADAPTER_ID,
        version: ADAPTER_VERSION,
        source_sha256: Digest::SHA256.file(adapter_path).hexdigest
      }
    }
  end

  def gem_version(name)
    Gem.loaded_specs.fetch(name).version.to_s
  end

  def assert_clean_producer!
    return if @options.fetch(:allow_dirty) || git_status.empty?

    abort 'Ruby golden-master worktree is dirty; commit changes before capture ' \
          'or use --allow-dirty for diagnostics only.'
  end

  def git_status
    git_output(@ruby_root, 'status', '--porcelain')
  end

  def git_output(root, *arguments)
    stdout, stderr, status = Open3.capture3('git', '-C', root, *arguments)
    abort stderr unless status.success?

    stdout.strip
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists

CaptureProviderSnapshot.new(ARGV).call if $PROGRAM_NAME == __FILE__
