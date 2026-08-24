# frozen_string_literal: true

require_relative 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'psych'
require 'bash/merge'
require 'rbs/merge'
require 'rust/merge'
require 'go/merge'
require 'html/merge'
require 'commonmarker/merge'
require 'kramdown/merge'
require 'markdown/merge'
require 'markly/merge'
require 'typescript/merge'
require 'shellwords'
require 'zip/merge'

# rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength -- real Git setup and assertions form one integration boundary
RSpec.describe 'ast-merge-git executable' do
  def ruby_root
    Pathname(__dir__).join('..', '..', '..').expand_path
  end

  def executable
    ruby_root.join('gems', 'ast-merge-git', 'exe', 'ast-merge-git')
  end

  def driver_gemfile
    ruby_root.join('gems', 'ast-merge-git', 'Gemfile')
  end

  def repository
    ruby_root.join('tmp', "real-git-driver-#{Process.pid}")
  end

  def git(*arguments, allow_failure: false)
    stdout, stderr, status = Open3.capture3('git', *arguments, chdir: repository.to_s)
    unless status.success? || allow_failure
      raise "git #{arguments.join(' ')} failed (#{status.exitstatus}): #{stderr}\n#{stdout}"
    end

    [stdout, stderr, status]
  end

  def write(path, content)
    repository.join(path).binwrite(content)
  end

  def configure_repository(base:, ours:, theirs:)
    FileUtils.rm_rf(repository)
    FileUtils.mkdir_p(repository)
    git('init', '--quiet', '--initial-branch=main')
    git('config', 'user.name', 'StructuredMerge Test')
    git('config', 'user.email', 'structuredmerge@example.invalid')
    write('.gitattributes', "*.json merge=structuredmerge\n")
    write('package.json', base)
    git('add', '.gitattributes', 'package.json')
    git('commit', '--quiet', '-m', 'base')

    git('checkout', '--quiet', '-b', 'ours')
    write('package.json', ours)
    git('commit', '--quiet', '-am', 'ours')

    git('checkout', '--quiet', '-b', 'theirs', 'main')
    write('package.json', theirs)
    git('commit', '--quiet', '-am', 'theirs')
    git('checkout', '--quiet', 'ours')
    configure_driver
  end

  def configure_driver
    command = (bundle_driver_prefix + [
      'AST_MERGE_REQUIRE=json/merge',
      'AST_MERGE_FAMILY=json',
      'AST_MERGE_DIALECT=json',
      'bundle',
      'exec',
      Shellwords.escape(executable.to_s),
      '%O',
      '%A',
      '%B',
      '%P',
      '%L'
    ]).join(' ')
    git('config', 'merge.structuredmerge.name', 'StructuredMerge JSON provider')
    git('config', 'merge.structuredmerge.driver', command)
  end

  def configure_text_repository
    FileUtils.rm_rf(repository)
    FileUtils.mkdir_p(repository)
    git('init', '--quiet', '--initial-branch=main')
    git('config', 'user.name', 'StructuredMerge Test')
    git('config', 'user.email', 'structuredmerge@example.invalid')
    write('.gitattributes', "*.txt merge=structuredmerge\n")
    write('notes.txt', "base\n")
    git('add', '.gitattributes', 'notes.txt')
    git('commit', '--quiet', '-m', 'base')

    git('checkout', '--quiet', '-b', 'ours')
    git('commit', '--quiet', '--allow-empty', '-m', 'ours')

    git('checkout', '--quiet', '-b', 'theirs', 'main')
    write('notes.txt', "theirs\n")
    git('commit', '--quiet', '-am', 'theirs')
    git('checkout', '--quiet', 'ours')
    configure_text_driver
  end

  def configure_text_driver
    command = (bundle_driver_prefix + [
      'AST_MERGE_REQUIRE=plain/merge',
      'AST_MERGE_FAMILY=text',
      'AST_MERGE_DIALECT=text',
      'AST_MERGE_PROFILE=coarse_document',
      'bundle',
      'exec',
      Shellwords.escape(executable.to_s),
      '%O',
      '%A',
      '%B',
      '%P',
      '%L'
    ]).join(' ')
    git('config', 'merge.structuredmerge.name', 'StructuredMerge text provider')
    git('config', 'merge.structuredmerge.driver', command)
  end

  def configure_opaque_repository(extension:, base:, ours:, theirs:, **driver)
    path = "document.#{extension}"
    FileUtils.rm_rf(repository)
    FileUtils.mkdir_p(repository)
    git('init', '--quiet', '--initial-branch=main')
    git('config', 'user.name', 'StructuredMerge Test')
    git('config', 'user.email', 'structuredmerge@example.invalid')
    write('.gitattributes', "*.#{extension} merge=structuredmerge\n")
    write(path, base)
    git('add', '.gitattributes', path)
    git('commit', '--quiet', '-m', 'base')

    git('checkout', '--quiet', '-b', 'ours')
    write(path, ours)
    ours == base ? git('commit', '--quiet', '--allow-empty', '-m', 'ours') : git('commit', '--quiet', '-am', 'ours')

    git('checkout', '--quiet', '-b', 'theirs', 'main')
    write(path, theirs)
    git('commit', '--quiet', '-am', 'theirs')
    git('checkout', '--quiet', 'ours')
    configure_opaque_driver(**driver)
    path
  end

  def configure_opaque_driver(provider_id: nil, **driver)
    command = (bundle_driver_prefix + [
      "AST_MERGE_REQUIRE=#{driver.fetch(:require_path)}",
      ("AST_MERGE_PROVIDER=#{provider_id}" if provider_id),
      "AST_MERGE_FAMILY=#{driver.fetch(:family)}",
      "AST_MERGE_DIALECT=#{driver.fetch(:dialect)}",
      "AST_MERGE_BACKEND=#{driver.fetch(:backend)}",
      "AST_MERGE_PROFILE=#{driver.fetch(:profile)}",
      'bundle',
      'exec',
      Shellwords.escape(executable.to_s),
      '%O',
      '%A',
      '%B',
      '%P',
      '%L'
    ].compact).join(' ')
    git('config', 'merge.structuredmerge.name', "StructuredMerge #{driver.fetch(:family)} provider")
    git('config', 'merge.structuredmerge.driver', command)
  end

  # The driver runs from Git's temporary checkout while the specs already run
  # under the family bundle. Remove that parent Bundler bootstrap before
  # selecting the driver's own Gemfile.
  def bundle_driver_prefix
    [
      'env',
      '-u', 'BUNDLE_BIN_PATH',
      '-u', 'BUNDLE_FROZEN',
      '-u', 'BUNDLE_GEMFILE',
      '-u', 'BUNDLE_LOCKFILE',
      '-u', 'BUNDLER_SETUP',
      '-u', 'BUNDLER_VERSION',
      '-u', 'RUBYLIB',
      '-u', 'RUBYOPT',
      "BUNDLE_GEMFILE=#{Shellwords.escape(driver_gemfile.to_s)}"
    ]
  end

  def text_git_baseline(base:, ours:, theirs:)
    write('baseline-base.json', base)
    write('baseline-ours.json', ours)
    write('baseline-theirs.json', theirs)
    git(
      'merge-file',
      '-p',
      'baseline-ours.json',
      'baseline-base.json',
      'baseline-theirs.json',
      allow_failure: true
    )
  end

  after do
    FileUtils.rm_rf(repository)
  end

  it 'cleanly merges independent JSON additions that text Git conflicts on' do
    base = "{\n  \"shared\": true\n}\n"
    ours = "{\n  \"shared\": true,\n  \"ours\": 1\n}\n"
    theirs = "{\n  \"shared\": true,\n  \"theirs\": 2\n}\n"
    configure_repository(base: base, ours: ours, theirs: theirs)

    baseline_output, _baseline_error, baseline_status = text_git_baseline(base: base, ours: ours, theirs: theirs)
    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(JSON.parse(repository.join('package.json').binread)).to eq(
      'shared' => true,
      'ours' => 1,
      'theirs' => 2
    )
  end

  it 'returns a real Git conflict with provider-localized owner markers' do
    base = "{\n  \"stable\": true,\n  \"value\": 0\n}\n"
    ours = "{\n  \"stable\": true,\n  \"value\": 1\n}\n"
    theirs = "{\n  \"stable\": true,\n  \"value\": 2\n}\n"
    configure_repository(base: base, ours: ours, theirs: theirs)

    _stdout, _stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)
    conflicted = repository.join('package.json').binread

    expect(status.exitstatus).to eq(1)
    expect(conflicted).to start_with("{\n  \"stable\": true,\n<<<<<<< ours\n")
    expect(conflicted).to end_with(">>>>>>> theirs\n}\n")
    expect(git('status', '--short').first).to include('UU package.json')
  end

  it 'runs the coarse text provider through the installed Git-driver path' do
    configure_text_repository

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join('notes.txt').binread).to eq("theirs\n")
  end

  it 'runs the Prism Ruby provider through the installed Git-driver path' do
    base = "VALUE = 0\n"
    ours = "VALUE = 0\nOURS = 1\n"
    theirs = "VALUE = 0\nTHEIRS = 2\n"
    path = configure_opaque_repository(
      extension: 'rb',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'prism/merge',
      family: 'ruby',
      dialect: 'ruby',
      backend: 'prism',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq("VALUE = 0\nOURS = 1\nTHEIRS = 2\n")
  end

  it 'runs the exact RBS selector where baseline text merge conflicts' do
    base = "class Shared\nend\n"
    ours = "class Shared\nend\nclass Ours\nend\n"
    theirs = "class Shared\nend\nclass Theirs\nend\n"
    path = configure_opaque_repository(
      extension: 'rbs',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'rbs/merge',
      provider_id: 'ruby.rbs',
      family: 'rbs',
      dialect: 'rbs',
      backend: 'rbs',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq(
      "class Shared\nend\nclass Ours\nend\nclass Theirs\nend\n"
    )
  end

  [
    {
      label: 'Markdown workflow',
      require_path: 'markdown/merge',
      provider_id: 'ruby.markdown',
      backend: 'kreuzberg-language-pack'
    },
    {
      label: 'Commonmarker Markdown backend',
      require_path: 'commonmarker/merge',
      provider_id: 'ruby.markdown.commonmarker',
      backend: 'commonmarker'
    },
    {
      label: 'Kramdown Markdown backend',
      require_path: 'kramdown/merge',
      provider_id: 'ruby.markdown.kramdown',
      backend: 'kramdown'
    },
    {
      label: 'Markly Markdown backend',
      require_path: 'markly/merge',
      provider_id: 'ruby.markdown.markly',
      backend: 'markly'
    }
  ].each do |provider|
    it "runs the exact #{provider.fetch(:label)} selector through the installed Git-driver path" do
      base = "# Alpha\n\nalpha\n\n# Beta\n\nbeta\n"
      ours = base.sub('alpha', 'ours')
      theirs = base.sub('beta', 'theirs')
      path = configure_opaque_repository(
        extension: 'md',
        base: base,
        ours: ours,
        theirs: theirs,
        require_path: provider.fetch(:require_path),
        provider_id: provider.fetch(:provider_id),
        family: 'markdown',
        dialect: 'markdown',
        backend: provider.fetch(:backend),
        profile: 'source_preserving'
      )

      _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

      expect(status.exitstatus).to eq(0), stderr
      expect(repository.join(path).binread).to eq("# Alpha\n\nours\n\n# Beta\n\ntheirs\n")
    end
  end

  it 'runs the exact Go selector where baseline text merge conflicts' do
    base = "package demo\n\nfunc Shared() {}\n"
    ours = "#{base}func Ours() {}\n"
    theirs = "#{base}func Theirs() {}\n"
    path = configure_opaque_repository(
      extension: 'go',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'go/merge',
      provider_id: 'ruby.go',
      family: 'go',
      dialect: 'go',
      backend: 'kreuzberg-language-pack',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq("#{base}func Ours() {}\nfunc Theirs() {}\n")
  end

  it 'runs the exact Rust selector where baseline text merge conflicts' do
    base = "fn shared() {}\n"
    ours = "#{base}fn ours() {}\n"
    theirs = "#{base}fn theirs() {}\n"
    path = configure_opaque_repository(
      extension: 'rs',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'rust/merge',
      provider_id: 'ruby.rust',
      family: 'rust',
      dialect: 'rust',
      backend: 'kreuzberg-language-pack',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq("#{base}fn ours() {}\nfn theirs() {}\n")
  end

  it 'runs the exact Bash selector where baseline text merge conflicts' do
    base = "shared() { :; }\n"
    ours = "#{base}ours() { :; }\n"
    theirs = "#{base}theirs() { :; }\n"
    path = configure_opaque_repository(
      extension: 'sh',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'bash/merge',
      provider_id: 'ruby.bash',
      family: 'bash',
      dialect: 'bash',
      backend: 'kreuzberg-language-pack',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq("#{base}ours() { :; }\ntheirs() { :; }\n")
  end

  it 'runs the exact TypeScript selector where baseline text merge conflicts' do
    base = "export function shared() {}\n"
    ours = "#{base}export function ours() {}\n"
    theirs = "#{base}export function theirs() {}\n"
    path = configure_opaque_repository(
      extension: 'ts',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'typescript/merge',
      provider_id: 'ruby.typescript',
      family: 'typescript',
      dialect: 'typescript',
      backend: 'kreuzberg-language-pack',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq("#{base}export function ours() {}\nexport function theirs() {}\n")
  end

  it 'runs the exact HTML selector where baseline text merge conflicts' do
    base = "<main id=content>base</main>\n<footer id=footer>base</footer>\n"
    ours = "<main id=content>ours</main>\n<footer id=footer>base</footer>\n"
    theirs = "<main id=content>base</main>\n<footer id=footer>theirs</footer>\n"
    path = configure_opaque_repository(
      extension: 'html',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'html/merge',
      provider_id: 'ruby.html',
      family: 'html',
      dialect: 'html',
      backend: 'kreuzberg-language-pack',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq(
      "<main id=content>ours</main>\n<footer id=footer>theirs</footer>\n"
    )
  end

  it 'runs the dotenv provider through the installed Git-driver path' do
    base = "SHARED=1\n"
    ours = "SHARED=1\nOURS=left\n"
    theirs = "SHARED=1\nTHEIRS=right\n"
    path = configure_opaque_repository(
      extension: 'env',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'dotenv/merge',
      family: 'dotenv',
      dialect: 'dotenv',
      backend: 'dotenv-line',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq("SHARED=1\nOURS=left\nTHEIRS=right\n")
  end

  it 'runs the Psych YAML provider through the installed Git-driver path' do
    base = "shared: true\n"
    ours = "shared: true\nours: left\n"
    theirs = "shared: true\ntheirs: right\n"
    path = configure_opaque_repository(
      extension: 'yml',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'psych/merge',
      family: 'yaml',
      dialect: 'yaml',
      backend: 'psych',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(Psych.safe_load(repository.join(path).binread)).to eq(
      'shared' => true,
      'ours' => 'left',
      'theirs' => 'right'
    )
  end

  it 'runs the exact Citrus TOML provider where baseline text merge conflicts' do
    base = "shared = true\n"
    ours = "shared = true\nours = 'left'\n"
    theirs = "shared = true\ntheirs = \"right\"\n"
    path = configure_opaque_repository(
      extension: 'toml',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'citrus/toml/merge',
      provider_id: 'ruby.toml.citrus',
      family: 'toml',
      dialect: 'toml',
      backend: 'citrus',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq(
      "shared = true\nours = 'left'\ntheirs = \"right\"\n"
    )
  end

  it 'runs the exact Parslet TOML selector where baseline text merge conflicts' do
    base = "shared = true\n"
    ours = "shared = true\nours = \"left\"\n"
    theirs = "shared = true\ntheirs = [1, 2]\n"
    path = configure_opaque_repository(
      extension: 'toml',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'parslet/toml/merge',
      provider_id: 'ruby.toml.parslet',
      family: 'toml',
      dialect: 'toml',
      backend: 'parslet',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq(
      "shared = true\nours = \"left\"\ntheirs = [1, 2]\n"
    )
  end

  it 'runs the exact TOML workflow selector where baseline text merge conflicts' do
    base = "shared = true\n"
    ours = "shared = true\nours = 'left'\n"
    theirs = "shared = true\ntheirs = { enabled = true }\n"
    path = configure_opaque_repository(
      extension: 'toml',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'toml/merge',
      provider_id: 'ruby.toml',
      family: 'toml',
      dialect: 'toml',
      backend: 'kreuzberg-language-pack',
      profile: 'source_preserving'
    )
    baseline_output, _baseline_error, baseline_status = text_git_baseline(
      base: base,
      ours: ours,
      theirs: theirs
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(baseline_status.exitstatus).to eq(1)
    expect(baseline_output).to include('<<<<<<< baseline-ours.json')
    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq(
      "shared = true\nours = 'left'\ntheirs = { enabled = true }\n"
    )
  end

  it 'reports an opaque binary conflict without changing ours bytes' do
    ours = "\x00ours\xFF".b
    path = configure_opaque_repository(
      extension: 'bin',
      base: "\x00base".b,
      ours: ours,
      theirs: "\x00theirs".b,
      require_path: 'binary/merge',
      family: 'binary',
      dialect: 'binary',
      backend: 'raw_bytes',
      profile: 'opaque_document'
    )

    _stdout, _stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(status.exitstatus).to eq(1)
    expect(repository.join(path).binread).to eq(ours)
    expect(git('status', '--short').first).to include("UU #{path}")
  end

  it 'runs a valid ZIP archive through the installed Git-driver path' do
    base = Zip::Merge.new_stored_zip('docs/readme.md' => "# Base\n")
    theirs = Zip::Merge.new_stored_zip('docs/readme.md' => "# Theirs\n")
    path = configure_opaque_repository(
      extension: 'zip',
      base: base,
      ours: base,
      theirs: theirs,
      require_path: 'zip/merge',
      family: 'zip',
      dialect: 'zip',
      backend: Zip::Merge::BACKEND_REFERENCE.id,
      profile: 'opaque_archive'
    )

    _stdout, stderr, status = git('merge', '--no-edit', 'theirs', allow_failure: true)

    expect(status.exitstatus).to eq(0), stderr
    expect(repository.join(path).binread).to eq(theirs)
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength
