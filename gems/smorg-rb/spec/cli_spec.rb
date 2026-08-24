# frozen_string_literal: true

require 'English'
require 'json'

require_relative 'spec_helper'

RSpec.describe Smorg::RB do
  def write_file(dir, name, source)
    path = File.join(dir, name)
    File.write(path, source)
    path
  end

  def git_driver_json_fixture
    path = File.expand_path(
      '../../../../fixtures/diagnostics/slice-951-git-driver-json-integration/git-driver-json-integration.json', __dir__
    )
    JSON.parse(File.read(path))
  end

  def git_driver_fallback_fixture
    path = File.expand_path('../../../../fixtures/diagnostics/slice-954-git-driver-fallback/git-driver-fallback.json',
                            __dir__)
    JSON.parse(File.read(path))
  end

  def git_install_report_fixture
    path = File.expand_path(
      '../../../../fixtures/diagnostics/slice-1017-git-driver-opt-in-setup/git-install-report.json', __dir__
    )
    JSON.parse(File.read(path))
  end

  def diff_driver_smoke_fixture
    path = File.expand_path(
      '../../../../fixtures/diagnostics/slice-903-diff-driver-smoke-fixtures/diff-driver-smoke-fixtures.json', __dir__
    )
    JSON.parse(File.read(path))
  end

  def run_git(dir, *args)
    return skip('git executable is required for repository integration fixture') unless system('git', '--version',
                                                                                               out: File::NULL, err: File::NULL)

    output = IO.popen([{ 'GIT_CONFIG_NOSYSTEM' => '1' }, 'git', *args], chdir: dir, err: %i[child out], &:read)
    return if $CHILD_STATUS.success?

    raise "git #{args.join(' ')} failed:\n#{output}"
  end

  around do |example|
    Dir.mktmpdir('smorg-rb-test-') do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    end
  end

  it 'updates the current file in merge-driver mode' do
    ancestor = write_file(@dir, 'ancestor.json', '{"name":"structuredmerge"}')
    current = write_file(@dir, 'current.tmp', '{"name":"structuredmerge","current":true}')
    other = write_file(@dir, 'other.tmp', '{"name":"structuredmerge","other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', '--path-name', 'package.json', ancestor, current, other],
                                    stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    merged = File.read(current)
    expect(JSON.parse(merged)).to include('current' => true, 'other' => true)
    expect(stdout.string).to eq('')
  end

  it 'uses smorg.language from gitattributes' do
    File.write('.gitattributes', "*.data smorg.language=json\n")
    ancestor = write_file(@dir, 'ancestor.tmp', '{"name":"structuredmerge"}')
    current = write_file(@dir, 'current.tmp', '{"name":"structuredmerge","current":true}')
    other = write_file(@dir, 'other.tmp', '{"name":"structuredmerge","other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', ancestor, current, other, 'package.data'], stdout: stdout,
                                                                                                stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    merged = File.read(current)
    expect(JSON.parse(merged)).to include('current' => true, 'other' => true)
  end

  it 'merges JSON5 paths advertised by gitattributes' do
    File.write('.gitattributes', "*.json5 smorg.language=json5\n")
    ancestor = write_file(@dir, 'ancestor.tmp', "{ name: 'structuredmerge', }")
    current = write_file(@dir, 'current.tmp', "{ name: 'structuredmerge', current: true, }")
    other = write_file(@dir, 'other.tmp', "{ name: 'structuredmerge', other: true, }")
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', ancestor, current, other, 'package.json5'], stdout: stdout,
                                                                                                 stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to include('current: true', 'other: true')
  end

  it 'routes TOML through the base-aware workflow and propagates its exact report' do
    ancestor = write_file(@dir, 'ancestor.toml', "obsolete = true\nstable = true\n")
    current = write_file(@dir, 'current.tmp', "obsolete = true\nstable = true\nours = 'left'\n")
    other = write_file(@dir, 'other.tmp', "stable = true\ntheirs = { enabled = true }\n")
    report_path = File.join(@dir, 'merge-report.json')
    stdout = StringIO.new
    stderr = StringIO.new

    expect(Toml::Merge::SmartMerger).not_to receive(:new)
    exit_code = described_class.run(
      ['merge-driver', '--report', report_path, '--path-name', 'config.toml', ancestor, current, other],
      stdout: stdout,
      stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to eq("stable = true\nours = 'left'\ntheirs = { enabled = true }\n")
    report = JSON.parse(File.read(report_path))
    expect(report.fetch('ok')).to be(true)
    expect(report.dig('provider', 'provider_id')).to eq('ruby.toml')
    expect(report.dig('provider', 'backend')).to eq('kreuzberg-language-pack')
    expect(report.dig('verification', 'base_participated')).to be(true)
    expect(report.dig('render_report', 'strategy')).to eq('exact_mapping_entry_composite')
  end

  it 'installs local Git diff driver attributes' do
    fixture = git_install_report_fixture
    stdout = StringIO.new
    stderr = StringIO.new
    run_git(@dir, 'init')

    exit_code = described_class.run(['git', 'install', '--json'], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    report = JSON.parse(stdout.string)
    expected = fixture.fetch('report')
    expect(report.fetch('report_version')).to eq(expected.fetch('report_version'))
    expect(report.fetch('ok')).to eq(expected.fetch('ok'))
    expect(report.fetch('profile')).to eq(expected.fetch('profile'))
    expect(report.fetch('scope')).to eq(expected.fetch('scope'))
    expect(report.fetch('install_steps').first).to include(expected.fetch('step'))
    diagnostic_keys = report.fetch('install_steps').flat_map do |step|
      step.fetch('diagnostics', [])
    end.map { |diagnostic| diagnostic.fetch('key') }
    expect(diagnostic_keys).to include(*expected.fetch('diagnostic_keys'))
    expect(File.read('.gitattributes')).to include(fixture.dig('implementations', 'ruby', 'attribute_contains'))
  end

  it 'supports builtin Git diff driver install profile' do
    stdout = StringIO.new
    stderr = StringIO.new
    run_git(@dir, 'init')

    exit_code = described_class.run(['git', 'install', '--profile', 'builtin-diff'], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(stdout.string).to include('git install: succeeded builtin-diff local')
    expect(File.read('.gitattributes')).to include('*.rb diff=ruby')
  end

  it 'routes Markdown paths through the Markdown merge backend' do
    ancestor = write_file(@dir, 'ancestor.md', "# Usage\n\nBase usage.\n")
    current = write_file(
      @dir,
      'current.md',
      "# Usage\n\nBase usage.\n\n# Local\n\nKeep local notes.\n"
    )
    other = write_file(
      @dir,
      'other.md',
      "# Usage\n\nBase usage.\n\n# Remote\n\nInclude remote notes.\n"
    )
    report = File.join(@dir, 'markdown-report.json')
    stdout = StringIO.new
    stderr = StringIO.new

    expect(Plain::Merge).not_to receive(:merge_text)
    exit_code = described_class.run(
      ['merge-driver', '--report', report, ancestor, current, other, 'README.md'],
      stdout: stdout,
      stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    merged = File.read(current)
    expect(merged).to include("# Local\n\nKeep local notes.")
    expect(merged).to include("# Remote\n\nInclude remote notes.")
    expect(JSON.parse(File.read(report)).dig('provider', 'provider_id')).to eq('ruby.markdown')
  end

  it 'fails closed instead of using the removed two-way Markdown containment heuristic' do
    ancestor = write_file(
      @dir,
      'ancestor.md',
      "# Links\n\nRead http://example.com/posts/old-page/ for details.\n"
    )
    current_source = [
      '# Links',
      '',
      'Read',
      'https://example.com/docs/new-page/',
      'for details.',
      '',
      '# Local',
      '',
      'Keep local notes.',
      ''
    ].join("\n")
    current = write_file(@dir, 'current.md', current_source)
    other = write_file(
      @dir,
      'other.md',
      "# Links\n\nRead https://example.com/docs/new-page/ for details.\n"
    )
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', ancestor, current, other, 'README.md'], stdout: stdout,
                                                                                             stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    expect(File.read(current)).to include('<<<<<<< ours', '||||||| base', '>>>>>>> theirs', '# Local')
  end

  it 'advertises Markdown paths in generated gitattributes' do
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['languages', '--gitattributes'], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(stdout.string).to include('*.bash merge=smorg-rb diff=smorg-rb smorg.language=bash')
    expect(stdout.string).to include('*.sh merge=smorg-rb diff=smorg-rb smorg.language=bash')
    expect(stdout.string).to include('*.md merge=smorg-rb diff=smorg-rb smorg.language=markdown')
    expect(stdout.string).to include('*.markdown merge=smorg-rb diff=smorg-rb smorg.language=markdown')
    expect(stdout.string).to include('*.json5 merge=smorg-rb diff=smorg-rb smorg.language=json5')
    expect(stdout.string).to include('*.go merge=smorg-rb diff=smorg-rb smorg.language=go')
    expect(stdout.string).to include('*.htm merge=smorg-rb diff=smorg-rb smorg.language=html')
    expect(stdout.string).to include('*.html merge=smorg-rb diff=smorg-rb smorg.language=html')
    expect(stdout.string).to include('*.rb merge=smorg-rb diff=smorg-rb smorg.language=ruby')
    expect(stdout.string).to include('*.rbs merge=smorg-rb diff=smorg-rb smorg.language=rbs')
    expect(stdout.string).to include('*.rs merge=smorg-rb diff=smorg-rb smorg.language=rust')
    expect(stdout.string).to include('*.ts merge=smorg-rb diff=smorg-rb smorg.language=typescript')
    expect(stdout.string).to include('*.tsx merge=smorg-rb diff=smorg-rb smorg.language=tsx')
    expect(stdout.string).to include('*.yml merge=smorg-rb diff=smorg-rb smorg.language=yaml')
    expect(stdout.string).to include('*.yaml merge=smorg-rb diff=smorg-rb smorg.language=yaml')
    expect(stdout.string).to include('*.env merge=smorg-rb diff=smorg-rb smorg.language=dotenv')
    expect(stdout.string).to include('.env merge=smorg-rb diff=smorg-rb smorg.language=dotenv')
  end

  it 'routes Go paths only through the exact base-aware provider' do
    ancestor = write_file(@dir, 'ancestor.go', "package demo\n\nfunc Obsolete() {}\nfunc Stable() {}\n")
    current = write_file(
      @dir,
      'current.tmp',
      "package demo\n\nfunc Obsolete() {}\nfunc Stable() {}\nfunc Ours() {}\n"
    )
    other = write_file(@dir, 'other.tmp', "package demo\n\nfunc Stable() {}\nfunc Theirs() {}\n")
    report_path = File.join(@dir, 'go-report.json')
    stdout = StringIO.new
    stderr = StringIO.new

    expect(Go::Merge).not_to receive(:merge_go)
    exit_code = described_class.run(
      ['merge-driver', '--report', report_path, '--path-name', 'example.go', ancestor, current, other],
      stdout: stdout,
      stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to eq("package demo\n\nfunc Stable() {}\nfunc Ours() {}\nfunc Theirs() {}\n")
    report = JSON.parse(File.read(report_path))
    expect(report.dig('provider', 'provider_id')).to eq('ruby.go')
    expect(report.dig('provider', 'backend')).to eq('kreuzberg-language-pack')
    expect(report.dig('verification', 'base_participated')).to be(true)
  end

  it 'routes TypeScript and TSX paths only through the exact base-aware provider' do
    %w[ts tsx].each do |extension|
      ancestor = write_file(@dir, "ancestor.#{extension}",
                            "export function obsolete() {}\nexport function stable() {}\n")
      current = write_file(
        @dir,
        "current-#{extension}.tmp",
        "export function obsolete() {}\nexport function stable() {}\nexport function ours() {}\n"
      )
      other = write_file(
        @dir,
        "other-#{extension}.tmp",
        "export function stable() {}\nexport function theirs() {}\n"
      )
      report_path = File.join(@dir, "typescript-#{extension}-report.json")
      stderr = StringIO.new

      expect(TypeScript::Merge).not_to receive(:merge_type_script)
      exit_code = described_class.run(
        ['merge-driver', '--report', report_path, '--path-name', "example.#{extension}", ancestor, current, other],
        stdout: StringIO.new,
        stderr: stderr
      )

      expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
      expect(File.read(current)).to eq(
        "export function stable() {}\nexport function ours() {}\nexport function theirs() {}\n"
      )
      report = JSON.parse(File.read(report_path))
      expect(report.dig('provider', 'provider_id')).to eq('ruby.typescript')
      expect(report.dig('provider', 'dialect')).to eq(extension == 'tsx' ? 'tsx' : 'typescript')
      expect(report.dig('verification', 'base_participated')).to be(true)
    end
  end

  it 'routes HTML extensions and identifiers only through the exact base-aware provider' do
    expect(described_class.normalize_language('', 'example.htm')).to eq('html')
    expect(described_class.normalize_language('text/html', 'extensionless')).to eq('html')
    %w[htm html].each do |extension|
      ancestor = write_file(
        @dir,
        "ancestor.#{extension}",
        "<main id=content>base</main>\n<footer id=footer>base</footer>\n"
      )
      current = write_file(
        @dir,
        "current-#{extension}.tmp",
        "<main id=content>ours</main>\n<footer id=footer>base</footer>\n"
      )
      other = write_file(
        @dir,
        "other-#{extension}.tmp",
        "<main id=content>base</main>\n<footer id=footer>theirs</footer>\n"
      )
      report_path = File.join(@dir, "html-#{extension}-report.json")
      stderr = StringIO.new

      exit_code = described_class.run(
        ['merge-driver', '--report', report_path, '--path-name', "example.#{extension}", ancestor, current, other],
        stdout: StringIO.new,
        stderr: stderr
      )

      expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
      expect(File.read(current)).to eq(
        "<main id=content>ours</main>\n<footer id=footer>theirs</footer>\n"
      )
      report = JSON.parse(File.read(report_path))
      expect(report.dig('provider', 'provider_id')).to eq('ruby.html')
      expect(report.dig('verification', 'base_participated')).to be(true)
    end
  end

  it 'routes dotenv paths through the base-aware dotenv provider' do
    ancestor = write_file(@dir, 'ancestor.env', "SHARED=1\n")
    current = write_file(@dir, 'current.env', "SHARED=1\nOURS=left\n")
    other = write_file(@dir, 'other.env', "SHARED=1\nTHEIRS=right\n")
    stdout = StringIO.new
    stderr = StringIO.new
    report_path = File.join(@dir, 'dotenv-report.json')

    exit_code = described_class.run(
      ['merge-driver', '--path-name', '.env', '--report', report_path, ancestor, current, other],
      stdout: stdout,
      stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to eq("SHARED=1\nOURS=left\nTHEIRS=right\n")
    report = JSON.parse(File.read(report_path))
    expect(report.dig('provider', 'provider_id')).to eq('ruby.dotenv')
    expect(report.dig('provider', 'backend')).to eq('dotenv-line')
    expect(report.dig('profile', 'profile_id')).to eq('source_preserving')
    expect(report.dig('render_report', 'strategy')).to eq('exact_assignment_composite')
  end

  it 'routes Ruby paths through the base-aware Prism provider' do
    ancestor = write_file(@dir, 'ancestor.rb', "VALUE = 0\n")
    current = write_file(@dir, 'current.rb', "VALUE = 0\nOURS = 1\n")
    other = write_file(@dir, 'other.rb', "VALUE = 0\nTHEIRS = 2\n")
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(
      ['merge-driver', '--path-name', 'example.rb', ancestor, current, other],
      stdout: stdout,
      stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to eq("VALUE = 0\nOURS = 1\nTHEIRS = 2\n")
  end

  it 'routes RBS paths through the exact base-aware workflow provider' do
    ancestor = write_file(@dir, 'ancestor.rbs', "class Obsolete\nend\nclass Stable\nend\n")
    current = write_file(@dir, 'current.tmp', "class Obsolete\nend\nclass Stable\nend\nclass Ours\nend\n")
    other = write_file(@dir, 'other.tmp', "class Stable\nend\nclass Theirs\nend\n")
    report_path = File.join(@dir, 'rbs-report.json')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(
      ['merge-driver', '--report', report_path, '--path-name', 'example.rbs', ancestor, current, other],
      stdout: stdout,
      stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to eq("class Stable\nend\nclass Ours\nend\nclass Theirs\nend\n")
    report = JSON.parse(File.read(report_path))
    expect(report.fetch('ok')).to be(true)
    expect(report.dig('provider', 'provider_id')).to eq('ruby.rbs')
    expect(report.dig('provider', 'family')).to eq('rbs')
    expect(report.dig('provider', 'backend')).to eq('rbs')
    expect(report.dig('profile', 'profile_id')).to eq('source_preserving')
    expect(report.dig('verification', 'base_participated')).to be(true)
  end

  it 'routes Rust paths only through the exact base-aware workflow provider' do
    ancestor = write_file(@dir, 'ancestor.rs', "fn shared() {}\n")
    current = write_file(@dir, 'current.tmp', "fn shared() {}\nfn ours() {}\n")
    other = write_file(@dir, 'other.tmp', "fn shared() {}\nfn theirs() {}\n")
    report_path = File.join(@dir, 'rust-report.json')
    stderr = StringIO.new

    expect(Rust::Merge).not_to receive(:merge_rust)
    exit_code = described_class.run(
      ['merge-driver', '--report', report_path, '--path-name', 'example.rs', ancestor, current, other],
      stdout: StringIO.new,
      stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to eq("fn shared() {}\nfn ours() {}\nfn theirs() {}\n")
    report = JSON.parse(File.read(report_path))
    expect(report.dig('provider', 'provider_id')).to eq('ruby.rust')
    expect(report.dig('provider', 'family')).to eq('rust')
    expect(report.dig('provider', 'dialect')).to eq('rust')
    expect(report.dig('verification', 'base_participated')).to be(true)
  end

  it 'routes Bash extensions and identifiers only through the exact workflow provider' do
    expect(described_class.normalize_language('', 'example.bash')).to eq('bash')
    expect(described_class.normalize_language('sh', 'extensionless')).to eq('bash')

    ancestor = write_file(@dir, 'ancestor.sh', "shared() { :; }\n")
    current = write_file(@dir, 'current.tmp', "shared() { :; }\nours() { :; }\n")
    other = write_file(@dir, 'other.tmp', "shared() { :; }\ntheirs() { :; }\n")
    report_path = File.join(@dir, 'bash-report.json')
    stderr = StringIO.new

    expect(Bash::Merge::SmartMerger).not_to receive(:new)
    exit_code = described_class.run(
      ['merge-driver', '--report', report_path, '--path-name', 'example.sh', ancestor, current, other],
      stdout: StringIO.new,
      stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to eq("shared() { :; }\nours() { :; }\ntheirs() { :; }\n")
    report = JSON.parse(File.read(report_path))
    expect(report.dig('provider', 'provider_id')).to eq('ruby.bash')
    expect(report.dig('provider', 'family')).to eq('bash')
    expect(report.dig('provider', 'dialect')).to eq('bash')
    expect(report.dig('verification', 'base_participated')).to be(true)
  end

  it 'routes YAML paths through the Psych provider' do
    ancestor = write_file(@dir, 'ancestor.yml', "obsolete: true\nstable: true\n")
    current = write_file(@dir, 'current.yml', "obsolete: true\nstable: true\nours: left\n")
    other = write_file(@dir, 'other.yml', "stable: true\ntheirs: right\n")
    report_path = File.join(@dir, 'merge-report.json')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', '--report', report_path, ancestor, current, other, 'config.yml'],
                                    stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to eq("stable: true\nours: left\ntheirs: right\n")
    report = JSON.parse(File.read(report_path))
    expect(report.fetch('ok')).to be(true)
    expect(report.dig('provider', 'provider_id')).to eq('ruby.yaml.psych')
    expect(report.dig('provider', 'backend')).to eq('psych')
    expect(report.dig('verification', 'base_participated')).to be(true)
  end

  it 'returns conflict exit code for strict merge failures' do
    ancestor = write_file(@dir, 'ancestor.json', '{"name":"structuredmerge"}')
    current = write_file(@dir, 'current.json', '{"name":')
    other = write_file(@dir, 'other.json', '{"other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', '--strict', ancestor, current, other, 'package.json'],
                                    stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    expect(stderr.string).to include('parse_error')
    expect(stderr.string).to include('ours parse error')
  end

  it 'writes full-file conflict markers for non-strict fallback failures' do
    ancestor = write_file(@dir, 'ancestor.json', '{"name":"structuredmerge"}')
    current = write_file(@dir, 'current.json', '{"name":')
    other = write_file(@dir, 'other.json', '{"other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', ancestor, current, other, 'package.json'], stdout: stdout,
                                                                                                stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    current_source = File.read(current)
    expect(current_source).to include('<<<<<<< ours')
    expect(current_source).to include('||||||| base')
    expect(current_source).to include('=======')
    expect(current_source).to include('>>>>>>> theirs')
    expect(stderr.string).to include('parse_error')
  end

  it 'conforms to the git-driver fallback fixture' do
    git_driver_fallback_fixture.fetch('cases').each do |test_case|
      Dir.mktmpdir('smorg-rb-fallback-') do |dir|
        ancestor = write_file(dir, 'ancestor.json', test_case.fetch('base_source'))
        current = write_file(dir, 'current.json', test_case.fetch('ours_source'))
        other = write_file(dir, 'other.json', test_case.fetch('theirs_source'))
        report_path = File.join(dir, 'merge-report.json')
        args = ['merge-driver']
        args << '--strict' if test_case.dig('options', 'strict')
        fallback = test_case.dig('options', 'fallback')
        args.concat(['--fallback', fallback]) if fallback && fallback != 'full-file'
        args.concat(['--report', report_path])
        args.concat([ancestor, current, other, test_case.fetch('path_name')])
        stdout = StringIO.new
        stderr = StringIO.new

        exit_code = described_class.run(args, stdout: stdout, stderr: stderr)
        expected = test_case.fetch('expected')
        current_source = File.read(current)
        expect(exit_code).to eq(expected.fetch('exit_code')), test_case.fetch('case_id')
        expect(current_source).to eq(expected.fetch('merged_source')) if expected['merged_source']
        expected.fetch('source_contains', []).each do |needle|
          expect(current_source).to include(needle), test_case.fetch('case_id')
        end
        expected.fetch('stderr_contains', []).each do |needle|
          expect(stderr.string).to include(needle), test_case.fetch('case_id')
        end
        expected.fetch('stderr_not_contains', []).each do |needle|
          expect(stderr.string).not_to include(needle), test_case.fetch('case_id')
        end
        report = JSON.parse(File.read(report_path))
        expected_report = expected.fetch('machine_report')
        expect(report.fetch('ok')).to eq(expected_report.fetch('ok')), test_case.fetch('case_id')
        expect(report.fetch('exit_code')).to eq(expected_report.fetch('exit_code')), test_case.fetch('case_id')
        expect(report.fetch('fallbacks')).to eq(expected_report.fetch('fallbacks')), test_case.fetch('case_id')
        diagnostics_json = JSON.generate(report.fetch('diagnostics'))
        expected_report.fetch('diagnostics_contain').each do |needle|
          expect(diagnostics_json).to include(needle), test_case.fetch('case_id')
        end
        expected_report.fetch('required_fields', []).each do |field|
          expect(report).to have_key(field), test_case.fetch('case_id')
        end
      end
    end
  end

  it 'uses the ancestor for JSON same-key conflicts' do
    ancestor = write_file(@dir, 'ancestor.json', '{"name":"demo","enabled":true}')
    current = write_file(@dir, 'current.json', '{"name":"demo","enabled":false}')
    other = write_file(@dir, 'other.json', '{"name":"demo","enabled":"yes"}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', '--strict', ancestor, current, other, 'package.json'],
                                    stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    expect(File.read(current)).to include('<<<<<<< ours')
    expect(File.read(current)).to include('||||||| base')
    expect(File.read(current)).to include('=======')
    expect(File.read(current)).to include('>>>>>>> theirs')
    expect(stderr.string).to include('merge_conflict')
  end

  it 'reports an explicit full-file fallback when an owner shares a source line' do
    ancestor = write_file(@dir, 'ancestor.json', '{"name":"demo","enabled":true}')
    current = write_file(@dir, 'current.json', '{"name":"demo","enabled":false}')
    other = write_file(@dir, 'other.json', '{"name":"demo","enabled":"yes"}')
    report_path = File.join(@dir, 'merge-report.json')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(
      ['merge-driver', '--report', report_path, ancestor, current, other,
       'package.json'], stdout: stdout, stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    report = JSON.parse(File.read(report_path))
    expect(report.dig('render_report', 'strategy')).to eq('full_file_conflict')
    expect(report.fetch('change_classifications')).to eq(
      [
        {
          'path' => '/enabled',
          'ours' => 'edited',
          'theirs' => 'edited'
        }
      ]
    )
    expect(report.fetch('owned_regions')).to be_empty
    expect(report.fetch('fallbacks')).to include(
      hash_including(
        'to' => 'full_file_conflict',
        'reason' => 'owner_not_whole_line_addressable'
      )
    )
    expect(report.dig('profile', 'profile_id')).to eq('source_preserving')
    expect(report.dig('verification', 'base_participated')).to be(true)
    expect(report.dig('provider', 'family')).to eq('json')
    expect(report.dig('provider', 'dialect')).to eq('json')
  end

  it 'conforms to the git-driver JSON integration fixture in a repository' do
    git_driver_json_fixture.fetch('cases').each do |test_case|
      Dir.mktmpdir('smorg-rb-git-driver-') do |dir|
        run_git(dir, 'init')
        run_git(dir, 'config', 'user.email', 'smorg-rb@example.invalid')
        run_git(dir, 'config', 'user.name', 'smorg-rb test')
        write_file(dir, '.gitattributes', "*.json merge=smorg-rb smorg.language=json\n")
        write_file(dir, test_case.fetch('path_name'), test_case.fetch('base_source'))
        run_git(dir, 'add', '.')
        run_git(dir, 'commit', '-m', 'base')

        ancestor = write_file(dir, 'ancestor.tmp', test_case.fetch('base_source'))
        current = write_file(dir, test_case.fetch('path_name'), test_case.fetch('ours_source'))
        other = write_file(dir, 'other.tmp', test_case.fetch('theirs_source'))
        stdout = StringIO.new
        stderr = StringIO.new

        exit_code = described_class.run(
          ['merge-driver', '--strict', ancestor, current, other,
           test_case.fetch('path_name')], stdout: stdout, stderr: stderr
        )
        expected = test_case.fetch('expected')
        expect(exit_code).to eq(expected.fetch('exit_code')), "#{test_case.fetch('case_id')} stderr=#{stderr.string}"
        expected.fetch('stderr_contains').each do |needle|
          expect(stderr.string).to include(needle), test_case.fetch('case_id')
        end

        merged_source = File.read(current)
        if expected['merged_json']
          expect(JSON.parse(merged_source)).to eq(expected.fetch('merged_json')), test_case.fetch('case_id')
        elsif expected['merged_source']
          expect(merged_source).to eq(expected.fetch('merged_source')), test_case.fetch('case_id')
        end
        expected.fetch('conflicted_source_contains', []).each do |needle|
          expect(merged_source).to include(needle), test_case.fetch('case_id')
        end
      end
    end
  end

  it 'supports check-only exit-code without writing' do
    ancestor = write_file(@dir, 'ancestor.json', '{"name":"structuredmerge"}')
    current = write_file(@dir, 'current.json', '{"name":"structuredmerge","current":true}')
    other = write_file(@dir, 'other.json', '{"name":"structuredmerge","other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(
      ['merge-driver', '--check-only', '--exit-code', ancestor, current, other,
       'package.json'], stdout: stdout, stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    expect(File.read(current)).not_to include('"other":true')
  end

  it 'prints profile report and blocks unmet required profile status' do
    ancestor = write_file(@dir, 'ancestor.json', '{"name":"structuredmerge"}')
    current = write_file(@dir, 'current.json', '{"name":"structuredmerge","current":true}')
    other = write_file(@dir, 'other.json', '{"name":"structuredmerge","other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(
      ['merge-driver', '--profile', 'json.keyed-object', '--profile-report', '--require-profile-status', 'recommended',
       ancestor, current, other, 'package.json'],
      stdout: stdout,
      stderr: stderr
    )

    expect(exit_code).to eq(described_class::EXIT_USER_ERROR)
    expect(stdout.string).to include('"rejection_code":"profile_status_unmet"')
    expect(stderr.string).to include('profile status available is below required recommended')
  end

  it 'uses smorg profile attributes' do
    File.write('.gitattributes', "*.json smorg.profile=json.keyed-object smorg.requireProfileStatus=recommended\n")
    ancestor = write_file(@dir, 'ancestor.json', '{"name":"structuredmerge"}')
    current = write_file(@dir, 'current.json', '{"name":"structuredmerge","current":true}')
    other = write_file(@dir, 'other.json', '{"name":"structuredmerge","other":true}')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', '--profile-report', ancestor, current, other, 'package.json'],
                                    stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_USER_ERROR)
    expect(stdout.string).to include('"profile_id":"json.keyed-object"')
    expect(stdout.string).to include('"rejection_code":"profile_status_unmet"')
  end

  it 'supports diff-driver git arities' do
    [7, 9].each do |argument_count|
      old_path = write_file(@dir, "old-#{argument_count}.json", '{"old":true}')
      new_path = write_file(@dir, "new-#{argument_count}.json", '{"new":true}')
      args = ['diff-driver', 'package.json', old_path, 'abc123', '100644', new_path, 'def456', '100644']
      args += ['a/', 'b/'] if argument_count == 9
      stdout = StringIO.new
      stderr = StringIO.new

      exit_code = described_class.run(args, stdout: stdout, stderr: stderr)

      expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
      expect(stdout.string).to include('structured-diff package.json')
      expect(stdout.string).to include('review-diff unified')
      expect(stdout.string).to include('@@ -1 +1 @@')
      expect(stdout.string).to include('-{"old":true}')
      expect(stdout.string).to include('+{"new":true}')
    end
  end

  it 'renders compact review hunks instead of whole-file replacements' do
    old_source = (1..12).map { |index| "sentinel_#{index.to_s.rjust(2, '0')}\n" }.join
    new_source = old_source.sub("sentinel_07\n", "changed_07\n")
    old_path = write_file(@dir, 'old-source.rb', old_source)
    new_path = write_file(@dir, 'new-source.rb', new_source)
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['diff-driver', '--path-name', 'lib/example.rb', old_path, new_path],
                                    stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(stdout.string).to include('structured-diff lib/example.rb')
    expect(stdout.string).to include('review-diff unified')
    expect(stdout.string).to include('@@ -4,7 +4,7 @@')
    expect(stdout.string).to include('-sentinel_07')
    expect(stdout.string).to include('+changed_07')
    expect(stdout.string).not_to include('sentinel_01')
    expect(stdout.string).not_to include('sentinel_12')
    expect(stdout.string).not_to include('@@ -1,12 +1,12 @@')
  end

  it 'keeps no-ext-diff source review fragments in structured diff output' do
    source_pair = diff_driver_smoke_fixture.fetch('suite').fetch('real_source_pairs').first
    old_path = write_file(@dir, 'old-source.rb', source_pair.fetch('old_source'))
    new_path = write_file(@dir, 'new-source.rb', source_pair.fetch('new_source'))
    stdout = StringIO.new
    stderr = StringIO.new

    plain_diff = IO.popen([{ 'GIT_CONFIG_NOSYSTEM' => '1' }, 'git', '--no-pager', 'diff', '--no-ext-diff',
                           '--no-index', old_path, new_path], err: %i[child out], &:read)
    expect([0, 1]).to include($CHILD_STATUS.exitstatus)
    exit_code = described_class.run(['diff-driver', '--path-name', source_pair.fetch('path'), old_path,
                                     new_path], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    source_pair.fetch('expected_plain_diff_fragments').each { |fragment| expect(plain_diff).to include(fragment) }
    source_pair.fetch('expected_structured_diff_fragments').each do |fragment|
      expect(stdout.string).to include(fragment)
    end
  end

  it 'reports conflict regions' do
    conflicted = write_file(@dir, 'conflicted.go',
                            "package main\n<<<<<<< ours\nfunc Current() {}\n=======\nfunc Other() {}\n>>>>>>> theirs\n")
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['conflicts', 'diff', '--path-name', 'main.go', '--exit-code', conflicted],
                                    stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_UNRESOLVED_CONFLICT)
    expect(stdout.string).to include('conflicts main.go')
    expect(stdout.string).to include('conflict 1 lines 2-6 separator 4')
  end

  it 'prints gitattributes' do
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['languages', '--gitattributes'], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(stdout.string).to include('*.go merge=smorg-rb diff=smorg-rb smorg.language=go')
    expect(stdout.string).to include('*.toml merge=smorg-rb diff=smorg-rb smorg.language=toml')
  end
end
