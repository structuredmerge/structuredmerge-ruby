# frozen_string_literal: true

# kettle-dev:freeze
# To retain chunks of comments & code during kettle-dev templating:
# Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
# The content between those markers will be preserved across template runs.
# kettle-dev:unfreeze

gem_version =
  if RUBY_VERSION >= '3.1'
    Module.new.tap { |mod| Kernel.load("#{__dir__}/lib/kettle/dev/version.rb", mod) }::Kettle::Dev::Version::VERSION
  else
    lib = File.expand_path('lib', __dir__)
    $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
    require 'kettle/dev/version'
    Kettle::Dev::Version::VERSION
  end

Gem::Specification.new do |spec|
  spec.name = 'kettle-dev'
  spec.version = gem_version
  spec.authors = ['Peter H. Boling']
  spec.email = ['floss@galtzo.com']

  spec.summary = '🍲 A kettle-rb meta tool to streamline development and testing'
  spec.description = '🍲 Kettle::Dev is a meta tool from kettle-rb to streamline development and testing. Acts as a shim dependency, pulling in many other dependencies, to give you OOTB productivity with a RubyGem, or Ruby app project. Configures a complete set of Rake tasks, for all the libraries is brings in, so they arrive ready to go. Fund overlooked open source projects - bottom of stack, dev/test dependencies: floss-funding.dev'
  spec.homepage = 'https://github.com/kettle-dev/kettle-dev'
  spec.licenses = ['MIT']
  spec.required_ruby_version = '>= 2.3.0'

  unless ENV.include?('SKIP_GEM_SIGNING')
    user_cert = "certs/#{ENV.fetch('GEM_CERT_USER', ENV['USER'])}.pem"
    cert_file_path = File.join(__dir__, user_cert)
    cert_chain = cert_file_path.split(',')
    cert_chain.select! { |fp| File.exist?(fp) }
    if cert_file_path && cert_chain.any?
      spec.cert_chain = cert_chain
      if $PROGRAM_NAME.endwith?('gem') && ARGV[0] == 'build'
        spec.signing_key = File.join(Gem.user_home, '.ssh', 'gem-private_key.pem')
      end
    end
  end

  spec.metadata['homepage_uri'] = "https://#{spec.name.tr('_', '-')}.galtzo.com/"
  spec.metadata['source_code_uri'] = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['documentation_uri'] = "https://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  spec.metadata['funding_uri'] = 'https://github.com/sponsors/pboling'
  spec.metadata['wiki_uri'] = "#{spec.homepage}/wiki"
  spec.metadata['news_uri'] = "https://www.railsbling.com/tags/#{spec.name}"
  spec.metadata['discord_uri'] = 'https://discord.gg/3qme4XHNKN'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'lib/**/*.rb',
    'lib/**/*.rake',
    'sig/**/*.rbs'
  ]

  spec.extra_rdoc_files = Dir[
    'CHANGELOG.md',
    'CITATION.cff',
    'CODE_OF_CONDUCT.md',
    'CONTRIBUTING.md',
    'FUNDING.md',
    'LICENSE.txt',
    'README.md',
    'REEK',
    'RUBOCOP.md',
    'SECURITY.md'
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
  spec.require_paths = ['lib']
  spec.bindir = 'exe'
  spec.executables = %w[kettle-changelog kettle-commit-msg kettle-dev-setup kettle-pre-release
                        kettle-readme-backers kettle-release kettle-dvcs]

  # NOTE: It is preferable to list development dependencies in the gemspec due to increased
  #       visibility and discoverability.
  #       However, development dependencies in gemspec will install on
  #       all versions of Ruby that will run in CI.
  #       This gem, and its gemspec runtime dependencies, will install on Ruby down to 2.3.0.
  #       This gem, and its gemspec development dependencies, will install on Ruby down to 2.3.0.
  #       Thus, dev dependencies in gemspec must have
  #
  #       required_ruby_version ">= 2.3.0" (or lower)
  #
  #       Development dependencies that require strictly newer Ruby versions should be in a "gemfile",
  #       and preferably a modular one (see gemfiles/modular/*.gemfile).

  # Security
  spec.add_development_dependency('bundler-audit', '~> 0.9.3')

  # Tasks
  spec.add_development_dependency('rake', '~> 13.0')

  # Debugging
  spec.add_development_dependency('require_bench', '~> 1.0', '>= 1.0.4')

  # Testing
  spec.add_development_dependency('appraisal2', '~> 3.0')
  spec.add_development_dependency('kettle-test', '~> 1.0', '>= 1.0.6')

  # Releasing
  spec.add_development_dependency('ruby-progressbar', '~> 1.13')
  spec.add_development_dependency('stone_checksums', '~> 1.0', '>= 1.0.3')

  spec.add_development_dependency('gitmoji-regex', '~> 1.0', '>= 1.0.3')
end
