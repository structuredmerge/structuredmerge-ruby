# frozen_string_literal: true

# kettle-jem:freeze
# To retain chunks of comments & code during kettle-jem templating:
# Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
# kettle-jem will then preserve content between those markers across template runs.
# kettle-jem:unfreeze

Gem::Specification.new do |spec|
  spec.name = 'markly-merge'
  spec.version = Module.new.tap { |mod| Kernel.load("#{__dir__}/lib/markly/merge/version.rb", mod) }::Markly::Merge::Version::VERSION
  spec.authors = ['Peter H. Boling']
  spec.email = ['floss@galtzo.com']

  spec.summary = '☯️ Structured Merge Markly-backed Markdown analysis for Ruby'
  spec.description = '☯️ Markly-backed Markdown provider gem for the Structured Merge Markdown family.'
  spec.homepage = 'https://github.com/structuredmerge/structuredmerge-ruby'
  spec.licenses = ['AGPL-3.0-only', 'PolyForm-Small-Business-1.0.0']
  spec.required_ruby_version = '>= 4.0.0'

  # Linux distros often package gems and securely certify them independent
  #   of the official RubyGem certification process. Allowed via ENV["SKIP_GEM_SIGNING"]
  # Ref: https://gitlab.com/ruby-oauth/version_gem/-/issues/3
  # Hence, only enable signing if `SKIP_GEM_SIGNING` is not set in ENV.
  # See CONTRIBUTING.md
  unless ENV.include?('SKIP_GEM_SIGNING')
    user_cert = "certs/#{ENV.fetch('GEM_CERT_USER', ENV['USER'])}.pem"
    cert_file_path = File.join(__dir__, user_cert)
    cert_chain = cert_file_path.split(',')
    cert_chain.select! { |fp| File.exist?(fp) }
    if cert_file_path && cert_chain.any?
      spec.cert_chain = cert_chain
      if $PROGRAM_NAME.end_with?('gem') && ARGV[0] == 'build'
        spec.signing_key = File.join(Gem.user_home, '.ssh', 'gem-private_key.pem')
      end
    end
  end

  spec.metadata['homepage_uri'] = 'https://structuredmerge.org'
  spec.metadata['source_code_uri'] = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['documentation_uri'] = "https://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  spec.metadata['funding_uri'] = 'https://github.com/sponsors/pboling'
  spec.metadata['wiki_uri'] = "#{spec.homepage}/wiki"
  spec.metadata['news_uri'] = "https://www.railsbling.com/tags/#{spec.name}"
  spec.metadata['discord_uri'] = 'https://discord.gg/3qme4XHNKN'
  spec.metadata['mailing_list_uri'] = 'https://www.rubyforum.org/tag/structuredmerge'
  spec.metadata['rubygems_mfa_required'] = 'true'

  gemspec_root = __dir__
  relative_package_path = lambda do |path|
    path.delete_prefix("#{gemspec_root}/")
  end
  enumerate_package_glob = lambda do |glob|
    Dir.glob(glob, File::FNM_DOTMATCH).filter_map do |path|
      next unless File.file?(path) && !['.', '..'].include?(File.basename(path))

      relative_package_path.call(path)
    end
  end
  enumerate_package_files = lambda do |root|
    enumerate_package_glob.call(File.join(gemspec_root, root, '**', '*'))
  end
  package_metadata_files = %w[
    CHANGELOG.md
    LICENSE.md
    README.md
    sig/markly/merge.rbs
  ].select { |path| File.exist?(File.join(gemspec_root, path)) }

  # Specify which files are part of the released package.
  spec.files = [
    # Root package metadata
    *package_metadata_files,
    # Code / tasks / data (NOTE: exe/ is specified via spec.bindir and spec.executables below)
    *enumerate_package_files.call('lib'),
    # Executables and executable support scripts
    *enumerate_package_files.call('exe')
  ]
  spec.rdoc_options += [
    '--title',
    "#{spec.name} - #{spec.summary}",
    '--main',
    'README.md',
    '--exclude',
    '^sig/',
    '--line-numbers',
    '--inline-source',
    '--quiet'
  ]
  spec.bindir = 'exe'
  # Listed files are the relative paths from bindir above.
  spec.executables = []

  # kettle-jem:freeze
  # To retain chunks of comments & code during markly-merge templating:
  # Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
  # markly-merge will then preserve content between those markers across template runs.
  # kettle-jem:unfreeze

  spec.require_paths = ['lib']

  # Utilities
  spec.add_dependency 'markdown-merge', "= #{spec.version}"
  spec.add_dependency 'markly', '~> 0.9'
  spec.add_dependency('version_gem', '~> 1.1', '>= 1.1.15') # ruby >= 2.2.0

  # NOTE: It is preferable to list development dependencies in the gemspec due to increased
  #       visibility and discoverability.
  #       However, development dependencies in gemspec will install on
  #       all versions of Ruby that will run in CI.
  #       This gem, and its gemspec runtime dependencies, will install on Ruby down to 4.0.0.
  #       This gem, and its gemspec development dependencies, will install on Ruby down to 4.0.0.
  #       Thus, dev dependencies in gemspec must have
  #
  #       required_ruby_version ">= 4.0.0" (or lower)
  #
  #       Development dependencies that require strictly newer Ruby versions should be in a "gemfile",
  #       and preferably a modular one (see gemfiles/modular/*.gemfile).

  # Dev, Test, & Release Tasks
  spec.add_development_dependency('kettle-dev', '~> 3.0', '>= 3.0.7') # ruby >= 4.0.0

  # Security
  spec.add_development_dependency('bundler-audit', '~> 0.9.3') # ruby >= 2.0.0

  # Tasks
  spec.add_development_dependency('rake', '~> 13.0') # ruby >= 2.2.0

  # Debugging
  spec.add_development_dependency('require_bench', '~> 1.0', '>= 1.0.4') # ruby >= 2.2.0

  # Testing
  # Loads version files in anonymous namespaces for coverage without constant redefinition warnings.
  spec.add_development_dependency('anonymous_loader', '~> 0.1', '>= 0.1.3')         # ruby >= 2.2.0
  spec.add_development_dependency('appraisal2', '~> 3.2', '>= 3.2.2')               # ruby >= 1.8.7, for testing against multiple versions of dependencies
  spec.add_development_dependency('kettle-test', '~> 2.0', '>= 2.0.20') # ruby >= 4.0.0
  spec.add_development_dependency('turbo_tests2', '~> 3.2', '>= 3.2.6') # ruby >= 2.4.0, default kettle-test runner

  # Releasing
  spec.add_development_dependency('ruby-progressbar', '~> 1.13')                    # ruby >= 0
  spec.add_development_dependency('stone_checksums', '~> 1.0', '>= 1.0.8')          # ruby >= 2.2.0

  # Development tasks
  # The cake is a lie. erb v2.2, the oldest release, was never compatible with Ruby 2.3.
  # This means we have no choice but to use the erb that shipped with Ruby 2.3
  # /opt/hostedtoolcache/Ruby/2.3.8/x64/lib/ruby/gems/2.3.0/gems/erb-2.2.2/lib/erb.rb:670:in `prepare_trim_mode': undefined method `match?' for "-":String (NoMethodError)
  # spec.add_development_dependency("erb", ">= 2.2")                                  # ruby >= 2.3.0, not SemVer, old rubies get dropped in a patch.
  spec.add_development_dependency('gitmoji-regex', '~> 2.0', '>= 2.0.12') # ruby >= 2.4
end
