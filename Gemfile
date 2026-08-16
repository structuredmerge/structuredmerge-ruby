kettle_dev_dev = ENV.fetch("KETTLE_DEV_DEV", "false")

source "https://rubygems.org"

# Use released TSLP with the Ruby ABI platform-gem fix.
gem "tree_sitter_language_pack", "~> 1.13", ">= 1.13.7"

unless kettle_dev_dev.casecmp("false").zero?
  require "nomono/bundler"

  eval_nomono_gems(
    gems: %w[kettle-dev kettle-drift kettle-family kettle-test kettle-soup-cover],
    prefix: "KETTLE_DEV",
    path_env: "KETTLE_DEV_DEV",
    vendored_gems_env: "VENDORED_GEMS",
    vendor_gem_dir_env: "VENDOR_GEM_DIR",
    debug_env: "KETTLE_DEV_DEBUG",
  )
end

unless ENV.fetch("GALTZO_FLOSS_DEV", "false").casecmp("false").zero?
  require "nomono/bundler"

  eval_nomono_gems(
    gems: %w[turbo_tests2 yard-fence yard-timekeeper yard-yaml],
    prefix: "GALTZO_FLOSS",
    path_env: "GALTZO_FLOSS_DEV",
    vendored_gems_env: "GALTZO_FLOSS_VENDORED_GEMS",
    vendor_gem_dir_env: "GALTZO_FLOSS_VENDOR_GEM_DIR",
    debug_env: "GALTZO_FLOSS_DEBUG",
  )
end

gemspec path: "gems/tree_haver"
gemspec path: "gems/ast-merge"
gemspec path: "gems/ast-merge-git"
gemspec path: "gems/ast-crispr"
gemspec path: "gems/ast-crispr-ruby-prism"
gemspec path: "gems/ast-crispr-markdown-markly"
gemspec path: "gems/ast-template"
gemspec path: "gems/kettle-jem"
gemspec path: "gems/plain-merge"
gemspec path: "gems/bash-merge"
gemspec path: "gems/dotenv-merge"
gemspec path: "gems/rbs-merge"
gemspec path: "gems/binary-merge"
gemspec path: "gems/zip-merge"
gemspec path: "gems/html-merge"
gemspec path: "gems/json-merge"
gemspec path: "gems/toml-merge"
gemspec path: "gems/citrus-toml-merge"
gemspec path: "gems/parslet-toml-merge"
gemspec path: "gems/yaml-merge"
gemspec path: "gems/psych-merge"
gemspec path: "gems/markdown-merge"
gemspec path: "gems/kramdown-merge"
gemspec path: "gems/commonmarker-merge"
gemspec path: "gems/markly-merge"
gemspec path: "gems/ruby-merge"
gemspec path: "gems/prism-merge"
gemspec path: "gems/typescript-merge"
gemspec path: "gems/rust-merge"
gemspec path: "gems/go-merge"
gemspec path: "gems/smorg-rb"

gem "rake"
gem "rspec"
gem "token-resolver", "~> 2.0", ">= 2.0.4"

gem "appraisal2", "~> 3.2", ">= 3.2.0"

gem "bundler-audit", "~> 0.9.3"

if kettle_dev_dev.casecmp("false").zero?
  gem "kettle-dev", "~> 3.0", ">= 3.0.0"

  gem 'kettle-family', '~> 1.2', '>= 1.2.55'

  gem "kettle-soup-cover", "~> 3.0", ">= 3.0.6"

  gem "kettle-test", "~> 2.0", ">= 2.0.11"
end

if kettle_dev_dev.casecmp("false").zero?
  gem "kettle-drift", "~> 1.0", ">= 1.0.8", require: false
end


gem "stone_checksums", "~> 1.0", ">= 1.0.3"

gem "gitmoji-regex", "~> 2.0", ">= 2.0.1"

gem "turbo_tests2", "~> 3.1", ">= 3.1.14"

# Debugging
platform :mri do
  gem "debug", ">= 1.1"
end

gem "gem_bench", "~> 2.0", ">= 2.0.5"

# Style
gem "reek", "~> 6.5", ">= 6.5.0"

platform :mri do
  gem "appraisal2-rubocop", "~> 1.0", ">= 1.0.0", require: false
  gem "rubocop-gradual", "~> 0.4", ">= 0.4.0"
  gem "rubocop-minitest", "~> 0.40", ">= 0.40.0"
  gem "rubocop-on-rbs", "~> 2.0", ">= 2.0.0"
  gem "rubocop-packaging", "~> 0.6", ">= 0.6.0"
  gem "standard", "~> 1.56", ">= 1.56.0"

  if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("false").zero?
    gem "rubocop-lts", "~> 24.2", ">= 24.2.1"
    gem "rubocop-lts-rspec", "~> 1.0", ">= 1.0.5"
    gem "rubocop-ruby3_2", "~> 3.0", ">= 3.0.6"
  end
end

# Documentation
gem "kramdown", "~> 2.5", ">= 2.5.2", require: false
gem "kramdown-parser-gfm", "~> 1.1", require: false
gem "yaml-converter", "~> 0.2", ">= 0.2.3", require: false
gem "yard", "~> 0.9", ">= 0.9.45", require: false
gem "yard-junk", "~> 0.1", ">= 0.1.0", require: false
gem "yard-lint", "~> 1.10", ">= 1.10.2", require: false
gem "yard-relative_markdown_links", "~> 0.6", require: false

if ENV.fetch("GALTZO_FLOSS_DEV", "false").casecmp("false").zero?
  gem "yard-fence", "~> 0.9", ">= 0.9.6", require: false
  gem "yard-timekeeper", "~> 0.2", ">= 0.2.4", require: false
  gem "yard-yaml", "~> 0.2", ">= 0.2.3", require: false
end

gem "rdoc", "~> 6.11", require: false unless ENV.fetch("KJ_FRAMEWORK_MATRIX_GEM", "") == "rdoc"

# Optional and extracted stdlib tools used by the templated main Gemfile stack.
gem "addressable", ">= 2.8", "< 3"
gem "rbs", ">= 3.0", require: false
gem "irb", "~> 1.17"

ruby_version = Gem::Version.new(RUBY_VERSION)

if ruby_version >= Gem::Version.new("4.0")
  gem "benchmark", "~> 0.5", ">= 0.5.0"
  gem "cgi", "~> 0.5"
  gem "erb", "~> 6.0", ">= 6.0.6"
  gem "mutex_m", "~> 0.2"
  gem "stringio", ">= 3.0"
  gem "webrick", "~> 1.9"
elsif ruby_version >= Gem::Version.new("3.2")
  gem "erb", "~> 6.0", ">= 6.0.6"
  gem "mutex_m", "~> 0.2"
  gem "stringio", ">= 3.0"
elsif ruby_version >= Gem::Version.new("3.1")
  gem "mutex_m", "~> 0.2"
  gem "stringio", ">= 3.0"
else
  gem "erb", "~> 3.0"
  gem "mutex_m", "~> 0.2"
  gem "stringio", ">= 3.0"
end
