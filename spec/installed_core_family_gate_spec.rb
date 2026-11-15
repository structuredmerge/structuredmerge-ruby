# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../bin/core_family_checkpoint'

RSpec.describe 'installed core family gate' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:clean_env) { {'RUBYOPT' => nil, 'BUNDLE_GEMFILE' => nil, 'BUNDLE_PATH' => nil} }

  it 'refuses to run family suites in the original checkout even with a forged marker' do
    config_path = File.join(root, '.kettle-family.yml')
    original = File.binread(config_path)
    _out, err, status = Open3.capture3(clean_env.merge('STRUCTUREDMERGE_GATE_WORKTREE' => root),
      RbConfig.ruby, File.join(root, 'bin/check_installed_core_family.rb'),
      '--core-gem', '/missing.gem', '--run-family-tests', chdir: root)

    expect(status).not_to be_success
    expect(err).to include('family suites require the disposable worktree')
    expect(File.binread(config_path)).to eq(original)
  end

  it 'rejects a dirty checkout before creating a test worktree' do
    Dir.mktmpdir('core-gate-spec') do |tmp|
      project = File.join(tmp, 'ruby')
      core = File.join(tmp, 'core')
      FileUtils.mkdir_p([File.join(project, 'bin'), File.join(core, 'packages/ruby')])
      FileUtils.cp(File.join(root, 'bin/test_installed_core_family.rb'), File.join(project, 'bin'))
      File.write(File.join(core, 'packages/ruby/Gemfile'), "source 'https://rubygems.org'\n")
      system('git', 'init', '--quiet', project, exception: true)
      File.write(File.join(project, 'uncommitted'), 'keep me')
      _out, err, status = Open3.capture3(clean_env.merge('STRUCTUREDMERGE_CORE_DEV' => core),
        RbConfig.ruby, File.join(project, 'bin/test_installed_core_family.rb'), chdir: project)

      expect(status).not_to be_success
      expect(err).to include('commit or stash Ruby family changes')
      expect(File.read(File.join(project, 'uncommitted'))).to eq('keep me')
      expect(Dir.children(tmp)).to contain_exactly('core', 'ruby')
    end
  end

  it 'refuses to build from a dirty core checkout without changing either checkout' do
    Dir.mktmpdir('core-gate-dirty-core') do |tmp|
      project = File.join(tmp, 'ruby')
      core = File.join(tmp, 'core')
      FileUtils.mkdir_p([File.join(project, 'bin'), File.join(core, 'packages/ruby')])
      FileUtils.cp(File.join(root, 'bin/test_installed_core_family.rb'), File.join(project, 'bin'))
      File.write(File.join(core, 'packages/ruby/Gemfile'), "source 'https://rubygems.org'\n")
      system('git', 'init', '--quiet', project, exception: true)
      system('git', '-C', project, 'add', 'bin', exception: true)
      system('git', '-C', project, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
        'commit', '--quiet', '-m', 'initial', exception: true)
      system('git', 'init', '--quiet', core, exception: true)
      _out, err, status = Open3.capture3(clean_env.merge('STRUCTUREDMERGE_CORE_DEV' => core),
        RbConfig.ruby, File.join(project, 'bin/test_installed_core_family.rb'), chdir: project)

      expect(status).not_to be_success
      expect(err).to include('commit or stash core checkout changes')
      expect(File.read(File.join(core, 'packages/ruby/Gemfile'))).to eq("source 'https://rubygems.org'\n")
      expect(Dir.children(tmp)).to contain_exactly('core', 'ruby')
    end
  end

end

RSpec.describe CoreFamilyCheckpoint do
  it 'resumes only verified members for the same family and core package' do
    Dir.mktmpdir('core-gate-checkpoint') do |dir|
      identity = {'family_revision' => 'abc', 'core_sha256' => '123', 'ruby_version' => RUBY_VERSION}
      checkpoint = described_class.new(directory: dir, identity: identity, members: %w[one two])
      checkpoint.record('one')

      resumed = described_class.new(directory: dir, identity: identity, members: %w[one two])
      expect(resumed.completed).to eq(['one'])
      expect(described_class.new(directory: dir, identity: identity.merge('core_sha256' => '456'), members: %w[one two]).completed).to be_empty
      expect { resumed.record('other') }.to raise_error(/unknown family member/)
      File.write(checkpoint.path, '{invalid')
      expect { described_class.new(directory: dir, identity: identity, members: %w[one two]) }.to raise_error(JSON::ParserError)
    end
  end
end
