# frozen_string_literal: true

require_relative 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'psych'
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
    command = [
      'env',
      "BUNDLE_GEMFILE=#{Shellwords.escape(ruby_root.join('Gemfile').to_s)}",
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
    ].join(' ')
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
    command = [
      'env',
      "BUNDLE_GEMFILE=#{Shellwords.escape(ruby_root.join('Gemfile').to_s)}",
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
    ].join(' ')
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
    command = [
      'env',
      "BUNDLE_GEMFILE=#{Shellwords.escape(ruby_root.join('Gemfile').to_s)}",
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
    ].compact.join(' ')
    git('config', 'merge.structuredmerge.name', "StructuredMerge #{driver.fetch(:family)} provider")
    git('config', 'merge.structuredmerge.driver', command)
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

  it 'runs the Ruby workflow provider through the installed Git-driver path' do
    base = "VALUE = 0\n"
    ours = "VALUE = 0\nOURS = 1\n"
    theirs = "VALUE = 0\nTHEIRS = 2\n"
    path = configure_opaque_repository(
      extension: 'rb',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'ruby/merge',
      provider_id: 'ruby.ruby',
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

  it 'runs the YAML workflow provider through the installed Git-driver path' do
    base = "shared: true\n"
    ours = "shared: true\nours: left\n"
    theirs = "shared: true\ntheirs: right\n"
    path = configure_opaque_repository(
      extension: 'yaml',
      base: base,
      ours: ours,
      theirs: theirs,
      require_path: 'yaml/merge',
      family: 'yaml',
      dialect: 'yaml',
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
    expect(repository.join(path).binread).to eq("shared: true\nours: left\ntheirs: right\n")
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
