kettle_dev_dev = ENV.fetch("KETTLE_DEV_DEV", "false")

source "https://rubygems.org"

# Use released TSLP with the Ruby ABI platform-gem fix.
gem "tree_sitter_language_pack", "~> 1.13", ">= 1.13.3"

unless kettle_dev_dev.casecmp("false").zero?
  require "nomono/bundler"

  eval_nomono_gems(
    gems: %w[kettle-dev kettle-family kettle-test],
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
    gems: %w[turbo_tests2],
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

gem "appraisal2", "~> 3.1", ">= 3.1.1"

gem "bundler-audit", "~> 0.9.3"

if kettle_dev_dev.casecmp("false").zero?
  gem "kettle-dev", "~> 2.2", ">= 2.2.25"

  gem "kettle-family", ">= 1.0.4"

  gem "kettle-test", "~> 2.0", ">= 2.0.11"
end

gem "kettle-drift", "~> 1.0", ">= 1.0.5"


gem "stone_checksums", "~> 1.0", ">= 1.0.3"

gem "gitmoji-regex", "~> 2.0", ">= 2.0.1"

gem "turbo_tests2", "~> 3.1", ">= 3.1.14"
