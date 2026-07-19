# frozen_string_literal: true

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

  def run_git(dir, *args)
    return skip('git executable is required for repository integration fixture') unless system('git', '--version',
                                                                                               out: File::NULL, err: File::NULL)

    output = IO.popen([{ 'GIT_CONFIG_NOSYSTEM' => '1' }, 'git', *args], chdir: dir, err: %i[child out], &:read)
    return if $?.success?

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
    ancestor = write_file(@dir, 'ancestor.md', "# Project\n\n## Usage\n\nBase usage.\n")
    current = write_file(
      @dir,
      'current.md',
      "# Project\n\n## Usage\n\nBase usage.\n\n## Local\n\nKeep local notes.\n"
    )
    other = write_file(
      @dir,
      'other.md',
      "# Project\n\n## Usage\n\nBase usage.\n\n## Remote\n\nInclude remote notes.\n"
    )
    stdout = StringIO.new
    stderr = StringIO.new

    expect(Plain::Merge).not_to receive(:merge_text)
    exit_code = described_class.run(['merge-driver', ancestor, current, other, 'README.md'], stdout: stdout,
                                                                                             stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    merged = File.read(current)
    expect(merged).to include("## Local\n\nKeep local notes.")
    expect(merged).to include("## Remote\n\nInclude remote notes.")
  end

  it 'keeps current Markdown when theirs is already present in the matching section' do
    ancestor = write_file(
      @dir,
      'ancestor.md',
      "# Project\n\n## Links\n\nRead http://example.com/posts/old-page/ for details.\n"
    )
    current_source = [
      '# Project',
      '',
      '## Links',
      '',
      'Read',
      'https://example.com/docs/new-page/',
      'for details.',
      '',
      '## Local',
      '',
      'Keep local notes.',
      ''
    ].join("\n")
    current = write_file(@dir, 'current.md', current_source)
    other = write_file(
      @dir,
      'other.md',
      "# Project\n\n## Links\n\nRead https://example.com/docs/new-page/ for details.\n"
    )
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', ancestor, current, other, 'README.md'], stdout: stdout,
                                                                                             stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(File.read(current)).to eq(current_source)
  end

  it 'advertises Markdown paths in generated gitattributes' do
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['languages', '--gitattributes'], stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    expect(stdout.string).to include('*.md merge=smorg-rb diff=smorg-rb smorg.language=markdown')
    expect(stdout.string).to include('*.markdown merge=smorg-rb diff=smorg-rb smorg.language=markdown')
  end

  it 'falls back from unsupported structured file types instead of failing closed' do
    ancestor = write_file(@dir, 'ancestor.yml', "name: structuredmerge\ncurrent: false\n\nother: false\n")
    current = write_file(@dir, 'current.yml', "name: structuredmerge\ncurrent: true\n\nother: false\n")
    other = write_file(@dir, 'other.yml', "name: structuredmerge\ncurrent: false\n\nother: true\n")
    report_path = File.join(@dir, 'merge-report.json')
    stdout = StringIO.new
    stderr = StringIO.new

    exit_code = described_class.run(['merge-driver', '--report', report_path, ancestor, current, other, 'config.yml'],
                                    stdout: stdout, stderr: stderr)

    expect(exit_code).to eq(described_class::EXIT_SUCCESS), stderr.string
    merged = File.read(current)
    expect(merged).to include('current: true')
    expect(merged).to include('other: true')
    report = JSON.parse(File.read(report_path))
    expect(report.fetch('ok')).to be(true)
    expect(report.fetch('fallbacks')).to include(
      a_hash_including(
        'mode' => 'git_merge_file',
        'reason' => 'unsupported_language',
        'applied' => true
      )
    )
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

  it 'includes owned-region placement in merge-driver reports' do
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
    expect(report.dig('render_report', 'strategy')).to eq('owned_region_conflict_markers')
    expect(report.fetch('change_classifications')).to eq(
      [
        {
          'path' => '/enabled',
          'ours' => 'edited',
          'theirs' => 'edited'
        }
      ]
    )
    expect(report.dig('owned_regions', 0, 'owner_path')).to eq('/enabled')
    expect(report.dig('owned_regions', 0, 'region_kind')).to eq('node')
    expect(report.dig('profile', 'profile_id')).to eq('json.keyed-object')
    expect(report.dig('profile', 'language')).to eq('json')
    expect(report.dig('formatting_preservation', 'line_diff_score')).not_to be_nil
    expect(report.dig('default_driver_evaluation', 'status')).to be_a(String)
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
  end
end
