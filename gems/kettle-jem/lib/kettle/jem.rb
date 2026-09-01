# frozen_string_literal: true

require "fileutils"
require "find"
require "English"
require "digest"
require "json"
require "net/http"
require "open3"
require "pathname"
require "parslet"
require "rbconfig"
require "time"
require "uri"
require "addressable/uri"
require "token/resolver"
require "yaml"
require "ast/merge"
require "ast/crispr/markdown/markly"
require "kettle/ndjson"
require "rbs"
require "kettle/dev"
require "kettle/changelog"
require "kettle/rb/compat_matrix"
require_relative "jem/version"
require_relative "jem/license_txt_migrator"
require_relative "jem/maintenance_changelog"

begin
  require "kettle/drift"
rescue LoadError
  # kettle-drift is optional; duplicate drift reports stay unavailable when absent.
end

module Kettle
  module Jem
    class Error < StandardError; end

    PACKAGE_NAME = "kettle-jem"
    CONTENT_RECIPE_TRANSPORT_VERSION = Ast::Merge::STRUCTURED_EDIT_TRANSPORT_VERSION
    TEMPLATE_SOURCE_APPLICATION_FINGERPRINT_VERSION = 1
    APPRAISALS_TEMPLATE_POLICY_FINGERPRINT_VERSION = 2
    GEMSPEC_TEMPLATE_POLICY_FINGERPRINT_VERSION = 2
    SPEC_HELPER_TEMPLATE_POLICY_FINGERPRINT_VERSION = 1
    VERSION_NAMESPACE_TEMPLATE_POLICY_FINGERPRINT_VERSION = 2
    KETTLE_CONFIG_PATH = ".structuredmerge/kettle-jem.yml"
    LEGACY_KETTLE_CONFIG_PATH = ".kettle-jem.yml"
    KETTLE_LOCK_PATH = ".structuredmerge/kettle-jem.lock"
    LEGACY_KETTLE_LOCK_PATH = ".kettle-jem.lock"
    MANAGED_BLOCK_OPEN = "# <<kettle-jem:generated>> do not edit below this line"
    MANAGED_BLOCK_CLOSE = "# <</kettle-jem:generated>>"
    GEMSPEC_DEPENDENCY_MINIMUM_REQUIREMENTS = {
      "rspec-stubbed_env" => ">= 1.0.6"
    }.freeze
    DEFAULT_GEMSPEC_METADATA_VALUES = {
      "allowed_push_host" => "TODO: Set to your gem server 'https://example.com'"
    }.freeze
    OBSOLETE_GITHUB_WORKFLOWS = %w[
      ancient.yml
      legacy.yml
      supported.yml
      unsupported.yml
      main.yml
      deps_locked.yml
      deps_unlocked.yml
      hoary.yml
      codeql-analysis.yml
      tests.yml
    ].freeze
    OPENCOLLECTIVE_DISABLED_FILES = %w[.opencollective.yml .github/workflows/opencollective.yml].freeze
    OPT_IN_GITHUB_WORKFLOWS = %w[.github/workflows/discord-notifier.yml].freeze
    OBSOLETE_APPRAISAL_SPEC_EXEC_CMDS = [
      "env KETTLE_TEST_RUNNER=rspec kettle-test -I ../spec --options ../.rspec ../spec",
      "KETTLE_TEST_RUNNER=rspec kettle-test -I ../spec --options ../.rspec ../spec",
      "kettle-test -I ../spec --options ../.rspec ../spec"
    ].freeze
    DEFAULT_ENGINES = %w[ruby jruby truffleruby].freeze
    DEFAULT_OPENCOLLECTIVE_ORG = "galtzo-floss"
    RETIRED_GEMSPEC_DEVELOPMENT_DEPENDENCIES = %w[kettle-drift kettle-soup-cover rubocop-rspec yard-junk].freeze
    FILE_DELETION_PRIMITIVES = %w[
      supplied_obsolete_file_deletion
      supplied_opt_in_workflow_deletion
      supplied_inactive_packaged_workflow_deletion
      supplied_inactive_packaged_template_deletion
      supplied_disabled_opencollective_file_deletion
      supplied_legacy_destination_file_deletion
      supplied_obsolete_license_file_deletion
      supplied_shim_profile_file_deletion
    ].freeze
    PHASE_ORDER = %i[
      config_sync
      dev_container
      github_workflows
      quality_config
      modular_gemfiles
      spec_helper
      environment_templates
      remaining_files
      git_hooks
      license_files
      duplicate_check
    ].freeze
    PACKAGED_TEMPLATE_ROOT = File.expand_path("jem/templates", __dir__)
    TRANSFER_CHANGELOG_TEMPLATE_PATH = "CHANGELOG.transfer.md"
    TRANSFER_CHANGELOG_FILTER_FIELD_TYPES = {
      "profile" => :enum,
      "topology" => :enum,
      "ruby.min" => :version,
      "engine.jruby" => :boolean,
      "engine.truffleruby" => :boolean,
      "engine.alternates" => :boolean,
      "feature.appraisals" => :boolean,
      "feature.rubyforum" => :boolean,
      "feature.rubyforum_project_tag" => :boolean,
      "feature.corporate_sponsors" => :boolean,
      "feature.organization_logo" => :boolean,
      "feature.structuredmerge_driver" => :boolean,
      "feature.dedicated_version_gem" => :boolean,
      "workflow.dep_heads" => :boolean,
      "workflow.jruby_94" => :boolean,
      "version_gem.mode" => :enum
    }.freeze
    COPY_ONLY_WHEN_MISSING_TEMPLATE_PATHS = %w[REEK bin/setup].freeze
    MONOREPO_ROOT_TEMPLATE_PROFILE = "monorepo-root"
    MONOREPO_SUBGEM_PACKAGE_TEMPLATE_PROFILE = "monorepo-subgem-package"
    MONOREPO_SUBGEM_RELEASE_TEMPLATE_PROFILE = "monorepo-subgem-release"
    MONOREPO_SUBGEM_FULL_TEMPLATE_PROFILE = "monorepo-subgem-full"
    MONOREPO_SUBGEM_TEMPLATE_PROFILE = MONOREPO_SUBGEM_PACKAGE_TEMPLATE_PROFILE
    SHIM_TEMPLATE_PROFILE = "shim"
    FULL_TEMPLATE_PROFILE = "full"
    REPOSITORY_TOPOLOGY_STANDALONE = "standalone"
    REPOSITORY_TOPOLOGY_MONOREPO_SUBPROJECT = "monorepo-subproject"
    MONOREPO_ROOT_TEMPLATE_ENTRIES = [
      "CHANGELOG.md",
      "CODE_OF_CONDUCT.md",
      "CONTRIBUTING.md",
      "FUNDING.md",
      "Gemfile",
      "IRP.md",
      "LICENSE.md",
      "AGPL-3.0-only.md",
      "PolyForm-Small-Business-1.0.0.md",
      "RUBOCOP.md",
      "Rakefile",
      "SECURITY.md",
      ".github/FUNDING.yml",
      ".gitignore",
      ".structuredmerge/git-drivers.toml"
    ].freeze
    MONOREPO_SUBGEM_TEMPLATE_ENTRIES = [
      "README.md",
      "Rakefile",
      "LICENSE.md",
      "MIT.md",
      "AGPL-3.0-only.md",
      "PolyForm-Noncommercial-1.0.0.md",
      "PolyForm-Small-Business-1.0.0.md",
      "Big-Time-Public-License.md",
      "mise.toml",
      "Gemfile",
      "certs/pboling.pem",
      "tmp/.gitignore"
    ].freeze
    PACKAGED_MODULAR_GEMFILE_TEMPLATE_ENTRIES = Dir.glob(File.join(PACKAGED_TEMPLATE_ROOT, "gemfiles", "modular", "**", "*.example"))
      .map { |path| path.delete_prefix("#{PACKAGED_TEMPLATE_ROOT}/").sub(/\.example\z/, "") }
      .reject { |path| path == "gemfiles/modular/shunted.gemfile" }
      .sort
      .freeze
    MONOREPO_SUBGEM_RELEASE_TEMPLATE_ENTRIES = (
      MONOREPO_SUBGEM_TEMPLATE_ENTRIES + [
        "Gemfile",
        "Rakefile",
        ".rspec",
        ".simplecov",
        ".yard-lint.yml",
        ".yardignore",
        ".yardopts",
        "bin/setup",
        "spec/README.md",
        "spec/spec_helper.rb"
      ] + PACKAGED_MODULAR_GEMFILE_TEMPLATE_ENTRIES
    ).freeze
    SIMPLECOV_BOOTSTRAP_TEMPLATE_PATHS = %w[
      .simplecov
      spec/spec_helper.rb
    ].freeze
    SHIM_TEMPLATE_STATIC_ENTRIES = [
      "README.md",
      "CHANGELOG.md",
      "Gemfile",
      "Rakefile",
      ".gitignore",
      ".rspec",
      "gemfiles/modular/templating.gemfile",
      "gemfiles/modular/templating_local.gemfile",
      "spec/spec_helper.rb",
      "spec/shim_spec.rb",
      ".github/workflows/current.yml",
      ".structuredmerge/kettle-jem.yml"
    ].freeze
    SHIM_TEMPLATE_SOURCE_TARGETS = {
      "README.md" => "shim/README.md",
      "CHANGELOG.md" => "shim/CHANGELOG.md",
      "Gemfile" => "shim/Gemfile",
      "Rakefile" => "shim/Rakefile",
      ".rspec" => "shim/.rspec",
      "spec/spec_helper.rb" => "shim/spec/spec_helper.rb",
      "spec/shim_spec.rb" => "shim/spec/shim_spec.rb",
      ".github/workflows/current.yml" => "shim/.github/workflows/current.yml",
      ".structuredmerge/kettle-jem.yml" => "shim/.structuredmerge/kettle-jem.yml"
    }.freeze
    SHIM_PROFILE_CLEANUP_GLOBS = [
      "Appraisal.root.gemfile",
      "Appraisals",
      "Guardfile",
      ".simplecov",
      ".yard-lint.yml",
      ".yardignore",
      ".yardopts",
      ".github/FUNDING.yml",
      ".gitattributes",
      "bin/*",
      "gemfiles/**/*.gemfile",
      "sig/**/*.rbs",
      "spec/**/*_spec.rb",
      "spec/support/**/*",
      ".github/workflows/*.yml",
      "lib/**/*.rb",
      "*.gemspec"
    ].freeze
    EXECUTABLE_GIT_HOOK_PATHS = %w[
      .git-hooks/commit-msg
      .git-hooks/prepare-commit-msg
    ].freeze
    VERSION_GEM_TEMPLATE_SOURCES = [
      "lib/gem/version.rb",
      "lib/gem/version_gem.rb",
      "sig/gem.rbs"
    ].freeze
    KETTLE_CONFIG_ENV_SYNC_PATHS = Ractor.make_shareable({
      %w[project_emoji] => "KJ_PROJECT_EMOJI",
      %w[repository topology] => "KJ_REPOSITORY_TOPOLOGY",
      %w[min_divergence_threshold] => "KJ_MIN_DIVERGENCE_THRESHOLD",
      %w[yard_host] => "KJ_YARD_HOST",
      %w[homepage_uri] => "KJ_HOMEPAGE_URI",
      %w[rubyforum family_tag] => "KJ_RUBYFORUM_FAMILY_TAG",
      %w[rubyforum project_tag] => "KJ_RUBYFORUM_PROJECT_TAG",
      %w[rubygems min_ruby] => "KJ_MIN_RUBY",
      %w[rubygems version_gem_entrypoint] => "KJ_VERSION_GEM_ENTRYPOINT",
      %w[templates profile] => "KETTLE_JEM_TEMPLATE_PROFILE",
      %w[shim replacement_gem] => "KETTLE_JEM_SHIMMED_GEM",
      %w[shim replacement_require] => "KETTLE_JEM_SHIMMED_REQUIRE",
      %w[workflows exec_cmd] => "KJ_EXEC_CMD",
      %w[tokens forge gh_user] => "KJ_GH_USER",
      %w[tokens forge gl_user] => "KJ_GL_USER",
      %w[tokens forge cb_user] => "KJ_CB_USER",
      %w[tokens forge sh_user] => "KJ_SH_USER",
      %w[tokens author name] => "KJ_AUTHOR_NAME",
      %w[tokens author given_names] => "KJ_AUTHOR_GIVEN_NAMES",
      %w[tokens author family_names] => "KJ_AUTHOR_FAMILY_NAMES",
      %w[tokens author email] => "KJ_AUTHOR_EMAIL",
      %w[tokens author domain] => "KJ_AUTHOR_DOMAIN",
      %w[tokens author orcid] => "KJ_AUTHOR_ORCID",
      %w[tokens funding kofi] => "KJ_FUNDING_KOFI",
      %w[tokens funding open_collective] => %w[OPENCOLLECTIVE_HANDLE FUNDING_ORG],
      %w[tokens funding paypal] => "KJ_FUNDING_PAYPAL",
      %w[tokens funding buymeacoffee] => "KJ_FUNDING_BUYMEACOFFEE",
      %w[tokens funding liberapay] => "KJ_FUNDING_LIBERAPAY",
      %w[tokens social mastodon] => "KJ_SOCIAL_MASTODON",
      %w[tokens social bluesky] => "KJ_SOCIAL_BLUESKY",
      %w[tokens social linktree] => "KJ_SOCIAL_LINKTREE",
      %w[tokens social devto] => "KJ_SOCIAL_DEVTO"
    })
    KETTLE_CONFIG_INTERNAL_SYNC_PATHS = Ractor.make_shareable({
      %w[kettle-jem version] => :version
    })
    NON_LICENSE_MD_BASENAMES = %w[
      AGENTS
      CHANGELOG
      CODE_OF_CONDUCT
      CONTRIBUTING
      FUNDING
      IRP
      LICENSE
      README
      RUBOCOP
      SECURITY
    ].freeze
    KNOWN_LICENSE_TEMPLATE_BASENAMES = Dir.glob(File.join(PACKAGED_TEMPLATE_ROOT, "*.md.example"))
      .map { |path| File.basename(path, ".md.example") }
      .reject { |basename| NON_LICENSE_MD_BASENAMES.include?(basename) }
      .to_set
      .freeze
    MONOREPO_SUBGEM_README_BLOB_PATHS = %w[
      CHANGELOG.md
      CODE_OF_CONDUCT.md
      CONTRIBUTING.md
      IRP.md
      RUBOCOP.md
      SECURITY.md
    ].freeze
    README_DEV_TEST_STACK_GEMS = Ractor.make_shareable([
      {
        name: "appraisal2",
        repo: "https://github.com/appraisal-rb/appraisal2",
        role: "multi-dependency Appraisal matrix generation"
      },
      {
        name: "appraisal2-rubocop",
        repo: "https://github.com/appraisal-rb/appraisal2-rubocop",
        role: "RuboCop Appraisal generator integration"
      },
      {
        name: "kettle-dev",
        repo: "https://github.com/kettle-dev/kettle-dev",
        role: "development, release, and CI workflow tooling"
      },
      {
        name: "kettle-jem",
        repo: "https://github.com/kettle-dev/kettle-jem",
        role: "Appraisals & CI workflow templates"
      },
      {
        name: "kettle-soup-cover",
        repo: "https://github.com/kettle-dev/kettle-soup-cover",
        role: "SimpleCov coverage policy and reporting"
      },
      {
        name: "kettle-test",
        repo: "https://github.com/kettle-dev/kettle-test",
        role: "standard test runner and coverage harness"
      },
      {
        name: "rubocop-lts",
        repo: "https://github.com/rubocop-lts/rubocop-lts",
        role: "Ruby-version-aware linting"
      },
      {
        name: "turbo_tests2",
        repo: "https://github.com/galtzo-floss/turbo_tests2",
        role: "parallel test execution"
      }
    ])
    MONOREPO_SUBGEM_THIN_README_KEEP_HEADINGS = [
      "synopsis",
      "info you can shake a stick at",
      "compatibility",
      "installation",
      "configuration",
      "basic usage",
      "security",
      "contributing",
      "versioning",
      "license"
    ].freeze
    LEGACY_DESTINATION_PATHS = {
      ".github/copilot_instructions.md" => ".github/COPILOT_INSTRUCTIONS.md"
    }.freeze
    SUPPORTED_TEMPLATE_STRATEGIES = %i[merge accept_template keep_destination raw_copy].freeze
    SUPPORTED_TEMPLATE_FILE_TYPES = %i[ruby gemfile appraisals gemspec rakefile yaml toml markdown json jsonc json5 dotenv rbs bash text].freeze
    SUPPORTED_RUBY_METHOD_MOVE_POLICIES = %w[destination_order].freeze
    DEFAULT_RUBY_METHOD_MOVE_POLICY = "destination_order"
    SUPPORTED_YAML_COMMENT_MERGE_POLICIES = %w[preserve_destination template_fallback_when_missing template_documentation].freeze
    DEFAULT_TEMPLATE_YAML_COMMENT_MERGE_POLICY = "template_fallback_when_missing"
    EVENT_TYPES = %w[
      run_start
      phase_start
      phase_finish
      recipe
      post_apply_step
      command_step
      diagnostic
      summary
    ].freeze
    DEFAULT_EVENT_TYPES = EVENT_TYPES.freeze
    EVENT_TYPE_ALIASES = {
      "all" => EVENT_TYPES,
      "default" => DEFAULT_EVENT_TYPES,
      "progress" => %w[run_start phase_start phase_finish recipe post_apply_step command_step summary]
    }.freeze
    RECIPE_PLANNING_STRATEGIES = %w[sequential classified].freeze
    DISABLED_RECIPE_PLANNING_STRATEGY_VALUES = %w[0 false no off none sequential].freeze
    ENABLED_RECIPE_PLANNING_STRATEGY_VALUES = %w[1 true yes on classified classify].freeze
    WORKER_SAFE_RECIPE_NAME_PATTERNS = Ractor.make_shareable([
      /\Agithub_actions_framework_gemfile_/,
      /\Agithub_actions_obsolete_workflow_cleanup_/,
      /\Agithub_actions_opt_in_workflow_cleanup_/,
      /\Agithub_actions_inactive_packaged_workflow_cleanup_/,
      /\Aopencollective_disabled_file_cleanup_/,
      /\Atemplate_legacy_destination_cleanup_/,
      /\Atemplate_obsolete_license_cleanup_/,
      /\Atemplate_shim_profile_cleanup_/
    ])
    GITHUB_ACTIONS_FRAMEWORK_GEMFILE_RECIPE = /\Agithub_actions_framework_gemfile_/
    GITHUB_ACTIONS_OBSOLETE_WORKFLOW_CLEANUP_RECIPE = /\Agithub_actions_obsolete_workflow_cleanup_/
    GITHUB_ACTIONS_OPT_IN_WORKFLOW_CLEANUP_RECIPE = /\Agithub_actions_opt_in_workflow_cleanup_/
    OPENCOLLECTIVE_DISABLED_FILE_CLEANUP_RECIPE = /\Aopencollective_disabled_file_cleanup_/
    TEMPLATE_LEGACY_DESTINATION_CLEANUP_RECIPE = /\Atemplate_legacy_destination_cleanup_/
    TEMPLATE_OBSOLETE_LICENSE_CLEANUP_RECIPE = /\Atemplate_obsolete_license_cleanup_/
    TEMPLATE_SHIM_PROFILE_CLEANUP_RECIPE = /\Atemplate_shim_profile_cleanup_/
    GITHUB_ACTIONS_WORKFLOW_SNIPPETS_RECIPE = /\Agithub_actions_workflow_snippets_/
    TEMPLATE_SOURCE_PREFERENCE_RECIPE = /\Atemplate_source_preference_/
    TEMPLATE_SOURCE_APPLICATION_RECIPE = /\Atemplate_source_application_/
    DECISION_NO_WRITE_ACTIONS = %w[keep skip].freeze
    RUBY_TEMPLATE_POLICY_FILE_TYPES = %i[gemfile gemspec appraisals].freeze
    GEMFILE_POLICY_SELF_DEPENDENCIES = %w[appraisal].freeze
    TEMPLATE_CONTENT_PRIMITIVES = %w[
      supplied_kettle_config_bootstrap
      supplied_template_source_preference
      supplied_template_source_application
    ].freeze
    PROJECT_ROOT_SENSITIVE_TEMPLATE_PATHS = %w[
      README.md
      mise.toml
    ].freeze
    RACTOR_SAFE_ACCEPT_TEMPLATE_FILE_TYPES = %i[
      rbs
      ruby
    ].freeze
    RAKEFILE_GUARDED_REQUIRE_NAMES = %w[kettle/dev kettle/jem stone_checksums].freeze
    COVERAGE_THRESHOLD_KEYS = %w[K_SOUP_COV_MIN_BRANCH K_SOUP_COV_MIN_LINE].freeze
    GITHUB_WORKFLOW_ENGINE_JOB_KEYS = {
      "jruby" => "jruby",
      "truffleruby" => "truffleruby"
    }.freeze
    CHANGELOG_TRANSFER_KEY_SEPARATOR = /\s+-\s+/
    CHANGELOG_TRANSFER_KEY_PATTERN = /\Akettle-jem-template-\d{8}-\d{3}\z/
    CHANGELOG_TRANSFER_KEY_SCAN_PATTERN = /\bkettle-jem-template-\d{8}-\d{3}\b/
    CHANGELOG_INITIAL_TEMPLATE_KEY = "kettle-jem-template-initial"
    CHANGELOG_INITIAL_TEMPLATE_ENTRY = {
      key: CHANGELOG_INITIAL_TEMPLATE_KEY,
      section: "### Added",
      lines: ["- #{CHANGELOG_INITIAL_TEMPLATE_KEY} - Initial templating by kettle-jem."]
    }.freeze
    README_KLOC_BADGE_PATTERN = /(\[🧮kloc-img\]:\s*https?:\/\/img\.shields\.io\/badge\/KLOC-)(\d+(?:\.\d+)?)(-[^\s]*)/
    CHANGELOG_COVERAGE_KLOC_PATTERN = /-\s*COVERAGE:\s*.+--\s*\d+\/(\d+)\s+lines/i
    RUBY_TEMPLATE_BASENAMES = %w[Gemfile Rakefile Appraisals Appraisal.root.gemfile .simplecov].freeze
    RUBY_TEMPLATE_SUFFIXES = %w[.gemspec .gemfile].freeze
    RUBY_TEMPLATE_EXTENSIONS = %w[.rb .rake].freeze
    TEMPLATE_TOKEN_CONFIG = Token::Resolver::Config.new(separators: ["|", ":"]).freeze
    EMPTY_TEMPLATE_TOKENS = %w[
      KJ|CB:USER
      KJ|COPYRIGHT_PREFIX
      KJ|AUTHOR:DOMAIN
      KJ|AUTHOR:NAME
      KJ|AUTHOR:ORCID
      KJ|FUNDING:BUYMEACOFFEE
      KJ|FUNDING:KOFI
      KJ|FUNDING:LIBERAPAY
      KJ|FUNDING:PAYPAL
      KJ|GEMSPEC:PACKAGE_FILE_INCLUDES
      KJ|GH:USER
      KJ|GH_ORG
      KJ|GL:USER
      KJ|LICENSE_EYE:FLAGS
      KJ|LICENSE_EYE:DEPENDENCY_LICENSES
      KJ|LICENSE_EYE:MODE
      KJ|LICENSE_EYE:PRIMARY_SPDX
      KJ|LOCAL_GEMFILE_NOMONO_BOOTSTRAP
      KJ|MAIN_GEMFILE_KETTLE_FAMILY_GEM
      KJ|MAIN_GEMFILE_DIRECT_SIBLING_BLOCK
      KJ|MAIN_GEMFILE_NOMONO_BOOTSTRAP
      KJ|MIN_DIVERGENCE_THRESHOLD
      KJ|MIN_RUBY
      KJ|KETTLE_CHANGELOG_GEMFILE_DEPENDENCY
      KJ|OPENCOLLECTIVE_ORG
      KJ|README:COPYRIGHT_NOTICE
      KJ|README:CORPORATE_SPONSORS
      KJ|README:FAMILY_INTRO_BACKEND_MATRIX
      KJ|README:LICENSE_BADGE
      KJ|README:LICENSE_COMPAT_BADGE
      KJ|README:LICENSE_EYE_WORKFLOW_BADGE
      KJ|README:DEV_TEST_STACK_TABLE
      KJ|README:FOSSA_BADGE
      KJ|README:FOSSA_REFS
      KJ|README:H2_SYNOPSIS_LOGO_ROW
      KJ|README:LICENSE_INTRO
      KJ|README:LICENSE_REFS
      KJ|README:TOP_LOGO_REFS
      KJ|README:TOP_LOGO_ROW
      KJ|RUBYFORUM:FAMILY_TAG
      KJ|RUBYFORUM:PROJECT_TAG
      KJ|RUBY_STYLE:TRAILING_ARRAY_COMMA
      KJ|SH:USER
      KJ|SHIMMED_GEM_NAME
      KJ|SHIMMED_REQUIRE
      KJ|SHIM_COMPAT_REQUIRES
      KJ|SHIMMED_GEMFILE_OVERRIDE
      KJ|SOCIAL:BLUESKY
      KJ|SOCIAL:DEVTO
      KJ|SOCIAL:LINKTREE
      KJ|SOCIAL:MASTODON
    ].freeze
    COPYRIGHT_NAME_RE = /\ACopyright \(c\) [\d,\s-]+ (.+)\z/
    BOT_IDENTITY_PATTERN = /\[bot\]/i
    DEFAULT_MACHINE_USERS = ["autobolt", "StepSecurity Bot", "dependabot[bot]", "depfu[bot]"].freeze
    NOT_COMMITTED_EMAIL = "not.committed.yet"
    LOGOS_GALTZO_BASE_URL = "https://logos.galtzo.com/assets/images"
    README_TOP_LOGO_DEFAULTS = %w[org project].freeze
    README_H2_SYNOPSIS_LOGO_DEFAULTS = %w[related_org ruby].freeze
    README_TOP_LOGO_OPTIONS = %w[related_org ruby org project].freeze
    README_TOP_LOGO_LEGACY_MODE_MAP = Ractor.make_shareable({
      "org" => %w[related_org ruby org],
      "project" => %w[related_org ruby project],
      "org_and_project" => %w[related_org ruby org project]
    })
    KETTLE_CONFIG_LEGACY_KEY_PATHS = Ractor.make_shareable([
      {
        path: %w[readme top_logo_mode],
        replacement_path: %w[readme top_logos],
        added_in: "7.0.0",
        prune_after: "8.0.0"
      }
    ])
    README_TOP_LOGO_TYPES = %w[related_org ruby language org project affiliated_project].freeze
    APPRAISAL_NAME_PREFIX = "kja"
    APPRAISAL_GEM_ABBREVIATIONS = {
      "activerecord" => "ar",
      "actionmailer" => "am",
      "actionpack" => "ap",
      "activesupport" => "as",
      "activejob" => "aj",
      "actioncable" => "ac",
      "actionview" => "av",
      "activestorage" => "ast",
      "actionmailbox" => "amb",
      "actiontext" => "at",
      "omniauth" => "oa",
      "mongoid" => "mo",
      "sequel" => "sq",
      "couch_potato" => "cp",
      "rom" => "rom",
      "rom-sql" => "rsql"
    }.freeze
    APPRAISAL_WORKFLOW_LIFECYCLE_RANGES = Ractor.make_shareable({
      "current" => {min: Gem::Version.new("3.4"), max: Gem::Version.new("3.99")},
      "supported" => {min: Gem::Version.new("3.2"), max: Gem::Version.new("3.3")},
      "legacy" => {min: Gem::Version.new("3.0"), max: Gem::Version.new("3.1")},
      "unsupported" => {min: Gem::Version.new("2.6"), max: Gem::Version.new("2.7")},
      "ancient" => {min: Gem::Version.new("2.3"), max: Gem::Version.new("2.5")}
    })
    APPRAISAL_ALWAYS_EXCLUDED_GEMS = %w[version_gem].freeze
    APPRAISAL_VERSION_SELECTION_MODES = %w[major minor patch minor-minmax semver].freeze
    DEFAULT_TEST_MINIMUM_RUBY = Gem::Version.new("2.4")
    REQUIRE_RELATIVE_MIN_RUBY = Gem::Version.new("2.2").freeze
    ANONYMOUS_VERSION_LOADER_MIN_RUBY = Gem::Version.new("2.2").freeze
    MODERN_GEMSPEC_VERSION_LOADER_MIN_RUBY = Gem::Version.new("3.1").freeze
    APPRAISAL_DEFAULT_FRESHNESS_TTL = 604_800
    DECISION_ACTIONS = %w[create merge replace keep delete skip].freeze
    DECISION_SEVERITIES = %w[advisory warning fatal].freeze

    DecisionEvaluation = Struct.new(
      :id,
      :category,
      :file,
      :default_action,
      :selected_action,
      :source,
      :severity,
      :blocking,
      :diagnostics,
      :prompt_required,
      :prompt
    ) do
      def to_h
        {
          id: id,
          category: category,
          file: file,
          default_action: default_action,
          selected_action: selected_action,
          source: source,
          severity: severity,
          blocking: blocking,
          diagnostics: diagnostics,
          prompt_required: prompt_required,
          prompt: prompt
        }.compact
      end
    end

    class DecisionPolicy
      TRUE_VALUES = %w[1 true y yes on].freeze
      FALSE_VALUES = %w[0 false n no off].freeze

      attr_reader :mode, :failure_mode, :require_clean, :input_source, :prompt_answers

      def self.from_env(env = {}, **options)
        env_hash = env || {}
        option_hash = symbolize_keys(options)
        interactive = option_hash.key?(:interactive) ? option_hash[:interactive] : truthy?(env_hash["interactive"])
        force = option_hash.key?(:force) ? option_hash[:force] : value_to_boolean(env_hash["force"])
        accept = option_hash.key?(:accept) ? option_hash[:accept] : value_to_boolean(env_hash["accept"])
        interactive = false if accept == true || force == true
        interactive = true if force == false && accept != true && !option_hash.key?(:interactive)
        new(
          mode: interactive ? :interactive : :accept,
          failure_mode: option_hash.fetch(:failure_mode, env_hash["FAILURE_MODE"] || env_hash["failure_mode"] || "error"),
          require_clean: option_hash.fetch(:require_clean, value_to_boolean(env_hash["KETTLE_JEM_REQUIRE_CLEAN"])),
          input_source: option_hash.fetch(:input_source, "default"),
          prompt_answers: option_hash.fetch(:prompt_answers, parse_prompt_answers(env_hash["KETTLE_JEM_PROMPT_ANSWERS"]))
        )
      end

      def self.symbolize_keys(hash)
        hash.each_with_object({}) { |(key, value), acc| acc[key.to_sym] = value }
      end

      def self.truthy?(value)
        TRUE_VALUES.include?(value.to_s.strip.downcase)
      end

      def self.falsey?(value)
        FALSE_VALUES.include?(value.to_s.strip.downcase)
      end

      def self.value_to_boolean(value)
        return true if value == true
        return false if value == false
        return true if truthy?(value)
        return false if falsey?(value)

        nil
      end

      def self.parse_prompt_answers(value)
        return {} if value.nil? || value.to_s.strip.empty?

        parsed = JSON.parse(value.to_s)
        raise ArgumentError, "KETTLE_JEM_PROMPT_ANSWERS must be a JSON object" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError => error
        raise ArgumentError, "KETTLE_JEM_PROMPT_ANSWERS must be valid JSON: #{error.message}"
      end

      def initialize(mode: :accept, failure_mode: "error", require_clean: nil, input_source: "default", prompt_answers: {})
        @mode = normalize_mode(mode)
        @failure_mode = failure_mode.to_s.empty? ? "error" : failure_mode.to_s
        @require_clean = require_clean
        @input_source = input_source.to_s
        @prompt_answers = normalize_prompt_answers(prompt_answers)
      end

      def accept?
        mode == :accept
      end

      def interactive?
        mode == :interactive
      end

      def non_interactive?
        !interactive?
      end

      def resolve(id:, category:, default_action:, file: nil, severity: :advisory, diagnostics: [])
        action = normalize_action(default_action)
        severity_value = normalize_severity(severity)
        raise Error, "No safe default decision for #{id}" if action.nil? && severity_value == "fatal"
        promptable = interactive? && !action.nil? && severity_value != "fatal"
        answer = promptable ? prompt_answers[id.to_s] : nil
        selected_action = answer || action
        selected_source = if answer
          "interactive_answer"
        elsif promptable
          "interactive_default"
        else
          "default"
        end
        decision_diagnostics = Array(diagnostics).compact.map(&:to_s)
        prompt = nil
        if promptable
          prompt = {
            id: id.to_s,
            category: category.to_s,
            file: file&.to_s,
            message: "Apply #{category.to_s.tr("_", " ")} for #{file || id}?",
            default_action: action,
            choices: DECISION_ACTIONS
          }.compact
          decision_diagnostics << if answer
            "Interactive prompt answer supplied through the shared decision policy input contract."
          else
            "Interactive prompt transport is active; selected the configured default pending an external response."
          end
        end

        DecisionEvaluation.new(
          id: id.to_s,
          category: category.to_s,
          file: file&.to_s,
          default_action: action,
          selected_action: selected_action,
          source: selected_source,
          severity: severity_value,
          blocking: severity_value == "fatal",
          diagnostics: decision_diagnostics,
          prompt_required: promptable,
          prompt: prompt
        )
      end

      def to_h
        {
          mode: mode.to_s,
          non_interactive: non_interactive?,
          accept: accept?,
          interactive: interactive?,
          failure_mode: failure_mode,
          require_clean: require_clean,
          input_source: input_source,
          prompt_answers: prompt_answers.empty? ? nil : prompt_answers
        }.compact
      end

      private

      def normalize_prompt_answers(value)
        Hash(value || {}).each_with_object({}) do |(key, answer), acc|
          acc[key.to_s] = normalize_action(answer)
        end
      end

      def normalize_mode(value)
        normalized = value.to_s.strip.downcase.tr("-", "_")
        return :interactive if normalized == "interactive"
        return :accept if normalized.empty? || %w[accept force non_interactive default].include?(normalized)

        raise ArgumentError, "Unsupported Kettle/Jem decision mode #{value.inspect}"
      end

      def normalize_action(value)
        return if value.nil?

        action = value.to_s.strip
        raise ArgumentError, "Unsupported Kettle/Jem decision action #{value.inspect}" unless DECISION_ACTIONS.include?(action)

        action
      end

      def normalize_severity(value)
        severity_value = value.to_s.strip
        raise ArgumentError, "Unsupported Kettle/Jem decision severity #{value.inspect}" unless DECISION_SEVERITIES.include?(severity_value)

        severity_value
      end
    end

    class TransferChangelogLineParser < Parslet::Parser
      rule(:space) { match('\s') }
      rule(:digit) { match("[0-9]") }
      rule(:date) { digit.repeat(8, 8).as(:date) }
      rule(:sequence) { digit.repeat(3, 3).as(:sequence) }
      rule(:key) { (str("kettle-jem-template-") >> date >> str("-") >> sequence).as(:key) }
      rule(:filter_character) { str("]").absent? >> any }
      rule(:filter) do
        str("[") >> str("if") >> space.repeat(1) >> filter_character.repeat(1).as(:filter) >> str("]")
      end
      rule(:separator) { space.repeat(1) >> str("-") >> space.repeat(1) }
      rule(:message) { any.repeat(1).as(:message) }
      rule(:entry) { key >> (space.repeat(1) >> filter).maybe >> separator >> message >> any.absent? }
      root(:entry)
    end

    # This deliberately accepts only conjunctions.  A transfer entry should be
    # easy to audit, and derived boolean facts avoid a general-purpose query
    # language for the few cases where an OR would otherwise be tempting.
    class TransferChangelogFilterParser < Parslet::Parser
      rule(:space) { match('\s') }
      rule(:identifier_start) { match("[A-Za-z]") }
      rule(:identifier_rest) { match("[A-Za-z0-9_.]") }
      rule(:identifier) { (identifier_start >> identifier_rest.repeat).as(:field) }
      rule(:operator) { (str(">=") | str("<=") | str("!=") | str("=") | str(">") | str("<")).as(:operator) }
      rule(:literal) { match("[A-Za-z0-9_.-]").repeat(1).as(:value) }
      rule(:predicate) { (identifier >> operator >> literal).as(:predicate) }
      rule(:separator) { space.repeat >> str("&") >> space.repeat }
      rule(:expression) { predicate.as(:predicate) >> (separator >> predicate.as(:predicate)).repeat }
      root(:expression)
    end

    module ReadmePostProcessor
      module_function

      ENGINE_COMPATIBILITY_MRI_VERSION = {
        "jruby" => {
          "9.1" => Gem::Version.new("2.3"),
          "9.2" => Gem::Version.new("2.5"),
          "9.3" => Gem::Version.new("2.6"),
          "9.4" => Gem::Version.new("3.1"),
          "10.0" => Gem::Version.new("3.4")
        }.freeze,
        "truby" => {
          "22.3" => Gem::Version.new("3.0"),
          "23.0" => Gem::Version.new("3.0"),
          "23.1" => Gem::Version.new("3.1"),
          "24.2" => Gem::Version.new("3.3"),
          "25.0" => Gem::Version.new("3.3"),
          "33.0" => Gem::Version.new("3.3")
        }.freeze
      }.freeze
      COMPATIBILITY_REFERENCE_LABEL_RE = /\A(?:💎(?:ruby|jruby|truby)-|🚎)/
      ENGINE_ROW_PATTERNS = Ractor.make_shareable({
        "jruby" => {
          row_prefix: "| Works with JRuby",
          badge_prefixes: %w[💎jruby-],
          ref_prefixes: [/\A🚎jruby-/, /\A🚎\d+-j-/]
        }.freeze,
        "truffleruby" => {
          row_prefix: "| Works with Truffle Ruby",
          badge_prefixes: %w[💎truby-],
          ref_prefixes: [/\A🚎truby-/, /\A🚎\d+-t-/]
        }.freeze
      })
      VERSIONED_ENGINE_COMPATIBILITY_BADGES = [
        {
          engine: "jruby",
          version: "10.0",
          workflow_path: ".github/workflows/jruby-10.0.yml",
          workflow_file: "jruby-10.0.yml",
          row_prefix: "| Works with JRuby",
          badge_label: "💎jruby-10.0i",
          workflow_label: "🚎jruby-10.0-wf",
          inline: "[![JRuby 10.0 Compat][💎jruby-10.0i]][🚎jruby-10.0-wf]",
          insert_before: "💎jruby-c-i",
          badge_definition: "[💎jruby-10.0i]: https://img.shields.io/badge/JRuby-10.0-FBE742?style=for-the-badge&logo=ruby&logoColor=red"
        }.freeze,
        {
          engine: "truby",
          version: "33.0",
          workflow_path: ".github/workflows/truffleruby-33.0.yml",
          workflow_file: "truffleruby-33.0.yml",
          row_prefix: "| Works with Truffle Ruby",
          badge_label: "💎truby-33.0i",
          workflow_label: "🚎truby-33.0-wf",
          inline: "[![Truffle Ruby 33.0 Compat][💎truby-33.0i]][🚎truby-33.0-wf]",
          insert_before: "💎truby-c-i",
          badge_definition: "[💎truby-33.0i]: https://img.shields.io/badge/Truffle_Ruby-33.0-34BCB1?style=for-the-badge&logo=ruby&logoColor=pink"
        }.freeze
      ].freeze

      def process(content:, min_ruby:, engines: nil, workflow_paths: nil)
        Kettle::Jem.ensure_runtime_dependencies!
        processed = content.to_s
        processed = remove_disabled_engine_content(processed, engines) if engines
        processed = remove_missing_workflow_badges(processed, workflow_paths) if workflow_paths
        return processed if min_ruby.to_s.empty?

        min_ruby_version = Gem::Version.new(min_ruby.to_s)
        processed = add_supported_versioned_engine_badges(processed, min_ruby_version, workflow_paths) if workflow_paths
        processed = remove_incompatible_compatibility_badges(processed, min_ruby_version)
        processed = normalize_compatibility_rows(processed)
        prune_unused_compatibility_reference_definitions(processed)
      end

      def remove_disabled_engine_content(content, engines)
        enabled = Array(engines).map { |engine| engine.to_s.strip.downcase }
        processed = content.to_s

        ENGINE_ROW_PATTERNS.each do |engine, patterns|
          next if enabled.include?(engine)

          processed = remove_markdown_table_rows(processed) do |owner|
            owner.source.to_s.lstrip.start_with?(patterns.fetch(:row_prefix))
          end
          labels = markdown_inline_reference_owners(processed).flat_map(&:labels).uniq
          labels.each do |label|
            next unless patterns.fetch(:badge_prefixes).any? { |prefix| label.start_with?(prefix) }

            processed = remove_badge_occurrences(processed, label)
          end
          ref_labels = markdown_link_definition_owners(processed).filter_map do |owner|
            label = owner.label.to_s
            label if patterns.fetch(:ref_prefixes).any? { |pattern| pattern.match?(label) }
          end
          ref_labels.each do |label|
            processed = remove_markdown_inline_references(processed, label)
          end
          processed = delete_markdown_link_definitions(processed, ref_labels)
        end

        processed
      end

      def remove_missing_workflow_badges(content, workflow_paths)
        existing = Array(workflow_paths).map { |path| path.to_s.delete_prefix("./") }.to_set
        workflow_references(content).each do |label, workflow_path|
          next if existing.include?(workflow_path)

          content = remove_workflow_badge_occurrences(content, label)
        end

        content
      end

      def workflow_references(content)
        markdown_structural_owners(content, :link_definitions).fetch(:link_definitions).each_with_object({}) do |owner, references|
          workflow = URI(owner.url.to_s).path.to_s.split("/actions/workflows/", 2).last
          next unless workflow
          workflow = workflow.split("/", 2).first

          references[owner.label.to_s] = ".github/workflows/#{workflow}"
        end
      rescue URI::InvalidURIError
        {}
      end

      def remove_workflow_badge_occurrences(content, workflow_label)
        remove_markdown_inline_references(content, workflow_label)
      end

      def add_supported_versioned_engine_badges(content, min_ruby, workflow_paths)
        existing_workflows = Array(workflow_paths).map { |path| path.to_s.delete_prefix("./") }.to_set
        VERSIONED_ENGINE_COMPATIBILITY_BADGES.reduce(content.to_s) do |processed, badge|
          next processed unless existing_workflows.include?(badge.fetch(:workflow_path))
          next processed if processed.include?("[#{badge.fetch(:badge_label)}]:")
          next processed unless versioned_engine_badge_compatible?(badge, min_ruby)

          with_inline = add_versioned_engine_badge_to_row(processed, badge)
          next processed if with_inline == processed

          add_versioned_engine_badge_definitions(with_inline, badge)
        end
      end

      def versioned_engine_badge_compatible?(badge, min_ruby)
        badge_min_mri = ENGINE_COMPATIBILITY_MRI_VERSION.dig(badge.fetch(:engine), badge.fetch(:version))
        badge_min_mri && ruby_minor_version(badge_min_mri) >= ruby_minor_version(min_ruby)
      end

      def add_versioned_engine_badge_to_row(content, badge)
        lines = content.lines
        row_index = lines.index { |line| line.lstrip.start_with?(badge.fetch(:row_prefix)) }
        return content unless row_index
        return content if lines.fetch(row_index).include?(badge.fetch(:badge_label))

        line = lines.fetch(row_index)
        insert_before = badge.fetch(:insert_before)
        inline = badge.fetch(:inline)
        lines[row_index] = if line.include?("[#{insert_before}]")
          line.sub(/(?=\[!\[[^\]]+\]\[#{Regexp.escape(insert_before)}\])/, "#{inline} ")
        else
          line.sub(/\s*\|\s*$/, " #{inline}|")
        end
        lines.join
      end

      def add_versioned_engine_badge_definitions(content, badge)
        processed = ensure_markdown_link_definition(content, badge.fetch(:badge_definition))
        return processed if processed.include?("[#{badge.fetch(:workflow_label)}]:")

        workflow_base = workflow_definition_base_url(processed)
        return processed unless workflow_base

        ensure_markdown_link_definition(
          processed,
          "[#{badge.fetch(:workflow_label)}]: #{workflow_base}/actions/workflows/#{badge.fetch(:workflow_file)}"
        )
      end

      def ensure_markdown_link_definition(content, definition)
        label = definition[/\A(\[[^\]]+\]):/, 1]
        return content if label && content.include?("#{label}:")

        separator = content.end_with?("\n") ? "" : "\n"
        "#{content}#{separator}#{definition}\n"
      end

      def workflow_definition_base_url(content)
        markdown_link_definition_owners(content).filter_map do |owner|
          url = owner.url.to_s
          url.split("/actions/workflows/", 2).first if url.include?("/actions/workflows/")
        end.first
      end

      def remove_incompatible_compatibility_badges(content, min_ruby)
        markdown_inline_reference_owners(content).flat_map(&:labels).uniq.each do |label|
          badge_min_mri = compatibility_badge_min_mri(label)
          next unless badge_min_mri && ruby_minor_version(badge_min_mri) < ruby_minor_version(min_ruby)

          content = remove_badge_occurrences(content, label)
        end

        content
      end

      def compatibility_badge_min_mri(label)
        if (match = label.match(/\A💎ruby-(?<version>\d+\.\d+)i\z/))
          Gem::Version.new(match[:version])
        elsif (match = label.match(/\A💎(?<engine>jruby|truby)-(?<version>\d+\.\d+)i\z/))
          ENGINE_COMPATIBILITY_MRI_VERSION.dig(match[:engine], match[:version])
        end
      rescue
        nil
      end

      def ruby_minor_version(version)
        segments = version.segments
        Gem::Version.new("#{segments[0]}.#{segments[1] || 0}")
      end

      def remove_badge_occurrences(content, label)
        remove_markdown_inline_references(content, label)
      end

      def normalize_compatibility_rows(content)
        lines = content.lines
        markdown_table_row_owners(content).each do |owner|
          line = lines[owner.location.start_line - 1]
          next unless compatibility_row?(line)

          cells = line.split("|", -1)
          badge_cell = normalize_compatibility_badge_cell(cells[2])
          if badge_cell.empty?
            lines[owner.location.start_line - 1] = nil
            next
          end

          cells[2] = " #{badge_cell}"
          lines[owner.location.start_line - 1] = cells.join("|")
        end
        lines.compact.join
      end

      def normalize_compatibility_badge_cell(cell)
        cell.to_s
          .split(/<br\/>/i)
          .filter_map do |segment|
            normalized = segment.gsub(/[ \t]+/, " ").strip
            normalized unless normalized.empty?
          end
          .join(" <br/> ")
      end

      def prune_unused_compatibility_reference_definitions(content)
        owners = markdown_structural_owners(content, :inline_references, :link_definitions)
        referenced_labels = owners.fetch(:inline_references).flat_map(&:labels).to_h { |label| [label, true] }

        labels = owners.fetch(:link_definitions).filter_map do |owner|
          label = owner.label.to_s
          label if COMPATIBILITY_REFERENCE_LABEL_RE.match?(label) && !referenced_labels[label]
        end
        delete_markdown_link_definitions(content, labels)
      end

      def prune_orphaned_workflow_inline_references(content)
        owners = markdown_structural_owners(content, :link_definitions, :inline_references)
        defined_labels = owners.fetch(:link_definitions).map { |owner| owner.label.to_s }.to_set
        orphaned_labels = owners.fetch(:inline_references).flat_map(&:labels).map(&:to_s).uniq.select do |label|
          label.start_with?("🚎") && !defined_labels.include?(label)
        end
        processed = orphaned_labels.reduce(content.to_s) do |memo, label|
          remove_markdown_inline_references(memo, label)
        end
        normalize_compatibility_rows(processed)
      end

      def markdown_link_definition_owners(content)
        Kettle::Jem.ensure_runtime_dependencies!
        context = Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: "README.md")
        context.structural_owners(owner_scope: :link_definitions)
      rescue Ast::Crispr::Error
        []
      end

      def markdown_inline_reference_owners(content)
        Kettle::Jem.ensure_runtime_dependencies!
        context = Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: "README.md")
        context.structural_owners(owner_scope: :inline_references)
      rescue Ast::Crispr::Error
        []
      end

      def markdown_table_row_owners(content)
        Kettle::Jem.ensure_runtime_dependencies!
        context = Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: "README.md")
        context.structural_owners(owner_scope: :table_rows)
      rescue Ast::Crispr::Error
        []
      end

      def markdown_structural_owners(content, *owner_scopes)
        Kettle::Jem.ensure_runtime_dependencies!
        context = Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: "README.md")
        owner_scopes.each_with_object({}) do |owner_scope, owners|
          owners[owner_scope] = context.structural_owners(owner_scope: owner_scope)
        end
      rescue Ast::Crispr::Error
        owner_scopes.to_h { |owner_scope| [owner_scope, []] }
      end

      def compatibility_row?(line)
        text = line.to_s.lstrip
        text.start_with?("| Works with MRI Ruby", "| Works with JRuby", "| Works with Truffle Ruby")
      end

      def delete_markdown_link_definitions(content, labels)
        Kettle::Jem.ensure_runtime_dependencies!
        targets = labels.uniq.map do |label|
          Ast::Crispr::Markdown::Markly::Selectors.link_definition(label: label, limit: {at_least: 0})
        end
        return content if targets.empty?

        Ast::Crispr::DeleteBatch.call(content: content.to_s, targets: targets, source_label: "README.md").updated_content
      end

      def remove_markdown_inline_references(content, label)
        lines = content.to_s.lines
        markdown_inline_reference_owners(content).select { |owner| owner.labels.include?(label.to_s) }
          .group_by(&:line)
          .each do |line_number, owners|
            index = line_number - 1
            line = lines[index].to_s
            owners.sort_by(&:start_column).reverse_each do |owner|
              start_column = owner.start_column
              end_column = owner.end_column
              if start_column.positive? && line[start_column - 1] == " "
                start_column -= 1
              elsif line[end_column] == " "
                end_column += 1
              end
              line = "#{line[0...start_column]}#{line[end_column..]}"
            end
            lines[index] = line
          end
        lines.join
      end

      def remove_markdown_table_rows(content)
        lines = content.to_s.lines
        markdown_table_row_owners(content).select { |owner| yield owner }.reverse_each do |owner|
          lines.delete_at(owner.location.start_line - 1)
        end
        lines.join
      end
    end

    class RubyGemsResolver
      RUBYGEMS_V1_API_BASE = "https://gem.coop/api/v1"
      RUBYGEMS_V2_API_BASE = "https://gem.coop/api/v2/rubygems"

      attr_reader :cache

      def initialize(cache: {}, http_get: nil, v1_api_base: RUBYGEMS_V1_API_BASE, v2_api_base: RUBYGEMS_V2_API_BASE)
        @cache = cache
        @http_get = http_get || ->(uri) { Net::HTTP.get_response(uri) }
        @v1_api_base = v1_api_base.to_s.delete_suffix("/")
        @v2_api_base = v2_api_base.to_s.delete_suffix("/")
      end

      def versions(gem_name, include_prerelease: false, requirements: nil)
        requirement = normalize_requirements(requirements)
        fetch_versions(gem_name).filter_map do |entry|
          number = entry["number"].to_s
          next if number.empty?
          next if !include_prerelease && entry["prerelease"]
          next if requirement && !requirement.satisfied_by?(Gem::Version.new(number))

          {
            number: number,
            ruby_version: entry["ruby_version"],
            created_at: entry["created_at"],
            prerelease: !!entry["prerelease"]
          }
        end.sort_by { |entry| Gem::Version.new(entry.fetch(:number)) }
      end

      def version_info(gem_name, version)
        data = fetch_gem_info(gem_name, version)
        return unless data

        runtime_dependencies = Array(data.dig("dependencies", "runtime")).map do |dependency|
          {
            name: dependency["name"],
            requirements: dependency["requirements"]
          }
        end

        {
          number: data["number"] || version.to_s,
          ruby_version: data["ruby_version"],
          runtime_dependencies: runtime_dependencies
        }
      end

      def min_ruby_version(gem_name, version)
        entry = fetch_versions(gem_name).find { |candidate| candidate["number"].to_s == version.to_s }
        parse_min_ruby(entry && entry["ruby_version"])
      end

      def minor_versions_by_major(gem_name, requirements: nil)
        versions(gem_name, requirements: requirements).each_with_object({}) do |entry, grouped|
          version = Gem::Version.new(entry.fetch(:number))
          segments = version.segments
          next unless segments[0]

          major = segments[0]
          minor = "#{segments[0]}.#{segments[1] || 0}"
          grouped[major] ||= Set.new
          grouped[major] << minor
        end.sort_by(&:first).map do |major, minors|
          {
            major: major,
            minors: minors.to_a.sort_by { |minor| Gem::Version.new(minor) }
          }
        end
      end

      def fetch_versions(gem_name)
        cache_key = "versions:#{gem_name}"
        return cache.fetch(cache_key) if cache.key?(cache_key)

        uri = URI("#{@v1_api_base}/versions/#{escape_path_component(gem_name)}.json")
        response = @http_get.call(uri)
        raise Error, "RubyGems API error for #{gem_name}: #{response_code(response)}" unless successful_response?(response)

        cache[cache_key] = JSON.parse(response_body(response)).sort_by { |entry| Gem::Version.new(entry.fetch("number")) }
      end

      def fetch_gem_info(gem_name, version)
        cache_key = "info:#{gem_name}:#{version}"
        return cache.fetch(cache_key) if cache.key?(cache_key)

        uri = URI("#{@v2_api_base}/#{escape_path_component(gem_name)}/versions/#{escape_path_component(version)}.json")
        response = @http_get.call(uri)
        return unless successful_response?(response)

        cache[cache_key] = JSON.parse(response_body(response))
      end

      def parse_min_ruby(requirement)
        return if requirement.to_s.strip.empty?

        parsed = Gem::Requirement.new(requirement.to_s)
        parsed.requirements.each do |operator, version|
          return version if operator == ">="
        end
        parsed.requirements.each do |operator, version|
          return version if operator == "~>"
        end
        nil
      rescue ArgumentError
        nil
      end

      private

      def normalize_requirements(requirements)
        values = Array(requirements).flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?)
        return if values.empty?

        Gem::Requirement.new(values)
      end

      def successful_response?(response)
        code = response_code(response).to_i
        code >= 200 && code < 300
      end

      def response_code(response)
        response.respond_to?(:code) ? response.code : response.fetch(:code)
      end

      def response_body(response)
        response.respond_to?(:body) ? response.body : response.fetch(:body)
      end

      def escape_path_component(value)
        URI.encode_www_form_component(value.to_s)
      end
    end

    class GemSpecReader
      DEFAULT_MINIMUM_RUBY = Gem::Version.new("1.8").freeze
      CacheState = Struct.new(:entries, :mutex)
      CACHE = CacheState.new({}, Mutex.new)
      private_constant :CacheState, :CACHE

      class << self
        def load(root)
          cache_key = File.expand_path(root.to_s)
          CACHE.mutex.synchronize do
            return CACHE.entries[cache_key] if CACHE.entries.key?(cache_key)
          end

          gemspec_path = Dir.glob(File.join(root.to_s, "*.gemspec")).first
          spec = load_gemspec(gemspec_path)
          result = metadata(root: root, gemspec_path: gemspec_path, spec: spec)

          CACHE.mutex.synchronize do
            CACHE.entries[cache_key] = result
          end
          result
        end

        def clear_cache!
          CACHE.mutex.synchronize { CACHE.entries.clear }
        end

        private

        def load_gemspec(gemspec_path)
          return unless gemspec_path && File.file?(gemspec_path)

          Gem::Specification.load(gemspec_path)
        rescue
          nil
        end

        def metadata(root:, gemspec_path:, spec:)
          gem_name = spec&.name.to_s
          gem_name = fallback_gem_name(gemspec_path) if gem_name.strip.empty?
          homepage = spec&.homepage.to_s
          forge = derive_forge(homepage)
          entrypoint_require = derive_entrypoint_require(root: root, gem_name: gem_name, spec: spec)
          namespace = entrypoint_require.to_s.split("/").reject(&:empty?).map { |segment| camelize(segment) }.join("::")

          {
            gemspec_path: gemspec_path,
            gem_name: gem_name,
            version: spec&.version.to_s,
            min_ruby: min_ruby_version(spec&.required_ruby_version),
            homepage: homepage,
            homepage_uri: spec&.metadata.to_h.fetch("homepage_uri", nil),
            source_code_uri: spec&.metadata.to_h.fetch("source_code_uri", nil),
            funding_uri: spec&.metadata.to_h.fetch("funding_uri", nil),
            gh_org: forge.fetch(:org, nil),
            forge_org: forge.fetch(:org, nil),
            gh_repo: forge.fetch(:repo, nil),
            namespace: namespace,
            namespace_shield: shield_token(namespace),
            entrypoint_require: entrypoint_require,
            gem_shield: gem_name.gsub("-", "--").gsub("_", "__"),
            authors: Array(spec&.authors).compact.uniq,
            email: Array(spec&.email).compact.uniq,
            summary: spec&.summary.to_s,
            description: spec&.description.to_s,
            licenses: Array(spec&.licenses),
            required_ruby_version: spec&.required_ruby_version,
            require_paths: Array(spec&.require_paths),
            bindir: (spec&.bindir || "").to_s,
            executables: Array(spec&.executables),
            runtime_dependencies: Array(spec&.runtime_dependencies),
            development_dependencies: Array(spec&.development_dependencies)
          }
        end

        def min_ruby_version(requirement)
          return DEFAULT_MINIMUM_RUBY unless requirement

          Gem::Requirement.parse(requirement)[1] || DEFAULT_MINIMUM_RUBY
        rescue
          DEFAULT_MINIMUM_RUBY
        end

        def fallback_gem_name(gemspec_path)
          return "" unless gemspec_path

          File.basename(gemspec_path.to_s, ".gemspec")
        end

        def shield_token(value)
          value.to_s.gsub("-", "--").gsub("_", "__").tr(" ", "_")
        end

        def derive_forge(homepage)
          uri = URI.parse(homepage.to_s)
          return {} unless uri.host.to_s.casecmp("github.com").zero?

          parts = uri.path.to_s.split("/").reject(&:empty?)
          {
            org: parts[0],
            repo: parts[1].to_s.sub(/\.git\z/, "")
          }
        rescue URI::InvalidURIError
          {}
        end

        def derive_entrypoint_require(root:, gem_name:, spec:)
          default_entrypoint = gem_name.to_s.tr("-", "/")
          return default_entrypoint if entrypoint_exists?(root, default_entrypoint)

          Array(spec&.require_paths).each do |require_path|
            lib_root = File.join(root.to_s, require_path.to_s)
            next unless Dir.exist?(lib_root)

            version_files = Dir.glob(File.join(lib_root, "**", "version.rb")).reject { |path| path.include?("/vendor/") }
            return version_files.first.sub(%r{\A#{Regexp.escape(lib_root)}/?}, "").sub(%r{/version\.rb\z}, "") if version_files.size == 1
          end

          default_entrypoint
        end

        def entrypoint_exists?(root, entrypoint_require)
          return false if entrypoint_require.to_s.strip.empty?

          File.file?(File.join(root.to_s, "lib", "#{entrypoint_require}.rb")) ||
            File.file?(File.join(root.to_s, "lib", entrypoint_require, "version.rb"))
        end

        def camelize(value)
          value.to_s.split(/[_-]/).map { |part| "#{part[0].to_s.upcase}#{part[1..]}" }.join
        end
      end
    end
    README_DEFAULT_PRESERVE_SECTIONS = ["synopsis", "configuration", "basic usage"].freeze
    README_DEFAULT_PRESERVE_PATTERNS = ["note:*"].freeze
    README_CODETRIAGE_BADGE = "[![Open Source Helpers][👽oss-helpi]][👽oss-help]"
    README_CODETRIAGE_LINK_LABELS = ["👽oss-help", "👽oss-helpi"].freeze
    README_LICENSE_EYE_WORKFLOW_BADGE = "[![Apache SkyWalking Eyes License Compatibility Check][🚎15-🪪-wfi]][🚎15-🪪-wf]"
    README_LICENSE_EYE_WORKFLOW_LINK_LABELS = ["🚎15-🪪-wf", "🚎15-🪪-wfi"].freeze
    README_FOSSA_BADGE = "[![FOSSA Status][🧪fossa-img]][🧪fossa]"
    README_FOSSA_LINK_LABELS = ["🧪fossa", "🧪fossa-img"].freeze
    LICENSE_EYE_COMPATIBILITY_LICENSES = %w[MIT].freeze
    SKYWALKING_EYES_INTEGRATION = "skywalking-eyes"
    README_OPEN_COLLECTIVE_FUNDING_BADGES = "[![OpenCollective Backers][🖇osc-backers-i]][🖇osc-backers] [![OpenCollective Sponsors][🖇osc-sponsors-i]][🖇osc-sponsors]"
    README_OPEN_COLLECTIVE_LINK_LABELS = [
      "🖇osc",
      "🖇osc-all-bottom-img",
      "🖇osc-backers",
      "🖇osc-backers-i",
      "🖇osc-backers-img",
      "🖇osc-backers-bottom-img",
      "🖇osc-sponsors",
      "🖇osc-sponsors-i",
      "🖇osc-sponsors-img",
      "🖇osc-sponsors-bottom-img"
    ].freeze
    FUNDING_YML_PLATFORMS = %w[
      buy_me_a_coffee
      community_bridge
      github
      issuehunt
      ko_fi
      liberapay
      open_collective
      patreon
      polar
      thanks_dev
      tidelift
    ].freeze
    FUNDING_README_PLATFORMS = (FUNDING_YML_PLATFORMS + ["paypal"]).freeze
    FUNDING_DEFAULT_DISABLED_PLATFORMS = %w[issuehunt patreon polar].freeze
    README_FUNDING_BADGE_POLICIES = {
      "github" => {
        badges: [
          "[![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor]",
          "[![Sponsor me on GitHub Sponsors][🖇sponsor-bottom-img]][🖇sponsor]"
        ],
        labels: ["🖇sponsor", "🖇sponsor-img", "🖇sponsor-bottom-img"]
      },
      "liberapay" => {
        badges: [
          "[![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay]",
          "[![Sponsor me on Liberapay][⛳liberapay-bottom-img]][⛳liberapay]"
        ],
        labels: ["⛳liberapay", "⛳liberapay-img", "⛳liberapay-bottom-img"]
      },
      "paypal" => {
        badges: [
          "[![Donate on PayPal][🖇paypal-img]][🖇paypal]",
          "[![Donate on PayPal][🖇paypal-bottom-img]][🖇paypal]"
        ],
        labels: ["🖇paypal", "🖇paypal-img", "🖇paypal-bottom-img"]
      },
      "buy_me_a_coffee" => {
        badges: [
          "[![Buy me a coffee][🖇buyme-small-img]][🖇buyme]"
        ],
        labels: ["🖇buyme", "🖇buyme-small-img", "🖇buyme-img"]
      },
      "ko_fi" => {
        badges: [
          "[![Donate at ko-fi.com][🖇kofi-img]][🖇kofi]",
          "[![Donate to my FLOSS efforts at ko-fi.com][🖇kofi-img]][🖇kofi]"
        ],
        labels: ["🖇kofi", "🖇kofi-img"]
      },
      "tidelift" => {
        badges: [
          "[![Get help from me on Tidelift][🏙️entsup-tidelift-img]][🏙️entsup-tidelift]"
        ],
        labels: ["🏙️entsup-tidelift", "🏙️entsup-tidelift-img"]
      }
    }.freeze
    README_INTEGRATIONS = %w[codecov coveralls qlty codeql skywalking-eyes].freeze
    README_STAR_HISTORY_MIN_STARS = 150
    README_DISCOVERED_INTEGRATIONS = (README_INTEGRATIONS - [SKYWALKING_EYES_INTEGRATION]).freeze
    COVERAGE_INTEGRATIONS = %w[codecov coveralls qlty].freeze
    MANAGED_INTEGRATIONS = (COVERAGE_INTEGRATIONS + [SKYWALKING_EYES_INTEGRATION]).freeze
    COVERAGE_INTEGRATION_CONFIG_PATHS = Ractor.make_shareable({
      "codecov" => %w[.github/.codecov.yml codecov.yml .codecov.yml],
      "coveralls" => %w[.coveralls.yml],
      "qlty" => %w[.qlty/qlty.toml .qlty.yml]
    })
    INTEGRATION_TEMPLATE_PATHS = COVERAGE_INTEGRATION_CONFIG_PATHS.merge(
      SKYWALKING_EYES_INTEGRATION => %w[.licenserc.yaml .github/workflows/license-eye.yml .github/workflows/license-eye.yaml]
    ).freeze
    README_INTEGRATION_BADGE_PATTERNS = Ractor.make_shareable({
      "codecov" => [
        /\s*\[!\[CodeCov Test Coverage\]\[[^\]]+\]\]\[[^\]]+\]/,
        /\n\[!\[Coverage Graph\]\[[^\]]+\]\]\[[^\]]+\]\n/
      ],
      "coveralls" => [
        /\s*\[!\[Coveralls Test Coverage\]\[[^\]]+\]\]\[[^\]]+\]/
      ],
      "qlty" => [
        /\s*\[!\[QLTY Test Coverage\]\[[^\]]+\]\]\[[^\]]+\]/,
        /\s*\[!\[QLTY Maintainability\]\[[^\]]+\]\]\[[^\]]+\]/
      ],
      "codeql" => [
        /\s*\[!\[CodeQL\]\[[^\]]+\]\]\[[^\]]+\]/
      ],
      "skywalking-eyes" => [
        /\s*\[!\[Apache SkyWalking Eyes License Compatibility Check\]\[[^\]]+\]\]\[[^\]]+\]/
      ]
    })
    README_INTEGRATION_LINK_LABELS = {
      "codecov" => %w[🏀codecov 🏀codecovi 🏀codecov-g],
      "coveralls" => %w[🏀coveralls 🏀coveralls-img],
      "qlty" => %w[🏀qlty-mnt 🏀qlty-mnti 🏀qlty-cov 🏀qlty-covi],
      "codeql" => %w[🖐codeQL 🖐codeQL-img],
      "skywalking-eyes" => README_LICENSE_EYE_WORKFLOW_LINK_LABELS
    }.freeze
    README_SECTION_ALIASES = {
      "summary" => "synopsis",
      "usage" => "basic usage",
      "configuration options" => "configuration",
      "setup" => "basic usage"
    }.freeze
    VAR_HOME_PREFIX = %r{\A/var/home(?=/|\z)}
    VAR_HOME_TEXT = %r{/var/home(?=/|\z)}
    FORGE_USER_ENV_KEYS = {
      gh_user: "KJ_GH_USER",
      gl_user: "KJ_GL_USER",
      cb_user: "KJ_CB_USER",
      sh_user: "KJ_SH_USER"
    }.freeze
    FUNDING_TOKEN_ENV_KEYS = {
      kofi: "KJ_FUNDING_KOFI",
      paypal: "KJ_FUNDING_PAYPAL",
      buymeacoffee: "KJ_FUNDING_BUYMEACOFFEE",
      liberapay: "KJ_FUNDING_LIBERAPAY"
    }.freeze
    SOCIAL_TOKEN_ENV_KEYS = {
      mastodon: "KJ_SOCIAL_MASTODON",
      bluesky: "KJ_SOCIAL_BLUESKY",
      linktree: "KJ_SOCIAL_LINKTREE",
      devto: "KJ_SOCIAL_DEVTO"
    }.freeze
    APACHE_LICENSE_COMPAT_CATEGORIES = {
      "Apache-2.0" => :a,
      "MIT" => :a,
      "AGPL-3.0-only" => :x,
      "PolyForm-Noncommercial-1.0.0" => :x,
      "PolyForm-Small-Business-1.0.0" => :x,
      "LicenseRef-Big-Time-Public-License" => :x
    }.freeze
    APACHE_LICENSE_COMPAT_BADGE_DATA = Ractor.make_shareable({
      a: {
        alt: "Apache license compatibility: Category A",
        label: "Apache_Compatible:_Category_A",
        message: "\u2713",
        color: "259D6C",
        ref: "https://www.apache.org/legal/resolved.html#category-a"
      },
      b: {
        alt: "Apache license compatibility: Category B",
        label: "Apache_Maybe_Compatible:_Category_B",
        message: "?",
        color: "D9A407",
        ref: "https://www.apache.org/legal/resolved.html#category-b"
      },
      x: {
        alt: "Apache license compatibility: Category X",
        label: "Apache_Incompatible:_Category_X",
        message: "\u2717",
        color: "C0392B",
        ref: "https://www.apache.org/legal/resolved.html#category-x"
      },
      unknown: {
        alt: "Apache license compatibility: Unknown",
        label: "Apache_Compatibility",
        message: "Unknown",
        color: "6C757D",
        ref: "https://www.apache.org/legal/resolved.html"
      }
    })

    class PluginRegistry
      Hook = Struct.new(:plugin_name, :phase, :timing, :callback)
      VALID_TIMINGS = %i[before after].freeze

      attr_reader :hooks, :configured_plugins, :loaded_plugins, :load_errors

      def initialize(configured_plugins: [], loaded_plugins: [])
        @hooks = []
        @configured_plugins = configured_plugins
        @loaded_plugins = loaded_plugins
        @load_errors = []
      end

      def register(plugin_name:, phase:, timing:, &callback)
        raise ArgumentError, "Plugin callbacks require a block" unless callback

        @hooks << Hook.new(
          plugin_name: plugin_name.to_s,
          phase: normalize_phase(phase),
          timing: normalize_timing(timing),
          callback: callback
        )
      end

      def run(timing:, phase:, context:, actor:, phase_stats:)
        normalized_phase = normalize_phase(phase)
        normalized_timing = normalize_timing(timing)
        hooks_for(normalized_timing, normalized_phase).each do |hook|
          hook.callback.call(
            context: context,
            actor: actor,
            phase: normalized_phase,
            phase_stats: phase_stats,
            plugin_name: hook.plugin_name
          )
        end
      end

      def empty?
        @hooks.empty?
      end

      private

      def hooks_for(timing, phase)
        @hooks.select { |hook| hook.timing == timing && hook.phase == phase }
      end

      def normalize_phase(phase)
        value = phase.to_s.strip
        raise ArgumentError, "Plugin phase cannot be blank" if value.empty?

        value.downcase.to_sym
      end

      def normalize_timing(timing)
        value = timing.to_s.strip.downcase.to_sym
        return value if VALID_TIMINGS.include?(value)

        raise ArgumentError, "Unsupported plugin timing #{timing.inspect}"
      end
    end

    class PluginRegistrar
      attr_reader :plugin_name

      def initialize(plugin_name:, registry:)
        @plugin_name = plugin_name.to_s
        @registry = registry
      end

      def on_phase(phase, timing: :after, &block)
        @registry.register(plugin_name: plugin_name, phase: phase, timing: timing, &block)
      end

      def before_phase(phase, &block)
        on_phase(phase, timing: :before, &block)
      end

      def after_phase(phase, &block)
        on_phase(phase, timing: :after, &block)
      end
    end

    module PluginLoader
      REGISTRATION_METHOD = :register_kettle_jem_plugin

      module_function

      def load!(plugin_names:)
        names = normalize_plugin_names(plugin_names)
        registry = PluginRegistry.new(configured_plugins: names, loaded_plugins: names)
        names.each { |plugin_name| load_plugin!(plugin_name, registry: registry) }
        registry
      end

      def load_plugin!(plugin_name, registry:)
        # Plugins are apply-time main-Ractor extensions; workers receive reports, not plugin callbacks.
        require(plugin_require_path(plugin_name))
        handle = plugin_handle(plugin_name)
        unless handle.respond_to?(REGISTRATION_METHOD)
          raise Error, "Plugin #{plugin_name.inspect} does not implement #{REGISTRATION_METHOD}."
        end

        handle.public_send(
          REGISTRATION_METHOD,
          PluginRegistrar.new(plugin_name: plugin_name, registry: registry)
        )
      rescue LoadError => e
        raise Error, "Could not load plugin #{plugin_name.inspect}: #{e.message}"
      end

      def normalize_plugin_names(plugin_names)
        Array(plugin_names).flatten.map { |name| name.to_s.strip }.reject(&:empty?).uniq
      end

      def plugin_require_path(plugin_name)
        plugin_name.to_s.tr("-", "/")
      end

      def plugin_handle(plugin_name)
        constant_name = plugin_name.to_s.split("-").map { |part| camelize(part) }.join("::")
        constant_name.split("::").inject(Object) { |scope, name| scope.const_get(name) }
      rescue NameError => e
        raise Error, "Could not resolve plugin handle for #{plugin_name.inspect}: #{e.message}"
      end

      def camelize(value)
        value.to_s.split("_").map(&:capitalize).join
      end
    end

    class PluginContext
      attr_reader :project_root,
        :mode,
        :facts,
        :recipe_pack,
        :recipe_reports,
        :phase_reports,
        :changed_files,
        :diagnostics,
        :helpers,
        :out

      def initialize(project_root:, mode:, facts:, recipe_pack:, recipe_reports:, changed_files:, diagnostics:, phase_reports: [])
        @project_root = project_root
        @mode = mode
        @facts = facts
        @recipe_pack = recipe_pack
        @recipe_reports = recipe_reports
        @phase_reports = phase_reports
        @changed_files = changed_files
        @diagnostics = diagnostics
        @helpers = PluginHelpers.new(project_root: project_root, changed_files: changed_files, diagnostics: diagnostics)
        @out = PluginOutput.new(diagnostics: diagnostics)
      end
    end

    class PluginHelpers
      def initialize(project_root:, changed_files:, diagnostics:)
        @project_root = project_root
        @changed_files = changed_files
        @diagnostics = diagnostics
      end

      def record_template_result(path, action)
        relative_path = relative_project_path(path)
        normalize_recorded_template_file(path, relative_path)
        @changed_files << relative_path unless @changed_files.include?(relative_path)
        @diagnostics << {
          kind: "plugin_file_change",
          path: relative_path,
          action: action.to_s
        }
      end

      private

      def normalize_recorded_template_file(path, relative_path)
        return unless relative_path == "Rakefile"

        expanded = File.expand_path(path.to_s, @project_root)
        return unless File.file?(expanded)

        content = File.read(expanded)
        normalized = Kettle::Jem.send(:normalize_generated_rakefile, content)
        File.write(expanded, normalized) unless normalized == content
      end

      def relative_project_path(path)
        expanded = File.expand_path(path.to_s, @project_root)
        root = File.expand_path(@project_root)
        expanded.start_with?("#{root}/") ? expanded.delete_prefix("#{root}/") : path.to_s
      end
    end

    class PluginOutput
      def initialize(diagnostics:)
        @diagnostics = diagnostics
      end

      def report_detail(message)
        @diagnostics << {kind: "plugin_detail", message: message.to_s}
      end

      def warning(message)
        @diagnostics << {kind: "plugin_warning", message: message.to_s}
      end
    end

    class WriteIntent
      attr_reader :relative_path, :absolute_path, :action, :content, :recipe_name, :metadata

      def initialize(relative_path:, absolute_path:, action:, content: nil, recipe_name: nil, metadata: {})
        @relative_path = relative_path.to_s
        @absolute_path = absolute_path.to_s
        @action = action.to_sym
        @content = content
        @recipe_name = recipe_name
        @metadata = metadata || {}
      end

      def delete?
        action == :delete
      end

      def write?
        action == :write
      end
    end

    class FileWorkUnit
      attr_reader :relative_path, :operations

      def initialize(relative_path:, operations:)
        @relative_path = relative_path.to_s
        @operations = Array(operations)
        raise ArgumentError, "File work unit requires at least one operation" if @operations.empty?

        mismatched_paths = @operations.reject { |operation| operation.relative_path == @relative_path }
        return if mismatched_paths.empty?

        paths = mismatched_paths.map(&:relative_path).uniq.join(", ")
        raise ArgumentError, "File work unit #{relative_path.inspect} cannot include operations for #{paths}"
      end

      def outcome
        operations.last
      end
    end

    class ChecksumMode
      VALID_TOKENS = %w[dest template ignore-dest ignore-template off].freeze
      DEFAULT = "template,ignore-dest"

      attr_reader :tokens

      def self.parse(value)
        new(value)
      end

      def initialize(value)
        raw_tokens = value.to_s.strip.empty? ? DEFAULT.split(",") : value.to_s.split(",")
        normalized = raw_tokens.map { |token| token.to_s.strip.downcase }.reject(&:empty?)
        normalized = DEFAULT.split(",") if normalized.empty?
        unknown = normalized - VALID_TOKENS
        raise ArgumentError, "unknown --checksums mode(s): #{unknown.join(", ")}" unless unknown.empty?

        if normalized.include?("off")
          raise ArgumentError, "--checksums=off cannot be combined with other checksum modes" if normalized.length > 1

          @tokens = ["off"]
          return
        end

        normalized << "template" if normalized.include?("dest") && !normalized.include?("ignore-template") && !normalized.include?("template")
        normalized << "ignore-dest" if normalized.include?("template") && !normalized.include?("dest") && !normalized.include?("ignore-dest")
        if normalized.include?("dest") && normalized.include?("ignore-dest")
          raise ArgumentError, "--checksums cannot combine dest and ignore-dest"
        end
        if normalized.include?("template") && normalized.include?("ignore-template")
          raise ArgumentError, "--checksums cannot combine template and ignore-template"
        end
        if normalized.include?("ignore-dest") && normalized.include?("ignore-template")
          raise ArgumentError, "--checksums=ignore-dest,ignore-template is equivalent to off; use --checksums=off"
        end

        @tokens = normalized.uniq
      end

      def off?
        tokens.include?("off")
      end

      def check_template?
        !off? && tokens.include?("template")
      end

      def check_destination?
        !off? && tokens.include?("dest")
      end

      def to_s
        tokens.join(",")
      end
    end

    module TemplateChecksums
      YAML_KEY = "kettle-jem"
      CHECKSUMS_SUBKEY = "checksums"
      VERSION_SUBKEY = "version"
      APPLIED_AT_SUBKEY = "applied_at"
      CHANGELOG_REPLAY_SUBKEY = "changelog_replay"
      LAST_ENTRY_KEY_SUBKEY = "last_entry_key"
      LAST_ENTRY_DATE_SUBKEY = "last_entry_date"

      module_function

      def compute(template_root:)
        root = template_root.to_s.chomp("/")
        checksums = {}
        Find.find(root) do |path|
          next unless File.file?(path)

          relative_path = path.delete_prefix("#{root}/")
          checksums[relative_path] = Digest::SHA256.file(path).hexdigest
        end
        checksums.sort.to_h
      end

      def load_stored(config_path:)
        return {} unless File.exist?(config_path.to_s)

        entry = load_state(config_path: config_path)
        stored = entry.is_a?(Hash) ? entry[CHECKSUMS_SUBKEY] : nil
        stored.is_a?(Hash) ? stored : {}
      rescue
        {}
      end

      def load_state(config_path:)
        return {} unless File.exist?(config_path.to_s)

        data = YAML.safe_load_file(config_path.to_s, permitted_classes: [], aliases: false)
        entry = data.is_a?(Hash) ? data[YAML_KEY] : nil
        entry.is_a?(Hash) ? entry : {}
      rescue
        {}
      end

      def remove_from_config(config_path:)
        return false unless File.exist?(config_path.to_s)

        content = File.read(config_path.to_s)
        range = yaml_state_node_range(content)
        return false unless range

        lines = content.to_s.lines
        updated = [*lines[0...range.begin], *lines[range.end..].to_a].join
        File.write(config_path.to_s, updated.gsub(/\n{3,}/, "\n\n"))
        true
      end

      def diff(current:, stored:)
        current_keys = current.keys.to_set
        stored_keys = stored.keys.to_set

        {
          added: (current_keys - stored_keys).sort,
          changed: (current_keys & stored_keys).select { |path| current[path] != stored[path] }.sort,
          removed: (stored_keys - current_keys).sort
        }
      end

      def diff_count(diff)
        diff.fetch(:added, []).size + diff.fetch(:changed, []).size + diff.fetch(:removed, []).size
      end

      def summary(diff)
        count = diff_count(diff)
        return "no template files changed since last run" if count.zero?

        parts = []
        parts << "#{diff.fetch(:added, []).size} added" if diff.fetch(:added, []).any?
        parts << "#{diff.fetch(:changed, []).size} changed" if diff.fetch(:changed, []).any?
        parts << "#{diff.fetch(:removed, []).size} removed" if diff.fetch(:removed, []).any?
        "#{count} template file(s) since last run: #{parts.join(", ")}"
      end

      def detail_lines(diff)
        [
          *diff.fetch(:added, []).map { |path| "  + #{path}" },
          *diff.fetch(:changed, []).map { |path| "  ~ #{path}" },
          *diff.fetch(:removed, []).map { |path| "  - #{path}" }
        ]
      end

      def build_yaml_block(checksums:, version: nil, applied_at: nil, changelog_replay: nil)
        lines = [YAML_KEY]
        lines[0] = "#{lines[0]}:"
        lines.concat(build_yaml_state_lines(checksums: checksums, version: version, applied_at: applied_at, changelog_replay: changelog_replay).map { |line| "  #{line}" })
        lines.join("\n")
      end

      def build_yaml_state(checksums:, version: nil, applied_at: nil, changelog_replay: nil)
        build_yaml_state_lines(
          checksums: checksums,
          version: version,
          applied_at: applied_at,
          changelog_replay: changelog_replay
        ).join("\n")
      end

      def build_yaml_state_lines(checksums:, version: nil, applied_at: nil, changelog_replay: nil)
        lines = []
        lines << "#{VERSION_SUBKEY}: #{version.to_s.dump}" if version
        lines << "#{APPLIED_AT_SUBKEY}: #{applied_at.to_s.dump}" if applied_at
        if changelog_replay.is_a?(Hash) && !changelog_replay.empty?
          lines << "#{CHANGELOG_REPLAY_SUBKEY}:"
          last_entry_key = changelog_replay[LAST_ENTRY_KEY_SUBKEY] || changelog_replay[:last_entry_key]
          last_entry_date = changelog_replay[LAST_ENTRY_DATE_SUBKEY] || changelog_replay[:last_entry_date]
          lines << "  #{LAST_ENTRY_KEY_SUBKEY}: #{last_entry_key.to_s.dump}" if last_entry_key
          lines << "  #{LAST_ENTRY_DATE_SUBKEY}: #{last_entry_date.to_s.dump}" if last_entry_date
        end
        lines << "#{CHECKSUMS_SUBKEY}:"
        checksums.sort.each do |path, sha|
          lines << "  #{path.dump}: #{sha.dump}"
        end
        lines
      end

      def write_to_config(config_path:, checksums:, version: nil, applied_at: nil, changelog_replay: nil)
        return unless File.exist?(config_path.to_s)

        content = File.read(config_path.to_s)
        state = build_yaml_state(
          checksums: checksums,
          version: version,
          applied_at: applied_at,
          changelog_replay: changelog_replay
        )
        updated = merge_yaml_state(content, "#{YAML_KEY}:\n#{state.lines.map { |line| "  #{line}" }.join}")
        File.write(config_path.to_s, updated)
      end

      def merge_yaml_state(content, state_block)
        range = yaml_state_node_range(content)
        return "#{content.to_s.rstrip}\n\n#{state_block}\n" unless range

        lines = content.to_s.lines
        [*lines[0...range.begin], "#{state_block}\n", *lines[range.end..].to_a].join
      end

      def yaml_state_node_range(content)
        require "yaml/merge"

        analysis = Yaml::Merge::FileAnalysis.new(content.to_s)
        raise Error, "could not parse kettle-jem config as YAML" unless analysis.valid?

        body = analysis.documents.first&.body_node
        return unless body&.mapping?

        pairs = body.mapping_pairs
        pairs.each_with_index do |pair, index|
          next unless pair.key_name == YAML_KEY

          start_index = pair.start_line.to_i - 1
          next_pair = pairs[index + 1]
          end_index = next_pair ? next_pair.start_line.to_i - 1 : [pair.end_line.to_i - 1, content.to_s.lines.length].min
          return start_index...end_index
        end

        nil
      end
    end

    module TemplateLock
      VERSION = 1
      TEMPLATE_STATE_KEY = "template_state"
      FILES_KEY = "files"

      module_function

      def path(project_root)
        File.join(project_root.to_s, KETTLE_LOCK_PATH)
      end

      def legacy_path(project_root)
        File.join(project_root.to_s, LEGACY_KETTLE_LOCK_PATH)
      end

      def load(project_root:, config_path: nil)
        lock_path = path(project_root)
        legacy_lock_path = legacy_path(project_root)
        lock = if File.exist?(lock_path)
          data = YAML.safe_load_file(lock_path, permitted_classes: [], aliases: false)
          data.is_a?(Hash) ? data : {}
        elsif File.exist?(legacy_lock_path)
          data = YAML.safe_load_file(legacy_lock_path, permitted_classes: [], aliases: false)
          data.is_a?(Hash) ? data : {}
        else
          {}
        end
        legacy = config_path ? TemplateChecksums.load_state(config_path: config_path) : {}
        merge_legacy(lock, legacy)
      rescue
        {}
      end

      def merge_legacy(lock, legacy)
        return lock unless legacy.is_a?(Hash) && !legacy.empty?

        merged = lock.dup
        state = (merged[TEMPLATE_STATE_KEY].is_a?(Hash) ? merged[TEMPLATE_STATE_KEY].dup : {})
        state["version"] ||= legacy[TemplateChecksums::VERSION_SUBKEY]
        state["applied_at"] ||= legacy[TemplateChecksums::APPLIED_AT_SUBKEY]
        state["changelog_replay"] ||= legacy[TemplateChecksums::CHANGELOG_REPLAY_SUBKEY] if legacy[TemplateChecksums::CHANGELOG_REPLAY_SUBKEY]
        state["checksums"] ||= legacy[TemplateChecksums::CHECKSUMS_SUBKEY] if legacy[TemplateChecksums::CHECKSUMS_SUBKEY]
        merged["version"] ||= VERSION
        merged[TEMPLATE_STATE_KEY] = state unless state.empty?
        merged[FILES_KEY] ||= {}
        merged
      end

      def write(project_root:, lock:)
        lock_path = path(project_root)
        FileUtils.mkdir_p(File.dirname(lock_path))
        File.write(lock_path, YAML.dump(lock).to_s)
      end

      def remove_legacy(project_root)
        legacy_lock_path = legacy_path(project_root)
        return false unless File.exist?(legacy_lock_path)

        File.delete(legacy_lock_path)
        true
      end

      def files(lock)
        value = lock.is_a?(Hash) ? lock[FILES_KEY] : nil
        value.is_a?(Hash) ? value : {}
      end

      def file_record(lock, relative_path)
        record = files(lock)[relative_path.to_s]
        record.is_a?(Hash) ? record : {}
      end

      def build_lock(template_state:, file_records:)
        {
          "version" => VERSION,
          TEMPLATE_STATE_KEY => template_state,
          FILES_KEY => file_records.sort.to_h
        }
      end
    end

    module TemplatingReport
      REPORT_DIR = File.join("tmp", "kettle-jem").freeze
      REPORT_PREFIX = "templating-report"
      MERGE_GEM_NAMES = %w[
        ast-merge
        bash-merge
        dotenv-merge
        json-merge
        markdown-merge
        markly-merge
        prism-merge
        psych-merge
        rbs-merge
        toml-merge
      ].freeze

      module_function

      def snapshot(loaded_specs: Gem.loaded_specs, workspace_root: default_workspace_root)
        {
          kettle_jem: build_entry("kettle-jem", loaded_specs["kettle-jem"], workspace_root: workspace_root),
          workspace_root: workspace_root,
          merge_gems: MERGE_GEM_NAMES.map { |name| build_entry(name, loaded_specs[name], workspace_root: workspace_root) }
        }
      end

      def build_entry(name, spec, workspace_root:)
        path = spec&.full_gem_path.to_s
        {
          name: name,
          version: spec&.version&.to_s,
          path: path.empty? ? nil : path,
          local_path: !path.empty? && local_path?(path, workspace_root: workspace_root),
          loaded: !spec.nil?
        }
      end

      def default_workspace_root
        env_root = ENV["KETTLE_DEV_DEV"].to_s.strip
        return if env_root.casecmp("false").zero?

        repo_root = File.expand_path("../../..", __dir__)
        sibling_root = File.expand_path("..", repo_root)
        if env_root.empty? || env_root.casecmp("true").zero?
          return canonical_path(sibling_root) if File.directory?(File.join(sibling_root, "nomono"))

          return
        end
        canonical_path(env_root)
      end

      def local_path?(path, workspace_root: default_workspace_root)
        return false if workspace_root.to_s.strip.empty?

        expanded_path = canonical_path(path)
        expanded_root = canonical_path(workspace_root)
        expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}/")
      end

      def canonical_path(path)
        File.realpath(path)
      rescue
        File.expand_path(path)
      end

      def console_lines(snapshot: nil, project_root: nil)
        snapshot ||= self.snapshot
        merge_gems = snapshot.fetch(:merge_gems, [])
        return [] if merge_gems.empty?

        lines = []
        kettle_jem = snapshot[:kettle_jem]
        header = "[kettle-jem] Templating merge environment"
        header += " (kettle-jem #{kettle_jem[:version]})" if kettle_jem&.dig(:version)
        lines << header
        workspace_root = snapshot[:workspace_root]
        lines << "  workspace root: #{Kettle::Jem.display_path(workspace_root)}" if workspace_root
        merge_gems.each do |entry|
          version = entry[:version] || "not loaded"
          path = entry[:path] ? " - #{Kettle::Jem.display_path(entry[:path])}" : ""
          lines << "  - #{entry[:name]} #{version} (#{source_label(entry)})#{path}"
        end
        local_workspace_warning_lines(snapshot: snapshot, project_root: project_root).each { |line| lines << "  #{line}" }
        lines
      end

      def markdown_section(snapshot: nil)
        snapshot ||= self.snapshot
        merge_gems = snapshot.fetch(:merge_gems, [])
        return "" if merge_gems.empty?

        lines = ["## Merge Gem Environment", ""]
        workspace_root = snapshot[:workspace_root]
        if workspace_root
          lines << "**Workspace root**: `#{Kettle::Jem.display_path(workspace_root)}`"
          lines << ""
        end
        lines << "| Gem | Version | Source | Path |"
        lines << "|-----|---------|--------|------|"
        merge_gems.each do |entry|
          version = entry[:version] || "_not loaded_"
          path = entry[:path] ? "`#{Kettle::Jem.display_path(entry[:path])}`" : ""
          lines << "| #{entry[:name]} | #{version} | #{source_label(entry)} | #{path} |"
        end
        lines << ""
        lines.join("\n")
      end

      def render_markdown(project_root:, output_dir: nil, snapshot: nil, run_started_at: Time.now, finished_at: nil,
        status: nil, warnings: [], error: nil, template_diff: nil, template_commit_sha: nil)
        snapshot ||= self.snapshot
        lines = ["# kettle-jem Templating Run Report", ""]
        lines << "**Started**: #{run_started_at.iso8601}"
        lines << "**Finished**: #{finished_at.iso8601}" if finished_at
        lines << "**Status**: `#{status}`" if status
        lines << "**Project root**: `#{Kettle::Jem.display_path(project_root)}`"
        lines << "**Output dir**: `#{Kettle::Jem.display_path(output_dir)}`" if output_dir
        if (kettle_jem = snapshot[:kettle_jem])
          path = kettle_jem[:path] ? " `#{Kettle::Jem.display_path(kettle_jem[:path])}`" : ""
          lines << "**kettle-jem**: #{kettle_jem[:version] || "unknown"} (#{source_label(kettle_jem)})#{path}"
        end
        if (warning = local_workspace_warning(snapshot: snapshot, project_root: project_root))
          lines << ""
          lines << local_warning_section(warning)
        end
        lines << "**Template commit**: `#{template_commit_sha}`" if template_commit_sha
        lines << ""
        lines << template_diff_section(template_diff) if template_diff
        section = markdown_section(snapshot: snapshot)
        lines << section unless section.empty?
        unique_warnings = Array(warnings).map(&:to_s).reject { |warning| warning.strip.empty? }.uniq
        if unique_warnings.any?
          lines << "## Warnings"
          lines << ""
          unique_warnings.each { |warning| lines << "- #{warning}" }
          lines << ""
        end
        if error
          lines << "## Error"
          lines << ""
          lines << "```text"
          lines << "#{error.class}: #{error.message}"
          Array(error.backtrace).first(10).each { |line| lines << line }
          lines << "```"
          lines << ""
        end
        lines.join("\n")
      end

      def report_path(project_root:, output_dir: nil, run_started_at: Time.now, pid: Process.pid)
        target_root = output_dir || project_root
        timestamp = run_started_at.utc.strftime("%Y%m%d-%H%M%S-%6N")
        File.join(target_root, REPORT_DIR, "#{REPORT_PREFIX}-#{timestamp}-#{pid}.md")
      end

      def write(project_root:, output_dir: nil, snapshot: nil, report_path: nil, run_started_at: Time.now,
        finished_at: nil, status: nil, warnings: [], error: nil, template_diff: nil, template_commit_sha: nil)
        snapshot ||= self.snapshot
        report_path ||= self.report_path(project_root: project_root, output_dir: output_dir, run_started_at: run_started_at)
        FileUtils.mkdir_p(File.dirname(report_path))
        File.write(
          report_path,
          render_markdown(
            project_root: project_root,
            output_dir: output_dir,
            snapshot: snapshot,
            run_started_at: run_started_at,
            finished_at: finished_at,
            status: status,
            warnings: warnings,
            error: error,
            template_diff: template_diff,
            template_commit_sha: template_commit_sha
          )
        )
        report_path
      end

      def source_label(entry)
        return "not loaded" unless entry[:loaded]
        return "local path" if entry[:local_path]

        "installed gem"
      end

      def local_workspace_warning_lines(snapshot:, project_root:)
        warning = local_workspace_warning(snapshot: snapshot, project_root: project_root)
        return [] unless warning

        [
          "WARNING: #{warning}",
          "Hint: set KETTLE_DEV_DEV=true (or configure it in .env.local) to use sibling workspace gems."
        ]
      end

      def local_warning_section(warning)
        <<~MARKDOWN.chomp
          ## Local Workspace Warning

          #{warning}

          Set `KETTLE_DEV_DEV=true` (or configure it in `.env.local`) to use sibling workspace gems instead of the installed release.
        MARKDOWN
      end

      def local_workspace_warning(snapshot:, project_root:)
        return if project_root.to_s.strip.empty?

        kettle_jem = snapshot[:kettle_jem]
        return unless kettle_jem&.fetch(:loaded, false)
        return if kettle_jem[:local_path]

        workspace_root = sibling_workspace_root(project_root)
        return unless workspace_root

        local_checkout = File.join(workspace_root, "kettle-jem")
        return unless File.directory?(local_checkout)

        loaded_path = canonical_path(kettle_jem[:path].to_s)
        checkout_path = canonical_path(local_checkout)
        return if loaded_path == checkout_path

        env_value = ENV.fetch("KETTLE_DEV_DEV", "<unset>")
        "Detected sibling workspace checkout at `#{Kettle::Jem.display_path(local_checkout)}`, but this run is using installed `kettle-jem` " \
          "(KETTLE_DEV_DEV=#{env_value.inspect})."
      end

      def sibling_workspace_root(project_root)
        candidate = canonical_path(File.expand_path("..", project_root))
        return unless File.directory?(File.join(candidate, "nomono"))

        candidate
      end

      def template_diff_section(diff)
        lines = ["## Template File Changes", ""]
        if Kettle::Jem::TemplateChecksums.diff_count(diff).zero?
          lines << "_No template files changed since last run._"
          lines << ""
          return lines.join("\n")
        end
        lines << Kettle::Jem::TemplateChecksums.summary(diff)
        lines << ""
        {added: "Added", changed: "Changed", removed: "Removed"}.each do |key, label|
          next unless diff.fetch(key, []).any?

          lines << "### #{label} (#{diff.fetch(key).size})"
          lines << ""
          diff.fetch(key).each { |path| lines << "- `#{path}`" }
          lines << ""
        end
        lines.join("\n")
      end
    end

    module SelfTest
      module Manifest
        module_function

        def generate(dir)
          result = {}
          dir = dir.to_s
          return result unless Dir.exist?(dir)

          Find.find(dir) do |path|
            next if File.directory?(path)

            content = File.binread(path)
            relative_path = path.sub(%r{^#{Regexp.escape(dir)}/?}, "")
            result[relative_path] = Digest::SHA256.hexdigest(content) unless relative_path.empty?
          rescue
            next
          end
          result.sort.to_h
        end

        def compare(before, after)
          all_keys = (before.keys | after.keys).sort
          result = {matched: [], changed: [], added: [], removed: []}
          all_keys.each do |key|
            before_sha = before[key]
            after_sha = after[key]
            if before_sha.nil?
              result[:added] << key
            elsif after_sha.nil?
              result[:removed] << key
            elsif before_sha == after_sha
              result[:matched] << key
            else
              result[:changed] << key
            end
          end
          result
        end
      end

      module Reporter
        module_function

        def diff(file_a, file_b)
          a = File.exist?(file_a.to_s) ? file_a.to_s : File::NULL
          b = File.exist?(file_b.to_s) ? file_b.to_s : File::NULL
          out, = Open3.capture2("diff", "-u", a, b)
          out
        rescue Errno::ENOENT
          a_lines = File.exist?(file_a.to_s) ? File.readlines(file_a) : []
          b_lines = File.exist?(file_b.to_s) ? File.readlines(file_b) : []
          return "" if a_lines == b_lines

          ["--- #{file_a}", "+++ #{file_b}", *a_lines.map { |line| "-#{line.chomp}" }, *b_lines.map { |line| "+#{line.chomp}" }].join("\n") + "\n"
        end

        def summary(comparison, output_dir:, templating_environment: nil, diff_count: nil, now: Time.now)
          matched = comparison.fetch(:matched, [])
          changed = comparison.fetch(:changed, [])
          added = comparison.fetch(:added, [])
          removed = comparison.fetch(:removed, [])
          skipped = comparison.fetch(:skipped, [])
          diff_count = changed.size if diff_count.nil?
          total = matched.size + changed.size + added.size + removed.size
          score = total.zero? ? 0.0 : (matched.size.to_f / total * 100).round(1)
          divergence = (100.0 - score).round(1)

          lines = ["# Template Self-Test Report", ""]
          lines << "**Date**: #{now.iso8601}"
          lines << "**Output**: `#{output_dir}`"
          lines << "**Score**: #{score}% (#{matched.size}/#{total} files unchanged)"
          lines << "**Divergence**: #{divergence}% (#{changed.size + added.size + removed.size}/#{total} files changed, added, or missing)"
          lines << ""
          environment_section = Kettle::Jem::TemplatingReport.markdown_section(snapshot: templating_environment) if templating_environment
          lines << environment_section if environment_section && !environment_section.empty?
          append_self_test_table(lines, "Changed Files", changed, "modified")
          append_self_test_table(lines, "New Files", added)
          if removed.any?
            lines << "## Not Templated - Unexpected (#{removed.size})"
            lines << ""
            lines << "These files exist in the source gem and appear to be within the template's"
            lines << "scope, but were not produced by the template task."
            lines << ""
            lines << "| File |"
            lines << "|------|"
            removed.each { |path| lines << "| #{path} |" }
            lines << ""
          end
          if changed.empty? && added.empty? && removed.empty?
            lines << "## All files match! :tada:"
          else
            lines << "## Detailed Diffs"
            lines << ""
            lines << if diff_count.to_i.positive?
              "See `report/diffs/` directory (#{diff_count} file#{"s" unless diff_count == 1})."
            else
              "No per-file diffs were generated for this run; `report/diffs/` is empty."
            end
          end
          append_skipped_files(lines, skipped)
          lines << ""
          lines.join("\n")
        end

        def append_self_test_table(lines, title, paths, status = nil)
          return if paths.empty?

          lines << "## #{title} (#{paths.size})"
          lines << ""
          if status
            lines << "| File | Status |"
            lines << "|------|--------|"
            paths.each { |path| lines << "| #{path} | #{status} |" }
          else
            lines << "| File |"
            lines << "|------|"
            paths.each { |path| lines << "| #{path} |" }
          end
          lines << ""
        end

        def append_skipped_files(lines, skipped)
          return if skipped.empty?

          lines << ""
          lines << '<details markdown="1">'
          lines << "<summary>Not Templated (#{skipped.size} files) - source-only files not produced by the template task</summary>"
          lines << ""
          lines << "These files are part of the gem source and are not expected to appear in the template output."
          lines << ""
          lines << "| File |"
          lines << "|------|"
          skipped.each { |path| lines << "| #{path} |" }
          lines << ""
          lines << "</details>"
        end
      end
    end

    module Tasks
    end

    module_function

    # rubocop:disable ThreadSafety/ClassInstanceVariable
    def ensure_runtime_dependencies!
      return if defined?(@runtime_dependencies_loaded) && @runtime_dependencies_loaded

      require "ruby/merge"
      require "prism/merge"
      require "bash/merge"
      require "json/merge"
      require "dotenv/merge"
      require "rbs/merge"
      require "citrus-toml-merge"
      require "psych-merge"
      require "ast/crispr/markdown/markly"
      require "ast/crispr/ruby/prism"
      @runtime_dependencies_loaded = true
    end
    # rubocop:enable ThreadSafety/ClassInstanceVariable

    def display_path(path)
      return path if path.nil?

      path.to_s.sub(VAR_HOME_PREFIX, "/home")
    end

    def display_text(text)
      return text if text.nil?

      text.to_s.gsub(VAR_HOME_TEXT, "/home")
    end

    def packaged_template_root
      PACKAGED_TEMPLATE_ROOT
    end

    def template_root_path(project_root = Dir.pwd, config: nil)
      root = File.expand_path(project_root.to_s)
      resolved_config = config || kettle_jem_config(root)
      templates = resolved_config["templates"].is_a?(Hash) ? resolved_config["templates"] : {}
      template_root(root, templates).fetch(:path)
    end

    def template_manifest(project_root: Dir.pwd, template_root: nil, config: nil)
      root = template_root || template_root_path(project_root, config: config)
      {
        kind: "kettle_jem_template_manifest",
        version: 1,
        template_root: root,
        checksums: TemplateChecksums.compute(template_root: root)
      }
    end

    def install_tasks
      # Rake task files must be reloaded for each active Rake.application.
      require "rake"
      load(File.expand_path("jem/tasks.rb", __dir__))
    end

    def appraisal_gem_abbreviation(gem_name)
      APPRAISAL_GEM_ABBREVIATIONS.fetch(gem_name.to_s, gem_name.to_s)
    end

    def appraisal_format_version(version)
      version.to_s.tr(".", "-")
    end

    def appraisal_name(tier1_gem:, tier1_version:, ruby_series:, tier2_gem: nil, tier2_version: nil)
      parts = [
        APPRAISAL_NAME_PREFIX,
        appraisal_gem_abbreviation(tier1_gem),
        appraisal_format_version(tier1_version)
      ]
      unless tier2_gem.to_s.empty?
        parts << appraisal_gem_abbreviation(tier2_gem)
        parts << appraisal_format_version(tier2_version)
      end
      parts << ruby_series.to_s
      parts.join("-")
    end

    def appraisal_modular_gemfile_path(gem_name:, version:, ruby_series:)
      File.join("gemfiles", "modular", gem_name.to_s, ruby_series.to_s, "v#{version}.gemfile")
    end

    def appraisal_modular_gemfile_content(gem_name:, version:, sub_dependencies: {})
      lines = [
        "# frozen_string_literal: true",
        "",
        "# Generated by kettle-jem",
        "",
        %(gem "#{gem_name}", "#{appraisal_version_requirement(version)}")
      ]
      sub_dependencies.each do |name, requirement|
        lines << %(gem "#{name}", "~> #{requirement}")
      end
      ensure_trailing_newline(lines.join("\n"))
    end

    def appraisal_version_requirement(version)
      segments = version.to_s.split(".")
      (segments.length >= 3) ? "~> #{version}" : "~> #{version}.0"
    end

    def appraisal_file_content(matrix_entries)
      lines = [
        "# frozen_string_literal: true",
        "",
        "# Generated by kettle-jem",
        "# Do not edit directly; regenerate from Kettle/Jem appraisal matrix metadata.",
        ""
      ]
      matrix_entries.each do |entry|
        lines << %(appraise "#{entry.fetch(:name)}" do)
        lines << %(  eval_gemfile "#{appraisal_eval_gemfile_path(entry.fetch(:tier1_gemfile))}") if entry[:tier1_gemfile]
        lines << %(  eval_gemfile "#{appraisal_eval_gemfile_path(entry.fetch(:tier2_gemfile))}") if entry[:tier2_gemfile]
        lines << %(  eval_gemfile "#{appraisal_eval_gemfile_path(entry.fetch(:x_std_libs_gemfile))}") if entry[:x_std_libs_gemfile]
        lines << "end"
        lines << ""
      end
      lines.pop while lines.last == ""
      ensure_trailing_newline(lines.join("\n"))
    end

    def appraisal_eval_gemfile_path(path)
      path.to_s.delete_prefix("gemfiles/")
    end

    def appraisal_workflow_groups(matrix_entries, bucket_ranges:, exec_cmd: "kettle-test")
      grouped = Hash.new { |hash, key| hash[key] = [] }
      normalized_ranges = bucket_ranges.transform_values do |range|
        {
          floor: Gem::Version.new((range[:floor] || range["floor"]).to_s),
          ceiling: Gem::Version.new((range[:ceiling] || range["ceiling"]).to_s)
        }
      end
      matrix_entries.each do |entry|
        ruby_series = entry[:ruby_series] || entry["ruby_series"]
        range = normalized_ranges[ruby_series]
        next unless range

        lifecycle = appraisal_workflow_lifecycle(range.fetch(:floor))
        grouped[lifecycle] << {
          ruby: appraisal_workflow_ruby(range.fetch(:floor), lifecycle),
          appraisal: entry[:name] || entry["name"],
          exec_cmd: exec_cmd,
          rubygems: "latest",
          bundler: "latest"
        }
      end
      grouped.transform_values { |entries| entries.sort_by { |entry| entry.fetch(:appraisal).to_s } }
    end

    def appraisal_workflow_yaml_snippets(matrix_entries, bucket_ranges:, exec_cmd: "kettle-test")
      appraisal_workflow_groups(matrix_entries, bucket_ranges: bucket_ranges, exec_cmd: exec_cmd).transform_values do |entries|
        lines = ["strategy:", "  matrix:", "    include:"]
        entries.each do |entry|
          lines << %(      - ruby: "#{entry.fetch(:ruby)}")
          lines << %(        appraisal: "#{entry.fetch(:appraisal)}")
          lines << %(        exec_cmd: "#{entry.fetch(:exec_cmd)}")
          lines << %(        rubygems: "#{entry.fetch(:rubygems)}")
          lines << %(        bundler: "#{entry.fetch(:bundler)}")
        end
        lines.join("\n")
      end
    end

    def appraisal_workflow_lifecycle(ruby_floor)
      APPRAISAL_WORKFLOW_LIFECYCLE_RANGES.each do |name, range|
        return name if ruby_floor.between?(range.fetch(:min), range.fetch(:max))
      end
      (ruby_floor < APPRAISAL_WORKFLOW_LIFECYCLE_RANGES.fetch("ancient").fetch(:min)) ? "ancient" : "current"
    end

    def appraisal_workflow_ruby(ruby_floor, lifecycle)
      return "ruby" if lifecycle == "current"

      segments = ruby_floor.segments
      "#{segments[0]}.#{segments[1] || 0}"
    end

    def appraisal_x_stdlib_exclusions(template_content)
      gems = ruby_call_records(template_content, :eval_gemfile).filter_map do |call|
        path = ruby_string_argument(call).to_s
        next unless path.start_with?("../")

        path.delete_prefix("../").split("/").first
      end
      (gems + APPRAISAL_ALWAYS_EXCLUDED_GEMS).uniq.sort
    end

    def appraisal_select_versions(version_metadata, mode:, requirements: nil)
      mode = mode.to_s
      raise ArgumentError, "invalid appraisal version selection mode: #{mode}" unless APPRAISAL_VERSION_SELECTION_MODES.include?(mode)

      versions = appraisal_filtered_versions(version_metadata, requirements: requirements)
      return versions if mode == "patch"

      by_major = appraisal_minor_versions_by_major(versions)
      return [] if by_major.empty?

      current_major = by_major.last.fetch(:major)
      case mode
      when "major"
        by_major.map { |entry| entry.fetch(:minors).last }
      when "minor"
        by_major.flat_map { |entry| entry.fetch(:minors) }
      when "minor-minmax"
        by_major.flat_map do |entry|
          minors = entry.fetch(:minors)
          (entry.fetch(:major) < current_major) ? [minors.first, minors.last].uniq : minors
        end
      when "semver"
        by_major.flat_map do |entry|
          (entry.fetch(:major) < current_major) ? [entry.fetch(:minors).last] : entry.fetch(:minors)
        end
      end
    end

    def appraisal_matrix_entries(tier1_gems:, tier2_gems: [])
      entries = []
      tier1_gems.each do |tier1|
        tier1_name = tier1[:name] || tier1["name"]
        assignments = tier1[:assignments] || tier1["assignments"] || []
        assignments.each do |assignment|
          tier1_version = assignment[:version] || assignment["version"]
          ruby_series = assignment[:bucket] || assignment["bucket"] || assignment[:ruby_series] || assignment["ruby_series"]
          if tier2_gems.empty?
            entries << appraisal_matrix_entry(
              tier1_name: tier1_name,
              tier1_version: tier1_version,
              ruby_series: ruby_series
            )
          else
            tier2_gems.each do |tier2|
              tier2_name = tier2[:name] || tier2["name"]
              Array(tier2[:versions] || tier2["versions"]).each do |tier2_version|
                entries << appraisal_matrix_entry(
                  tier1_name: tier1_name,
                  tier1_version: tier1_version,
                  ruby_series: ruby_series,
                  tier2_name: tier2_name,
                  tier2_version: tier2_version
                )
              end
            end
          end
        end
      end
      entries
    end

    def appraisal_matrix_entry(tier1_name:, tier1_version:, ruby_series:, tier2_name: nil, tier2_version: nil)
      {
        name: appraisal_name(
          tier1_gem: tier1_name,
          tier1_version: tier1_version,
          tier2_gem: tier2_name,
          tier2_version: tier2_version,
          ruby_series: ruby_series
        ),
        tier1_gemfile: appraisal_modular_gemfile_path(gem_name: tier1_name, version: tier1_version, ruby_series: ruby_series),
        tier2_gemfile: tier2_name ? appraisal_modular_gemfile_path(gem_name: tier2_name, version: tier2_version, ruby_series: ruby_series) : nil,
        x_std_libs_gemfile: File.join("gemfiles", "modular", "x_std_libs", ruby_series.to_s, "libs.gemfile"),
        ruby_series: ruby_series.to_s
      }
    end

    def appraisal_filtered_versions(version_metadata, requirements:)
      requirement = requirements ? Gem::Requirement.new(Array(requirements)) : nil
      version_metadata.filter_map do |entry|
        number = entry[:number] || entry["number"]
        next if number.to_s.empty?
        next if entry[:prerelease] || entry["prerelease"]
        next if requirement && !requirement.satisfied_by?(Gem::Version.new(number))

        number.to_s
      end.sort_by { |version| Gem::Version.new(version) }
    end

    def appraisal_minor_versions_by_major(versions)
      versions.map do |version|
        gem_version = Gem::Version.new(version)
        segments = gem_version.segments
        {
          major: segments[0],
          minor: "#{segments[0]}.#{segments[1] || 0}"
        }
      end.uniq.group_by { |entry| entry.fetch(:major) }.map do |major, entries|
        {
          major: major,
          minors: entries.map { |entry| entry.fetch(:minor) }.sort_by { |minor| Gem::Version.new(minor) }
        }
      end.sort_by { |entry| entry.fetch(:major) }
    end

    def appraisal_find_ruby_seams(version_metadata)
      minors = appraisal_latest_patch_by_minor(version_metadata)
      seams = []
      previous = nil
      minors.sort_by { |minor, _entry| Gem::Version.new(minor) }.each do |minor, entry|
        min_ruby = Gem::Version.new((entry[:min_ruby] || entry["min_ruby"]).to_s)
        min_ruby = [min_ruby, DEFAULT_TEST_MINIMUM_RUBY].max
        if previous.nil? || min_ruby > previous
          seams << {version: minor, min_ruby: min_ruby}
        end
        previous = min_ruby
      end
      seams
    end

    def appraisal_ruby_series(version_metadata, project_min_ruby: nil)
      floors = appraisal_find_ruby_seams(version_metadata).map { |seam| seam.fetch(:min_ruby) }
      if project_min_ruby
        floor = Gem::Version.new(project_min_ruby.to_s)
        floors.reject! { |version| version < floor }
        floors << floor unless floors.include?(floor)
      end
      floors = [Gem::Version.new("3.2")] if floors.empty?
      appraisal_minor_versions_to_buckets(floors.map { |version| appraisal_minor_key(version) }.uniq.sort)
    end

    def appraisal_assign_version_buckets(selected_versions:, seams:, buckets:, bucket_ranges:, all_versions:)
      return [] if selected_versions.empty? || buckets.empty?

      normalized_ranges = appraisal_normalized_bucket_ranges(bucket_ranges)
      version_min_rubies = appraisal_version_min_ruby_map(all_versions, seams)
      assignments = selected_versions.sort_by { |version| Gem::Version.new(version) }.filter_map do |version|
        min_ruby = version_min_rubies[version]
        next unless min_ruby

        next_seam = appraisal_next_seam_ruby(version, min_ruby, all_versions, version_min_rubies)
        bucket = next_seam ? appraisal_bucket_below(next_seam, buckets, normalized_ranges) : buckets.last
        {version: version, bucket: bucket} if bucket
      end
      appraisal_fill_bucket_gaps(assignments, buckets, normalized_ranges, version_min_rubies, all_versions)
    end

    def appraisal_latest_patch_by_minor(version_metadata)
      version_metadata.each_with_object({}) do |entry, latest|
        number = (entry[:number] || entry["number"]).to_s
        next if number.empty?

        version = Gem::Version.new(number)
        minor = "#{version.segments[0]}.#{version.segments[1] || 0}"
        current = latest[minor]
        latest[minor] = entry if current.nil? || version > Gem::Version.new((current[:number] || current["number"]).to_s)
      end
    end

    def appraisal_minor_versions_to_buckets(minor_versions)
      by_major = minor_versions.group_by { |minor| minor.split(".").first.to_i }
      buckets = []
      ranges = {}
      by_major.each do |major, minors|
        sorted = minors.sort_by { |minor| Gem::Version.new(minor) }
        sorted.each_with_index do |minor, index|
          bucket = (index == sorted.length - 1) ? "r#{major}" : "r#{major}.#{[sorted[index + 1].split(".").last.to_i - 1, minor.split(".").last.to_i].max}"
          next if ranges.key?(bucket)

          buckets << bucket
          ceiling = if index == sorted.length - 1
            "#{major}.99"
          else
            bucket.split(".").last ? "#{major}.#{bucket.split(".").last}" : "#{major}.99"
          end
          ranges[bucket] = {floor: Gem::Version.new(minor), ceiling: Gem::Version.new(ceiling)}
        end
      end
      {buckets: buckets.sort_by { |bucket| appraisal_bucket_sort_key(bucket) }, bucket_ranges: ranges}
    end

    def appraisal_minor_key(version)
      segments = Gem::Version.new(version.to_s).segments
      "#{segments[0]}.#{segments[1] || 0}"
    end

    def appraisal_bucket_sort_key(bucket)
      match = bucket.to_s.match(/\Ar(\d+)(?:\.(\d+))?\z/)
      [match[1].to_i, match[2] ? match[2].to_i : 999]
    end

    def appraisal_normalized_bucket_ranges(bucket_ranges)
      bucket_ranges.transform_values do |range|
        {
          floor: Gem::Version.new((range[:floor] || range["floor"]).to_s),
          ceiling: Gem::Version.new((range[:ceiling] || range["ceiling"]).to_s)
        }
      end
    end

    def appraisal_version_min_ruby_map(all_versions, seams)
      sorted_seams = seams.sort_by { |seam| Gem::Version.new(seam[:version] || seam["version"]) }
      seam_index = 0
      current = nil
      all_versions.sort_by { |version| Gem::Version.new(version) }.each_with_object({}) do |version, map|
        while seam_index < sorted_seams.length && Gem::Version.new(sorted_seams[seam_index][:version] || sorted_seams[seam_index]["version"]) <= Gem::Version.new(version)
          current = Gem::Version.new((sorted_seams[seam_index][:min_ruby] || sorted_seams[seam_index]["min_ruby"]).to_s)
          current = [current, DEFAULT_TEST_MINIMUM_RUBY].max
          seam_index += 1
        end
        map[version] = current if current
      end
    end

    def appraisal_next_seam_ruby(version, min_ruby, all_versions, version_min_rubies)
      found = false
      all_versions.sort_by { |candidate| Gem::Version.new(candidate) }.each do |candidate|
        found ||= Gem::Version.new(candidate) >= Gem::Version.new(version)
        next unless found

        candidate_ruby = version_min_rubies[candidate]
        return candidate_ruby if candidate_ruby && candidate_ruby > min_ruby
      end
      nil
    end

    def appraisal_bucket_below(ruby_floor, buckets, bucket_ranges)
      buckets.filter_map do |bucket|
        range = bucket_ranges[bucket]
        next unless range && range.fetch(:ceiling) < ruby_floor

        [bucket, range.fetch(:ceiling)]
      end.max_by(&:last)&.first
    end

    def appraisal_fill_bucket_gaps(assignments, buckets, bucket_ranges, version_min_rubies, all_versions)
      covered = assignments.map { |assignment| assignment.fetch(:bucket) }
      (buckets - covered).each do |bucket|
        range = bucket_ranges[bucket]
        next unless range

        filler = all_versions.sort_by { |version| Gem::Version.new(version) }.reverse.find do |version|
          ruby = version_min_rubies[version]
          ruby&.between?(range.fetch(:floor), range.fetch(:ceiling))
        end
        filler ||= all_versions.sort_by { |version| Gem::Version.new(version) }.reverse.find do |version|
          ruby = version_min_rubies[version]
          ruby && ruby <= range.fetch(:ceiling)
        end
        assignments << {version: filler, bucket: bucket, filler: true} if filler
      end
      assignments.sort_by { |assignment| bucket_ranges.fetch(assignment.fetch(:bucket)).fetch(:floor) }
    end

    def appraisal_resolve_sub_dependencies(parent_gem:, parent_version:, parent_versions:, dependency_versions:, ruby_min: nil, excluded_gems: [])
      parent = appraisal_latest_version_matching(parent_versions, parent_version)
      return {} unless parent

      ruby_floor = Gem::Version.new(ruby_min.to_s) unless ruby_min.to_s.empty?
      excluded = excluded_gems.map(&:to_s)
      Array(parent[:runtime_dependencies] || parent["runtime_dependencies"]).each_with_object({}) do |dependency, resolved|
        name = (dependency[:name] || dependency["name"]).to_s
        next if name.empty? || excluded.include?(name)

        requirement = begin
          Gem::Requirement.new(dependency[:requirements] || dependency["requirements"] || ">= 0")
        rescue ArgumentError
          Gem::Requirement.default
        end
        selected = appraisal_select_dependency_version(
          Array(dependency_versions[name] || dependency_versions[name.to_sym]),
          requirement: requirement,
          ruby_min: ruby_floor
        )
        resolved[name] = selected if selected
      end
    end

    def appraisal_latest_version_matching(version_metadata, requested_version)
      prefix = "#{requested_version}."
      version_metadata.select do |entry|
        number = (entry[:number] || entry["number"]).to_s
        number == requested_version.to_s || number.start_with?(prefix)
      end.max_by { |entry| Gem::Version.new((entry[:number] || entry["number"]).to_s) }
    end

    def appraisal_select_dependency_version(version_metadata, requirement:, ruby_min:)
      compatible = version_metadata.select do |entry|
        number = (entry[:number] || entry["number"]).to_s
        !number.empty? && requirement.satisfied_by?(Gem::Version.new(number))
      end.sort_by { |entry| Gem::Version.new((entry[:number] || entry["number"]).to_s) }
      return if compatible.empty?

      if ruby_min
        selected = compatible.reverse.find do |entry|
          min_ruby = entry[:min_ruby] || entry["min_ruby"]
          min_ruby.to_s.empty? || Gem::Version.new(min_ruby.to_s) <= ruby_min
        end
        return (selected || compatible.first).then { |entry| entry[:number] || entry["number"] }
      end
      compatible.last.then { |entry| entry[:number] || entry["number"] }
    end

    def appraisal_stale_gemfile_paths(existing_paths:, current_entries:)
      current_names = current_entries.map { |entry| (entry[:name] || entry["name"]).to_s }.to_set
      existing_paths.map(&:to_s).select do |path|
        basename = File.basename(path, ".gemfile")
        path.start_with?("gemfiles/#{APPRAISAL_NAME_PREFIX}-") &&
          path.end_with?(".gemfile") &&
          !current_names.include?(basename)
      end.sort
    end

    def appraisal_extract_runtime_dependencies(gemspec_content)
      gemspec_dependency_records(gemspec_content)
        .reject { |record| record.fetch(:kind) == "add_development_dependency" }
        .map { |record| record.fetch(:name) }
        .uniq
    end

    def appraisal_scaffold_config(gemspec_content:, existing_config: {}, exclusions: [], default_mode: "semver", freshness_ttl: APPRAISAL_DEFAULT_FRESHNESS_TTL)
      excluded = exclusions.map(&:to_s).to_set
      runtime_dependencies = appraisal_extract_runtime_dependencies(gemspec_content)
      tier1 = runtime_dependencies.reject { |name| excluded.include?(name) }.map { |name| {"name" => name} }
      config = deep_string_key_hash(existing_config)
      matrix = config["appraisal_matrix"] || {}
      gems = matrix["gems"] || {}

      matrix["mode"] ||= default_mode
      matrix["freshness_ttl"] ||= freshness_ttl
      gems["tier1"] = tier1
      gems["tier2"] ||= []
      matrix["gems"] = gems
      config["appraisal_matrix"] = matrix
      config
    end

    def appraisal_matrix_has_versions?(matrix)
      gems = deep_string_key_hash(matrix || {}).fetch("gems", {})
      %w[tier1 tier2].any? do |tier|
        Array(gems[tier]).any? { |gem_config| Array(gem_config["versions"]).any? }
      end
    end

    def appraisal_matrix_fresh?(matrix, now: Time.now.to_i)
      resolved_at = (matrix || {})[:resolved_at] || (matrix || {})["resolved_at"]
      return false unless resolved_at

      ttl = (matrix || {})[:freshness_ttl] || (matrix || {})["freshness_ttl"] || APPRAISAL_DEFAULT_FRESHNESS_TTL
      (now.to_i - resolved_at.to_i) < ttl.to_i
    end

    def appraisal_time_ago(timestamp, now: Time.now.to_i)
      return "unknown" unless timestamp

      seconds = now.to_i - timestamp.to_i
      return "#{seconds / 60}m" if seconds < 3600
      return "#{seconds / 3600}h" if seconds < 86_400

      "#{seconds / 86_400}d"
    end

    def appraisal_all_versions_for(resolver:, gem_name:, mode:, requirements: nil, include_versions: nil, exclude_versions: nil)
      base_versions = if mode.to_s == "patch"
        resolver.versions(gem_name, requirements: requirements).map { |entry| entry[:number] || entry["number"] }
      else
        resolver.minor_versions_by_major(gem_name, requirements: requirements).flat_map { |entry| entry[:minors] || entry["minors"] }
      end
      appraisal_finalize_versions(base_versions, include_versions: include_versions, exclude_versions: exclude_versions)
    end

    def appraisal_finalize_versions(base_versions, include_versions: nil, exclude_versions: nil)
      merged = appraisal_sort_versions(Array(base_versions) + Array(include_versions))
      excluded = Array(exclude_versions).map(&:to_s).to_set
      return merged if excluded.empty?

      appraisal_sort_versions(merged.reject { |version| excluded.include?(version) })
    end

    def appraisal_compatible_version_for_bucket?(resolver:, gem_name:, version:, ruby_series:, bucket_ranges:)
      range = bucket_ranges[ruby_series] || bucket_ranges[ruby_series.to_s]
      return true unless range

      ceiling = Gem::Version.new((range[:ceiling] || range["ceiling"]).to_s)
      exact_version = appraisal_latest_minor_patch(resolver: resolver, gem_name: gem_name, version: version)
      min_ruby = resolver.min_ruby_version(gem_name, exact_version)
      min_ruby.nil? || Gem::Version.new(min_ruby.to_s) <= ceiling
    rescue
      true
    end

    def appraisal_latest_minor_patch(resolver:, gem_name:, version:)
      all_versions = resolver.versions(gem_name)
      prefix = "#{version}."
      matching = all_versions.select do |entry|
        number = (entry[:number] || entry["number"]).to_s
        number == version.to_s || number.start_with?(prefix)
      end
      return version.to_s if matching.empty?

      latest = matching.max_by { |entry| Gem::Version.new((entry[:number] || entry["number"]).to_s) }
      (latest[:number] || latest["number"]).to_s
    end

    def appraisal_sort_versions(values)
      values.compact.map(&:to_s).reject(&:empty?).uniq.sort_by { |version| Gem::Version.new(version) }
    end

    def deep_string_key_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), converted|
          converted[key.to_s] = deep_string_key_hash(child)
        end
      when Array
        value.map { |child| deep_string_key_hash(child) }
      else
        value
      end
    end

    def ruby_style_facts(project_root)
      config_path = File.join(project_root.to_s, ".rubocop.yml")
      config = if File.file?(config_path)
        YAML.safe_load_file(config_path, permitted_classes: [], aliases: true) || {}
      else
        {}
      end
      config = {} unless config.is_a?(Hash)
      dot_position = config.dig("Layout/DotPosition", "EnforcedStyle").to_s
      dot_position = if dot_position == "trailing"
        "trailing"
      else
        "leading"
      end

      {
        dot_position: dot_position,
        trailing_array_comma: config.dig("Style/TrailingCommaInArrayLiteral", "EnforcedStyleForMultiline").to_s == "comma"
      }
    rescue Psych::Exception
      {dot_position: "leading", trailing_array_comma: false}
    end

    def discover_monorepo_root_facts(project_root, kettle_config, env, template_selection)
      source_url = git_remote_source_url(project_root)
      package_name = repository_name_from_source_url(source_url)
      package_name = File.basename(project_root.to_s) if package_name.empty?
      configured_or_detected_licenses = detected_license_ids(project_root)
      configured_or_detected_licenses = Array(kettle_config["licenses"]) if configured_or_detected_licenses.empty?
      copyright = copyright_facts(project_root, kettle_config)
      author = author_facts(kettle_config, env, copyright: copyright)
      license = license_facts(
        kettle_config.merge("licenses" => configured_or_detected_licenses),
        configured_or_detected_licenses,
        author: author,
        author_email: author[:email],
        copyright: copyright,
        source_url: source_url,
        license_txt: license_txt_facts(project_root)
      )
      test_min_ruby = config_test_min_ruby(kettle_config, nil)
      project_runtime = project_runtime_facts(
        kettle_config,
        env,
        package_name: package_name,
        source_url: source_url,
        author_domain: author[:domain],
        min_ruby: nil,
        test_min_ruby: test_min_ruby,
        version: nil,
        project_root: project_root
      )
      facts = {
        package: compact_hash(
          ecosystem: "monorepo",
          name: package_name,
          slug: package_name,
          description: "#{package_name} monorepo",
          homepage_url: source_url,
          source_url: source_url,
          license_expression: license[:expression]
        ),
        rubygems: compact_hash(
          namespace: classify_namespace(package_name),
          min_ruby: nil,
          engines: ruby_engines_config(kettle_config)
        ),
        template_profile: MONOREPO_ROOT_TEMPLATE_PROFILE
      }
      bootstrap = kettle_config_bootstrap_facts(project_root, env, template_selection: template_selection)
      bootstrap[:licenses] = configured_or_detected_licenses if bootstrap && !configured_or_detected_licenses.empty?
      facts[:kettle_config_bootstrap] = bootstrap if bootstrap
      facts[:author] = author unless author.empty?
      facts[:copyright] = copyright unless copyright.empty?
      forge = forge_facts(kettle_config, env, derived_github_user: nil)
      social = social_facts(kettle_config, env)
      facts[:forge] = forge unless forge.empty?
      facts[:social] = social unless social.empty?
      facts[:license] = license unless license.empty?
      facts[:project_runtime] = project_runtime unless project_runtime.empty?
      facts[:ruby_style] = ruby_style_facts(project_root)
      opencollective_policy = opencollective_policy(kettle_config, env)
      opencollective_disabled = opencollective_policy.fetch(:disabled)
      funding_platforms = funding_platform_policies(kettle_config, env)
      detected_open_collective_org = opencollective_org(project_root, kettle_config, env, opencollective_disabled: opencollective_disabled)
      detected_open_collective_org ||= fallback_opencollective_org unless opencollective_disabled
      funding = compact_hash(
        urls: funding_urls(
          project_root,
          package_name,
          opencollective_disabled: opencollective_disabled,
          open_collective_org: detected_open_collective_org && detected_open_collective_org.fetch(:org),
          enabled_platforms: funding_platforms
        ),
        platform_tokens: funding_platform_token_facts(kettle_config, env),
        platforms: funding_platforms
      )
      funding[:open_collective_disabled] = true if opencollective_disabled
      funding[:open_collective_disabled_source] = opencollective_policy[:source] if opencollective_disabled
      if detected_open_collective_org
        funding[:open_collective_org] = detected_open_collective_org.fetch(:org)
        funding[:open_collective_org_source] = detected_open_collective_org.fetch(:source)
      end
      facts[:funding] = funding unless funding.empty?
      repository = repository_facts(
        project_root,
        source_url,
        package_name: package_name,
        repository_topology: REPOSITORY_TOPOLOGY_STANDALONE
      )
      facts[:repository] = repository unless repository.empty?
      warnings = opencollective_fallback_warnings(funding, github_org_from_url(source_url).to_s)
      facts[:warnings] = warnings unless warnings.empty?
      readme_logo = readme_logo_facts(
        kettle_config,
        package_name: package_name,
        github_org: project_runtime[:github_org],
        repository: facts[:repository]
      )
      facts[:readme_logo] = readme_logo unless readme_logo.empty?
      readme_sponsors = readme_corporate_sponsors_facts(kettle_config, env)
      facts[:readme_sponsors] = readme_sponsors unless readme_sponsors.empty?
      disabled_integrations = disabled_integrations(kettle_config, license: license)
      facts[:integrations] = {disabled: disabled_integrations} unless disabled_integrations.empty?
      template_facts = {}
      template_config = template_runtime_config(kettle_config, facts, license: license)
      template_preferences = template_source_preferences(
        project_root,
        template_config,
        opencollective_disabled: opencollective_disabled,
        include_patterns: template_selection[:include]
      )
      template_preferences += existing_simplecov_bootstrap_template_preferences(
        project_root,
        template_config,
        template_preferences
      )
      template_facts[:source_preferences] = template_preferences unless template_preferences.empty?
      template_tokens = template_tokens(facts, funding)
      template_facts[:tokens] = template_tokens unless template_tokens.empty?
      facts[:templates] = template_facts unless template_facts.empty?
      facts
    end

    def discover_facts(project_root, env: ENV, run_options: {})
      kettle_config = kettle_jem_config(project_root)
      template_selection = template_selection_for(env, run_options)
      configured_template_profile = normalize_template_profile(kettle_config.dig("templates", "profile"))
      if template_selection[:template_profile].to_s.empty? && !configured_template_profile.empty?
        template_selection[:template_profile] = configured_template_profile
      end
      gemspec_path = Dir.glob(File.join(project_root, "*.gemspec")).min
      if !gemspec_path && template_selection[:template_profile].to_s == MONOREPO_ROOT_TEMPLATE_PROFILE
        return discover_monorepo_root_facts(project_root, kettle_config, env, template_selection)
      end
      raise ArgumentError, "no gemspec found in #{project_root}" unless gemspec_path

      gemspec_spec = load_project_gemspec(gemspec_path)
      gemspec_metadata = project_gemspec_metadata(project_root, gemspec_path, spec: gemspec_spec)
      rubygems_config = kettle_config["rubygems"].is_a?(Hash) ? kettle_config["rubygems"] : {}
      configured_name = rubygems_config["name"].to_s.strip
      name = (configured_name.empty? ? nil : configured_name) ||
        metadata_value(gemspec_metadata, :gem_name) ||
        File.basename(gemspec_path, ".gemspec")
      homepage_url = metadata_value(gemspec_metadata, :homepage)
      metadata_source_url = metadata_value(gemspec_metadata, :source_code_uri)
      metadata_source_url = nil if generated_version_tree_source_url?(metadata_source_url, metadata_value(gemspec_metadata, :version))
      metadata_github_url = concrete_github_url(metadata_source_url)
      homepage_github_url = concrete_github_url(homepage_url)
      git_source_url = git_remote_source_url(project_root)
      git_github_url = concrete_github_url(git_source_url)
      source_url = if template_selection[:template_profile].to_s == SHIM_TEMPLATE_PROFILE
        git_github_url || git_source_url || metadata_github_url || homepage_github_url || metadata_source_url || homepage_url
      else
        metadata_github_url ||
          git_github_url ||
          homepage_github_url ||
          metadata_source_url ||
          git_source_url ||
          homepage_url
      end
      if homepage_github_url && git_github_url && homepage_github_url != git_github_url && source_url == git_github_url
        homepage_url = git_github_url
      end
      derived_github_user = (git_github_url && source_url == git_github_url) ? github_org_from_url(git_github_url) : nil
      entrypoint_require = rubygems_config["entrypoint_require"].to_s.strip
      entrypoint_require = metadata_value(gemspec_metadata, :entrypoint_require) if entrypoint_require.empty?
      entrypoint_require = name.tr("-", "/") if entrypoint_require.to_s.empty?
      version_path = File.join("lib", entrypoint_require, "version.rb")
      entrypoint_path = File.join("lib", "#{entrypoint_require}.rb")
      configured_namespace = rubygems_config["namespace"].to_s.strip
      version_namespace = existing_version_namespace(project_root, version_path)
      version_namespace = reconcile_existing_version_namespace(
        project_root,
        entrypoint_path,
        version_path,
        version_namespace
      )
      metadata_namespace = metadata_value(gemspec_metadata, :namespace)
      default_namespace = classify_namespace(name)
      namespace_hint = configured_namespace.empty? ? default_namespace : configured_namespace
      entrypoint_namespace = existing_entrypoint_version_namespace(
        project_root,
        entrypoint_path,
        expected_depth: namespace_hint.split("::").count { |segment| !segment.empty? }
      )
      namespace = configured_namespace.empty? ? nil : configured_namespace
      namespace ||= project_namespace(
        entrypoint_namespace: entrypoint_namespace,
        version_namespace: version_namespace,
        metadata_namespace: metadata_namespace,
        default_namespace: default_namespace
      )
      version_namespace_kinds = existing_version_namespace_kinds(
        project_root,
        version_path,
        namespace,
        entrypoint_path: entrypoint_path
      )
      version_namespace_superclasses = existing_version_namespace_superclasses(
        project_root,
        version_path,
        namespace
      )
      namespace_superclass_details = existing_namespace_superclass_details(
        project_root,
        namespace,
        preferred_path: entrypoint_path
      )
      entrypoint_namespace_superclasses = namespace_superclass_details.fetch(:superclasses)
      project_version = metadata_value(gemspec_metadata, :version)
      project_version = existing_version_file_value(project_root, version_path) unless valid_gem_version?(project_version)
      project_version = git_version_file_value(project_root, version_path) unless valid_gem_version?(project_version)
      configured_min_ruby = preferred_template_token_value(nil, rubygems_config["min_ruby"], env, "KJ_MIN_RUBY").to_s.strip
      min_ruby = (configured_min_ruby.empty? ? nil : configured_min_ruby) ||
        metadata_value(gemspec_metadata, :required_ruby_version) ||
        metadata_value(gemspec_metadata, :min_ruby)
      gemspec_licenses = Array(gemspec_metadata[:licenses])

      copyright = copyright_facts(project_root, kettle_config)
      license_txt = license_txt_facts(project_root)
      author = author_facts(kettle_config, env, gemspec_metadata: gemspec_metadata, copyright: copyright)
      license = license_facts(
        kettle_config,
        gemspec_licenses,
        author: author,
        author_email: author[:email],
        copyright: copyright,
        source_url: source_url,
        license_txt: license_txt
      )
      gemspec_license_spdx = gemspec_licenses
        .map { |license_id| license_id.to_s.strip }
        .reject(&:empty?)
      repository_topology = repository_topology_for(kettle_config, env, template_selection)
      repository = repository_facts(
        project_root,
        source_url,
        package_name: name,
        repository_topology: repository_topology
      )
      project_runtime = project_runtime_facts(
        kettle_config,
        env,
        package_name: name,
        source_url: source_url,
        author_domain: author[:domain],
        min_ruby: min_ruby,
        test_min_ruby: config_test_min_ruby(kettle_config, min_ruby),
        version: project_version,
        project_root: project_root,
        gemspec_metadata: gemspec_metadata,
        repository: repository
      )
      rubyforum = rubyforum_facts(kettle_config, env, package_name: name)
      shim = shim_facts(
        kettle_config,
        env,
        run_options,
        package_name: name,
        entrypoint_require: entrypoint_require,
        template_profile: template_selection[:template_profile]
      )
      facts = {
        package: compact_hash(
          ecosystem: "rubygems",
          name: name,
          slug: name,
          summary: metadata_value(gemspec_metadata, :summary),
          description: metadata_value(gemspec_metadata, :description) ||
            metadata_value(gemspec_metadata, :summary),
          homepage_url: homepage_url,
          source_url: source_url,
          license_expression: license[:expression],
          runtime_dependencies: gemspec_runtime_dependency_names(gemspec_metadata)
        ),
        rubygems: compact_hash(
          gemspec_path: File.basename(gemspec_path),
          entrypoint_require: entrypoint_require,
          namespace: namespace,
          min_ruby: min_ruby,
          version_namespace_kinds: version_namespace_kinds,
          version_namespace_superclasses: version_namespace_superclasses,
          entrypoint_namespace_superclasses: entrypoint_namespace_superclasses,
          entrypoint_namespace_superclass_path: namespace_superclass_details[:path],
          version_gem_default_enabled: version_gem_default_enabled_for_project?(rubygems_config, gemspec_metadata),
          engines: ruby_engines_config(kettle_config)
        )
      }
      facts[:rubyforum] = rubyforum unless rubyforum.empty?
      version_gem_facts = version_gem_facts_for_project(
        project_root,
        entrypoint_require,
        mode: rubygems_version_gem_entrypoint_mode(rubygems_config)
      )
      facts[:version_gem] = version_gem_facts unless version_gem_facts.empty?
      facts[:shim] = shim unless shim.empty?
      facts[:repository] = repository unless repository.empty?
      generated_blocks = generated_blocks_facts(gemspec_metadata, facts.merge(project_root: File.expand_path(project_root)), run_options)
      facts[:generated_blocks] = generated_blocks unless generated_blocks.empty?
      bootstrap = kettle_config_bootstrap_facts(project_root, env, template_selection: template_selection)
      if bootstrap
        min_ruby_token = minimum_ruby_token(min_ruby)
        bootstrap[:licenses] = gemspec_license_spdx unless gemspec_license_spdx.empty?
        bootstrap[:gemspec_path] = File.basename(gemspec_path) if gemspec_path
        bootstrap[:min_ruby] = min_ruby_token unless min_ruby_token.empty?
        bootstrap[:test_min_ruby] = config_test_min_ruby(kettle_config, min_ruby).to_s
        bootstrap[:yard_host] = project_runtime[:yard_host].to_s
        bootstrap[:homepage_uri] = project_runtime[:homepage_uri].to_s
        bootstrap[:rubyforum] = rubyforum if rubyforum && !rubyforum.empty?
        project_emoji = preferred_template_token_value(nil, nil, env, "KJ_PROJECT_EMOJI")
        project_emoji ||= readme_project_emoji(project_root)
        project_emoji ||= gemspec_project_emoji(gemspec_metadata)
        project_emoji ||= "💎" if monorepo_subgem_template_profile_value?(template_selection[:template_profile])
        project_emoji ||= "🪞" if template_selection[:template_profile].to_s == SHIM_TEMPLATE_PROFILE
        bootstrap[:project_emoji] = project_emoji
        bootstrap[:shim] = shim if shim && !shim.empty?
      end
      facts[:kettle_config_bootstrap] = bootstrap if bootstrap
      facts[:author] = author unless author.empty?
      facts[:copyright] = copyright unless copyright.empty?
      forge = forge_facts(kettle_config, env, derived_github_user: derived_github_user)
      facts[:forge] = forge unless forge.empty?
      social = social_facts(kettle_config, env)
      facts[:social] = social unless social.empty?
      opencollective_policy = opencollective_policy(kettle_config, env)
      opencollective_disabled = opencollective_policy.fetch(:disabled)
      funding_platforms = funding_platform_policies(kettle_config, env)
      open_collective_org = opencollective_org(project_root, kettle_config, env, opencollective_disabled: opencollective_disabled)
      open_collective_org ||= fallback_opencollective_org unless opencollective_disabled
      funding = compact_hash(
        urls: funding_urls(
          project_root,
          name,
          funding_uri: metadata_value(gemspec_metadata, :funding_uri),
          opencollective_disabled: opencollective_disabled,
          open_collective_org: open_collective_org && open_collective_org.fetch(:org),
          enabled_platforms: funding_platforms
        ),
        platforms: funding_platforms
      )
      funding_tokens = funding_platform_token_facts(kettle_config, env)
      funding[:platform_tokens] = funding_tokens unless funding_tokens.empty?
      funding[:open_collective_disabled] = true if opencollective_disabled
      funding[:open_collective_disabled_source] = opencollective_policy[:source] if opencollective_disabled
      if open_collective_org
        funding[:open_collective_org] = open_collective_org.fetch(:org)
        funding[:open_collective_org_source] = open_collective_org.fetch(:source)
      end
      open_collective_files = opencollective_disabled ? opencollective_disabled_files(project_root) : []
      funding[:open_collective_files] = open_collective_files unless open_collective_files.empty?
      facts[:funding] = funding unless funding.empty?
      warnings = opencollective_fallback_warnings(funding, project_runtime[:github_org].to_s)
      facts[:warnings] = warnings unless warnings.empty?
      disabled_integrations = disabled_integrations(kettle_config, license: license)
      facts[:integrations] = {disabled: disabled_integrations} unless disabled_integrations.empty?
      opt_in_workflows = opt_in_workflow_cleanup_files(project_root, template_selection)
      facts[:template_profile] = template_selection[:template_profile] unless template_selection[:template_profile].to_s.empty?
      template_config = template_runtime_config(kettle_config, facts, license: license)
      inactive_workflows = inactive_packaged_workflow_cleanup_files(
        project_root,
        template_config,
        include_patterns: template_selection[:include]
      )
      inactive_templates = inactive_packaged_template_cleanup_files(project_root, template_config)
      facts[:ci] = {
        provider: "github_actions",
        default_branch: "main",
        exec_cmd: github_actions_exec_cmd(kettle_config, env),
        engine_exec_cmds: github_actions_engine_exec_cmds(kettle_config),
        recording: project_recording_enabled?(project_root, kettle_config),
        ruby_versions: github_actions_ruby_versions(project_runtime.fetch(:test_min_ruby)),
        test_min_ruby: project_runtime.fetch(:test_min_ruby).to_s,
        obsolete_workflows: github_actions_obsolete_workflows(project_root),
        custom_workflows: github_actions_custom_workflows(project_root, template_config, opencollective_disabled: opencollective_disabled)
      }
      standard_appraisal_gemfiles = github_actions_standard_appraisal_gemfiles(kettle_config)
      facts[:ci][:standard_appraisal_gemfiles] = standard_appraisal_gemfiles unless standard_appraisal_gemfiles.empty?
      facts[:ci][:opt_in_workflow_cleanups] = opt_in_workflows unless opt_in_workflows.empty?
      facts[:ci][:inactive_packaged_workflow_cleanups] = inactive_workflows unless inactive_workflows.empty?
      coverage_config = github_actions_coverage_config(kettle_config, env)
      facts[:ci][:coverage] = coverage_config unless coverage_config.empty?
      framework_matrix = github_actions_framework_matrix(kettle_config)
      facts[:ci][:framework_matrix] = framework_matrix unless framework_matrix.empty?
      default_test_bundle = default_test_bundle_config(kettle_config, framework_matrix)
      facts[:ci][:default_test_bundle] = default_test_bundle unless default_test_bundle.empty?
      template_facts = {}
      template_preferences = template_source_preferences(
        project_root,
        template_config,
        opencollective_disabled: opencollective_disabled,
        include_patterns: template_selection[:include]
      )
      template_preferences += existing_simplecov_bootstrap_template_preferences(
        project_root,
        template_config,
        template_preferences
      )
      template_facts[:source_preferences] = template_preferences unless template_preferences.empty?
      template_facts[:inactive_packaged_template_cleanups] = inactive_templates unless inactive_templates.empty?
      shim_cleanups = shim_profile_cleanups(project_root, facts, template_preferences, template_selection: template_selection)
      template_facts[:shim_profile_cleanups] = shim_cleanups unless shim_cleanups.empty?
      legacy_cleanups = template_legacy_destination_cleanups(project_root, template_preferences)
      template_facts[:legacy_destination_cleanups] = legacy_cleanups unless legacy_cleanups.empty?
      license_cleanups = template_obsolete_license_cleanups(project_root, template_config, template_preferences, license_txt: license_txt)
      template_facts[:obsolete_license_cleanups] = license_cleanups unless license_cleanups.empty?
      unless template_preferences.empty?
        facts[:license] = license unless license.empty?
        facts[:project_runtime] = project_runtime unless project_runtime.empty?
        readme_github_org = project_runtime[:github_org].to_s
        readme_github_org = forge[:gh_user].to_s if readme_github_org.empty?
        readme_github_org = facts.fetch(:repository, {})[:slug].to_s.split("/", 2).first.to_s if readme_github_org.empty?
        readme_logo = readme_logo_facts(
          kettle_config,
          package_name: name,
          github_org: readme_github_org,
          repository: facts[:repository]
        )
        facts[:readme_logo] = readme_logo unless readme_logo.empty?
        readme_sponsors = readme_corporate_sponsors_facts(kettle_config, env)
        facts[:readme_sponsors] = readme_sponsors unless readme_sponsors.empty?
        readme_style = readme_style_facts(
          project_root,
          kettle_config,
          license,
          template_profile: template_selection[:template_profile],
          repository: facts[:repository]
        )
        facts[:readme_style] = readme_style unless readme_style.empty?
        facts[:ruby_style] = ruby_style_facts(project_root)
        changelog = changelog_transfer_facts(project_root, changelog_transfer_entries(PACKAGED_TEMPLATE_ROOT))
        facts[:changelog] = changelog unless changelog.empty?
        gemspec_facts = gemspec_template_facts(kettle_config)
        facts[:gemspec] = gemspec_facts unless gemspec_facts.empty?
        template_tokens = template_tokens(facts, funding)
        template_facts[:tokens] = template_tokens unless template_tokens.empty?
      end
      if template_facts[:tokens].to_h.empty? && funding[:open_collective_org].to_s != ""
        template_facts[:tokens] = {"KJ|OPENCOLLECTIVE_ORG" => funding.fetch(:open_collective_org).to_s}
      end
      facts[:templates] = template_facts unless template_facts.empty?
      facts
    end

    def recipe_pack(facts)
      recipes = if monorepo_template_profile?(facts) || shim_template_profile?(facts)
        []
      else
        [
          recipe_entry("readme_metadata", "README.md", "markdown", "supplied_readme_metadata_synchronization", facts: %w[package funding readme]),
          recipe_entry("changelog_unreleased", "CHANGELOG.md", "markdown", "changelog_unreleased_normalization", facts: %w[package changelog]),
          recipe_entry(
            "generated_block_sync",
            "gemfiles/modular/shunted.gemfile",
            "ruby",
            "supplied_managed_text_block_replacement",
            facts: %w[package generated_blocks],
            provider_backend: "ast-crispr-ruby-prism"
          ),
          recipe_entry(
            "github_funding_yml",
            ".github/FUNDING.yml",
            "yaml",
            "supplied_github_funding_yaml_synchronization",
            facts: %w[package funding]
          )
        ]
      end
      if facts[:kettle_config_bootstrap]
        recipes.unshift(kettle_config_bootstrap_recipe(facts.fetch(:kettle_config_bootstrap)))
      end
      unless monorepo_template_profile?(facts) || shim_template_profile?(facts)
        facts.dig(:ci, :framework_matrix, :gemfiles).to_a.each do |gemfile|
          recipes << recipe_entry(
            "github_actions_framework_gemfile_#{workflow_recipe_slug(gemfile.fetch(:path))}",
            gemfile.fetch(:path),
            "ruby",
            "supplied_framework_matrix_gemfile_generation",
            facts: %w[ci]
          )
        end
        facts.dig(:ci, :obsolete_workflows).to_a.each do |workflow_path|
          recipes << recipe_entry(
            "github_actions_obsolete_workflow_cleanup_#{workflow_recipe_slug(workflow_path)}",
            workflow_path,
            "file",
            "supplied_obsolete_file_deletion",
            facts: %w[ci]
          )
        end
        facts.dig(:ci, :opt_in_workflow_cleanups).to_a.each do |workflow_path|
          recipes << recipe_entry(
            "github_actions_opt_in_workflow_cleanup_#{workflow_recipe_slug(workflow_path)}",
            workflow_path,
            "file",
            "supplied_opt_in_workflow_deletion",
            facts: %w[ci]
          )
        end
        facts.dig(:ci, :inactive_packaged_workflow_cleanups).to_a.each do |workflow_path|
          recipes << recipe_entry(
            "github_actions_inactive_packaged_workflow_cleanup_#{workflow_recipe_slug(workflow_path)}",
            workflow_path,
            "file",
            "supplied_inactive_packaged_workflow_deletion",
            facts: %w[ci]
          )
        end
        facts.dig(:funding, :open_collective_files).to_a.each do |relative_path|
          recipes << recipe_entry(
            "opencollective_disabled_file_cleanup_#{workflow_recipe_slug(relative_path)}",
            relative_path,
            "file",
            "supplied_disabled_opencollective_file_deletion",
            facts: %w[funding]
          )
        end
        facts.dig(:ci, :custom_workflows).to_a.each do |workflow_path|
          recipes << recipe_entry(
            "github_actions_workflow_snippets_#{workflow_recipe_slug(workflow_path)}",
            workflow_path,
            "yaml",
            "supplied_github_actions_workflow_snippet_merge",
            facts: %w[ci]
          )
        end
      end
      if monorepo_template_profile?(facts)
        facts.dig(:ci, :inactive_packaged_workflow_cleanups).to_a.each do |workflow_path|
          recipes << recipe_entry(
            "github_actions_inactive_packaged_workflow_cleanup_#{workflow_recipe_slug(workflow_path)}",
            workflow_path,
            "file",
            "supplied_inactive_packaged_workflow_deletion",
            facts: %w[ci]
          )
        end
      end
      facts.dig(:templates, :source_preferences).to_a.each do |preference|
        apply_template = preference.fetch(:apply, false)
        recipe = recipe_entry(
          "#{apply_template ? "template_source_application" : "template_source_preference"}_#{workflow_recipe_slug(preference.fetch(:target_path))}",
          preference.fetch(:target_path),
          "file",
          apply_template ? "supplied_template_source_application" : "supplied_template_source_preference",
          facts: %w[templates funding]
        )
        recipe[:template_preference] = preference
        recipe[:template_tokens] = facts.dig(:templates, :tokens) if facts.dig(:templates, :tokens)
        recipe[:readme_style] = facts[:readme_style] if preference.fetch(:target_path) == "README.md" && facts[:readme_style]
        recipes << recipe
      end
      facts.dig(:templates, :inactive_packaged_template_cleanups).to_a.each do |cleanup|
        recipes << recipe_entry(
          "template_inactive_packaged_cleanup_#{workflow_recipe_slug(cleanup.fetch(:target_path))}",
          cleanup.fetch(:target_path),
          "file",
          "supplied_inactive_packaged_template_deletion",
          facts: %w[templates]
        )
      end
      facts.dig(:templates, :legacy_destination_cleanups).to_a.each do |cleanup|
        recipes << recipe_entry(
          "template_legacy_destination_cleanup_#{workflow_recipe_slug(cleanup.fetch(:legacy_path))}",
          cleanup.fetch(:legacy_path),
          "file",
          "supplied_legacy_destination_file_deletion",
          facts: %w[templates]
        )
      end
      facts.dig(:templates, :obsolete_license_cleanups).to_a.each do |cleanup|
        recipes << recipe_entry(
          "template_obsolete_license_cleanup_#{workflow_recipe_slug(cleanup.fetch(:license_path))}",
          cleanup.fetch(:license_path),
          "file",
          "supplied_obsolete_license_file_deletion",
          facts: %w[templates license]
        )
      end
      facts.dig(:templates, :shim_profile_cleanups).to_a.each do |cleanup|
        recipes << recipe_entry(
          "template_shim_profile_cleanup_#{workflow_recipe_slug(cleanup.fetch(:target_path))}",
          cleanup.fetch(:target_path),
          "file",
          "supplied_shim_profile_file_deletion",
          facts: %w[templates shim]
        )
      end
      unless shim_template_profile?(facts)
        recipes << recipe_entry(
          "rakefile_scaffold_cleanup",
          "Rakefile",
          "generic_ast",
          "supplied_source_selector_deletion",
          provider_backend: "generic_structural_owners",
          facts: %w[rubygems rakefile],
          selectors: %w[rakefile_scaffold]
        )
      end

      {
        name: "kettle-jem-core",
        version: 1,
        ecosystem: "rubygems",
        recipes: recipes
      }
    end

    def generated_blocks_facts(gemspec, facts, run_options)
      return {} if shim_template_profile?(facts)

      shunted = shunted_gemfile_block(gemspec, facts, run_options)
      shunted ? {shunted_gemfile: shunted} : {}
    end

    def shim_facts(config, env, run_options, package_name:, entrypoint_require:, template_profile:)
      shim_config = config["shim"].is_a?(Hash) ? config["shim"] : {}
      selection = run_options || {}
      replacement_gem = selection[:shimmed_gem].to_s.strip
      replacement_gem = selection["shimmed_gem"].to_s.strip if replacement_gem.empty?
      replacement_gem = env["KETTLE_JEM_SHIMMED_GEM"].to_s.strip if replacement_gem.empty?
      replacement_gem = shim_config["replacement_gem"].to_s.strip if replacement_gem.empty?

      replacement_require = selection[:shimmed_require].to_s.strip
      replacement_require = selection["shimmed_require"].to_s.strip if replacement_require.empty?
      replacement_require = env["KETTLE_JEM_SHIMMED_REQUIRE"].to_s.strip if replacement_require.empty?
      replacement_require = shim_config["replacement_require"].to_s.strip if replacement_require.empty?
      replacement_require = replacement_gem if replacement_require.empty?
      replacement_git = env["KETTLE_JEM_SHIMMED_GIT"].to_s.strip
      replacement_git = shim_config["replacement_git"].to_s.strip if replacement_git.empty?

      legacy_requires = Array(shim_config["legacy_requires"]).flat_map { |entry| entry.to_s.split(",") }
      env_legacy_requires = env["KETTLE_JEM_SHIM_LEGACY_REQUIRES"].to_s
      legacy_requires.concat(env_legacy_requires.split(",")) unless env_legacy_requires.empty?
      legacy_requires << entrypoint_require
      legacy_requires = legacy_requires.map(&:strip).reject(&:empty?).uniq

      return {} if replacement_gem.empty? && template_profile.to_s != SHIM_TEMPLATE_PROFILE
      if replacement_gem.empty?
        raise ArgumentError,
          "shim template profile requires shim.replacement_gem, KETTLE_JEM_SHIMMED_GEM, or --shimmed-gem"
      end

      {
        replacement_gem: replacement_gem,
        replacement_require: replacement_require,
        replacement_git: replacement_git,
        legacy_requires: legacy_requires,
        primary_require: entrypoint_require.to_s,
        package_name: package_name.to_s,
        version_strategy: shim_config.dig("version", "strategy").to_s.empty? ? "shim" : shim_config.dig("version", "strategy").to_s
      }
    end

    def shunted_gemfile_block(gemspec, facts, run_options)
      resolver = run_options[:rubygems_resolver] || run_options["rubygems_resolver"] || RubyGemsResolver.new
      dependencies = extract_gemspec_development_dependencies(gemspec)
      return if dependencies.empty?

      floor = shunted_effective_floor(facts.dig(:rubygems, :min_ruby))
      project_root = facts[:project_root] || facts["project_root"] || run_options[:project_root] || run_options["project_root"]
      shunted = dependencies.filter_map do |dependency|
        next if shunted_dependency_has_modular_override?(project_root, dependency)

        versions = resolver.versions(dependency.fetch(:name), requirements: dependency[:requirement])
        version = versions.max_by { |entry| Gem::Version.new((entry[:number] || entry["number"]).to_s) }
        next unless version

        number = (version[:number] || version["number"]).to_s
        min_ruby = resolver.min_ruby_version(dependency.fetch(:name), number) ||
          resolver.parse_min_ruby(version[:ruby_version] || version["ruby_version"])
        next unless min_ruby && Gem::Version.new(min_ruby.to_s) > floor
        next if shunted_dependency_has_floor_compatible_version?(resolver, dependency, versions, floor)

        dependency.merge(version: number, min_ruby: min_ruby.to_s)
      rescue
        nil
      end
      return if shunted.empty?

      shunted_gemfile_managed_block(shunted)
    rescue
      nil
    end

    def shunted_dependency_has_modular_override?(project_root, dependency)
      root = project_root.to_s
      return false if root.empty?

      name = dependency.fetch(:name).to_s
      return false if name.empty? || name.include?("/") || name.include?("\\")

      File.directory?(File.join(root, "gemfiles", "modular", name))
    end

    def shunted_dependency_has_floor_compatible_version?(resolver, dependency, versions, floor)
      versions.any? do |entry|
        number = (entry[:number] || entry["number"]).to_s
        next false if number.empty?

        min_ruby = resolver.min_ruby_version(dependency.fetch(:name), number) ||
          resolver.parse_min_ruby(entry[:ruby_version] || entry["ruby_version"])
        min_ruby.nil? || Gem::Version.new(min_ruby.to_s) <= floor
      rescue
        false
      end
    end

    def extract_gemspec_development_dependencies(gemspec)
      if gemspec.is_a?(Hash)
        return Array(gemspec[:development_dependencies] || gemspec["development_dependencies"]).map do |dependency|
          {
            name: dependency.name.to_s,
            requirement: dependency.requirement.to_s
          }
        end.reject { |dependency| dependency.fetch(:name).empty? }.uniq { |dependency| dependency.fetch(:name) }
      end

      Array(gemspec&.development_dependencies).map do |dependency|
        {
          name: dependency.name.to_s,
          requirement: dependency.requirement.to_s
        }
      end.reject { |dependency| dependency.fetch(:name).empty? }.uniq { |dependency| dependency.fetch(:name) }
    end

    def shunted_effective_floor(min_ruby)
      floor = minimum_ruby_token(min_ruby)
      versions = [Gem::Version.new("2.3")]
      versions << Gem::Version.new(floor) unless floor.to_s.empty?
      versions.max
    rescue ArgumentError
      Gem::Version.new("2.3")
    end

    def shunted_gemfile_managed_block(dependencies)
      lines = [
        MANAGED_BLOCK_OPEN
      ]
      if dependencies.empty?
        lines << "# (no shunted dependencies)"
      else
        dependencies.sort_by { |dependency| dependency.fetch(:name) }.each do |dependency|
          requirement = dependency[:requirement].to_s.empty? ? "" : %(, "#{dependency.fetch(:requirement)}")
          lines << %(gem "#{dependency.fetch(:name)}"#{requirement} # ruby >= #{dependency.fetch(:min_ruby)})
        end
      end
      lines << MANAGED_BLOCK_CLOSE
      ensure_trailing_newline(lines.join("\n"))
    end

    def plan_project(project_root, env: ENV, run_options: {})
      events = event_stream_from_options(run_options)
      emit_event(events, "run_start", mode: "plan", project_root: project_root.to_s)
      with_event_phase(events, "runtime_dependencies") { ensure_runtime_dependencies! }
      with_event_phase(events, "preflight") { preflight_project!(project_root) }
      template_selection = with_event_phase(events, "template_selection") { template_selection_for(env, run_options) }
      checksum_mode = with_event_phase(events, "checksum_mode") { checksum_mode_for(env, run_options) }
      decision_policy = with_event_phase(events, "decision_policy") { decision_policy_for(env, run_options) }
      git_preflight = with_event_phase(events, "git_preflight") do
        git_preflight_report(project_root, env: env, template_selection: template_selection)
      end
      with_event_phase(events, "git_preflight_enforcement") do
        enforce_git_preflight!(git_preflight, decision_policy: decision_policy, template_selection: template_selection)
      end
      facts = with_event_phase(events, "facts") { discover_facts(project_root, env: env, run_options: run_options) }
      pack = with_event_phase(events, "recipe_pack") { recipe_pack(facts) }
      pack = with_event_phase(events, "recipe_filter") { filter_recipe_pack(pack, template_selection) }
      files = with_event_phase(events, "read_project_files") { read_project_files(project_root, pack) }
      template_contents = with_event_phase(events, "read_template_files") { read_template_source_files(project_root, pack) }
      recipes = pack.fetch(:recipes)
      recipe_planning_strategy = with_event_phase(events, "recipe_planning_strategy") { recipe_planning_strategy_for(env, run_options) }
      recipe_planning_workers = with_event_phase(events, "recipe_planning_workers") { recipe_planning_workers_for(env, run_options) }
      recipe_planning_thread_workers = with_event_phase(events, "recipe_planning_thread_workers") { recipe_planning_thread_workers_for(env, run_options) }
      recipe_planning_execution = {}
      recipe_reports = with_event_phase(events, "recipes", total: recipes.length) do
        execute_recipe_reports(
          project_root: project_root,
          recipes: recipes,
          facts: facts,
          files: files,
          template_contents: template_contents,
          decision_policy: decision_policy,
          env: env,
          events: events,
          strategy: recipe_planning_strategy,
          workers: recipe_planning_workers,
          thread_workers: recipe_planning_thread_workers,
          stats: recipe_planning_execution
        )
      end
      template_lock = with_event_phase(events, "template_lock") { template_lock_state(project_root) }
      recipe_reports = with_event_phase(events, "checksum_skip") do
        apply_checksum_skips(project_root, recipe_reports, checksum_mode: checksum_mode, template_lock: template_lock)
      end
      with_event_phase(events, "dependency_conflicts") do
        validate_modular_dependency_conflicts!(project_root, recipe_reports)
      end
      plugin_registry = with_event_phase(events, "plugins") { plugin_registry_for_project(project_root) }
      changed_files = changed_files_from_recipe_reports(recipe_reports)
      file_outcomes = template_file_outcomes(recipe_reports)
      diagnostics = recipe_reports.flat_map { |report| report[:diagnostics] }
      phase_reports = phase_reports_for(recipe_reports)
      decision_evaluations = recipe_reports.map { |report| report.fetch(:decision_evaluation) }
      prompt_requests = decision_evaluations.filter_map { |decision| decision[:prompt] if decision[:prompt_required] }
      unless plugin_registry.configured_plugins.empty?
        diagnostics << plugin_lifecycle_diagnostic(
          plugin_registry,
          callbacks_run: false,
          active_runner_phases: []
        )
      end
      emit_diagnostic_events(events, diagnostics)
      run_stats = recipe_run_stats(recipe_reports, diagnostics: diagnostics)
      warnings = Array(facts[:warnings]).map(&:to_s).reject(&:empty?)
      warnings.concat(github_workflow_template_pin_warnings(recipe_reports))

      report = with_event_phase(events, "report") do
        {
          mode: "plan",
          ready: true,
          facts: facts,
          recipe_pack: pack,
          recipe_reports: recipe_reports,
          phase_reports: phase_reports,
          recipe_planning_strategy: recipe_planning_strategy,
          recipe_planning_workers: recipe_planning_workers,
          recipe_planning_thread_workers: recipe_planning_thread_workers,
          recipe_planning_execution: recipe_planning_execution,
          decision_policy: decision_policy.to_h,
          checksum_mode: checksum_mode.to_s,
          template_lock: template_lock,
          template_selection: template_selection,
          git_preflight: git_preflight,
          decision_evaluations: decision_evaluations,
          prompt_requests: prompt_requests,
          changed_files: changed_files,
          file_outcomes: file_outcomes,
          phase_timings: events.respond_to?(:phase_timings) ? events.phase_timings : [],
          warnings: warnings.uniq,
          diagnostics: diagnostics,
          run_stats: run_stats
        }
      end
      emit_summary_event(events, report)
      report
    end

    def changed_files_from_recipe_reports(recipe_reports)
      latest_by_path = {}
      recipe_reports.each do |report|
        path = report[:relative_path]
        latest_by_path[path] = report if path
      end
      latest_by_path.values.filter_map { |report| report[:relative_path] if report[:changed] }.uniq.sort
    end

    # Reduce overlays by path so post-planning outcome counts describe
    # destination files, not individual recipes.
    def template_file_outcomes(recipe_reports)
      latest_by_path = {}
      unscoped_recipes = 0

      recipe_reports.each do |report|
        path = report[:relative_path].to_s
        if path.empty?
          unscoped_recipes += 1
        else
          latest_by_path[path] = report
        end
      end

      outcomes = {
        planned: latest_by_path.length,
        checksum_hits: 0,
        checksum_protected: 0,
        unchanged: 0,
        changed: 0,
        unscoped_recipes: unscoped_recipes
      }
      latest_by_path.each_value do |report|
        if checksum_exact_match?(report)
          outcomes[:checksum_hits] += 1
        elsif report[:checksum_skipped]
          outcomes[:checksum_protected] += 1
        elsif report[:changed]
          outcomes[:changed] += 1
        else
          outcomes[:unchanged] += 1
        end
      end
      outcomes
    end

    def checksum_exact_match?(report)
      checksum_match = report.dig(:metadata, :checksum_match) || report.dig(:metadata, "checksum_match") || {}
      (checksum_match[:input_match] == true && checksum_match[:destination_match] == true) ||
        (checksum_match["input_match"] == true && checksum_match["destination_match"] == true)
    end

    def checksum_mode_for(env, run_options)
      raw = (run_options || {})[:checksums] ||
        (run_options || {})["checksums"] ||
        (env || {})["KETTLE_JEM_CHECKSUMS"]
      ChecksumMode.parse(raw)
    end

    def template_lock_state(project_root)
      TemplateLock.load(project_root: project_root, config_path: kettle_jem_config_path(project_root))
    end

    def apply_checksum_skips(project_root, recipe_reports, checksum_mode:, template_lock:)
      return recipe_reports if checksum_mode.off?

      recipe_reports.map do |report|
        checksum_match = checksum_match_details(project_root, report, checksum_mode: checksum_mode, template_lock: template_lock)
        next report unless checksum_match

        matched = deep_dup(report)
        matched[:metadata] = deep_dup(matched.fetch(:metadata, {})).merge(checksum_match: checksum_match)
        next matched unless report[:changed]

        matched[:changed] = false
        matched[:checksum_skipped] = true
        matched[:metadata][:checksum_skip] = {
          mode: checksum_mode.to_s,
          reason: "lock_match"
        }
        matched
      end
    end

    def checksum_skip_report?(project_root, report, checksum_mode:, template_lock:)
      return false unless report[:changed]

      !checksum_match_details(project_root, report, checksum_mode: checksum_mode, template_lock: template_lock).nil?
    end

    def checksum_match_details(project_root, report, checksum_mode:, template_lock:)
      return unless checksum_cache_safe_report?(report)

      relative_path = report.fetch(:relative_path).to_s
      # `template,ignore-dest` preserves a user edit to an existing managed
      # file, but it must never turn a missing managed file into a cache hit.
      # Otherwise a prior partial template run can retain an empty SHA record
      # and leave an aggregate Gemfile referring to a leaf it never creates.
      return unless File.file?(File.join(project_root.to_s, relative_path))

      record = TemplateLock.file_record(template_lock, relative_path)
      return if record.empty?

      input_match = record["input_fingerprint"].to_s == template_input_fingerprint(project_root, report)
      destination_match = record["dest_sha256"].to_s == destination_file_sha256(project_root, relative_path).to_s

      if checksum_mode.check_template?
        return if record["input_fingerprint"].to_s.empty? || !input_match
      end
      if checksum_mode.check_destination?
        return if record["dest_sha256"].to_s.empty? || !destination_match
      end
      {input_match: input_match, destination_match: destination_match}
    end

    def checksum_cache_safe_report?(report)
      metadata = report.fetch(:metadata, {})
      preference = metadata[:template_source_preference] || metadata["template_source_preference"]
      return false unless preference.is_a?(Hash)
      return false if report.dig(:metadata, :delete_file) || report.dig(:metadata, "delete_file")
      # Config migrations are implemented during template application. They must
      # run even when the template source and destination checksums still match.
      return false if report.fetch(:relative_path, "").to_s == KETTLE_CONFIG_PATH

      primitive = report.dig(:request_envelope, :request, :recipe_name).to_s
      primitive == "supplied_template_source_application"
    end

    def template_input_fingerprint(project_root, report)
      Digest::SHA256.hexdigest(JSON.generate(template_input_fingerprint_payload(project_root, report)))
    end

    def template_input_fingerprint_payload(project_root, report)
      metadata = report.fetch(:metadata, {})
      preference = metadata[:template_source_preference] || metadata["template_source_preference"] || {}
      tokens = stringify_keys_for_json(metadata[:template_tokens] || metadata["template_tokens"] || {})
      source_path = template_source_absolute_path(project_root, preference)
      # This payload is the per-destination "template checksum" used by
      # --checksums=template. Bump the explicit renderer version only when
      # source-template application semantics change; unrelated Kettle-Jem
      # code changes must not invalidate every destination record.
      payload = {
        template_source_application_fingerprint_version: TEMPLATE_SOURCE_APPLICATION_FINGERPRINT_VERSION,
        recipe_name: report[:recipe_name].to_s,
        request_recipe_name: report.dig(:request_envelope, :request, :recipe_name).to_s,
        recipe_version: report.dig(:request_envelope, :request, :recipe_version).to_s,
        relative_path: report.fetch(:relative_path).to_s,
        template_source: template_source_lock_path(preference),
        template_source_sha256: (source_path && File.file?(source_path)) ? Digest::SHA256.file(source_path).hexdigest : "",
        template_source_preference: stringify_keys_for_json(preference),
        template_token_keys: tokens.keys.sort,
        template_tokens_sha256: Digest::SHA256.hexdigest(JSON.generate(tokens))
      }
      if template_file_type_for_relative_path(report.fetch(:relative_path).to_s) == :appraisals
        payload[:appraisals_template_policy_fingerprint_version] = APPRAISALS_TEMPLATE_POLICY_FINGERPRINT_VERSION
      end
      if template_file_type_for_relative_path(report.fetch(:relative_path).to_s) == :gemspec
        payload[:gemspec_template_policy_fingerprint_version] = GEMSPEC_TEMPLATE_POLICY_FINGERPRINT_VERSION
      end
      if version_namespace_template_file?(report.fetch(:relative_path).to_s)
        payload[:version_namespace_template_policy_fingerprint_version] = VERSION_NAMESPACE_TEMPLATE_POLICY_FINGERPRINT_VERSION
      end
      if report.fetch(:relative_path).to_s == "spec/spec_helper.rb"
        payload[:spec_helper_template_policy_fingerprint_version] = SPEC_HELPER_TEMPLATE_POLICY_FINGERPRINT_VERSION
      end
      if report.fetch(:relative_path).to_s.start_with?(".github/workflows/")
        engine_exec_cmds = github_workflow_engine_exec_cmds_for_template(
          source_path,
          report.dig(:request_envelope, :request, :runtime_context, :ci, :engine_exec_cmds) ||
            report.dig(:request_envelope, :request, :runtime_context, "ci", "engine_exec_cmds") ||
            {}
        )
        payload[:github_workflow_engine_exec_cmds] = engine_exec_cmds unless engine_exec_cmds.empty?
      end
      payload
    end

    def github_workflow_engine_exec_cmds_for_template(source_path, overrides)
      return {} unless source_path && File.file?(source_path)

      configured = stringify_keys_for_json(overrides)
      return {} if configured.empty?

      yaml_mapping_nodes(File.read(source_path)).each_with_object({}) do |mapping, matching|
        engine = yaml_mapping_scalar_value(mapping, "ruby")
        matching[engine] = configured[engine] if configured.key?(engine)
      end
    rescue Psych::Exception
      {}
    end

    def version_namespace_template_file?(relative_path)
      basename = File.basename(relative_path.to_s)
      basename == "version.rb" || basename == "version_gem.rb" || basename.end_with?(".gemspec")
    end

    def template_file_type_for_relative_path(relative_path)
      basename = File.basename(relative_path.to_s)
      return :appraisals if basename.start_with?("Appraisals") || basename == "Appraisal.root.gemfile"

      nil
    end

    def template_source_absolute_path(project_root, preference)
      return unless preference.is_a?(Hash)

      root = preference[:source_root_path] || preference["source_root_path"] || project_root
      relative = preference[:source_relative_path] || preference["source_relative_path"] ||
        preference[:selected_source] || preference["selected_source"]
      return if relative.to_s.empty?

      File.join(root.to_s, relative.to_s)
    end

    def template_source_lock_path(preference)
      return "" unless preference.is_a?(Hash)

      (preference[:source_relative_path] || preference["source_relative_path"] ||
        preference[:selected_source] || preference["selected_source"]).to_s
    end

    def destination_file_sha256(project_root, relative_path)
      path = File.join(project_root.to_s, relative_path.to_s)
      return unless File.file?(path)

      Digest::SHA256.file(path).hexdigest
    end

    def stringify_keys_for_json(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.to_h do |key|
          raw_value = value.key?(key) ? value[key] : value[key.to_sym]
          [key, stringify_keys_for_json(raw_value)]
        end
      when Array
        value.map { |entry| stringify_keys_for_json(entry) }
      else
        value
      end
    end

    def recipe_planning_strategy_for(env, run_options)
      value = (run_options || {})[:recipe_planning_strategy] ||
        (run_options || {})["recipe_planning_strategy"] ||
        (env || {})["KETTLE_JEM_RECIPE_PLANNING_STRATEGY"]
      strategy = value.to_s.strip
      strategy = "sequential" if strategy.empty?
      strategy = strategy.tr("_", "-")
      strategy = "sequential" if DISABLED_RECIPE_PLANNING_STRATEGY_VALUES.include?(strategy)
      strategy = "classified" if ENABLED_RECIPE_PLANNING_STRATEGY_VALUES.include?(strategy)
      raise ArgumentError, "Unsupported kettle-jem recipe planning strategy #{value.inspect}" unless RECIPE_PLANNING_STRATEGIES.include?(strategy)

      strategy
    end

    def recipe_planning_workers_for(env, run_options)
      value = (run_options || {})[:ractor_workers] ||
        (run_options || {})["ractor_workers"] ||
        (run_options || {})[:recipe_planning_workers] ||
        (run_options || {})["recipe_planning_workers"] ||
        (env || {})["KETTLE_JEM_RACTOR_WORKERS"]
      return 0 if value.nil? || value.to_s.strip.empty?

      workers = Integer(value)
      raise ArgumentError, "KETTLE_JEM_RACTOR_WORKERS must be >= 0" if workers.negative?

      workers
    rescue ArgumentError
      raise ArgumentError, "KETTLE_JEM_RACTOR_WORKERS must be a non-negative integer"
    end

    def recipe_planning_thread_workers_for(env, run_options)
      value = (run_options || {})[:thread_workers] ||
        (run_options || {})["thread_workers"] ||
        (run_options || {})[:recipe_planning_thread_workers] ||
        (run_options || {})["recipe_planning_thread_workers"] ||
        (env || {})["KETTLE_JEM_THREAD_WORKERS"]
      return 0 if value.nil? || value.to_s.strip.empty?

      workers = Integer(value)
      raise ArgumentError, "KETTLE_JEM_THREAD_WORKERS must be >= 0" if workers.negative?

      workers
    rescue ArgumentError
      raise ArgumentError, "KETTLE_JEM_THREAD_WORKERS must be a non-negative integer"
    end

    def file_work_workers_for(env, run_options)
      value = (run_options || {})[:ractor_file_workers] ||
        (run_options || {})["ractor_file_workers"] ||
        (run_options || {})[:file_work_workers] ||
        (run_options || {})["file_work_workers"] ||
        (env || {})["KETTLE_JEM_RACTOR_FILE_WORKERS"]
      return 0 if value.nil? || value.to_s.strip.empty?

      workers = Integer(value)
      raise ArgumentError, "KETTLE_JEM_RACTOR_FILE_WORKERS must be >= 0" if workers.negative?

      workers
    rescue ArgumentError
      raise ArgumentError, "KETTLE_JEM_RACTOR_FILE_WORKERS must be a non-negative integer"
    end

    def file_work_thread_workers_for(env, run_options)
      value = (run_options || {})[:thread_file_workers] ||
        (run_options || {})["thread_file_workers"] ||
        (run_options || {})[:file_work_thread_workers] ||
        (run_options || {})["file_work_thread_workers"] ||
        (env || {})["KETTLE_JEM_THREAD_FILE_WORKERS"]
      return 0 if value.nil? || value.to_s.strip.empty?

      workers = Integer(value)
      raise ArgumentError, "KETTLE_JEM_THREAD_FILE_WORKERS must be >= 0" if workers.negative?

      workers
    rescue ArgumentError
      raise ArgumentError, "KETTLE_JEM_THREAD_FILE_WORKERS must be a non-negative integer"
    end

    def execute_recipe_reports(project_root:, recipes:, facts:, files:, template_contents:, decision_policy:, env:, events:, strategy:, workers: 0, thread_workers: 0, stats: nil)
      case strategy.to_s
      when "sequential"
        record_recipe_planning_execution_stats(
          stats,
          worker_safe: 0,
          main_only: recipes.length,
          worker_count: 0,
          spawned: 0,
          ractor_recipes: 0,
          thread_worker_count: 0,
          thread_spawns: 0,
          thread_recipes: 0,
          main_recipes: recipes.length
        )
        execute_recipe_reports_sequential(
          project_root: project_root,
          recipes: recipes,
          facts: facts,
          files: files,
          template_contents: template_contents,
          decision_policy: decision_policy,
          env: env,
          events: events
        )
      when "classified"
        execute_recipe_reports_classified(
          project_root: project_root,
          recipes: recipes,
          facts: facts,
          files: files,
          template_contents: template_contents,
          decision_policy: decision_policy,
          env: env,
          events: events,
          workers: workers,
          thread_workers: thread_workers,
          stats: stats
        )
      else
        raise ArgumentError, "Unsupported kettle-jem recipe planning strategy #{strategy.inspect}"
      end
    end

    def execute_recipe_reports_sequential(project_root:, recipes:, facts:, files:, template_contents:, decision_policy:, env:, events:)
      recipes.each_with_index.map do |recipe, index|
        report = execute_timed_recipe(
          project_root: project_root,
          recipe: recipe,
          facts: facts,
          files: files,
          template_contents: template_contents,
          decision_policy: decision_policy,
          env: env
        )
        emit_recipe_event(events, report, index: index, total: recipes.length)
        report
      end
    end

    def execute_recipe_reports_classified(project_root:, recipes:, facts:, files:, template_contents:, decision_policy:, env:, events:, workers: 0, thread_workers: 0, stats: nil)
      indexed_recipes = recipes.each_with_index.to_a
      reports_by_index = {}
      worker_safe, main_only = indexed_recipes.partition { |recipe, _index| worker_safe_recipe?(recipe) }
      use_threads = thread_workers.to_i.positive?
      use_ractors = workers.to_i.positive? && worker_safe.any?
      raise ArgumentError, "Use either KETTLE_JEM_RACTOR_WORKERS or KETTLE_JEM_THREAD_WORKERS, not both" if use_threads && workers.to_i.positive?

      worker_count = use_ractors ? [workers.to_i, worker_safe.length].min : 0
      thread_worker_count = use_threads ? [thread_workers.to_i, worker_safe.length].min : 0
      record_recipe_planning_execution_stats(
        stats,
        worker_safe: worker_safe.length,
        main_only: main_only.length,
        worker_count: worker_count,
        spawned: worker_count,
        ractor_recipes: use_ractors ? worker_safe.length : 0,
        thread_worker_count: thread_worker_count,
        thread_spawns: thread_worker_count,
        thread_recipes: use_threads ? worker_safe.length : 0,
        main_recipes: main_only.length + ((use_threads || use_ractors) ? 0 : worker_safe.length)
      )
      if use_threads
        reports_by_index.merge!(
          execute_indexed_recipe_reports_thread(
            project_root: project_root,
            indexed_recipes: worker_safe,
            facts: facts,
            files: files,
            template_contents: template_contents,
            decision_policy: decision_policy,
            env: env,
            workers: thread_worker_count
          )
        )
      else
        reports_by_index.merge!(
          if use_ractors
            execute_worker_safe_recipe_reports_ractor(
              project_root: project_root,
              indexed_recipes: worker_safe,
              facts: facts,
              files: files,
              template_contents: template_contents,
              decision_policy: decision_policy,
              env: env,
              workers: worker_count
            )
          else
            execute_indexed_recipe_reports(
              project_root: project_root,
              indexed_recipes: worker_safe,
              facts: facts,
              files: files,
              template_contents: template_contents,
              decision_policy: decision_policy,
              env: env
            )
          end
        )
      end
      reports_by_index.merge!(
          execute_indexed_recipe_reports(
            project_root: project_root,
            indexed_recipes: main_only,
            facts: facts,
            files: files,
            template_contents: template_contents,
            decision_policy: decision_policy,
            env: env
          )
        )
      recipes.each_index.map do |index|
        report = reports_by_index.fetch(index)
        emit_recipe_event(events, report, index: index, total: recipes.length)
        report
      end
    end

    def execute_indexed_recipe_reports(project_root:, indexed_recipes:, facts:, files:, template_contents:, decision_policy:, env:)
      indexed_recipes.to_h do |recipe, index|
        [
          index,
          execute_timed_recipe(
            project_root: project_root,
            recipe: recipe,
            facts: facts,
            files: files,
            template_contents: template_contents,
            decision_policy: decision_policy,
            env: env
          )
        ]
      end
    end

    def record_recipe_planning_execution_stats(stats, worker_safe:, main_only:, worker_count:, spawned:, ractor_recipes:, thread_worker_count:, thread_spawns:, thread_recipes:, main_recipes:)
      return unless stats

      stats[:worker_safe_recipes] = worker_safe
      stats[:main_only_recipes] = main_only
      stats[:ractor_worker_count] = worker_count
      stats[:ractor_spawn_count] = spawned
      stats[:ractor_recipe_count] = ractor_recipes
      stats[:thread_worker_count] = thread_worker_count
      stats[:thread_spawn_count] = thread_spawns
      stats[:thread_recipe_count] = thread_recipes
      stats[:main_recipe_count] = main_recipes
    end

    def execute_indexed_recipe_reports_thread(project_root:, indexed_recipes:, facts:, files:, template_contents:, decision_policy:, env:, workers:)
      chunks = Array.new(workers) { [] }
      indexed_recipes.each_with_index do |job, offset|
        chunks.fetch(offset % chunks.length) << job
      end
      chunks.reject(&:empty?).flat_map do |chunk|
        # rubocop:disable ThreadSafety/NewThread -- Bounded workers only read shared inputs and are joined below.
        Thread.new do
          thread_id = Thread.current.object_id
          chunk.map do |recipe, index|
            report = execute_timed_recipe(
              project_root: project_root,
              recipe: recipe,
              facts: facts,
              files: files,
              template_contents: template_contents,
              decision_policy: decision_policy,
              env: env
            )
            report[:metadata][:executor] = "thread"
            report[:metadata][:thread_id] = thread_id
            report.dig(:report_envelope, :report, :metadata)[:executor] = "thread"
            report.dig(:report_envelope, :report, :metadata)[:thread_id] = thread_id
            [index, report]
          end
        end
        # rubocop:enable ThreadSafety/NewThread
      end.flat_map(&:value).to_h
    end

    def execute_worker_safe_recipe_reports_ractor(project_root:, indexed_recipes:, facts:, files:, template_contents:, decision_policy:, env:, workers:)
      context = Ractor.make_shareable({
        project_root: project_root,
        facts: facts,
        files: files,
        template_contents: template_contents,
        decision_policy: decision_policy,
        env: env
      })
      chunks = Array.new(workers) { [] }
      indexed_recipes.each_with_index do |job, offset|
        chunks.fetch(offset % chunks.length) << job
      end
      pool = chunks.reject(&:empty?).map do |chunk|
        jobs = Ractor.make_shareable(chunk.map do |recipe, index|
          {
            index: index,
            recipe: worker_safe_recipe_payload(recipe, project_root: project_root, template_contents: template_contents)
          }
        end)
        started_at = monotonic_time
        [
          started_at,
          Ractor.new(context, jobs) do |worker_context, worker_jobs|
            ractor_id = Ractor.current.object_id
            worker_jobs.map do |job|
              report = Kettle::Jem.execute_recipe(**worker_context.merge(recipe: job.fetch(:recipe)))
              [job.fetch(:index), report, ractor_id]
            end
          end
        ]
      end
      reports = {}
      pool.each do |started_at, worker|
        worker_results = worker.value
        duration_ms = duration_ms_since(started_at)
        worker_results.each do |index, report, ractor_id|
          report = report_with_duration(report, duration_ms)
          report[:metadata][:executor] = "ractor"
          report[:metadata][:ractor_id] = ractor_id
          report.dig(:report_envelope, :report, :metadata)[:executor] = "ractor"
          report.dig(:report_envelope, :report, :metadata)[:ractor_id] = ractor_id
          reports[index] = report
        end
      end
      reports
    end

    def worker_safe_recipe_payload(recipe, project_root:, template_contents:)
      return recipe unless recipe.fetch(:primitive).to_s == "supplied_template_source_application"
      return recipe if recipe.dig(:template_preference, :strategy).to_s == "raw_copy"

      content = recipe_template_content(project_root, recipe, template_contents: template_contents)
      recipe.merge(
        resolved_template_content: resolve_template_tokens(
          content,
          recipe.fetch(:template_tokens, {}),
          scan_unresolved: unresolved_template_scan?(recipe)
        )
      )
    end

    def execute_timed_recipe(project_root:, recipe:, facts:, files:, template_contents:, decision_policy:, env:)
      timed_recipe_report do
        execute_recipe(
          project_root: project_root,
          recipe: recipe,
          facts: facts,
          files: files,
          template_contents: template_contents,
          decision_policy: decision_policy,
          env: env
        )
      end
    end

    def worker_safe_recipe?(recipe)
      name = recipe.fetch(:name).to_s
      return true if WORKER_SAFE_RECIPE_NAME_PATTERNS.any? { |pattern| pattern.match?(name) }

      template_source_application_worker_safe?(recipe)
    end

    def template_source_application_worker_safe?(recipe)
      return false unless recipe.fetch(:primitive).to_s == "supplied_template_source_application"

      path = recipe.fetch(:target_path).to_s
      return false if PROJECT_ROOT_SENSITIVE_TEMPLATE_PATHS.include?(path)
      return false if path == KETTLE_CONFIG_PATH
      return false if github_workflow_template_recipe?(recipe)
      return true if recipe.dig(:template_preference, :strategy).to_s == "raw_copy"

      recipe.dig(:template_preference, :strategy).to_s == "accept_template" &&
        RACTOR_SAFE_ACCEPT_TEMPLATE_FILE_TYPES.include?(template_file_type(recipe))
    end

    def apply_project(project_root, env: ENV, run_options: {})
      events = event_stream_from_options(run_options)
      report = plan_project(project_root, env: env, run_options: run_options).merge(mode: "apply")
      file_work_workers = with_event_phase(events, "file_work_workers") { file_work_workers_for(env, run_options) }
      file_work_thread_workers = with_event_phase(events, "file_work_thread_workers") { file_work_thread_workers_for(env, run_options) }
      report[:file_work_workers] = file_work_workers
      report[:file_work_thread_workers] = file_work_thread_workers
      report[:file_work_execution] = file_work_execution_stats(file_work_workers, file_work_thread_workers)
      with_event_phase(events, "apply") do
        before_apply_files = with_event_phase(events, "snapshot_changed_files") do
          snapshot_changed_files(
            project_root,
            report.fetch(:recipe_reports).filter_map { |entry| entry[:relative_path] }
          )
        end
        report[:version_bootstrap_source] = version_bootstrap_source_state(report, before_apply_files)
        with_event_phase(events, "write_template_files") do
          run_apply_phases(
            project_root,
            report,
            file_workers: file_work_workers,
            file_thread_workers: file_work_thread_workers,
            file_stats: report.fetch(:file_work_execution)
          )
        end
        report[:changed_files] = with_event_phase(events, "actual_changed_files") do
          actual_changed_files_after_apply(project_root, report.fetch(:changed_files), before_apply_files)
        end
        report[:post_apply_steps] = with_event_phase(events, "post_apply_steps") { post_apply_steps(project_root, report) }
        emit_step_events(events, "post_apply_step", report.fetch(:post_apply_steps), phase: "post_apply")
      end
      report[:changed_files] = (report.fetch(:changed_files, []) + report.fetch(:post_apply_steps).flat_map do |step|
        reported_post_apply_changed_files(step)
      end).uniq.sort
      report[:duplicate_drift] = with_event_phase(events, "duplicate_drift") do
        if DecisionPolicy.value_to_boolean((run_options || {})[:skip_drift_check])
          {
            available: false,
            skipped: true,
            reason: "skip_drift_check"
          }
        else
          duplicate_drift_report(
            project_root: project_root,
            template_root: template_root_path(project_root, config: kettle_jem_config(project_root)),
            run_options: run_options
          )
        end
      end
      report[:phase_timings] = events.phase_timings if events.respond_to?(:phase_timings)
      emit_summary_event(events, report)
      report
    end

    def event_stream(io, types: nil)
      Kettle::Ndjson.event_stream(
        io,
        types: types,
        event_types: EVENT_TYPES,
        aliases: EVENT_TYPE_ALIASES
      )
    end

    def parse_event_types(types)
      Kettle::Ndjson.normalize_event_types(
        Array(types).join(","),
        event_types: EVENT_TYPES,
        aliases: EVENT_TYPE_ALIASES
      )
    rescue Kettle::Ndjson::UnknownEventTypeError => error
      raise ArgumentError, "#{error.message}. Supported event types: #{EVENT_TYPES.join(", ")}"
    end

    def event_stream_from_options(run_options)
      options = run_options || {}
      recorder = options[:event_recorder] || options["event_recorder"]
      return recorder if recorder.respond_to?(:emit)

      stream = options[:event_stream] || options["event_stream"]
      phase_timings = options[:phase_timings] ||= []
      recorder = Kettle::Ndjson.event_recorder(stream.respond_to?(:emit) ? stream : nil, phase_timings: phase_timings)
      options[:event_recorder] = recorder if options.respond_to?(:[]=)
      recorder
    end

    def with_event_phase(events, phase, payload = {})
      started_at = monotonic_time
      emit_phase_event(events, phase, status: "started", **payload)
      result = yield
      duration_ms = duration_ms_since(started_at)
      record_phase_timing(events, phase, status: "ok", duration_ms: duration_ms, payload: payload)
      emit_phase_event(events, phase, status: "ok", duration_ms: duration_ms, **payload)
      result
    rescue => error
      duration_ms = duration_ms_since(started_at) if started_at
      record_phase_timing(events, phase, status: "failed", duration_ms: duration_ms, payload: payload)
      emit_phase_event(
        events,
        phase,
        status: "failed",
        duration_ms: duration_ms,
        error_class: error.class.name,
        error_message: error.message,
        **payload
      )
      raise
    end

    def record_phase_timing(events, phase, status:, duration_ms:, payload:)
      Kettle::Ndjson.record_phase_timing(events, phase, status: status, duration_ms: duration_ms, payload: payload)
    end

    def emit_phase_event(events, phase, status:, **payload)
      Kettle::Ndjson.emit_phase_event(events, phase, status: status, **payload)
    end

    def emit_recipe_event(events, report, index:, total:)
      payload = {
        phase: "template",
        index: index + 1,
        total: total,
        path: report.fetch(:relative_path, nil),
        recipe: report.fetch(:recipe_name, nil),
        changed: report.fetch(:changed, false),
        status: "ok",
        mark: report.fetch(:changed, false) ? "*" : "."
      }
      duration_ms = report.dig(:metadata, :duration_ms)
      payload[:duration_ms] = duration_ms if duration_ms
      emit_event(events, "recipe", payload)
    end

    def timed_recipe_report
      started_at = monotonic_time
      report = yield
      report_with_duration(report, duration_ms_since(started_at))
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def duration_ms_since(started_at)
      ((monotonic_time - started_at) * 1000).round(3)
    end

    def with_readme_timing_context(relative_path, timings)
      return yield unless relative_path.to_s == "README.md"

      previous = Thread.current[:kettle_jem_readme_timings]
      Thread.current[:kettle_jem_readme_timings] = timings
      yield
    ensure
      Thread.current[:kettle_jem_readme_timings] = previous if relative_path.to_s == "README.md"
    end

    def with_readme_timing(name)
      timings = Thread.current[:kettle_jem_readme_timings]
      return yield unless timings

      started_at = monotonic_time
      result = yield
      timings << {name: name.to_s, status: "ok", duration_ms: duration_ms_since(started_at)}
      result
    rescue => error
      if timings && started_at
        timings << {
          name: name.to_s,
          status: "failed",
          duration_ms: duration_ms_since(started_at),
          error_class: error.class.name,
          error_message: error.message
        }
      end
      raise
    end

    def report_with_duration(report, duration_ms)
      report[:metadata] = report.fetch(:metadata, {}).merge(duration_ms: duration_ms)
      report.dig(:report_envelope, :report, :metadata)&.[]=(:duration_ms, duration_ms)
      report
    end

    def emit_step_events(events, event_type, steps, phase:)
      Array(steps).each_with_index do |step, index|
        emit_step_event(events, event_type, step, phase: phase, index: index + 1, total: Array(steps).length)
      end
    end

    def emit_step_event(events, event_type, step, phase:, index: nil, total: nil)
      emit_event(
        events,
        event_type,
        phase: phase.to_s,
        index: index,
        total: total,
        name: event_payload_value(step, :name),
        status: event_payload_value(step, :status),
        reason: event_payload_value(step, :reason),
        command: event_payload_value(step, :command),
        path: event_payload_value(step, :path),
        changed_files: Array(event_payload_value(step, :changed_files) || []),
        changed_count: Array(event_payload_value(step, :changed_files) || []).length,
        mark: step_event_mark(step)
      )
    end

    def step_event_mark(step)
      return ">" if event_payload_value(step, :status).to_s == "started"
      return "F" if %w[failed blocked].include?(event_payload_value(step, :status).to_s)

      Array(event_payload_value(step, :changed_files) || []).empty? ? "." : "*"
    end

    def emit_diagnostic_events(events, diagnostics)
      Array(diagnostics).each_with_index do |diagnostic, index|
        payload = diagnostic.respond_to?(:to_h) ? diagnostic.to_h : {message: diagnostic.to_s}
        emit_event(
          events,
          "diagnostic",
          index: index + 1,
          total: Array(diagnostics).length,
          kind: payload[:kind] || payload["kind"] || payload[:key] || payload["key"],
          severity: payload[:severity] || payload["severity"],
          path: payload[:path] || payload["path"],
          message: payload[:message] || payload["message"] || diagnostic.to_s,
          blocking: payload[:blocking] || payload["blocking"]
        )
      end
    end

    def event_payload_value(payload, key)
      payload.fetch(key, payload.fetch(key.to_s, nil))
    end

    def reported_post_apply_changed_files(step)
      return [] if event_payload_value(step, :metadata_only)

      Array(event_payload_value(step, :changed_files) || [])
    end

    def emit_summary_event(events, report)
      file_outcomes = report.fetch(:file_outcomes, {})
      emit_event(
        events,
        "summary",
        mode: report.fetch(:mode, nil),
        changed_files: Array(report.fetch(:changed_files, [])),
        changed_count: Array(report.fetch(:changed_files, [])).length,
        planned_count: file_outcomes.fetch(:planned, 0),
        checksum_hit_count: file_outcomes.fetch(:checksum_hits, 0),
        checksum_protected_count: file_outcomes.fetch(:checksum_protected, 0),
        unchanged_count: file_outcomes.fetch(:unchanged, 0),
        unscoped_recipe_count: file_outcomes.fetch(:unscoped_recipes, 0),
        diagnostics_count: Array(report.fetch(:diagnostics, [])).length,
        status: "ok",
        mark: "."
      )
    end

    def emit_event(events, type, payload = {})
      Kettle::Ndjson.emit_event(events, type, payload)
    end

    def snapshot_changed_files(project_root, changed_files)
      changed_files.to_h do |relative_path|
        path = File.join(project_root, relative_path)
        [relative_path, File.exist?(path) ? File.read(path) : nil]
      end
    end

    def actual_changed_files_after_apply(project_root, changed_files, before_apply_files)
      changed_files.filter_map do |relative_path|
        path = File.join(project_root, relative_path)
        original = before_apply_files.fetch(relative_path, nil)
        if File.exist?(path)
          (File.read(path) == original) ? nil : relative_path
        else
          original.nil? ? nil : relative_path
        end
      end.uniq.sort
    end

    def post_apply_steps(project_root, report)
      selection = report.fetch(:template_selection, {})
      scoped_template = Array(selection[:only]).any?
      return [kettle_jem_state_sync_step(project_root, report)].compact if scoped_template

      [
        *[template_version_gem_bootstrap_step(project_root, report)].flatten,
        executable_version_entrypoint_sync_step(project_root, report),
        monorepo_root_gemfile_dependency_sync_step(project_root, report),
        modular_dependency_conflict_resolution_step(project_root),
        git_hooks_executable_step(project_root),
        github_actions_pin_sync_step(project_root),
        monorepo_subgem_kettle_config_profile_sync_step(project_root, report),
        kettle_jem_state_sync_step(project_root, report)
      ].compact
    end

    def version_bootstrap_source_state(report, before_apply_files)
      facts = report.fetch(:facts, {})
      entrypoint_require = facts.dig(:rubygems, :entrypoint_require).to_s
      return {} if entrypoint_require.empty?

      version_path = File.join("lib", entrypoint_require, "version.rb")
      content = before_apply_files.fetch(version_path, nil)
      return {} unless content

      {
        preserve_version_module_include: version_file_includes_version_module?(content)
      }
    end

    def modular_dependency_conflict_resolution_step(project_root)
      decisions = modular_dependency_conflict_decisions(kettle_jem_config(project_root))
      return nil if decisions.empty?

      changed_files = apply_modular_dependency_conflict_resolutions(project_root, decisions)
      {
        name: "modular_dependency_conflict_resolution",
        status: changed_files.empty? ? "already_current" : "applied",
        changed_files: changed_files,
        decisions: decisions.map { |decision| %w[gem modular action].to_h { |key| [key, decision.fetch(key)] } }
      }
    end

    # Older generated executable headers used the package name for both the
    # version file and namespace.  Projects such as appraisal2 intentionally
    # expose a different historical entrypoint, so repair that exact stale
    # header shape from the configured entrypoint facts.
    def executable_version_entrypoint_sync_step(project_root, report)
      facts = report.fetch(:facts)
      package_name = facts.dig(:package, :name).to_s
      entrypoint_require = facts.dig(:rubygems, :entrypoint_require).to_s
      return if package_name.empty? || entrypoint_require.empty?

      package_entrypoint = package_name.tr("-", "/")
      return if package_entrypoint == entrypoint_require

      namespace = facts.dig(:rubygems, :namespace).to_s
      version_path = File.join("lib", entrypoint_require, "version.rb")
      namespace = existing_version_namespace(project_root, version_path) if namespace.empty?
      return if namespace.empty?

      legacy_namespace = package_name.split(/[-_]/).map { |part| part[0].to_s.upcase + part[1..].to_s }.join("::")
      legacy_version_path = "../lib/#{package_entrypoint}/version"
      canonical_version_path = "../lib/#{entrypoint_require}/version"
      changed_files = Dir.glob(File.join(project_root, "exe", "*")).sort.filter_map do |path|
        next unless File.file?(path)

        before = File.read(path)
        after = normalize_executable_version_entrypoint(
          before,
          legacy_version_path: legacy_version_path,
          canonical_version_path: canonical_version_path,
          legacy_namespace: legacy_namespace,
          namespace: namespace
        )
        next if after == before

        File.write(path, after)
        path.delete_prefix("#{project_root}/")
      end
      {
        name: "executable_version_entrypoint_sync",
        status: changed_files.empty? ? "already_current" : "applied",
        changed_files: changed_files
      }
    end

    def normalize_executable_version_entrypoint(content, legacy_version_path:, canonical_version_path:, legacy_namespace:, namespace:)
      parsed = prism_parse_success(content)
      return content unless parsed

      require_call = ruby_call_records(content, :require_relative).find do |call|
        argument = call.arguments&.arguments&.first
        [legacy_version_path, canonical_version_path].include?(ruby_static_string_value(argument))
      end
      return content unless require_call

      stale_header = stale_executable_startup_header(
        parsed.value,
        require_call: require_call,
        namespaces: [legacy_namespace, namespace]
      )
      return remove_stale_executable_startup_header(content, stale_header) if stale_header

      require_argument = require_call.arguments&.arguments&.first
      return content unless ruby_static_string_value(require_argument) == legacy_version_path

      legacy_segments = legacy_namespace.to_s.split("::")
      namespace_segments = namespace.to_s.split("::")
      version_constants = []
      parsed.value.breadth_first_search_all do |node|
        next unless node.is_a?(::Prism::ConstantPathNode)

        segments = ruby_constant_path_segments(node)
        version_constants << node if segments == legacy_segments + ["Version", "VERSION"] || segments == legacy_segments + ["VERSION"]
      end
      return content if version_constants.empty?

      replacements = [
        {
          start_offset: require_argument.location.start_offset,
          end_offset: require_argument.location.end_offset,
          replacement: JSON.generate(canonical_version_path)
        }
      ]
      version_constants.each do |node|
        suffix = (ruby_constant_path_segments(node).last(2) == ["Version", "VERSION"]) ? ["Version", "VERSION"] : ["VERSION"]
        replacements << {
          start_offset: node.location.start_offset,
          end_offset: node.location.end_offset,
          replacement: (namespace_segments + suffix).join("::")
        }
      end
      replace_source_offsets(content, replacements)
    end

    def stale_executable_startup_header(ast, require_call:, namespaces:)
      owners = ast.statements&.body.to_a
      require_index = owners.index do |owner|
        owner.location.start_offset == require_call.location.start_offset &&
          owner.location.end_offset == require_call.location.end_offset
      end
      return unless require_index && require_index >= 1

      assignment = owners.fetch(require_index - 1)
      conditional = owners.fetch(require_index + 1, nil)
      header = owners.drop(require_index + 2).find do |owner|
        owner.is_a?(::Prism::CallNode) && owner.name == :puts && owner.slice.to_s.include?("script_basename")
      end
      return unless assignment.is_a?(::Prism::LocalVariableWriteNode) && assignment.name == :script_basename
      return unless conditional.is_a?(::Prism::IfNode) && header

      namespace_segments = namespaces.filter_map do |value|
        segments = value.to_s.split("::").reject(&:empty?)
        segments unless segments.empty?
      end
      return if namespace_segments.empty?
      return unless executable_version_constant_nodes(conditional, namespace_segments).any?
      return unless executable_version_constant_nodes(header, namespace_segments).any?
      return unless header.slice.to_s.include?("script_basename")

      {assignment: assignment, require_call: require_call, conditional: conditional, header: header}
    end

    def executable_version_constant_nodes(node, namespaces)
      constants = []
      node.breadth_first_search_all do |candidate|
        next unless candidate.is_a?(::Prism::ConstantPathNode)

        segments = ruby_constant_path_segments(candidate)
        constants << candidate if namespaces.any? do |namespace|
          segments == namespace + ["Version", "VERSION"] || segments == namespace + ["VERSION"]
        end
      end
      constants
    end

    def remove_stale_executable_startup_header(content, header)
      replacements = header.values.map do |node|
        {
          start_offset: node.location.start_offset,
          end_offset: node.location.end_offset,
          replacement: ""
        }
      end
      ensure_trailing_newline(collapse_excess_blank_lines(replace_source_offsets(content, replacements)))
    end

    def git_hooks_executable_step(project_root)
      existing_paths = EXECUTABLE_GIT_HOOK_PATHS.select do |relative_path|
        File.file?(File.join(project_root.to_s, relative_path))
      end
      return {name: "git_hooks_executable", status: "missing", changed_files: []} if existing_paths.empty?

      changed_files = existing_paths.filter_map do |relative_path|
        path = File.join(project_root.to_s, relative_path)
        before = File.stat(path).mode
        after = before | 0o111
        next if before == after

        FileUtils.chmod(after, path)
        relative_path
      end
      {
        name: "git_hooks_executable",
        status: changed_files.empty? ? "already_executable" : "updated",
        changed_files: changed_files
      }
    end

    def github_actions_pin_sync_step(project_root)
      workflow_root = File.join(project_root.to_s, ".github", "workflows")
      return unless File.directory?(workflow_root)

      changed_files = Dir[File.join(workflow_root, "*.{yml,yaml}")].sort.filter_map do |path|
        before = File.read(path)
        after = update_github_actions_pins(before)
        next if after == before

        File.write(path, after)
        path.delete_prefix("#{project_root}/")
      end
      {
        name: "github_actions_pin_sync",
        status: changed_files.empty? ? "already_current" : "applied",
        changed_files: changed_files
      }
    end

    def monorepo_subgem_kettle_config_profile_sync_step(project_root, report)
      facts = report.fetch(:facts)
      return unless monorepo_subgem_template_profile?(facts)

      profile = normalize_template_profile(facts[:template_profile])
      path = File.join(project_root.to_s, KETTLE_CONFIG_PATH)
      return unless File.file?(path)

      gemspec = facts.dig(:rubygems, :gemspec_path).to_s
      before = File.read(path)
      after = sync_kettle_config_monorepo_subgem_profile(before, gemspec, profile)
      File.write(path, after) if after != before
      {
        name: "monorepo_subgem_kettle_config_profile_sync",
        path: KETTLE_CONFIG_PATH,
        status: (after == before) ? "already_current" : "applied",
        changed_files: (after == before) ? [] : [KETTLE_CONFIG_PATH]
      }
    end

    def kettle_jem_state_sync_step(project_root, report)
      config_path = kettle_jem_config_path(project_root)
      return unless File.file?(config_path)

      relative_config_path = config_path.delete_prefix("#{project_root}/")
      lock_path = TemplateLock.path(project_root)
      relative_lock_path = lock_path.delete_prefix("#{project_root}/")
      legacy_lock_path = TemplateLock.legacy_path(project_root)
      relative_legacy_lock_path = legacy_lock_path.delete_prefix("#{project_root}/")
      legacy_lock_existed = File.exist?(legacy_lock_path)
      before_config = File.read(config_path)
      before_lock = File.exist?(lock_path) ? File.read(lock_path) : nil
      latest_replay = report.dig(:facts, :changelog, :latest_transfer_entry)
      existing_state = TemplateLock.load(project_root: project_root, config_path: config_path)
      existing_replay = existing_state.dig(TemplateLock::TEMPLATE_STATE_KEY, TemplateChecksums::CHANGELOG_REPLAY_SUBKEY)
      changelog_replay = if latest_replay
        {
          TemplateChecksums::LAST_ENTRY_KEY_SUBKEY => latest_replay.fetch(:key),
          TemplateChecksums::LAST_ENTRY_DATE_SUBKEY => changelog_transfer_key_date(latest_replay.fetch(:key))
        }
      elsif existing_replay.is_a?(Hash)
        existing_replay
      end
      template_state = {
        "version" => VERSION,
        "applied_at" => Time.now.utc.strftime("%Y-%m-%d"),
        TemplateChecksums::CHANGELOG_REPLAY_SUBKEY => changelog_replay,
        TemplateChecksums::CHECKSUMS_SUBKEY => TemplateChecksums.compute(
          template_root: template_root_path(project_root, config: kettle_jem_config(project_root))
        )
      }.compact
      file_records = checksum_file_records(project_root, report, existing_state)
      TemplateLock.write(
        project_root: project_root,
        lock: TemplateLock.build_lock(template_state: template_state, file_records: file_records)
      )
      TemplateLock.remove_legacy(project_root)
      TemplateChecksums.remove_from_config(config_path: config_path)
      after_config = File.read(config_path)
      after_lock = File.read(lock_path)
      if after_config != before_config
        config_report = report.fetch(:recipe_reports, []).find { |entry| entry.fetch(:relative_path, nil) == relative_config_path }
        config_report[:final_content] = after_config if config_report
        config_report&.dig(:report_envelope, :report)&.[]=(:final_content, after_config)
      end
      changed_files = []
      changed_files << relative_config_path if after_config != before_config
      changed_files << relative_lock_path if after_lock != before_lock
      changed_files << relative_legacy_lock_path if legacy_lock_existed
      {
        name: "kettle_jem_state_sync",
        path: relative_lock_path,
        status: changed_files.empty? ? "already_current" : "applied",
        changed_files: changed_files,
        metadata_only: true
      }
    end

    def checksum_file_records(project_root, report, existing_state)
      existing_records = TemplateLock.files(existing_state).each_with_object({}) do |(relative_path, record), retained|
        action = record.is_a?(Hash) ? record["action"].to_s : ""
        next if action != "delete" && !File.exist?(File.join(project_root, relative_path.to_s))

        retained[relative_path] = record
      end
      report.fetch(:recipe_reports, []).each_with_object(existing_records.dup) do |recipe_report, records|
        next unless checksum_cache_safe_report?(recipe_report)

        relative_path = recipe_report.fetch(:relative_path).to_s
        existing = records[relative_path].is_a?(Hash) ? records[relative_path].dup : {}
        if recipe_report[:checksum_skipped]
          records[relative_path] = existing.merge(
            "recipe" => recipe_report[:recipe_name].to_s,
            "input_fingerprint" => template_input_fingerprint(project_root, recipe_report),
            "template_sources" => [template_source_lock_path(
              recipe_report.dig(:metadata, :template_source_preference) ||
                recipe_report.dig(:metadata, "template_source_preference") ||
                {}
            )].reject(&:empty?)
          )
          next
        end

        records[relative_path] = {
          "recipe" => recipe_report[:recipe_name].to_s,
          "action" => recipe_report.dig(:metadata, :delete_file) ? "delete" : "write",
          "dest_sha256" => destination_file_sha256(project_root, relative_path),
          "input_fingerprint" => template_input_fingerprint(project_root, recipe_report),
          "template_sources" => [template_source_lock_path(
            recipe_report.dig(:metadata, :template_source_preference) ||
              recipe_report.dig(:metadata, "template_source_preference") ||
              {}
          )].reject(&:empty?)
        }.compact
      end
    end

    def sync_kettle_config_monorepo_subgem_profile(content, gemspec_path, profile)
      normalized_profile = normalize_template_profile(profile)
      entries = monorepo_subgem_template_entries(gemspec_path, normalized_profile)
      lines = content.to_s.lines(chomp: true)
      templates_index = lines.index("templates:")
      return content unless templates_index

      profile_index = ((templates_index + 1)...lines.length).find do |index|
        line = lines.fetch(index)
        break nil if top_level_yaml_key_line?(line)

        line.start_with?("  profile:")
      end
      return content unless profile_index

      updated = lines.dup
      updated[profile_index] = "  profile: #{normalized_profile}"
      entries_lines = kettle_config_template_entries_lines(entries)
      entries_index = ((templates_index + 1)...updated.length).find do |index|
        line = updated.fetch(index)
        break nil if top_level_yaml_key_line?(line)

        line == "  entries:"
      end
      if entries_index
        entries_end = entries_index + 1
        entries_end += 1 while entries_end < updated.length && updated.fetch(entries_end).start_with?("    ")
        updated[entries_index...entries_end] = entries_lines
      else
        updated.insert(profile_index + 1, *entries_lines)
      end
      sync_kettle_config_gemspec_strategy_lines!(updated, gemspec_path)
      sync_kettle_config_rakefile_strategy_lines!(updated)
      ensure_trailing_newline(updated.join("\n"))
    end

    def sync_kettle_config_gemspec_strategy_lines!(lines, gemspec_path)
      gemspec = gemspec_path.to_s
      return if gemspec.empty?

      files_index = lines.index("files:")
      return unless files_index

      remove_stale_gemspec_file_override_blocks!(lines, files_index, gemspec)
      gemspec_index = lines.index("  #{gemspec}:")
      unless gemspec_index
        insertion_index = kettle_config_gemspec_override_insertion_index(lines, files_index)
        lines.insert(insertion_index, "  #{gemspec}:", "    strategy: merge")
        return
      end

      block_end = kettle_config_file_override_block_end(lines, gemspec_index)
      strategy_index = ((gemspec_index + 1)...block_end).find do |index|
        line = lines.fetch(index)
        line.start_with?("    strategy:")
      end
      if strategy_index
        lines[strategy_index] = "    strategy: merge"
      else
        lines.insert(gemspec_index + 1, "    strategy: merge")
      end
    end

    def sync_kettle_config_rakefile_strategy_lines!(lines)
      files_index = lines.index("files:")
      return unless files_index

      rakefile_index = ((files_index + 1)...lines.length).find do |index|
        line = lines.fetch(index)
        break nil if top_level_yaml_key_line?(line)

        line == "  Rakefile:"
      end
      unless rakefile_index
        insertion_index = kettle_config_gemspec_override_insertion_index(lines, files_index)
        lines.insert(insertion_index, "  Rakefile:", "    strategy: accept_template")
        return
      end

      block_end = kettle_config_file_override_block_end(lines, rakefile_index)
      strategy_index = ((rakefile_index + 1)...block_end).find do |index|
        lines.fetch(index).start_with?("    strategy:")
      end
      if strategy_index
        lines[strategy_index] = "    strategy: accept_template"
      else
        lines.insert(rakefile_index + 1, "    strategy: accept_template")
      end
    end

    def remove_stale_gemspec_file_override_blocks!(lines, files_index, gemspec)
      index = files_index + 1
      while index < lines.length
        line = lines.fetch(index)
        break if top_level_yaml_key_line?(line)

        # Keep this as a bounded line match instead of dumping YAML so the
        # generated field-guide comments and ordering survive profile sync.
        match = line.match(/\A  ([^ ].*\.gemspec):\z/)
        if match && match[1] != gemspec
          block_end = kettle_config_file_override_block_end(lines, index)
          lines.slice!(index...block_end)
          next
        end

        index += 1
      end
    end

    def kettle_config_gemspec_override_insertion_index(lines, files_index)
      readme_index = lines.index("  README.md:")
      if readme_index && readme_index > files_index
        return kettle_config_file_override_block_end(lines, readme_index)
      end

      files_index + 1
    end

    def kettle_config_file_override_block_end(lines, start_index)
      index = start_index + 1
      index += 1 while index < lines.length && lines.fetch(index).start_with?("    ")
      index
    end

    def top_level_yaml_key_line?(line)
      return false if line.to_s.empty? || line.start_with?("#") || line.start_with?(" ")

      line.include?(":")
    end

    def kettle_config_template_entries_lines(entries)
      ["  entries:", *entries.flat_map do |entry|
        if entry.is_a?(Hash)
          [
            "    - source: #{entry.fetch("source")}",
            "      target: #{entry.fetch("target")}"
          ]
        else
          ["    - #{entry}"]
        end
      end]
    end

    def monorepo_root_gemfile_dependency_sync_step(project_root, report)
      facts = report.fetch(:facts)
      return unless monorepo_root_template_profile?(facts)

      path = File.join(project_root.to_s, "Gemfile")
      before = File.exist?(path) ? File.read(path) : %(source "https://gem.coop"\n)
      after = ensure_monorepo_root_gemfile_dependencies(before)
      File.write(path, after) if after != before
      {
        name: "monorepo_root_gemfile_dependency_sync",
        path: "Gemfile",
        status: (after == before) ? "already_current" : "applied",
        changed_files: (after == before) ? [] : ["Gemfile"]
      }
    end

    def ensure_monorepo_root_gemfile_dependencies(content)
      updated = ensure_trailing_newline(content.to_s.empty? ? %(source "https://gem.coop"\n) : content.to_s).dup
      monorepo_root_gemfile_dependency_lines.each do |line|
        next if gemfile_declares_gem?(updated, line.fetch(:name))

        updated << "\n" unless updated.end_with?("\n\n")
        updated << line.fetch(:source)
      end
      ensure_trailing_newline(updated)
    end

    def monorepo_root_gemfile_dependency_lines
      [
        {name: "appraisal2", source: %(gem "appraisal2", "~> 3.2", ">= 3.2.3"\n)},
        {name: "bundler-audit", source: %(gem "bundler-audit", "~> 0.9.3"\n)},
        {name: "kettle-dev", source: %(gem "kettle-dev", "~> 3.0", ">= 3.0.27"\n)},
        {name: "kettle-drift", source: %(gem "kettle-drift", "~> 1.0", ">= 1.0.13"\n)},
        {name: "kettle-family", source: %(gem "kettle-family", "~> 1.2", ">= 1.2.77"\n)},
        {name: "kettle-jem", source: %(gem "kettle-jem", "~> 7.1", ">= 7.1.13"\n)},
        {name: "kettle-test", source: %(gem "kettle-test", "~> 2.0", ">= 2.0.21"\n)},
        {name: "rake", source: %(gem "rake", "~> 13.0"\n)},
        {name: "rspec", source: %(gem "rspec", "~> 3.0"\n)},
        {name: "stone_checksums", source: %(gem "stone_checksums", "~> 1.0", ">= 1.0.8"\n)},
        {name: "turbo_tests2", source: %(gem "turbo_tests2", "~> 3.2", ">= 3.2.7"\n)}
      ].freeze
    end

    def gemfile_declares_gem?(content, gem_name)
      ruby_call_records(content, nil).any? do |call|
        next false unless call.receiver.nil?

        case call.name
        when :gem
          ruby_string_argument(call) == gem_name.to_s
        when :gemspec
          gemspec_path_declares_gem?(ruby_keyword_string_argument(call, :path), gem_name)
        else
          false
        end
      end
    end

    def gemspec_path_declares_gem?(path, gem_name)
      normalized_path = path.to_s.delete_suffix("/")
      normalized_path == "gems/#{gem_name}"
    end

    def detected_license_ids(project_root)
      known_license_template_basenames.filter_map do |basename|
        path = File.join(project_root.to_s, "#{basename}.md")
        File.exist?(path) ? spdx_from_basename(basename) : nil
      end.sort
    end

    def spdx_from_basename(basename)
      return "LicenseRef-Big-Time-Public-License" if basename.to_s == "Big-Time-Public-License"

      basename.to_s
    end

    def template_version_gem_bootstrap_step(project_root, report)
      facts = report.fetch(:facts)
      entrypoint_require = facts.dig(:rubygems, :entrypoint_require).to_s
      entrypoint_require = facts.dig(:package, :name).to_s.tr("-", "/") if entrypoint_require.empty?
      return [] unless version_gem_post_apply_selected?(report, entrypoint_require)

      package_name = facts.dig(:package, :name).to_s
      package_entrypoint_path = File.join("lib", "#{package_name}.rb")
      package_entrypoint_report = report.fetch(:recipe_reports, []).find do |recipe_report|
        recipe_report.fetch(:relative_path, "").to_s == package_entrypoint_path
      end
      package_entrypoint_preexisting = if package_entrypoint_report
        destination_existed = package_entrypoint_report.dig(:metadata, :destination_existed)
        destination_existed.nil? ? File.file?(File.join(project_root, package_entrypoint_path)) : destination_existed
      else
        File.file?(File.join(project_root, package_entrypoint_path))
      end
      package_entrypoint_preexisting = false if facts.dig(:version_gem, :mode).to_s == "inline"

      unless version_gem_runtime_compatible?(facts)
        return [
          old_ruby_version_bootstrap_step(
            project_root,
            report,
            entrypoint_require: entrypoint_require,
            preserve_version_module_include: report.dig(:version_bootstrap_source, :preserve_version_module_include)
          ),
          legacy_rbs_consolidation_step(project_root, facts, entrypoint_require: entrypoint_require)
        ].compact
      end

      unless project_uses_version_gem?(project_root, entrypoint_require, facts)
        return [
          version_gem_cleanup_step(project_root, facts, cleanup_entrypoint: !version_gem_enabled?(facts)),
          legacy_rbs_consolidation_step(project_root, facts, entrypoint_require: entrypoint_require)
        ].compact
      end

      templated_paths = report.fetch(:recipe_reports, []).map { |recipe_report| recipe_report.fetch(:relative_path, "") }
      version_path = File.join("lib", entrypoint_require, "version.rb")
      signature_path = File.join("sig", "#{entrypoint_require}.rbs")
      namespace = facts.dig(:rubygems, :namespace).to_s
      entrypoint_path = facts.dig(:rubygems, :entrypoint_namespace_superclass_path).to_s
      entrypoint_path = File.join("lib", "#{entrypoint_require}.rb") unless File.file?(File.join(project_root, entrypoint_path))
      namespace_superclass_details = existing_namespace_superclass_details(
        project_root,
        namespace,
        preferred_path: entrypoint_path
      )
      entrypoint_path = namespace_superclass_details[:path] if namespace_superclass_details[:path]
      namespace_kinds_override = existing_version_namespace_kinds(
        project_root,
        version_path,
        namespace,
        entrypoint_path: entrypoint_path
      )
      version_gem_bootstrap_step_for_paths(
        project_root,
        facts,
        package_entrypoint_preexisting: package_entrypoint_preexisting,
        preserve_version_module_include: report.dig(:version_bootstrap_source, :preserve_version_module_include),
        # The generic recipe renders module namespaces.  A destination entrypoint
        # can establish its outer namespace as a class (for example Month), which
        # the generated version file must reopen as that same class.
        manage_version_file: !templated_paths.include?(version_path) ||
          version_namespace_outer_kind_for_template(project_root, facts, entrypoint_path, version_path, namespace) == :class,
        manage_signature_file: !templated_paths.include?(signature_path),
        namespace_kinds_override: namespace_kinds_override
      )
    end

    def version_gem_post_apply_selected?(report, entrypoint_require)
      selected = Array(report.dig(:template_selection, :only)).map(&:to_s)
      return true if selected.empty?

      package_name = report.dig(:facts, :package, :name).to_s
      managed_paths = [
        "#{package_name}.gemspec",
        File.join("lib", "#{entrypoint_require}.rb"),
        File.join("lib", entrypoint_require, "version.rb"),
        File.join("lib", entrypoint_require, "version_gem.rb"),
        File.join("sig", "#{entrypoint_require}.rbs"),
        File.join("spec", entrypoint_require, "version_spec.rb")
      ]
      report.fetch(:recipe_reports, []).any? do |recipe_report|
        path = recipe_report.fetch(:relative_path, "").to_s
        managed_paths.include?(path)
      end
    end

    def old_ruby_version_bootstrap_step(project_root, report, entrypoint_require:, preserve_version_module_include: nil)
      facts = report.fetch(:facts)
      package_name = facts.dig(:package, :name).to_s
      return {name: "version_bootstrap", status: "unavailable", reason: "missing_package_facts"} if package_name.empty?

      entrypoint_require = package_name.tr("-", "/") if entrypoint_require.to_s.empty?
      namespace = facts.dig(:rubygems, :namespace).to_s
      version_path = File.join("lib", entrypoint_require, "version.rb")
      entrypoint_path = File.join("lib", "#{entrypoint_require}.rb")
      if namespace.empty?
        namespace = existing_entrypoint_version_namespace(
          project_root,
          entrypoint_path,
          expected_depth: classify_namespace(package_name).split("::").count { |segment| !segment.empty? }
        ).to_s
      end
      namespace = existing_version_namespace(project_root, version_path).to_s if namespace.empty?
      namespace = classify_namespace(package_name) if namespace.empty?
      return {name: "version_bootstrap", status: "unavailable", reason: "missing_package_facts"} if namespace.empty?

      namespace_superclass_details = existing_namespace_superclass_details(
        project_root,
        namespace,
        preferred_path: entrypoint_path
      )
      entrypoint_namespace_superclasses = version_namespace_superclasses_from_facts(facts).merge(
        namespace_superclass_details.fetch(:superclasses)
      ).merge(
        entrypoint_namespace_superclasses_from_facts(facts)
      )
      fact_superclass_path = facts.dig(:rubygems, :entrypoint_namespace_superclass_path).to_s
      if entrypoint_namespace_superclasses.any? && File.file?(File.join(project_root, fact_superclass_path))
        entrypoint_path = fact_superclass_path
      elsif namespace_superclass_details[:path]
        entrypoint_path = namespace_superclass_details[:path]
      end
      templated_paths = report.fetch(:recipe_reports, []).map { |recipe_report| recipe_report.fetch(:relative_path, "") }
      changes = []
      outer_namespace_kind = version_namespace_outer_kind(project_root, entrypoint_path, namespace)
      namespace_kinds = existing_version_namespace_kinds(
        project_root,
        version_path,
        namespace,
        entrypoint_path: entrypoint_path
      )
      cleanup = version_gem_cleanup_step(
        project_root,
        facts,
        entrypoint_path: entrypoint_path,
        after_declarations: !entrypoint_namespace_superclasses.empty?
      )
      changes.concat(Array(cleanup[:changed_files]))
      preserve_version_module_include = existing_version_file_includes_version_module?(project_root, version_path) if preserve_version_module_include.nil?
      unless templated_paths.include?(version_path) && outer_namespace_kind != :class
        version = facts.dig(:project_runtime, :version).to_s
        version = project_gemspec_version(project_root) if version.empty?
        version = "0.0.1.pre" if version.empty?
        changes << write_if_changed(
          project_root,
          version_path,
          version_gem_version_file_content(
            existing_version: existing_version_file_value(project_root, version_path),
            namespace: namespace,
            version: version,
            outer_namespace_kind: outer_namespace_kind,
            namespace_kinds: namespace_kinds,
            preserve_version_module_include: preserve_version_module_include
          )
        )
      end
      changes << normalize_version_gem_version_spec(
        project_root,
        File.join("spec", entrypoint_require, "version_spec.rb"),
        entrypoint_require,
        namespace,
        ensure_version_gem_require: false,
        include_version_gem_path: false
      )
      changes.compact!
      changes.uniq!

      {
        name: "version_bootstrap",
        status: changes.empty? ? "already_current" : "applied",
        changed_files: changes,
        cleanup_status: cleanup.fetch(:status)
      }
    end

    def legacy_rbs_consolidation_step(project_root, facts, entrypoint_require:)
      legacy_signature_paths = legacy_rbs_signature_paths(project_root, entrypoint_require)
      return if legacy_signature_paths.empty?

      namespace = facts.dig(:rubygems, :namespace).to_s
      signature_path = File.join("sig", "#{entrypoint_require}.rbs")
      changes = write_consolidated_version_signature(
        project_root,
        signature_path,
        legacy_signature_paths,
        namespace: namespace
      ).compact
      {
        name: "legacy_rbs_consolidation",
        status: changes.empty? ? "already_current" : "applied",
        changed_files: changes,
        signature_path: signature_path
      }
    end

    def version_gem_cleanup_step(project_root, facts, cleanup_entrypoint: true, after_declarations: false, entrypoint_path: nil)
      package_name = facts.dig(:package, :name).to_s
      return {name: "version_gem_cleanup", status: "unavailable", reason: "missing_package_facts"} if package_name.empty?

      entrypoint_require = facts.dig(:rubygems, :entrypoint_require).to_s
      entrypoint_require = package_name.tr("-", "/") if entrypoint_require.empty?
      entrypoint_path ||= File.join("lib", "#{entrypoint_require}.rb")
      dedicated_entrypoint_path = File.join("lib", entrypoint_require, "version_gem.rb")
      version_spec_path = File.join("spec", entrypoint_require, "version_spec.rb")
      changed_files = []
      current = read_project_file(project_root, entrypoint_path)
      if cleanup_entrypoint && !current.empty?
        version_path = File.join(project_root, "lib", entrypoint_require, "version.rb")
        cleaned = version_gem_free_entrypoint_content(
          current,
          entrypoint_require: entrypoint_require,
          ensure_version_require: File.file?(version_path),
          after_declarations: after_declarations
        )
        changed_files << write_if_changed(project_root, entrypoint_path, cleaned)
      end
      changed_files << cleanup_version_gem_entrypoint(project_root, dedicated_entrypoint_path)
      changed_files << cleanup_version_gem_version_spec(project_root, version_spec_path)
      changed_files.compact!
      {
        name: "version_gem_cleanup",
        status: changed_files.empty? ? "already_current" : "applied",
        changed_files: changed_files,
        entrypoint_path: entrypoint_path,
        dedicated_entrypoint_path: dedicated_entrypoint_path,
        version_spec_path: version_spec_path
      }
    end

    def project_gemspec_version(project_root)
      path = Dir.glob(File.join(project_root, "*.gemspec")).min
      return "" unless path

      load_project_gemspec(path)&.version.to_s
    end

    def project_gemspec_declares_version_gem?(project_root)
      path = Dir.glob(File.join(project_root, "*.gemspec")).min
      return false unless path

      metadata = static_project_gemspec_metadata(path)
      dependencies = Array(metadata[:runtime_dependencies] || metadata["runtime_dependencies"])
      if dependencies.empty?
        spec = load_project_gemspec(path)
        dependencies = Array(spec&.runtime_dependencies)
      end
      dependencies.any? { |dependency| dependency.name == "version_gem" }
    end

    def project_uses_version_gem?(project_root, _entrypoint_require, facts = nil)
      return false if version_gem_explicitly_disabled?(facts)

      version_gem_enabled?(facts) || project_gemspec_declares_version_gem?(project_root)
    end

    def duplicate_drift_report(project_root:, template_root:, run_options: {})
      runner = run_options[:duplicate_drift_runner] || run_options["duplicate_drift_runner"]
      unless runner
        if defined?(Kettle::Drift)
          runner = Kettle::Drift
        else
          return {
            available: false,
            reason: "kettle-drift is not available"
          }
        end
      end

      outcome = if runner.respond_to?(:call)
        runner.call(project_root: project_root, template_dir: template_root)
      else
        runner.run(
          project_root: project_root,
          template_dir: template_root,
          lock_path: File.join(project_root.to_s, ".kettle-drift.lock"),
          mode: :force_update,
          printer_class: nil
        )
      end
      {
        available: true,
        warning_count: outcome.respond_to?(:warning_count) ? outcome.warning_count : outcome.fetch(:warning_count),
        json_path: outcome.respond_to?(:json_path) ? outcome.json_path : outcome[:json_path],
        lock_path: outcome.respond_to?(:lock_path) ? outcome.lock_path : outcome[:lock_path],
        exit_code: outcome.respond_to?(:exit_code) ? outcome.exit_code : outcome[:exit_code]
      }.compact
    rescue => error
      {
        available: false,
        reason: "#{error.class}: #{error.message}"
      }
    end

    def setup_project(project_root, env: ENV, run_options: {}, command_runner: nil)
      root = File.expand_path(project_root.to_s)
      config_path = kettle_jem_config_path(root)
      config_existed = File.exist?(config_path)
      execution_context = setup_execution_context(env, run_options)
      plan = plan_project(root, env: env, run_options: run_options)
      selection = plan.fetch(:template_selection)
      bootstrap_only = selection[:bootstrap_mode] || (!config_existed && !selection[:accept_config])

      if bootstrap_only
        bootstrap_report = plan.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == KETTLE_CONFIG_PATH }
        apply_recipe_report(root, bootstrap_report) if bootstrap_report&.fetch(:changed, false)
        changed_files = bootstrap_report&.fetch(:changed, false) ? [KETTLE_CONFIG_PATH] : []
        return plan.merge(
          mode: "setup",
          setup_status: config_existed ? "bootstrap_config_already_present" : "bootstrap_config_written",
          setup_execution_context: execution_context,
          ready: config_existed,
          changed_files: changed_files,
          diagnostics: plan.fetch(:diagnostics) + [setup_guidance_diagnostic(config_existed: config_existed)]
        )
      end

      install_kwargs = {project_root: root, env: env, run_options: run_options}
      install_kwargs[:command_runner] = command_runner if command_runner
      Tasks::InstallTask.run(**install_kwargs).merge(
        mode: "setup",
        setup_execution_context: execution_context,
        setup_status: config_existed ? "configured_project_applied" : "accepted_config_applied"
      )
    end

    def plan_readme_style(project_root, env: ENV)
      facts = discover_facts(project_root, env: env)
      config = kettle_jem_config(project_root)
      readme_style = facts[:readme_style] ||
        readme_style_facts(
          project_root,
          config,
          facts.fetch(:license, {}),
          template_profile: facts[:template_profile],
          repository: facts[:repository]
        )
      original_path = File.join(project_root, "README.md")
      original = File.exist?(original_path) ? File.read(original_path) : ""
      final_content = render_thin_readme(facts, readme_style, original, readme_preserve_config(config))

      {
        mode: "plan",
        readme_path: "README.md",
        changed: final_content != original,
        readme_style: readme_style,
        final_content: final_content,
        diagnostics: []
      }
    end

    def apply_readme_style(project_root, env: ENV)
      report = plan_readme_style(project_root, env: env).merge(mode: "apply")
      return report unless report.fetch(:changed)

      path = File.join(project_root, report.fetch(:readme_path))
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, report.fetch(:final_content))
      report
    end

    def render_thin_readme(facts, readme_style, original, preserve_config)
      package = facts.fetch(:package)
      rubygems = facts.fetch(:rubygems)
      license_expression = package[:license_expression].to_s
      min_ruby = minimum_ruby_token(rubygems[:min_ruby])
      title = classify_namespace(package.fetch(:name))
      badges = [
        package[:source_url] && "[![Source](https://img.shields.io/badge/source-github-238636.svg)](#{package[:source_url]})",
        license_expression.empty? ? nil : "![License](https://img.shields.io/badge/license-#{shield_token(license_expression)}-259D6C.svg)"
      ].compact.join(" ")
      funding_enabled = readme_style.fetch(:floss_funding_enabled, false)
      security_enabled = readme_style.fetch(:security_enabled, false)
      section_partials = readme_section_partials_for_render(readme_style, facts)
      rendered = [
        "# 💎 #{title}",
        badges,
        "## 🌻 Synopsis\n\n#{section_partials.fetch("synopsis", "")}",
        "## 💡 Info you can shake a stick at\n\nCompatible with MRI Ruby #{min_ruby}+.\n\n#{readme_family_intro_and_backend_matrix(readme_style)}",
        "## ✨ Installation\n\n```console\ngem install #{package.fetch(:name)}\n```",
        "## ⚙️ Configuration\n\n#{section_partials.fetch("configuration", "")}",
        "## 🔧 Basic Usage\n\n#{section_partials.fetch("basic usage", "")}"
      ]
      rendered << "## 🦷 FLOSS Funding\n\nThis free software project accepts funding support when configured by the package maintainer." if funding_enabled
      rendered << "## 🔐 Security\n\nSee [SECURITY.md](SECURITY.md)." if security_enabled
      rendered.concat([
        "## 🤝 Contributing\n\nContributions are welcome. Missing optional service integrations are reported by the generator instead of rendered as broken badges.",
        "## 📌 Versioning\n\nThis project follows semantic versioning for its public API where practical.",
        "## 📄 License\n\nThis project is made available under the following license expression: #{license_expression.empty? ? "unspecified" : license_expression}.",
        "## 🤑 A request for help\n\nPlease support the project by using it, reporting issues, and contributing improvements."
      ])
      template_content = rendered.reject(&:empty?).join("\n\n") + "\n"

      merge_readme_template(
        template_content: template_content,
        destination_content: original,
        preserve_config: readme_preserve_config_without_partial_sections(preserve_config, section_partials.keys)
      )
    end

    def readme_section_partials_for_render(readme_style, facts)
      partials = readme_style[:section_partials]
      return {} unless partials.is_a?(Hash)

      tokens = readme_template_tokens(facts)
      partials.each_with_object({}) do |(section, partial), result|
        content = partial.is_a?(Hash) ? partial[:content].to_s : partial.to_s
        next if content.strip.empty?

        result[normalize_readme_section_key(section)] = resolve_template_tokens(content, tokens)
      end
    end

    def readme_preserve_config_without_partial_sections(preserve_config, partial_sections)
      normalized_partials = partial_sections.map { |section| normalize_readme_section_key(section) }
      return preserve_config if normalized_partials.empty?

      config = (preserve_config || {}).dup
      sections = if config.key?(:sections)
        Array(config[:sections]).map { |section| normalize_readme_section_key(section) }
      else
        README_DEFAULT_PRESERVE_SECTIONS.dup
      end
      config[:sections] = sections.reject { |section| normalized_partials.include?(section) }
      config
    end

    def readme_template_tokens(facts)
      {
        "KJ|CB:USER" => "",
        "KJ|FUNDING:BUYMEACOFFEE" => "",
        "KJ|FUNDING:KOFI" => "",
        "KJ|FUNDING:LIBERAPAY" => "",
        "KJ|FUNDING:PAYPAL" => "",
        "KJ|GH:USER" => "",
        "KJ|GH_ORG" => github_org_from_url(facts.dig(:package, :source_url)).to_s,
        "KJ|GL:USER" => "",
        "KJ|PROJECT_EMOJI" => "💎",
        "KJ|README:COPYRIGHT_NOTICE" => "",
        "KJ|README:CORPORATE_SPONSORS" => "",
        "KJ|README:LICENSE_BADGE" => "",
        "KJ|README:LICENSE_COMPAT_BADGE" => "",
        "KJ|README:DEV_TEST_STACK_TABLE" => "",
        "KJ|README:LICENSE_INTRO" => "",
        "KJ|README:LICENSE_REFS" => "",
        "KJ|README:H2_SYNOPSIS_LOGO_ROW" => "",
        "KJ|README:TOP_LOGO_REFS" => "",
        "KJ|README:TOP_LOGO_ROW" => "",
        "KJ|SH:USER" => "",
        "KJ|SOCIAL:BLUESKY" => "",
        "KJ|SOCIAL:DEVTO" => "",
        "KJ|SOCIAL:LINKTREE" => "",
        "KJ|SOCIAL:MASTODON" => "",
        "KJ|HOMEPAGE_URI" => "https://rubydoc.info",
        "KJ|YARD_HOST" => "rubydoc.info"
      }.merge(template_tokens(facts, facts.fetch(:funding, {})))
    end

    def content_recipe_execution_request(recipe_name:, recipe_version:, relative_path:, provider_family:,
      template_content:, destination_content:, steps:, provider_backend: nil, runtime_context: nil, metadata: nil)
      compact_hash(
        recipe_name: recipe_name.to_s,
        recipe_version: recipe_version.to_s,
        relative_path: relative_path.to_s,
        provider_family: provider_family.to_s,
        provider_backend: provider_backend&.to_s,
        template_content: template_content.to_s,
        destination_content: destination_content.to_s,
        steps: deep_dup(steps),
        runtime_context: deep_dup(runtime_context || {}),
        metadata: deep_dup(metadata || {})
      )
    end

    def content_recipe_execution_request_envelope(request)
      {
        kind: "content_recipe_execution_request",
        version: CONTENT_RECIPE_TRANSPORT_VERSION,
        request: deep_dup(request)
      }
    end

    def content_recipe_execution_report(request:, final_content:, changed:, step_reports:, diagnostics:, metadata: nil)
      compact_hash(
        request: deep_dup(request),
        final_content: final_content.to_s,
        changed: changed ? true : false,
        step_reports: deep_dup(step_reports),
        diagnostics: deep_dup(diagnostics),
        metadata: deep_dup(metadata || {})
      )
    end

    def content_recipe_execution_report_envelope(report)
      {
        kind: "content_recipe_execution_report",
        version: CONTENT_RECIPE_TRANSPORT_VERSION,
        report: deep_dup(report)
      }
    end

    def synchronize_readme(content, facts, project_root: nil)
      package = facts.fetch(:package)
      lines = content.to_s.split("\n", -1)
      heading = "# #{package.fetch(:name)}"
      h1_index = lines.index { |line| line.start_with?("# ") }
      unless h1_index
        lines.unshift(heading, "")
      end
      postprocess_readme_content(
        replace_markdown_managed_block(lines.join("\n"), "kettle-jem:metadata", readme_metadata_block(facts)),
        facts,
        project_root: project_root
      )
    end

    def normalize_changelog(content, facts)
      text = normalize_legacy_changelog_release_headings(content.to_s)
      title = "# Changelog"
      headings = markdown_heading_owners(text, source_label: "CHANGELOG.md")
      unless headings.any? { |heading| heading.level == 1 }
        text = "#{title}\n\n#{text}"
        headings = markdown_heading_owners(text, source_label: "CHANGELOG.md")
      end
      return ensure_trailing_newline(text) if headings.any? { |heading| heading.level == 2 && changelog_unreleased_heading?(heading.heading_text) }

      lines = text.split("\n", -1)
      insert_at = headings.find { |heading| heading.level == 2 }&.location&.start_line&.-(1) || lines.length
      section = [
        "## [Unreleased]",
        "",
        "### Added",
        "",
        "### Changed",
        "",
        "### Deprecated",
        "",
        "### Removed",
        "",
        "### Fixed",
        "",
        "### Security",
        ""
      ]
      lines.insert(insert_at, *section)
      ensure_trailing_newline(lines.join("\n").gsub(/\n{3,}/, "\n\n"))
    end

    def normalize_legacy_changelog_release_headings(content)
      lines = markdown_source_lines(content)
      markdown_heading_owners(content, source_label: "CHANGELOG.md").each do |heading|
        next unless heading.level == 2

        canonical = canonical_changelog_release_heading(heading.heading_text)
        next unless canonical

        lines[heading.location.start_line - 1] = canonical
      end
      lines.join("\n")
    end

    def canonical_changelog_release_heading(heading_text)
      text = heading_text.to_s.strip
      return if changelog_unreleased_heading?(text) || text.start_with?("[")

      version, date = text.split(" - ", 2)
      version = version.to_s.delete_prefix("v")
      # Markly owns heading discovery; Gem::Version is the bounded semantic
      # version parser because Markdown has no release-version node type.
      return unless Gem::Version.correct?(version)

      suffix = date ? " - #{date}" : ""
      "## [#{version}]#{suffix}"
    end

    CHANGELOG_STANDARD_HEADINGS = [
      "### Added",
      "### Changed",
      "### Deprecated",
      "### Removed",
      "### Fixed",
      "### Security"
    ].freeze

    def merge_changelog_template_source(template_content, destination_content, facts: nil)
      destination = normalize_legacy_changelog_release_headings(destination_content.to_s)
      if destination.strip.empty?
        return apply_changelog_transfer_entries(
          ensure_trailing_newline(template_content.to_s),
          facts.to_h.dig(:changelog, :transfer_entries),
          excluded_keys: facts.to_h.dig(:changelog, :excluded_transfer_keys)
        )
      end

      template_lines = markdown_source_lines(template_content)
      template_unreleased = changelog_unreleased_line_index(template_lines)
      unless template_unreleased
        return apply_changelog_transfer_entries(
          ensure_trailing_newline(template_content.to_s),
          facts.to_h.dig(:changelog, :transfer_entries),
          excluded_keys: facts.to_h.dig(:changelog, :excluded_transfer_keys)
        )
      end

      destination_lines = markdown_source_lines(destination)
      destination_unreleased = changelog_unreleased_line_index(destination_lines)
      unless destination_unreleased
        header = changelog_template_header(template_lines, template_unreleased).join("\n")
        return apply_changelog_transfer_entries(
          ensure_trailing_newline("#{header}\n\n#{destination}"),
          facts.to_h.dig(:changelog, :transfer_entries),
          excluded_keys: facts.to_h.dig(:changelog, :excluded_transfer_keys)
        )
      end

      destination_end = changelog_unreleased_end_index(destination_lines, destination_unreleased)
      destination_body = destination_lines[(destination_unreleased + 1)...destination_end] || []
      canonical = build_changelog_unreleased_section(
        template_lines.fetch(template_unreleased),
        changelog_unreleased_items(destination_body)
      )
      header = changelog_template_header(template_lines, template_unreleased)
      merged_lines = header +
        (header.empty? ? [] : [""]) +
        canonical +
        destination_lines[destination_end..].to_a
      apply_changelog_transfer_entries(
        ensure_trailing_newline(merged_lines.join("\n").gsub(/\n{3,}/, "\n\n")),
        facts.to_h.dig(:changelog, :transfer_entries),
        excluded_keys: facts.to_h.dig(:changelog, :excluded_transfer_keys)
      )
    end

    def markdown_source_lines(content)
      content.to_s.split("\n")
    end

    def changelog_template_header(lines, unreleased_index)
      header = lines[0...unreleased_index].to_a
      header.pop while header.any? && header.last.to_s.strip.empty?
      header
    end

    def changelog_unreleased_line_index(lines)
      lines.index { |line| changelog_unreleased_heading_line?(line) }
    end

    def changelog_unreleased_heading_line?(line)
      text = line.to_s.strip
      return false unless text.start_with?("## ")

      changelog_unreleased_heading?(text.delete_prefix("## ").strip)
    end

    def changelog_unreleased_end_index(lines, unreleased_index)
      index = unreleased_index + 1
      while index < lines.length
        line = lines.fetch(index)
        # Markdown link-reference definitions are footer content, not Unreleased section body.
        return index if markdown_link_reference_definition_line?(line)
        return index if line.start_with?("# ") || (line.start_with?("## ") && !changelog_unreleased_heading_line?(line))

        index += 1
      end
      lines.length
    end

    def markdown_link_reference_definition_line?(line)
      line.to_s.lstrip.start_with?("[") && line.to_s.include?("]:")
    end

    def changelog_unreleased_items(body_lines)
      items = {}
      heading = nil
      index = 0
      while index < body_lines.length
        line = body_lines.fetch(index)
        if line.start_with?("### ")
          heading = line.strip
          items[heading] ||= []
          index += 1
          next
        end

        if changelog_bullet_line?(line)
          lines, index = collect_changelog_list_item(body_lines, index)
          items[heading] ||= []
          items[heading].concat(lines)
          next
        end

        index += 1
      end
      items
    end

    def build_changelog_unreleased_section(heading, items)
      lines = [heading]
      CHANGELOG_STANDARD_HEADINGS.each do |standard_heading|
        lines << ""
        lines << standard_heading
        lines << ""
        section_items = items[standard_heading].to_a.dup
        section_items.pop while section_items.any? && section_items.last.to_s.strip.empty?
        lines.concat(section_items) if section_items.any?
      end
      lines << ""
      lines
    end

    def changelog_transfer_facts(project_root, entries)
      all_entries = Array(entries)
      latest = latest_changelog_transfer_entry(all_entries)
      lock = TemplateLock.load(project_root: project_root, config_path: kettle_jem_config_path(project_root))
      state = lock[TemplateLock::TEMPLATE_STATE_KEY]
      state = state.is_a?(Hash) ? state : {}
      context = transfer_changelog_context(project_root)
      applicable_entries = all_entries.select { |entry| transfer_changelog_entry_applies?(entry, context) }
      excluded_keys = all_entries.reject { |entry| transfer_changelog_entry_applies?(entry, context) }.map { |entry| entry.fetch(:key).to_s }
      applied_keys = changelog_transfer_applied_keys(project_root)
      selected_entries = if state.empty?
        [CHANGELOG_INITIAL_TEMPLATE_ENTRY]
      else
        applicable_entries.reject { |entry| applied_keys.include?(entry.fetch(:key).to_s) }
      end

      {
        transfer_entries: selected_entries,
        excluded_transfer_keys: excluded_keys,
        latest_transfer_entry: latest,
        first_template: state.empty?
      }.compact
    end

    def transfer_changelog_status(project_root, env: ENV, verbose: false)
      all_entries = changelog_transfer_entries(PACKAGED_TEMPLATE_ROOT)
      context = transfer_changelog_context(project_root, env: env)
      applicable = all_entries.select { |entry| transfer_changelog_entry_applies?(entry, context) }
      applicable_keys = applicable.map { |entry| entry.fetch(:key).to_s }.to_set
      applied_keys = changelog_transfer_applied_keys(project_root)
      missing = applicable.reject { |entry| applied_keys.include?(entry.fetch(:key).to_s) }
      excluded_present = changelog_transfer_applied_keys(project_root).reject { |key| applicable_keys.include?(key) }
      result = {
        total_count: all_entries.size,
        applicable_count: applicable.size,
        applied_count: applicable.size - missing.size,
        missing_count: missing.size,
        excluded_present_count: excluded_present.size
      }.compact
      result[:missing_entries] = missing if verbose
      result[:excluded_present_keys] = excluded_present if verbose
      result
    end

    # Compatibility API for callers released before filter-aware replay.  New
    # callers must use transfer_changelog_status(project_root:).
    def transfer_changelog_lag(last_entry_key = nil, verbose: false)
      all_entries = changelog_transfer_entries(PACKAGED_TEMPLATE_ROOT)
      latest = latest_changelog_transfer_entry(all_entries)
      missing = if last_entry_key.to_s.empty?
        all_entries
      else
        changelog_transfer_entries_after(all_entries, last_entry_key)
      end
      result = {
        last_entry_key: last_entry_key.to_s.empty? ? nil : last_entry_key.to_s,
        latest_entry_key: latest&.fetch(:key),
        missing_count: missing.size
      }.compact
      result[:missing_entries] = missing if verbose
      result
    end

    def transfer_changelog_entries
      changelog_transfer_entries(PACKAGED_TEMPLATE_ROOT)
    end

    def latest_changelog_transfer_entry(entries)
      Array(entries).last
    end

    def changelog_transfer_applied_keys(project_root)
      path = File.join(project_root.to_s, "CHANGELOG.md")
      return Set.new unless File.file?(path)

      changelog_transfer_keys(File.read(path))
    end

    def changelog_unreleased_transfer_keys(project_root)
      path = File.join(project_root.to_s, "CHANGELOG.md")
      return Set.new unless File.file?(path)

      changelog_existing_transfer_occurrences(File.read(path))
        .select { |occurrence| occurrence.fetch(:release_heading) == "## [Unreleased]" }
        .map { |occurrence| occurrence.fetch(:key).to_s }
        .to_set
    end

    def transfer_changelog_context(project_root, env: ENV)
      config = kettle_jem_config(project_root)
      rubygems = config["rubygems"].is_a?(Hash) ? config["rubygems"] : {}
      engines = Array(ruby_engines_config(config))
      engines = DEFAULT_ENGINES if engines.empty?
      profile = normalize_template_profile(config.dig("templates", "profile"))
      profile = FULL_TEMPLATE_PROFILE if profile.empty?
      min_ruby = transfer_changelog_min_ruby(project_root, rubygems)
      entrypoint = transfer_changelog_entrypoint_require(project_root, rubygems)
      version_gem_mode = rubygems_version_gem_entrypoint_mode(rubygems)
      rubyforum_config = config["rubyforum"].is_a?(Hash) ? config["rubyforum"] : {}
      project_tag = preferred_template_token_value(nil, rubyforum_config["project_tag"], env, "KJ_RUBYFORUM_PROJECT_TAG").to_s
      sponsors = readme_corporate_sponsors(config, env)
      {
        "profile" => profile,
        "topology" => config.dig("repository", "topology").to_s.empty? ? REPOSITORY_TOPOLOGY_STANDALONE : config.dig("repository", "topology").to_s,
        "ruby.min" => min_ruby.empty? ? "0" : min_ruby,
        "engine.jruby" => engines.include?("jruby"),
        "engine.truffleruby" => engines.include?("truffleruby") || engines.include?("truby"),
        "engine.alternates" => engines.any? { |engine| %w[jruby truffleruby truby].include?(engine) },
        "feature.appraisals" => File.file?(File.join(project_root, "Appraisals")),
        "feature.rubyforum" => !rubyforum_facts(config, env, package_name: transfer_changelog_package_name(project_root)).empty?,
        "feature.rubyforum_project_tag" => !normalize_rubyforum_tag(project_tag).empty?,
        "feature.corporate_sponsors" => sponsors.any?,
        "feature.organization_logo" => readme_top_logo_options(config).any? || readme_h2_synopsis_logo_options(config).any?,
        "feature.structuredmerge_driver" => config.fetch("git_drivers", "semantic-diff").to_s == "semantic-diff",
        "feature.dedicated_version_gem" => version_gem_mode == "dedicated" || File.file?(File.join(project_root, "lib", entrypoint, "version_gem.rb")),
        "workflow.dep_heads" => File.file?(File.join(project_root, ".github", "workflows", "dep-heads.yml")),
        "workflow.jruby_94" => File.file?(File.join(project_root, ".github", "workflows", "jruby-9.4.yml")),
        "version_gem.mode" => version_gem_mode
      }
    end

    # Do not call discover_facts here. discover_facts itself computes changelog
    # facts, so doing so would recurse during every prepare/template operation.
    def transfer_changelog_min_ruby(project_root, rubygems)
      configured = minimum_ruby_token(rubygems["min_ruby"])
      return configured unless configured.empty?

      minimum_ruby_token(transfer_changelog_gemspec_assignment(project_root, "required_ruby_version"))
    end

    def transfer_changelog_entrypoint_require(project_root, rubygems)
      configured = rubygems["entrypoint_require"].to_s.strip
      return configured unless configured.empty?

      transfer_changelog_package_name(project_root).tr("-", "/")
    end

    def transfer_changelog_package_name(project_root)
      transfer_changelog_gemspec_assignment(project_root, "name").to_s.strip.then do |name|
        name.empty? ? File.basename(project_root.to_s) : name
      end
    end

    def transfer_changelog_gemspec_assignment(project_root, field)
      path = Dir.glob(File.join(project_root, "*.gemspec")).min
      return nil unless path

      gemspec_assignment_records(File.read(path)).find { |record| record.fetch(:field) == field }&.fetch(:value)
    rescue SystemCallError, Error
      nil
    end

    def transfer_changelog_entry_applies?(entry, context)
      filter = entry[:filter]
      return true unless filter

      transfer_changelog_filter_applies?(filter, context)
    end

    def transfer_changelog_filter_applies?(filter, context)
      Array(filter.fetch(:predicates)).all? do |predicate|
        field = predicate.fetch(:field)
        type = transfer_changelog_filter_field_types.fetch(field) do
          raise Error, "Unknown transfer changelog filter field #{field.inspect}"
        end
        actual = context.fetch(field) do
          raise Error, "Transfer changelog context omitted #{field.inspect}"
        end
        transfer_changelog_filter_predicate_applies?(type, actual, predicate.fetch(:operator), predicate.fetch(:value))
      end
    end

    def transfer_changelog_filter_field_types
      TRANSFER_CHANGELOG_FILTER_FIELD_TYPES
    end

    def transfer_changelog_filter_predicate_applies?(type, actual, operator, expected)
      case type
      when :boolean
        raise Error, "Invalid boolean transfer changelog filter value #{expected.inspect}" unless %w[true false].include?(expected)
        raise Error, "Invalid boolean transfer changelog filter operator #{operator.inspect}" unless %w[= !=].include?(operator)

        (operator == "=") ? actual == (expected == "true") : actual != (expected == "true")
      when :version
        actual_version = Gem::Version.new(actual.to_s)
        expected_version = Gem::Version.new(expected.to_s)
        {"=" => actual_version == expected_version, "!=" => actual_version != expected_version, ">" => actual_version > expected_version, ">=" => actual_version >= expected_version, "<" => actual_version < expected_version, "<=" => actual_version <= expected_version}.fetch(operator) do
          raise Error, "Invalid version transfer changelog filter operator #{operator.inspect}"
        end
      when :enum
        raise Error, "Invalid enum transfer changelog filter operator #{operator.inspect}" unless %w[= !=].include?(operator)

        (operator == "=") ? actual.to_s == expected : actual.to_s != expected
      else
        raise Error, "Unknown transfer changelog filter type #{type.inspect}"
      end
    rescue ArgumentError
      raise Error, "Invalid version transfer changelog filter value #{expected.inspect}"
    end

    def changelog_transfer_entries_after(entries, key)
      all_entries = Array(entries)
      index = all_entries.index { |entry| entry.fetch(:key).to_s == key.to_s }
      return all_entries if index.nil?

      all_entries[(index + 1)..].to_a
    end

    def changelog_transfer_key_date(key)
      parsed = parse_changelog_transfer_key(key)
      return nil unless parsed

      date = parsed.fetch(:date)
      "#{date[0, 4]}-#{date[4, 2]}-#{date[6, 2]}"
    end

    def changelog_transfer_entries(template_root)
      path = File.join(template_root, TRANSFER_CHANGELOG_TEMPLATE_PATH)
      return [] unless File.file?(path)

      content = File.read(path)
      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: path)
      sections = context.structural_owners(owner_scope: :heading_sections).select do |owner|
        owner.level == 2 && changelog_transfer_section_map.key?(owner.heading_text.to_s.strip)
      end
      list_items = context.structural_owners(owner_scope: :list_items)
      ordered_sections = sections.sort_by { |section| section.location.start_line }
      entries = ordered_sections.each_with_index.flat_map do |section, index|
        heading = changelog_transfer_section_map.fetch(section.heading_text.to_s.strip)
        next_section = ordered_sections[index + 1]
        section_end_line = next_section ? next_section.location.start_line - 1 : section.location.end_line
        list_items.filter_map do |item|
          next unless item.depth == 1
          next unless item.location.start_line > section.location.start_line
          next unless item.location.end_line <= section_end_line

          payload = changelog_transfer_list_item_payload(item.source)
          parsed = parse_changelog_transfer_line(payload)
          lines = item.source.lines.map { |line| line.chomp.rstrip }
          lines[0] = changelog_transfer_list_item_line(item.source, parsed.fetch(:rendered_payload))
          {
            key: parsed.fetch(:key),
            section: heading,
            lines: lines,
            filter: parsed[:filter]
          }
        end
      end
      validate_changelog_transfer_entries!(entries, path)
      entries.sort_by { |entry| entry.fetch(:key).to_s }
    end

    def changelog_transfer_section_map
      CHANGELOG_STANDARD_HEADINGS.to_h do |heading|
        [heading.delete_prefix("### ").strip, heading]
      end
    end

    def changelog_transfer_line_parser
      Thread.current.thread_variable_get(:kettle_jem_transfer_changelog_line_parser) ||
        Thread.current.thread_variable_set(:kettle_jem_transfer_changelog_line_parser, TransferChangelogLineParser.new)
    end

    def changelog_transfer_filter_parser
      Thread.current.thread_variable_get(:kettle_jem_transfer_changelog_filter_parser) ||
        Thread.current.thread_variable_set(:kettle_jem_transfer_changelog_filter_parser, TransferChangelogFilterParser.new)
    end

    def changelog_transfer_list_item_payload(source)
      stripped = source.to_s.lines.first.to_s.lstrip.chomp
      %w[- *].each do |marker|
        prefix = "#{marker} "
        return stripped.delete_prefix(prefix) if stripped.start_with?(prefix)
      end

      stripped
    end

    def parse_changelog_transfer_line(payload)
      parsed = changelog_transfer_line_parser.parse(payload.to_s)
      key_data = parsed.fetch(:key)
      date = key_data.fetch(:date).to_s
      sequence = key_data.fetch(:sequence).to_s
      key = "kettle-jem-template-#{date}-#{sequence}"
      filter = parsed[:filter] ? parse_changelog_transfer_filter(parsed.fetch(:filter).to_s) : nil
      {
        key: key,
        date: date,
        sequence: sequence,
        message: parsed.fetch(:message).to_s,
        rendered_payload: "#{key} - #{parsed.fetch(:message)}"
      }.tap { |entry| entry[:filter] = filter if filter }
    end

    def parse_changelog_transfer_filter(payload)
      parsed = changelog_transfer_filter_parser.parse(payload.to_s)
      predicates = (parsed.is_a?(Array) ? parsed : [parsed]).map do |node|
        predicate = node.fetch(:predicate).fetch(:predicate)
        {
          field: predicate.fetch(:field).to_s,
          operator: predicate.fetch(:operator).to_s,
          value: predicate.fetch(:value).to_s
        }
      end
      {predicates: predicates}
    end

    def changelog_transfer_list_item_line(source, rendered_payload)
      first_line = source.to_s.lines.first.to_s
      indentation = first_line.each_char.take_while { |character| character.match?(" ") || character.match?("\t") }.join
      marker = first_line.lstrip.start_with?("* ") ? "*" : "-"
      "#{indentation}#{marker} #{rendered_payload}"
    end

    def parse_changelog_transfer_key(key)
      parse_changelog_transfer_line("#{key} - placeholder")
    rescue Parslet::ParseFailed
      nil
    end

    def validate_changelog_transfer_entries!(entries, path)
      keys = entries.map { |entry| entry.fetch(:key).to_s }
      duplicates = keys.tally.select { |_key, count| count > 1 }.keys
      raise Error, "Duplicate transfer changelog key(s) in #{path}: #{duplicates.join(", ")}" if duplicates.any?
    end

    def changelog_transfer_key(line)
      payload = changelog_transfer_list_item_payload(line)
      parse_changelog_transfer_line(payload)&.fetch(:key)
    rescue Parslet::ParseFailed
      nil
    end

    def apply_changelog_transfer_entries(content, entries, excluded_keys: [])
      Kettle::Changelog::TransferMerger.apply(
        content: normalize_changelog(content, {}),
        entries: entries,
        excluded_keys: excluded_keys
      )
    end

    def remove_excluded_changelog_transfer_entries(content, excluded_keys)
      excluded = Array(excluded_keys).map(&:to_s).reject(&:empty?).to_set
      return content if excluded.empty?

      lines = markdown_source_lines(content)
      removals = changelog_existing_transfer_occurrences(content).filter_map do |occurrence|
        key = occurrence.fetch(:key).to_s
        next unless excluded.include?(key)

        (occurrence.fetch(:start_line)..occurrence.fetch(:end_line))
      end
      return content if removals.empty?

      lines.each_with_index.reject do |_line, index|
        line_number = index + 1
        removals.any? { |range| range.cover?(line_number) }
      end.map(&:first).join("\n").then { |text| ensure_trailing_newline(text.gsub(/\n{3,}/, "\n\n")) }
    end

    def changelog_existing_transfer_occurrences(content)
      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "CHANGELOG.md")
      release_sections = context.structural_owners(owner_scope: :heading_sections)
        .select { |owner| owner.level == 2 }
        .sort_by { |owner| owner.location.start_line }
      list_items = context.structural_owners(owner_scope: :list_items)
      list_items.filter_map do |item|
        next unless item.depth == 1

        key = changelog_transfer_key(item.source)
        next unless key

        release = changelog_release_section_for_item(release_sections, item)
        next unless release

        {
          key: key,
          release_heading: "## #{release.heading_text}",
          start_line: item.location.start_line,
          end_line: item.location.end_line
        }
      end
    end

    def changelog_release_section_for_item(release_sections, item)
      release_sections.each_with_index.find do |section, index|
        next_section = release_sections[index + 1]
        section_end_line = next_section ? next_section.location.start_line - 1 : section.location.end_line
        item.location.start_line > section.location.start_line &&
          item.location.end_line <= section_end_line
      end&.first
    end

    def insert_changelog_transfer_entries_in_release(lines, heading, entries)
      heading_index = lines.index { |line| line.to_s == heading.to_s }
      heading_index = changelog_unreleased_line_index(lines) if heading_index.nil?
      return lines if heading_index.nil?

      release_end = changelog_unreleased_end_index(lines, heading_index)
      release_body = lines[(heading_index + 1)...release_end] || []
      release_preamble = changelog_section_preamble(release_body)
      items = changelog_unreleased_items(release_body)
      entries.group_by { |entry| entry.fetch(:section, "### Changed") }.each do |section, section_entries|
        section = CHANGELOG_STANDARD_HEADINGS.include?(section) ? section : "### Changed"
        items[section] ||= []
        items[section].pop while items[section].any? && items[section].last.to_s.strip.empty?
        items[section] << "" if items[section].any?
        section_entries.each do |entry|
          items[section].concat(Array(entry.fetch(:lines)).map(&:rstrip))
        end
      end

      lines[0...heading_index] +
        build_changelog_section(lines.fetch(heading_index), release_preamble, items) +
        lines[release_end..].to_a
    end

    def changelog_section_preamble(body_lines)
      body_lines.take_while { |line| !line.to_s.start_with?("### ") }.map(&:rstrip)
    end

    def build_changelog_section(heading, preamble, items)
      lines = [heading.rstrip, ""]
      preamble_lines = Array(preamble).map(&:rstrip)
      preamble_lines.pop while preamble_lines.any? && preamble_lines.last.to_s.strip.empty?
      if preamble_lines.any?
        lines.concat(preamble_lines)
        lines << ""
      end
      section_lines = build_changelog_unreleased_section(heading, items)
      lines.concat(section_lines.drop(2))
    end

    def changelog_transfer_keys(content)
      content.to_s.scan(CHANGELOG_TRANSFER_KEY_SCAN_PATTERN).to_set
    end

    def changelog_bullet_line?(line)
      stripped = line.to_s.lstrip
      stripped.start_with?("- ", "* ")
    end

    def collect_changelog_list_item(lines, start_index)
      line = lines.fetch(start_index).to_s
      base_indent = line.length - line.lstrip.length
      item_lines = [line.rstrip]
      index = start_index + 1
      in_fence = false
      while index < lines.length
        current = lines.fetch(index).to_s
        current_indent = current.length - current.lstrip.length
        break if !in_fence && changelog_heading_line?(current)
        break if !in_fence && changelog_bullet_line?(current) && current_indent <= base_indent

        if current.lstrip.start_with?("```")
          in_fence = !in_fence
          item_lines << current.rstrip
          index += 1
          next
        end

        break unless in_fence || current.strip.empty? || current_indent > base_indent

        item_lines << current.rstrip
        index += 1
      end
      [item_lines, index]
    end

    def changelog_heading_line?(line)
      stripped = line.to_s.lstrip
      marker, text = stripped.split(" ", 2)
      !text.to_s.empty? && marker.to_s.each_char.all? { |char| char == "#" }
    end

    def changelog_unreleased_heading?(heading_text)
      text = heading_text.to_s.strip
      text = text[1...-1] if text.start_with?("[") && text.end_with?("]")
      text.casecmp("Unreleased").zero?
    end

    def synchronize_managed_block(content, facts)
      replacement = facts.dig(:generated_blocks, :shunted_gemfile) || [
        MANAGED_BLOCK_OPEN,
        "# package: #{facts.fetch(:package).fetch(:name)}",
        "# generated by kettle-jem vNext",
        MANAGED_BLOCK_CLOSE,
        ""
      ].join("\n")
      replace_ruby_managed_block(content.to_s, replacement)
    end

    def execute_recipe(project_root:, recipe:, facts:, files:, decision_policy:, env: ENV, template_contents: nil)
      relative_path = recipe.fetch(:target_path)
      destination_existed = File.exist?(File.join(project_root, relative_path))
      original = files.fetch(relative_path, "")
      deletion = rakefile_scaffold_cleanup_recipe?(recipe) ? rakefile_scaffold_cleanup(original, facts) : nil
      readme_timings = []
      final = with_readme_timing_context(relative_path, readme_timings) do
        case recipe.fetch(:name)
        when "readme_metadata"
          synchronize_readme(original, facts, project_root: project_root)
        when "changelog_unreleased"
          apply_changelog_transfer_entries(
            normalize_changelog(original, facts),
            facts.to_h.dig(:changelog, :transfer_entries),
            excluded_keys: facts.to_h.dig(:changelog, :excluded_transfer_keys)
          )
        when "generated_block_sync"
          synchronize_managed_block(original, facts)
        when "github_funding_yml"
          synchronize_github_funding_yml(original, facts)
        when "github_actions_ci"
          synchronize_github_actions_ci(original, facts)
        when "github_actions_framework_ci"
          synchronize_github_actions_framework_ci(original, facts)
        when GITHUB_ACTIONS_FRAMEWORK_GEMFILE_RECIPE
          synchronize_github_actions_framework_gemfile(recipe.fetch(:target_path), facts)
        when "github_actions_coverage_ci"
          synchronize_github_actions_coverage_ci(original, facts)
        when GITHUB_ACTIONS_OBSOLETE_WORKFLOW_CLEANUP_RECIPE
          ""
        when GITHUB_ACTIONS_OPT_IN_WORKFLOW_CLEANUP_RECIPE
          ""
        when OPENCOLLECTIVE_DISABLED_FILE_CLEANUP_RECIPE
          ""
        when TEMPLATE_LEGACY_DESTINATION_CLEANUP_RECIPE
          ""
        when TEMPLATE_OBSOLETE_LICENSE_CLEANUP_RECIPE
          ""
        when TEMPLATE_SHIM_PROFILE_CLEANUP_RECIPE
          ""
        when GITHUB_ACTIONS_WORKFLOW_SNIPPETS_RECIPE
          synchronize_github_actions_workflow_snippets(original, facts: facts)
        when "kettle_config_bootstrap"
          apply_kettle_config_bootstrap(project_root, recipe, env: env, template_contents: template_contents)
        when TEMPLATE_SOURCE_PREFERENCE_RECIPE
          original
        when TEMPLATE_SOURCE_APPLICATION_RECIPE
          apply_template_source(project_root, recipe, original, facts: facts, env: env, template_contents: template_contents)
        when "rakefile_scaffold_cleanup"
          deletion.fetch(:content)
        else
          original
        end
      end
      final = normalize_generated_rakefile(final) if relative_path == "Rakefile"
      final = ensure_trailing_newline(final) unless delete_file_recipe?(recipe)

      template_content = recipe_template_content(project_root, recipe, template_contents: template_contents)
      request = content_recipe_execution_request(
        recipe_name: recipe.fetch(:primitive),
        recipe_version: "1",
        relative_path: relative_path,
        provider_family: recipe.fetch(:provider_family),
        provider_backend: recipe[:provider_backend],
        template_content: template_content,
        destination_content: original,
        steps: [content_recipe_step(recipe)],
        runtime_context: recipe_runtime_context(recipe, facts, deletion),
        metadata: {packaging_recipe: recipe.fetch(:name), project_root: project_root.to_s}
      )
      changed = delete_file_recipe?(recipe) || final != original
      metadata = recipe_report_metadata(recipe).merge(destination_existed: destination_existed)
      decision_evaluation = recipe_decision_evaluation(
        decision_policy: decision_policy,
        recipe: recipe,
        changed: changed,
        destination_existed: destination_existed
      )
      if DECISION_NO_WRITE_ACTIONS.include?(decision_evaluation.fetch(:selected_action))
        final = original
        changed = false
        deletion = nil
      end
      if github_workflow_template_recipe?(recipe)
        stale_pins = stale_github_workflow_template_pin_records(relative_path, final, original)
        metadata[:stale_github_workflow_template_pins] = stale_pins unless stale_pins.empty?
      end
      step_report = content_recipe_step_report(recipe: recipe, request: request, original: original, final: final, changed: changed, deletion: deletion)
      metadata[:decision_evaluation] = decision_evaluation
      metadata[:readme_timings] = readme_timings unless readme_timings.empty?
      report = content_recipe_execution_report(
        request: request,
        final_content: final,
        changed: changed,
        step_reports: [step_report],
        diagnostics: [],
        metadata: metadata
      )

      {
        recipe_name: recipe.fetch(:name),
        relative_path: relative_path,
        changed: changed,
        request_envelope: content_recipe_execution_request_envelope(request),
        report_envelope: content_recipe_execution_report_envelope(report),
        final_content: final,
        metadata: metadata,
        decision_evaluation: decision_evaluation,
        diagnostics: []
      }
    end

    def rakefile_scaffold_cleanup_recipe?(recipe)
      recipe.fetch(:name) == "rakefile_scaffold_cleanup"
    end

    def rakefile_scaffold_cleanup(content, facts)
      return {content: content.to_s, delete_selectors: []} if facts[:template_profile].to_s == MONOREPO_ROOT_TEMPLATE_PROFILE

      delete_rakefile_scaffold(content)
    end

    def content_recipe_step(recipe)
      step = {
        step_id: recipe.fetch(:name),
        step_kind: recipe.fetch(:primitive),
        name: recipe.fetch(:name),
        provider_family: recipe.fetch(:provider_family),
        metadata: {target_path: recipe.fetch(:target_path)}
      }
      step[:provider_backend] = recipe[:provider_backend] if recipe[:provider_backend]
      if recipe.fetch(:primitive) == "supplied_source_selector_deletion"
        step[:step_kind] = "native_policy"
        step[:policy] = {
          policy_kind: "delete_supplied_structural_owners",
          required_context: "delete_selectors",
          operation: "delete",
          selector_family: "structural_owner_range",
          normalize_blank_lines: true
        }
      end
      step
    end

    def content_recipe_step_report(recipe:, request:, original:, final:, changed:, deletion: nil)
      operation_profile = Ast::Merge.structured_edit_operation_profile(
        operation_kind: recipe.fetch(:primitive),
        known_operation_kind: true,
        source_requirement: "destination_content",
        destination_requirement: "relative_path",
        replacement_source: "runtime_context",
        captures_source_text: false,
        supports_if_missing: true,
        operation_family: "kettle-jem"
      )
      result = Ast::Merge.structured_edit_result(
        operation_kind: recipe.fetch(:primitive),
        updated_content: final,
        changed: changed,
        operation_profile: operation_profile
      )
      application = Ast::Merge.structured_edit_application(request: request, result: result)
      {
        step_id: recipe.fetch(:name),
        step_kind: recipe.fetch(:primitive),
        status: changed ? "applied" : "unchanged",
        changed: changed,
        input_content: original,
        output_content: final,
        application: application,
        diagnostics: [],
        metadata: step_report_metadata(recipe, deletion).merge(
          ruby_template_policy_report(recipe: recipe, request: request, original: original, final: final)
        )
      }
    end

    def ruby_template_policy_report(recipe:, request:, original:, final:)
      return {} unless recipe.fetch(:primitive) == "supplied_template_source_application"

      file_type = template_file_type(recipe)
      return {} unless RUBY_TEMPLATE_POLICY_FILE_TYPES.include?(file_type)

      template_content = request.fetch(:template_content, "")
      report = {
        policy_kind: "kettle_jem_ruby_template_policy",
        file_type: file_type.to_s
      }
      operations = case file_type
      when :gemfile
        gemfile_policy_operations(template_content, original, final, request)
      when :gemspec
        gemspec_policy_operations(template_content, original, final, request)
      when :appraisals
        appraisals_policy_operations(template_content, original, final, request)
      end
      report[:operations] = operations
      {ruby_template_policy: report}
    end

    def gemfile_policy_operations(template_content, original, final, request)
      package_name = runtime_context_value(request, :package, :name).to_s
      deleted = gemfile_dependency_names("#{template_content}\n#{original}") - gemfile_dependency_names(final)
      expected = GEMFILE_POLICY_SELF_DEPENDENCIES.dup
      expected << package_name unless package_name.empty?
      [
        {
          operation: "delete_dependency_declarations",
          deleted_gems: (deleted & expected).sort
        }
      ]
    end

    def appraisals_policy_operations(template_content, original, final, request)
      package_name = runtime_context_value(request, :package, :name).to_s
      min_ruby = minimum_ruby_token(runtime_context_value(request, :ci, :test_min_ruby) || runtime_context_value(request, :rubygems, :min_ruby))
      source = "#{template_content}\n#{original}"
      [
        {
          operation: "merge_appraisal_blocks",
          inserted_appraisals: (appraisal_names(template_content) - appraisal_names(original)).sort,
          preserved_destination_appraisals: (appraisal_names(original) - appraisal_names(template_content) & appraisal_names(final)).sort
        },
        {
          operation: "delete_self_dependency_declarations",
          deleted_dependency_count: [gemfile_dependency_names(source).count(package_name) - gemfile_dependency_names(final).count(package_name), 0].max
        },
        {
          operation: "prune_minimum_ruby_appraisals",
          min_ruby: min_ruby,
          deleted_appraisals: (ruby_appraisal_names_below(original, min_ruby) - appraisal_names(final)).sort
        }
      ]
    end

    def gemspec_policy_operations(template_content, original, final, request)
      template_receiver = gemspec_block_param(template_content) || "spec"
      destination_receiver = gemspec_block_param(original) || "spec"
      package_name = runtime_context_value(request, :package, :name).to_s
      self_dependency_names = gemspec_self_dependency_names(request, package_name)
      operations = [
        {
          operation: "preserve_project_fields",
          preserved_fields: gemspec_preserved_assignments(original, receiver: destination_receiver).keys.select do |field|
            final.include?("#{template_receiver}.#{field} =")
          end.sort
        },
        {
          operation: "preserve_dependency_declarations",
          preserved_dependencies: gemspec_dependency_line_index(original, receiver: destination_receiver).keys.map(&:last).select do |gem_name|
            final.include?(%("#{gem_name}"))
          end.sort
        },
        {
          operation: "delete_self_dependency_declarations",
          deleted_dependency_count: [
            gemspec_dependency_names("#{template_content}\n#{original}").count { |name| self_dependency_names.include?(name) } -
              gemspec_dependency_names(final).count { |name| self_dependency_names.include?(name) },
            0
          ].max
        }
      ]
      version_loader_operation = gemspec_version_loader_policy_operation(original, final, request)
      operations << version_loader_operation if version_loader_operation
      if template_receiver != destination_receiver
        operations << {
          operation: "normalize_gemspec_receiver",
          from: destination_receiver,
          to: template_receiver
        }
      end
      operations
    end

    def gemspec_version_loader_policy_operation(original, final, request)
      min_ruby = minimum_ruby_token(runtime_context_value(request, :rubygems, :min_ruby))
      return if min_ruby.to_s.empty?

      modern = Gem::Version.new(min_ruby) >= MODERN_GEMSPEC_VERSION_LOADER_MIN_RUBY
      before_legacy = !gemspec_top_level_gem_version_node(original).nil?
      after_legacy = !gemspec_top_level_gem_version_node(final).nil?
      superclass_sensitive = gemspec_version_loader_superclass_sensitive?(request[:runtime_context] || request["runtime_context"] || {})
      {
        operation: "rewrite_version_loader",
        min_ruby: min_ruby,
        mode: modern ? "modern" : "legacy",
        superclass_sensitive: superclass_sensitive,
        legacy_preamble_removed: before_legacy && !after_legacy,
        legacy_preamble_present: after_legacy
      }
    rescue ArgumentError, Ast::Crispr::Error
      nil
    end

    def runtime_context_value(request, *path)
      context = request[:runtime_context] || request["runtime_context"] || {}
      path.reduce(context) do |value, key|
        break nil unless value.respond_to?(:[])

        value[key] || value[key.to_s]
      end
    end

    def gemfile_dependency_names(content)
      gemfile_gem_call_records(content).map { |record| record.fetch(:name) } + gemfile_nomono_dependency_names(content)
    end

    def gemfile_nomono_dependency_names(content)
      result = prism_parse_success(content)
      return [] unless result

      word_arrays_by_local = ruby_local_word_array_assignments(result.value)
      ruby_call_records(content, :eval_nomono_gems).flat_map do |call|
        ruby_static_string_array_value(ruby_keyword_argument_node(call, :gems), word_arrays_by_local)
      end.uniq
    end

    def ruby_local_word_array_assignments(root)
      root.breadth_first_search_all do |node|
        node.is_a?(::Prism::LocalVariableWriteNode) && ruby_word_array_node?(node.value)
      end.to_h do |node|
        [node.name.to_s, ruby_word_array_names(node.value)]
      end
    end

    def ruby_static_string_array_value(node, local_word_arrays = {})
      case node
      when ::Prism::ArrayNode
        return ruby_word_array_names(node) if ruby_word_array_node?(node)

        node.elements.map { |element| ruby_static_string_value(element) }
      when ::Prism::LocalVariableReadNode
        local_word_arrays.fetch(node.name.to_s, [])
      else
        []
      end.compact
    end

    def ruby_keyword_argument_node(call, key)
      keyword_hash = Array(call&.arguments&.arguments).find { |argument| argument.is_a?(::Prism::KeywordHashNode) }
      assoc = keyword_hash&.elements&.find do |element|
        element.respond_to?(:key) && element.key.respond_to?(:unescaped) && element.key.unescaped == key.to_s
      end
      assoc&.value
    end

    def appraisal_names(content)
      appraisal_call_records(content).map { |record| record.fetch(:name) }
    end

    def ruby_appraisal_names_below(content, min_ruby)
      return [] if min_ruby.to_s.empty?

      minimum = Gem::Version.new(min_ruby.to_s)
      appraisal_names(content).select do |name|
        version = ruby_appraisal_name_version(name)
        version && version < minimum
      end
    rescue ArgumentError
      []
    end

    def read_project_files(project_root, pack)
      pack.fetch(:recipes).map { |recipe| recipe.fetch(:target_path) }.uniq.to_h do |relative_path|
        path = File.join(project_root, relative_path)
        [relative_path, File.exist?(path) ? File.read(path) : ""]
      end
    end

    def read_template_source_files(project_root, pack)
      pack.fetch(:recipes).filter_map { |recipe| recipe_template_content_path(project_root, recipe) }.uniq.to_h do |path|
        [path, File.read(path)]
      end
    end

    def recipe_template_content(project_root, recipe, template_contents: nil)
      path = recipe_template_content_path(project_root, recipe)
      return "" unless path

      return template_contents.fetch(path) if template_contents&.key?(path)

      File.read(path)
    end

    def recipe_template_content_path(project_root, recipe)
      return unless TEMPLATE_CONTENT_PRIMITIVES.include?(recipe.fetch(:primitive))

      preference = recipe.fetch(:template_preference)
      File.join(
        preference.fetch(:source_root_path, project_root),
        preference.fetch(:source_relative_path, preference.fetch(:selected_source))
      )
    end

    def normalize_generated_rakefile(content)
      return "" if content.to_s.empty?

      stripped = strip_orphaned_rake_task_requires(content.to_s)
      spaced = normalize_rakefile_section_spacing(stripped)
      ensure_trailing_newline(spaced.rstrip)
    end

    def normalize_rakefile_section_spacing(content)
      content.to_s.lines.each_with_object([]) do |line, normalized|
        if line.start_with?("### ")
          normalized.pop while normalized.length > 1 && normalized[-1].strip.empty? && normalized[-2].strip.empty?
        end
        normalized << line
      end.join
    end

    def strip_orphaned_rake_task_requires(content)
      remove_indexes = Set.new
      ruby_top_level_require_records(content).each do |record|
        next unless RAKEFILE_GUARDED_REQUIRE_NAMES.include?(record.fetch(:name))

        (record.fetch(:start_line)..record.fetch(:end_line)).each { |line_number| remove_indexes << (line_number - 1) }
      end
      content.to_s.lines.each_with_index.reject { |_line, index| remove_indexes.include?(index) }.map(&:first).join
    end

    def apply_template_source(project_root, recipe, original, facts: nil, env: ENV, template_contents: nil)
      strategy = recipe.dig(:template_preference, :strategy).to_s
      return original if strategy == "keep_destination"

      content = recipe_template_content(project_root, recipe, template_contents: template_contents)
      return finalize_github_workflow_template(content, facts) if strategy == "raw_copy" && github_workflow_template_recipe?(recipe)
      return finalize_template_source_content(recipe, content) if strategy == "raw_copy"

      resolved = recipe.fetch(:resolved_template_content) do
        resolve_template_tokens(
          content,
          recipe.fetch(:template_tokens, {}),
          scan_unresolved: unresolved_template_scan?(recipe)
        )
      end
    rescue ArgumentError => e
      raise ArgumentError, "#{recipe.fetch(:target_path)}: #{e.message}"
    else
      resolved = prepare_readme_template(resolved, recipe[:readme_style]) if recipe.fetch(:target_path) == "README.md"
      resolved = prepare_github_workflow_template(resolved, recipe, facts)
      if recipe.fetch(:target_path) == "README.md" && (strategy.empty? || strategy == "merge")
        merged_readme = with_readme_timing("readme.merge_template") do
          merge_readme_template(
            template_content: resolved,
            destination_content: original,
            preserve_config: recipe.dig(:template_preference, :readme_preserve_config) || {}
          )
        end
        processed = postprocess_readme_content(
          merged_readme,
          facts,
          project_root: project_root,
          destination_content: original
        )
        return with_readme_timing("readme.append_used_link_definitions") do
          appended = append_used_markdown_link_definitions(processed, resolved)
          postprocess_readme_content(
            appended,
            facts,
            project_root: project_root,
            destination_content: original
          )
        end
      end
      if strategy.empty? || strategy == "merge"
        merged = merge_config_template_source(recipe, resolved, original, facts: facts, env: env)
        merged = preserve_mise_project_settings(recipe, merged, original, project_root: project_root, facts: facts) if template_file_type(recipe) == :toml
        return finalize_template_source_content(recipe, sync_kettle_config_env_overrides(merged, env)) if recipe.fetch(:target_path) == KETTLE_CONFIG_PATH

        merged = postprocess_funding_markdown_content(merged, facts) if recipe.fetch(:target_path) == "FUNDING.md"

        if github_workflow_template_recipe?(recipe)
          merged = preserve_github_workflow_project_settings(recipe, merged, original, project_root: project_root)
          merged = finalize_github_workflow_template(merged, facts)
          return preserve_newer_github_workflow_action_pins(merged, original)
        end

        return finalize_template_source_content(recipe, merged)
      end
      if strategy == "accept_template"
        accepted = finalize_accepted_template_source(recipe, resolved, original, facts: facts, project_root: project_root)
        accepted = preserve_github_workflow_project_settings(recipe, accepted, original, project_root: project_root) if github_workflow_template_recipe?(recipe)
        accepted = sync_kettle_config_env_overrides(accepted, env) if recipe.fetch(:target_path) == KETTLE_CONFIG_PATH
        accepted = postprocess_funding_markdown_content(accepted, facts) if recipe.fetch(:target_path) == "FUNDING.md"
        if github_workflow_template_recipe?(recipe)
          accepted = finalize_github_workflow_template(accepted, facts)
          accepted = preserve_newer_github_workflow_action_pins(accepted, original)
        end
        if recipe.fetch(:target_path) == "README.md"
          return postprocess_readme_content(
            accepted,
            facts,
            project_root: project_root,
            destination_content: original
          )
        end

        return finalize_template_source_content(recipe, accepted)
      end

      resolved = finalize_github_workflow_template(resolved, facts) if github_workflow_template_recipe?(recipe)
      resolved = postprocess_funding_markdown_content(resolved, facts) if recipe.fetch(:target_path) == "FUNDING.md"
      if recipe.fetch(:target_path) == "README.md"
        return postprocess_readme_content(
          resolved,
          facts,
          project_root: project_root,
          destination_content: original
        )
      end

      finalize_template_source_content(recipe, resolved)
    end

    def finalize_template_source_content(recipe, content)
      return finalize_rubocop_config(content) if recipe.fetch(:target_path).to_s == ".rubocop.yml"
      return finalize_kettle_config_template_source(recipe, content) if recipe.fetch(:target_path).to_s == KETTLE_CONFIG_PATH
      return normalize_simplecov_template_source(content) if recipe.fetch(:target_path).to_s == ".simplecov"
      return normalize_spec_helper_simplecov_template_source(content) if recipe.fetch(:target_path).to_s == "spec/spec_helper.rb"

      content
    end

    def finalize_kettle_config_template_source(recipe, content)
      tokens = stringify_template_tokens(recipe.fetch(:template_tokens, {}))
      resolved = resolve_template_tokens(content, tokens, scan_unresolved: false)
      assert_no_unresolved_template_tokens_in_yaml_values(resolved, KETTLE_CONFIG_PATH)
    end

    def finalize_rubocop_config(content)
      finalized = remove_yaml_scalar_path(content, %w[AllCops TargetRubyVersion])
      ensure_yaml_top_level_sequence_items(finalized, "plugins", ["rubocop-rspec"])
    end

    def finalize_accepted_template_source(recipe, content, destination_content, facts:, project_root: nil)
      case template_file_type(recipe)
      when :gemfile
        finalize_gemfile_template_source(recipe, content, destination_content, facts: facts, template_content: content)
      when :appraisals
        merge_appraisals_template_policy(content, facts: facts)
      when :gemspec
        package_name = facts.dig(:package, :name).to_s if facts
        receiver = gemspec_block_param(content) || "spec"
        pruned = remove_gemspec_self_dependency_lines(content, package_name, receiver: receiver)
        rewrite_gemspec_version_loader(pruned, facts: facts)
      when :toml
        preserve_mise_project_settings(recipe, content, destination_content, project_root: project_root)
      else
        content
      end
    end

    def preserve_mise_project_settings(recipe, content, destination_content, project_root:, facts:)
      return content unless recipe.fetch(:target_path).to_s == "mise.toml"

      thresholds = coverage_thresholds_from_mise(destination_content)
      thresholds = coverage_thresholds_from_workflow(project_root) if thresholds.empty?
      preserved = thresholds.reduce(content.to_s) do |result, (key, value)|
        replace_toml_string_scalar_line(result, key, value)
      end
      return preserved unless monorepo_subgem_template_profile?(facts)

      # Subgems generate useful coverage reports, but their narrow suites cannot
      # satisfy the aggregate thresholds enforced by the monorepo root.
      replace_toml_string_scalar_line(preserved, "K_SOUP_COV_MIN_HARD", "false")
    end

    def coverage_thresholds_from_mise(content)
      COVERAGE_THRESHOLD_KEYS.each_with_object({}) do |key, thresholds|
        value = toml_string_scalar_line_value(content, key)
        thresholds[key] = value if value
      end
    end

    def coverage_thresholds_from_workflow(project_root)
      return {} if project_root.to_s.empty?

      path = File.join(project_root.to_s, ".github", "workflows", "coverage.yml")
      return {} unless File.file?(path)

      content = File.read(path)
      COVERAGE_THRESHOLD_KEYS.each_with_object({}) do |key, thresholds|
        value = yaml_scalar_line_value(content, key)
        thresholds[key] = value.to_s.delete_prefix("\"").delete_suffix("\"") if value
      end
    end

    def toml_string_scalar_line_value(content, key)
      content.to_s.lines.each do |line|
        stripped = line.strip
        next if stripped.start_with?("#")
        next unless stripped.start_with?("#{key} ")

        value = stripped.split("=", 2).last.to_s.strip
        return value[1...-1] if value.start_with?("\"") && value.end_with?("\"")
        return value unless value.empty?
      end
      nil
    end

    def replace_toml_string_scalar_line(content, key, value)
      lines = content.to_s.lines
      lines.each_with_index do |line, index|
        next unless line.strip.start_with?("#{key} ")

        indent = line[/\A\s*/]
        lines[index] = "#{indent}#{key} = #{JSON.generate(value.to_s)}\n"
        return lines.join
      end
      content
    end

    def prepare_github_workflow_template(content, recipe, facts)
      processed = prune_disabled_github_workflow_engine_jobs(content, facts)
      return processed unless recipe.fetch(:target_path).to_s == ".github/workflows/framework-ci.yml"
      return processed if facts.to_h.dig(:ci, :framework_matrix).to_h.empty?

      synchronize_github_actions_framework_ci(processed, facts)
    end

    def prune_disabled_github_workflow_engine_jobs(content, facts)
      engines = facts.to_h.dig(:rubygems, :engines)
      return content if engines.nil?

      enabled = Array(engines).map { |engine| engine.to_s.strip.downcase }.reject(&:empty?).to_set
      return content if enabled.empty?

      disabled_job_keys = GITHUB_WORKFLOW_ENGINE_JOB_KEYS.except(*enabled).values
      return content if disabled_job_keys.empty?

      delete_yaml_top_level_mapping_entries(
        content,
        parent_key: "jobs",
        child_keys: disabled_job_keys
      )
    rescue Psych::Exception
      content
    end

    def delete_yaml_top_level_mapping_entries(content, parent_key:, child_keys:)
      document = Psych.parse(content.to_s)
      # Psych returns `false` for a comment-only document under some versions.
      # Such content has no mapping to prune and must pass through unchanged.
      root = document.root if document.respond_to?(:root)
      return content unless root.is_a?(Psych::Nodes::Mapping)

      parent = yaml_mapping_value(root, parent_key)
      return content unless parent.is_a?(Psych::Nodes::Mapping)

      child_key_set = Array(child_keys).map(&:to_s).to_set
      ranges = parent.children.each_slice(2).filter_map do |key_node, value_node|
        next unless child_key_set.include?(key_node.value.to_s)

        key_node.start_line...value_node.end_line
      end
      return content if ranges.empty?

      remove_line_ranges(content, ranges)
    end

    def yaml_mapping_value(mapping, key)
      mapping.children.each_slice(2) do |key_node, value_node|
        return value_node if key_node.value.to_s == key.to_s
      end

      nil
    end

    def remove_line_ranges(content, ranges)
      delete_lines = ranges.flat_map(&:to_a).to_set
      content.to_s.lines.each_with_index.reject { |_line, index| delete_lines.include?(index) }.map(&:first).join
    end

    def preserve_github_workflow_project_settings(recipe, content, destination_content, project_root:)
      return content unless recipe.fetch(:target_path).to_s == ".github/workflows/coverage.yml"

      thresholds = coverage_thresholds_from_project_mise(project_root)
      thresholds = coverage_thresholds_from_yaml_workflow(destination_content) if thresholds.empty?
      preserved = content
      thresholds.each do |key, value|
        preserved = replace_yaml_scalar_line(preserved, key, value)
      end
      preserved
    end

    def coverage_thresholds_from_project_mise(project_root)
      return {} if project_root.to_s.empty?

      path = File.join(project_root.to_s, "mise.toml")
      return {} unless File.file?(path)

      coverage_thresholds_from_mise(File.read(path))
    end

    def coverage_thresholds_from_yaml_workflow(content)
      COVERAGE_THRESHOLD_KEYS.each_with_object({}) do |key, thresholds|
        value = yaml_scalar_line_value(content, key)
        thresholds[key] = value if value
      end
    end

    def postprocess_readme_content(content, facts, project_root: nil, destination_content: nil)
      return content unless facts

      processed = with_readme_timing("postprocess.readme_post_processor") do
        ReadmePostProcessor.process(
          content: content,
          min_ruby: minimum_ruby_token(facts.dig(:rubygems, :min_ruby)),
          engines: facts.dig(:rubygems, :engines)
        )
      end
      processed = with_readme_timing("postprocess.compatibility_summary") do
        normalize_readme_compatibility_summary(
          processed,
          facts.dig(:rubygems, :engines),
          minimum_ruby_token(facts.dig(:rubygems, :min_ruby))
        )
      end
      processed = with_readme_timing("postprocess.project_heading") { normalize_readme_project_heading(processed, facts) }
      processed = with_readme_timing("postprocess.synopsis_heading") { normalize_readme_synopsis_heading(processed, facts) }
      processed = with_readme_timing("postprocess.conditional_blocks") { apply_readme_conditional_blocks(processed, facts) }
      processed = with_readme_timing("postprocess.badge_policy") { apply_readme_badge_policy(processed, facts) }
      processed = with_readme_timing("postprocess.rubygems_download_badges") do
        normalize_readme_rubygems_download_badges(processed)
      end
      processed = with_readme_timing("postprocess.logo_link_prune") { prune_unused_readme_logo_link_definitions(processed) }
      processed = with_readme_timing("postprocess.kloc_badge") do
        apply_readme_kloc_badge(processed, facts, project_root, destination_content: destination_content)
      end
      processed = with_readme_timing("postprocess.monorepo_thin_projection") { apply_monorepo_subgem_thin_readme_projection(processed, facts) }
      processed = with_readme_timing("postprocess.monorepo_subgem_recipe") { apply_monorepo_subgem_readme_recipe(processed, facts) }
      processed = with_readme_timing("postprocess.metadata_block") do
        replace_existing_markdown_managed_block(processed, "kettle-jem:metadata", readme_metadata_block(facts))
      end
      with_readme_timing("postprocess.blank_lines") { normalize_readme_blank_line_runs(processed) }
    end

    def normalize_readme_rubygems_download_badges(content)
      content.gsub("https://img.shields.io/gem/rd/", "https://img.shields.io/gem/dt/")
    end

    def normalize_readme_blank_line_runs(content)
      return Ast::Merge.normalize_blank_line_runs(content) if Ast::Merge.respond_to?(:normalize_blank_line_runs)

      collapse_excess_blank_lines(content)
    end

    def prune_unused_readme_logo_link_definitions(content)
      owners = ReadmePostProcessor.markdown_structural_owners(content, :inline_references, :link_definitions)
      referenced = owners.fetch(:inline_references).flat_map(&:labels).map(&:to_s).to_set
      labels = owners.fetch(:link_definitions).filter_map do |owner|
        label = owner.label.to_s
        label if label.start_with?("🖼️") && !referenced.include?(label)
      end
      return content if labels.empty?

      ReadmePostProcessor.delete_markdown_link_definitions(content, labels)
    end

    def apply_readme_kloc_badge(content, facts, project_root, destination_content: nil)
      kloc = readme_kloc_from_changelog(project_root, facts.dig(:project_runtime, :version))
      return preserve_destination_readme_kloc_badge(content, destination_content) if kloc.to_s.empty?

      content.to_s.gsub(
        README_KLOC_BADGE_PATTERN,
        "\\1#{kloc}\\3"
      )
    end

    def preserve_destination_readme_kloc_badge(content, destination_content)
      destination_match = destination_content.to_s.match(README_KLOC_BADGE_PATTERN)
      return content unless destination_match

      content.to_s.gsub(README_KLOC_BADGE_PATTERN) do
        "#{Regexp.last_match(1)}#{destination_match[2]}#{Regexp.last_match(3)}"
      end
    end

    def readme_kloc_from_changelog(project_root, version)
      return if project_root.to_s.empty? || version.to_s.empty?

      changelog_path = File.join(project_root, "CHANGELOG.md")
      return unless File.file?(changelog_path)

      changelog_coverage_kloc(current_changelog_version_section(File.read(changelog_path), version))
    end

    def current_changelog_version_section(content, version)
      version_text = version.to_s.strip
      return if version_text.empty?

      lines = content.to_s.lines
      start_index = lines.index { |line| changelog_version_heading_line?(line, version_text) }
      return unless start_index

      end_index = lines[(start_index + 1)..].to_a.index { |line| line.start_with?("## ") }
      lines[start_index...(end_index ? start_index + 1 + end_index : lines.length)].join
    end

    def changelog_version_heading_line?(line, version)
      text = line.to_s.strip
      return false unless text.start_with?("## ")

      heading = text.delete_prefix("## ").strip
      heading = heading[1...heading.index("]")] if heading.start_with?("[") && heading.include?("]")
      heading == version || heading.start_with?("#{version} ")
    end

    def changelog_coverage_kloc(section)
      return if section.to_s.empty?

      match = section.to_s.match(CHANGELOG_COVERAGE_KLOC_PATTERN)
      return unless match

      format("%.3f", match[1].to_i.to_f / 1000.0)
    end

    def apply_readme_conditional_blocks(content, facts)
      open_collective_enabled = !facts.dig(:funding, :open_collective_disabled)
      processed = apply_markdown_conditional_block(content, "OPEN_COLLECTIVE", keep: open_collective_enabled)
      processed = apply_markdown_conditional_block(processed, "NO_OPEN_COLLECTIVE", keep: !open_collective_enabled)
      processed = apply_markdown_conditional_block(
        processed,
        "FUNDING_TIDELIFT",
        keep: funding_platform_enabled?(facts.dig(:funding, :platforms), "tidelift")
      )
      star_history_enabled = facts.dig(:repository, :star_history, :enabled) == true
      return processed if star_history_enabled

      delete_markdown_with_ast_crispr(
        processed,
        Ast::Crispr::Markdown::Markly::Selectors.html_details(
          summary_text: "⭐️ Star History",
          limit: {at_least: 0}
        )
      )
    end

    def postprocess_funding_markdown_content(content, facts)
      open_collective_enabled = !facts.dig(:funding, :open_collective_disabled)
      processed = apply_markdown_conditional_block(content, "OPEN_COLLECTIVE", keep: open_collective_enabled)
      processed = apply_markdown_conditional_block(processed, "NO_OPEN_COLLECTIVE", keep: !open_collective_enabled)
      funding_platforms = facts.dig(:funding, :platforms)
      if facts.dig(:funding, :open_collective_disabled)
        processed = remove_readme_badge_and_refs(
          processed,
          README_OPEN_COLLECTIVE_FUNDING_BADGES,
          README_OPEN_COLLECTIVE_LINK_LABELS
        )
      end
      README_FUNDING_BADGE_POLICIES.each do |platform, policy|
        next if funding_platform_enabled?(funding_platforms, platform)

        processed = policy.fetch(:badges).reduce(processed) do |badge_content, badge|
          remove_readme_badge_and_refs(badge_content, badge, policy.fetch(:labels))
        end
      end
      processed
    end

    def apply_readme_badge_policy(content, facts)
      processed = with_readme_timing("badge_policy.codetriage") do
        remove_readme_badge_and_refs(content, README_CODETRIAGE_BADGE, README_CODETRIAGE_LINK_LABELS)
      end
      if facts.dig(:readme_style, :fossa_project).to_s.empty?
        processed = with_readme_timing("badge_policy.fossa") do
          remove_readme_badge_and_refs(processed, README_FOSSA_BADGE, README_FOSSA_LINK_LABELS)
        end
      end
      if Array(facts.dig(:readme_style, :disabled_integrations)).map(&:to_s).include?(SKYWALKING_EYES_INTEGRATION)
        processed = with_readme_timing("badge_policy.license_eye") do
          remove_readme_badge_and_refs(
            processed,
            README_LICENSE_EYE_WORKFLOW_BADGE,
            README_LICENSE_EYE_WORKFLOW_LINK_LABELS
          )
        end
      end
      if facts.dig(:funding, :open_collective_disabled)
        processed = with_readme_timing("badge_policy.open_collective") do
          remove_readme_badge_and_refs(
            processed,
            README_OPEN_COLLECTIVE_FUNDING_BADGES,
            README_OPEN_COLLECTIVE_LINK_LABELS
          )
        end
      end
      funding_platforms = facts.dig(:funding, :platforms)
      README_FUNDING_BADGE_POLICIES.each do |platform, policy|
        next if funding_platform_enabled?(funding_platforms, platform)

        processed = with_readme_timing("badge_policy.#{platform}") do
          policy.fetch(:badges).reduce(processed) do |badge_content, badge|
            remove_readme_badge_and_refs(badge_content, badge, policy.fetch(:labels))
          end
        end
      end
      Array(facts.dig(:readme_style, :disabled_integrations)).each do |integration|
        patterns = README_INTEGRATION_BADGE_PATTERNS.fetch(integration.to_s, [])
        labels = README_INTEGRATION_LINK_LABELS.fetch(integration.to_s, [])
        processed = patterns.reduce(processed) { |content, pattern| content.gsub(pattern, "") }
        processed = ReadmePostProcessor.delete_markdown_link_definitions(processed, labels)
      end
      processed
    end

    def normalize_readme_compatibility_summary(content, engines, min_ruby = "")
      enabled = Array(engines).map { |engine| engine.to_s.strip.downcase }.reject(&:empty?).uniq
      return content if enabled.empty?

      runtime_floor = min_ruby.to_s.strip
      runtime_floor = " #{runtime_floor}+" unless runtime_floor.empty?
      runtime_engines = ["MRI Ruby#{runtime_floor}"]
      runtime_engines << "JRuby" if enabled.include?("jruby")
      runtime_engines << "TruffleRuby" if enabled.include?("truffleruby") || enabled.include?("truby")
      description = runtime_engines.one? ? runtime_engines.first : runtime_engines[0...-1].join(", ") + ", and #{runtime_engines.last}"
      content.to_s.sub(
        /Compatible with MRI Ruby [^\n]+\./,
        "Compatible with #{description}."
      )
    end

    def remove_readme_badge_and_refs(content, badge_source, link_labels)
      ensure_runtime_dependencies!
      processed = content.to_s.gsub(badge_source, "").lines.map(&:rstrip).join("\n")
      processed = "#{processed}\n" if content.to_s.end_with?("\n")
      ReadmePostProcessor.delete_markdown_link_definitions(processed, Array(link_labels))
    end

    def apply_markdown_conditional_block(content, name, keep:)
      ensure_runtime_dependencies!
      start_text = "KJ:#{name}:START"
      end_text = "KJ:#{name}:END"
      if keep
        delete_markdown_with_ast_crispr_batch(
          content,
          Ast::Crispr::Markdown::Markly::Selectors.html_comment(text: start_text, limit: {at_least: 0}),
          Ast::Crispr::Markdown::Markly::Selectors.html_comment(text: end_text, limit: {at_least: 0})
        )
      else
        delete_markdown_with_ast_crispr(
          content,
          Ast::Crispr::Markdown::Markly::Selectors.html_comment_block(
            start_text: start_text,
            end_text: end_text,
            limit: {at_least: 0}
          )
        )
      end
    end

    def apply_monorepo_subgem_readme_recipe(content, facts)
      return content unless monorepo_subgem_template_profile?(facts)

      source_url = facts.dig(:package, :source_url).to_s
      return content if source_url.empty?

      root_doc_links = MONOREPO_SUBGEM_README_BLOB_PATHS.to_h do |path|
        [path, source_blob_url(source_url, path)]
      end
      rewrite_markdown_reference_links(content, root_doc_links)
    end

    def apply_monorepo_subgem_thin_readme_projection(content, facts)
      ensure_runtime_dependencies!
      return content unless monorepo_subgem_template_profile?(facts)

      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "README.md")
      link_definitions = context.structural_owners(owner_scope: :link_definitions)
      heading_sections = context.structural_owners(owner_scope: :heading_sections)
      removable = heading_sections.each_with_index.select do |owner, index|
        owner.level.to_i > 1 && !MONOREPO_SUBGEM_THIN_README_KEEP_HEADINGS.include?(owner.base.to_s)
      end.reject do |owner, index|
        markdown_heading_has_preserved_readme_ancestor?(heading_sections, index)
      end.map(&:first)
      projected = removable.reverse.reduce(content.to_s) do |processed, owner|
        delete_markdown_with_ast_crispr(
          processed,
          Ast::Crispr::Markdown::Markly::Selectors.heading_section(
            heading_text: owner.heading_text,
            level: owner.level,
            limit: {at_least: 0}
          )
        )
      end
      append_missing_markdown_link_definitions(projected, link_definitions)
    end

    def markdown_heading_has_preserved_readme_ancestor?(heading_sections, index)
      owner = heading_sections.fetch(index)
      ancestor_level = owner.level.to_i
      heading_sections[0...index].reverse_each do |candidate|
        next unless candidate.level.to_i < ancestor_level

        return true if README_DEFAULT_PRESERVE_SECTIONS.include?(candidate.base.to_s)

        ancestor_level = candidate.level.to_i
      end
      false
    end

    def rewrite_markdown_reference_links(content, links)
      ensure_runtime_dependencies!
      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "README.md")
      context.structural_owners(owner_scope: :link_definitions).reduce(content.to_s) do |processed, owner|
        replacement = links[owner.url.to_s]
        next processed unless replacement

        replace_markdown_with_ast_crispr(
          processed,
          Ast::Crispr::Markdown::Markly::Selectors.link_definition(label: owner.label, limit: {exactly: 1}),
          markdown_link_definition_source(owner, replacement)
        )
      end
    end

    def append_missing_markdown_link_definitions(content, definitions)
      ensure_runtime_dependencies!
      existing = Ast::Crispr::Markdown::Markly.document_context(
        content: content,
        source_label: "README.md"
      ).structural_owners(owner_scope: :link_definitions).map { |owner| owner.label.to_s }
      missing_sources = definitions.reject { |owner| existing.include?(owner.label.to_s) }.map do |owner|
        owner.source.to_s.end_with?("\n") ? owner.source.to_s : "#{owner.source}\n"
      end
      return content if missing_sources.empty?

      [content.to_s.rstrip, "", missing_sources.join.rstrip, ""].join("\n")
    end

    def append_used_markdown_link_definitions(content, definition_source)
      owners = ReadmePostProcessor.markdown_structural_owners(content, :link_definitions, :inline_references)
      existing = owners.fetch(:link_definitions).map { |owner| owner.label.to_s }.to_set
      referenced = owners.fetch(:inline_references).flat_map(&:labels).map(&:to_s).to_set
      available = ReadmePostProcessor.markdown_link_definition_owners(definition_source).to_h do |owner|
        [owner.label.to_s, owner]
      end
      missing = referenced.filter_map do |label|
        next if existing.include?(label)

        available[label]
      end
      append_missing_markdown_link_definitions(content, missing)
    end

    def delete_markdown_with_ast_crispr(content, target)
      ensure_runtime_dependencies!
      Ast::Crispr::Delete.call(content: content.to_s, target: target, source_label: "README.md").updated_content
    end

    def delete_markdown_with_ast_crispr_batch(content, *targets)
      ensure_runtime_dependencies!
      target_list = targets.flatten.compact
      return content if target_list.empty?

      Ast::Crispr::DeleteBatch.call(content: content.to_s, targets: target_list, source_label: "README.md").updated_content
    end

    def replace_markdown_with_ast_crispr(content, target, replacement)
      ensure_runtime_dependencies!
      Ast::Crispr::Replace.call(
        content: content.to_s,
        target: target,
        replacement: replacement,
        source_label: "README.md"
      ).updated_content
    end

    def markdown_link_definition_source(owner, url)
      source = "[#{owner.label}]: #{url}"
      source = "#{source} #{owner.title.dump}" if owner.title
      "#{source}\n"
    end

    def source_blob_url(source_url, path)
      base = source_url.to_s.dup
      base = base[0...-1] while base.end_with?("/")
      escaped_path = path.to_s.split("/").map { |segment| segment.split(" ").join("%20") }.join("/")
      if base.start_with?("https://gitlab.com/", "http://gitlab.com/")
        "#{base}/-/blob/main/#{escaped_path}"
      elsif base.start_with?("https://codeberg.org/", "http://codeberg.org/")
        "#{base}/src/branch/main/#{escaped_path}"
      else
        "#{base}/blob/main/#{escaped_path}"
      end
    end

    def normalize_readme_project_heading(content, facts)
      package = facts.fetch(:package, {})
      rubygems = facts.fetch(:rubygems, {})
      title = readme_title_token(package, rubygems)
      emoji = facts.dig(:project_runtime, :project_emoji).to_s
      return content if title.empty? || emoji.empty?

      lines = content.to_s.split("\n", -1)
      h1 = markdown_heading_owners(content, source_label: "README.md").find { |owner| owner.level == 1 }
      return content unless h1

      index = h1.location.start_line - 1
      lines[index] = "# #{emoji} #{title}"
      lines.join("\n")
    end

    def normalize_readme_synopsis_heading(content, facts)
      logo_row = facts.dig(:readme_logo, :h2_synopsis_logo_row).to_s
      return content if logo_row.empty?

      lines = content.to_s.split("\n", -1)
      h2 = markdown_heading_owners(content, source_label: "README.md").find do |owner|
        owner.level == 2 && owner.base.to_s == "synopsis"
      end
      return content unless h2

      index = h2.location.start_line - 1
      lines[index] = "## 🌻 Synopsis #{logo_row}"
      lines.join("\n")
    end

    def markdown_heading_owners(content, source_label: "README.md")
      ensure_runtime_dependencies!
      context = Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: source_label)
      context.structural_owners(owner_scope: :heading_sections)
    rescue Ast::Crispr::Error
      []
    end

    def prepare_readme_template(content, readme_style)
      style = readme_style || {}
      prepared = with_readme_timing("prepare.integration_badges") { prune_readme_integration_badges(content, style) }
      if style[:workflow_paths]
        prepared = with_readme_timing("prepare.workflow_post_processor") do
          ReadmePostProcessor.process(
            content: prepared,
            min_ruby: "0",
            workflow_paths: style[:workflow_paths]
          )
        end
      end
      if style[:workflow_paths]
        prepared = with_readme_timing("prepare.workflow_link_prune") do
          prune_missing_workflow_link_definitions(prepared, style[:workflow_paths])
        end
        prepared = with_readme_timing("prepare.workflow_inline_prune") do
          ReadmePostProcessor.prune_orphaned_workflow_inline_references(prepared)
        end
      end
      omitted_sections = Array(style[:omitted_sections]).map(&:to_s)
      omitted_sections << "security" if style.key?(:security_enabled) && !style[:security_enabled]
      omitted_sections << "floss_funding" if style.key?(:floss_funding_enabled) && !style[:floss_funding_enabled]
      with_readme_timing("prepare.remove_sections") do
        remove_readme_sections(prepared, omitted_sections.map { |section| section.tr("_", " ") })
      end
    end

    def prune_readme_integration_badges(content, readme_style)
      ensure_runtime_dependencies!
      integrations = Array(readme_style[:missing_integrations]) + Array(readme_style[:disabled_integrations])
      labels = []
      pruned = integrations.uniq.reduce(content.to_s) do |result, integration|
        labels.concat(README_INTEGRATION_LINK_LABELS.fetch(integration.to_s, []))
        README_INTEGRATION_BADGE_PATTERNS.fetch(integration.to_s, []).reduce(result) do |memo, pattern|
          memo.gsub(pattern, "")
        end
      end
      ReadmePostProcessor.delete_markdown_link_definitions(pruned, labels).gsub(/[ \t]{2,}/, " ")
    end

    def prune_missing_workflow_link_definitions(content, workflow_paths)
      ensure_runtime_dependencies!
      existing = Array(workflow_paths).map { |path| path.to_s.delete_prefix("./") }.to_set
      Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: "README.md")
        .structural_owners(owner_scope: :link_definitions)
        .filter_map do |owner|
          workflow_path = readme_workflow_path_from_url(owner.url)
          owner.label if !workflow_path.empty? && !existing.include?(workflow_path)
        end
        .then { |labels| ReadmePostProcessor.delete_markdown_link_definitions(content, labels) }
    end

    def readme_workflow_path_from_url(url)
      marker = "/actions/workflows/"
      path = URI.parse(url.to_s).path.to_s
      marker_index = path.index(marker)
      return "" unless marker_index

      workflow = path[(marker_index + marker.length)..].to_s.split("/").first.to_s
      workflow.empty? ? "" : ".github/workflows/#{workflow}"
    rescue URI::InvalidURIError
      ""
    end

    def remove_readme_sections(content, section_bases)
      bases = section_bases.map { |section| normalize_readme_heading(section) }.uniq
      return content if bases.empty?

      sections = markdown_sections(content).select { |section| bases.include?(section.fetch(:base)) }
      return content if sections.empty?

      lines = content.to_s.split("\n", -1)
      sections.reverse_each do |section|
        lines[section.fetch(:start)..section.fetch(:end)] = []
      end
      ensure_trailing_newline(lines.join("\n").gsub(/\n{3,}/, "\n\n").strip)
    end

    def merge_config_template_source(recipe, template_content, destination_content, facts: nil, env: ENV)
      file_type = template_file_type(recipe)
      if destination_content.to_s.strip.empty?
        if file_type == :gemfile
          return finalize_gemfile_template_source(recipe, template_content, destination_content, facts: facts, template_content: template_content)
        end
        return merge_appraisals_template_policy(template_content, facts: facts) if file_type == :appraisals
        return finalize_github_workflow_template(prune_github_workflow_matrix_by_min_ruby(template_content, facts), facts) if github_workflow_template_recipe?(recipe)

        return template_content
      end
      if destination_content == template_content
        if file_type == :gemfile
          return finalize_gemfile_template_source(recipe, destination_content, destination_content, facts: facts, template_content: template_content)
        end
        return merge_appraisals_template_policy(destination_content, facts: facts) if file_type == :appraisals

        return destination_content
      end

      case file_type
      when :gitignore
        return merge_gitignore_template_source(template_content, destination_content)
      when :gemspec
        return merge_gemspec_template_source(template_content, destination_content, facts: facts, env: env)
      when :ruby, :gemfile, :rakefile, :appraisals
        merge_destination = if recipe.fetch(:target_path).to_s == ".simplecov"
          normalize_simplecov_template_source(destination_content)
        else
          destination_content
        end
        merge_result = merge_ruby_template_source(file_type, recipe, template_content, merge_destination, facts: facts)
      when :yaml
        merge_result = Psych::Merge.merge_yaml(
          template_content,
          destination_content,
          "yaml",
          **yaml_merge_options(recipe)
        )
      when :toml
        merge_result = Citrus::Toml::Merge.merge_toml(template_content, destination_content, "toml")
      when :json, :jsonc, :json5
        merge_result = merge_json_template_source(template_content, destination_content, recipe, file_type)
      when :markdown
        return merge_changelog_template_source(template_content, destination_content, facts: facts) if recipe.fetch(:target_path) == "CHANGELOG.md"

        return template_content
      when :dotenv
        merge_result = merge_dotenv_template_source(template_content, destination_content, recipe)
      when :rbs
        merge_result = merge_rbs_template_source(template_content, destination_content, recipe)
      when :bash
        merge_result = merge_bash_template_source(template_content, destination_content, recipe)
      else
        return template_content
      end
      if merge_result[:ok]
        output = merge_result.fetch(:output)
        if file_type == :gemfile
          output = merge_gemfile_eval_bucket_entries(template_content, output, destination_content: destination_content)
          return finalize_gemfile_template_source(recipe, output, destination_content, facts: facts, template_content: template_content)
        end
        return merge_appraisals_template_policy(output, facts: facts) if file_type == :appraisals

        output = finalize_github_workflow_template(prune_github_workflow_matrix_by_min_ruby(output, facts), facts) if github_workflow_template_recipe?(recipe)
        output = normalize_simplecov_template_source(output) if recipe.fetch(:target_path).to_s == ".simplecov"
        output = normalize_spec_helper_simplecov_template_source(output) if recipe.fetch(:target_path).to_s == "spec/spec_helper.rb"
        output = normalize_spec_helper_block_bindings(output, template_content) if recipe.fetch(:target_path).to_s == "spec/spec_helper.rb"
        return output
      end

      raise adapter_failure_template_source_error(file_type, recipe) if process_result_adapter_failure?(merge_result)
      return template_content if github_workflow_template_recipe?(recipe)

      diagnostics = merge_result.fetch(:diagnostics, [])
      message = diagnostics.map { |diagnostic| diagnostic[:message] || diagnostic["message"] }.compact.join("; ")
      raise ArgumentError, "failed to merge #{file_type} template #{recipe.fetch(:target_path)}: #{message}"
    end

    def finalize_gemfile_template_source(recipe, content, destination_content, facts:, template_content:)
      modular_gemfile = modular_gemfile_template_recipe?(recipe)
      output = if modular_gemfile
        # Modular Gemfiles are dependency fragments, not aggregate project
        # Gemfiles. Preserve a dependency when a released fragment is
        # specifically named for that dependency (for example
        # mutex_m/r4/v0.3.gemfile). Local override fragments intentionally
        # retain their existing dependency-pruning behavior.
        target = recipe.fetch(:target_path).to_s
        package_name = facts.to_h.dig(:package, :name).to_s
        runtime_dependencies = package_runtime_dependency_names(facts)
        if local_gemfile_template_recipe?(recipe)
          output = remove_gemfile_dependency_blocks(content, ["rdoc"])
        else
          named_fragment_dependencies = runtime_dependencies.select do |dependency|
            target.include?(dependency.tr("-", "_"))
          end
          removable = [package_name, *(runtime_dependencies - named_fragment_dependencies)]
          output = remove_gemfile_dependency_blocks(content, removable)
          output = remove_gemfile_percent_w_entries(output, removable)
        end
        # The returned content contains the policy-preserving rewrite.
        # rubocop:disable Lint/UselessAssignment
        output = apply_commented_gem_dependency_policy(template_content, output)
        # rubocop:enable Lint/UselessAssignment
      else
        merge_gemfile_template_policy(
          content,
          facts: facts,
          template_content: template_content,
          preserve_self_word_entries: local_gemfile_template_recipe?(recipe)
        )
      end
      if recipe.fetch(:target_path).to_s == "Gemfile"
        # A merged Gemfile retains its project-specific source; an accepted
        # template owns the complete source declaration.
        unless recipe.dig(:template_preference, :strategy).to_s == "accept_template"
          output = preserve_destination_gemfile_source(output, destination_content)
        end
        output = inject_main_gemfile_recording_eval(output, facts)
        output = inject_main_gemfile_default_test_bundle(output, facts)
        output = remove_stale_main_gemfile_tree_sitter_language_pack(output, template_content)
        output = remove_stale_main_gemfile_direct_sibling_block(output, template_content)
        output = deduplicate_main_gemfile_direct_sibling_blocks(output)
        output = ensure_main_gemfile_nomono_bootstrap(output, template_content)
        output = normalize_main_gemfile_nomono_declaration(output)
        output = deduplicate_main_gemfile_eval_gemfiles(output)
        output = guard_main_gemfile_runtime_workspace_overrides(output)
        output = migrate_legacy_byebug_pair(output)
      end

      output = normalize_local_gemfile_nomono_bootstrap(output) if local_gemfile_template_recipe?(recipe)
      output = remove_gemfile_percent_w_entries(output, [facts.to_h.dig(:package, :name)]) if local_gemfile_template_recipe?(recipe)
      return output if recipe.dig(:template_preference, :strategy).to_s == "accept_template"
      return output unless local_gemfile_template_recipe?(recipe)

      output = normalize_structuredmerge_local_gems(output, template_content)
      merge_local_gem_overrides(output, destination_content, facts: facts, template_content: template_content)
    end

    def preserve_destination_gemfile_source(content, destination_content)
      destination_source = ruby_call_records(destination_content, :source).find do |call|
        call.receiver.nil? && ruby_string_argument(call)
      end
      template_source = ruby_call_records(content, :source).find do |call|
        call.receiver.nil? && ruby_string_argument(call)
      end
      return content unless destination_source && template_source

      destination_text = destination_source.location.slice
      return content if destination_text == template_source.location.slice

      replace_record_ranges(content, {
        template_source.location.start_line => {
          start_line: template_source.location.start_line,
          end_line: ruby_node_source_end_line(template_source),
          replacement: "#{destination_text}\n"
        }
      })
    end

    def migrate_legacy_byebug_pair(content)
      records = gemfile_gem_call_records(content)
      obsolete = records.select { |record| record.fetch(:name).include?("byebug") }
      return content if obsolete.empty?

      first = obsolete.min_by { |record| record.fetch(:start_line) }
      replacement = "#{content.to_s.lines.fetch(first.fetch(:start_line) - 1)[/\A\s*/]}gem \"debug\", require: false\n"
      replacements = obsolete.to_h do |record|
        source = (record == first) ? replacement : ""
        [record.fetch(:start_line), record.merge(replacement: source)]
      end
      replace_record_ranges(content, replacements)
    end

    def remove_stale_main_gemfile_tree_sitter_language_pack(content, template_content)
      return content if gemfile_declares_direct_gem?(template_content, "tree_sitter_language_pack")

      records = main_gemfile_direct_gem_records(content, "tree_sitter_language_pack")
      return content if records.empty?

      records.sort_by { |record| -record.fetch(:start_line) }.reduce(content.to_s) do |output, record|
        replace_source_range_lines(
          output,
          record.fetch(:start_line),
          expand_line_range_through_following_blanks(output, record.fetch(:end_line)),
          ""
        )
      end
    end

    def remove_stale_main_gemfile_direct_sibling_block(content, template_content)
      return content if template_content.to_s.include?("direct_sibling_gems = %w[")

      records = main_gemfile_direct_sibling_records(content)
      return content if records.empty?

      records.sort_by { |record| -record.fetch(:start_line) }.reduce(content.to_s) do |output, record|
        replace_source_range_lines(
          output,
          record.fetch(:start_line),
          expand_line_range_through_following_blanks(output, record.fetch(:end_line)),
          ""
        )
      end
    end

    def gemfile_declares_direct_gem?(content, gem_name)
      ruby_call_records(content, :gem).any? do |call|
        call.receiver.nil? && ruby_string_argument(call) == gem_name.to_s
      end
    end

    def main_gemfile_direct_gem_records(content, gem_name)
      lines = content.to_s.lines
      ruby_call_records(content, :gem).filter_map do |call|
        next unless call.receiver.nil? && ruby_string_argument(call) == gem_name.to_s

        start_line = stale_main_gemfile_gem_comment_start_line(lines, call.location.start_line, gem_name)
        {
          start_line: start_line,
          end_line: ruby_node_source_end_line(call)
        }
      end
    end

    def stale_main_gemfile_gem_comment_start_line(lines, start_line, gem_name)
      index = start_line.to_i - 2
      return start_line if index.negative?

      previous = lines.fetch(index).to_s
      return index + 1 if stale_main_gemfile_gem_comment?(previous, gem_name)

      start_line
    end

    def stale_main_gemfile_gem_comment?(line, gem_name)
      stripped = line.to_s.strip
      return false unless stripped.start_with?("#")
      return stripped.include?("TSLP") if gem_name.to_s == "tree_sitter_language_pack"

      false
    end

    def deduplicate_main_gemfile_direct_sibling_blocks(content)
      records = main_gemfile_direct_sibling_records(content)
      return content if records.length <= 1

      records[1..].sort_by { |record| -record.fetch(:start_line) }.reduce(content.to_s) do |output, record|
        replace_source_range_lines(
          output,
          record.fetch(:start_line),
          expand_line_range_through_following_blanks(output, record.fetch(:end_line)),
          ""
        )
      end
    end

    def main_gemfile_direct_sibling_records(content)
      body = prism_parse_success(content)&.value&.statements&.body || []
      assignments = body.select do |node|
        node.is_a?(::Prism::LocalVariableWriteNode) && node.name == :direct_sibling_gems
      end
      return [] if assignments.empty?

      lines = content.to_s.lines
      assignments.each_with_object([]) do |assignment, records|
        block_ifs = body.select do |node|
          node.is_a?(::Prism::IfNode) &&
            node.location.start_line > assignment.location.end_line &&
            prism_subtree_contains_call?(node, :eval_nomono_gems)
        end
        next if block_ifs.empty?

        start_line = assignment.location.start_line
        previous = lines[start_line - 2].to_s
        start_line -= 1 if previous.strip.start_with?("# Direct sibling dependencies")
        records << {start_line: start_line, end_line: block_ifs.first.location.end_line}
        block_ifs.drop(1).each do |block_if|
          records << {start_line: block_if.location.start_line, end_line: block_if.location.end_line}
        end
      end
    end

    def guard_main_gemfile_runtime_workspace_overrides(content)
      content = collapse_nested_templating_guards(content)
      content = normalize_templating_guard_indentation(content)
      records = runtime_workspace_override_records(content)
      return content if records.empty?

      output = content.to_s
      records.sort_by { |record| -record.fetch(:start_line) }.each do |record|
        source = output.lines[(record.fetch(:start_line) - 1)..(record.fetch(:end_line) - 1)].join
        guarded = [
          %(unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?),
          indent_source(source, 2).rstrip,
          "end",
          ""
        ].join("\n")
        output = replace_source_range_lines(output, record.fetch(:start_line), record.fetch(:end_line), guarded)
      end
      output
    end

    def ensure_main_gemfile_nomono_bootstrap(content, template_content)
      return content if gemfile_declares_gem?(content, "nomono")

      bootstrap_source = main_gemfile_nomono_bootstrap_source(template_content)
      return content if bootstrap_source.empty?

      lines = content.to_s.lines
      insert_line = main_gemfile_templating_eval_line(content) ||
        main_gemfile_first_eval_gemfile_line(content) ||
        main_gemfile_after_gemspec_line(content) ||
        (lines.length + 1)
      lines.insert(insert_line - 1, bootstrap_source)
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def main_gemfile_nomono_bootstrap_source(template_content)
      records = main_gemfile_nomono_requirement_records(template_content)
      call = records.fetch(:calls).first
      return "" unless call

      lines = template_content.to_s.lines
      start_line = call.fetch(:start_line)
      previous = lines[start_line - 2].to_s
      start_line -= 1 if previous.strip.start_with?("# Local workspace dependency wiring")
      lines[(start_line - 1)..(call.fetch(:end_line) - 1)].join.rstrip + "\n\n"
    end

    def main_gemfile_templating_eval_line(content)
      ruby_call_records(content, :eval_gemfile).filter_map do |call|
        next unless ruby_string_argument(call) == "gemfiles/modular/templating.gemfile"

        call.location.start_line
      end.min
    end

    def main_gemfile_first_eval_gemfile_line(content)
      ruby_call_records(content, :eval_gemfile).map { |call| call.location.start_line }.min
    end

    def main_gemfile_after_gemspec_line(content)
      ruby_call_records(content, :gemspec).map { |call| ruby_node_source_end_line(call) + 1 }.min
    end

    def deduplicate_main_gemfile_eval_gemfiles(content)
      records = ruby_call_records(content, :eval_gemfile).filter_map do |call|
        path = ruby_string_argument(call)
        next unless path

        {
          path: path,
          start_line: gemfile_eval_comment_start_line(content.to_s.lines, call.location.start_line),
          end_line: ruby_node_source_end_line(call)
        }
      end
      return content if records.length <= 1

      seen = Set.new
      duplicate_records = []
      records.reverse_each do |record|
        path = record.fetch(:path)
        if seen.include?(path)
          duplicate_records << record
        else
          seen.add(path)
        end
      end
      return content if duplicate_records.empty?

      duplicate_records.sort_by { |record| -record.fetch(:start_line) }.reduce(content.to_s) do |output, record|
        replace_source_range_lines(
          output,
          record.fetch(:start_line),
          expand_line_range_through_following_blanks(output, record.fetch(:end_line)),
          ""
        )
      end
    end

    def normalize_main_gemfile_nomono_declaration(content)
      records = main_gemfile_nomono_requirement_records(content)
      return content if records.fetch(:calls).empty?

      output = records.fetch(:assignments).sort_by { |record| -record.fetch(:start_line) }.reduce(content.to_s) do |memo, record|
        replace_source_range_lines(
          memo,
          record.fetch(:start_line),
          expand_line_range_through_following_blanks(memo, record.fetch(:end_line)),
          ""
        )
      end
      main_gemfile_nomono_requirement_records(output).fetch(:calls).sort_by { |record| -record.fetch(:start_line) }.reduce(output) do |memo, record|
        replace_source_range_lines(memo, record.fetch(:start_line), record.fetch(:end_line), "#{nomono_gemfile_declaration}\n")
      end
    end

    def main_gemfile_nomono_requirement_records(content)
      body = prism_parse_success(content)&.value&.statements&.body || []
      assignments = body.filter_map do |node|
        next unless node.is_a?(::Prism::LocalVariableWriteNode) && node.name == :nomono_requirements

        {
          start_line: node.location.start_line,
          end_line: ruby_node_source_end_line(node),
          source: node.location.slice
        }
      end
      calls = ruby_call_records(content, :gem).filter_map do |call|
        next unless ruby_string_argument(call) == "nomono"

        {
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call),
          source: call.location.slice
        }
      end
      {assignments: assignments, calls: calls.sort_by { |record| record.fetch(:start_line) }}
    end

    def collapse_nested_templating_guards(content)
      records = nested_templating_guard_records(content)
      return content if records.empty?

      output = content.to_s
      records.sort_by { |record| -record.fetch(:outer_start_line) }.each do |record|
        inner_source = output.lines[(record.fetch(:inner_start_line) - 1)..(record.fetch(:inner_end_line) - 1)].join
        inner_source = outdent_source(inner_source, 2)
        output = replace_source_range_lines(output, record.fetch(:outer_start_line), record.fetch(:outer_end_line), inner_source)
      end
      output
    end

    def normalize_templating_guard_indentation(content)
      records = templating_guard_records(content)
      return content if records.empty?

      output = content.to_s
      records.sort_by { |record| -record.fetch(:start_line) }.each do |record|
        source = output.lines[(record.fetch(:start_line) - 1)..(record.fetch(:end_line) - 1)].join
        normalized = normalize_conditional_body_indentation(source)
        next if normalized == source

        output = replace_source_range_lines(output, record.fetch(:start_line), record.fetch(:end_line), normalized)
      end
      output
    end

    def templating_guard_records(content)
      result = prism_parse_success(content)
      return [] unless result

      result.value.breadth_first_search_all do |node|
        gemfile_conditional_node?(node) && prism_subtree_contains_string?(node.predicate, "K_JEM_TEMPLATING")
      end.map do |node|
        {start_line: node.location.start_line, end_line: node.location.end_line}
      end
    end

    def normalize_conditional_body_indentation(source)
      lines = source.to_s.lines
      return source if lines.length < 3

      outer_indent = leading_space_count(lines.first)
      desired_body_indent = outer_indent + 2
      body = lines[1...-1]
      min_body_indent = body.reject { |line| line.strip.empty? }.map { |line| leading_space_count(line) }.min
      return source unless min_body_indent && min_body_indent > desired_body_indent

      remove_spaces = min_body_indent - desired_body_indent
      ([lines.first] + body.map { |line| outdent_line(line, remove_spaces) } + [lines.last]).join
    end

    def normalize_simplecov_template_source(content)
      output = normalize_simplecov_cover_predicates(content)
      output = migrate_simplecov_start_configuration(output)
      nodes = simplecov_obsolete_call_nodes(output)
      output = nodes.sort_by { |node| -node.location.start_line }.reduce(output) do |memo, node|
        replace_source_range_lines(memo, node.location.start_line, expand_line_range_through_following_blanks(memo, node.location.end_line), "")
      end
      normalize_simplecov_usage_guidance(output)
    end

    # SimpleCov's compatibility probe changed spelling between template
    # generations. Normalize the legacy AST shape before merging so the same
    # generated branch is matched instead of appended a second time.
    def normalize_simplecov_cover_predicates(content)
      result = prism_parse_success(content)
      return content unless result

      nodes = []
      result.value.breadth_first_search_all { |node| nodes << node }
      replacements = nodes.filter_map do |node|
        next unless node.is_a?(::Prism::IfNode)

        predicate = node.predicate
        next unless predicate.is_a?(::Prism::CallNode)
        next unless predicate.name == :method_defined?
        next unless predicate.receiver&.slice.to_s == "SimpleCov::Configuration"
        next unless predicate.arguments&.arguments&.first&.slice.to_s == ":cover"

        {
          start_offset: predicate.location.start_offset,
          end_offset: predicate.location.end_offset,
          replacement: "SimpleCov::Configuration.instance_methods.include?(:cover)"
        }
      end
      return content if replacements.empty?

      replace_source_offsets(content, replacements)
    end

    # SimpleCov.start was historically used as both configuration and startup.
    # The generated spec helper now owns startup, but a destination's block can
    # contain project-specific filters and formatters that must survive.
    def migrate_simplecov_start_configuration(content)
      result = prism_parse_success(content)
      return content unless result

      replacements = []
      result.value.breadth_first_search_all do |node|
        next unless simplecov_start_call_node?(node) && node.block

        replacements << {
          start_offset: node.message_loc.start_offset,
          end_offset: node.message_loc.end_offset,
          replacement: "configure"
        }
      end
      replace_source_offsets(content, replacements)
    end

    # Older template merges appended a second generated usage-comment block.
    # Keep the first block and remove only later comment-only blocks with the
    # same generated heading, leaving any coverage code or local notes intact.
    def normalize_simplecov_usage_guidance(content)
      lines = content.to_s.lines
      starts = lines.each_index.select { |index| lines[index].strip == "# To get coverage" }
      return content if starts.length < 2

      starts.drop(1).reverse_each do |start_index|
        end_index = start_index
        end_index += 1 while end_index < lines.length && comment_or_blank_line?(lines[end_index])
        lines.slice!(start_index...end_index) if comment_only_lines?(lines[start_index...end_index])
      end
      lines.join
    end

    def simplecov_obsolete_call_nodes(content)
      result = prism_parse_success(content)
      return [] unless result

      result.value.breadth_first_search_all do |node|
        simplecov_start_call_node?(node) || simplecov_config_require_call_node?(node) || simplecov_kettle_soup_cover_require_call_node?(node)
      end
    end

    def simplecov_start_call_node?(node)
      node.is_a?(::Prism::CallNode) &&
        node.name == :start &&
        node.receiver&.slice == "SimpleCov"
    end

    def simplecov_config_require_call_node?(node)
      node.is_a?(::Prism::CallNode) &&
        node.name == :require &&
        node.receiver.nil? &&
        ruby_string_argument(node) == "kettle/soup/cover/config"
    end

    def simplecov_kettle_soup_cover_require_call_node?(node)
      node.is_a?(::Prism::CallNode) &&
        node.name == :require &&
        node.receiver.nil? &&
        ruby_string_argument(node) == "kettle-soup-cover"
    end

    def normalize_spec_helper_simplecov_template_source(content)
      output = remove_duplicate_simplecov_do_cov_bootstrap_blocks(content)
      output = ensure_spec_helper_simplecov_do_cov_bootstrap(output)
      output = remove_obsolete_simplecov_rescue_bootstrap_blocks(output)
      output = remove_duplicate_simplecov_requires(output)
      output = ensure_spec_helper_simplecov_config_require(output)
      output = ensure_spec_helper_simplecov_start(output)
      migrate_legacy_byebug_requires(output)
    end

    # The Gemfile migration replaces every byebug-family dependency with
    # debug. Keep the runnable spec helper consistent with that dependency
    # graph: a stale require "byebug" otherwise makes a successfully
    # templated project fail before its examples load.
    def migrate_legacy_byebug_requires(content)
      debug_records = ruby_call_records(content, :require).filter_map do |call|
        next unless call.receiver.nil? && ruby_string_argument(call) == "debug"

        line = content.to_s.lines.fetch(call.location.start_line - 1, "")
        next unless line.strip == call.location.slice.strip

        {
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call),
          source: call.location.slice
        }
      end
      records = ruby_call_records(content, :require).filter_map do |call|
        next unless call.receiver.nil?

        name = ruby_string_argument(call).to_s
        next unless name.include?("byebug")

        {
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call),
          source: call.location.slice
        }
      end.sort_by { |record| record.fetch(:start_line) }
      return normalize_debug_require_records(content, debug_records) if records.empty?

      debug_already_required = !debug_records.empty?
      first = records.first
      replacements = records.to_h do |record|
        replacement = if record.equal?(first) && !debug_already_required
          indent = content.to_s.lines.fetch(record.fetch(:start_line) - 1)[/\A\s*/]
          %(#{indent}#{guarded_debug_require}\n)
        else
          ""
        end
        [record.fetch(:start_line), record.merge(replacement: replacement)]
      end
      normalize_debug_require_records(replace_record_ranges(content, replacements), debug_records)
    end

    def normalize_debug_require_records(content, records)
      return content if records.empty?

      replacements = records.to_h do |record|
        indent = content.to_s.lines.fetch(record.fetch(:start_line) - 1)[/\A\s*/]
        [record.fetch(:start_line), record.merge(replacement: %(#{indent}#{guarded_debug_require}\n))]
      end
      replace_record_ranges(content, replacements)
    end

    def guarded_debug_require
      'require "debug" if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7") && ENV["CI"].nil? && ENV.fetch("DEBUG", "false").casecmp("true").zero?'
    end

    def normalize_spec_helper_block_bindings(content, template_content)
      output = content
      [
        lambda { |call| call.receiver&.slice == "RSpec" && call.name == :configure },
        lambda { |call| call.name == :expect_with && call.receiver }
      ].each do |matcher|
        template_binding = Prism::Merge::BlockBinding.find(template_content, &matcher)
        destination_binding = Prism::Merge::BlockBinding.find(output, &matcher)
        next unless template_binding && destination_binding

        output = Prism::Merge::BlockVarRenamer.normalize(
          output,
          binding: destination_binding,
          canonical_name: template_binding.name
        )
      end
      output
    end

    def remove_obsolete_simplecov_rescue_bootstrap_blocks(content)
      records = obsolete_simplecov_rescue_bootstrap_records(content)
      return content if records.empty?

      records.sort_by { |record| -record.fetch(:start_line) }.reduce(content.to_s) do |output, record|
        replace_source_range_lines(output, record.fetch(:start_line), expand_line_range_through_following_blanks(output, record.fetch(:end_line)), "")
      end
    end

    def obsolete_simplecov_rescue_bootstrap_records(content)
      result = prism_parse_success(content)
      return [] unless result

      complete_bootstrap_present = simplecov_do_cov_bootstrap_records(content).any? { |record| record.fetch(:complete) }
      result.value.breadth_first_search_all do |node|
        obsolete_simplecov_rescue_bootstrap_node?(node, complete_bootstrap_present: complete_bootstrap_present)
      end.map do |node|
        {
          start_line: node.location.start_line,
          end_line: ruby_node_source_end_line(node)
        }
      end
    end

    def obsolete_simplecov_rescue_bootstrap_node?(node, complete_bootstrap_present:)
      return false unless node.is_a?(::Prism::BeginNode)
      return false unless node.rescue_clause

      calls = prism_call_nodes(node)
      has_kettle_soup_cover_require = calls.any? { |call| simplecov_kettle_soup_cover_require_call_node?(call) }
      has_simplecov_require = calls.any? { |call| simplecov_require_call_node?(call) }
      has_config_require = calls.any? { |call| simplecov_config_require_call_node?(call) }
      has_kettle_soup_cover_require &&
        !has_config_require &&
        (has_simplecov_require || complete_bootstrap_present) &&
        calls.all? { |call| simplecov_bootstrap_call_node?(call) || simplecov_load_error_guard_call_node?(call) }
    end

    def simplecov_bootstrap_call_node?(node)
      simplecov_require_call_node?(node) ||
        simplecov_config_require_call_node?(node) ||
        simplecov_kettle_soup_cover_require_call_node?(node) ||
        simplecov_start_call_node?(node)
    end

    def simplecov_load_error_guard_call_node?(node)
      return true if node.name == :raise
      return true if node.name == :message
      return true if node.name == :include? && ruby_string_argument(node) == "kettle"

      false
    end

    def remove_duplicate_simplecov_do_cov_bootstrap_blocks(content)
      records = simplecov_do_cov_bootstrap_records(content)
      return content if records.length <= 1

      records.drop(1).select { |record| record.fetch(:bootstrap_only) }.sort_by { |record| -record.fetch(:start_line) }.reduce(content.to_s) do |output, record|
        replace_source_range_lines(output, record.fetch(:start_line), expand_line_range_through_following_blanks(output, record.fetch(:end_line)), "")
      end
    end

    def ensure_spec_helper_simplecov_do_cov_bootstrap(content)
      record = simplecov_do_cov_bootstrap_records(content).first
      return content unless record
      return content if record.fetch(:complete)

      replace_source_range_lines(
        content,
        record.fetch(:start_line),
        record.fetch(:end_line),
        spec_helper_simplecov_do_cov_bootstrap_source(leading_whitespace(record.fetch(:source)))
      )
    end

    def spec_helper_simplecov_do_cov_bootstrap_source(indent)
      [
        "#{indent}if Kettle::Soup::Cover::DO_COV\n",
        "#{indent}  require \"simplecov\" # Loads project-local .simplecov.\n",
        "#{indent}  require \"kettle/soup/cover/config\"\n",
        "#{indent}  SimpleCov.start\n",
        "#{indent}end\n"
      ].join
    end

    def simplecov_do_cov_bootstrap_records(content)
      result = prism_parse_success(content)
      return [] unless result

      lines = content.to_s.lines
      result.value.breadth_first_search_all do |node|
        node.is_a?(::Prism::IfNode) &&
          simplecov_do_cov_predicate_node?(node.predicate) &&
          prism_subtree_contains_simplecov_require?(node)
      end.map do |node|
        end_line = ruby_node_source_end_line(node)
        source = (lines[(node.location.start_line - 1)..(end_line - 1)] || []).join
        {
          start_line: node.location.start_line,
          end_line: end_line,
          source: source,
          bootstrap_only: simplecov_do_cov_bootstrap_only_node?(node),
          complete: simplecov_do_cov_bootstrap_complete_node?(node)
        }
      end.sort_by { |record| record.fetch(:start_line) }
    end

    def simplecov_do_cov_predicate_node?(node)
      node&.location&.slice.to_s == "Kettle::Soup::Cover::DO_COV"
    end

    def prism_subtree_contains_simplecov_require?(node)
      node.compact_child_nodes.any? do |child|
        simplecov_require_call_node?(child) || prism_subtree_contains_simplecov_require?(child)
      end
    end

    def simplecov_do_cov_bootstrap_complete_node?(node)
      subtree = prism_call_nodes(node)
      subtree.any? { |child| simplecov_require_call_node?(child) } &&
        subtree.any? { |child| simplecov_config_require_call_node?(child) } &&
        subtree.any? { |child| simplecov_start_call_node?(child) }
    end

    def simplecov_do_cov_bootstrap_only_node?(node)
      calls = prism_call_nodes(node)
      return false if calls.empty?

      calls.all? do |call|
        simplecov_require_call_node?(call) ||
          simplecov_config_require_call_node?(call) ||
          simplecov_start_call_node?(call)
      end
    end

    def prism_call_nodes(node)
      return [] unless node

      nodes = []
      stack = [node]
      until stack.empty?
        current = stack.pop
        nodes << current if current.is_a?(::Prism::CallNode)
        stack.concat(current.compact_child_nodes)
      end
      nodes
    end

    def remove_duplicate_simplecov_requires(content)
      records = simplecov_require_call_records(content)
      return content if records.length <= 1

      records.drop(1).sort_by { |record| -record.fetch(:start_line) }.reduce(content.to_s) do |output, record|
        replace_source_range_lines(output, record.fetch(:start_line), expand_line_range_through_following_blanks(output, record.fetch(:end_line)), "")
      end
    end

    def ensure_spec_helper_simplecov_config_require(content)
      return content if simplecov_config_require_call_nodes(content).any?

      simplecov_require = simplecov_require_call_records(content).first
      return content unless simplecov_require

      insert_lines_after(
        content,
        simplecov_require.fetch(:end_line),
        "#{leading_whitespace(simplecov_require.fetch(:source))}require \"kettle/soup/cover/config\"\n"
      )
    end

    def ensure_spec_helper_simplecov_start(content)
      return content if simplecov_start_call_nodes(content).any?

      config_require = simplecov_config_require_call_records(content).first
      return content unless config_require

      insert_lines_after(
        content,
        config_require.fetch(:end_line),
        "#{leading_whitespace(config_require.fetch(:source))}SimpleCov.start\n"
      )
    end

    def simplecov_require_call_node?(node)
      node.is_a?(::Prism::CallNode) &&
        node.name == :require &&
        node.receiver.nil? &&
        ruby_string_argument(node) == "simplecov"
    end

    def simplecov_require_call_records(content)
      lines = content.to_s.lines
      ruby_call_records(content, :require).filter_map do |call|
        next unless simplecov_require_call_node?(call)

        end_line = ruby_node_source_end_line(call)
        {
          start_line: call.location.start_line,
          end_line: end_line,
          source: (lines[(call.location.start_line - 1)..(end_line - 1)] || []).join
        }
      end.sort_by { |record| record.fetch(:start_line) }
    end

    def simplecov_config_require_call_records(content)
      lines = content.to_s.lines
      ruby_call_records(content, :require).filter_map do |call|
        next unless simplecov_config_require_call_node?(call)

        end_line = ruby_node_source_end_line(call)
        {
          start_line: call.location.start_line,
          end_line: end_line,
          source: (lines[(call.location.start_line - 1)..(end_line - 1)] || []).join
        }
      end.sort_by { |record| record.fetch(:start_line) }
    end

    def simplecov_config_require_call_nodes(content)
      result = prism_parse_success(content)
      return [] unless result

      result.value.breadth_first_search_all do |node|
        simplecov_config_require_call_node?(node)
      end
    end

    def simplecov_start_call_nodes(content)
      result = prism_parse_success(content)
      return [] unless result

      result.value.breadth_first_search_all do |node|
        simplecov_start_call_node?(node)
      end
    end

    def leading_space_count(line)
      line.to_s.each_char.take_while { |char| char == " " }.count
    end

    def outdent_line(line, spaces)
      return line if line.strip.empty?

      line.delete_prefix(" " * spaces)
    end

    def nested_templating_guard_records(content)
      result = prism_parse_success(content)
      return [] unless result

      result.value.breadth_first_search_all do |node|
        redundant_templating_guard_wrapper_node?(node)
      end.map do |node|
        inner = node.statements.body.first
        {
          outer_start_line: node.location.start_line,
          outer_end_line: node.location.end_line,
          inner_start_line: inner.location.start_line,
          inner_end_line: inner.location.end_line
        }
      end
    end

    def redundant_templating_guard_wrapper_node?(node)
      return false unless gemfile_conditional_node?(node)
      return false unless prism_subtree_contains_string?(node.predicate, "K_JEM_TEMPLATING")

      body = node.statements&.body.to_a
      return false unless body.length == 1

      inner = body.first
      gemfile_conditional_node?(inner) &&
        prism_subtree_contains_string?(inner.predicate, "K_JEM_TEMPLATING")
    end

    def runtime_workspace_override_records(content)
      result = prism_parse_success(content)
      return [] unless result

      conditional_nodes = result.value.breadth_first_search_all do |node|
        gemfile_conditional_node?(node)
      end
      templating_guard_ranges = conditional_nodes.filter_map do |node|
        next unless prism_subtree_contains_string?(node, "K_JEM_TEMPLATING")

        {start_line: node.location.start_line, end_line: node.location.end_line}
      end
      conditional_nodes.select do |node|
        gemfile_workspace_override_node?(node) &&
          !node_enclosed_by_ranges?(node, templating_guard_ranges)
      end.map do |node|
        {start_line: node.location.start_line, end_line: node.location.end_line}
      end
    end

    def gemfile_workspace_override_node?(node)
      return false unless gemfile_conditional_node?(node)
      return false if prism_subtree_contains_string?(node, "K_JEM_TEMPLATING")

      prism_subtree_contains_call?(node, :eval_nomono_gems)
    end

    def gemfile_conditional_node?(node)
      node.is_a?(::Prism::IfNode) || node.is_a?(::Prism::UnlessNode)
    end

    def node_enclosed_by_ranges?(node, ranges)
      start_line = node.location.start_line
      end_line = node.location.end_line
      ranges.any? do |range|
        range.fetch(:start_line) < start_line && range.fetch(:end_line) > end_line
      end
    end

    def prism_subtree_contains_call?(node, call_name)
      node.breadth_first_search_all do |child|
        child.is_a?(::Prism::CallNode) && child.name == call_name
      end.any?
    end

    def prism_subtree_contains_string?(node, string)
      node.breadth_first_search_all do |child|
        child.is_a?(::Prism::StringNode) && child.unescaped == string
      end.any?
    end

    def indent_source(source, spaces)
      prefix = " " * spaces
      source.to_s.lines.map { |line| line.strip.empty? ? line : "#{prefix}#{line}" }.join
    end

    def outdent_source(source, spaces)
      prefix = " " * spaces
      source.to_s.lines.map { |line| line.start_with?(prefix) ? line.delete_prefix(prefix) : line }.join
    end

    def local_gemfile_template_recipe?(recipe)
      recipe.fetch(:target_path).to_s.end_with?("_local.gemfile")
    end

    def modular_gemfile_template_recipe?(recipe)
      recipe.fetch(:target_path).to_s.start_with?("gemfiles/modular/")
    end

    def normalize_local_gemfile_nomono_bootstrap(content)
      output = remove_obsolete_local_gemfile_nomono_activation(content)
      bootstrap = "#{local_gemfile_nomono_bootstrap(nil)}\n\n"
      require_records = ruby_call_records(output, :require).filter_map do |call|
        next unless ruby_string_argument(call) == "nomono/bundler"

        {
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call)
        }
      end
      unless require_records.empty?
        first = require_records.min_by { |record| record.fetch(:start_line) }
        without_duplicates = require_records.reject { |record| record.equal?(first) }.sort_by { |record| -record.fetch(:start_line) }.reduce(output) do |memo, record|
          replace_source_range_lines(memo, record.fetch(:start_line), expand_line_range_through_following_blanks(memo, record.fetch(:end_line)), "")
        end
        return replace_source_range_lines(without_duplicates, first.fetch(:start_line), first.fetch(:end_line), bootstrap)
      end

      if (record = local_gems_assignment_record(output))
        insert_lines_before(output, record.fetch(:start_line), bootstrap)
      else
        ensure_trailing_newline([output.to_s.rstrip, bootstrap.rstrip].reject(&:empty?).join("\n\n"))
      end
    end

    def remove_obsolete_local_gemfile_nomono_activation(content)
      records = obsolete_local_gemfile_nomono_activation_records(content)
      return content if records.empty?

      records.sort_by { |record| -record.fetch(:start_line) }.reduce(content.to_s) do |output, record|
        replace_source_range_lines(
          output,
          record.fetch(:start_line),
          expand_line_range_through_following_blanks(output, record.fetch(:end_line)),
          ""
        )
      end
    end

    def obsolete_local_gemfile_nomono_activation_records(content)
      result = prism_parse_success(content)
      body = result&.value&.statements&.body || []
      assignments = body.select do |node|
        node.is_a?(::Prism::LocalVariableWriteNode) && node.name == :nomono_activation_requirements
      end
      return [] if assignments.empty?

      lines = content.to_s.lines
      assignments.filter_map do |assignment|
        kernel_gem_call = body.find do |node|
          local_gemfile_nomono_kernel_activation_call?(node) &&
            node.location.start_line > assignment.location.start_line
        end
        next unless kernel_gem_call

        {
          start_line: preceding_comment_block_start_line(lines, assignment.location.start_line),
          end_line: ruby_node_source_end_line(kernel_gem_call)
        }
      end
    end

    def local_gemfile_nomono_kernel_activation_call?(node)
      node.is_a?(::Prism::CallNode) &&
        node.name == :send &&
        node.receiver&.slice == "Kernel" &&
        node.arguments&.arguments&.[](0)&.location&.slice == ":gem" &&
        ruby_string_argument_at(node, 1) == "nomono"
    end

    def preceding_comment_block_start_line(lines, line_number)
      line = line_number
      line -= 1 while line > 1 && lines[line - 2].to_s.strip.start_with?("#")
      line
    end

    def merge_local_gem_overrides(content, destination_content, facts:, template_content: nil)
      template_gems = local_gems_assignment(content)
      template_gems = local_gems_assignment(template_content) if template_gems.empty?
      destination_gems = local_gems_assignment(destination_content)
      return content if template_gems.empty? && destination_gems.empty?

      destination_gems = destination_gems.reject do |destination_gem|
        template_gems.any? { |template_gem| versioned_gem_name_update_candidate?(destination_gem, template_gem) }
      end
      gems = (template_gems + destination_gems).map(&:to_s).reject(&:empty?).uniq
      replace_local_gems_assignment(content, gems)
    end

    # This list is resolved exclusively through STRUCTUREDMERGE_DEV. Preserve no
    # destination entries here: an obsolete entry can point Bundler at a sibling
    # path that does not exist in the StructuredMerge gems directory.
    def normalize_structuredmerge_local_gems(content, template_content)
      template_gems = word_array_assignment(template_content, :structuredmerge_local_gems)
      return content if template_gems.empty?
      return content unless word_array_assignment_record(content, :structuredmerge_local_gems)

      replace_word_array_assignment(content, :structuredmerge_local_gems, template_gems)
    end

    def versioned_gem_name_update_candidate?(destination_name, template_name)
      destination = versioned_gem_name_parts(destination_name)
      template = versioned_gem_name_parts(template_name)
      return false unless destination && template
      return false unless destination.fetch(:prefix) == template.fetch(:prefix)
      return false if destination.fetch(:versions) == template.fetch(:versions)

      destination.fetch(:versions).length == template.fetch(:versions).length
    end

    def versioned_gem_name_parts(name)
      match = name.to_s.match(/\A(.+?)(\d+(?:[_-]\d+)*)\z/)
      return unless match

      {
        prefix: match[1],
        versions: match[2].split(/[_-]/).map { |segment| Integer(segment, exception: false) }
      }
    end

    def local_gems_assignment(content)
      word_array_assignment(content, :local_gems)
    end

    def replace_local_gems_assignment(content, gems)
      replace_word_array_assignment(content, :local_gems, gems)
    end

    def local_gems_assignment_record(content)
      word_array_assignment_record(content, :local_gems)
    end

    def word_array_assignment(content, name)
      word_array_assignment_record(content, name)&.fetch(:names) || []
    end

    def replace_word_array_assignment(content, name, gems)
      replacement = ["#{name} = %w["]
      gems.each { |gem_name| replacement << "  #{gem_name}" }
      replacement << "]"
      if (record = word_array_assignment_record(content, name))
        replace_source_range_lines(content, record.fetch(:start_line), record.fetch(:end_line), ensure_trailing_newline(replacement.join("\n")))
      else
        ensure_trailing_newline([content.to_s.rstrip, replacement.join("\n")].reject(&:empty?).join("\n\n"))
      end
    end

    def word_array_assignment_record(content, name)
      result = prism_parse_success(content)
      return unless result

      result.value.breadth_first_search_all do |node|
        node.is_a?(::Prism::LocalVariableWriteNode) &&
          node.name == name &&
          ruby_word_array_node?(node.value)
      end.first&.then do |node|
        {
          names: ruby_word_array_names(node.value),
          start_line: node.location.start_line,
          end_line: node.location.end_line
        }
      end
    end

    def prune_github_workflow_matrix_by_min_ruby(content, facts)
      min_ruby = minimum_ruby_token(facts.to_h.dig(:ci, :test_min_ruby) || facts.to_h.dig(:rubygems, :min_ruby))
      return content if min_ruby.to_s.empty?

      minimum = Gem::Version.new(min_ruby)
      lines = content.to_s.lines
      remove_indexes = Set.new
      yaml_mapping_nodes(content).each do |mapping|
        next unless prune_workflow_matrix_item?(mapping, minimum)

        (mapping.start_line...mapping.end_line).each { |line_index| remove_indexes << line_index }
      end

      return content if remove_indexes.empty?

      ensure_trailing_newline(lines.each_with_index.reject { |_line, line_index| remove_indexes.include?(line_index) }.map(&:first).join.gsub(/\n{3,}/, "\n\n"))
    rescue
      content
    end

    def finalize_github_workflow_template(content, facts = nil)
      output = apply_github_actions_engine_exec_cmd_overrides(content, facts)
      inject_framework_matrix_workflow_env(update_github_actions_pins(output), facts)
    end

    def apply_github_actions_engine_exec_cmd_overrides(content, facts)
      overrides = facts.to_h.dig(:ci, :engine_exec_cmds).to_h
      return content if overrides.empty?

      lines = content.to_s.lines
      yaml_mapping_nodes(content).sort_by { |mapping| -mapping.start_line }.each do |mapping|
        engine = yaml_mapping_scalar_value(mapping, "ruby")
        command = overrides[engine]
        next if command.to_s.empty?

        exec_cmd_node = yaml_mapping_scalar_node(mapping, "exec_cmd")
        next unless exec_cmd_node

        line_index = exec_cmd_node.start_line
        indent = lines.fetch(line_index).to_s.match(/\A(\s*)/)[1]
        lines[line_index] = "#{indent}exec_cmd: #{yaml_double_quoted_scalar(command)}\n"
      end
      lines.join
    rescue Psych::Exception
      content
    end

    def inject_framework_matrix_workflow_env(content, facts)
      env_by_appraisal = framework_matrix_appraisal_env_by_name(facts)
      return content if env_by_appraisal.empty?

      lines = content.to_s.lines
      inserted_keys = Set.new
      inserted_locations = Set.new
      yaml_mapping_nodes(content).sort_by { |mapping| -mapping.start_line }.each do |mapping|
        appraisal = yaml_mapping_scalar_value(mapping, "appraisal")
        matrix_env = env_by_appraisal[appraisal]
        next unless matrix_env

        insert_index = workflow_matrix_env_insert_index(lines, mapping)
        next unless insert_index

        indent = workflow_matrix_env_indent(lines, mapping)
        additions = matrix_env.reject { |key, _value| yaml_mapping_scalar_node(mapping, key) }
        additions.reject! { |key, _value| inserted_locations.include?([insert_index, key.to_s]) }
        next if additions.empty?

        additions.each_key { |key| inserted_keys << key }
        additions.each_key { |key| inserted_locations << [insert_index, key.to_s] }
        lines.insert(insert_index, *additions.map { |key, value| %(#{indent}#{key}: #{yaml_double_quoted_scalar(value)}\n) })
      end
      return content if inserted_keys.empty?

      add_framework_matrix_job_env(lines.join, inserted_keys)
    rescue
      content
    end

    def framework_matrix_appraisal_env_by_name(facts)
      entries = facts.to_h.dig(:ci, :framework_matrix, :appraisals).to_a
      entries.to_h do |entry|
        env = {"KJ_FRAMEWORK_MATRIX_GEM" => entry.fetch(:gem).to_s}.merge(entry.fetch(:env, {}).transform_keys(&:to_s))
        [entry.fetch(:name).to_s, env.reject { |_key, value| value.to_s.empty? }]
      end.reject { |_name, env| env.empty? }
    end

    def workflow_matrix_env_insert_index(lines, mapping)
      ((mapping.start_line - 1)...mapping.end_line).each do |index|
        return index + 1 if lines[index].to_s.match?(/\A\s+appraisal:/)
      end
      mapping.start_line
    end

    def workflow_matrix_env_indent(lines, mapping)
      ((mapping.start_line - 1)...mapping.end_line).each do |index|
        line = lines[index].to_s
        match = line.match(/\A(\s+)appraisal:/)
        return match[1] if match
      end
      lines.fetch(mapping.start_line - 1, "").match(/\A(\s*)/)[1] + "  "
    end

    def yaml_double_quoted_scalar(value)
      %("#{value.to_s.gsub("\\", "\\\\\\").gsub('"', '\"')}")
    end

    def add_framework_matrix_job_env(content, keys)
      lines = content.lines
      bundle_index = lines.index { |line| line.match?(/\A\s+BUNDLE_GEMFILE:/) }
      return content unless bundle_index

      indent = lines.fetch(bundle_index).match(/\A(\s*)/)[1]
      existing = workflow_job_env_existing_keys(lines, bundle_index, indent.length)
      additions = keys.map(&:to_s).sort.reject { |key| existing.include?(key) }
      return content if additions.empty?

      lines.insert(
        bundle_index + 1,
        *additions.map { |key| %(#{indent}#{key}: ${{ matrix.#{key} || '' }}\n) }
      )
      lines.join
    end

    def workflow_job_env_existing_keys(lines, bundle_index, indent_length)
      existing = Set.new
      ((bundle_index + 1)...lines.length).each do |index|
        line = lines.fetch(index)
        next if line.strip.empty?

        current_indent = line.match(/\A(\s*)/)[1].length
        break if current_indent < indent_length
        next unless current_indent == indent_length

        key = line.strip.split(":", 2).first.to_s
        existing << key unless key.empty?
      end
      existing
    end

    def yaml_mapping_nodes(content)
      root = Psych.parse_stream(content.to_s)
      nodes = []
      stack = [root]
      until stack.empty?
        node = stack.pop
        nodes << node if node.is_a?(Psych::Nodes::Mapping)
        stack.concat(Array(node.respond_to?(:children) ? node.children : nil))
      end
      nodes
    end

    def prune_workflow_matrix_item?(mapping, minimum)
      ruby = yaml_mapping_scalar_value(mapping, "ruby").to_s.strip
      return true if !ruby.empty? && Gem::Version.new(ruby) < minimum

      appraisal_ruby = appraisal_ruby_version(yaml_mapping_scalar_value(mapping, "appraisal")).to_s.strip
      !appraisal_ruby.empty? && Gem::Version.new(appraisal_ruby) < minimum
    rescue ArgumentError
      false
    end

    def yaml_mapping_scalar_value(mapping, key)
      yaml_mapping_scalar_node(mapping, key)&.value.to_s
    end

    def yaml_mapping_scalar_node(mapping, key)
      mapping.children.each_slice(2) do |key_node, value_node|
        next unless key_node.is_a?(Psych::Nodes::Scalar) && key_node.value.to_s == key.to_s
        next unless value_node.is_a?(Psych::Nodes::Scalar)

        return value_node
      end
      nil
    end

    def appraisal_ruby_version(value)
      parts = value.to_s.split("-")
      return unless parts.length == 3 && parts.first == "ruby"

      major = Integer(parts[1], exception: false)
      minor = Integer(parts[2], exception: false)
      return unless major && minor

      "#{major}.#{minor}"
    end

    def ruby_method_move_policy(recipe)
      recipe.dig(:template_preference, :method_move_policy) ||
        (Ruby::Merge.const_defined?(:DEFAULT_METHOD_MOVE_POLICY) ? Ruby::Merge::DEFAULT_METHOD_MOVE_POLICY : DEFAULT_RUBY_METHOD_MOVE_POLICY)
    end

    def github_workflow_template_recipe?(recipe)
      recipe.fetch(:target_path).to_s.start_with?(".github/workflows/")
    end

    def yaml_process_result_adapter_failure?(merge_result)
      process_result_adapter_failure?(merge_result)
    end

    def process_result_adapter_failure?(merge_result)
      diagnostics = merge_result.respond_to?(:fetch) ? merge_result.fetch(:diagnostics, []) : []
      diagnostics.any? do |diagnostic|
        message = diagnostic[:message] || diagnostic["message"]
        message.to_s.include?("TreeSitterLanguagePack::ProcessResult") && message.to_s.include?("undefined method")
      end
    end

    def adapter_failure_template_source_error(file_type, recipe)
      ArgumentError.new("failed to merge #{file_type} template #{recipe.fetch(:target_path)}: provider adapter failure")
    end

    def ruby_merge_options(recipe, merge_template_requires:)
      options = {merge_template_requires: merge_template_requires}
      parameters = Ruby::Merge.method(:merge_ruby).parameters
      if parameters.include?([:key, :method_move_policy]) || parameters.any? { |kind, _name| kind == :keyrest }
        options[:method_move_policy] = ruby_method_move_policy(recipe)
      end
      options
    end

    def merge_ruby_template_source(file_type, recipe, template_content, destination_content, facts: nil)
      return merge_prism_gemfile_template_source(template_content, destination_content) if file_type == :gemfile

      template_preference = recipe.fetch(:template_preference, {})
      preference = (template_preference[:preference] || "destination").to_sym
      add_template_only_nodes = true
      unless template_preference[:add_template_only_nodes].nil?
        configured = DecisionPolicy.value_to_boolean(template_preference[:add_template_only_nodes])
        add_template_only_nodes = configured unless configured.nil?
      end

      Prism::Merge.merge_ruby(
        template_content,
        destination_content,
        "ruby",
        preference: preference,
        add_template_only_nodes: add_template_only_nodes,
        signature_generator: Prism::Merge.ruby_dsl_signature_generator(require_aliases: ruby_require_aliases(recipe, facts)),
        **prism_ruby_merge_options(recipe)
      )
    end

    def merge_prism_gemfile_template_source(template_content, destination_content)
      Prism::Merge.merge_ruby(
        template_content,
        destination_content,
        "ruby",
        preference: :template,
        add_template_only_nodes: true,
        signature_generator: Prism::Merge.ruby_dsl_signature_generator
      )
    end

    def prism_ruby_merge_options(recipe)
      {
        method_move_policy: ruby_method_move_policy(recipe),
        merge_template_requires: true,
        template_only_placement: :after_anchor
      }
    end

    def ruby_require_aliases(recipe, facts = nil)
      facts ||= recipe[:facts] || recipe["facts"]
      return [] unless facts.is_a?(Hash)

      package = facts[:package] || facts["package"] || {}
      rubygems = facts[:rubygems] || facts["rubygems"] || {}
      package_name = (package[:name] || package["name"]).to_s.strip
      entrypoint = (rubygems[:entrypoint_require] || rubygems["entrypoint_require"]).to_s.strip
      return [] if package_name.empty? || entrypoint.empty? || package_name == entrypoint

      [[package_name, entrypoint]]
    end

    def merge_gemfile_template_policy(content, facts:, template_content: nil, preserve_self_word_entries: false)
      package_name = facts.dig(:package, :name).to_s if facts
      removable_gems = ["appraisal"]
      removable_gems << package_name unless package_name.to_s.empty?
      removable_gems.concat(package_runtime_dependency_names(facts))
      removable_gems << "version_gem" unless version_gem_enabled?(facts)
      pruned = remove_gemfile_dependency_blocks(content, removable_gems)
      pruned = remove_gemfile_percent_w_entries(pruned, [package_name]) unless preserve_self_word_entries
      pruned = merge_template_gemfile_dependency_blocks(
        template_content,
        pruned,
        removable_gems,
        preserve_self_word_entries: preserve_self_word_entries
      )
      apply_commented_gem_dependency_policy(template_content, pruned)
    end

    def package_runtime_dependency_names(facts)
      dependencies = facts.to_h.dig(:package, :runtime_dependencies)
      Array(dependencies).map(&:to_s).reject(&:empty?).uniq
    end

    def inject_main_gemfile_recording_eval(content, facts)
      return content unless facts.to_h.dig(:ci, :recording)
      return content if gemfile_eval_paths(content).any? { |path| path.to_s.include?("gemfiles/modular/recording/") }

      lines = content.to_s.lines
      insert_at = main_gemfile_recording_insertion_index(content) || lines.length
      lines.insert(insert_at, "# Test HTTP Interaction Recording\n", %(eval_gemfile "#{main_gemfile_recording_eval_path}"\n), "\n")
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    # The root Gemfile is the local-development bundle. Appraisals and CI use
    # their own Gemfiles, so a project that needs a framework or application
    # harness locally must declare that dependency separately in test_bundle.
    def inject_main_gemfile_default_test_bundle(content, facts)
      bundle = facts.to_h.dig(:ci, :default_test_bundle).to_h
      return content if bundle.empty?

      managed_gems = bundle.fetch(:managed_gems, [])
      output = remove_gemfile_dependency_blocks(content, managed_gems)
      existing_paths = gemfile_eval_paths(output).to_set
      additions = bundle.fetch(:gemfiles, []).filter_map do |path|
        next if existing_paths.include?(path)

        %(eval_gemfile "#{path}")
      end
      additions.concat(bundle.fetch(:gems, []).map { |gem| default_test_bundle_gem_source(gem) })
      return output if additions.empty?

      lines = output.to_s.lines
      insert_at = main_gemfile_default_test_bundle_insertion_index(output) || lines.length
      block = ["# Default local test bundle", *additions].join("\n")
      lines.insert(insert_at, "#{block}\n\n")
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def default_test_bundle_gem_source(gem)
      arguments = [gem.fetch(:name).inspect, *gem.fetch(:requirements, []).map(&:inspect)]
      arguments << "require: false" if gem[:require] == false
      "gem #{arguments.join(", ")}"
    end

    def main_gemfile_default_test_bundle_insertion_index(content)
      main_gemfile_templating_eval_line(content) ||
        main_gemfile_first_eval_gemfile_line(content) ||
        main_gemfile_after_gemspec_line(content)
    end

    def main_gemfile_recording_insertion_index(content)
      lines = content.to_s.lines
      call = ruby_call_records(content, :eval_gemfile).find do |candidate|
        ruby_string_argument(candidate).to_s == "gemfiles/modular/style.gemfile"
      end
      return unless call

      gemfile_eval_comment_start_line(lines, call.location.start_line) - 1
    end

    def main_gemfile_recording_eval_path
      "gemfiles/modular/recording/r4/recording.gemfile"
    end

    def gemfile_eval_paths(content)
      ruby_call_records(content, :eval_gemfile).filter_map { |call| ruby_string_argument(call) }
    end

    def merge_template_gemfile_dependency_blocks(template_content, content, removable_gems, preserve_self_word_entries: false)
      template = remove_gemfile_dependency_blocks(template_content, removable_gems)
      template = remove_gemfile_percent_w_entries(template, removable_gems) unless preserve_self_word_entries
      existing = gemfile_dependency_names(content) + gemfile_percent_w_names(content)
      additions = gemfile_paragraphs(template).filter_map do |paragraph|
        names = gemfile_dependency_names(paragraph) + gemfile_percent_w_names(paragraph)
        next if names.empty?
        next if (names - existing).empty?

        paragraph
      end
      return content if additions.empty?

      insert_gemfile_dependency_blocks(content, additions)
    end

    def gemfile_paragraphs(content)
      content.to_s.split(/\n{2,}/).map { |paragraph| ensure_trailing_newline(paragraph.strip) }.reject { |paragraph| paragraph.strip.empty? }
    end

    def gemfile_percent_w_names(content)
      ruby_word_array_records(content).flat_map { |record| record.fetch(:names) }.reject(&:empty?)
    end

    def insert_gemfile_dependency_blocks(content, blocks)
      lines = content.to_s.lines
      insert_at = gemfile_dependency_insertion_line(content)
      while insert_at.positive? && lines[insert_at - 1].strip.empty?
        insert_at -= 1
      end
      insertion = blocks.map { |block| block.strip }.join("\n\n")
      lines.insert(insert_at, "#{insertion}\n\n")
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def gemfile_dependency_insertion_line(content)
      body = prism_parse_success(content)&.value&.statements&.body || []
      node = body.find do |statement|
        gemfile_dependency_statement?(statement)
      end
      return content.to_s.lines.length unless node

      node.location.start_line - 1
    end

    def gemfile_dependency_statement?(node)
      case node
      when ::Prism::CallNode
        %i[gem group platforms].include?(node.name)
      when ::Prism::IfNode, ::Prism::UnlessNode
        true
      else
        false
      end
    end

    def apply_commented_gem_dependency_policy(template_content, content)
      commented_blocks = commented_gem_dependency_blocks(template_content)
      return content if commented_blocks.empty?

      active_records_by_line = gemfile_gem_call_records(content)
        .select { |record| commented_blocks.key?(record.fetch(:name)) }
        .to_h { |record| [record.fetch(:start_line), record] }
      comment_blocks_by_line = commented_gem_dependency_block_records(content)
        .select { |record| commented_blocks.key?(record.fetch(:name)) }
        .to_h { |record| [record.fetch(:block_start_line), record] }
      inserted = Set.new
      skip_until = 0
      lines = []
      content.to_s.lines.each_with_index do |line, index|
        line_number = index + 1
        next if line_number < skip_until

        if (record = comment_blocks_by_line[line_number])
          gem_name = record.fetch(:name)
          append_gemfile_comment_block(lines, commented_blocks.fetch(gem_name)) unless inserted.include?(gem_name)
          inserted << gem_name
          skip_until = record.fetch(:block_end_line) + 1
          next
        end

        if (record = active_records_by_line[line_number])
          gem_name = record.fetch(:name)
          append_gemfile_comment_block(lines, commented_blocks.fetch(gem_name)) unless inserted.include?(gem_name)
          inserted << gem_name
          skip_until = record.fetch(:end_line) + 1
          next
        end

        lines << line
      end
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def append_gemfile_comment_block(lines, block)
      first_line = block.first
      lines.pop while first_line && lines.last == first_line
      lines.concat(block)
    end

    def commented_gem_dependency_blocks(content)
      commented_gem_dependency_block_records(content).to_h do |record|
        [record.fetch(:name), record.fetch(:source_lines)]
      end
    end

    def commented_gem_dependency_block_records(content)
      lines = content.to_s.lines
      commented_gem_dependency_records(content).map do |record|
        start_index = record.fetch(:start_line) - 1
        while start_index.positive? && gemfile_comment_line?(lines[start_index - 1])
          start_index -= 1
        end
        record.merge(
          block_start_line: start_index + 1,
          block_end_line: record.fetch(:end_line),
          source_lines: lines[start_index..(record.fetch(:end_line) - 1)] || []
        )
      end
    end

    def remove_gemfile_dependency_lines(content, gem_names)
      names = gem_names.map(&:to_s).reject(&:empty?).uniq
      return content if names.empty?

      remove_indexes = Set.new
      gemfile_gem_call_records(content).each do |record|
        next unless names.include?(record.fetch(:name))

        (record.fetch(:start_line)..record.fetch(:end_line)).each { |line_number| remove_indexes << (line_number - 1) }
      end
      lines = content.to_s.lines.each_with_index.reject { |_line, index| remove_indexes.include?(index) }.map(&:first)
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def remove_gemfile_dependency_blocks(content, gem_names)
      names = gem_names.map(&:to_s).reject(&:empty?).uniq
      return content if names.empty?

      lines = content.to_s.lines
      remove_indexes = Set.new
      gemfile_gem_call_records(content).each do |record|
        next unless names.include?(record.fetch(:name))

        start_index = record.fetch(:start_line) - 1
        start_index -= 1 while start_index.positive? && gemfile_comment_line?(lines[start_index - 1])
        (start_index..(record.fetch(:end_line) - 1)).each { |index| remove_indexes << index }
      end
      return content if remove_indexes.empty?

      ensure_trailing_newline(lines.each_with_index.reject { |_line, index| remove_indexes.include?(index) }.map(&:first).join.gsub(/\n{3,}/, "\n\n"))
    end

    def gemfile_gem_call_records(content)
      ruby_call_records(content, :gem).filter_map do |call|
        name = ruby_string_argument(call)
        next unless name

        {
          name: name,
          requirements: ruby_string_arguments(call).drop(1),
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call)
        }
      end
    end

    # A dependency owned directly by the project must not also be introduced by
    # a generated modular Gemfile. On first bootstrap, write a reviewable
    # resolution list; later runs require an explicit removal operation.
    def validate_modular_dependency_conflicts!(project_root, recipe_reports)
      conflicts = modular_dependency_conflicts(project_root, recipe_reports)
      return if conflicts.empty?

      config = kettle_jem_config(project_root)
      decisions = modular_dependency_conflict_decisions(config)
      unresolved = conflicts.reject { |conflict| modular_dependency_conflict_decided?(decisions, conflict) }
      if unresolved.empty?
        return
      end

      bootstrap_report = recipe_reports.find { |report| report.fetch(:relative_path, "").to_s == KETTLE_CONFIG_PATH }
      if bootstrap_report && !modular_dependency_conflicts_reviewed?(config)
        bootstrap_report[:final_content] = add_dependency_conflict_review_list(bootstrap_report.fetch(:final_content, ""), conflicts)
        return
      end

      details = unresolved.sort_by { |conflict| conflict.values_at(:name, :direct, :modular) }.map do |conflict|
        "#{conflict.fetch(:name)} (#{conflict.fetch(:direct)} vs #{conflict.fetch(:modular)})"
      end.join(", ")
      raise Error,
        "direct dependencies also declared by templated modular Gemfiles: #{details}. " \
          "Review dependency_conflicts.resolve in #{KETTLE_CONFIG_PATH}; each entry needs gem, direct, modular, action, and reason. " \
        "Supported actions: remove_modular_gem, remove_x_std_lib_eval, keep_both. " \
        "keep_both is valid only when the direct and modular requirements overlap."
    end

    def modular_dependency_conflicts(project_root, recipe_reports)
      report_paths = recipe_reports.map { |report| report.fetch(:relative_path, "").to_s }
      paths = ["Gemfile", *Dir.glob(File.join(project_root.to_s, "*.gemspec")).map { |path| File.basename(path) }, *report_paths.select { |path| path.end_with?(".gemspec") }]
      direct = dependency_file_contents(project_root, recipe_reports, paths)
      modular_paths = [
        *Dir.glob(File.join(project_root.to_s, "gemfiles/modular/**/*.gemfile")).map do |path|
          Pathname(path).relative_path_from(Pathname(project_root.to_s)).to_s
        end,
        *report_paths.select { |path| path.start_with?("gemfiles/modular/") && path.end_with?(".gemfile") }
      ].uniq
      modular_paths = modular_paths.map do |path|
        if path.start_with?("/")
          Pathname(path).relative_path_from(Pathname(project_root.to_s)).to_s
        else
          path
        end
      end.select do |path|
        relative = path.delete_prefix("gemfiles/modular/")
        !relative.include?("/") || relative.start_with?("x_std_libs/")
      end
      modular = dependency_file_contents(project_root, recipe_reports, modular_paths)
      direct.flat_map do |direct_path, content|
        direct_records = dependency_records_for(direct_path, content)
        modular.flat_map do |modular_path, modular_content|
          modular_records = dependency_records_for(modular_path, modular_content)
          direct_records.flat_map do |direct_record|
            modular_records.select { |record| record.fetch(:name) == direct_record.fetch(:name) }.map do |modular_record|
              {
                name: direct_record.fetch(:name),
                direct: direct_path,
                modular: modular_path,
                direct_requirements: direct_record.fetch(:requirements, []),
                modular_requirements: modular_record.fetch(:requirements, [])
              }
            end
          end
        end
      end
    end

    def dependency_records_for(path, content)
      if path == "Gemfile" || path.end_with?(".gemfile")
        gemfile_gem_call_records(content)
      else
        gemspec_dependency_records(content)
      end
    end

    def dependency_file_contents(project_root, recipe_reports, paths)
      reports = recipe_reports.to_h { |report| [report.fetch(:relative_path, "").to_s, report] }
      paths.uniq.filter_map do |path|
        file_path = File.join(project_root.to_s, path)
        next unless reports.key?(path) || File.file?(file_path)

        content = reports.key?(path) ? reports.fetch(path).fetch(:final_content, "") : File.read(file_path)
        [path, content]
      end.to_h
    end

    def modular_dependency_conflict_decisions(config)
      Array(config.dig("dependency_conflicts", "resolve")).filter_map do |entry|
        case entry
        when Hash
          normalized = entry.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
          next if %w[gem direct modular action reason].any? { |key| normalized.fetch(key, "").to_s.strip.empty? }

          %w[gem direct modular action reason].to_h { |key| [key, normalized.fetch(key).to_s] }
        end
      end
    end

    def modular_dependency_conflicts_reviewed?(config)
      config.dig("dependency_conflicts", "reviewed") == true
    end

    def modular_dependency_conflict_decided?(decisions, conflict)
      decisions.any? do |decision|
        decision.fetch("gem") == conflict.fetch(:name) &&
          decision.fetch("direct") == conflict.fetch(:direct) &&
          decision.fetch("modular") == conflict.fetch(:modular) &&
          case decision.fetch("action")
          when "remove_modular_gem", "remove_x_std_lib_eval"
            true
          when "keep_both"
            compatible_dependency_requirements?(conflict.fetch(:direct_requirements), conflict.fetch(:modular_requirements))
          else
            false
          end
      end
    end

    def compatible_dependency_requirements?(direct_requirements, modular_requirements)
      direct = Gem::Requirement.new(*Array(direct_requirements).map(&:to_s))
      modular = Gem::Requirement.new(*Array(modular_requirements).map(&:to_s))
      candidates = ["0.0.0", "1.0.0", "2.0.0", "3.0.0", "4.0.0", "5.0.0", "6.0.0", "10.0.0"]
      [direct, modular].each do |requirement|
        requirement.requirements.each do |operator, version|
          base = version.to_s.split(".").map(&:to_i)
          base << 0 while base.length < 3
          candidates << base.join(".")
          candidates << [base[0], base[1] + 1, 0].join(".") if operator == "~>"
        end
      end
      candidates.uniq.any? do |version|
        version = Gem::Version.new(version)
        direct.satisfied_by?(version) && modular.satisfied_by?(version)
      end
    rescue ArgumentError
      false
    end

    def add_dependency_conflict_review_list(content, conflicts)
      lines = content.to_s.lines
      index = lines.index { |line| line.match?(/\Adependency_conflicts:\s*\z/) }
      unless index
        lines << "\n" unless lines.empty? || lines.last.strip.empty?
        lines.concat(["dependency_conflicts:\n", "  # Review each entry and choose a supported action.\n", "  resolve:\n"])
        index = lines.length - 3
      end

      block_end = (index + 1...lines.length).find { |line_index| lines[line_index].match?(/\A\S/) } || lines.length
      replacement = [
        "dependency_conflicts:\n",
        "  # Review each entry and choose a supported action.\n",
        "  # keep_both is for a broad direct requirement plus a compatible modular narrowing.\n",
        "  reviewed: false\n",
        "  resolve:\n"
      ]
      conflicts.sort_by { |conflict| conflict.values_at(:name, :direct, :modular) }.each do |conflict|
        replacement.concat([
          "    - gem: #{conflict.fetch(:name)}\n",
          "      direct: #{conflict.fetch(:direct)}\n",
          "      modular: #{conflict.fetch(:modular)}\n",
          "      action: review\n",
          "      reason: \"\"\n"
        ])
      end
      ensure_trailing_newline([*lines[0...index], *replacement, *lines[block_end..].to_a].join)
    end

    def apply_modular_dependency_conflict_resolutions(project_root, decisions)
      decisions.each_with_object([]) do |decision, changed_files|
        path = File.join(project_root.to_s, decision.fetch("modular"))
        next unless File.file?(path)

        before = File.read(path)
        after = case decision.fetch("action")
        when "remove_modular_gem"
          remove_gemfile_dependency_blocks(before, [decision.fetch("gem")])
        when "remove_x_std_lib_eval"
          remove_x_std_lib_eval_for_gem(before, decision.fetch("gem"))
        when "keep_both"
          before
        end
        next if after == before

        File.write(path, after)
        changed_files << decision.fetch("modular")
      end
    end

    def remove_x_std_lib_eval_for_gem(content, gem_name)
      records = ruby_call_records(content, :eval_gemfile).filter_map do |call|
        path = ruby_string_argument(call).to_s
        next unless path.split("/").any? { |part| part == gem_name || part.tr("-", "_") == gem_name.tr("-", "_") }

        {start_line: call.location.start_line, end_line: ruby_node_source_end_line(call)}
      end
      replace_record_ranges(content, records.to_h { |record| [record.fetch(:start_line), record.merge(replacement: "")] })
    end

    def ruby_top_level_require_records(content)
      body = prism_parse_success(content)&.value&.statements&.body || []
      body.filter_map do |node|
        next unless node.is_a?(::Prism::CallNode) && node.name == :require

        name = ruby_string_argument(node)
        next unless name

        {
          name: name,
          start_line: node.location.start_line,
          end_line: ruby_node_source_end_line(node)
        }
      end
    end

    def ruby_call_records(content, call_name)
      result = prism_parse_success(content)
      return [] unless result

      result.value.breadth_first_search_all do |node|
        node.is_a?(::Prism::CallNode) && (call_name.nil? || node.name == call_name)
      end
    end

    def ruby_node_source_end_line(node)
      return 0 unless node

      lines = [node.location&.end_line]
      lines << node.closing_loc&.start_line if node.respond_to?(:closing_loc)
      node.compact_child_nodes.each do |child|
        lines << ruby_node_source_end_line(child)
      end
      lines.compact.max.to_i
    end

    def commented_gem_dependency_records(content)
      result = prism_parse_success(content)
      return [] unless result

      result.comments.filter_map do |comment|
        call = commented_gem_call(comment.location.slice)
        name = ruby_string_argument(call)
        next unless name

        {
          name: name,
          start_line: comment.location.start_line,
          end_line: comment.location.end_line
        }
      end
    end

    def commented_gem_call(comment_source)
      source = uncomment_ruby_comment_line(comment_source)
      return unless source

      result = prism_parse_success(source)
      body = result&.value&.statements&.body
      call = body&.one? ? body.first : nil
      call if call.is_a?(::Prism::CallNode) && call.name == :gem
    end

    def uncomment_ruby_comment_line(comment_source)
      text = comment_source.to_s
      return unless text.start_with?("#")

      uncommented = text[1..].to_s
      uncommented = uncommented[1..].to_s if uncommented.start_with?(" ")
      uncommented
    end

    def ruby_string_argument(call)
      ruby_string_argument_at(call, 0)
    end

    def ruby_string_argument_at(call, index)
      argument = call&.arguments&.arguments&.[](index)
      ruby_static_string_value(argument)
    end

    def ruby_string_arguments(call)
      Array(call&.arguments&.arguments).filter_map do |argument|
        ruby_static_string_value(argument)
      end
    end

    def ruby_keyword_string_argument(call, key)
      keyword_hash = Array(call&.arguments&.arguments).find { |argument| argument.is_a?(::Prism::KeywordHashNode) }
      assoc = keyword_hash&.elements&.find do |element|
        element.respond_to?(:key) && element.key.respond_to?(:unescaped) && element.key.unescaped == key.to_s
      end
      value = assoc&.value
      ruby_static_string_value(value)
    end

    def ruby_static_string_value(node)
      case node
      when ::Prism::StringNode
        node.unescaped
      when ::Prism::InterpolatedStringNode
        ruby_static_interpolated_string_value(node)
      when ::Prism::CallNode
        ruby_static_string_call_value(node)
      end
    end

    def ruby_static_interpolated_string_value(node)
      parts = node.compact_child_nodes.map { |child| ruby_static_string_value(child) }
      return if parts.any?(&:nil?)

      parts.join
    end

    def ruby_static_string_call_value(node)
      return unless node.receiver && node.arguments.nil?

      value = ruby_static_string_value(node.receiver)
      return if value.nil?

      case node.name
      when :to_s
        value.to_s
      when :strip
        value.strip
      when :lstrip
        value.lstrip
      when :rstrip
        value.rstrip
      when :chomp
        value.chomp
      when :chop
        value.chop
      end
    end

    def prism_parse_success(content)
      ensure_runtime_dependencies!
      result = ::Prism.parse(content.to_s)
      result if result.success?
    end

    def gemfile_comment_line?(line)
      line.to_s.lstrip.start_with?("#")
    end

    def remove_gemfile_percent_w_entries(content, gem_names)
      names = gem_names.map(&:to_s).reject(&:empty?).uniq
      return content if names.empty?

      replacements = ruby_word_array_records(content).filter_map do |record|
        kept = record.fetch(:names).reject { |word| names.include?(word) }
        next if kept == record.fetch(:names)

        replacement = if record.fetch(:source).lines.one?
          "%w[#{kept.join(" ")}]"
        else
          ruby_multiline_word_array_source(kept, indent: record.fetch(:line_indent))
        end
        {start_offset: record.fetch(:start_offset), end_offset: record.fetch(:end_offset), replacement: replacement}
      end
      return content if replacements.empty?

      replaced = replace_source_offsets(content, replacements)
      ensure_trailing_newline(replaced.gsub(/\n{3,}/, "\n\n"))
    end

    def ruby_word_array_records(content)
      lines = content.to_s.lines
      ruby_word_array_nodes(content).map do |node|
        source_line = lines.fetch(node.location.start_line - 1)
        {
          names: ruby_word_array_names(node),
          source: node.location.slice,
          start_line: node.location.start_line,
          end_line: node.location.end_line,
          line_indent: source_line.length - source_line.lstrip.length,
          start_offset: node.location.start_offset,
          end_offset: node.location.end_offset
        }
      end
    end

    def ruby_word_array_nodes(content)
      result = prism_parse_success(content)
      return [] unless result

      result.value.breadth_first_search_all do |node|
        ruby_word_array_node?(node)
      end
    end

    def ruby_word_array_node?(node)
      node.is_a?(::Prism::ArrayNode) && node.opening_loc&.slice.to_s.start_with?("%w[")
    end

    def ruby_word_array_names(node)
      node.elements.filter_map do |element|
        element.unescaped if element.is_a?(::Prism::StringNode)
      end
    end

    def ruby_multiline_word_array_source(names, indent:)
      element_prefix = " " * (indent.to_i + 2)
      closing_prefix = " " * indent.to_i
      (["%w["] + names.map { |name| "#{element_prefix}#{name}" } + ["#{closing_prefix}]"]).join("\n")
    end

    def replace_source_offsets(content, replacements)
      output = content.to_s.dup
      replacements.sort_by { |replacement| -replacement.fetch(:start_offset) }.each do |replacement|
        output = replace_source_byte_range(
          output,
          replacement.fetch(:start_offset),
          replacement.fetch(:end_offset),
          replacement.fetch(:replacement)
        )
      end
      output
    end

    def replace_source_byte_range(content, start_offset, end_offset, replacement)
      source = content.to_s
      before = source.byteslice(0, start_offset) || +""
      after = source.byteslice(end_offset, source.bytesize - end_offset) || +""
      "#{before}#{replacement}#{after}"
    end

    def merge_gemfile_eval_bucket_entries(template_content, merged_content, destination_content: nil)
      template_entries = gemfile_eval_bucket_entries(template_content)
      template_by_key = template_entries.to_h { |entry| [entry.fetch(:key), entry] }
      destination_entries = gemfile_eval_bucket_entries(destination_content)
      destination_only_entries = destination_entries.reject { |entry| template_by_key.key?(entry.fetch(:key)) }
      return merged_content if template_entries.empty? && destination_only_entries.empty?

      emitted_paths = Set.new
      insert_at = nil
      lines = []
      merged_lines = merged_content.to_s.lines
      merged_entries_by_line = gemfile_eval_bucket_entries(merged_content).to_h { |entry| [entry.fetch(:start_line), entry] }
      skip_until = 0
      merged_lines.each_with_index do |line, index|
        line_number = index + 1
        next if line_number < skip_until

        entry = merged_entries_by_line[line_number]
        unless entry && template_by_key.key?(entry.fetch(:key))
          lines << line
          next
        end

        template_entry = template_by_key.fetch(entry.fetch(:key))
        if entry.fetch(:path) == template_entry.fetch(:path)
          lines << entry.fetch(:line) unless emitted_paths.include?(entry.fetch(:path))
          emitted_paths << entry.fetch(:path)
        else
          insert_at ||= lines.length
        end
        skip_until = entry.fetch(:end_line) + 1
      end

      existing_paths = gemfile_eval_bucket_entries(lines.join).map { |entry| entry.fetch(:path) }.to_set
      wanted_entries = template_entries + destination_only_entries
      missing_lines = wanted_entries
        .reject { |entry| emitted_paths.include?(entry.fetch(:path)) || existing_paths.include?(entry.fetch(:path)) }
        .map { |entry| entry.fetch(:section_line) }
      return ensure_trailing_newline(lines.join) if missing_lines.empty?

      insert_at ||= lines.length
      lines[insert_at, 0] = missing_lines
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def gemfile_eval_bucket_entries(content)
      lines = content.to_s.lines
      ruby_call_records(content, :eval_gemfile).filter_map do |call|
        path = ruby_string_argument(call)
        next unless path

        key = normalize_eval_gemfile_ruby_bucket(path)
        next unless key

        start_line = call.location.start_line
        end_line = ruby_node_source_end_line(call)
        section_start_line = gemfile_eval_comment_start_line(lines, start_line)
        {
          path: path,
          key: key,
          line: (lines[(start_line - 1)..(end_line - 1)] || []).join,
          section_line: (lines[(section_start_line - 1)..(end_line - 1)] || []).join,
          start_line: start_line,
          end_line: end_line
        }
      end
    end

    def gemfile_eval_comment_start_line(lines, start_line)
      index = start_line.to_i - 2
      return start_line if index.negative?

      index -= 1 while index >= 0 && lines.fetch(index).lstrip.start_with?("#")
      index + 2
    end

    def normalize_eval_gemfile_ruby_bucket(path)
      segments = path.to_s.split("/", -1)
      bucket_index = segments.index { |segment| ruby_bucket_path_segment?(segment) }
      return unless bucket_index

      segments[bucket_index] = "{ruby}"
      segments.join("/")
    end

    def ruby_bucket_path_segment?(segment)
      return false unless segment.to_s.start_with?("r")

      version = segment.to_s[1..].to_s
      return false if version.empty?

      version.split(".", -1).all? { |part| !part.empty? && part.each_char.all? { |char| char.between?("0", "9") } }
    end

    def merge_appraisals_template_policy(content, facts:)
      package_name = facts.dig(:package, :name).to_s if facts
      min_ruby = minimum_ruby_token(facts.dig(:ci, :test_min_ruby) || facts.dig(:rubygems, :min_ruby)) if facts
      with_framework_appraisals = merge_framework_matrix_appraisals(content, facts)
      with_standard_appraisal_gemfiles = inject_standard_appraisal_gemfiles(with_framework_appraisals, facts)
      pruned = prune_appraisals_recording_entries(with_standard_appraisal_gemfiles, facts)
      pruned = prune_appraisals_below_min_ruby(pruned, min_ruby)
      pruned = remove_managed_stdlib_appraisal_gems(pruned)
      pruned = migrate_legacy_byebug_appraisal_dependencies(pruned)
      pruned = remove_gemfile_dependency_lines(pruned, [package_name])
      remove_gemfile_percent_w_entries(pruned, [package_name])
    end

    # Each appraisal has an independent dependency set. Reuse the AST-based
    # Gemfile migration per block so every legacy byebug/pry-byebug pair is
    # replaced by one debug declaration in that same appraisal.
    def migrate_legacy_byebug_appraisal_dependencies(content)
      parsed = appraisal_blocks(content)
      blocks = parsed.fetch(:order).map do |name|
        migrate_legacy_byebug_pair(parsed.fetch(:blocks).fetch(name))
      end
      ensure_trailing_newline(([parsed.fetch(:prelude).to_s.rstrip] + blocks.map(&:rstrip)).reject(&:empty?).join("\n\n"))
    end

    # The x_std_libs aggregate owns these extracted standard libraries. Keeping
    # legacy gem declarations in an appraisal block that evaluates the aggregate
    # makes Bundler reject the same gem with two requirement declarations.
    MANAGED_APPRAISAL_STDLIB_GEMS = %w[benchmark cgi erb mutex_m stringio webrick].freeze

    def remove_managed_stdlib_appraisal_gems(content)
      parsed = appraisal_blocks(content)
      blocks = parsed.fetch(:order).map do |name|
        remove_managed_stdlib_gems_from_appraisal_block(parsed.fetch(:blocks).fetch(name))
      end
      ensure_trailing_newline(([parsed.fetch(:prelude).to_s.rstrip] + blocks.map(&:rstrip)).reject(&:empty?).join("\n\n"))
    end

    def remove_managed_stdlib_gems_from_appraisal_block(block)
      return block unless appraisal_x_stdlib_eval_gemfile_call(block)

      lines = block.to_s.lines
      remove_indexes = Set.new
      gemfile_gem_call_records(block).each do |record|
        next unless MANAGED_APPRAISAL_STDLIB_GEMS.include?(record.fetch(:name))

        start_index = record.fetch(:start_line) - 1
        start_index -= 1 while start_index.positive? && gemfile_comment_line?(lines[start_index - 1])
        (start_index..(record.fetch(:end_line) - 1)).each { |index| remove_indexes << index }
      end
      return block if remove_indexes.empty?

      ensure_trailing_newline(lines.each_with_index.reject { |_line, index| remove_indexes.include?(index) }.map(&:first).join.gsub(/\n{3,}/, "\n\n"))
    end

    def inject_standard_appraisal_gemfiles(content, facts)
      gemfiles = facts.to_h.dig(:ci, :standard_appraisal_gemfiles).to_a
      return content if gemfiles.empty?

      standard_names = standard_test_appraisal_names(content)
      return content if standard_names.empty?

      matrix_dependency_gemfiles = framework_matrix_appraisal_dependency_gemfiles(facts)
      parsed = appraisal_blocks(content)
      blocks = parsed.fetch(:order).map do |name|
        block = parsed.fetch(:blocks).fetch(name)
        if standard_names.include?(name) && !appraisal_block_has_matrix_dependency_gemfile?(block, matrix_dependency_gemfiles)
          inject_appraisal_gemfiles(block, gemfiles)
        else
          block
        end
      end
      ensure_trailing_newline(([parsed.fetch(:prelude).to_s.rstrip] + blocks.map(&:rstrip)).reject(&:empty?).join("\n\n"))
    end

    def standard_test_appraisal_names(content)
      appraisal_call_records(content).filter_map do |record|
        name = record.fetch(:name)
        next name if %w[unlocked_deps head current dep-heads coverage].include?(name)
        next name if ruby_appraisal_name_version(name)

        nil
      end.to_set
    end

    def framework_matrix_appraisal_dependency_gemfiles(facts)
      framework_matrix = facts.to_h.dig(:ci, :framework_matrix).to_h
      [
        *framework_matrix.fetch(:appraisals, []).flat_map { |entry| entry.fetch(:eval_gemfiles, []) },
        *framework_matrix.fetch(:gemfiles, []).map { |entry| entry.fetch(:path).to_s.delete_prefix("gemfiles/") }
      ].map(&:to_s).to_set
    end

    def appraisal_block_has_matrix_dependency_gemfile?(block, matrix_dependency_gemfiles)
      ruby_call_records(block, :eval_gemfile).any? do |call|
        path = ruby_string_argument(call).to_s
        next true if matrix_dependency_gemfiles.include?(path)

        path.start_with?("modular/") &&
          path.delete_prefix("modular/").include?("/") &&
          !path.start_with?("modular/x_std_libs/")
      end
    end

    def inject_appraisal_gemfiles(block, gemfiles)
      lines = block.to_s.lines
      existing_paths = ruby_call_records(block, :eval_gemfile).filter_map { |call| ruby_string_argument(call) }.to_set
      additions = gemfiles.filter_map do |gemfile|
        path = gemfile.to_s.delete_prefix("gemfiles/")
        line = %(  eval_gemfile "#{path}") + "\n"
        line unless existing_paths.include?(path)
      end
      return block if additions.empty?

      insert_line = appraisal_x_stdlib_eval_gemfile_call(block)&.location&.start_line ||
        ruby_call_records(block, :appraise).first&.location&.end_line
      insert_index = insert_line ? insert_line - 1 : nil
      return block unless insert_index

      lines.insert(insert_index, *additions)
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def appraisal_x_stdlib_eval_gemfile_call(block)
      ruby_call_records(block, :eval_gemfile).find do |call|
        ruby_string_argument(call).to_s.start_with?("modular/x_std_libs")
      end
    end

    def prune_appraisals_recording_entries(content, facts)
      remove_indexes = Set.new
      lines = content.to_s.lines
      unless facts.to_h.dig(:ci, :recording)
        ruby_call_records(content, :eval_gemfile).each do |call|
          path = ruby_string_argument(call)
          next unless path.to_s.include?("modular/recording/")

          (call.location.start_line..ruby_node_source_end_line(call)).each { |line_number| remove_indexes << (line_number - 1) }
        end
      end
      head_appraisal = appraisal_call_records(content).find { |record| record.fetch(:name) == "head" }
      if head_appraisal
        gemfile_gem_call_records(content).each do |record|
          next unless record.fetch(:name) == "cgi"
          next unless record.fetch(:start_line) >= head_appraisal.fetch(:start_line)
          next unless record.fetch(:end_line) <= head_appraisal.fetch(:end_line)

          start_index = record.fetch(:start_line) - 1
          while start_index.positive? && gemfile_comment_line?(lines[start_index - 1])
            start_index -= 1
          end
          (start_index..(record.fetch(:end_line) - 1)).each { |index| remove_indexes << index }
        end
      end
      return content if remove_indexes.empty?

      kept = lines.each_with_index.reject { |_line, index| remove_indexes.include?(index) }.map(&:first)
      ensure_trailing_newline(kept.join.gsub(/\n{3,}/, "\n\n"))
    end

    def merge_framework_matrix_appraisals(content, facts)
      entries = facts.to_h.dig(:ci, :framework_matrix, :appraisals).to_a
      return content if entries.empty?

      generated = entries.to_h do |entry|
        [entry.fetch(:name).to_s, framework_matrix_appraisal_block(entry)]
      end
      entries_by_name = entries.to_h { |entry| [entry.fetch(:name).to_s, entry] }
      replaced = entries.flat_map { |entry| entry.fetch(:replaces, []) }.map(&:to_s).to_set
      parsed = appraisal_blocks(content)
      emitted = Set.new
      blocks = parsed.fetch(:order).map do |name|
        next if replaced.include?(name) && !generated.key?(name)

        emitted << name
        parsed_block = parsed.fetch(:blocks).fetch(name).rstrip
        generated_block = generated[name]
        if generated_block && !entries_by_name.fetch(name).fetch(:standard_appraisal, false)
          generated_block
        elsif generated_block
          merge_appraisal_blocks_with_prism(generated_block, parsed_block)
        else
          parsed_block
        end
      end.compact
      entries.each do |entry|
        name = entry.fetch(:name).to_s
        next if emitted.include?(name)

        blocks << generated.fetch(name)
      end

      ensure_trailing_newline(([parsed.fetch(:prelude).to_s.rstrip] + blocks).reject(&:empty?).join("\n\n"))
    end

    def framework_matrix_appraisal_block(entry)
      lines = [
        %(appraise "#{entry.fetch(:name)}" do)
      ]
      entry.fetch(:eval_gemfiles).each do |gemfile|
        lines << %(  eval_gemfile "#{gemfile}")
      end
      lines << "end"
      lines.join("\n")
    end

    def yaml_merge_options(recipe)
      options = {
        preference: (recipe.dig(:template_preference, :preference) || "destination").to_sym,
        add_template_only_nodes: true,
        freeze_token: recipe.dig(:template_preference, :freeze_token) || "kettle-jem"
      }
      if !recipe.dig(:template_preference, :add_template_only_nodes).nil?
        configured = DecisionPolicy.value_to_boolean(recipe.dig(:template_preference, :add_template_only_nodes))
        options[:add_template_only_nodes] = configured unless configured.nil?
      end
      policy = recipe.dig(:template_preference, :comment_merge_policy).to_s
      policy = DEFAULT_TEMPLATE_YAML_COMMENT_MERGE_POLICY if policy.empty? && recipe.fetch(:primitive) == "supplied_template_source_application"
      options[:comment_merge_policy] = policy.to_sym unless policy.empty?

      options
    end

    def json_merge_options(recipe)
      options = {
        preference: (recipe.dig(:template_preference, :preference) || "destination").to_sym,
        add_template_only_nodes: true,
        freeze_token: recipe.dig(:template_preference, :freeze_token) || "kettle-jem"
      }
      if !recipe.dig(:template_preference, :add_template_only_nodes).nil?
        configured = DecisionPolicy.value_to_boolean(recipe.dig(:template_preference, :add_template_only_nodes))
        options[:add_template_only_nodes] = configured unless configured.nil?
      end
      options
    end

    def merge_json_template_source(template_content, destination_content, recipe, file_type)
      output = Json::Merge::SmartMerger.new(
        template_content,
        destination_content,
        dialect: file_type,
        **json_merge_options(recipe)
      ).merge
      {ok: true, output: output, diagnostics: []}
    rescue Json::Merge::Error => e
      {ok: false, output: destination_content, diagnostics: [{kind: "#{file_type}_merge_failed", message: e.message}]}
    end

    def dotenv_merge_options(recipe)
      options = {
        preference: (recipe.dig(:template_preference, :preference) || "destination").to_sym,
        add_template_only_nodes: true,
        freeze_token: recipe.dig(:template_preference, :freeze_token) || "kettle-jem"
      }
      if !recipe.dig(:template_preference, :add_template_only_nodes).nil?
        configured = DecisionPolicy.value_to_boolean(recipe.dig(:template_preference, :add_template_only_nodes))
        options[:add_template_only_nodes] = configured unless configured.nil?
      end
      options
    end

    def merge_dotenv_template_source(template_content, destination_content, recipe)
      output = Dotenv::Merge::SmartMerger.new(
        template_content,
        destination_content,
        **dotenv_merge_options(recipe)
      ).merge
      {ok: true, output: output, diagnostics: []}
    rescue Dotenv::Merge::Error => e
      {ok: false, output: destination_content, diagnostics: [{kind: "dotenv_merge_failed", message: e.message}]}
    end

    def rbs_merge_options(recipe)
      options = {
        preference: (recipe.dig(:template_preference, :preference) || "destination").to_sym,
        add_template_only_nodes: true,
        freeze_token: recipe.dig(:template_preference, :freeze_token) || "kettle-jem"
      }
      if !recipe.dig(:template_preference, :add_template_only_nodes).nil?
        configured = DecisionPolicy.value_to_boolean(recipe.dig(:template_preference, :add_template_only_nodes))
        options[:add_template_only_nodes] = configured unless configured.nil?
      end
      options
    end

    def merge_rbs_template_source(template_content, destination_content, recipe)
      output = Rbs::Merge::SmartMerger.new(
        template_content,
        destination_content,
        **rbs_merge_options(recipe)
      ).merge
      {ok: true, output: output, diagnostics: []}
    rescue Rbs::Merge::Error => e
      {ok: false, output: destination_content, diagnostics: [{kind: "rbs_merge_failed", message: e.message}]}
    end

    def bash_merge_options(recipe)
      options = {
        preference: (recipe.dig(:template_preference, :preference) || "destination").to_sym,
        add_template_only_nodes: true,
        freeze_token: recipe.dig(:template_preference, :freeze_token) || "kettle-jem"
      }
      if !recipe.dig(:template_preference, :add_template_only_nodes).nil?
        configured = DecisionPolicy.value_to_boolean(recipe.dig(:template_preference, :add_template_only_nodes))
        options[:add_template_only_nodes] = configured unless configured.nil?
      end
      options
    end

    def merge_bash_template_source(template_content, destination_content, recipe)
      availability = Bash::Merge.availability(source: template_content.to_s)
      unless availability.available?
        return {
          ok: false,
          output: destination_content,
          diagnostics: [{
            kind: "bash_merge_unavailable",
            message: "bash structural merge is unavailable because TreeHaver node parser support for Bash is not available",
            details: availability.diagnostics
          }]
        }
      end

      output = Bash::Merge::SmartMerger.new(
        template_content,
        destination_content,
        **bash_merge_options(recipe)
      ).merge
      {ok: true, output: output, diagnostics: []}
    rescue Bash::Merge::Error => e
      {ok: false, output: destination_content, diagnostics: [{kind: "bash_merge_failed", message: e.message}]}
    end

    def merge_appraisal_blocks_with_prism(template_block, destination_block)
      result = Prism::Merge.merge_ruby(
        template_block,
        destination_block,
        "ruby",
        preference: :destination,
        add_template_only_nodes: true,
        signature_generator: Prism::Merge.ruby_dsl_signature_generator,
        method_move_policy: ruby_method_move_policy({}),
        merge_template_requires: true,
        template_only_placement: :after_anchor
      )
      result[:ok] ? result.fetch(:output) : template_block
    end

    def appraisal_blocks(content)
      lines = content.to_s.lines
      blocks = {}
      order = []
      records = appraisal_call_records(content)
      records.each do |record|
        name = record.fetch(:name)
        unless blocks.key?(name)
          blocks[name] = record.fetch(:source)
          order << name
        end
      end
      prelude_end = records.empty? ? lines.length : records.first.fetch(:start_line) - 1
      prelude = lines[0...prelude_end].join
      {prelude: prelude, blocks: blocks, order: order}
    end

    def prune_appraisals_below_min_ruby(content, min_ruby)
      return content if min_ruby.to_s.empty?

      minimum = Gem::Version.new(min_ruby.to_s)
      remove_indexes = Set.new
      appraisal_call_records(content).each do |record|
        version = ruby_appraisal_name_version(record.fetch(:name))
        next unless version && version < minimum

        (record.fetch(:start_line)..record.fetch(:end_line)).each { |line_number| remove_indexes << (line_number - 1) }
      end
      kept = content.to_s.lines.each_with_index.reject { |_line, index| remove_indexes.include?(index) }.map(&:first)
      ensure_trailing_newline(kept.join.gsub(/\n{3,}/, "\n\n"))
    rescue ArgumentError
      content
    end

    def appraisal_call_records(content)
      lines = content.to_s.lines
      ruby_call_records(content, :appraise).filter_map do |call|
        name = ruby_string_argument(call)
        next unless name

        {
          name: name,
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call),
          source: (lines[(call.location.start_line - 1)..(ruby_node_source_end_line(call) - 1)] || []).join
        }
      end
    end

    def ruby_appraisal_name_version(name)
      text = name.to_s
      return unless text.start_with?("ruby-")

      major, minor, extra = text.delete_prefix("ruby-").split("-", -1)
      return if extra || major.to_s.empty? || minor.to_s.empty?
      return unless [major, minor].all? { |part| part.each_char.all? { |char| char.between?("0", "9") } }

      Gem::Version.new("#{major}.#{minor}")
    end

    def merge_gemspec_template_source(template_content, destination_content, facts: nil, env: ENV)
      template_receiver = gemspec_block_param(template_content) || "spec"
      destination_receiver = gemspec_block_param(destination_content) || "spec"
      package_name = facts.dig(:package, :name).to_s if facts
      replacements = gemspec_preserved_assignments(destination_content, receiver: destination_receiver)
        .except(*env_overridden_gemspec_fields(env))
      replacements = remove_stale_generated_gemspec_homepage_replacement(
        replacements,
        destination_content,
        facts,
        receiver: destination_receiver
      )
      normalized_replacements = replacements.to_h do |field, source|
        replacement = normalize_gemspec_receiver(source.rstrip, from: destination_receiver, to: template_receiver)
        [field, normalize_gemspec_project_emoji(replacement, facts, field: field)]
      end
      merged = replace_gemspec_assignment_sources(template_content, normalized_replacements, receiver: template_receiver)
      merged = insert_missing_gemspec_assignment_sources(merged, normalized_replacements, receiver: template_receiver)
      merged = normalize_gemspec_package_helper_assignments(merged, template_content)
      merged = merge_gemspec_files_assignment(
        merged,
        template_content: template_content,
        destination_content: destination_content,
        template_receiver: template_receiver,
        destination_receiver: destination_receiver
      )
      merged = insert_missing_gemspec_files_assignment(
        merged,
        template_content: template_content,
        template_receiver: template_receiver
      )
      merged = remove_gemspec_assignment(merged, receiver: template_receiver, field: "extra_rdoc_files")
      merged = preserve_gemspec_dependency_lines(
        merged,
        destination_content,
        template_receiver: template_receiver,
        destination_receiver: destination_receiver,
        facts: facts
      )
      merged = preserve_gemspec_freeze_blocks(merged, destination_content, facts: facts, receiver: template_receiver)
      merged = apply_configured_gemspec_licenses(merged, facts, receiver: template_receiver)
      merged = apply_configured_gemspec_required_ruby_version(merged, facts, receiver: template_receiver)
      merged = apply_configured_gemspec_metadata(merged, facts, receiver: template_receiver)
      merged = preserve_destination_only_gemspec_metadata(
        merged,
        template_content: template_content,
        destination_content: destination_content,
        template_receiver: template_receiver,
        destination_receiver: destination_receiver
      )
      merged = remove_duplicate_gemspec_assignments(merged, receiver: template_receiver, fields: %w[homepage])
      merged = remove_gemspec_self_dependency_lines(merged, package_name, receiver: template_receiver)
      merged = remove_gemspec_version_gem_dependency_when_disabled(
        merged,
        facts,
        receiver: template_receiver,
        template_declares_version_gem: gemspec_dependency_names(template_content).include?("version_gem")
      )
      merged = remove_gemspec_version_gem_dependency_when_non_default_entrypoint(merged, facts, receiver: template_receiver)
      # Yard owns the documentation dependency graph. A direct gemspec rdoc
      # development dependency creates an unnecessary second owner and can
      # conflict with the documentation modular Gemfile.
      merged = remove_gemspec_dependency_lines(merged, receiver: template_receiver, names: ["rdoc"], development_only: true)
      merged = remove_gemspec_development_dependencies_already_runtime(merged, receiver: template_receiver)
      merged = remove_duplicate_gemspec_dependency_lines(merged, receiver: template_receiver)
      merged = remove_empty_gemspec_development_dependency_section_headings(merged, receiver: template_receiver)
      merged = sort_runtime_gemspec_dependency_lines(merged, receiver: template_receiver)
      rewrite_gemspec_version_loader(merged, facts: facts)
    end

    def normalize_gemspec_package_helper_assignments(content, template_content)
      template_records = gemspec_package_helper_assignment_records(template_content).to_h do |record|
        [record.fetch(:name), record.fetch(:source)]
      end
      return content if template_records.empty?

      replacements = gemspec_package_helper_assignment_records(content).filter_map do |record|
        source = template_records[record.fetch(:name)]
        next unless source

        [record.fetch(:start_line), record.merge(replacement: source)]
      end.to_h
      return content if replacements.empty?

      replace_record_ranges(content, replacements)
    end

    def gemspec_package_helper_assignment_records(content)
      result = prism_parse_success(content)
      return [] unless result

      lines = content.to_s.lines
      helper_names = %w[
        gemspec_root
        relative_package_path
        enumerate_package_glob
        enumerate_package_files
        package_metadata_files
      ].to_set
      result.value.breadth_first_search_all do |node|
        node.is_a?(::Prism::LocalVariableWriteNode) && helper_names.include?(node.name.to_s)
      end.map do |node|
        end_line = ruby_node_source_end_line(node)
        {
          name: node.name.to_s,
          start_line: node.location.start_line,
          end_line: end_line,
          source: lines[(node.location.start_line - 1)..(end_line - 1)].join
        }
      end
    end

    def remove_stale_generated_gemspec_homepage_replacement(replacements, destination_content, facts, receiver:)
      desired_homepage = facts.to_h.dig(:package, :homepage_url).to_s
      return replacements if desired_homepage.empty? || !github_org_from_url(desired_homepage)
      return replacements unless replacements.key?("homepage")

      existing = gemspec_assignment_records(destination_content, receiver: receiver).find { |record| record.fetch(:field) == "homepage" }
      existing_homepage = existing && existing.fetch(:value).to_s
      return replacements if existing_homepage.empty? || existing_homepage == desired_homepage
      return replacements unless github_org_from_url(existing_homepage)

      replacements.except("homepage")
    end

    def rewrite_gemspec_version_loader(content, facts:)
      return content if shim_template_profile?(facts)

      min_ruby = gemspec_runtime_floor_token(facts)
      return content if min_ruby.to_s.empty?

      namespace = facts.to_h.dig(:rubygems, :namespace).to_s
      entrypoint_require = facts.to_h.dig(:rubygems, :entrypoint_require).to_s
      entrypoint_require = facts.to_h.dig(:package, :name).to_s.tr("-", "/") if entrypoint_require.empty?
      return content if namespace.empty? || entrypoint_require.empty?

      receiver = gemspec_block_param(content) || "spec"
      min_ruby_version = Gem::Version.new(min_ruby)
      modern = min_ruby_version >= MODERN_GEMSPEC_VERSION_LOADER_MIN_RUBY
      rhs = modern ? gemspec_modern_version_loader_expression(entrypoint_require: entrypoint_require, namespace: namespace) : "gem_version"
      rewritten = replace_gemspec_version_assignment(content, receiver: receiver, rhs: rhs)
      if modern
        remove_gemspec_legacy_version_loader_preamble(rewritten)
      else
        ensure_gemspec_legacy_version_loader_preamble(
          rewritten,
          entrypoint_require: entrypoint_require,
          namespace: namespace,
          min_ruby: min_ruby_version,
          superclass_sensitive: gemspec_version_loader_superclass_sensitive?(facts),
          fallback_version: facts.to_h.dig(:project_runtime, :version)
        )
      end
    rescue ArgumentError, Ast::Crispr::Error
      content
    end

    def replace_gemspec_version_assignment(content, receiver:, rhs:)
      replacement = "#{receiver}.version = #{rhs}"
      record = gemspec_assignment_records(content, receiver: receiver).find { |candidate| candidate.fetch(:field) == "version" }
      return replace_source_range_lines(content, record.fetch(:start_line), record.fetch(:end_line), "#{leading_whitespace(record.fetch(:source))}#{replacement}\n") if record

      name = gemspec_assignment_records(content, receiver: receiver).find { |candidate| candidate.fetch(:field) == "name" }
      return insert_lines_after(content, name.fetch(:end_line), "  #{replacement}\n") if name

      insert_lines_after(content, gemspec_new_call(content)&.location&.start_line || 1, "  #{replacement}\n")
    end

    def gemspec_modern_version_loader_expression(entrypoint_require:, namespace:)
      %(Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/#{entrypoint_require}/version.rb", mod) }::#{namespace}::Version::VERSION)
    end

    def gemspec_legacy_version_loader_block(entrypoint_require:, namespace:, min_ruby:, superclass_sensitive: false, fallback_version: nil)
      unless superclass_sensitive
        return gemspec_standard_legacy_version_loader_block(
          entrypoint_require: entrypoint_require,
          namespace: namespace,
          min_ruby: min_ruby
        )
      end

      anonymous_loader = <<~RUBY.chomp
        require "anonymous_loader"
        path = File.expand_path("lib/#{entrypoint_require}/version.rb", __dir__)
        anonymous_namespace = AnonymousLoader.load(files: path)
        anonymous_namespace::#{namespace}::Version::VERSION
      RUBY
      anonymous_loader_lines = anonymous_loader.lines.map { |line| "    #{line.chomp}" }
      fallback = fallback_version.to_s
      fallback = "0.0.0" if fallback.empty?
      lines = [
        "gem_version =",
        "  if Gem.ruby_version >= Gem::Version.new(\"3.1\")",
        "    # Loading Version into an anonymous module allows version.rb to get code coverage from SimpleCov!",
        "    # See: https://github.com/simplecov-ruby/simplecov/issues/557#issuecomment-2630782358",
        "    # See: https://github.com/panorama-ed/memo_wise/pull/397",
        "    #{gemspec_modern_version_loader_expression(entrypoint_require: entrypoint_require, namespace: namespace)}"
      ]
      lines << "  # The namesake namespace has a superclass. Directly requiring version.rb"
      lines << "  # on legacy Ruby could define that namespace with the wrong superclass."
      if min_ruby < ANONYMOUS_VERSION_LOADER_MIN_RUBY
        lines << "  elsif Gem.ruby_version >= Gem::Version.new(\"2.2\")"
        lines.concat(anonymous_loader_lines)
        lines << "  else"
        lines << "    #{fallback.dump}"
      else
        lines << "  else"
        lines.concat(anonymous_loader_lines)
      end
      lines << "  end"
      "#{lines.join("\n")}\n"
    end

    def gemspec_standard_legacy_version_loader_block(entrypoint_require:, namespace:, min_ruby:)
      legacy_require =
        if min_ruby >= REQUIRE_RELATIVE_MIN_RUBY
          %(require_relative "lib/#{entrypoint_require}/version")
        else
          <<~RUBY.chomp
            # NOTE: Use __FILE__ or __dir__ until removal of Ruby 1.x support
            # __dir__ introduced in Ruby 1.9.1
            lib = File.expand_path("lib", File.dirname(__FILE__))
            $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
            require "#{entrypoint_require}/version"
          RUBY
        end

      <<~RUBY
        gem_version =
          if Gem.ruby_version >= Gem::Version.new("3.1")
            # Loading Version into an anonymous module allows version.rb to get code coverage from SimpleCov!
            # See: https://github.com/simplecov-ruby/simplecov/issues/557#issuecomment-2630782358
            # See: https://github.com/panorama-ed/memo_wise/pull/397
            #{gemspec_modern_version_loader_expression(entrypoint_require: entrypoint_require, namespace: namespace)}
          else
            #{legacy_require.gsub("\n", "\n    ")}
            #{namespace}::Version::VERSION
          end
      RUBY
    end

    def gemspec_version_loader_superclass_sensitive?(facts)
      rubygems = facts.to_h[:rubygems]
      return false unless rubygems.is_a?(Hash)

      value = rubygems[:entrypoint_namespace_superclasses]
      value.is_a?(Hash) && !value.empty?
    end

    def remove_gemspec_legacy_version_loader_preamble(content)
      node = gemspec_top_level_gem_version_node(content)
      unless node
        fallback_range = gemspec_legacy_version_loader_preamble_line_range(content)
        return content unless fallback_range

        return replace_source_range_lines(content, fallback_range.fetch(:start_line), fallback_range.fetch(:end_line), "")
      end

      replace_source_range_lines(content, node.location.start_line, expand_line_range_through_following_blanks(content, node.location.end_line), "")
    end

    def gemspec_legacy_version_loader_preamble_line_range(content)
      lines = content.to_s.lines
      start_index = lines.index do |line|
        # Prism has represented this legacy multiline assignment inconsistently across
        # parser versions; this fallback is limited to the exact top-level preamble
        # shape immediately preceding Gem::Specification.new.
        line.match?(/\Agem_version\s*=/)
      end
      return unless start_index

      gemspec_index = lines.each_with_index.find do |line, index|
        index > start_index && line.include?("Gem::Specification.new")
      end&.last
      return unless gemspec_index

      end_line = gemspec_index
      end_line -= 1 while end_line > start_index && lines[end_line - 1].strip.empty?
      {start_line: start_index + 1, end_line: end_line}
    end

    def ensure_gemspec_legacy_version_loader_preamble(content, entrypoint_require:, namespace:, min_ruby:, superclass_sensitive: false, fallback_version: nil)
      block = "#{gemspec_legacy_version_loader_block(entrypoint_require: entrypoint_require, namespace: namespace, min_ruby: min_ruby, superclass_sensitive: superclass_sensitive, fallback_version: fallback_version)}\n"
      node = gemspec_top_level_gem_version_node(content)
      return replace_source_range_lines(content, node.location.start_line, expand_line_range_through_following_blanks(content, node.location.end_line), block) if node

      gemspec_call = gemspec_new_call(content)
      return content unless gemspec_call

      insert_lines_before(content, gemspec_call.location.start_line, block)
    end

    def gemspec_top_level_gem_version_node(content)
      ensure_runtime_dependencies!
      context = Ast::Crispr::Ruby::Prism.document_context(content: content.to_s, source_label: "gemspec")
      gemspec_call = context.structural_owners(owner_scope: :top_level_statements).find do |owner|
        owner.is_a?(::Prism::CallNode) && owner.name == :new && owner.receiver&.slice == "Gem::Specification"
      end
      context.structural_owners(owner_scope: :top_level_statements).find do |owner|
        owner.is_a?(::Prism::LocalVariableWriteNode) &&
          owner.name == :gem_version &&
          (!gemspec_call || owner.location.start_offset < gemspec_call.location.start_offset)
      end
    end

    def expand_line_range_through_following_blanks(content, end_line)
      lines = content.to_s.lines
      line = end_line
      line += 1 while lines[line]&.strip == ""
      line
    end

    def apply_configured_gemspec_licenses(content, facts, receiver:)
      licenses = Array(facts&.dig(:license, :spdx)).map { |license| license.to_s.strip }.reject(&:empty?)
      return content if licenses.empty?

      replacement = "#{receiver}.licenses = #{licenses.inspect}"
      existing = gemspec_assignment_records(content, receiver: receiver).find { |record| record.fetch(:field) == "licenses" }
      return replace_source_range_lines(content, existing.fetch(:start_line), existing.fetch(:end_line), "#{leading_whitespace(existing.fetch(:source))}#{replacement}\n") if existing

      homepage = gemspec_assignment_records(content, receiver: receiver).find { |record| record.fetch(:field) == "homepage" }
      return insert_lines_after(content, homepage.fetch(:end_line), "  #{replacement}\n") if homepage

      content
    end

    def apply_configured_gemspec_required_ruby_version(content, facts, receiver:)
      return remove_gemspec_assignment(content, receiver: receiver, field: "required_ruby_version") if explicit_zero_runtime_floor?(facts)

      min_ruby = minimum_ruby_token(facts.to_h.dig(:rubygems, :min_ruby))
      if min_ruby.to_s.empty?
        return content
      end

      replacement = %(#{receiver}.required_ruby_version = ">= #{min_ruby}"#{required_ruby_version_rubocop_disable(min_ruby)})
      existing = gemspec_assignment_records(content, receiver: receiver).find { |record| record.fetch(:field) == "required_ruby_version" }
      return replace_source_range_lines(content, existing.fetch(:start_line), existing.fetch(:end_line), "#{leading_whitespace(existing.fetch(:source))}#{replacement}\n") if existing

      licenses = gemspec_assignment_records(content, receiver: receiver).find { |record| record.fetch(:field) == "licenses" }
      return insert_lines_after(content, licenses.fetch(:end_line), "  #{replacement}\n") if licenses

      homepage = gemspec_assignment_records(content, receiver: receiver).find { |record| record.fetch(:field) == "homepage" }
      return insert_lines_after(content, homepage.fetch(:end_line), "  #{replacement}\n") if homepage

      content
    end

    def required_ruby_version_rubocop_disable(min_ruby)
      return "" unless Gem::Version.new(min_ruby) < Gem::Version.new("2.0")

      " # rubocop:disable Gemspec/RequiredRubyVersion"
    rescue ArgumentError
      ""
    end

    def apply_configured_gemspec_metadata(content, facts, receiver:)
      mailing_list_uri = facts.to_h.dig(:rubyforum, :url).to_s
      return content if mailing_list_uri.empty?

      ensure_gemspec_metadata_assignment(content, receiver: receiver, key: "mailing_list_uri", value: mailing_list_uri)
    end

    def ensure_gemspec_metadata_assignment(content, receiver:, key:, value:)
      replacement = %(#{receiver}.metadata[#{key.to_s.dump}] = #{value.to_s.dump})
      record = gemspec_metadata_assignment_records(content, receiver: receiver).find { |candidate| candidate.fetch(:key) == key.to_s }
      return replace_source_range_lines(content, record.fetch(:start_line), record.fetch(:end_line), "#{leading_whitespace(record.fetch(:source))}#{replacement}\n") if record

      anchor = %w[discord_uri news_uri wiki_uri funding_uri documentation_uri].filter_map do |metadata_key|
        gemspec_metadata_assignment_records(content, receiver: receiver).find { |candidate| candidate.fetch(:key) == metadata_key }
      end.first
      return insert_lines_after(content, anchor.fetch(:end_line), "  #{replacement}\n") if anchor

      homepage = gemspec_assignment_records(content, receiver: receiver).find { |candidate| candidate.fetch(:field) == "homepage" }
      return insert_lines_after(content, homepage.fetch(:end_line), "  #{replacement}\n") if homepage

      content
    end

    def preserve_destination_only_gemspec_metadata(
      content,
      template_content:,
      destination_content:,
      template_receiver:,
      destination_receiver:
    )
      template_keys = gemspec_metadata_assignment_records(template_content, receiver: template_receiver).map do |record|
        record.fetch(:key)
      end
      merged_keys = gemspec_metadata_assignment_records(content, receiver: template_receiver).map do |record|
        record.fetch(:key)
      end
      destination_records = gemspec_metadata_assignment_records(destination_content, receiver: destination_receiver).select do |record|
        !template_keys.include?(record.fetch(:key)) &&
          !merged_keys.include?(record.fetch(:key)) &&
          !default_gemspec_metadata_assignment?(record)
      end
      return content if destination_records.empty?

      insertion = destination_records.map do |record|
        normalize_gemspec_receiver(record.fetch(:source).rstrip, from: destination_receiver, to: template_receiver)
      end.join("\n") + "\n"
      anchor = gemspec_metadata_assignment_records(content, receiver: template_receiver).last
      anchor ||= gemspec_assignment_records(content, receiver: template_receiver).find { |record| record.fetch(:field) == "homepage" }
      return content unless anchor

      insert_lines_after(content, anchor.fetch(:end_line), insertion)
    end

    def gemspec_metadata_assignment_records(content, receiver:)
      lines = content.to_s.lines
      ruby_call_records(content, :[]=).filter_map do |call|
        next unless call.receiver&.slice.to_s == "#{receiver}.metadata"

        args = call.arguments&.arguments.to_a
        key = ruby_static_string_value(args.first)
        next if key.to_s.empty?

        start_line = call.location.start_line
        end_line = ruby_node_source_end_line(call)
        {
          key: key,
          value: ruby_static_string_value(args[1]),
          start_line: start_line,
          end_line: end_line,
          source: lines[(start_line - 1)..(end_line - 1)].to_a.join
        }
      end
    rescue Ast::Crispr::Error
      []
    end

    def default_gemspec_metadata_assignment?(record)
      DEFAULT_GEMSPEC_METADATA_VALUES[record.fetch(:key)] == record[:value]
    end

    def remove_gemspec_version_gem_dependency_when_disabled(content, facts, receiver:, template_declares_version_gem: false)
      return content if version_gem_enabled?(facts)
      return content if template_declares_version_gem && !version_gem_explicitly_disabled?(facts) && version_gem_runtime_compatible?(facts)

      cleaned = remove_gemspec_dependency_lines(content, receiver: receiver, names: ["version_gem"], runtime_only: true)
      remove_ruby_comment_lines_containing(cleaned, "version_gem")
    end

    def version_gem_explicitly_disabled?(facts)
      facts.to_h.dig(:version_gem, :enabled) == false
    end

    def remove_gemspec_version_gem_dependency_when_non_default_entrypoint(content, facts, receiver:)
      return content unless facts.to_h.dig(:version_gem, :non_default_entrypoint)

      cleaned = remove_gemspec_dependency_lines(content, receiver: receiver, names: ["version_gem"], runtime_only: true)
      remove_ruby_comment_lines_containing(cleaned, "version_gem")
    end

    def remove_gemspec_assignment(content, receiver:, field:)
      records_by_line = gemspec_assignment_records(content, receiver: receiver)
        .select { |record| record.fetch(:field) == field.to_s }
        .to_h { |record| [record.fetch(:start_line), record.merge(replacement: "")] }
      return content if records_by_line.empty?

      ensure_trailing_newline(replace_record_ranges(content, records_by_line).gsub(/\n{3,}/, "\n\n"))
    end

    def remove_gemspec_dependency_lines(content, receiver:, names:, runtime_only: false, development_only: false)
      wanted = names.map(&:to_s).to_set
      records_by_line = gemspec_dependency_records(content, receiver: receiver)
        .select { |record| wanted.include?(record.fetch(:name)) }
        .select { |record| !runtime_only || record.fetch(:kind) != "add_development_dependency" }
        .select { |record| !development_only || record.fetch(:kind) == "add_development_dependency" }
        .to_h { |record| [record.fetch(:start_line), record.merge(replacement: "")] }
      return content if records_by_line.empty?

      ensure_trailing_newline(replace_record_ranges(content, records_by_line).gsub(/\n{3,}/, "\n\n"))
    end

    def remove_ruby_comment_lines_containing(content, text)
      result = prism_parse_success(content)
      return content unless result

      selectors = result.comments.filter_map do |comment|
        next unless comment.location.slice.include?(text.to_s)

        {start_line: comment.location.start_line, end_line: comment.location.end_line}
      end
      return content if selectors.empty?

      ensure_trailing_newline(delete_line_ranges(content.to_s, selectors))
    end

    def version_gem_runtime_compatible?(facts)
      min_ruby = gemspec_runtime_floor_token(facts)
      return true if min_ruby.to_s.empty?

      Gem::Version.new(min_ruby) >= Gem::Version.new("2.2")
    rescue ArgumentError
      true
    end

    def version_gem_enabled?(facts)
      configured = facts.to_h.dig(:version_gem, :enabled)
      return configured if configured == true || configured == false

      return true if package_runtime_dependency_names(facts).include?("version_gem")

      facts.to_h.dig(:rubygems, :version_gem_default_enabled) == true
    end

    def gemspec_runtime_floor_token(facts)
      raw = facts.to_h.dig(:rubygems, :min_ruby).to_s.strip
      token = minimum_ruby_token(raw)
      return "0" if token.empty? && raw == "0"

      token
    end

    def explicit_zero_runtime_floor?(facts)
      facts.to_h.dig(:rubygems, :min_ruby).to_s.strip == "0"
    end

    def remove_duplicate_gemspec_assignments(content, receiver:, fields:)
      wanted = fields.map(&:to_s).to_set
      seen = Set.new
      duplicate_ranges = []
      gemspec_assignment_records(content, receiver: receiver).each do |record|
        field = record.fetch(:field).to_s
        next unless wanted.include?(field)

        key = [record.fetch(:receiver).to_s, field, record.fetch(:value)]
        if seen.include?(key)
          duplicate_ranges << [record.fetch(:start_line), record.fetch(:end_line)]
        else
          seen << key
        end
      end
      return content if duplicate_ranges.empty?

      lines = content.to_s.lines
      duplicate_ranges.reverse_each do |start_line, end_line|
        lines.slice!(start_line - 1, end_line - start_line + 1)
      end
      ensure_trailing_newline(lines.join)
    end

    def gemspec_block_param(source)
      call = gemspec_new_call(source)
      required = call&.block&.parameters&.parameters&.requireds&.first
      required&.name&.to_s
    end

    def normalize_gemspec_receiver(line, from:, to:)
      return line if from.to_s.empty? || to.to_s.empty? || from == to

      Prism::Merge::BlockVarRenamer.rename(line.to_s, old_var: from.to_s, new_var: to.to_s)
    end

    def normalize_gemspec_project_emoji(line, facts, field:)
      return line unless %w[summary description].include?(field.to_s)
      return line unless facts&.dig(:project_runtime, :project_emoji_configured)

      project_emoji = facts&.dig(:project_runtime, :project_emoji).to_s
      return line if project_emoji.empty?

      record = gemspec_assignment_records(line).find { |candidate| candidate.fetch(:field) == field.to_s }
      value = record&.fetch(:value)
      return line unless value.is_a?(String)
      string_node = ruby_first_simple_quoted_string_node(record[:value_node])
      return line unless string_node

      first_value = string_node.unescaped.to_s
      line.sub(first_value, "#{project_emoji} #{strip_leading_decorative_graphemes(first_value)}")
    end

    def gemspec_preserved_assignments(source, receiver:)
      gemspec_assignment_records(source, receiver: receiver).each_with_object({}) do |record, assignments|
        field = record.fetch(:field)
        next unless gemspec_preserved_assignment_fields.include?(field)
        next if assignments.key?(field)
        next if record.fetch(:source).include?("TODO:")

        assignments[field] = record.fetch(:source)
      end
    end

    def gemspec_preserved_assignment_fields
      %w[
        name
        authors
        email
        summary
        description
        homepage
        licenses
        required_ruby_version
        executables
      ]
    end

    def merge_gemspec_files_assignment(content, template_content:, destination_content:, template_receiver:, destination_receiver:)
      merged_record = gemspec_assignment_records(content, receiver: template_receiver).find { |record| record.fetch(:field) == "files" }
      template_record = gemspec_assignment_records(template_content, receiver: template_receiver).find { |record| record.fetch(:field) == "files" }
      destination_record = gemspec_assignment_records(destination_content, receiver: destination_receiver).find { |record| record.fetch(:field) == "files" }
      return content unless merged_record && template_record && destination_record

      replacement = merge_gemspec_files_assignment_source(
        merged_record: merged_record,
        template_record: template_record,
        destination_record: destination_record
      )
      replacement ||= replacement_for_supported_gemspec_files_assignment(
        template_record: template_record,
        destination_record: destination_record,
        template_receiver: template_receiver
      )
      unless replacement
        raise Error, "Unsupported gemspec spec.files assignment; kettle-jem requires an AST-mergeable Array, Dir[], or known Bundler git-ls-files assignment"
      end

      replace_source_range_lines(content, merged_record.fetch(:start_line), merged_record.fetch(:end_line), replacement)
    end

    def insert_missing_gemspec_files_assignment(content, template_content:, template_receiver:)
      return content if gemspec_assignment_records(content, receiver: template_receiver).any? { |record| record.fetch(:field) == "files" }

      template_record = gemspec_assignment_records(template_content, receiver: template_receiver).find { |record| record.fetch(:field) == "files" }
      return content unless template_record

      insertion = "#{normalize_gemspec_receiver(template_record.fetch(:source).rstrip, from: template_receiver, to: template_receiver)}\n"
      extra_rdoc = gemspec_assignment_records(content, receiver: template_receiver).find { |record| record.fetch(:field) == "extra_rdoc_files" }
      return insert_lines_before(content, extra_rdoc.fetch(:start_line), "\n#{insertion}") if extra_rdoc

      anchor = %w[required_ruby_version licenses homepage description summary name].filter_map do |field|
        gemspec_assignment_records(content, receiver: template_receiver).find { |record| record.fetch(:field) == field }
      end.first
      return insert_lines_after(content, anchor.fetch(:end_line), "\n#{insertion}") if anchor

      content
    end

    def merge_gemspec_files_assignment_source(merged_record:, template_record:, destination_record:)
      merged_parts = gemspec_files_collection_parts(merged_record)
      template_parts = gemspec_files_collection_parts(template_record)
      destination_parts = gemspec_files_collection_parts(destination_record)
      return unless merged_parts && template_parts && destination_parts

      if gemspec_files_collection_has_nonliteral_entries?(destination_parts)
        return merge_gemspec_files_assignment_with_destination_splats(
          merged_parts: merged_parts,
          destination_parts: destination_parts
        )
      end

      combined_groups = []
      seen = {}
      destination_groups = destination_parts.fetch(:groups).reject do |group|
        stale_generated_gemspec_files_group?(group) ||
          generated_gemspec_metadata_file_group?(group, template_parts)
      end
      merged_groups = merged_parts.fetch(:groups).reject do |group|
        generated_gemspec_metadata_file_group?(group, merged_parts)
      end

      [
        [destination_parts, destination_groups],
        [merged_parts, merged_groups],
        [template_parts, template_parts.fetch(:groups)]
      ].each do |parts, groups|
        groups.each do |group|
          next if seen[group.fetch(:key)]

          combined_groups << group.merge(source_collection_kind: gemspec_files_group_collection_kind(group, parts))
          seen[group.fetch(:key)] = true
        end
      end
      combined_groups = gemspec_files_normalize_dir_globs_for_array(combined_groups, merged_parts)
      if gemspec_files_collection_needs_concat?(merged_parts, combined_groups)
        return gemspec_files_concat_collection_source(merged_parts, combined_groups)
      end

      body = combined_groups.each_with_index.map do |group, index|
        gemspec_files_collection_group_source(group, trailing_comma: index < combined_groups.length - 1)
      end.join
      merged_parts.fetch(:opening) + body + merged_parts.fetch(:closing)
    end

    def gemspec_files_collection_needs_concat?(target_parts, groups)
      target_parts.fetch(:collection_kind) == :array &&
        groups.any? do |group|
          group.fetch(:source_collection_kind) == :dir &&
            group.fetch(:node).is_a?(::Prism::StringNode)
        end
    end

    def gemspec_files_concat_collection_source(target_parts, groups)
      dir_groups, array_groups = groups.partition do |group|
        group.fetch(:source_collection_kind) == :dir &&
          group.fetch(:node).is_a?(::Prism::StringNode)
      end
      return gemspec_files_array_collection_source(target_parts, array_groups) if dir_groups.empty?
      return gemspec_files_dir_collection_source(target_parts, dir_groups) if array_groups.empty?

      [
        gemspec_files_dir_collection_source(target_parts, dir_groups, closing: "] + [\n"),
        gemspec_files_collection_body_source(array_groups),
        target_parts.fetch(:closing)
      ].join
    end

    def gemspec_files_dir_collection_source(target_parts, groups, closing: nil)
      opening = target_parts.fetch(:opening).sub("= [", "= Dir[")
      [
        opening,
        gemspec_files_collection_body_source(groups),
        closing || target_parts.fetch(:closing)
      ].join
    end

    def gemspec_files_array_collection_source(target_parts, groups)
      [
        target_parts.fetch(:opening),
        gemspec_files_collection_body_source(groups),
        target_parts.fetch(:closing)
      ].join
    end

    def gemspec_files_collection_body_source(groups)
      groups.each_with_index.map do |group, index|
        gemspec_files_collection_group_source(group, trailing_comma: index < groups.length - 1)
      end.join
    end

    def gemspec_files_collection_group_source(group, trailing_comma:)
      lines = group.fetch(:lines).dup
      return lines.join unless trailing_comma

      entry_index = lines.rindex { |line| !line.strip.empty? && !line.lstrip.start_with?("#") }
      return lines.join unless entry_index

      line = lines.fetch(entry_index)
      return lines.join if line.rstrip.end_with?(",")

      newline = line.end_with?("\n") ? "\n" : ""
      lines[entry_index] = "#{line.delete_suffix("\n").rstrip},#{newline}"
      lines.join
    end

    def replacement_for_supported_gemspec_files_assignment(template_record:, destination_record:, template_receiver:)
      if generic_bundler_gemspec_files_assignment?(destination_record)
        normalize_gemspec_receiver(
          template_record.fetch(:source),
          from: template_receiver,
          to: template_receiver
        )
      end
    end

    def merge_gemspec_files_assignment_with_destination_splats(merged_parts:, destination_parts:)
      return unless %i[array concat].include?(destination_parts.fetch(:collection_kind))

      merged_keys = merged_parts.fetch(:groups).map { |group| group.fetch(:key) }.to_set
      destination_groups = destination_parts.fetch(:groups).reject do |group|
        stale_generated_gemspec_files_group?(group) ||
          generated_gemspec_metadata_file_group?(group, merged_parts)
      end
      destination_only_nonliteral = destination_groups.any? do |group|
        !group.fetch(:node).is_a?(::Prism::StringNode) &&
          !merged_keys.include?(group.fetch(:key)) &&
          !supported_gemspec_files_nonliteral_group?(group)
      end
      return if destination_only_nonliteral

      destination_groups_by_key = destination_groups.to_h do |group|
        [group.fetch(:key), group.merge(source_collection_kind: gemspec_files_group_collection_kind(group, destination_parts))]
      end
      seen = Set.new
      merged_groups = merged_parts.fetch(:groups).reject do |group|
        generated_gemspec_metadata_file_group?(group, merged_parts)
      end
      groups = merged_groups.map do |group|
        key = group.fetch(:key)
        seen << key
        destination_groups_by_key.fetch(key, group.merge(source_collection_kind: gemspec_files_group_collection_kind(group, merged_parts)))
      end
      destination_groups.each do |group|
        next if seen.include?(group.fetch(:key))

        groups << group.merge(source_collection_kind: gemspec_files_group_collection_kind(group, destination_parts))
      end
      groups = gemspec_files_normalize_dir_globs_for_array(groups, merged_parts)

      if gemspec_files_collection_needs_concat?(merged_parts, groups)
        return gemspec_files_concat_collection_source(merged_parts, groups)
      end

      gemspec_files_array_collection_source(merged_parts, groups)
    end

    def gemspec_files_normalize_dir_globs_for_array(groups, target_parts)
      return groups unless target_parts.fetch(:collection_kind) == :array

      groups.map do |group|
        next group unless group.fetch(:source_collection_kind, nil) == :dir

        node = group.fetch(:node)
        next group unless node.is_a?(::Prism::StringNode)

        pattern = node.unescaped.to_s
        lines = group.fetch(:lines)
        entry_line = lines.reverse.find { |line| !line.strip.empty? && !line.lstrip.start_with?("#") }.to_s
        indent = entry_line[/\A\s*/].to_s
        comments = lines.take_while { |line| line.strip.empty? || line.lstrip.start_with?("#") }
        group.merge(
          key: [:package_glob, pattern],
          source_collection_kind: :array,
          lines: comments + [%(#{indent}*enumerate_package_glob.call(File.join(gemspec_root, #{pattern.dump}))\n)]
        )
      end
    end

    def gemspec_files_collection_parts(record)
      value_node = record.fetch(:value_node)
      if gemspec_files_concat_call_node?(value_node)
        return gemspec_files_concat_collection_parts(record, value_node)
      end

      gemspec_files_single_collection_parts(record, value_node)
    end

    def gemspec_files_single_collection_parts(record, value_node)
      element_nodes = gemspec_files_collection_element_nodes(value_node)
      return unless element_nodes

      lines = record.fetch(:source).lines
      return if lines.length < 3

      groups = gemspec_files_collection_groups(record: record, element_nodes: element_nodes, lines: lines)
      return unless groups

      {
        collection_kind: gemspec_files_collection_kind(value_node),
        opening: lines.first,
        closing: lines.last,
        groups: groups
      }
    end

    def gemspec_files_concat_collection_parts(record, value_node)
      arguments = Array(value_node.arguments&.arguments)
      left_record = gemspec_files_child_collection_record(record, value_node.receiver)
      right_record = gemspec_files_child_collection_record(record, arguments.first)
      return unless left_record && right_record

      left_parts = gemspec_files_single_collection_parts(
        left_record,
        value_node.receiver
      )
      right_parts = gemspec_files_single_collection_parts(
        right_record,
        arguments.first
      )
      return unless left_parts && right_parts

      groups = left_parts.fetch(:groups).map do |group|
        group.merge(source_collection_kind: left_parts.fetch(:collection_kind))
      end
      groups.concat(
        right_parts.fetch(:groups).map do |group|
          group.merge(source_collection_kind: right_parts.fetch(:collection_kind))
        end
      )

      {
        collection_kind: :concat,
        opening: left_parts.fetch(:opening),
        closing: right_parts.fetch(:closing),
        groups: groups
      }
    end

    def gemspec_files_child_collection_record(record, value_node)
      source_start_line = record.fetch(:start_line)
      lines = record.fetch(:source).lines
      start_index = value_node.location.start_line - source_start_line
      end_index = value_node.location.end_line - source_start_line
      child_lines = lines[start_index..end_index]
      return unless child_lines

      record.merge(
        value_node: value_node,
        start_line: value_node.location.start_line,
        end_line: value_node.location.end_line,
        source: child_lines.join
      )
    end

    def gemspec_files_collection_kind(value_node)
      return :dir if gemspec_files_dir_call_node?(value_node)
      return :array if value_node.is_a?(::Prism::ArrayNode)

      nil
    end

    def gemspec_files_collection_element_nodes(value_node)
      if gemspec_files_dir_call_node?(value_node)
        return Array(value_node.arguments&.arguments)
      end
      return value_node.elements if value_node.is_a?(::Prism::ArrayNode)

      nil
    end

    def gemspec_files_group_collection_kind(group, parts)
      group.fetch(:source_collection_kind, parts.fetch(:collection_kind))
    end

    def gemspec_files_concat_call_node?(node)
      node.is_a?(::Prism::CallNode) &&
        node.name == :+ &&
        node.block.nil? &&
        node.receiver &&
        Array(node.arguments&.arguments).length == 1
    end

    def gemspec_files_dir_call_node?(node)
      node.is_a?(::Prism::CallNode) &&
        node.name == :[] &&
        node.block.nil? &&
        node.receiver&.slice == "Dir"
    end

    def gemspec_files_collection_groups(record:, element_nodes:, lines:)
      pending = []
      groups = []
      body_lines = lines[1...-1]
      nodes = element_nodes.dup

      body_lines.each_with_index do |line, body_index|
        current_entry = nodes.first

        if current_entry && current_entry.location.start_line == record.fetch(:start_line) + body_index + 1
          unless gemspec_files_collection_entry_node?(current_entry)
            groups = nil
            break
          end

          groups << {
            key: gemspec_files_collection_entry_key(current_entry),
            node: current_entry,
            lines: pending + [line]
          }
          pending = []
          nodes.shift
          next
        end

        if line.strip.empty? || line.lstrip.start_with?("#")
          pending << line
          next
        end
      end

      return unless groups
      return if nodes.any?

      groups
    end

    def gemspec_files_collection_entry_node?(node)
      node.location.start_line == node.location.end_line &&
        (node.is_a?(::Prism::StringNode) || node.is_a?(::Prism::SplatNode))
    end

    def gemspec_files_collection_entry_key(node)
      return [:string, node.unescaped] if node.is_a?(::Prism::StringNode)
      return [:splat, gemspec_files_splat_expression_key(node.expression)] if node.is_a?(::Prism::SplatNode)

      [:source, node.slice]
    end

    def gemspec_files_splat_expression_key(node)
      if node.is_a?(::Prism::CallNode)
        return [
          :call,
          node.receiver&.slice,
          node.name,
          Array(node.arguments&.arguments).map { |argument| ruby_static_string_value(argument) || argument.slice }
        ]
      end

      node&.slice
    end

    # Accept only the generated package helpers that can safely survive a
    # template revision. Other destination splats remain unsupported rather
    # than being silently treated as template-owned package content.
    def supported_gemspec_files_nonliteral_group?(group)
      node = group.fetch(:node)
      return false unless node.is_a?(::Prism::SplatNode)

      expression = node.expression
      return true if expression.is_a?(::Prism::LocalVariableReadNode) && expression.name == :package_metadata_files
      return false unless expression.is_a?(::Prism::CallNode) && expression.name == :call

      case expression.receiver&.slice
      when "enumerate_package_files"
        argument = Array(expression.arguments&.arguments).first
        %w[lib exe certs sig].include?(ruby_static_string_value(argument))
      when "enumerate_package_glob"
        generated_gemspec_package_glob_call?(expression)
      else
        false
      end
    end

    def generated_gemspec_package_glob_call?(node)
      arguments = Array(node.arguments&.arguments)
      return false unless arguments.length == 1

      join = arguments.first
      return false unless join.is_a?(::Prism::CallNode) && join.receiver&.slice == "File" && join.name == :join

      join_arguments = Array(join.arguments&.arguments)
      root = join_arguments.shift
      gemspec_root_reference_node?(root) &&
        join_arguments.any? &&
        join_arguments.all? { |argument| argument.is_a?(::Prism::StringNode) }
    end

    def gemspec_root_reference_node?(node)
      return node.name == :gemspec_root if node.is_a?(::Prism::LocalVariableReadNode)

      node.is_a?(::Prism::CallNode) &&
        node.receiver.nil? &&
        node.name == :gemspec_root &&
        Array(node.arguments&.arguments).empty? &&
        node.block.nil?
    end

    def stale_generated_gemspec_files_group?(group)
      node = group.fetch(:node)
      if node.is_a?(::Prism::StringNode)
        path = node.unescaped.to_s
        basename = File.basename(path, ".md")
        return true if %w[
          CITATION.md
          CITATION.cff
          CODE_OF_CONDUCT.md
          CONTRIBUTING.md
          FUNDING.md
          RUBOCOP.md
          SECURITY.md
        ].include?(path)
        return true if stale_generated_gemspec_package_glob?(path)
        return true if path.end_with?(".md") && basename != "LICENSE" && known_license_template_basenames.include?(basename)

        return false
      end

      key = group.fetch(:key)
      return false unless key.is_a?(Array) && key.first == :splat

      stale_generated_gemspec_splat_key?(key[1])
    end

    def stale_generated_gemspec_splat_key?(key)
      return false unless key.is_a?(Array) && key.first == :call

      receiver, method_name, arguments = key[1], key[2], Array(key[3])
      return true if receiver == "enumerate_package_files" && method_name == :call && %w[certs sig].include?(arguments.first.to_s)
      return true if receiver == "Dir" && method_name == :[] && arguments.first.to_s == "sig/**/*.rbs"

      false
    end

    def stale_generated_gemspec_package_glob?(path)
      %w[
        certs/**/*
        exe/*
        exe/**/*
        lib/**/*.rake
        lib/**/*.rb
        sig/**/*.rbs
      ].include?(path.to_s)
    end

    def generated_gemspec_metadata_file_group?(group, target_parts)
      return false unless gemspec_files_collection_has_package_metadata_splat?(target_parts)

      node = group.fetch(:node)
      return false unless node.is_a?(::Prism::StringNode)

      %w[CHANGELOG.md LICENSE.md README.md].include?(node.unescaped.to_s)
    end

    def gemspec_files_collection_has_package_metadata_splat?(parts)
      parts.fetch(:groups).any? do |group|
        key = group.fetch(:key)
        key.is_a?(Array) &&
          key.first == :splat &&
          (key[1] == "package_metadata_files" || key[1] == [:call, nil, :package_metadata_files, []])
      end
    end

    def gemspec_files_collection_has_nonliteral_entries?(parts)
      parts.fetch(:groups).any? do |group|
        node = group.fetch(:node)
        !node.is_a?(::Prism::StringNode)
      end
    end

    def generic_bundler_gemspec_files_assignment?(record)
      node = record.fetch(:value_node)
      io_popen_gemspec_files_assignment?(node) || legacy_git_ls_files_assignment?(node)
    end

    def io_popen_gemspec_files_assignment?(node)
      node.is_a?(::Prism::CallNode) &&
        node.name == :popen &&
        node.receiver&.slice == "IO" &&
        generic_bundler_gemspec_files_command?(node.arguments&.arguments&.first)
    end

    # Legacy gemspecs commonly shell out with backticks, then apply split and
    # optional filtering calls. Prism lets us recognize that bounded pipeline
    # without interpreting arbitrary Ruby.
    def legacy_git_ls_files_assignment?(node)
      return legacy_git_ls_files_chdir_assignment?(node) if node.is_a?(::Prism::CallNode) && node.name == :chdir

      current = node
      while current.is_a?(::Prism::CallNode) && %i[split reject select grep map].include?(current.name)
        current = current.receiver
      end
      current.is_a?(::Prism::XStringNode) && %w[git\ ls-files git\ ls-files\ -z].include?(current.unescaped.to_s)
    end

    # Older Bundler gemspecs commonly scope a git-ls-files pipeline with
    # Dir.chdir(File.expand_path(__dir__)). This wrapper does not change the
    # package-file semantics, so recognize it without evaluating arbitrary
    # destination Ruby. The block must contain exactly one known pipeline.
    def legacy_git_ls_files_chdir_assignment?(node)
      return false unless node.receiver&.slice == "Dir"
      return false unless Array(node.arguments&.arguments).length == 1

      body = Array(node.block&.body&.body)
      body.length == 1 && legacy_git_ls_files_assignment?(body.first)
    end

    def generic_bundler_gemspec_files_command?(node)
      node.is_a?(::Prism::ArrayNode) &&
        node.elements.map { |element| ruby_static_string_value(element) } == %w[git ls-files -z]
    end

    def env_overridden_gemspec_fields(env)
      fields = []
      fields << "authors" if present_template_token_value?(env["KJ_AUTHOR_NAME"].to_s)
      fields << "email" if present_template_token_value?(env["KJ_AUTHOR_EMAIL"].to_s)
      fields
    end

    def replace_gemspec_assignment_sources(content, replacements, receiver:)
      return content if replacements.empty?

      records_by_line = gemspec_assignment_records(content, receiver: receiver).each_with_object({}) do |record, index|
        field = record.fetch(:field)
        next unless replacements.key?(field)

        index[record.fetch(:start_line)] = record.merge(replacement: "#{replacements.fetch(field)}\n")
      end
      replace_record_ranges(content, records_by_line)
    end

    def insert_missing_gemspec_assignment_sources(content, replacements, receiver:)
      return content if replacements.empty?

      present_fields = gemspec_assignment_records(content, receiver: receiver).map { |record| record.fetch(:field) }.to_set
      missing_sources = gemspec_preserved_assignment_fields.filter_map do |field|
        next if present_fields.include?(field)

        source = replacements[field]
        "#{source}\n" if source
      end
      return content if missing_sources.empty?

      first_dependency_line = gemspec_dependency_records(content, receiver: receiver).map { |record| record.fetch(:start_line) }.min
      insert_lines_before(content, first_dependency_line || gemspec_end_line(content), missing_sources.join)
    end

    def preserve_gemspec_dependency_lines(template_content, destination_content, template_receiver:, destination_receiver:, facts: nil)
      namespace = facts.to_h.dig(:rubygems, :namespace).to_s
      template_dependencies = gemspec_dependency_line_index(template_content, receiver: template_receiver)
      destination_dependencies = gemspec_dependency_line_index(destination_content, receiver: destination_receiver)
        .transform_values do |source|
          normalized = normalize_gemspec_receiver(source, from: destination_receiver, to: template_receiver)
          normalized = normalize_gemspec_dependency_version_requirements(normalized, receiver: template_receiver, namespace: namespace)
          enforce_gemspec_dependency_minimum_requirements(normalized, receiver: template_receiver)
        end
      destination_dependencies = destination_dependencies.reject do |key, _source|
        retired_gemspec_development_dependency_key?(key)
      end
      return template_content if destination_dependencies.empty?

      replacements, additions = destination_dependencies.partition do |key, source|
        template_dependencies.key?(key) &&
          gemspec_dependency_source_newer?(source, template_dependencies.fetch(key), receiver: template_receiver)
      end.map(&:to_h)

      merged = replace_matching_gemspec_dependency_lines(template_content, replacements, receiver: template_receiver)
      append_missing_gemspec_dependency_lines(merged, additions, receiver: template_receiver)
    end

    def preserve_gemspec_freeze_blocks(content, destination_content, facts:, receiver:)
      blocks = freeze_marker_blocks(destination_content, freeze_token: facts.to_h.dig(:project_runtime, :freeze_token))
      return content if blocks.empty?

      merged = content.to_s
      blocks.each do |block|
        next if gemspec_freeze_block_structurally_managed?(block, receiver: receiver)
        next if merged.include?(block.join)

        insertion = "\n#{block.join}\n"
        require_paths = gemspec_assignment_records(merged, receiver: receiver).find { |record| record.fetch(:field) == "require_paths" }
        merged = if require_paths
          insert_lines_before(merged, require_paths.fetch(:start_line), insertion)
        else
          insert_lines_before(merged, gemspec_end_line(merged), insertion)
        end
      end
      ensure_trailing_newline(merged.gsub(/\n{3,}/, "\n\n"))
    end

    def gemspec_freeze_block_structurally_managed?(block, receiver:)
      gemspec_assignment_records(block.join, receiver: receiver).any? { |record| record.fetch(:field) == "files" }
    rescue Ast::Crispr::Error, Prism::ParseError
      false
    end

    def freeze_marker_blocks(content, freeze_token: nil)
      marker = freeze_token.to_s.empty? ? "kettle-jem" : freeze_token.to_s
      lines = content.to_s.lines
      blocks = []
      index = 0
      while index < lines.length
        unless lines[index].include?("# #{marker}:freeze")
          index += 1
          next
        end

        start_index = index
        while index < lines.length
          index += 1
          break if lines[index - 1].include?("# #{marker}:unfreeze")
        end
        blocks << lines[start_index...index]
      end
      blocks
    end

    def replace_matching_gemspec_dependency_lines(content, destination_dependencies, receiver:)
      records_by_line = gemspec_dependency_records(content, receiver: receiver).each_with_object({}) do |record, index|
        replacement = destination_dependencies[gemspec_dependency_record_key(record)]
        index[record.fetch(:start_line)] = record.merge(replacement: replacement) if replacement
      end
      replace_record_ranges(content, records_by_line)
    end

    def normalize_gemspec_dependency_version_requirements(source, receiver:, namespace:)
      return source if namespace.to_s.empty?

      replacements = ruby_call_records(source, nil).flat_map do |call|
        next [] unless gemspec_dependency_call_kind(call)

        Array(call.arguments&.arguments).drop(1).filter_map do |argument|
          replacement = ruby_project_version_interpolated_string_source(argument, receiver: receiver, namespace: namespace)
          next unless replacement

          {start_offset: argument.location.start_offset, end_offset: argument.location.end_offset, replacement: replacement}
        end
      end
      return source if replacements.empty?

      replace_source_offsets(source, replacements)
    end

    def enforce_gemspec_dependency_minimum_requirements(source, receiver:)
      replacements = ruby_call_records(source, nil).filter_map do |call|
        next unless gemspec_dependency_call_kind(call)
        next if receiver && call.receiver&.slice != receiver.to_s

        name = ruby_string_argument(call)
        requirement = GEMSPEC_DEPENDENCY_MINIMUM_REQUIREMENTS[name]
        next unless requirement
        next if gemspec_dependency_requirements_satisfy_floor?(ruby_string_arguments(call).drop(1), requirement)

        gemspec_dependency_minimum_requirement_replacement(call, requirement)
      end
      return source if replacements.empty?

      replace_source_offsets(source, replacements)
    end

    def gemspec_dependency_requirements_satisfy_floor?(requirements, floor_requirement)
      floor = Gem::Requirement.new(floor_requirement).requirements.first.last
      requirements.any? do |requirement|
        parsed = Gem::Requirement.new(requirement.to_s).requirements
        parsed.any? do |operator, version|
          %w[>= > =].include?(operator.to_s) && version >= floor
        end
      rescue ArgumentError
        false
      end
    end

    def gemspec_dependency_minimum_requirement_replacement(call, requirement)
      arguments = Array(call.arguments&.arguments)
      floor = Gem::Requirement.new(requirement).requirements.first.last
      existing_floor = arguments.drop(1).find do |argument|
        value = ruby_static_string_value(argument)
        next false unless value

        parsed = Gem::Requirement.new(value).requirements
        parsed.any? { |operator, version| %w[>= > =].include?(operator.to_s) && version < floor }
      rescue ArgumentError
        false
      end
      if existing_floor
        {
          start_offset: existing_floor.location.start_offset,
          end_offset: existing_floor.location.end_offset,
          replacement: JSON.generate(requirement)
        }
      else
        insertion_offset = arguments.last.location.end_offset
        {
          start_offset: insertion_offset,
          end_offset: insertion_offset,
          replacement: ", #{JSON.generate(requirement)}"
        }
      end
    end

    def ruby_project_version_interpolated_string_source(node, receiver:, namespace:)
      return unless node.is_a?(::Prism::InterpolatedStringNode)

      parts = node.parts.map do |part|
        case part
        when ::Prism::StringNode
          ruby_double_quoted_string_body(part.unescaped.to_s)
        when ::Prism::EmbeddedStatementsNode
          next unless ruby_project_version_embedded_statements?(part, namespace: namespace)

          "\#{#{receiver}.version}"
        end
      end
      return if parts.any?(&:nil?)

      %("#{parts.join}")
    end

    def ruby_project_version_embedded_statements?(node, namespace:)
      body = node.statements&.body.to_a
      return false unless body.length == 1

      ruby_project_version_constant_path?(body.first, namespace: namespace)
    end

    def ruby_project_version_constant_path?(node, namespace:)
      return false unless node.is_a?(::Prism::ConstantPathNode)

      segments = ruby_constant_path_segments(node)
      namespace_segments = namespace.to_s.split("::").reject(&:empty?)
      segments == namespace_segments + ["VERSION"] ||
        segments == namespace_segments + ["Version", "VERSION"]
    end

    def sort_runtime_gemspec_dependency_lines(content, receiver:)
      records = gemspec_dependency_records(content, receiver: receiver).select do |record|
        record.fetch(:kind) != "add_development_dependency" && record.fetch(:start_line) == record.fetch(:end_line)
      end
      return content if records.length < 2

      sorted_sources = records.sort_by { |record| [gemspec_dependency_sort_key(record.fetch(:name)), record.fetch(:source).to_s] }.map { |record| record.fetch(:source) }
      records_by_line = records.sort_by { |record| record.fetch(:start_line) }.each_with_index.to_h do |record, index|
        [record.fetch(:start_line), record.merge(replacement: sorted_sources.fetch(index))]
      end
      replace_record_ranges(content, records_by_line)
    end

    def gemspec_dependency_sort_key(name)
      name.to_s.tr("_", "-")
    end

    def remove_gemspec_development_dependencies_already_runtime(content, receiver:)
      records = gemspec_dependency_records(content, receiver: receiver)
      runtime_names = records.each_with_object(Set.new) do |record, names|
        next if record.fetch(:kind) == "add_development_dependency"

        names << record.fetch(:name)
      end
      return content if runtime_names.empty?

      duplicate_development_records = records.select do |record|
        record.fetch(:kind) == "add_development_dependency" && runtime_names.include?(record.fetch(:name))
      end
      return content if duplicate_development_records.empty?

      records_by_line = duplicate_development_records.to_h do |record|
        [record.fetch(:start_line), record.merge(replacement: "")]
      end
      replace_record_ranges(content, records_by_line)
    end

    # Template dependencies precede preserved destination dependencies. Keep
    # the first declaration for each dependency kind/name pair so an old,
    # weaker destination declaration cannot survive beside its managed one.
    def remove_duplicate_gemspec_dependency_lines(content, receiver:)
      seen = Set.new
      duplicates = gemspec_dependency_records(content, receiver: receiver).select do |record|
        key = gemspec_dependency_record_key(record)
        already_seen = seen.include?(key)
        seen << key
        already_seen
      end
      return content if duplicates.empty?

      replace_record_ranges(content, duplicates.to_h { |record| [record.fetch(:start_line), record.merge(replacement: "")] })
    end

    def remove_empty_gemspec_development_dependency_section_headings(content, receiver:)
      ensure_runtime_dependencies!
      target = empty_gemspec_development_dependency_sections_target(receiver: receiver)
      actor = Ast::Crispr::Delete.call(content: content.to_s, target: target, source_label: "gemspec")
      actor.updated_content
    end

    # Prism does not expose comments as normal AST statements, so dependency-section
    # headings are bounded to single-line comments after the gemspec development note.
    def gemspec_dependency_section_heading_comment?(stripped_line)
      stripped_line.start_with?("# ") &&
        !stripped_line.start_with?("# NOTE:") &&
        !stripped_line.start_with?("#       ")
    end

    def empty_gemspec_development_dependency_sections_target(receiver:)
      Ast::Crispr::OwnerSelector.new(
        id: "empty_gemspec_development_dependency_sections",
        limit: {at_least: 0},
        metadata: {
          adapter: Ast::Crispr::Ruby::Prism.adapter,
          owner_scope: :ruby_comments,
          selector_kind: :owner_filter,
          selection_intent: :section_branch,
          include_trailing_gap: true
        },
        locate: lambda do |context|
          lines = context.lines
          note_index = lines.find_index do |line|
            line.lstrip.start_with?("# NOTE: It is preferable to list development dependencies")
          end
          next [] unless note_index

          dependency_line_indexes = gemspec_dependency_records(context.content, receiver: receiver)
            .map { |record| record.fetch(:start_line) - 1 }
            .to_set
          comments = context.structural_owners(owner_scope: :ruby_comments)
          heading_line_indexes = comments.filter_map do |comment|
            line_index = comment.location.start_line - 1
            next if line_index <= note_index
            next unless gemspec_dependency_section_heading_comment?(lines.fetch(line_index).lstrip)

            line_index
          end.to_set

          empty_gemspec_development_dependency_section_matches(
            lines,
            heading_line_indexes: heading_line_indexes,
            dependency_line_indexes: dependency_line_indexes
          )
        end
      )
    end

    def empty_gemspec_development_dependency_section_matches(lines, heading_line_indexes:, dependency_line_indexes:)
      matches = []
      sorted_headings = heading_line_indexes.to_a.sort
      visited = Set.new
      sorted_headings.each do |heading_start|
        next if visited.include?(heading_start)

        heading_end = heading_start
        while heading_line_indexes.include?(heading_end)
          visited << heading_end
          heading_end += 1
        end

        cursor = heading_end
        cursor += 1 while cursor < lines.length && lines[cursor].strip != "end" && !heading_line_indexes.include?(cursor)
        next if (heading_end...cursor).any? { |line_index| dependency_line_indexes.include?(line_index) }

        start_line_index = heading_start
        start_line_index -= 1 if lines[heading_start - 1]&.strip == ""
        end_line_index = heading_end - 1
        matches << Ast::Crispr::Match.new(
          start_line: start_line_index + 1,
          end_line: end_line_index + 1,
          metadata: {
            start_boundary: :comment_region_start,
            end_boundary: :owner_end_plus_trailing_gap,
            payload_kind: :section_branch
          }
        )
      end
      matches
    end

    def append_missing_gemspec_dependency_lines(content, destination_dependencies, receiver:)
      existing_keys = gemspec_dependency_line_index(content, receiver: receiver).keys
      missing_lines = destination_dependencies.except(*existing_keys).values
      return content if missing_lines.empty?

      runtime_lines, development_lines = missing_lines.partition do |line|
        key = gemspec_dependency_line_key(line, receiver: receiver)
        key && key.first != "add_development_dependency"
      end

      merged = content.to_s
      merged = insert_missing_runtime_gemspec_dependency_lines(merged, runtime_lines, receiver: receiver)
      insert_missing_development_gemspec_dependency_lines(merged, development_lines)
    end

    def insert_missing_runtime_gemspec_dependency_lines(content, missing_lines, receiver:)
      return content if missing_lines.empty?

      lines = content.to_s.lines
      insertion_index = runtime_gemspec_dependency_insertion_index(lines, receiver: receiver)
      lines.insert(insertion_index, *missing_lines)
      lines.join
    end

    def insert_missing_development_gemspec_dependency_lines(content, missing_lines)
      return content if missing_lines.empty?

      insert_lines_before(content, gemspec_end_line(content), missing_lines.join)
    end

    def runtime_gemspec_dependency_insertion_index(lines, receiver:)
      note_index = lines.find_index { |line| line.lstrip.start_with?("# NOTE: It is preferable to list development dependencies") }
      return note_index - 1 if note_index&.positive? && lines[note_index - 1].strip.empty?
      return note_index if note_index

      development_line = gemspec_dependency_records(lines.join, receiver: receiver).find { |record| record.fetch(:kind) == "add_development_dependency" }&.fetch(:start_line)
      development_index = development_line && development_line - 1
      return development_index if development_index

      gemspec_end_line(lines.join) - 1
    end

    def gemspec_dependency_line_index(source, receiver:)
      gemspec_dependency_records(source, receiver: receiver).each_with_object({}) do |record, dependencies|
        key = gemspec_dependency_record_key(record)
        dependencies[key] ||= record.fetch(:source)
      end
    end

    def gemspec_dependency_names(source)
      gemspec_dependency_records(source).map { |record| record.fetch(:name) }
    end

    def gemspec_self_dependency_names(request, package_name)
      names = [package_name.to_s]
      token_value = runtime_context_value(request, :template_tokens, "KJ|GEM_NAME")
      names << "{KJ|GEM_NAME}" if token_value.to_s == package_name.to_s
      names.reject(&:empty?).uniq
    end

    def remove_gemspec_self_dependency_lines(content, package_name, receiver:)
      name = package_name.to_s
      return content if name.empty?

      remove_indexes = Set.new
      gemspec_dependency_records(content, receiver: receiver).each do |record|
        next unless record.fetch(:name) == name

        (record.fetch(:start_line)..record.fetch(:end_line)).each { |line_number| remove_indexes << (line_number - 1) }
      end
      lines = content.to_s.lines.each_with_index.reject { |_line, index| remove_indexes.include?(index) }.map(&:first)
      ensure_trailing_newline(lines.join.gsub(/\n{3,}/, "\n\n"))
    end

    def gemspec_dependency_line_key(line, receiver:)
      record = gemspec_dependency_records(line, receiver: receiver).first
      gemspec_dependency_record_key(record) if record
    end

    def gemspec_dependency_record_key(record)
      [record.fetch(:kind), record.fetch(:name)]
    end

    def retired_gemspec_development_dependency_key?(key)
      key.first == "add_development_dependency" &&
        RETIRED_GEMSPEC_DEVELOPMENT_DEPENDENCIES.include?(key.last)
    end

    def gemspec_dependency_source_newer?(candidate_source, current_source, receiver:)
      candidate = gemspec_dependency_records(candidate_source, receiver: receiver).first
      current = gemspec_dependency_records(current_source, receiver: receiver).first
      return false unless candidate && current

      gemspec_dependency_record_version(candidate) > gemspec_dependency_record_version(current)
    end

    def gemspec_dependency_record_version(record)
      versions = record.fetch(:requirements, []).filter_map do |requirement|
        Gem::Requirement.new(requirement.to_s).requirements.map(&:last)
      rescue ArgumentError
        nil
      end.flatten
      versions.max || Gem::Version.new("0")
    end

    def gemspec_assignment_records(source, receiver: nil)
      lines = source.to_s.lines
      ruby_call_records(source, nil).filter_map do |call|
        field = gemspec_assignment_field(call)
        next unless field
        next if receiver && call.receiver&.slice != receiver.to_s
        end_line = ruby_node_source_end_line(call)

        {
          field: field,
          value: gemspec_assignment_value(call),
          value_node: call.arguments&.arguments&.first,
          receiver: call.receiver&.slice,
          start_line: call.location.start_line,
          end_line: end_line,
          source: (lines[(call.location.start_line - 1)..(end_line - 1)] || []).join
        }
      end
    end

    def gemspec_assignment_field(call)
      name = call.name.to_s
      return unless name.end_with?("=")
      return if name == "[]="

      name.delete_suffix("=")
    end

    def gemspec_assignment_value(call)
      argument = call.arguments&.arguments&.first
      case argument
      when ::Prism::StringNode, ::Prism::InterpolatedStringNode, ::Prism::CallNode
        ruby_static_string_value(argument) || argument&.slice
      when ::Prism::ArrayNode
        argument.elements.filter_map { |element| ruby_static_string_value(element) }
      else
        argument&.slice
      end
    end

    def ruby_first_simple_quoted_string_node(node)
      case node
      when ::Prism::StringNode
        node if ruby_simple_quoted_string_node?(node)
      when ::Prism::InterpolatedStringNode
        node.compact_child_nodes.each do |child|
          string_node = ruby_first_simple_quoted_string_node(child)
          return string_node if string_node
        end
        nil
      when ::Prism::CallNode
        ruby_first_simple_quoted_string_node(node.receiver)
      end
    end

    def ruby_simple_quoted_string_node?(node)
      opening = node.opening_loc&.slice
      opening == '"' || opening == "'"
    end

    def gemspec_field_receiver_and_name(field)
      parts = field.to_s.split(".")
      return [nil, field.to_s] if parts.length == 1

      [parts[0...-1].join("."), parts.last]
    end

    def replace_record_ranges(content, records_by_line)
      return content if records_by_line.empty?

      skip_until = 0
      content.to_s.lines.each_with_index.flat_map do |line, index|
        line_number = index + 1
        next [] if line_number < skip_until

        record = records_by_line[line_number]
        if record
          skip_until = record.fetch(:end_line) + 1
          record.fetch(:replacement)
        else
          line
        end
      end.join
    end

    def replace_source_range_lines(content, start_line, end_line, replacement)
      replace_record_ranges(content, {start_line => {end_line: end_line, replacement: replacement}})
    end

    def insert_lines_before(content, line_number, insertion)
      lines = content.to_s.lines
      lines.insert([line_number - 1, 0].max, insertion)
      lines.join
    end

    def insert_lines_after(content, line_number, insertion)
      lines = content.to_s.lines
      lines.insert(line_number, insertion)
      lines.join
    end

    def leading_whitespace(source)
      text = source.to_s
      text[0...(text.length - text.lstrip.length)]
    end

    def gemspec_dependency_records(source, receiver: nil)
      lines = source.to_s.lines
      ruby_call_records(source, nil).filter_map do |call|
        kind = gemspec_dependency_call_kind(call)
        next unless kind
        next if receiver && call.receiver&.slice != receiver.to_s

        name = ruby_string_argument(call)
        next unless name

        {
          kind: kind,
          name: name,
          requirement: ruby_string_argument_at(call, 1),
          requirements: ruby_string_arguments(call).drop(1),
          receiver: call.receiver&.slice,
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call),
          source: (lines[(call.location.start_line - 1)..(ruby_node_source_end_line(call) - 1)] || []).join
        }
      end
    end

    def gemspec_dependency_call_kind(call)
      case call.name
      when :add_dependency, :add_runtime_dependency, :add_development_dependency
        call.name.to_s
      end
    end

    def gemspec_new_call(source)
      ruby_call_records(source, :new).find { |call| call.receiver&.slice == "Gem::Specification" }
    end

    def gemspec_end_line(source)
      gemspec_new_call(source)&.location&.end_line || source.to_s.lines.length + 1
    end

    def template_file_type(recipe)
      configured = recipe.dig(:template_preference, :file_type).to_s
      return configured.to_sym unless configured.empty?

      relative_path = recipe.fetch(:target_path).to_s
      basename = File.basename(relative_path)
      extension = File.extname(relative_path).downcase
      return :gitignore if basename == ".gitignore"
      return :gemfile if basename == "Gemfile" || basename.end_with?(".gemfile")
      return :appraisals if basename.start_with?("Appraisals") || basename == "Appraisal.root.gemfile"
      return :gemspec if basename.end_with?(".gemspec")
      return :rakefile if basename == "Rakefile" || extension == ".rake"
      return :ruby if RUBY_TEMPLATE_BASENAMES.include?(basename) ||
        RUBY_TEMPLATE_SUFFIXES.any? { |suffix| basename.end_with?(suffix) } ||
        RUBY_TEMPLATE_EXTENSIONS.include?(extension)
      return :yaml if extension.match?(/\A\.ya?ml\z/) || File.basename(relative_path).casecmp("citation.cff").zero?
      return :toml if extension == ".toml"
      return :jsonc if relative_path == ".devcontainer/devcontainer.json"
      return :jsonc if extension == ".jsonc"
      return :json5 if extension == ".json5"
      return :json if extension == ".json"
      return :markdown if extension.match?(/\A\.md(?:own)?\z/)
      return :dotenv if basename.start_with?(".env") || basename.end_with?(".env") || extension == ".env"
      return :rbs if extension == ".rbs"

      :text
    end

    def merge_gitignore_template_source(template_content, destination_content)
      # Git ignore files have no parser-backed AST. Treat each non-comment line
      # as a rule node, retain destination order and comments, and append only
      # template rules that the destination does not already declare.
      destination_rules = destination_content.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }.to_set
      additions = []
      pending_comments = []

      template_content.lines.each do |line|
        stripped = line.strip
        if stripped.empty?
          pending_comments << line unless pending_comments.empty?
          next
        end
        if stripped.start_with?("#")
          pending_comments << line
          next
        end
        next if destination_rules.include?(stripped)

        additions.concat(pending_comments)
        additions << line
        destination_rules << stripped
        pending_comments = []
      end

      return destination_content if additions.empty?

      output = destination_content.dup
      output << "\n" unless output.empty? || output.end_with?("\n\n")
      output << additions.join
      ensure_trailing_newline(output)
    end

    def apply_kettle_config_bootstrap(project_root, recipe, env: ENV, template_contents: nil)
      content = recipe_template_content(project_root, recipe, template_contents: template_contents)
      tokens = stringify_template_tokens(recipe.fetch(:template_tokens, {}))
      content = resolve_template_tokens(content, tokens, scan_unresolved: false)
      bootstrap_licenses = Array(recipe[:bootstrap_licenses]).map(&:to_s).reject(&:empty?)
      content = replace_kettle_config_bootstrap_licenses(content, bootstrap_licenses) unless bootstrap_licenses.empty?
      content = replace_kettle_config_bootstrap_project_emoji(content, recipe[:bootstrap_project_emoji]) unless recipe[:bootstrap_project_emoji].to_s.empty?
      content = replace_kettle_config_bootstrap_rubyforum(content, recipe[:bootstrap_rubyforum]) if recipe[:bootstrap_rubyforum].is_a?(Hash)
      content = apply_kettle_config_bootstrap_profile(content, recipe[:bootstrap_template_profile], recipe[:bootstrap_gemspec_path])
      content = add_shim_bootstrap_config(content, recipe[:bootstrap_shim]) if recipe[:bootstrap_shim].is_a?(Hash)
      assert_no_unresolved_template_tokens_in_yaml_values(sync_kettle_config_env_overrides(content, env), KETTLE_CONFIG_PATH)
    end

    def replace_kettle_config_bootstrap_project_emoji(content, emoji)
      updated = replace_yaml_scalar_line(content, "project_emoji", emoji.to_s)
      return updated unless updated == content

      raise Error, "Could not replace project_emoji in .kettle-jem.yml bootstrap template"
    end

    def replace_kettle_config_bootstrap_licenses(content, licenses)
      license_block = ["licenses:", *licenses.map { |license_id| "  - #{license_id}" }].join("\n")
      updated = replace_yaml_node_lines(content, "licenses", "#{license_block}\n")
      return updated unless updated == content

      raise Error, "Could not replace licenses block in .kettle-jem.yml bootstrap template"
    end

    def replace_kettle_config_bootstrap_rubyforum(content, rubyforum)
      updated = content
      family_tag = rubyforum[:family_tag].to_s
      project_tag = rubyforum[:project_tag].to_s
      family_tag = "" if token_placeholder?(family_tag)
      project_tag = "" if token_placeholder?(project_tag)
      updated = replace_yaml_scalar_path(updated, %w[rubyforum family_tag], yaml_config_scalar_literal(family_tag, path: %w[rubyforum family_tag])) unless family_tag.empty?
      updated = replace_yaml_scalar_path(updated, %w[rubyforum project_tag], yaml_config_scalar_literal(project_tag, path: %w[rubyforum project_tag])) unless project_tag.empty?
      updated
    end

    def replace_yaml_scalar_line(content, key, value)
      lines = content.to_s.lines
      yaml_scalar_pairs(content).each do |key_node, value_node|
        next unless key_node.value.to_s == key.to_s

        line_index = key_node.start_line
        line = lines[line_index].to_s
        key_index = line.index("#{key}:")
        next unless key_index

        lines[line_index] = "#{line[0...key_index]}#{key}: #{value}\n"
        return lines.join
      end
      content
    end

    def yaml_scalar_line_value(content, key)
      lines = content.to_s.lines
      yaml_scalar_pairs(content).each do |key_node, value_node|
        next unless key_node.value.to_s == key.to_s

        line = lines[value_node.start_line].to_s
        value_text = line.split(":", 2).last.to_s.strip
        return value_text unless value_text.empty?
      end
      nil
    end

    def sync_kettle_config_env_overrides(content, env)
      synced = KETTLE_CONFIG_ENV_SYNC_PATHS.reduce(content.to_s) do |updated, (path, env_key)|
        value = env_sync_value(env, env_key)
        next updated unless present_template_token_value?(value)

        replace_yaml_scalar_path(updated, path, yaml_config_scalar_literal(value, path: path))
      end
      synced = normalize_kettle_config_optional_scalars(synced)
      synced = sync_kettle_config_project_hostnames(synced)
      synced = sync_kettle_config_internal_values(synced)
      synced = migrate_readme_logo_config(synced)
      synced = prune_legacy_kettle_config_keys(synced)
      sync_kettle_config_documentation_comments(synced)
    end

    def normalize_kettle_config_optional_scalars(content)
      config = YAML.safe_load(content.to_s, permitted_classes: [], aliases: true) || {}
      return content unless config.key?("min_divergence_threshold")

      replace_yaml_scalar_path(
        content,
        %w[min_divergence_threshold],
        yaml_config_scalar_literal(config["min_divergence_threshold"], path: %w[min_divergence_threshold])
      )
    rescue Psych::Exception
      content
    end

    def sync_kettle_config_project_hostnames(content)
      config = YAML.safe_load(content.to_s, permitted_classes: [], aliases: true) || {}
      yard_host = config["yard_host"].to_s
      homepage_uri = config["homepage_uri"].to_s
      normalized_yard_host = token_placeholder?(yard_host) ? yard_host : normalize_project_hostname(yard_host)
      normalized_homepage_uri = token_placeholder?(homepage_uri) ? homepage_uri : normalize_project_homepage_uri(homepage_uri)
      synced = content.to_s
      if !yard_host.empty? && normalized_yard_host != yard_host
        synced = replace_yaml_scalar_path(synced, %w[yard_host], yaml_config_scalar_literal(normalized_yard_host, path: %w[yard_host]))
      end
      if !homepage_uri.empty? && normalized_homepage_uri != homepage_uri
        synced = replace_yaml_scalar_path(synced, %w[homepage_uri], yaml_config_scalar_literal(normalized_homepage_uri, path: %w[homepage_uri]))
      end
      synced
    end

    def env_sync_value(env, env_key)
      Array(env_key).each do |candidate|
        value = env[candidate].to_s.strip
        return value if present_template_token_value?(value)
      end
      ""
    end

    def sync_kettle_config_internal_values(content)
      KETTLE_CONFIG_INTERNAL_SYNC_PATHS.reduce(content.to_s) do |updated, (path, value_provider)|
        replace_yaml_scalar_path(updated, path, yaml_config_scalar_literal(kettle_config_internal_value(value_provider), path: path))
      end
    end

    def kettle_config_internal_value(value_provider)
      case value_provider
      when :version
        VERSION
      else
        raise ArgumentError, "Unsupported kettle-jem internal config value provider: #{value_provider.inspect}"
      end
    end

    def prune_legacy_kettle_config_keys(content)
      pruned = KETTLE_CONFIG_LEGACY_KEY_PATHS.reduce(content.to_s) do |updated, legacy_key|
        remove_yaml_scalar_path(updated, legacy_key.fetch(:path))
      end
      remove_obsolete_simplecov_keep_destination_config(pruned)
    end

    def remove_obsolete_simplecov_keep_destination_config(content)
      config = YAML.safe_load(content.to_s, permitted_classes: [], aliases: true) || {}
      simplecov_config = config.dig("files", ".simplecov")
      return content unless simplecov_config.is_a?(Hash)
      return content unless simplecov_config.keys == ["strategy"] && simplecov_config["strategy"].to_s == "keep_destination"

      remove_yaml_mapping_path(content, %w[files .simplecov])
    end

    def migrate_readme_logo_config(content)
      config = YAML.safe_load(content.to_s, permitted_classes: [], aliases: true) || {}
      readme_config = config["readme"]
      return content unless readme_config.is_a?(Hash)

      configured_specs = normalized_readme_logo_specs(readme_config["top_logos"] || readme_config["top_logo_options"])
      legacy_mode_migrated = configured_specs.empty?
      if legacy_mode_migrated
        legacy_options = legacy_readme_top_logo_mode_options(readme_config["top_logo_mode"])
        configured_specs = legacy_options.map { |option| {type: option, width: nil} }
      end
      configured = configured_specs.map { |spec| spec.fetch(:type) }
      return content if configured.empty?

      top_logo_specs = configured_specs.select { |spec| README_TOP_LOGO_DEFAULTS.include?(spec.fetch(:type)) }
      h2_synopsis_logo_specs = normalized_readme_logo_specs(readme_config["h2_synopsis_logos"])
      h2_synopsis_logo_specs = configured_specs.select { |spec| README_H2_SYNOPSIS_LOGO_DEFAULTS.include?(spec.fetch(:type)) } if h2_synopsis_logo_specs.empty?
      if legacy_mode_migrated && h2_synopsis_logo_specs.empty?
        h2_synopsis_logo_specs = README_H2_SYNOPSIS_LOGO_DEFAULTS.map { |option| {type: option, width: nil} }
      end
      top_logos = top_logo_specs.map { |spec| readme_logo_config_value(spec) }
      h2_synopsis_logos = h2_synopsis_logo_specs.map { |spec| readme_logo_config_value(spec) }
      return content if h2_synopsis_logos.empty? && top_logos == configured

      migrated = if readme_config.key?("top_logos")
        replace_yaml_scalar_path(content, %w[readme top_logos], top_logos.join(","))
      else
        insert_yaml_scalar_after_path(content, %w[readme], "top_logos", top_logos.join(","))
      end
      return replace_yaml_scalar_path(migrated, %w[readme h2_synopsis_logos], h2_synopsis_logos.join(",")) if readme_config.key?("h2_synopsis_logos")

      insert_yaml_scalar_after_path(migrated, %w[readme top_logos], "h2_synopsis_logos", h2_synopsis_logos.join(","))
    rescue Psych::Exception
      content
    end

    def legacy_readme_top_logo_mode_options(value)
      raw = value.to_s.strip
      return [] if raw.empty?

      normalized = raw.downcase.tr("-", "_").gsub(/\s*,\s*/, ",").tr(" ", "_")
      mapped = README_TOP_LOGO_LEGACY_MODE_MAP[normalized]
      return mapped if mapped

      normalized.split(",").filter_map do |option|
        option = option.strip
        README_TOP_LOGO_OPTIONS.include?(option) ? option : nil
      end
    end

    def readme_logo_config_value(spec)
      width = spec[:width].to_s
      width.empty? ? spec.fetch(:type).tr("_", "-") : "#{spec.fetch(:type).tr("_", "-")}|#{width}"
    end

    def sync_kettle_config_documentation_comments(content)
      synced = sync_readme_top_logos_documentation_comment(content)
      synced = remove_duplicate_framework_matrix_documentation(synced)
      synced = remove_duplicate_readme_preservation_documentation(synced)
      sync_author_names_documentation_comment(synced)
    end

    def sync_author_names_documentation_comment(content)
      legacy = "#   AUTHOR:NAMES        <- all authors from the gemspec, or copyright holders if no gemspec authors exist"
      current = [
        "#   AUTHOR:NAMES        <- existing gemspec authors plus Git-derived copyright holders\n",
        "#                           (after author_aliases consolidation)\n"
      ]
      lines = content.to_s.lines
      index = lines.index { |line| line.chomp == legacy }
      updated = if index
        lines[index, 1] = current
        lines.join
      else
        content
      end

      legacy_token_comment = "generated gemspec authors preserve the full existing authors array via AUTHOR:NAMES."
      current_token_comment = "AUTHOR:NAMES preserves existing gemspec authors and appends Git-derived copyright holders."
      updated.lines.map { |line| line.sub(legacy_token_comment, current_token_comment) }.join
    end

    # YAML parsers do not retain comments. These migrations therefore operate
    # on bounded comment-only spans left by older template versions; they never
    # remove a span containing a YAML key or value.
    def remove_duplicate_framework_matrix_documentation(content)
      remove_duplicate_comment_span_before_marker(
        content,
        start_marker: "# Framework matrix workflows.",
        end_marker: "# README top logos."
      )
    end

    def remove_duplicate_readme_preservation_documentation(content)
      lines = content.to_s.lines
      marker = "# Sections to preserve from the destination README during template merging."
      starts = lines.each_index.select { |index| lines[index].strip == marker }
      return content if starts.length < 2

      starts.drop(1).reverse_each do |start_index|
        end_index = start_index
        end_index += 1 while end_index < lines.length && comment_or_blank_line?(lines[end_index])
        lines.slice!(start_index...end_index) if comment_only_lines?(lines[start_index...end_index])
      end
      lines.join
    end

    def remove_duplicate_comment_span_before_marker(content, start_marker:, end_marker:)
      lines = content.to_s.lines
      starts = lines.each_index.select { |index| lines[index].chomp == start_marker }
      return content if starts.length < 2

      starts.drop(1).reverse_each do |start_index|
        end_index = ((start_index + 1)...lines.length).find { |index| lines[index].chomp == end_marker }
        next unless end_index && comment_only_lines?(lines[start_index...end_index])

        lines.slice!(start_index...end_index)
      end
      lines.join
    end

    def comment_or_blank_line?(line)
      stripped = line.to_s.strip
      stripped.empty? || stripped.start_with?("#")
    end

    def comment_only_lines?(lines)
      Array(lines).all? { |line| comment_or_blank_line?(line) }
    end

    def sync_readme_top_logos_documentation_comment(content)
      lines = content.to_s.lines
      start_index = lines.index do |line|
        stripped = line.strip
        stripped == "# README top logo mode." || stripped == "# README top logos."
      end
      return content unless start_index
      return content unless lines.any? { |line| line.strip.start_with?("top_logos:") }

      readme_index = ((start_index + 1)...lines.length).find { |index| lines[index].strip == "readme:" }
      return content unless readme_index

      replacement = [
        "# README top logos.\n",
        "# Comma-separated list of optional logo entries for the generated README header.\n",
        "# top_logos render above the title; h2_synopsis_logos render inline with the Synopsis H2.\n",
        "# Supported values: related-org, ruby, org, project, optionally followed by |width.\n",
        "# Examples: org|12%, ruby|96px\n",
        "# Default widths: top 1 logo => 14%, top 2 logos => 12%, Synopsis 1 logo => 10%, Synopsis 2 logos => 8%.\n",
        "# Default (when keys are absent): top_logos: org,project; h2_synopsis_logos: related-org,ruby\n",
        "# Legacy top_logo_mode values map as:\n",
        "#   org => related-org,ruby,org\n",
        "#   project => related-org,ruby,project\n",
        "#   org_and_project => related-org,ruby,org,project\n"
      ]
      lines[start_index...readme_index] = replacement
      lines.join
    end

    def insert_yaml_scalar_after_path(content, path, key, value)
      lines = content.to_s.lines
      scalar_entry = yaml_scalar_path_entries(content).find { |candidate| candidate.fetch(:path) == path }
      mapping_entry = yaml_mapping_path_entries(content).find { |candidate| candidate.fetch(:path) == path }
      entry = scalar_entry || mapping_entry
      return content unless entry

      line_index = entry.key?(:line) ? entry.fetch(:line) : entry.fetch(:start_line)
      indent = lines[line_index].to_s[/\A\s*/].to_s
      scalar_path = path[0...-1] + [key]
      if mapping_entry && !scalar_entry
        indent = "#{indent}  "
        scalar_path = path + [key]
      end
      lines.insert(line_index + 1, "#{indent}#{key}: #{yaml_config_scalar_literal(value, path: scalar_path)}\n")
      lines.join
    end

    def replace_yaml_scalar_path(content, path, value)
      lines = content.to_s.lines
      yaml_scalar_path_entries(content).each do |entry|
        next unless entry.fetch(:path) == path

        line_index = entry.fetch(:line)
        line = lines[line_index].to_s
        key = path.last.to_s
        key_index = line.index("#{key}:")
        next unless key_index

        lines[line_index] = "#{line[0...key_index]}#{key}: #{value}#{yaml_line_comment_suffix(line, key_index)}\n"
        return lines.join
      end
      content
    end

    def remove_yaml_scalar_path(content, path)
      lines = content.to_s.lines
      yaml_scalar_path_entries(content).each do |entry|
        next unless entry.fetch(:path) == path

        line_index = entry.fetch(:line)
        return ensure_trailing_newline(lines.each_with_index.reject { |_line, index| index == line_index }.map(&:first).join)
      end
      content
    end

    def ensure_yaml_top_level_sequence_items(content, key, items)
      document = Psych.parse_stream(content.to_s).children.first
      root = document&.root
      return content unless root.is_a?(Psych::Nodes::Mapping)

      key_node, value_node = root.children.each_slice(2).find do |candidate_key, _candidate_value|
        candidate_key.is_a?(Psych::Nodes::Scalar) && candidate_key.value.to_s == key.to_s
      end
      lines = content.to_s.lines
      unless key_node
        lines << "\n" unless lines.empty? || lines.last.strip.empty?
        lines << "#{key}:\n"
        items.each { |item| lines << "  - #{item}\n" }
        return lines.join
      end
      return content unless value_node.is_a?(Psych::Nodes::Sequence)

      existing = value_node.children.filter_map do |child|
        child.value.to_s if child.is_a?(Psych::Nodes::Scalar)
      end
      missing = items.map(&:to_s) - existing
      return content if missing.empty?

      reference_line = value_node.children.last&.start_line || key_node.start_line
      reference = lines[reference_line].to_s
      indent = reference.start_with?("-") ? "" : reference[/\A\s*/].to_s
      insertion_index = value_node.children.last ? value_node.children.last.end_line + 1 : key_node.end_line + 1
      lines.insert(insertion_index, *missing.map { |item| "#{indent}- #{item}\n" })
      lines.join
    rescue Psych::Exception
      content
    end

    def remove_yaml_mapping_path(content, path)
      lines = content.to_s.lines
      yaml_mapping_path_entries(content).each do |entry|
        next unless entry.fetch(:path) == path

        start_line = entry.fetch(:start_line)
        end_line = entry.fetch(:end_line)
        return ensure_trailing_newline([*lines[0...start_line], *lines[end_line..].to_a].join)
      end
      content
    end

    def yaml_line_comment_suffix(line, key_index)
      value_start = line.to_s.index(":", key_index).to_i + 1
      in_single_quote = false
      in_double_quote = false
      escaped = false
      value_start.upto(line.length - 1) do |index|
        char = line[index]
        if in_double_quote
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == "\""
            in_double_quote = false
          end
          next
        end
        if in_single_quote
          in_single_quote = false if char == "'"
          next
        end

        case char
        when "\""
          in_double_quote = true
        when "'"
          in_single_quote = true
        when "#"
          previous = index.zero? ? "" : line[index - 1]
          next unless previous == " " || previous == "\t"

          before_comment = line[(value_start...index)].to_s
          trailing_space = before_comment.reverse.each_char.take_while { |space| space == " " || space == "\t" }.join.reverse
          return "#{trailing_space}#{line[index..].to_s.chomp}"
        end
      end
      ""
    end

    def yaml_config_scalar_literal(value, path:)
      clean = value.to_s.strip
      return clean if path == ["project_emoji"]
      return clean if clean.match?(/\A\d+(?:\.\d+)?\z/)

      JSON.generate(clean)
    end

    def replace_yaml_node_lines(content, key, replacement)
      lines = content.to_s.lines
      yaml_mapping_nodes(content).each do |mapping|
        mapping.children.each_slice(2) do |key_node, value_node|
          next unless key_node.is_a?(Psych::Nodes::Scalar) && key_node.value.to_s == key.to_s

          start_line = key_node.start_line
          end_line = value_node.end_line
          return [*lines[0...start_line], replacement, *lines[end_line..].to_a].join
        end
      end
      content
    end

    def apply_kettle_config_bootstrap_profile(content, profile, gemspec_path)
      return content if profile.to_s.empty?
      return replace_yaml_scalar_path(content, %w[templates profile], FULL_TEMPLATE_PROFILE) if profile.to_s == FULL_TEMPLATE_PROFILE
      return apply_monorepo_root_template_profile(content) if profile.to_s == MONOREPO_ROOT_TEMPLATE_PROFILE
      return apply_monorepo_subgem_template_profile(content, gemspec_path, profile) if monorepo_subgem_template_profile_value?(profile)
      return apply_shim_template_profile(content, gemspec_path) if profile.to_s == SHIM_TEMPLATE_PROFILE

      raise Error, "Unknown kettle-jem template profile: #{profile}"
    end

    def apply_shim_template_profile(content, gemspec_path)
      entry_lines = shim_template_entries_for_config(gemspec_path, {}).flat_map do |entry|
        [
          "    - source: #{entry.fetch("source")}",
          "      target: #{entry.fetch("target")}"
        ]
      end
      profiled_content = replace_yaml_scalar_path(content, %w[templates profile], SHIM_TEMPLATE_PROFILE)
      entries_block = ["  entries:", *entry_lines].join("\n")
      updated = insert_after_line_sequence(
        profiled_content,
        ["templates:", "  root: packaged", "  apply: true", "  profile: #{SHIM_TEMPLATE_PROFILE}"],
        entries_block,
        nil
      )
      if updated == profiled_content
        updated = insert_after_line_sequence(
          profiled_content,
          ["templates:", "  root: packaged", "  apply: true"],
          entries_block,
          "Could not apply shim template profile to .kettle-jem.yml bootstrap template"
        )
      end
      raise Error, "Could not apply shim template profile to .kettle-jem.yml bootstrap template" if updated == profiled_content

      add_shim_file_overrides(updated, gemspec_path)
    end

    def add_shim_bootstrap_config(content, shim)
      replacement_gem = shim[:replacement_gem].to_s
      replacement_require = shim[:replacement_require].to_s
      legacy_requires = Array(shim[:legacy_requires]).map(&:to_s).reject(&:empty?)
      block = [
        "shim:",
        "  replacement_gem: #{replacement_gem}",
        "  replacement_require: #{replacement_require}"
      ]
      unless legacy_requires.empty?
        block << "  legacy_requires:"
        block.concat(legacy_requires.map { |path| "    - #{path}" })
      end
      block << "  version:"
      block << "    strategy: shim"
      insert_after_line_sequence(
        content,
        ["homepage_uri: \"{KJ|HOMEPAGE_URI}\""],
        ["", *block].join("\n"),
        "Could not add shim config to .kettle-jem.yml bootstrap template"
      )
    end

    def apply_monorepo_root_template_profile(content)
      entry_lines = MONOREPO_ROOT_TEMPLATE_ENTRIES.map { |entry| "    - #{entry}" }
      profiled_content = replace_yaml_scalar_path(content, %w[templates profile], MONOREPO_ROOT_TEMPLATE_PROFILE)
      entries_block = ["  entries:", *entry_lines].join("\n")
      updated = insert_after_line_sequence(
        profiled_content,
        ["templates:", "  root: packaged", "  apply: true", "  profile: #{MONOREPO_ROOT_TEMPLATE_PROFILE}"],
        entries_block,
        nil
      )
      if updated == profiled_content
        updated = insert_after_line_sequence(
          profiled_content,
          ["templates:", "  root: packaged", "  apply: true"],
          entries_block,
          "Could not apply monorepo-root template profile to .kettle-jem.yml bootstrap template"
        )
      end
      if updated == profiled_content
        raise Error,
          "Could not apply monorepo-root template profile to .kettle-jem.yml bootstrap template"
      end
      add_monorepo_root_file_overrides(updated)
    end

    def apply_monorepo_subgem_template_profile(content, gemspec_path, profile = MONOREPO_SUBGEM_TEMPLATE_PROFILE)
      entries = monorepo_subgem_template_entries(gemspec_path, profile)
      entry_lines = entries.flat_map do |entry|
        if entry.is_a?(Hash)
          [
            "    - source: #{entry.fetch("source")}",
            "      target: #{entry.fetch("target")}"
          ]
        else
          ["    - #{entry}"]
        end
      end
      normalized_profile = normalize_template_profile(profile)
      profiled_content = replace_yaml_scalar_path(content, %w[templates profile], normalized_profile)
      entries_block = ["  entries:", *entry_lines].join("\n")
      updated = insert_after_line_sequence(
        profiled_content,
        ["templates:", "  root: packaged", "  apply: true", "  profile: #{normalized_profile}"],
        entries_block,
        nil
      )
      if updated == profiled_content
        updated = insert_after_line_sequence(
          profiled_content,
          ["templates:", "  root: packaged", "  apply: true"],
          entries_block,
          "Could not apply monorepo-subgem template profile to .kettle-jem.yml bootstrap template"
        )
      end
      if updated == profiled_content
        raise Error,
          "Could not apply #{normalized_profile} template profile to .kettle-jem.yml bootstrap template"
      end

      add_monorepo_subgem_file_overrides(updated, gemspec_path, normalized_profile)
    end

    def add_monorepo_root_file_overrides(content)
      override_lines = MONOREPO_ROOT_TEMPLATE_ENTRIES.reject { |entry| entry.to_s.include?("/") }.flat_map do |entry|
        kettle_config_file_override_lines(entry, monorepo_root_file_strategy(entry))
      end
      insert_after_line_sequence(
        content,
        ["files:"],
        override_lines.join("\n"),
        "Could not apply monorepo-root file overrides to .kettle-jem.yml bootstrap template"
      )
    end

    def monorepo_root_file_strategy(entry)
      if entry.to_s == "CHANGELOG.md"
        "keep_destination"
      else
        "accept_template"
      end
    end

    def kettle_config_file_override_lines(path, strategy)
      parts = path.to_s.split("/")
      parts.each_with_index.flat_map do |part, index|
        indent = "  " * (index + 1)
        if index == parts.length - 1
          ["#{indent}#{part}:", "#{"  " * (index + 2)}strategy: #{strategy}"]
        else
          ["#{indent}#{part}:"]
        end
      end
    end

    def monorepo_subgem_template_entries(gemspec_path, profile = MONOREPO_SUBGEM_TEMPLATE_PROFILE)
      entries = monorepo_subgem_template_entries_for_profile(gemspec_path, profile)
      gemspec = gemspec_path.to_s.strip
      return entries if gemspec.empty?

      entries.insert(1, {"source" => "gem.gemspec", "target" => gemspec})
      entries.concat(version_gem_template_entries(gemspec))
      entries
    end

    def monorepo_subgem_template_entries_for_profile(gemspec_path, profile)
      case normalize_template_profile(profile)
      when MONOREPO_SUBGEM_RELEASE_TEMPLATE_PROFILE
        MONOREPO_SUBGEM_RELEASE_TEMPLATE_ENTRIES.dup
      when MONOREPO_SUBGEM_FULL_TEMPLATE_PROFILE
        project_root = File.dirname(File.expand_path(gemspec_path.to_s))
        template_inventory_entries(project_root, PACKAGED_TEMPLATE_ROOT).dup
      else
        (MONOREPO_SUBGEM_TEMPLATE_ENTRIES + PACKAGED_MODULAR_GEMFILE_TEMPLATE_ENTRIES).uniq
      end
    end

    def version_gem_template_entries(gemspec_path)
      VERSION_GEM_TEMPLATE_SOURCES.map do |source|
        {"source" => source, "target" => version_gem_template_target_path(gemspec_path, source)}
      end
    end

    def version_gem_template_target_path(gemspec_path, source)
      gemspec_reference = gemspec_path.to_s
      package_name = File.basename(gemspec_reference, ".gemspec")
      entrypoint_require = if File.dirname(gemspec_reference) == "."
        package_name.tr("-", "/")
      else
        project_root = File.dirname(File.expand_path(gemspec_reference))
        project_entrypoint_require(project_root, package_name)
      end
      case source
      when "lib/gem/version.rb"
        File.join("lib", entrypoint_require, "version.rb")
      when "lib/gem/version_gem.rb"
        File.join("lib", entrypoint_require, "version_gem.rb")
      when "sig/gem.rbs"
        File.join("sig", "#{entrypoint_require}.rbs")
      else
        source
      end
    end

    def version_gem_template_target_path_for_project(project_root, gemspec_path, source)
      config = kettle_jem_config(project_root)
      package_name = File.basename(gemspec_path.to_s, ".gemspec")
      entrypoint_require = project_entrypoint_require(project_root, package_name, config: config)
      case source
      when "lib/gem/version.rb"
        File.join("lib", entrypoint_require, "version.rb")
      when "lib/gem/version_gem.rb"
        File.join("lib", entrypoint_require, "version_gem.rb")
      when "sig/gem.rbs"
        File.join("sig", "#{entrypoint_require}.rbs")
      else
        source
      end
    end

    def project_entrypoint_require(project_root, package_name, config: nil)
      configured = (config || kettle_jem_config(project_root)).dig("rubygems", "entrypoint_require").to_s.strip
      return configured unless configured.empty?

      discovered = GemSpecReader.load(project_root).fetch(:entrypoint_require, "").to_s.strip
      return discovered unless discovered.empty?

      package_name.to_s.tr("-", "/")
    end

    def add_monorepo_subgem_file_overrides(content, gemspec_path, profile = MONOREPO_SUBGEM_TEMPLATE_PROFILE)
      override_lines = [
        "  README.md:",
        "    strategy: merge",
        "  Rakefile:",
        "    strategy: accept_template"
      ]
      gemspec = gemspec_path.to_s.strip
      unless gemspec.empty?
        override_lines.concat([
          "  #{gemspec}:",
          "    strategy: merge"
        ])
      end
      insert_after_line_sequence(
        content,
        ["files:"],
        override_lines.join("\n"),
        "Could not apply monorepo-subgem file overrides to .kettle-jem.yml bootstrap template"
      )
    end

    def shim_template_entries_for_config(gemspec_path, config)
      package_name = config.dig("rubygems", "name").to_s.strip
      package_name = File.basename(gemspec_path.to_s, ".gemspec") if package_name.empty?
      entrypoint_require = config.dig("rubygems", "entrypoint_require").to_s.strip
      entrypoint_require = package_name.tr("-", "/") if entrypoint_require.empty?
      legacy_requires = Array(config.dig("shim", "legacy_requires")).map(&:to_s)
      legacy_requires << entrypoint_require
      shim = {legacy_requires: legacy_requires.uniq}
      shim_template_entries(
        {
          package: {name: package_name},
          rubygems: {entrypoint_require: entrypoint_require},
          shim: shim
        },
        config
      )
    end

    def add_shim_file_overrides(content, gemspec_path)
      override_lines = shim_template_entries_for_config(gemspec_path, {}).flat_map do |entry|
        target = entry.fetch("target")
        next [] if target == KETTLE_CONFIG_PATH

        kettle_config_file_override_lines(target, "accept_template")
      end
      insert_after_line_sequence(
        content,
        ["files:"],
        override_lines.join("\n"),
        "Could not apply shim file overrides to .kettle-jem.yml bootstrap template"
      )
    end

    def insert_after_line_sequence(content, sequence, insertion, error_message)
      lines = content.to_s.lines(chomp: true)
      index = (0..(lines.length - sequence.length)).find do |candidate|
        lines[candidate, sequence.length] == sequence
      end
      return content if !index && error_message.nil?
      raise Error, error_message unless index

      insertion_lines = insertion.to_s.lines(chomp: true)
      updated = lines.dup
      updated.insert(index + sequence.length, *insertion_lines)
      "#{updated.join("\n")}\n"
    end

    def monorepo_subgem_template_profile?(facts)
      monorepo_subgem_template_profile_value?(facts[:template_profile])
    end

    def monorepo_root_template_profile?(facts)
      facts[:template_profile].to_s == MONOREPO_ROOT_TEMPLATE_PROFILE
    end

    def monorepo_template_profile?(facts)
      monorepo_root_template_profile?(facts) || monorepo_subgem_template_profile?(facts)
    end

    def shim_template_profile?(facts)
      facts[:template_profile].to_s == SHIM_TEMPLATE_PROFILE
    end

    def monorepo_subgem_template_profile_value?(profile)
      [
        MONOREPO_SUBGEM_PACKAGE_TEMPLATE_PROFILE,
        MONOREPO_SUBGEM_RELEASE_TEMPLATE_PROFILE,
        MONOREPO_SUBGEM_FULL_TEMPLATE_PROFILE
      ].include?(normalize_template_profile(profile))
    end

    def readme_project_emoji(project_root)
      readme_path = File.join(project_root, "README.md")
      return unless File.exist?(readme_path)

      h1 = markdown_heading_owners(File.read(readme_path), source_label: "README.md").find { |owner| owner.level == 1 }
      candidate = first_grapheme(h1&.heading_text)
      decorative_grapheme?(candidate) ? candidate : nil
    end

    def gemspec_project_emoji(gemspec_metadata)
      [
        metadata_value(gemspec_metadata, :summary),
        metadata_value(gemspec_metadata, :description)
      ].each do |value|
        candidate = first_grapheme(value)
        return candidate if decorative_grapheme?(candidate)
      end
      nil
    end

    def first_grapheme(text)
      text.to_s.strip[/\A\X/u].to_s
    end

    def decorative_grapheme?(grapheme)
      value = grapheme.to_s
      return false if value.empty?
      return false if value.ascii_only?

      !value.match?(/\A[[:alnum:][:space:]]\z/u)
    end

    def strip_leading_decorative_graphemes(text)
      remaining = text.to_s.sub(/\A\s+/, "")
      loop do
        first = first_grapheme(remaining)
        break unless decorative_grapheme?(first)

        remaining = remaining[first.length..].to_s.sub(/\A\s+/, "")
      end
      remaining
    end

    def ruby_double_quoted_string_body(value)
      value.to_s.gsub("\\", "\\\\\\").gsub('"', '\"')
    end

    def recipe_report_metadata(recipe)
      metadata = {packaging_recipe: recipe.fetch(:name)}
      metadata[:delete_file] = true if delete_file_recipe?(recipe)
      metadata[:template_source_preference] = deep_dup(recipe[:template_preference]) if recipe[:template_preference]
      metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      metadata[:readme_style] = deep_dup(recipe[:readme_style]) if recipe[:readme_style]
      metadata[:bootstrap_file] = true if recipe.fetch(:primitive) == "supplied_kettle_config_bootstrap"
      metadata
    end

    def decision_policy_for(env, run_options)
      DecisionPolicy.from_env(env || {}, **(run_options || {}))
    end

    def template_selection_for(env, run_options)
      env_hash = env || {}
      option_hash = run_options || {}
      {
        allowed: option_hash.fetch(:allowed, env_hash["allowed"]),
        hook_templates: option_hash.fetch(:hook_templates, env_hash["hook_templates"]),
        git_drivers: option_hash.fetch(:git_drivers, env_hash["git_drivers"] || env_hash["KETTLE_JEM_GIT_DRIVERS"]),
        only: normalize_list_option(option_hash.fetch(:only, env_hash["only"])),
        include: normalize_list_option(option_hash.fetch(:include, env_hash["include"])),
        template_profile: normalize_template_profile(option_hash.fetch(:template_profile, env_hash["KETTLE_JEM_TEMPLATE_PROFILE"])),
        shimmed_gem: option_hash.fetch(:shimmed_gem, env_hash["KETTLE_JEM_SHIMMED_GEM"]),
        shimmed_require: option_hash.fetch(:shimmed_require, env_hash["KETTLE_JEM_SHIMMED_REQUIRE"]),
        skip_commit: DecisionPolicy.value_to_boolean(option_hash.fetch(:skip_commit, env_hash["KETTLE_JEM_SKIP_COMMIT"])),
        skip_drift_check: DecisionPolicy.value_to_boolean(option_hash.fetch(:skip_drift_check, env_hash["KETTLE_JEM_SKIP_DRIFT_CHECK"])),
        skip_rubocop_gradual: DecisionPolicy.value_to_boolean(option_hash.fetch(:skip_rubocop_gradual, env_hash["KETTLE_JEM_SKIP_RUBOCOP_GRADUAL"])),
        skip_binstubs: DecisionPolicy.value_to_boolean(option_hash.fetch(:skip_binstubs, env_hash["KETTLE_JEM_SKIP_BINSTUBS"])),
        dry_run: DecisionPolicy.value_to_boolean(option_hash.fetch(:dry_run, env_hash["KETTLE_JEM_DRY_RUN"])),
        accept_config: DecisionPolicy.value_to_boolean(option_hash.fetch(:accept_config, env_hash["KETTLE_JEM_ACCEPT_CONFIG"])),
        bootstrap_mode: DecisionPolicy.value_to_boolean(option_hash.fetch(:bootstrap_mode, env_hash["KETTLE_JEM_BOOTSTRAP_MODE"])),
        quiet: DecisionPolicy.value_to_boolean(option_hash.fetch(:quiet, env_hash["KETTLE_JEM_QUIET"])),
        verbose: DecisionPolicy.value_to_boolean(option_hash.fetch(:verbose, env_hash["KETTLE_JEM_VERBOSE"]))
      }.compact
    end

    def normalize_list_option(value)
      values = Array(value).flat_map { |entry| entry.to_s.split(",") }.map(&:strip).reject(&:empty?)
      values.empty? ? nil : values
    end

    def normalize_template_profile(value)
      profile = value.to_s.strip.downcase.tr("_", "-")
      return "" if profile.empty?
      return FULL_TEMPLATE_PROFILE if %w[full large default standalone].include?(profile)
      return MONOREPO_SUBGEM_PACKAGE_TEMPLATE_PROFILE if %w[monorepo-subgem monorepo-subproject monorepo-package monorepo-subgem-package small thin package].include?(profile)
      return MONOREPO_SUBGEM_RELEASE_TEMPLATE_PROFILE if %w[monorepo-subgem-release monorepo-release release].include?(profile)
      return MONOREPO_SUBGEM_FULL_TEMPLATE_PROFILE if %w[monorepo-subgem-full monorepo-full subgem-full].include?(profile)
      return MONOREPO_ROOT_TEMPLATE_PROFILE if profile == MONOREPO_ROOT_TEMPLATE_PROFILE
      return SHIM_TEMPLATE_PROFILE if %w[shim shim-gem compatibility-shim compat-shim].include?(profile)

      profile
    end

    def repository_topology_for(config, env, template_selection)
      repository_config = config["repository"].is_a?(Hash) ? config["repository"] : {}
      topology = preferred_template_token_value(nil, repository_config["topology"], env, "KJ_REPOSITORY_TOPOLOGY")
      normalized = normalize_repository_topology(topology)
      return normalized unless normalized.empty?

      monorepo_subgem_template_profile_value?(template_selection[:template_profile]) ? REPOSITORY_TOPOLOGY_MONOREPO_SUBPROJECT : REPOSITORY_TOPOLOGY_STANDALONE
    end

    def normalize_repository_topology(value)
      topology = value.to_s.strip.downcase.tr("_", "-")
      return "" if topology.empty?
      return REPOSITORY_TOPOLOGY_MONOREPO_SUBPROJECT if %w[monorepo-subproject monorepo-subgem monorepo-package subproject subgem].include?(topology)
      return REPOSITORY_TOPOLOGY_STANDALONE if %w[standalone single-repo repo].include?(topology)

      topology
    end

    def filter_recipe_pack(pack, template_selection)
      patterns = recipe_filter_patterns(template_selection)
      return pack if patterns.empty?

      pack.merge(
        recipes: pack.fetch(:recipes).select { |recipe| selected_template_path?(recipe.fetch(:target_path), patterns) }
      )
    end

    def recipe_filter_patterns(template_selection)
      only = Array(template_selection[:only]).compact
      include = Array(template_selection[:include]).compact
      only.empty? ? [] : (only + include)
    end

    def selected_template_path?(relative_path, patterns)
      path = relative_path.to_s.delete_prefix("./")
      patterns.any? do |pattern|
        normalized = pattern.to_s.delete_prefix("./")
        path == normalized ||
          File.fnmatch?(normalized, path, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB) ||
          (normalized.end_with?("/**") && path.start_with?(normalized.delete_suffix("/**") + "/"))
      end
    end

    def recipe_decision_evaluation(decision_policy:, recipe:, changed:, destination_existed:)
      decision_policy.resolve(
        id: "recipe:#{recipe.fetch(:name)}",
        category: recipe_decision_category(recipe),
        file: recipe.fetch(:target_path),
        default_action: recipe_default_action(recipe, changed: changed, destination_existed: destination_existed),
        severity: :advisory,
        diagnostics: recipe_decision_diagnostics(recipe)
      ).to_h
    end

    def recipe_decision_category(recipe)
      return "delete_file" if delete_file_recipe?(recipe)
      return "select_template_source" if recipe.fetch(:primitive) == "supplied_template_source_preference"
      return "bootstrap_config" if recipe.fetch(:primitive) == "supplied_kettle_config_bootstrap"
      return "apply_template_source" if recipe.fetch(:primitive) == "supplied_template_source_application"

      "merge_valid_document"
    end

    def recipe_default_action(recipe, changed:, destination_existed:)
      return "delete" if delete_file_recipe?(recipe)
      return "keep" unless changed
      return "create" unless destination_existed
      return "replace" if recipe.fetch(:primitive) == "supplied_template_source_application"

      "merge"
    end

    def recipe_decision_diagnostics(recipe)
      diagnostics = []
      if recipe.fetch(:primitive) == "supplied_template_source_application"
        diagnostics << "Non-interactive runs apply the configured template source default and report the decision."
      end
      if delete_file_recipe?(recipe)
        diagnostics << "Deletion is allowed only for explicit Kettle/Jem cleanup primitives."
      end
      diagnostics
    end

    def setup_guidance_diagnostic(config_existed:)
      {
        severity: "advisory",
        message: if config_existed
                   "Kettle/Jem setup bootstrap mode found existing #{KETTLE_CONFIG_PATH}; run kettle-jem apply to template the project."
                 else
                   "Created #{KETTLE_CONFIG_PATH}. Review it, then run kettle-jem --accept-config to continue setup."
                 end
      }
    end

    def setup_execution_context(env, run_options)
      return {bundled: false, source: "bootstrap_mode", bundle_gemfile: nil} if DecisionPolicy.value_to_boolean((run_options || {})[:bootstrap_mode])

      bundle_gemfile = (env || {})["BUNDLE_GEMFILE"].to_s.strip
      {
        bundled: !bundle_gemfile.empty?,
        source: bundle_gemfile.empty? ? "process" : "BUNDLE_GEMFILE",
        bundle_gemfile: bundle_gemfile.empty? ? nil : bundle_gemfile
      }
    end

    def recipe_entry(name, target_path, provider_family, primitive, facts:, provider_backend: nil, selectors: [])
      {
        name: name,
        target_path: target_path,
        provider_family: provider_family,
        provider_backend: provider_backend,
        primitive: primitive,
        facts: facts,
        selectors: selectors
      }
    end

    def recipe_runtime_context(recipe, facts, deletion)
      context = deep_dup(facts)
      if recipe.fetch(:primitive) == "supplied_source_selector_deletion" && deletion
        context[:delete_selectors] = deletion.fetch(:delete_selectors)
      end
      context[:template_source_preference] = deep_dup(recipe[:template_preference]) if recipe[:template_preference]
      context[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      context[:readme_style] = deep_dup(recipe[:readme_style]) if recipe[:readme_style]
      context
    end

    def step_report_metadata(recipe, deletion)
      metadata = {
        target_path: recipe.fetch(:target_path),
        provider_family: recipe.fetch(:provider_family)
      }
      if recipe.fetch(:primitive) == "supplied_obsolete_file_deletion"
        metadata.merge!(
          policy_kind: "delete_obsolete_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path)
        )
      end
      if recipe.fetch(:primitive) == "supplied_disabled_opencollective_file_deletion"
        metadata.merge!(
          policy_kind: "delete_disabled_opencollective_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path)
        )
      end
      if recipe.fetch(:primitive) == "supplied_inactive_packaged_workflow_deletion"
        metadata.merge!(
          policy_kind: "delete_inactive_packaged_workflow",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path)
        )
      end
      if recipe.fetch(:primitive) == "supplied_inactive_packaged_template_deletion"
        metadata.merge!(
          policy_kind: "delete_inactive_packaged_template",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path)
        )
      end
      if recipe.fetch(:primitive) == "supplied_legacy_destination_file_deletion"
        metadata.merge!(
          policy_kind: "delete_legacy_destination_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path)
        )
      end
      if recipe.fetch(:primitive) == "supplied_obsolete_license_file_deletion"
        metadata.merge!(
          policy_kind: "delete_obsolete_license_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path)
        )
      end
      if recipe.fetch(:primitive) == "supplied_shim_profile_file_deletion"
        metadata.merge!(
          policy_kind: "delete_shim_profile_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path)
        )
      end
      if recipe.fetch(:primitive) == "supplied_template_source_preference"
        metadata.merge!(
          policy_kind: "select_template_source",
          operation: "select",
          template_source_preference: deep_dup(recipe.fetch(:template_preference))
        )
        metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
        metadata[:readme_style] = deep_dup(recipe[:readme_style]) if recipe[:readme_style]
      end
      if recipe.fetch(:primitive) == "supplied_template_source_application"
        metadata.merge!(
          policy_kind: "apply_template_source",
          operation: "replace",
          template_source_preference: deep_dup(recipe.fetch(:template_preference))
        )
        metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      end
      if recipe.fetch(:primitive) == "supplied_kettle_config_bootstrap"
        metadata.merge!(
          policy_kind: "bootstrap_kettle_config",
          operation: "create",
          template_source_preference: deep_dup(recipe.fetch(:template_preference))
        )
        metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      end
      return metadata unless deletion

      metadata.merge(
        policy_kind: "delete_supplied_structural_owners",
        operation: "delete",
        consumed_context: "delete_selectors",
        deleted_ranges: deletion.fetch(:delete_selectors).length,
        deleted_selector_ids: deletion.fetch(:delete_selectors).map { |selector| selector.fetch(:selector_id) }
      )
    end

    def ruby_engines_config(config)
      engines = config["engines"]
      return unless engines.is_a?(Array)

      engines.map { |engine| engine.to_s.strip.downcase }.reject(&:empty?).uniq
    end

    def funding_urls(project_root, package_name, funding_uri: nil, opencollective_disabled: false, open_collective_org: nil, enabled_platforms: nil)
      urls = [funding_uri]
      path = File.join(project_root, ".github", "FUNDING.yml")
      if File.exist?(path)
        urls.concat(
          github_funding_urls(
            path,
            opencollective_disabled: opencollective_disabled,
            enabled_platforms: enabled_platforms
          )
        )
      end
      if !opencollective_disabled && funding_platform_enabled?(enabled_platforms, "open_collective")
        urls << github_funding_platform_urls("open_collective", [open_collective_org]).first
      end
      if funding_platform_enabled?(enabled_platforms, "tidelift")
        urls << github_funding_platform_urls("tidelift", ["rubygems/#{package_name}"]).first
      end

      urls.compact.uniq.sort
    end

    def github_funding_urls(path, opencollective_disabled: false, enabled_platforms: nil)
      funding = YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      return [] unless funding.is_a?(Hash)

      funding.flat_map do |platform, value|
        normalized_platform = platform.to_s
        next [] if opencollective_disabled && normalized_platform == "open_collective"
        next [] unless funding_platform_enabled?(enabled_platforms, normalized_platform)

        github_funding_platform_urls(normalized_platform, Array(value).compact)
      end
    end

    def github_funding_platform_urls(platform, values)
      values.filter_map do |value|
        handle = value.to_s.strip.delete_prefix("@")
        next if handle.empty?

        case platform
        when "buy_me_a_coffee"
          "https://www.buymeacoffee.com/#{handle}"
        when "custom"
          handle if http_url?(handle)
        when "github"
          "https://github.com/sponsors/#{handle}"
        when "ko_fi"
          "https://ko-fi.com/#{handle}"
        when "liberapay"
          "https://liberapay.com/#{handle}/donate"
        when "open_collective"
          "https://opencollective.com/#{handle}"
        when "thanks_dev"
          "https://thanks.dev/#{handle}"
        when "tidelift"
          "https://tidelift.com/funding/github/#{handle}"
        end
      end
    end

    def github_actions_ruby_versions(min_ruby)
      floor = min_ruby.to_s[/\d+\.\d+/] || "3.1"
      candidates = %w[3.1 3.2 3.3 3.4]
      selected = candidates.select { |version| Gem::Version.new(version) >= Gem::Version.new(floor) }
      selected.empty? ? [floor] : selected
    end

    def github_actions_custom_workflows(project_root, config = {}, opencollective_disabled: false)
      workflow_root = File.join(project_root, ".github", "workflows")
      return [] unless Dir.exist?(workflow_root)

      Dir.glob(File.join(workflow_root, "*.{yml,yaml}")).filter_map do |path|
        relative_path = path.delete_prefix("#{project_root}/")
        next if opencollective_disabled && opencollective_disabled_file?(relative_path)
        next if inactive_packaged_workflow?(relative_path, config)
        next if generated_or_obsolete_github_workflow?(relative_path) &&
          !skip_packaged_workflow_template?(relative_path, config)

        relative_path
      end.sort
    end

    def inactive_packaged_workflow_cleanup_files(project_root, config = {}, include_patterns: nil)
      workflow_root = File.join(project_root, ".github", "workflows")
      return [] unless Dir.exist?(workflow_root)

      Dir.glob(File.join(workflow_root, "*.{yml,yaml}")).filter_map do |path|
        relative_path = path.delete_prefix("#{project_root}/")
        next if OPT_IN_GITHUB_WORKFLOWS.include?(relative_path)

        relative_path if inactive_packaged_workflow?(relative_path, config, include_patterns: include_patterns)
      end.sort
    end

    def inactive_packaged_workflow?(relative_path, config = {}, include_patterns: nil)
      return true if stale_versioned_engine_workflow?(relative_path)

      preferred_template_source(PACKAGED_TEMPLATE_ROOT, relative_path) &&
        skip_packaged_workflow_template?(relative_path, config, include_patterns: include_patterns)
    end

    def github_actions_obsolete_workflows(project_root)
      workflow_root = File.join(project_root, ".github", "workflows")
      OBSOLETE_GITHUB_WORKFLOWS.filter_map do |workflow|
        relative_path = ".github/workflows/#{workflow}"
        path = File.join(workflow_root, workflow)
        relative_path if File.exist?(path)
      end.sort
    end

    def opt_in_workflow_cleanup_files(project_root, template_selection)
      include_patterns = Array(template_selection[:include])
      OPT_IN_GITHUB_WORKFLOWS.select do |relative_path|
        File.exist?(File.join(project_root, relative_path)) &&
          !selected_template_path?(relative_path, include_patterns)
      end
    end

    def generated_or_obsolete_github_workflow?(relative_path)
      return true if preferred_template_source(PACKAGED_TEMPLATE_ROOT, relative_path)
      return true if stale_versioned_engine_workflow?(relative_path)
      return true if relative_path == ".github/workflows/opencollective.yml"

      OBSOLETE_GITHUB_WORKFLOWS.include?(File.basename(relative_path))
    end

    def stale_versioned_engine_workflow?(relative_path)
      return false if preferred_template_source(PACKAGED_TEMPLATE_ROOT, relative_path)

      basename = File.basename(relative_path.to_s, File.extname(relative_path.to_s))
      basename.match?(/\Aruby-\d+\.\d+\z/) ||
        basename.match?(/\Aruby-\d+-\d+\z/) ||
        basename.match?(/\Ajruby-\d+\.\d+\z/) ||
        basename.match?(/\Atruffleruby-\d+\.\d+\z/)
    end

    def opencollective_disabled_files(project_root)
      OPENCOLLECTIVE_DISABLED_FILES.select do |relative_path|
        File.exist?(File.join(project_root, relative_path))
      end
    end

    def opencollective_disabled_file?(relative_path)
      OPENCOLLECTIVE_DISABLED_FILES.include?(relative_path.to_s)
    end

    def preflight_project!(project_root)
      paths = Dir.glob(File.join(project_root, "*.gemspec")).sort
      gemfile_path = File.join(project_root, "Gemfile")
      paths << gemfile_path if File.exist?(gemfile_path)
      paths.each { |path| preflight_ruby_syntax!(project_root, path) }
    end

    def git_preflight_report(project_root, template_selection:, env: ENV)
      with_git_operation_lock(env) do
        inside = git_success?(project_root, "rev-parse", "--is-inside-work-tree")
        status = inside ? git_output(project_root, "status", "--porcelain") : nil
        dirty_entries = status.to_s.lines.map(&:chomp).reject(&:empty?)
        {
          git_repository: inside,
          clean_worktree: inside && dirty_entries.empty?,
          dirty_entries: dirty_entries,
          skip_commit: template_selection.fetch(:skip_commit, false)
        }
      end
    end

    def enforce_git_preflight!(git_preflight, decision_policy:, template_selection:)
      return unless decision_policy.require_clean
      return if template_selection.fetch(:skip_commit, false)
      raise Error, "Git preflight failed: project is not a git repository" unless git_preflight.fetch(:git_repository)
      raise Error, "Git preflight failed: worktree is not clean" unless git_preflight.fetch(:clean_worktree)
    end

    def git_success?(project_root, *args)
      _stdout, _stderr, status = Open3.capture3("git", "-C", project_root.to_s, *args)
      status.success?
    end

    def git_output(project_root, *args)
      stdout, _stderr, status = Open3.capture3("git", "-C", project_root.to_s, *args)
      status.success? ? stdout : ""
    end

    def with_git_operation_lock(env)
      lock_path = git_operation_lock_path(env || {})
      return yield if lock_path.to_s.empty?

      FileUtils.mkdir_p(File.dirname(lock_path))
      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      ensure
        lock&.flock(File::LOCK_UN)
      end
    end

    def git_operation_lock_path(env)
      %w[KETTLE_JEM_GIT_LOCK KETTLE_JEM_GIT_COMMIT_LOCK].each do |key|
        value = env.to_h[key].to_s.strip
        return value unless value.empty?
      end
      ""
    end

    def preflight_ruby_syntax!(project_root, path)
      if defined?(RubyVM::InstructionSequence)
        RubyVM::InstructionSequence.compile_file(path)
      else
        _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-c", path)
        raise SyntaxError, stderr unless status.success?
      end
    rescue SyntaxError => e
      relative_path = path.delete_prefix("#{project_root}/")
      raise Error, "Preflight failed for #{relative_path}: #{e.message}"
    end

    def delete_file_recipe?(recipe)
      FILE_DELETION_PRIMITIVES.include?(recipe.fetch(:primitive))
    end

    def workflow_recipe_slug(workflow_path)
      workflow_path.gsub(/[^a-zA-Z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    end

    def kettle_jem_config(project_root)
      path = kettle_jem_config_path(project_root)
      return {} unless File.exist?(path)

      config = YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      config = normalize_kettle_jem_config(config)
      validate_kettle_jem_config!(config)
      config
    rescue Psych::SyntaxError => error
      raise Error, "Invalid #{kettle_jem_config_relative_path(project_root)}: #{error.message}"
    end

    def normalize_kettle_jem_config(config)
      return config unless config.is_a?(Hash)

      files = config["files"]
      return config unless files.is_a?(Hash)

      simplecov_config = files[".simplecov"]
      return config unless simplecov_config.is_a?(Hash)
      return config unless simplecov_config.keys == ["strategy"] && simplecov_config["strategy"].to_s == "keep_destination"

      normalized = config.dup
      normalized["files"] = files.dup
      normalized["files"].delete(".simplecov")
      normalized
    end

    def kettle_jem_config_path(project_root)
      canonical = File.join(project_root, KETTLE_CONFIG_PATH)
      return canonical if File.exist?(canonical)

      File.join(project_root, LEGACY_KETTLE_CONFIG_PATH)
    end

    def kettle_jem_config_relative_path(project_root)
      path = kettle_jem_config_path(project_root)
      File.expand_path(path).delete_prefix("#{File.expand_path(project_root.to_s)}/")
    end

    def validate_kettle_jem_config!(config)
      raise Error, "Invalid kettle-jem config: root must be a mapping" unless config.is_a?(Hash)

      templates = config["templates"]
      if templates && !templates.is_a?(Hash)
        raise Error, "Invalid kettle-jem config: templates must be a mapping"
      end
      return unless templates&.key?("entries")
      return if templates["entries"].is_a?(Array)

      raise Error, "Invalid kettle-jem config: templates.entries must be a list"
    end

    def plugin_registry_for_project(project_root)
      plugin_names = PluginLoader.normalize_plugin_names(plugin_names_from_config(kettle_jem_config(project_root)))
      registry = PluginRegistry.new(configured_plugins: plugin_names)
      plugin_names.each do |plugin_name|
        PluginLoader.load_plugin!(plugin_name, registry: registry)
        registry.loaded_plugins << plugin_name
      rescue Error => e
        registry.load_errors << {
          plugin_name: plugin_name,
          message: e.message
        }
      end
      registry
    end

    def plugin_names_from_config(config)
      raw = config.is_a?(Hash) ? config["plugins"] : nil
      case raw
      when Hash
        raw.each_with_object([]) do |(name, enabled), names|
          names << name unless falsey_config?(enabled)
        end
      else
        raw
      end
    end

    def plugin_lifecycle_diagnostic(plugin_registry, callbacks_run:, active_runner_phases:)
      {
        kind: "plugin_lifecycle",
        configured_plugins: plugin_registry.configured_plugins,
        loaded_plugins: plugin_registry.loaded_plugins,
        load_errors: plugin_registry.load_errors,
        registered_hooks: plugin_registry.hooks.map do |hook|
          {
            plugin_name: hook.plugin_name,
            phase: hook.phase.to_s,
            timing: hook.timing.to_s
          }
        end,
        callbacks_run: callbacks_run,
        active_runner_phases: active_runner_phases.map(&:to_s)
      }
    end

    def run_apply_phases(project_root, report, file_workers: 0, file_thread_workers: 0, file_stats: nil)
      plugin_registry = plugin_registry_for_project(project_root)
      changed_files = report.fetch(:changed_files)
      diagnostics = report.fetch(:diagnostics)
      context = PluginContext.new(
        project_root: project_root,
        mode: "apply",
        facts: report.fetch(:facts),
        recipe_pack: report.fetch(:recipe_pack),
        recipe_reports: report.fetch(:recipe_reports),
        phase_reports: report.fetch(:phase_reports),
        changed_files: changed_files,
        diagnostics: diagnostics
      )
      reports_by_phase = report.fetch(:recipe_reports).group_by { |recipe_report| recipe_report_phase(recipe_report) }
      active_runner_phases = report.fetch(:phase_reports).map { |phase_report| phase_report.fetch(:phase).to_sym }
      active_runner_phases.each do |phase|
        phase_report = report.fetch(:phase_reports).find { |entry| entry.fetch(:phase).to_sym == phase }
        phase_stats = phase_report.fetch(:stats)
        unless plugin_registry.empty?
          plugin_registry.run(
            timing: :before,
            phase: phase,
            context: context,
            actor: self,
            phase_stats: phase_stats
          )
        end
        commit_file_work_units(
          file_work_units_for_phase(project_root, reports_by_phase.fetch(phase, [])),
          workers: file_workers,
          thread_workers: file_thread_workers,
          stats: file_stats
        )
        unless plugin_registry.empty?
          plugin_registry.run(
            timing: :after,
            phase: phase,
            context: context,
            actor: self,
            phase_stats: phase_stats
          )
        end
      end
      unless plugin_registry.configured_plugins.empty?
        diagnostics << plugin_lifecycle_diagnostic(
          plugin_registry,
          callbacks_run: true,
          active_runner_phases: active_runner_phases
        )
      end
      changed_files.sort!
      report[:run_stats] = recipe_run_stats(report.fetch(:recipe_reports), diagnostics: diagnostics)
    end

    def file_work_execution_stats(file_workers, file_thread_workers = 0)
      {
        file_worker_count: file_workers.to_i,
        file_thread_worker_count: file_thread_workers.to_i,
        file_work_units: 0,
        file_operations: 0,
        file_ractor_units: 0,
        file_ractor_spawn_count: 0,
        file_thread_units: 0,
        file_thread_spawn_count: 0,
        main_file_units: 0
      }
    end

    def apply_recipe_report(project_root, recipe_report)
      intent = write_intent_from_recipe_report(project_root, recipe_report)
      commit_file_outcome(intent) if intent
    end

    def commit_file_work_units(file_work_units, workers: 0, thread_workers: 0, stats: nil)
      units = Array(file_work_units)
      return if units.empty?

      raise ArgumentError, "Use either KETTLE_JEM_RACTOR_FILE_WORKERS or KETTLE_JEM_THREAD_FILE_WORKERS, not both" if workers.to_i.positive? && thread_workers.to_i.positive?

      record_file_work_execution_stats(stats, units: units, workers: workers.to_i, thread_workers: thread_workers.to_i)
      return commit_file_work_units_thread(units, workers: thread_workers.to_i) if thread_workers.to_i.positive?
      return commit_file_work_units_ractor(units, workers: workers.to_i) if workers.to_i.positive?

      units.each { |file_work_unit| commit_file_work_unit(file_work_unit) }
    end

    def record_file_work_execution_stats(stats, units:, workers:, thread_workers:)
      return unless stats

      stats[:file_work_units] += units.length
      stats[:file_operations] += units.sum { |unit| unit.operations.length }
      if workers.positive?
        stats[:file_ractor_units] += units.length
        stats[:file_ractor_spawn_count] += [workers, units.length].min
      elsif thread_workers.positive?
        stats[:file_thread_units] += units.length
        stats[:file_thread_spawn_count] += [thread_workers, units.length].min
      else
        stats[:main_file_units] += units.length
      end
    end

    def commit_file_work_units_thread(file_work_units, workers:)
      distribute_file_work_units(file_work_units, workers).map do |chunk|
        # rubocop:disable ThreadSafety/NewThread -- Independent file units are joined before this method returns.
        Thread.new { chunk.each { |file_work_unit| commit_file_work_unit(file_work_unit) } }
        # rubocop:enable ThreadSafety/NewThread
      end.each(&:join)
    end

    def commit_file_work_units_ractor(file_work_units, workers:)
      distribute_file_work_units(file_work_units, workers).map do |chunk|
        payloads = Ractor.make_shareable(chunk.map { |file_work_unit| file_work_unit_payload(file_work_unit) })
        Ractor.new(payloads) do |worker_payloads|
          worker_payloads.map do |worker_payload|
            Kettle::Jem.commit_file_work_unit_payload(worker_payload)
          end
        end
      end.each(&:value)
    end

    def distribute_file_work_units(file_work_units, workers)
      chunks = Array.new([workers, file_work_units.length].min) { [] }
      file_work_units.each_with_index do |file_work_unit, offset|
        chunks.fetch(offset % chunks.length) << file_work_unit
      end
      chunks
    end

    def commit_file_work_unit(file_work_unit)
      file_work_unit.operations.each { |operation| commit_file_outcome(operation) }
    end

    def file_work_units_for_phase(project_root, recipe_reports)
      file_work_units_from_write_intents(write_intents_for_phase(project_root, recipe_reports))
    end

    def write_intents_for_phase(project_root, recipe_reports)
      recipe_reports.filter_map { |recipe_report| write_intent_from_recipe_report(project_root, recipe_report) }
    end

    def file_work_units_from_write_intents(write_intents)
      grouped_operations = {}
      Array(write_intents).each do |write_intent|
        grouped_operations[write_intent.relative_path] ||= []
        grouped_operations[write_intent.relative_path] << write_intent
      end
      grouped_operations.map do |relative_path, operations|
        FileWorkUnit.new(relative_path: relative_path, operations: operations)
      end
    end

    def file_work_unit_payload(file_work_unit)
      {
        relative_path: file_work_unit.relative_path,
        operations: file_work_unit.operations.map { |operation| file_outcome_payload(operation) }
      }
    end

    def file_outcome_payload(file_outcome)
      {
        relative_path: file_outcome.relative_path,
        absolute_path: file_outcome.absolute_path,
        action: file_outcome.action.to_s,
        content: file_outcome.content
      }
    end

    def write_intent_from_recipe_report(project_root, recipe_report)
      return unless recipe_report[:changed]

      relative_path = recipe_report.fetch(:relative_path)
      action = recipe_report.dig(:metadata, :delete_file) ? :delete : :write
      content = (action == :write) ? recipe_report.fetch(:final_content) : nil
      WriteIntent.new(
        relative_path: relative_path,
        absolute_path: File.join(project_root, relative_path),
        action: action,
        content: content,
        recipe_name: recipe_report[:recipe_name],
        metadata: recipe_report.fetch(:metadata, {})
      )
    end

    def commit_write_intent(write_intent)
      commit_file_outcome(write_intent)
    end

    def commit_file_outcome(file_outcome)
      commit_filesystem_outcome(file_outcome)
    end

    def commit_filesystem_outcome(file_outcome)
      commit_filesystem_outcome_payload(file_outcome_payload(file_outcome))
    end

    def commit_file_work_unit_payload(payload)
      Array(payload.fetch(:operations)).each { |operation| commit_filesystem_outcome_payload(operation) }
      payload.fetch(:relative_path)
    end

    def commit_filesystem_outcome_payload(payload)
      path = payload.fetch(:absolute_path)
      action = payload.fetch(:action).to_s
      if action == "delete"
        File.delete(path) if File.exist?(path) || File.symlink?(path)
      elsif action == "write"
        mkdir_p_core(File.dirname(path))
        File.write(path, payload.fetch(:content))
      else
        raise ArgumentError, "Unsupported file outcome action #{action.inspect}"
      end
    end

    def mkdir_p_core(path)
      dir = path.to_s
      return if dir.empty? || dir == "." || Dir.exist?(dir)

      pending = []
      until dir.empty? || dir == "." || Dir.exist?(dir)
        pending << dir
        parent = File.dirname(dir)
        break if parent == dir

        dir = parent
      end
      pending.reverse_each do |entry|
        Dir.mkdir(entry) unless Dir.exist?(entry)
      rescue Errno::EEXIST
        nil
      end
    end

    def phase_reports_for(recipe_reports)
      reports_by_phase = recipe_reports.group_by { |recipe_report| recipe_report_phase(recipe_report) }
      PHASE_ORDER.map do |phase|
        reports = reports_by_phase.fetch(phase, [])
        changed_reports = reports.select { |recipe_report| recipe_report[:changed] }
        {
          phase: phase.to_s,
          recipes: reports.map { |recipe_report| recipe_report[:recipe_name] }.compact,
          changed_files: changed_reports.map { |recipe_report| recipe_report[:relative_path] }.compact.uniq.sort,
          stats: {
            recipe_count: reports.length,
            changed_count: changed_reports.length
          }
        }
      end
    end

    def recipe_report_phase(recipe_report)
      phase_for_recipe(recipe_report[:recipe_name], recipe_report[:relative_path])
    end

    def phase_for_recipe(recipe_name, relative_path)
      path = relative_path.to_s
      name = recipe_name.to_s
      return :config_sync if path == KETTLE_CONFIG_PATH || path == LEGACY_KETTLE_CONFIG_PATH || name.include?("kettle_config")
      return :dev_container if path.start_with?(".devcontainer/")
      return :github_workflows if path.start_with?(".github/workflows/") || path == ".github/FUNDING.yml"
      return :modular_gemfiles if path.start_with?("gemfiles/modular/")
      return :spec_helper if path == "spec/spec_helper.rb" || path.start_with?("spec/support/")
      return :environment_templates if path.start_with?(".env") || path.end_with?(".env")
      return :git_hooks if path.start_with?(".git/hooks/", "git-hooks/")
      return :license_files if path.start_with?("LICENSE", "NOTICE") || managed_license_template_basename(path)
      return :duplicate_check if name.include?("duplicate")
      return :quality_config if quality_config_path?(path)

      :remaining_files
    end

    def quality_config_path?(path)
      %w[
        .rubocop.yml
        .reek.yml
        .standard.yml
        .simplecov
        .yard-lint.yml
        .yardopts
        Rakefile
      ].include?(path)
    end

    def recipe_run_stats(recipe_reports, diagnostics: [])
      stats = {
        recipes: recipe_reports.length,
        created: 0,
        pre_existing: 0,
        identical: 0,
        changed: 0,
        deleted: 0,
        plugin_file_changes: diagnostics.count { |diagnostic| diagnostic[:kind] == "plugin_file_change" }
      }

      recipe_reports.each do |report|
        metadata = report.fetch(:metadata, {})
        if metadata[:delete_file]
          stats[:deleted] += 1 if report[:changed]
          next
        end

        if metadata[:destination_existed]
          stats[:pre_existing] += 1
          if report[:changed]
            stats[:changed] += 1
          else
            stats[:identical] += 1
          end
        elsif report[:changed]
          stats[:created] += 1
        end
      end

      stats[:summary] = recipe_run_stats_summary(stats)
      stats
    end

    def recipe_run_stats_summary(stats)
      [
        "recipes #{stats.fetch(:recipes)}",
        "created #{stats.fetch(:created)}",
        "pre_existing #{stats.fetch(:pre_existing)}",
        "identical #{stats.fetch(:identical)}",
        "changed #{stats.fetch(:changed)}",
        "deleted #{stats.fetch(:deleted)}",
        "plugin_file_changes #{stats.fetch(:plugin_file_changes)}"
      ].join(" ")
    end

    def opencollective_disabled?(config, env: ENV)
      opencollective_policy(config, env).fetch(:disabled)
    end

    def funding_platform_policies(config, env)
      funding = config["funding"]
      configured = funding.is_a?(Hash) ? funding : {}
      FUNDING_README_PLATFORMS.to_h do |platform|
        value = if platform == "open_collective"
          !opencollective_policy(config, env).fetch(:disabled)
        elsif configured.key?(platform)
          !falsey_config?(configured.fetch(platform))
        else
          !FUNDING_DEFAULT_DISABLED_PLATFORMS.include?(platform)
        end
        [platform, value]
      end
    end

    def funding_platform_enabled?(enabled_platforms, platform)
      return true unless enabled_platforms.is_a?(Hash)

      enabled_platforms.fetch(platform.to_s, true) == true
    end

    def opencollective_policy(config, env)
      funding = config["funding"]
      if funding.is_a?(Hash) && funding.key?("open_collective")
        config_value = funding["open_collective"]
        return {
          disabled: falsey_config?(config_value),
          source: "config.funding.open_collective",
          value: config_value.to_s
        }
      end

      env_falsey = opencollective_falsey_env(env)
      return {disabled: true, source: "env.#{env_falsey.fetch(:key)}", value: env_falsey.fetch(:value).to_s} if env_falsey

      template_profile = config.dig("templates", "profile").to_s
      if [MONOREPO_SUBGEM_TEMPLATE_PROFILE, "monorepo-subgem"].include?(template_profile)
        return {disabled: true, source: "config.templates.profile", value: template_profile}
      end

      {disabled: false}
    end

    def opencollective_falsey_env(env)
      %w[OPENCOLLECTIVE_HANDLE FUNDING_ORG].each do |key|
        value = env[key]
        return {key: key, value: value} if falsey_config?(value)
      end
      nil
    end

    def opencollective_org(project_root, config, env, opencollective_disabled: false)
      return if opencollective_disabled

      env_org = opencollective_org_env(env)
      return env_org if env_org

      config_org = opencollective_org_config(config)
      return config_org if config_org

      funding_org = opencollective_org_github_funding_file(project_root)
      return funding_org if funding_org

      opencollective_org_file(project_root)
    end

    def fallback_opencollective_org
      {org: DEFAULT_OPENCOLLECTIVE_ORG, source: "fallback.default"}
    end

    def opencollective_fallback_warnings(funding, github_org)
      return [] unless funding[:open_collective_org_source].to_s == "fallback.default"

      clean_github_org = github_org.to_s.strip
      return [] if clean_github_org.empty? || clean_github_org == DEFAULT_OPENCOLLECTIVE_ORG

      [
        "OpenCollective funding org defaulted to #{DEFAULT_OPENCOLLECTIVE_ORG.inspect}, but the GitHub org is #{clean_github_org.inspect}. Configure funding.open_collective or FUNDING_ORG if this is not intended."
      ]
    end

    def opencollective_org_config(config)
      funding = config["funding"]
      return unless funding.is_a?(Hash) && funding.key?("open_collective")

      value = funding["open_collective"]
      return if value == true || falsey_config?(value)

      org = value.to_s.strip
      return if org.empty?

      {org: org, source: "config.funding.open_collective"}
    end

    def opencollective_org_env(env)
      %w[OPENCOLLECTIVE_HANDLE FUNDING_ORG].each do |key|
        value = env[key].to_s.strip
        next if value.empty? || falsey_config?(value)

        return {org: value, source: "env.#{key}"}
      end
      nil
    end

    def opencollective_org_file(project_root)
      path = File.join(project_root, ".opencollective.yml")
      return unless File.exist?(path)

      config = YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      return unless config.is_a?(Hash)

      org = config.fetch("collective", config["org"]).to_s.strip
      return if org.empty?

      {org: org, source: ".opencollective.yml"}
    end

    def opencollective_org_github_funding_file(project_root)
      path = File.join(project_root, ".github", "FUNDING.yml")
      return unless File.exist?(path)

      funding = YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
      return unless funding.is_a?(Hash)

      org = Array(funding["open_collective"]).map(&:to_s).map(&:strip).reject(&:empty?).first
      return unless org

      {org: org.delete_prefix("@"), source: ".github/FUNDING.yml"}
    end

    def template_tokens(facts, funding)
      package = facts.fetch(:package)
      rubygems = facts.fetch(:rubygems)
      github_org = facts.fetch(:project_runtime, {})[:github_org].to_s
      github_org = facts.fetch(:forge, {})[:gh_user].to_s if github_org.empty?
      github_org = facts.fetch(:repository, {})[:slug].to_s.split("/", 2).first.to_s if github_org.empty?
      tokens = {
        "KJ|GEM_NAME" => package.fetch(:name).to_s,
        "KJ|PACKAGE_SUMMARY" => package.fetch(:summary, package.fetch(:description, "")).to_s,
        "KJ|PACKAGE_DESCRIPTION" => package.fetch(:description, package.fetch(:summary, "")).to_s,
        "KJ|GEMSPEC_PACKAGE_SUMMARY" => ruby_double_quoted_string_body(strip_leading_decorative_graphemes(package.fetch(:summary, package.fetch(:description, "")).to_s)),
        "KJ|GEMSPEC_PACKAGE_DESCRIPTION" => ruby_double_quoted_string_body(strip_leading_decorative_graphemes(package.fetch(:description, package.fetch(:summary, "")).to_s)),
        "KJ|GEM_NAME_PATH" => package.fetch(:name).to_s.tr("-", "/"),
        "KJ|ENTRYPOINT_REQUIRE" => rubygems.fetch(:entrypoint_require, package.fetch(:name).to_s.tr("-", "/")).to_s,
        "KJ|GEM_SHIELD" => shield_token(package.fetch(:name).to_s),
        "KJ|GEM_VERSION" => facts.dig(:project_runtime, :version).to_s,
        "KJ|GEM_MAJOR" => gem_major_token(facts.fetch(:project_runtime, {})[:version]),
        "KJ|SECURITY:SUPPORTED_VERSION" => security_supported_version_token(facts.fetch(:project_runtime, {})[:version]),
        "KJ|GH_ORG" => github_org,
        "KJ|NAMESPACE" => rubygems.fetch(:namespace, package.fetch(:name).to_s).to_s,
        "KJ|NAMESPACE_SHIELD" => shield_token(rubygems.fetch(:namespace, package.fetch(:name).to_s).to_s),
        "KJ|README:TITLE" => readme_title_token(package, rubygems),
        "KJ|MIN_RUBY" => minimum_ruby_token(rubygems[:min_ruby]),
        "KJ|MIN_DEV_RUBY" => facts.dig(:project_runtime, :test_min_ruby).to_s,
        "KJ|MIN_TEST_RUBY" => facts.dig(:project_runtime, :test_min_ruby).to_s,
        "KJ|KETTLE_CHANGELOG_GEMFILE_DEPENDENCY" => kettle_changelog_gemfile_dependency_token(
          package.fetch(:name).to_s
        ),
        "KJ|CI:EXEC_CMD" => facts.dig(:ci, :exec_cmd).to_s,
        "KJ|GITHUB_ACTIONS:COVERAGE_UPLOAD_STEPS" => github_actions_coverage_steps(disabled_integrations: facts.dig(:integrations, :disabled))
      }.merge(
        rubocop_template_tokens(rubygems[:min_ruby], ruby_style: facts.fetch(:ruby_style, {}))
      ).merge(
        author_template_tokens(facts.fetch(:author, {}))
      ).merge(
        forge_template_tokens(facts.fetch(:forge, {}))
      ).merge(
        funding_template_tokens(funding)
      ).merge(
        social_template_tokens(facts.fetch(:social, {}))
      ).merge(
        license_template_tokens(facts.fetch(:license, {}))
      ).merge(
        gemspec_template_tokens(facts.fetch(:gemspec, {}), min_ruby: rubygems[:min_ruby])
      ).merge(
        project_runtime_template_tokens(facts.fetch(:project_runtime, {}))
      ).merge(
        readme_url_template_tokens(facts.fetch(:repository, {}), package.fetch(:name).to_s, github_org)
      ).merge(
        readme_logo_template_tokens(facts.fetch(:readme_logo, {}))
      ).merge(
        readme_corporate_sponsor_template_tokens(facts.fetch(:readme_sponsors, {}))
      )
      org = funding[:open_collective_org].to_s
      tokens["KJ|OPENCOLLECTIVE_ORG"] = org
      tokens["KJ|README:FAMILY_INTRO_BACKEND_MATRIX"] =
        readme_family_intro_and_backend_matrix(facts.fetch(:readme_style, {}))
      tokens["KJ|README:DEV_TEST_STACK_TABLE"] = readme_dev_test_stack_table(package.fetch(:name).to_s)
      tokens.merge!(readme_fossa_template_tokens(facts.fetch(:readme_style, {})))
      tokens.merge!(rubyforum_template_tokens(facts.fetch(:rubyforum, {})))
      tokens.merge!(version_gem_template_tokens(facts))
      tokens.merge!(shim_template_tokens(facts.fetch(:shim, {})))

      tokens.reject { |key, value| value.empty? && !EMPTY_TEMPLATE_TOKENS.include?(key) }
    end

    def kettle_changelog_gemfile_dependency_token(package_name)
      return "" if package_name == "kettle-changelog"

      <<~RUBY.chomp
        # Release lockfile/build commands set this dependency-specific switch so
        # the development tool cannot pull unpublished family gems into resolution.
        kettle_changelog_skip = ENV.fetch("KETTLE_DEV_SKIP_CHANGELOG_DEPENDENCY", "false").downcase
        kettle_changelog_skip = %w[true 1 yes on].include?(kettle_changelog_skip)
        kettle_changelog_local = ENV.fetch("KETTLE_DEV_DEV", "false").downcase
        kettle_changelog_local = !%w[false 0 no off].include?(kettle_changelog_local)
        unless kettle_changelog_skip
          if kettle_changelog_local
            require "nomono/bundler"
            eval_nomono_gems(
              gems: ["kettle-changelog"],
              prefix: "KETTLE_DEV",
              path_env: "KETTLE_DEV_DEV",
              root: ["src", "my", "kettle-dev"]
            )
          elsif Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("4.0.0")
            gem "kettle-changelog", "~> 1.0", ">= 1.0.7"
          end
        end
      RUBY
    end

    def readme_title_token(package, rubygems)
      package_name = package.fetch(:name).to_s.strip
      default_entrypoint = package_name.tr("-", "/")
      entrypoint = rubygems.fetch(:entrypoint_require, default_entrypoint).to_s.strip
      namespace = rubygems.fetch(:namespace, package_name).to_s.strip
      return namespace if entrypoint.empty? || entrypoint == default_entrypoint || namespace.empty?

      "#{package_name} / #{namespace}"
    end

    def readme_dev_test_stack_table(package_name)
      rows = README_DEV_TEST_STACK_GEMS.reject { |gem| gem.fetch(:name) == package_name.to_s }.map do |gem|
        name = gem.fetch(:name)
        clickgems_url = "https://clickgems.clickhouse.com/dashboard/#{name}"
        badge_url = "https://img.shields.io/gem/dt/#{name}.svg?style=flat-square"
        [
          "| [#{name}](#{clickgems_url})",
          "[GitHub](#{gem.fetch(:repo)})",
          gem.fetch(:role),
          "[![Total downloads for #{name}](#{badge_url})](#{clickgems_url}) |"
        ].join(" | ")
      end

      [
        '<details markdown="1">',
        "<summary>How kettle-dev manages complexity in tests</summary>",
        "",
        "| Gem | Source | Role | Total downloads |",
        "|-----|--------|------|---------------------|",
        *rows,
        "",
        "</details>"
      ].join("\n")
    end

    def shim_template_tokens(shim)
      return {} unless shim.is_a?(Hash) && !shim.empty?

      {
        "KJ|SHIMMED_GEM_NAME" => shim[:replacement_gem].to_s,
        "KJ|SHIMMED_REQUIRE" => shim[:replacement_require].to_s,
        "KJ|SHIM_COMPAT_REQUIRES" => Array(shim[:legacy_requires]).join(", ")
      }
    end

    def readme_fossa_template_tokens(readme_style)
      project = readme_style.fetch(:fossa_project, "").to_s
      return {"KJ|README:FOSSA_BADGE" => "", "KJ|README:FOSSA_REFS" => ""} if project.empty?

      encoded_project = URI.encode_www_form_component(project)
      {
        "KJ|README:FOSSA_BADGE" => README_FOSSA_BADGE,
        "KJ|README:FOSSA_REFS" => [
          "[🧪fossa]: https://app.fossa.com/projects/#{encoded_project}?ref=badge_shield",
          "[🧪fossa-img]: https://app.fossa.com/api/projects/#{encoded_project}.svg?type=shield"
        ].join("\n")
      }
    end

    def rubyforum_facts(config, env, package_name:)
      rubyforum_config = config["rubyforum"].is_a?(Hash) ? config["rubyforum"] : {}
      family_tag = preferred_template_token_value(nil, rubyforum_config["family_tag"], env, "KJ_RUBYFORUM_FAMILY_TAG").to_s
      project_tag = preferred_template_token_value(nil, rubyforum_config["project_tag"], env, "KJ_RUBYFORUM_PROJECT_TAG").to_s
      family_tag = normalize_rubyforum_tag(family_tag)
      project_tag = normalize_rubyforum_tag(project_tag)
      tag = project_tag.empty? ? family_tag : project_tag
      tag = normalize_rubyforum_tag(package_name) if tag.empty?
      return {} if tag.empty?

      url = rubyforum_tag_url(tag)
      {
        family_tag: family_tag,
        project_tag: project_tag,
        tag: tag,
        url: url,
        badge_img: rubyforum_badge_image_url,
        badge_img_ftb: rubyforum_badge_image_url(style: "for-the-badge")
      }
    end

    def normalize_rubyforum_tag(value)
      value.to_s.strip.delete_prefix("#").delete_suffix("/").split("/").last.to_s
    end

    def rubyforum_tag_url(tag)
      "https://www.rubyforum.org/tag/#{URI.encode_www_form_component(tag.to_s)}"
    end

    def rubyforum_badge_image_url(style: "flat")
      "https://img.shields.io/discourse/topics?server=https%3A%2F%2Fwww.rubyforum.org&style=#{style}&logo=discourse&label=Ruby%20Users%20Forum"
    end

    def rubyforum_template_tokens(rubyforum)
      url = rubyforum[:url].to_s
      badge_img = rubyforum[:badge_img].to_s
      badge_img_ftb = rubyforum[:badge_img_ftb].to_s
      {
        "KJ|RUBYFORUM:TAG" => rubyforum[:tag].to_s,
        "KJ|RUBYFORUM:FAMILY_TAG" => rubyforum[:family_tag].to_s,
        "KJ|RUBYFORUM:PROJECT_TAG" => rubyforum[:project_tag].to_s,
        "KJ|RUBYFORUM:URL" => url,
        "KJ|RUBYFORUM:BADGE_IMG" => badge_img,
        "KJ|RUBYFORUM:BADGE_IMG_FTB" => badge_img_ftb
      }
    end

    def readme_url_template_tokens(repository, package_name, github_org)
      repo_url = repository[:url].to_s
      repo_name = repository[:name].to_s
      repo_slug = repository[:slug].to_s
      package_path = repository[:package_path].to_s
      package_source_url = repository[:package_source_url].to_s
      repo_url = "https://github.com/#{github_org}/#{package_name}" if repo_url.empty?
      repo_name = package_name if repo_name.empty?
      repo_slug = "#{github_org}/#{repo_name}" if repo_slug.empty?
      package_source_url = repo_url if package_source_url.empty?

      repository = repository.merge(
        url: repo_url,
        name: repo_name,
        slug: repo_slug,
        package_path: package_path,
        package_source_url: package_source_url
      )
      resources = repository[:resource_urls].is_a?(Hash) ? repository[:resource_urls] : repository_resource_urls(repository)
      resource_url = lambda do |key, fallback|
        value = resources[key].to_s
        value.empty? ? fallback : value
      end

      gitlab_source = repository[:gitlab_package_source_url].to_s
      codeberg_source = repository[:codeberg_package_source_url].to_s
      gitlab_source = "https://gitlab.com/#{repo_slug}/" if gitlab_source.empty?
      codeberg_source = "https://codeberg.org/#{repo_slug}" if codeberg_source.empty?
      checksums_url = repository[:checksums_url].to_s
      checksums_url = "https://gitlab.com/#{repo_slug}/-/tree/main/checksums" if checksums_url.empty?

      {
        "KJ|README:REPO_SLUG" => repo_slug,
        "KJ|README:REPO_NAME" => repo_name,
        "KJ|README:PACKAGE_PATH" => package_path,
        "KJ|README:GH_REPOSITORY_URL" => resource_url.call(:github_repository_url, repo_url),
        "KJ|README:GH_PACKAGE_SOURCE_URL" => resource_url.call(:github_package_source_url, package_source_url),
        "KJ|README:GH_RELEASES_URL" => resource_url.call(:github_releases_url, "#{repo_url}/releases"),
        "KJ|README:GH_TAG_BADGE_REPO" => repo_slug,
        "KJ|README:GH_ACTIONS_URL" => resource_url.call(:github_actions_url, "#{repo_url}/actions"),
        "KJ|README:GH_DISCUSSIONS_URL" => resource_url.call(:github_discussions_url, "#{repo_url}/discussions"),
        "KJ|README:GH_ISSUES_URL" => resource_url.call(:github_issues_url, "#{repo_url}/issues"),
        "KJ|README:GH_PULLS_URL" => resource_url.call(:github_pulls_url, "#{repo_url}/pulls"),
        "KJ|README:GH_WIKI_URL" => resource_url.call(:github_wiki_url, "#{repo_url}/wiki"),
        "KJ|README:GH_CODEQL_URL" => resource_url.call(:github_codeql_url, "#{repo_url}/security/code-scanning"),
        "KJ|README:GH_CONTRIBUTORS_URL" => resource_url.call(:github_contributors_url, "#{repo_url}/graphs/contributors"),
        "KJ|README:GH_CONTRIBUTING_URL" => resource_url.call(:github_contributing_url, source_blob_url(repo_url, "CONTRIBUTING.md")),
        "KJ|README:GH_CHANGELOG_URL" => resource_url.call(:github_changelog_url, source_blob_url(repo_url, "CHANGELOG.md")),
        "KJ|README:GH_SECURITY_URL" => resource_url.call(:github_security_url, source_blob_url(repo_url, "SECURITY.md")),
        "KJ|README:GH_CODE_OF_CONDUCT_URL" => resource_url.call(:github_code_of_conduct_url, source_blob_url(repo_url, "CODE_OF_CONDUCT.md")),
        "KJ|README:GH_RUBOCOP_URL" => resource_url.call(:github_rubocop_url, source_blob_url(repo_url, "RUBOCOP.md")),
        "KJ|README:GH_IRP_URL" => resource_url.call(:github_irp_url, source_blob_url(repo_url, "IRP.md")),
        "KJ|README:GL_REPOSITORY_URL" => resource_url.call(:gitlab_repository_url, "https://gitlab.com/#{repo_slug}"),
        "KJ|README:GL_PACKAGE_SOURCE_URL" => resource_url.call(:gitlab_package_source_url, gitlab_source),
        "KJ|README:GL_ISSUES_URL" => resource_url.call(:gitlab_issues_url, gitlab_repo_url(repository, repo_slug, "issues")),
        "KJ|README:GL_PULLS_URL" => resource_url.call(:gitlab_pulls_url, gitlab_repo_url(repository, repo_slug, "merge_requests")),
        "KJ|README:GL_WIKI_URL" => resource_url.call(:gitlab_wiki_url, gitlab_repo_url(repository, repo_slug, "wikis/home")),
        "KJ|README:GL_CONTRIBUTORS_URL" => resource_url.call(:gitlab_contributors_url, gitlab_repo_url(repository, repo_slug, "graphs/main")),
        "KJ|README:GL_CONTRIBUTING_URL" => resource_url.call(:gitlab_contributing_url, source_blob_url("https://gitlab.com/#{repo_slug}", "CONTRIBUTING.md")),
        "KJ|README:GL_CHANGELOG_URL" => resource_url.call(:gitlab_changelog_url, source_blob_url("https://gitlab.com/#{repo_slug}", "CHANGELOG.md")),
        "KJ|README:GL_CODE_OF_CONDUCT_URL" => resource_url.call(:gitlab_code_of_conduct_url, source_blob_url("https://gitlab.com/#{repo_slug}", "CODE_OF_CONDUCT.md")),
        "KJ|README:CB_REPOSITORY_URL" => resource_url.call(:codeberg_repository_url, "https://codeberg.org/#{repo_slug}"),
        "KJ|README:CB_PACKAGE_SOURCE_URL" => resource_url.call(:codeberg_package_source_url, codeberg_source),
        "KJ|README:CB_ISSUES_URL" => resource_url.call(:codeberg_issues_url, codeberg_repo_url(repository, repo_slug, "issues")),
        "KJ|README:CB_PULLS_URL" => resource_url.call(:codeberg_pulls_url, codeberg_repo_url(repository, repo_slug, "pulls")),
        "KJ|README:CODECOV_URL" => resource_url.call(:codecov_url, "https://codecov.io/gh/#{repo_slug}"),
        "KJ|README:CODECOV_BADGE_URL" => resource_url.call(:codecov_badge_url, "https://codecov.io/gh/#{repo_slug}/graph/badge.svg"),
        "KJ|README:CODECOV_GRAPH_URL" => resource_url.call(:codecov_graph_url, "https://codecov.io/gh/#{repo_slug}/graph/badge.svg"),
        "KJ|README:COVERALLS_URL" => resource_url.call(:coveralls_url, "https://coveralls.io/github/#{repo_slug}?branch=main"),
        "KJ|README:COVERALLS_BADGE_URL" => resource_url.call(:coveralls_badge_url, "https://coveralls.io/repos/github/#{repo_slug}/badge.svg?branch=main"),
        "KJ|README:QLTY_PROJECT_URL" => resource_url.call(:qlty_project_url, "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}"),
        "KJ|README:QLTY_MAINTAINABILITY_URL" => resource_url.call(:qlty_maintainability_url, "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}/maintainability.svg"),
        "KJ|README:QLTY_COVERAGE_URL" => resource_url.call(:qlty_coverage_url, "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}/metrics/code?sort=coverageRating"),
        "KJ|README:QLTY_COVERAGE_BADGE_URL" => resource_url.call(:qlty_coverage_badge_url, "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}/coverage.svg"),
        "KJ|CHANGELOG:GL_COMPARE_URL" => resource_url.call(:gitlab_compare_url, "https://gitlab.com/#{repo_slug}/-/compare"),
        "KJ|CHANGELOG:GL_TAGS_URL" => resource_url.call(:gitlab_tags_url, "https://gitlab.com/#{repo_slug}/-/tags"),
        "KJ|README:CONTRIBUTORS_IMAGE_REPO" => repo_slug,
        "KJ|README:STAR_HISTORY_REPO" => repo_slug,
        "KJ|README:SHA_CHECKSUMS_URL" => resource_url.call(:checksums_url, checksums_url)
      }
    end

    def version_gem_template_tokens(facts)
      namespace = facts.dig(:rubygems, :namespace).to_s
      version = facts.dig(:project_runtime, :version).to_s
      version = "0.0.1.pre" if version.empty?
      return {} if namespace.empty?

      namespace_kinds = version_namespace_kinds_from_facts(facts)
      outer_namespace_kind = namespace_kinds.fetch(namespace.split("::").length - 1, :module)

      version_rb = if facts.dig(:shim, :version_strategy).to_s == "shim"
        shim_version_file_content(
          namespace: namespace,
          replacement_namespace: shim_replacement_namespace(facts.dig(:shim, :replacement_require)),
          replacement_require: facts.dig(:shim, :replacement_require)
        )
      else
        version_gem_version_file_content(
          existing_version: "",
          namespace: namespace,
          version: version,
          outer_namespace_kind: outer_namespace_kind,
          namespace_kinds: namespace_kinds
        )
      end

      {
        "KJ|GEM_VERSION" => version,
        "KJ|VERSION_GEM:VERSION_RB" => version_rb.chomp,
        "KJ|VERSION_GEM:VERSION_GEM_RB" => version_gem_entrypoint_file_content(
          namespace: namespace,
          entrypoint_require: facts.dig(:rubygems, :entrypoint_require).to_s,
          dedicated: true
        ).chomp,
        "KJ|VERSION_GEM:VERSION_RBS" => version_gem_signature_file_content(
          namespace: namespace,
          outer_namespace_kind: outer_namespace_kind,
          namespace_kinds: namespace_kinds
        ).chomp
      }
    end

    SHIM_REPLACEMENT_NAMESPACE_ACRONYMS = {
      "jwt" => "JWT",
      "jwt2" => "JWT2",
      "oauth" => "OAuth",
      "oauth2" => "OAuth2"
    }.freeze
    private_constant :SHIM_REPLACEMENT_NAMESPACE_ACRONYMS

    def shim_replacement_namespace(replacement_require)
      replacement_require.to_s.tr("-", "/").split("/").reject(&:empty?).map do |segment|
        SHIM_REPLACEMENT_NAMESPACE_ACRONYMS.fetch(segment) do
          segment.split("_").map { |part| "#{part[0].to_s.upcase}#{part[1..]}" }.join
        end
      end.join("::")
    end

    def shim_version_file_content(namespace:, replacement_namespace:, replacement_require:)
      body = [
        "# Version namespace delegated to the replacement gem.",
        "Version = #{replacement_namespace}::Version unless const_defined?(:Version, false)",
        "# Current gem version delegated to the replacement gem.",
        "VERSION = #{replacement_namespace}::VERSION unless const_defined?(:VERSION, false)"
      ]

      <<~RUBY
        # frozen_string_literal: true

        require #{replacement_require.to_s.dump}

        #{wrap_ruby_namespace(namespace, body).join("\n")}
      RUBY
    end

    def readme_family_intro_and_backend_matrix(readme_style = {})
      return "" unless readme_style.is_a?(Hash) && readme_style[:package_family].to_s == "structuredmerge"

      [
        "<details markdown=\"1\">",
        "<summary>StructuredMerge package family</summary>",
        "",
        "This gem is part of the StructuredMerge Ruby package family. The implementation inventory, layering model, and backend notes live in the [root package-family guide][sm-family-guide]. Shared behavior is defined by the [StructuredMerge fixtures][sm-family-fixtures] and implemented by the [Go][sm-family-go], [Ruby][sm-family-ruby], [Rust][sm-family-rust], and [TypeScript][sm-family-typescript] repositories.",
        "",
        "Merge analysis must enter parsing through `tree_haver`. Parser-specific gems register concrete TreeHaver backends; substrate gems register grammar mappings and keep shared format or language merge behavior in one place. Missing backends fail closed instead of falling back to direct parser-library calls.",
        "",
        "</details>",
        "",
        "[sm-family-guide]: https://github.com/structuredmerge/structuredmerge-ruby#package-family",
        "[sm-family-fixtures]: https://github.com/structuredmerge/structuredmerge-fixtures",
        "[sm-family-go]: https://github.com/structuredmerge/structuredmerge-go",
        "[sm-family-ruby]: https://github.com/structuredmerge/structuredmerge-ruby",
        "[sm-family-rust]: https://github.com/structuredmerge/structuredmerge-rust",
        "[sm-family-typescript]: https://github.com/structuredmerge/structuredmerge-typescript"
      ].join("\n")
    end

    def minimum_ruby_token(requirement)
      text = requirement.to_s.strip
      return "0" if text == "0"

      requirement.to_s[/\d+(?:\.\d+){1,2}/].to_s
    end

    def gem_major_token(version)
      Gem::Version.new(version.to_s).segments.first.to_s
    rescue ArgumentError
      "0"
    end

    def security_supported_version_token(version)
      parsed = Gem::Version.new(version.to_s)
      major = parsed.segments.fetch(0, 0).to_i
      return "0.latest" if major.zero?

      minor = parsed.segments.fetch(1, 0).to_i
      "#{major}.#{minor}.latest"
    rescue ArgumentError
      "0.latest"
    end

    def valid_gem_version?(version)
      text = version.to_s
      return false if text.empty?

      Gem::Version.new(text)
      true
    rescue ArgumentError
      false
    end

    def author_facts(config, env, gemspec_metadata: {}, copyright: {})
      token_config = token_config_values(config)
      author_config = token_config["author"].is_a?(Hash) ? token_config["author"] : {}
      aliases = author_aliases(config)
      derived_name = Array(gemspec_metadata[:authors]).map { |value| canonical_author_name(value, aliases) }.find do |value|
        present_template_token_value?(value)
      end
      derived_email = Array(gemspec_metadata[:email]).map(&:to_s).find { |value| present_template_token_value?(value) }
      name = preferred_template_token_value(derived_name, author_config["name"], env, "KJ_AUTHOR_NAME").to_s
      email = preferred_template_token_value(derived_email, author_config["email"], env, "KJ_AUTHOR_EMAIL").to_s
      given_names = preferred_template_token_value(author_given_names(name), author_config["given_names"], env, "KJ_AUTHOR_GIVEN_NAMES")
      family_names = preferred_template_token_value(author_family_names(name), author_config["family_names"], env, "KJ_AUTHOR_FAMILY_NAMES")
      domain = preferred_template_token_value(email.split("@", 2)[1], author_config["domain"], env, "KJ_AUTHOR_DOMAIN")
      orcid = preferred_template_token_value(nil, author_config["orcid"], env, "KJ_AUTHOR_ORCID")
      compact_hash(
        name: name,
        names: author_names(gemspec_metadata, copyright, name, author_aliases: aliases),
        given_names: given_names.to_s,
        family_names: family_names.to_s,
        email: email,
        domain: domain.to_s,
        orcid: orcid.to_s
      )
    end

    def token_config_values(config)
      raw = config.is_a?(Hash) ? config["tokens"] : nil
      raw.is_a?(Hash) ? raw : {}
    end

    def preferred_template_token_value(derived_value, config_value, env, env_key)
      env_clean = env[env_key].to_s.strip
      return env_clean if present_template_token_value?(env_clean)

      config_clean = config_value.to_s.strip
      return config_clean if present_template_token_value?(config_clean)
      return unless present_template_token_value?(derived_value)

      derived_value.to_s.strip
    end

    def present_template_token_value?(value)
      clean = value.to_s.strip
      !clean.empty? && !token_placeholder?(clean)
    end

    def token_placeholder?(value)
      value.to_s.strip.match?(%r{\A\{KJ\|[A-Z][A-Z0-9_:]*\}\z})
    end

    def author_aliases(config)
      return {} unless config.is_a?(Hash)

      configured = config["author_aliases"]
      configured = config.dig("copyright", "author_aliases") if configured.nil? && config["copyright"].is_a?(Hash)
      return {} unless configured.is_a?(Hash)

      configured.each_with_object({}) do |(alias_name, canonical_name), aliases|
        alias_key = alias_name.to_s.strip.downcase
        canonical = canonical_name.to_s.strip
        next if alias_key.empty? || canonical.empty?

        aliases[alias_key] = canonical
      end
    end

    def canonical_author_name(value, aliases)
      current = value.to_s.strip
      seen = {}
      loop do
        key = current.downcase
        break if current.empty? || seen[key]

        seen[key] = true
        replacement = aliases[key]
        break if replacement.nil? || replacement.to_s.strip.empty?

        current = replacement.to_s.strip
      end
      current
    end

    def canonical_author_name_for_entry(entry, aliases)
      name = entry[:name].to_s.strip
      email = entry[:email].to_s.strip
      configured_name = aliases[name.downcase]
      configured_email = aliases[email.downcase]
      canonical_author_name(configured_name || configured_email || name, aliases)
    end

    def author_template_tokens(author)
      names = Array(author[:names]).map(&:to_s).reject(&:empty?)
      names = [author[:name].to_s] if names.empty?
      {
        "KJ|AUTHOR:NAME" => author[:name].to_s,
        "KJ|AUTHOR:NAMES" => ruby_array_literal(names),
        "KJ|AUTHOR:GIVEN_NAMES" => author[:given_names].to_s,
        "KJ|AUTHOR:FAMILY_NAMES" => author[:family_names].to_s,
        "KJ|AUTHOR:EMAIL" => author[:email].to_s,
        "KJ|AUTHOR:DOMAIN" => author[:domain].to_s,
        "KJ|AUTHOR:ORCID" => author[:orcid].to_s
      }
    end

    def author_names(gemspec_metadata, copyright, primary_name, author_aliases: {})
      names = Array(gemspec_metadata[:authors]).map(&:to_s)
      names += copyright_author_names(copyright)
      names = names
        .map { |name| canonical_author_name(name, author_aliases) }
        .select { |name| present_template_token_value?(name) }
      names = [canonical_author_name(primary_name, author_aliases)] if names.empty?
      names.map(&:strip).reject(&:empty?).uniq
    end

    def copyright_author_names(copyright)
      Array(copyright[:lines]).filter_map do |line|
        copyright_name_from_line(line.to_s)
      end
    end

    def copyright_name_from_line(line)
      prefix = "Copyright (c) "
      return unless line.start_with?(prefix)

      tokens = line[prefix.length..].to_s.split
      tokens.shift while tokens.first && copyright_year_token?(tokens.first)
      tokens.join(" ").strip.then { |name| name unless name.empty? }
    end

    def copyright_year_token?(token)
      token.delete(",-").chars.all? { |char| char.between?("0", "9") }
    end

    def ruby_array_literal(values)
      "[#{Array(values).map { |value| %("#{ruby_double_quoted_string_body(value.to_s)}") }.join(", ")}]"
    end

    def copyright_facts(project_root, config)
      lines = git_copyright_lines(
        project_root,
        copyright_machine_users(config),
        author_aliases: author_aliases(config)
      )
      compact_hash(lines: lines)
    end

    def copyright_machine_users(config)
      copyright = config["copyright"].is_a?(Hash) ? config["copyright"] : {}
      configured = DEFAULT_MACHINE_USERS + Array(config["machine_users"]) + Array(copyright["machine_users"])
      configured.map { |user| user.to_s.downcase.strip }.reject(&:empty?).uniq
    end

    def git_copyright_lines(project_root, machine_users, author_aliases: {})
      files = git_capture(project_root, "ls-files", "-z")
      return [] if files.to_s.empty?

      author_map = Hash.new { |hash, email| hash[email] = {name: nil, years: [], email: email} }
      files.split("\0").reject(&:empty?).each do |relative_path|
        next unless File.exist?(File.join(project_root, relative_path))

        parse_blame_porcelain(git_capture(project_root, "blame", "--porcelain", "--", relative_path), author_map)
      rescue ArgumentError
        next
      end
      resolve_uncommitted_author!(project_root, author_map)
      consolidated = author_map.values
        .reject { |entry| copyright_bot_entry?(entry) }
        .reject { |entry| copyright_machine_user_entry?(entry, machine_users, author_aliases: author_aliases) }
        .each_with_object({}) do |entry, authors|
          next if entry[:name].to_s.strip.empty? || entry[:years].empty?

          name = canonical_author_name_for_entry(entry, author_aliases)
          next if name.empty?

          author = authors[name.downcase] ||= {name: name, years: []}
          author[:years].concat(entry[:years])
        end
        .values
      consolidated
        .sort_by { |entry| [entry[:years].map(&:to_i).min, entry[:name].to_s.downcase] }
        .map { |entry| "Copyright (c) #{format_copyright_years(entry[:years])} #{entry[:name]}" }
    rescue ArgumentError
      []
    end

    def git_capture(project_root, *args)
      output, status = Open3.capture2("git", "-C", project_root.to_s, *args, err: File::NULL)
      raise ArgumentError, "git #{args.join(" ")} failed" unless status.success?

      output.to_s
    end

    def parse_blame_porcelain(output, author_map)
      commit_meta = {}
      current_sha = nil
      current_name = nil
      current_email = nil
      current_time = nil
      output.to_s.each_line do |raw_line|
        line = raw_line.chomp
        if line.match?(/\A[0-9a-f]{40}\s/)
          current_sha = line[0, 40]
          meta = commit_meta[current_sha]
          current_name = meta && meta[:name]
          current_email = meta && meta[:email]
          current_time = meta && meta[:time]
        elsif line.start_with?("author ") && !commit_meta.key?(current_sha.to_s)
          current_name = line[7..].strip
        elsif line.start_with?("author-mail ") && !commit_meta.key?(current_sha.to_s)
          current_email = line[12..].strip.gsub(/[<>]/, "")
        elsif line.start_with?("author-time ") && !commit_meta.key?(current_sha.to_s)
          current_time = line[12..].strip.to_i
        elsif line.start_with?("filename ")
          next unless current_sha && current_email

          commit_meta[current_sha] ||= {name: current_name, email: current_email, time: current_time}
          year = current_time&.positive? ? Time.at(current_time).utc.year.to_s : Time.now.utc.year.to_s
          author_map[current_email][:name] ||= current_name
          author_map[current_email][:years] << year
        end
      end
    end

    def resolve_uncommitted_author!(project_root, author_map)
      uncommitted = author_map.delete(NOT_COMMITTED_EMAIL)
      return unless uncommitted && !uncommitted[:years].empty?

      name = git_capture(project_root, "config", "user.name").strip
      email = git_capture(project_root, "config", "user.email").strip
      return if email.empty?

      author_map[email][:name] ||= name
      author_map[email][:years].concat(uncommitted[:years])
    rescue ArgumentError
      nil
    end

    def copyright_bot_entry?(entry)
      entry[:name].to_s.match?(BOT_IDENTITY_PATTERN) || entry[:email].to_s.match?(BOT_IDENTITY_PATTERN)
    end

    def copyright_machine_user_entry?(entry, machine_users, author_aliases: {})
      return false if machine_users.empty?

      identities = [
        entry[:name],
        entry[:email],
        canonical_author_name_for_entry(entry, author_aliases)
      ].map { |identity| identity.to_s.downcase.strip }
      identities.any? { |identity| machine_users.include?(identity) }
    end

    def format_copyright_years(years)
      sorted = Array(years).map(&:to_i).reject(&:zero?).sort.uniq
      return Time.now.utc.year.to_s if sorted.empty?
      return sorted.first.to_s if sorted.one?

      runs = []
      run = [sorted.first]
      sorted[1..].to_a.each do |year|
        if year == run.last + 1
          run << year
        else
          runs << run
          run = [year]
        end
      end
      runs << run
      runs.map { |span| span.one? ? span.first.to_s : "#{span.first}-#{span.last}" }.join(", ")
    end

    def forge_facts(config, env, derived_github_user: nil)
      token_config = token_config_values(config)
      forge_config = token_config["forge"].is_a?(Hash) ? token_config["forge"] : {}
      compact_hash(
        gh_user: forge_user_value(forge_config, env, :gh_user, derived_value: derived_github_user).to_s,
        gl_user: forge_user_value(forge_config, env, :gl_user).to_s,
        cb_user: forge_user_value(forge_config, env, :cb_user).to_s,
        sh_user: forge_user_value(forge_config, env, :sh_user).to_s
      )
    end

    def forge_user_value(forge_config, env, key, derived_value: nil)
      preferred_template_token_value(derived_value, forge_config[key.to_s], env, FORGE_USER_ENV_KEYS.fetch(key))
    end

    def forge_template_tokens(forge)
      {
        "KJ|GH:USER" => forge[:gh_user].to_s,
        "KJ|GL:USER" => forge[:gl_user].to_s,
        "KJ|CB:USER" => forge[:cb_user].to_s,
        "KJ|SH:USER" => forge[:sh_user].to_s
      }
    end

    def funding_platform_token_facts(config, env)
      token_config = token_config_values(config)
      funding_config = token_config["funding"].is_a?(Hash) ? token_config["funding"] : {}
      compact_hash(
        kofi: funding_platform_token_value(funding_config, env, :kofi).to_s,
        paypal: funding_platform_token_value(funding_config, env, :paypal).to_s,
        buymeacoffee: funding_platform_token_value(funding_config, env, :buymeacoffee).to_s,
        liberapay: funding_platform_token_value(funding_config, env, :liberapay).to_s
      )
    end

    def funding_platform_token_value(funding_config, env, key)
      preferred_template_token_value(nil, funding_config[key.to_s], env, FUNDING_TOKEN_ENV_KEYS.fetch(key))
    end

    def funding_template_tokens(funding)
      platform_tokens = funding.fetch(:platform_tokens, {})
      {
        "KJ|FUNDING:KOFI" => platform_tokens[:kofi].to_s,
        "KJ|FUNDING:PAYPAL" => platform_tokens[:paypal].to_s,
        "KJ|FUNDING:BUYMEACOFFEE" => platform_tokens[:buymeacoffee].to_s,
        "KJ|FUNDING:LIBERAPAY" => platform_tokens[:liberapay].to_s
      }
    end

    def social_facts(config, env)
      token_config = token_config_values(config)
      social_config = token_config["social"].is_a?(Hash) ? token_config["social"] : {}
      compact_hash(
        mastodon: social_token_value(social_config, env, :mastodon).to_s,
        bluesky: social_token_value(social_config, env, :bluesky).to_s,
        linktree: social_token_value(social_config, env, :linktree).to_s,
        devto: social_token_value(social_config, env, :devto).to_s
      )
    end

    def social_token_value(social_config, env, key)
      preferred_template_token_value(nil, social_config[key.to_s], env, SOCIAL_TOKEN_ENV_KEYS.fetch(key))
    end

    def social_template_tokens(social)
      {
        "KJ|SOCIAL:MASTODON" => social[:mastodon].to_s,
        "KJ|SOCIAL:BLUESKY" => social[:bluesky].to_s,
        "KJ|SOCIAL:LINKTREE" => social[:linktree].to_s,
        "KJ|SOCIAL:DEVTO" => social[:devto].to_s
      }
    end

    def project_runtime_facts(
      config,
      env,
      package_name:,
      source_url:,
      author_domain:,
      min_ruby:,
      test_min_ruby:,
      version:,
      project_root: nil,
      gemspec_metadata: {},
      repository: {}
    )
      run_timestamp = Time.now
      configured_project_emoji = preferred_template_token_value(nil, config["project_emoji"], env, "KJ_PROJECT_EMOJI")
      yard_host = project_yard_host(config, env, package_name: package_name, author_domain: author_domain)
      local_modular_eval_paths = local_modular_runtime_eval_paths(project_root, gemspec_metadata, package_name: package_name)
      direct_sibling_gems = direct_sibling_runtime_gems(
        project_root,
        gemspec_metadata,
        package_name: package_name,
        local_modular_eval_paths: local_modular_eval_paths
      )
      compact_hash(
        freeze_token: config.dig("defaults", "freeze_token").to_s.empty? ? "kettle-jem" : config.dig("defaults", "freeze_token").to_s,
        kettle_jem_version: VERSION,
        template_run_date: run_timestamp.strftime("%Y-%m-%d"),
        template_run_year: run_timestamp.year.to_s,
        kettle_dev_local_gems: kettle_dev_local_gems(config),
        local_gemfile_nomono_bootstrap: local_gemfile_nomono_bootstrap(package_name),
        main_gemfile_kettle_family_gem: main_gemfile_kettle_family_gem(package_name),
        main_gemfile_nomono_bootstrap: main_gemfile_nomono_bootstrap(package_name),
        package_name: package_name.to_s,
        yard_host: yard_host,
        homepage_uri: project_homepage_uri(config, env, yard_host: yard_host, gemspec_homepage_uri: metadata_value(gemspec_metadata, :homepage_uri)),
        project_emoji: preferred_template_token_value("💎", config["project_emoji"], env, "KJ_PROJECT_EMOJI").to_s,
        project_emoji_configured: !configured_project_emoji.to_s.empty?,
        min_divergence_threshold: preferred_template_token_value(nil, config["min_divergence_threshold"], env, "KJ_MIN_DIVERGENCE_THRESHOLD").to_s,
        min_dev_ruby: test_min_ruby.to_s,
        test_min_ruby: test_min_ruby.to_s,
        version: version.to_s,
        github_org: github_org_from_url(source_url).to_s,
        main_gemfile_direct_sibling_block: main_gemfile_direct_sibling_block(
          direct_sibling_gems,
          package_name: package_name,
          source_url: source_url,
          project_root: project_root,
          repository: repository,
          local_modular_eval_paths: local_modular_eval_paths.values.flatten
        )
      )
    end

    def direct_sibling_runtime_gems(project_root, gemspec_metadata, package_name:, local_modular_eval_paths: {})
      return [] unless project_root && gemspec_metadata.is_a?(Hash)

      sibling_root = File.expand_path("..", project_root.to_s)
      excluded = [package_name.to_s, *local_modular_eval_paths.keys.map(&:to_s)]
      pending = gemspec_runtime_dependency_names(gemspec_metadata)
      discovered = []

      until pending.empty?
        name = pending.shift.to_s
        next if name.empty? || discovered.include?(name)

        sibling_path = File.join(sibling_root, name)
        next unless direct_sibling_directory_defines_gem?(sibling_path, name)

        discovered << name
        sibling_metadata = sibling_gemspec_metadata(sibling_path, name)
        pending.concat(gemspec_runtime_dependency_names(sibling_metadata))
      end

      discovered.reject { |name| excluded.include?(name) }
    end

    def sibling_gemspec_metadata(sibling_path, gem_name)
      gemspec_path = Dir.glob(File.join(sibling_path, "*.gemspec")).find do |path|
        metadata_value(static_project_gemspec_metadata(path), :gem_name).to_s == gem_name.to_s
      end
      gemspec_path ? static_project_gemspec_metadata(gemspec_path) : {}
    end

    def local_modular_runtime_eval_paths(project_root, gemspec_metadata, package_name:)
      return {} unless project_root && gemspec_metadata.is_a?(Hash)

      runtime_names = gemspec_runtime_dependency_names(gemspec_metadata) - [package_name.to_s]
      return {} if runtime_names.empty?

      runtime_names.each_with_object({}) do |gem_name, paths_by_gem|
        paths = local_modular_eval_paths_for_gem(project_root, gem_name)
        paths_by_gem[gem_name] = paths if paths.any?
      end
    end

    def local_modular_eval_paths_for_gem(project_root, gem_name)
      Dir.glob(File.join(project_root.to_s, "gemfiles", "modular", "**", "*_local.gemfile")).filter_map do |path|
        next unless gemfile_dependency_names(File.read(path)).include?(gem_name.to_s)

        local_relative = project_relative_path(path, project_root)
        paired_relative = paired_modular_gemfile_path(local_relative)
        next unless paired_relative
        next unless File.file?(File.join(project_root.to_s, paired_relative))

        paired_relative
      rescue Errno::ENOENT
        nil
      end
        .uniq
        .sort
    end

    def paired_modular_gemfile_path(local_relative_path)
      suffix = "_local.gemfile"
      path = local_relative_path.to_s
      return unless path.end_with?(suffix)

      "#{path[0...-suffix.length]}.gemfile"
    end

    def project_relative_path(path, project_root)
      expanded_root = File.expand_path(project_root.to_s)
      expanded_path = File.expand_path(path.to_s)
      prefix = "#{expanded_root}#{File::SEPARATOR}"
      return expanded_path unless expanded_path.start_with?(prefix)

      expanded_path[prefix.length..].to_s
    end

    def direct_sibling_directory_defines_gem?(sibling_path, gem_name)
      return false unless File.directory?(sibling_path)

      Dir.glob(File.join(sibling_path, "*.gemspec")).any? do |gemspec_path|
        metadata_value(static_project_gemspec_metadata(gemspec_path), :gem_name).to_s == gem_name.to_s
      end
    end

    def gemspec_runtime_dependency_names(gemspec_metadata)
      dependencies = Array(
        gemspec_metadata[:runtime_dependencies] || gemspec_metadata["runtime_dependencies"]
      )
      dependencies.each_with_object([]) do |dependency, names|
        name = dependency.respond_to?(:name) ? dependency.name.to_s : dependency.to_s
        next if name.empty? || names.include?(name)

        names << name
      end
    end

    def main_gemfile_direct_sibling_block(gems, package_name:, source_url:, project_root:, repository: {}, local_modular_eval_paths: [])
      names = Array(gems).map(&:to_s).reject(&:empty?).uniq
      eval_paths = Array(local_modular_eval_paths).map(&:to_s).reject(&:empty?).uniq.sort
      return "" if names.empty? && eval_paths.empty?

      blocks = []
      if eval_paths.any?
        blocks << [
          "# Modular sibling dependencies (env-switched inside each modular Gemfile)",
          *eval_paths.map { |path| %(eval_gemfile "#{path}") }
        ].join("\n")
      end
      return blocks.join("\n\n") if names.empty?

      workspace_slug = direct_sibling_workspace_slug(source_url, project_root)
      prefix = workspace_slug.to_s.upcase.tr("-", "_")
      prefix = "LOCAL" if prefix.empty?
      dev_env = "#{prefix}_DEV"
      root_literal = ruby_array_literal(direct_sibling_nomono_root_parts(workspace_slug, repository))
      word_array = names.map { |name| "  #{name}" }.join("\n")
      nomono_loader = %(require "nomono/bundler")

      blocks << <<~RUBY.rstrip
        # Direct sibling dependencies (env-switched via #{dev_env})
        direct_sibling_gems = %w[
        #{word_array}
        ]
        direct_sibling_dev = ENV.fetch("#{dev_env}", "")
        direct_sibling_local =
          !direct_sibling_dev.empty? && !%w[false 0 no off].include?(direct_sibling_dev.downcase)
        direct_sibling_templating = ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?

        if direct_sibling_gems.any? &&
            (direct_sibling_local ||
              ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?)
          direct_sibling_dev_was_set = ENV.key?("#{dev_env}")
          direct_sibling_dev_original = ENV.fetch("#{dev_env}", nil)
          #{nomono_loader}
          begin
            ENV["#{dev_env}"] = File.expand_path("..", __dir__) if direct_sibling_templating && !direct_sibling_local

            eval_nomono_gems(
              gems: direct_sibling_gems,
              prefix: "#{prefix}",
              path_env: "#{dev_env}",
              root: #{root_literal}
            )
          ensure
            if direct_sibling_templating && !direct_sibling_local
              if direct_sibling_dev_was_set
                ENV["#{dev_env}"] = direct_sibling_dev_original
              else
                ENV.delete("#{dev_env}")
              end
            end
          end
        end
      RUBY
      blocks.join("\n\n")
    end

    def direct_sibling_workspace_slug(source_url, project_root)
      slug = github_org_from_url(source_url).to_s
      return slug unless slug.empty?
      return "" unless project_root

      File.basename(File.expand_path("..", project_root.to_s)).to_s
    end

    def direct_sibling_nomono_root_parts(workspace_slug, repository)
      parts = ["src", "my", workspace_slug].reject(&:empty?)
      return parts unless repository_monorepo_subproject?(repository)

      repo_name = repository.is_a?(Hash) ? repository[:name].to_s : ""
      if !repo_name.empty? && repo_name != workspace_slug.to_s
        suffix = repo_name.delete_prefix("#{workspace_slug}-")
        parts.concat(suffix.split("-").reject(&:empty?)) unless suffix.empty? || suffix == repo_name
      end
      package_parent = File.dirname((repository[:package_path] if repository.is_a?(Hash)).to_s)
      parts.concat(package_parent.split("/").reject { |segment| segment.empty? || segment == "." })
      parts
    end

    def project_gemspec_metadata(project_root, gemspec_path, spec: nil)
      metadata = GemSpecReader.load(project_root)
      spec ||= load_project_gemspec(gemspec_path)
      metadata = {} unless metadata.is_a?(Hash)
      metadata = metadata.dup

      if spec
        metadata[:gemspec_path] ||= gemspec_path
        metadata[:gem_name] = spec.name.to_s if metadata_value(metadata, :gem_name).nil?
        metadata[:version] = spec.version.to_s if metadata_value(metadata, :version).nil?
        metadata[:min_ruby] = min_ruby_version(spec.required_ruby_version) if metadata[:min_ruby].nil?
        metadata[:homepage] = spec.homepage.to_s if metadata_value(metadata, :homepage).nil?
        metadata[:homepage_uri] = spec.metadata.fetch("homepage_uri", nil) if metadata_value(metadata, :homepage_uri).nil?
        metadata[:source_code_uri] = spec.metadata.fetch("source_code_uri", nil) if metadata_value(metadata, :source_code_uri).nil?
        metadata[:funding_uri] = spec.metadata.fetch("funding_uri", nil) if metadata_value(metadata, :funding_uri).nil?
        metadata[:authors] = Array(spec.authors).compact.uniq if Array(metadata[:authors]).empty?
        metadata[:email] = Array(spec.email).compact.uniq if Array(metadata[:email]).empty?
        metadata[:summary] = spec.summary.to_s if metadata_value(metadata, :summary).nil?
        metadata[:description] = spec.description.to_s if metadata_value(metadata, :description).nil?
        metadata[:licenses] = Array(spec.licenses) if Array(metadata[:licenses]).empty?
        metadata[:required_ruby_version] = spec.required_ruby_version if metadata[:required_ruby_version].nil?
        metadata[:require_paths] = Array(spec.require_paths) if Array(metadata[:require_paths]).empty?
        metadata[:bindir] = spec.bindir.to_s if metadata_value(metadata, :bindir).nil?
        metadata[:executables] = Array(spec.executables) if Array(metadata[:executables]).empty?
      end

      return {} unless present_template_token_value?(metadata[:gem_name])

      metadata
    rescue LoadError, StandardError
      static_project_gemspec_metadata(gemspec_path)
    end

    def static_project_gemspec_metadata(gemspec_path)
      return {} unless gemspec_path && File.file?(gemspec_path)

      content = File.read(gemspec_path)
      assignments = gemspec_assignment_records(content)
      values = assignments.to_h { |record| [record.fetch(:field).to_sym, record.fetch(:value)] }
      name = values[:name].to_s
      return {} if name.empty?

      metadata = {
        gemspec_path: gemspec_path,
        gem_name: name,
        homepage: values[:homepage].to_s,
        summary: values[:summary].to_s,
        description: values[:description].to_s,
        required_ruby_version: values[:required_ruby_version],
        min_ruby: min_ruby_version(values[:required_ruby_version]),
        licenses: Array(values[:licenses]),
        runtime_dependencies: gemspec_dependency_records(content).select { |dependency| dependency.fetch(:kind) == "add_dependency" }.map { |dependency| gemspec_dependency_from_record(dependency) },
        development_dependencies: gemspec_dependency_records(content).select { |dependency| dependency.fetch(:kind) == "add_development_dependency" }.map { |dependency| gemspec_dependency_from_record(dependency) }
      }
      static_source_code_uri = static_gemspec_metadata_assignment(content, "source_code_uri")
      metadata[:source_code_uri] = static_source_code_uri if static_source_code_uri
      static_homepage_uri = static_gemspec_metadata_assignment(content, "homepage_uri")
      metadata[:homepage_uri] = static_homepage_uri if static_homepage_uri
      metadata
    end

    def gemspec_dependency_from_record(record)
      Gem::Dependency.new(record.fetch(:name), *record.fetch(:requirements), (record.fetch(:kind) == "add_development_dependency") ? :development : :runtime)
    end

    def static_gemspec_metadata_assignment(content, key)
      ruby_call_records(content, :[]=).each do |call|
        next unless call.receiver&.slice.to_s.end_with?(".metadata")

        args = call.arguments&.arguments.to_a
        next unless args.first.respond_to?(:unescaped) && args.first.unescaped == key
        return args[1].unescaped if args[1].respond_to?(:unescaped)
      end
      nil
    rescue Ast::Crispr::Error
      nil
    end

    def static_gemspec_metadata_key_assigned?(content, key)
      ruby_call_records(content, :[]=).any? do |call|
        next false unless call.receiver&.slice.to_s.end_with?(".metadata")

        args = call.arguments&.arguments.to_a
        args.first.respond_to?(:unescaped) && args.first.unescaped == key
      end
    rescue Ast::Crispr::Error
      false
    end

    def generated_version_tree_source_url?(source_url, version)
      return false unless present_template_token_value?(source_url) && present_template_token_value?(version)

      uri = URI.parse(source_url.to_s)
      segments = uri.path.to_s.split("/").reject(&:empty?)
      uri.host == "github.com" && segments[2] == "tree" && segments[3] == "v#{version}"
    rescue URI::InvalidURIError
      false
    end

    def metadata_value(metadata, key)
      value = metadata[key]
      return if value.nil?

      text = value.to_s.strip
      text unless text.empty?
    end

    def load_project_gemspec(gemspec_path)
      Gem::Specification.load(gemspec_path)
    rescue LoadError, StandardError
      nil
    end

    def project_runtime_template_tokens(project_runtime)
      {
        "KJ|FREEZE_TOKEN" => project_runtime[:freeze_token].to_s,
        "KJ|KETTLE_JEM_VERSION" => project_runtime[:kettle_jem_version].to_s,
        "KJ|TEMPLATE_RUN_DATE" => project_runtime[:template_run_date].to_s,
        "KJ|TEMPLATE_RUN_YEAR" => project_runtime[:template_run_year].to_s,
        "KJ|KETTLE_DEV_LOCAL_GEMS" => project_runtime[:kettle_dev_local_gems].to_s,
        "KJ|LOCAL_GEMFILE_NOMONO_BOOTSTRAP" => project_runtime[:local_gemfile_nomono_bootstrap].to_s,
        "KJ|MAIN_GEMFILE_KETTLE_FAMILY_GEM" => project_runtime[:main_gemfile_kettle_family_gem].to_s,
        "KJ|MAIN_GEMFILE_NOMONO_BOOTSTRAP" => project_runtime[:main_gemfile_nomono_bootstrap].to_s,
        "KJ|MAIN_GEMFILE_DIRECT_SIBLING_BLOCK" => project_runtime[:main_gemfile_direct_sibling_block].to_s,
        "KJ|PACKAGE_NAME" => project_runtime[:package_name].to_s,
        "KJ|YARD_HOST" => project_runtime[:yard_host].to_s,
        "KJ|HOMEPAGE_URI" => project_runtime[:homepage_uri].to_s,
        "KJ|PROJECT_EMOJI" => project_runtime[:project_emoji].to_s,
        "KJ|MIN_DIVERGENCE_THRESHOLD" => project_runtime[:min_divergence_threshold].to_s
      }
    end

    def project_yard_host(config, env, package_name:, author_domain:)
      derived = "#{package_name.to_s.tr("_", "-")}.#{author_domain.to_s.empty? ? "example.com" : author_domain}"
      normalize_project_hostname(
        preferred_template_token_value(derived, project_runtime_config_value(config, "yard_host"), env, "KJ_YARD_HOST")
      )
    end

    def kettle_dev_local_gems(config)
      gems = %w[kettle-dev kettle-family kettle-test kettle-soup-cover kettle-changelog]
      plugin_names = PluginLoader.normalize_plugin_names(plugin_names_from_config(config))
      gems.concat(plugin_names.select { |plugin_name| plugin_name.start_with?("kettle-") })
      gems.uniq.join(" ")
    end

    def main_gemfile_kettle_family_gem(package_name)
      return "" if package_name.to_s == "kettle-family"

      %(gem "kettle-family", "~> 1.2", ">= 1.2.77"\n)
    end

    def main_gemfile_nomono_bootstrap(package_name)
      return "" if package_name.to_s == "nomono"

      <<~RUBY.rstrip
        # Local workspace dependency wiring for *_local.gemfile overrides
        #{nomono_gemfile_declaration}
      RUBY
    end

    def nomono_gemfile_declaration
      %(gem "nomono", "~> 1.1", ">= 1.1.5", require: false # ruby >= 3.2.0)
    end

    def local_gemfile_nomono_bootstrap(_package_name)
      <<~RUBY.rstrip
        # Bootstrapping nomono here cannot rely on a plain `gem "nomono", ...` line.
        # Bundler records that dependency during Gemfile evaluation, but it does not
        # activate that exact version before the immediate `require "nomono/bundler"`.
        nomono_activation_requirements = ["~> 1.1", ">= 1.1.5"]
        nomono_requirement = Gem::Requirement.new(nomono_activation_requirements)
        nomono_already_activated = Gem.loaded_specs["nomono"]
        nomono_lockfile = File.expand_path("../../Gemfile.lock", __dir__)
        if !nomono_already_activated || !nomono_requirement.satisfied_by?(nomono_already_activated.version)
          require "bundler"
          if File.file?(nomono_lockfile)
            nomono_locked_spec = Bundler::LockfileParser
              .new(Bundler.read_file(nomono_lockfile))
              .specs
              .find { |spec| spec.name == "nomono" }
            nomono_locked_installed = nomono_locked_spec &&
              Gem::Specification.find_all_by_name("nomono").any? { |spec| spec.version == nomono_locked_spec.version }
            nomono_locked = nomono_locked_spec &&
              nomono_locked_installed &&
              nomono_requirement.satisfied_by?(nomono_locked_spec.version)
            nomono_activation_requirements = ["= \#{nomono_locked_spec.version}"] if nomono_locked
          end
        end
        Kernel.send(:gem, "nomono", *nomono_activation_requirements)
        require "nomono/bundler"
      RUBY
    end

    def project_homepage_uri(config, env, yard_host:, gemspec_homepage_uri: nil)
      derived = if present_template_token_value?(gemspec_homepage_uri)
        gemspec_homepage_uri
      elsif present_template_token_value?(yard_host)
        "https://#{yard_host}"
      end
      normalize_project_homepage_uri(
        preferred_template_token_value(derived, project_runtime_config_value(config, "homepage_uri"), env, "KJ_HOMEPAGE_URI")
      )
    end

    def normalize_project_hostname(value)
      value.to_s.tr("_", "-")
    end

    def normalize_project_homepage_uri(value)
      uri = URI.parse(value.to_s)
      return value.to_s unless uri.host

      uri.host = normalize_project_hostname(uri.host)
      uri.to_s
    rescue URI::InvalidURIError
      value.to_s
    end

    def project_runtime_config_value(config, key)
      token_config = token_config_values(config)
      runtime_config = token_config["project_runtime"].is_a?(Hash) ? token_config["project_runtime"] : {}
      top_level_value = config[key]
      return top_level_value if present_template_token_value?(top_level_value)

      runtime_config[key]
    end

    def version_gem_bootstrap_step(project_root, facts)
      version_gem_bootstrap_step_for_paths(project_root, facts)
    end

    def version_gem_bootstrap_step_for_paths(project_root, facts, manage_version_file: true, manage_signature_file: true,
      package_entrypoint_preexisting: true, preserve_version_module_include: nil, namespace_kinds_override: {})
      package_name = facts.dig(:package, :name).to_s
      return {name: "version_gem_bootstrap", status: "unavailable", reason: "missing_package_facts"} if package_name.empty?

      entrypoint_require = facts.dig(:rubygems, :entrypoint_require).to_s
      entrypoint_require = package_name.tr("-", "/") if entrypoint_require.empty?
      namespace = facts.dig(:rubygems, :namespace).to_s
      version_path = File.join("lib", entrypoint_require, "version.rb")
      entrypoint_path = version_gem_bootstrap_entrypoint_path(
        project_root,
        package_name,
        entrypoint_require,
        package_entrypoint_preexisting: package_entrypoint_preexisting
      )
      default_entrypoint_path = File.join("lib", "#{entrypoint_require}.rb")
      default_entrypoint = read_project_file(project_root, default_entrypoint_path)
      version_spec_path = File.join("spec", entrypoint_require, "version_spec.rb")
      signature_path = File.join("sig", "#{entrypoint_require}.rbs")
      legacy_signature_paths = legacy_rbs_signature_paths(project_root, entrypoint_require)
      if namespace.empty?
        namespace = existing_entrypoint_version_namespace(
          project_root,
          entrypoint_path,
          expected_depth: classify_namespace(package_name).split("::").count { |segment| !segment.empty? }
        ).to_s
      end
      namespace = existing_version_namespace(project_root, version_path).to_s if namespace.empty?
      namespace = classify_namespace(package_name) if namespace.empty?
      return {name: "version_gem_bootstrap", status: "unavailable", reason: "missing_package_facts"} if namespace.empty?

      namespace_superclass_details = existing_namespace_superclass_details(
        project_root,
        namespace,
        preferred_path: entrypoint_path
      )
      entrypoint_namespace_superclasses = version_namespace_superclasses_from_facts(facts).merge(
        namespace_superclass_details.fetch(:superclasses)
      ).merge(
        entrypoint_namespace_superclasses_from_facts(facts)
      )
      fact_superclass_path = facts.dig(:rubygems, :entrypoint_namespace_superclass_path).to_s
      if entrypoint_namespace_superclasses.any? && File.file?(File.join(project_root, fact_superclass_path))
        entrypoint_path = fact_superclass_path
      elsif namespace_superclass_details[:path]
        entrypoint_path = namespace_superclass_details[:path]
      end
      default_entrypoint_loads_version = entrypoint_path != default_entrypoint_path &&
        entrypoint_loads_version_file?(
          default_entrypoint,
          project_root: project_root,
          entrypoint_path: default_entrypoint_path,
          version_path: version_path
        )
      version = facts.dig(:project_runtime, :version).to_s
      version = project_gemspec_version(project_root) if version.empty?
      version = "0.0.1.pre" if version.empty?
      changes = []
      current_entrypoint = read_project_file(project_root, entrypoint_path)
      discovered_namespace_kinds = existing_version_namespace_kinds(
        project_root,
        version_path,
        namespace,
        entrypoint_path: entrypoint_path
      )
      namespace_kinds = version_namespace_kinds_from_facts(facts).merge(discovered_namespace_kinds)
      namespace_kinds = namespace_kinds.merge(namespace_kinds_override)
      outer_namespace_kind = namespace_kinds.fetch(
        namespace.split("::").length - 1,
        ruby_entrypoint_outer_namespace_kind(current_entrypoint, namespace)
      )
      preserve_version_module_include = existing_version_file_includes_version_module?(project_root, version_path) if preserve_version_module_include.nil?

      if manage_version_file
        changes << write_if_changed(
          project_root,
          version_path,
          version_gem_version_file_content(
            existing_version: existing_version_file_value(project_root, version_path),
            namespace: namespace,
            version: version,
            outer_namespace_kind: outer_namespace_kind,
            namespace_kinds: namespace_kinds,
            preserve_version_module_include: preserve_version_module_include
          )
        )
      end
      non_default_version_gem = facts.dig(:version_gem, :non_default_entrypoint) ||
        non_default_version_gem_entrypoint?(project_root, entrypoint_require)
      entrypoint_content = if non_default_version_gem
        version_gem_free_entrypoint_content(
          current_entrypoint,
          entrypoint_require: entrypoint_require,
          ensure_version_require: !default_entrypoint_loads_version,
          after_declarations: !entrypoint_namespace_superclasses.empty?,
          version_require_path: version_require_path_for_entrypoint(entrypoint_path, version_path)
        )
      elsif current_entrypoint.empty?
        version_gem_entrypoint_file_content(namespace: namespace, entrypoint_require: entrypoint_require)
      else
        version_gem_bootstrap_entrypoint_content(
          current_entrypoint,
          namespace: namespace,
          entrypoint_require: entrypoint_require,
          namespace_superclasses: entrypoint_namespace_superclasses,
          version_require_path: version_require_path_for_entrypoint(entrypoint_path, version_path)
        )
      end
      changes << write_if_changed(project_root, entrypoint_path, entrypoint_content)
      if entrypoint_path != default_entrypoint_path
        unless default_entrypoint.empty?
          cleaned_default_entrypoint = remove_version_gem_entrypoint_references(default_entrypoint)
          changes << write_if_changed(project_root, default_entrypoint_path, cleaned_default_entrypoint)
        end
      end
      if non_default_version_gem
        changes << write_if_changed(
          project_root,
          File.join("lib", entrypoint_require, "version_gem.rb"),
          version_gem_entrypoint_file_content(namespace: namespace, entrypoint_require: entrypoint_require, dedicated: true)
        )
      end
      changes << normalize_version_gem_version_spec(
        project_root,
        version_spec_path,
        entrypoint_require,
        namespace,
        package_name: package_name,
        ensure_version_gem_require: non_default_version_gem,
        ensure_package_entrypoint_require: !non_default_version_gem
      )
      if manage_signature_file || !legacy_signature_paths.empty?
        changes.concat(
          write_consolidated_version_signature(
            project_root,
            signature_path,
            legacy_signature_paths,
            namespace: namespace,
            outer_namespace_kind: outer_namespace_kind,
            namespace_kinds: namespace_kinds
          )
        )
      end
      changed_files = changes.compact

      {
        name: "version_gem_bootstrap",
        status: changed_files.empty? ? "already_current" : "applied",
        changed_files: changed_files,
        version_path: version_path,
        entrypoint_path: entrypoint_path,
        signature_path: signature_path
      }
    end

    def version_gem_bootstrap_entrypoint_path(project_root, package_name, entrypoint_require,
      package_entrypoint_preexisting: true)
      default_path = File.join("lib", "#{entrypoint_require}.rb")
      package_path = File.join("lib", "#{package_name}.rb")
      return package_path if package_entrypoint_preexisting && package_path != default_path &&
        File.file?(File.join(project_root, package_path))

      default_path
    end

    def version_require_path_for_entrypoint(entrypoint_path, version_path)
      Pathname(version_path).relative_path_from(Pathname(File.dirname(entrypoint_path))).to_s.delete_suffix(".rb")
    end

    def entrypoint_loads_version_file?(content, project_root:, entrypoint_path:, version_path:)
      return false if content.to_s.empty?

      version_absolute_path = File.expand_path(File.join(project_root, version_path))
      version_require_path = version_path.delete_prefix("lib/").delete_suffix(".rb")
      top_level_ruby_call_records(content, :require).concat(
        top_level_ruby_call_records(content, :require_relative)
      ).any? do |call|
        argument = ruby_string_argument(call)
        next false if argument.to_s.empty?

        if call.name == :require_relative
          File.expand_path(File.join(project_root, File.dirname(entrypoint_path), "#{argument}.rb")) == version_absolute_path
        else
          argument == version_require_path
        end
      end
    end

    def non_default_version_gem_entrypoint?(project_root, entrypoint_require)
      version_gem_path = File.join("lib", entrypoint_require.to_s, "version_gem.rb")
      File.file?(File.join(project_root, version_gem_path))
    end

    def version_gem_facts_for_project(project_root, entrypoint_require, mode: "")
      version_gem_path = File.join("lib", entrypoint_require.to_s, "version_gem.rb")
      normalized_mode = normalize_version_gem_entrypoint_mode(mode)
      return {enabled: false, mode: "disabled"} if normalized_mode == "disabled"

      dedicated = normalized_mode == "dedicated" || File.file?(File.join(project_root, version_gem_path))
      return {enabled: true, mode: "inline"} if normalized_mode == "inline"
      return {} unless dedicated

      {enabled: true, mode: "dedicated", non_default_entrypoint: true, entrypoint_path: version_gem_path}
    end

    def version_gem_default_enabled_for_project?(rubygems_config, gemspec_metadata)
      configured_floor = rubygems_config.fetch("min_ruby", "").to_s.strip
      gemspec_floor = metadata_value(gemspec_metadata, :required_ruby_version).to_s.strip
      floor = minimum_ruby_token(configured_floor.empty? ? gemspec_floor : configured_floor)
      return false if floor.empty?

      Gem::Version.new(floor) >= Gem::Version.new("2.2")
    rescue ArgumentError
      false
    end

    def rubygems_version_gem_entrypoint_mode(rubygems_config)
      raw = rubygems_config["version_gem_entrypoint"]
      nested = rubygems_config["version_gem"]
      raw = nested["entrypoint"] if raw.to_s.strip.empty? && nested.is_a?(Hash)
      normalize_version_gem_entrypoint_mode(raw)
    end

    def normalize_version_gem_entrypoint_mode(value)
      mode = value.to_s.strip.downcase.tr("_", "-")
      return "" if mode.empty? || mode == "auto"
      return "dedicated" if %w[dedicated non-default nondefault separate split].include?(mode)
      return "inline" if %w[inline default].include?(mode)
      return "disabled" if %w[disabled disable false off no none].include?(mode)

      mode
    end

    def project_namespace(entrypoint_namespace:, version_namespace:, metadata_namespace:, default_namespace:)
      if namespace_descendant?(entrypoint_namespace, version_namespace)
        return version_namespace
      end

      if namespace_descendant?(version_namespace, default_namespace) || namespace_descendant?(entrypoint_namespace, default_namespace)
        return default_namespace
      end

      [entrypoint_namespace, version_namespace, metadata_namespace, default_namespace].find do |candidate|
        !candidate.to_s.empty?
      end
    end

    def namespace_descendant?(namespace, parent)
      namespace = namespace.to_s
      parent = parent.to_s
      return false if namespace.empty? || parent.empty? || namespace == parent

      namespace.start_with?("#{parent}::")
    end

    def normalize_version_gem_version_spec(project_root, version_spec_path, entrypoint_require, namespace, ensure_version_gem_require:, package_name: nil, include_version_gem_path: true, ensure_package_entrypoint_require: false)
      current = read_project_file(project_root, version_spec_path)
      package_entrypoint_require = if ensure_package_entrypoint_require
        version_spec_package_entrypoint_require(project_root, package_name, entrypoint_require)
      end

      require_path = File.join(entrypoint_require.to_s, "version_gem")
      updated = if current.empty?
        version_gem_version_spec_content(namespace: namespace)
      else
        current
      end

      requirements = []
      requirements << %(require "anonymous_loader"\n) unless ruby_top_level_require?(updated, "require", "anonymous_loader")
      if ensure_version_gem_require && !ruby_top_level_require?(updated, "require", require_path)
        requirements << %(require "#{require_path}"\n)
      end
      if ensure_package_entrypoint_require && !entrypoint_require.to_s.empty? &&
          !package_name.to_s.empty? && package_name.to_s != entrypoint_require.to_s
        updated = remove_top_level_ruby_require(updated, package_name.to_s)
      end
      if ensure_package_entrypoint_require && package_entrypoint_require.to_s != entrypoint_require.to_s
        updated = remove_top_level_ruby_require(updated, entrypoint_require.to_s)
      end
      if ensure_package_entrypoint_require && !entrypoint_require.to_s.empty? &&
          !ruby_top_level_require?(updated, "require", package_entrypoint_require.to_s)
        requirements << %(require "#{package_entrypoint_require}"\n)
      end

      if requirements.any?
        lines = updated.lines
        lines.insert(version_spec_require_insertion_index(updated), *requirements)
        updated = lines.join
      end
      updated = remove_version_gem_shared_example(updated) unless include_version_gem_path
      updated = normalize_version_spec_anonymous_loader_example(
        updated,
        version_spec_path: version_spec_path,
        entrypoint_require: entrypoint_require,
        namespace: namespace,
        include_version_gem_path: include_version_gem_path
      )
      write_if_changed(project_root, version_spec_path, collapse_excess_blank_lines(updated))
    end

    def version_spec_package_entrypoint_require(project_root, package_name, entrypoint_require)
      package_name = package_name.to_s.strip
      entrypoint_require = entrypoint_require.to_s.strip
      return entrypoint_require if package_name.empty? || package_name == entrypoint_require

      package_path = File.join("lib", "#{package_name}.rb")
      version_path = File.join("lib", "#{entrypoint_require}.rb")
      return entrypoint_require unless File.file?(File.join(project_root, package_path))

      package_content = read_project_file(project_root, package_path)
      entrypoint_loads_version_file?(
        package_content,
        project_root: project_root,
        entrypoint_path: package_path,
        version_path: version_path
      ) ? package_name : entrypoint_require
    end

    def remove_version_gem_shared_example(content)
      content.to_s.lines.reject do |line|
        line.include?('it_behaves_like "a Version module"')
      end.join
    end

    def version_gem_version_spec_content(namespace:)
      clean_namespace = namespace.to_s.start_with?("::") ? namespace.to_s[2..] : namespace.to_s
      <<~RUBY
        # frozen_string_literal: true

        RSpec.describe #{clean_namespace}::Version do
          it_behaves_like "a Version module", described_class
        end
      RUBY
    end

    def cleanup_version_gem_version_spec(project_root, version_spec_path)
      current = read_project_file(project_root, version_spec_path)
      return if current.empty? || !managed_version_gem_version_spec?(current)

      delete_project_file(project_root, version_spec_path)
    end

    def cleanup_version_gem_entrypoint(project_root, entrypoint_path)
      current = read_project_file(project_root, entrypoint_path)
      return if current.empty?
      return unless current.include?('require "version_gem"') && current.include?("VersionGem::Basic")

      delete_project_file(project_root, entrypoint_path)
    end

    def managed_version_gem_version_spec?(content)
      content.to_s.include?('it_behaves_like "a Version module"') ||
        version_spec_anonymous_loader_call?(content)
    end

    def normalize_version_spec_anonymous_loader_example(content, version_spec_path:, entrypoint_require:, namespace:, include_version_gem_path: true)
      version_path = version_spec_relative_version_path(version_spec_path, entrypoint_require)
      version_gem_path = version_spec_relative_version_gem_path(version_spec_path, entrypoint_require)
      path_loader = if include_version_gem_path
        <<~RUBY.chomp
          paths = [
            File.expand_path("#{version_path}", __dir__),
            File.expand_path("#{version_gem_path}", __dir__)
          ].select { |path| File.file?(path) }
          anonymous_namespace = AnonymousLoader.load(files: paths)
        RUBY
      else
        <<~RUBY.chomp
          path = File.expand_path("#{version_path}", __dir__)
          anonymous_namespace = AnonymousLoader.load(files: path)
        RUBY
      end
      legacy_path_loader = <<~RUBY.chomp
        path = File.expand_path("#{version_path}", __dir__)
        anonymous_namespace = AnonymousLoader.load(files: path)
      RUBY
      indented_path_loader = path_loader.lines.map { |line| "    #{line}" }.join
      indented_legacy_path_loader = legacy_path_loader.lines.map { |line| "    #{line}" }.join
      return content.sub(indented_legacy_path_loader, indented_path_loader) if content.include?(indented_legacy_path_loader)

      return content.sub(legacy_path_loader, path_loader) if content.include?(legacy_path_loader)

      return content if version_spec_anonymous_loader_call?(content)

      describe_call = version_spec_rspec_describe_call(content)
      return content unless describe_call&.block

      clean_namespace = namespace.to_s.start_with?("::") ? namespace.to_s[2..] : namespace.to_s
      example = <<~RUBY

          it "executes the version file for coverage without redefining constants" do
        #{indented_path_loader}

            expect(anonymous_namespace::#{clean_namespace}::Version::VERSION).to eq(described_class::VERSION)
          end
      RUBY

      insert_lines_before(content, describe_call.block.closing_loc.start_line, example)
    end

    def version_spec_anonymous_loader_call?(content)
      ruby_call_records(content, :load).any? { |call| call.receiver&.slice == "AnonymousLoader" }
    end

    def version_spec_rspec_describe_call(content)
      top_level_ruby_call_records(content, :describe).find do |call|
        call.receiver&.slice == "RSpec" && call.block
      end
    end

    def version_spec_relative_version_path(version_spec_path, entrypoint_require)
      spec_depth = File.dirname(version_spec_path.to_s).split(File::SEPARATOR).count { |part| !part.empty? }
      "#{"../" * spec_depth}lib/#{entrypoint_require}/version.rb"
    end

    def version_spec_relative_version_gem_path(version_spec_path, entrypoint_require)
      spec_depth = File.dirname(version_spec_path.to_s).split(File::SEPARATOR).count { |part| !part.empty? }
      "#{"../" * spec_depth}lib/#{entrypoint_require}/version_gem.rb"
    end

    def legacy_rbs_signature_paths(project_root, entrypoint_require)
      legacy_root = File.join(project_root, "sig", entrypoint_require.to_s)
      return [] unless Dir.exist?(legacy_root)

      Dir.glob(File.join(legacy_root, "**", "*.rbs")).sort.map do |path|
        path.delete_prefix("#{project_root}/")
      end
    end

    def write_consolidated_version_signature(project_root, signature_path, legacy_signature_paths, namespace:,
      outer_namespace_kind: :module, namespace_kinds: {})
      template = version_gem_signature_file_content(
        namespace: namespace,
        outer_namespace_kind: outer_namespace_kind,
        namespace_kinds: namespace_kinds
      )
      current = read_project_file(project_root, signature_path)
      merged = current
      legacy_signature_paths.each do |legacy_signature_path|
        legacy = read_project_file(project_root, legacy_signature_path)
        merged = merge_rbs_signature_sources(legacy, merged) unless legacy.empty?
      end
      merged = merge_rbs_signature_sources(template, merged)

      [
        write_if_changed(project_root, signature_path, merged),
        legacy_signature_paths.map { |legacy_signature_path| delete_project_file(project_root, legacy_signature_path) }
      ].flatten.compact
    end

    def merge_rbs_signature_sources(template_content, destination_content)
      return ensure_trailing_newline(template_content) if destination_content.to_s.strip.empty?

      result = merge_rbs_template_source(
        ensure_trailing_newline(template_content),
        ensure_trailing_newline(destination_content),
        {template_preference: {preference: "destination"}}
      )
      result.fetch(:ok) ? result.fetch(:output) : ensure_trailing_newline(destination_content)
    end

    def delete_project_file(project_root, relative_path)
      path = File.join(project_root, relative_path)
      return unless File.file?(path)

      File.delete(path)
      prune_empty_parent_directories(project_root, File.dirname(relative_path))
      relative_path
    end

    def prune_empty_parent_directories(project_root, relative_path)
      current = relative_path.to_s
      while !current.empty? && current != "."
        path = File.join(project_root, current)
        begin
          Dir.rmdir(path)
        rescue SystemCallError
          break
        end
        current = File.dirname(current)
      end
    end

    def version_spec_require_insertion_index(content)
      ensure_runtime_dependencies!
      context = Ast::Crispr::Ruby::Prism.document_context(content: content.to_s, source_label: "version_spec.rb")
      owners = context.structural_owners(owner_scope: :top_level_statements)
      requires = owners.select { |owner| owner.is_a?(::Prism::CallNode) && owner.name == :require }
      return requires.last.location.end_line if requires.any?

      version_gem_require_insertion_index(content)
    end

    def version_gem_version_file_content(existing_version:, namespace:, version:, outer_namespace_kind: :module, namespace_kinds: {}, preserve_version_module_include: false)
      resolved_version = existing_version.to_s.empty? ? version.to_s : existing_version.to_s
      body = [
        "# Version namespace for this gem.",
        "module Version",
        "  # Current gem version.",
        "  VERSION = #{resolved_version.dump}",
        "end",
        "# Current gem version exposed at the traditional constant location.",
        "VERSION = Version::VERSION # Traditional Constant Location"
      ]
      body << "include Version" if preserve_version_module_include

      <<~RUBY
        # frozen_string_literal: true

        #{wrap_ruby_namespace(namespace, body, outer_namespace_kind: outer_namespace_kind, namespace_kinds: namespace_kinds).join("\n")}
      RUBY
    end

    def version_gem_entrypoint_file_content(namespace:, entrypoint_require:, dedicated: false)
      sections = ["# frozen_string_literal: true"]
      requires = []
      requires << 'require "version_gem"' unless File.basename(entrypoint_require) == "version_gem"
      version_require = dedicated ? "version" : File.join(File.basename(entrypoint_require), "version")
      requires << %(require_relative "#{version_require}")
      sections << requires.join("\n")
      sections << wrap_ruby_namespace(namespace, []).join("\n") unless dedicated
      sections << version_gem_class_eval_block(namespace).chomp
      "#{sections.reject(&:empty?).join("\n\n")}\n"
    end

    def version_gem_signature_file_content(namespace:, outer_namespace_kind: :module, namespace_kinds: {})
      body = [
        "module Version",
        "  VERSION: String",
        "end",
        "VERSION: String"
      ]

      "#{wrap_ruby_namespace(namespace, body, outer_namespace_kind: outer_namespace_kind, namespace_kinds: namespace_kinds).join("\n")}\n"
    end

    def version_gem_bootstrap_entrypoint_content(content, namespace:, entrypoint_require:, namespace_superclasses: {}, version_require_path: nil)
      current = if namespace_superclasses.empty?
        # Preserve the existing relative-require position when there is no
        # declaration ordering constraint.
        normalize_entrypoint_version_require(
          content,
          entrypoint_require: entrypoint_require,
          version_require_path: version_require_path
        )
      else
        # A namesake superclass is a declaration-order constraint: establish
        # the class, load version.rb, then extend its Version module.
        source = remove_version_gem_class_eval_references(content)
        source = ensure_entrypoint_namespace_superclass_declarations(
          source,
          namespace: namespace,
          namespace_superclasses: namespace_superclasses
        )
        normalize_entrypoint_version_require(
          source,
          entrypoint_require: entrypoint_require,
          version_require_path: version_require_path,
          after_declarations: true
        )
      end
      current = remove_version_gem_class_eval_references(current)
      lines = current.lines
      insert_lines = []
      if File.basename(entrypoint_require) != "version_gem" && !ruby_top_level_require?(current, "require", "version_gem")
        insert_lines << "require \"version_gem\"\n"
      end
      if insert_lines.any?
        relative_path = version_require_path.to_s.empty? ? File.join(File.basename(entrypoint_require), "version") : version_require_path.to_s
        lines.insert(version_gem_require_insertion_index(current, before_relative_path: relative_path), *insert_lines)
      end

      updated = lines.join
      unless ruby_version_class_eval_namespaces(updated).include?(namespace.to_s)
        updated += "\n" unless updated.end_with?("\n")
        updated += "\n#{version_gem_class_eval_block(namespace)}"
      end
      collapse_excess_blank_lines(updated)
    end

    def ensure_entrypoint_namespace_superclass_declarations(content, namespace:, namespace_superclasses: {})
      # A version file must only reopen a namesake class.  When legacy source
      # declared that class and its superclass in version.rb, establish the
      # class in the entrypoint before requiring version.rb, then render the
      # version file without a superclass.
      segments = namespace.to_s.split("::").reject(&:empty?)
      return content.to_s if segments.empty? || namespace_superclasses.empty?

      missing_superclass_declaration = namespace_superclasses.any? do |index, _superclass|
        ruby_namespace_declaration_node(content, segments.first(index + 1).join("::")).nil?
      end
      return content.to_s unless missing_superclass_declaration

      namespace_kinds = segments.each_index.each_with_object({}) do |index, kinds|
        prefix = segments.first(index + 1).join("::")
        kinds[index] = ruby_namespace_declaration_kind(content, prefix) || :module
        kinds[index] = :class if namespace_superclasses.key?(index)
      end
      declaration = wrap_ruby_namespace(
        namespace,
        [],
        namespace_kinds: namespace_kinds,
        namespace_superclasses: namespace_superclasses
      ).join("\n")
      current = trim_trailing_blank_lines(content)
      current.empty? ? "#{declaration}\n" : "#{current}\n\n#{declaration}\n"
    end

    def version_gem_free_entrypoint_content(content, entrypoint_require:, ensure_version_require: true, after_declarations: false, version_require_path: nil)
      current = remove_version_gem_entrypoint_references(content)
      unless ensure_version_require
        relative_path = version_require_path.to_s.empty? ? File.join(File.basename(entrypoint_require), "version") : version_require_path.to_s
        absolute_path = File.join(entrypoint_require, "version")
        legacy_relative_path = File.join(File.basename(entrypoint_require), "version")
        current = [relative_path, legacy_relative_path].uniq.reduce(current) do |value, path|
          remove_entrypoint_version_requires(value, relative_path: path, absolute_path: absolute_path)
        end
        return trim_trailing_blank_lines(collapse_excess_blank_lines(current))
      end

      normalize_entrypoint_version_require(
        current,
        entrypoint_require: entrypoint_require,
        version_require_path: version_require_path,
        after_declarations: after_declarations
      )
    end

    def normalize_entrypoint_version_require(content, entrypoint_require:, version_require_path: nil, after_declarations: false)
      relative_path = version_require_path.to_s.empty? ? File.join(File.basename(entrypoint_require), "version") : version_require_path.to_s
      absolute_path = File.join(entrypoint_require, "version")
      legacy_relative_path = File.join(File.basename(entrypoint_require), "version")
      current = [relative_path, legacy_relative_path].uniq.reduce(content) do |value, path|
        remove_entrypoint_version_requires(value, relative_path: path, absolute_path: absolute_path)
      end
      if after_declarations
        current = trim_trailing_blank_lines(collapse_excess_blank_lines(current))
        return "#{current}\n\nrequire_relative \"#{relative_path}\"\n" unless current.empty?
      end

      lines = current.lines
      lines.insert(version_gem_require_insertion_index(current), %(require_relative "#{relative_path}"\n), "\n")
      trim_trailing_blank_lines(collapse_excess_blank_lines(lines.join))
    end

    def remove_entrypoint_version_requires(content, relative_path:, absolute_path:)
      selectors = [
        *top_level_ruby_call_records(content, :require),
        *top_level_ruby_call_records(content, :require_relative)
      ].filter_map do |call|
        argument = ruby_string_argument(call)
        matches_relative = call.name == :require_relative && argument == relative_path
        matches_absolute = call.name == :require && argument == absolute_path
        next unless matches_relative || matches_absolute

        {start_line: call.location.start_line, end_line: ruby_node_source_end_line(call)}
      end
      return content.to_s if selectors.empty?

      collapse_excess_blank_lines(delete_line_ranges(content.to_s, selectors))
    end

    def remove_top_level_ruby_require(content, argument)
      selectors = top_level_ruby_call_records(content, :require).filter_map do |call|
        next unless ruby_string_argument(call) == argument.to_s

        {start_line: call.location.start_line, end_line: ruby_node_source_end_line(call)}
      end
      return content.to_s if selectors.empty?

      collapse_excess_blank_lines(delete_line_ranges(content.to_s, selectors))
    end

    def remove_version_gem_entrypoint_references(content)
      selectors = []
      top_level_ruby_call_records(content, :require).each do |call|
        next unless ruby_string_argument(call) == "version_gem"

        selectors << {start_line: call.location.start_line, end_line: ruby_node_source_end_line(call)}
      end
      selectors.concat(version_gem_class_eval_selectors(content))
      return content.to_s if selectors.empty?

      collapse_excess_blank_lines(delete_line_ranges(content.to_s, selectors))
    end

    def remove_version_gem_class_eval_references(content)
      selectors = version_gem_class_eval_selectors(content)
      return content.to_s if selectors.empty?

      collapse_excess_blank_lines(delete_line_ranges(content.to_s, selectors))
    end

    def version_gem_class_eval_selectors(content)
      top_level_ruby_call_records(content, :class_eval).filter_map do |call|
        next unless version_gem_class_eval_call?(call)

        {start_line: call.location.start_line, end_line: ruby_node_source_end_line(call)}
      end
    end

    def version_gem_class_eval_call?(call)
      call.receiver && call.block&.body&.body.to_a.any? do |child|
        child.is_a?(::Prism::CallNode) &&
          child.receiver.nil? &&
          child.name == :extend &&
          child.arguments&.arguments&.first&.slice == "VersionGem::Basic"
      end
    end

    def version_gem_require_insertion_index(content, before_relative_path: nil)
      ensure_runtime_dependencies!
      context = Ast::Crispr::Ruby::Prism.document_context(content: content.to_s, source_label: "entrypoint.rb")
      owners = context.structural_owners(owner_scope: :top_level_statements)
      if before_relative_path
        owner = owners.find { |candidate| ruby_require_call?(candidate, "require_relative", before_relative_path) }
        return owner.location.start_line - 1 if owner
      end

      initial_requires = owners.take_while do |candidate|
        candidate.is_a?(::Prism::CallNode) && %i[require require_relative].include?(candidate.name)
      end
      return initial_requires.last.location.end_line if initial_requires.any?

      first_owner = owners.first
      first_owner ? first_owner.location.start_line - 1 : ruby_parse_comments(context.ast).map { |comment| comment.location.end_line }.max.to_i
    end

    def ruby_parse_comments(analysis)
      return analysis.comments if analysis.respond_to?(:comments)
      return analysis.parse_result.comments if analysis.respond_to?(:parse_result) && analysis.parse_result.respond_to?(:comments)

      []
    end

    def ruby_top_level_require?(content, method_name, argument)
      ensure_runtime_dependencies!
      context = Ast::Crispr::Ruby::Prism.document_context(content: content.to_s, source_label: "entrypoint.rb")
      context.structural_owners(owner_scope: :top_level_statements).any? do |owner|
        ruby_require_call?(owner, method_name, argument)
      end
    end

    def ruby_require_call?(owner, method_name, argument)
      owner.is_a?(::Prism::CallNode) &&
        owner.name.to_s == method_name.to_s &&
        ruby_first_string_argument(owner).to_s == argument.to_s
    end

    def ruby_first_string_argument(owner)
      argument = owner.arguments&.arguments&.first
      argument.respond_to?(:unescaped) ? argument.unescaped : nil
    end

    def collapse_excess_blank_lines(content)
      blank_count = 0
      content.to_s.lines.filter_map do |line|
        if line.strip.empty?
          blank_count += 1
          next if blank_count > 1
        else
          blank_count = 0
        end
        line
      end.join
    end

    def trim_trailing_blank_lines(content)
      lines = content.to_s.lines
      lines.pop while lines.last&.strip == ""
      ensure_trailing_newline(lines.join)
    end

    def version_gem_class_eval_block(namespace)
      <<~RUBY
        #{namespace}::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
    end

    def wrap_ruby_namespace(namespace, body_lines, outer_namespace_kind: :module, namespace_kinds: {}, namespace_superclasses: {})
      segments = namespace.to_s.split("::").reject(&:empty?)
      return body_lines if segments.empty?

      lines = []
      segments.each_with_index do |segment, index|
        kind = namespace_kinds.fetch(index, index.zero? ? outer_namespace_kind : :module)
        keyword = (kind == :class) ? "class" : "module"
        superclass = namespace_superclasses[index].to_s
        declaration = "#{keyword} #{segment}"
        declaration += " < #{superclass}" if keyword == "class" && !superclass.empty?
        lines << ("  " * index) + declaration
      end
      body_lines.each { |line| lines << ("  " * segments.length) + line unless line.empty? }
      (segments.length - 1).downto(0) { |index| lines << ("  " * index) + "end" }
      lines
    end

    def version_namespace_outer_kind(project_root, entrypoint_path, namespace)
      ruby_entrypoint_outer_namespace_kind(read_project_file(project_root, entrypoint_path), namespace)
    end

    def version_namespace_outer_kind_for_template(project_root, facts, entrypoint_path, version_path, namespace)
      kind = version_namespace_outer_kind(project_root, entrypoint_path, namespace)
      return kind if kind == :class

      entrypoint_kind = ruby_namespace_declaration_kind(read_project_file(project_root, entrypoint_path), namespace)
      return entrypoint_kind if entrypoint_kind == :class

      configured_kinds = version_namespace_kinds_from_facts(facts)
      target_index = namespace.to_s.split("::").count { |element| !element.empty? } - 1
      configured_kind = configured_kinds[target_index]
      return configured_kind if configured_kind

      ruby_namespace_declaration_kind(read_project_file(project_root, version_path), namespace) || kind
    end

    def version_namespace_kinds_from_facts(facts)
      raw = facts.dig(:rubygems, :version_namespace_kinds)
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(index, kind), kinds|
        normalized_kind = kind.to_s.to_sym
        kinds[index.to_i] = normalized_kind if %i[class module].include?(normalized_kind)
      end
    end

    def version_namespace_superclasses_from_facts(facts)
      raw = facts.dig(:rubygems, :version_namespace_superclasses)
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(index, superclass), superclasses|
        value = superclass.to_s.strip
        superclasses[index.to_i] = value unless value.empty?
      end
    end

    def entrypoint_namespace_superclasses_from_facts(facts)
      raw = facts.dig(:rubygems, :entrypoint_namespace_superclasses)
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(index, superclass), superclasses|
        value = superclass.to_s.strip
        superclasses[index.to_i] = value unless value.empty?
      end
    end

    def ruby_entrypoint_outer_namespace_kind(content, namespace)
      first_segment = namespace.to_s.split("::").reject(&:empty?).first
      return :module if first_segment.to_s.empty?

      body = prism_parse_success(content)&.value&.statements&.body || []
      declaration = body.find do |node|
        (node.is_a?(::Prism::ClassNode) || node.is_a?(::Prism::ModuleNode)) &&
          ruby_constant_path_segments(node.constant_path).first == first_segment
      end
      declaration.is_a?(::Prism::ClassNode) ? :class : :module
    end

    def existing_version_file_value(project_root, relative_path)
      ruby_version_constant_value(read_project_file(project_root, relative_path)).to_s
    end

    def git_version_file_value(project_root, relative_path)
      [
        git_output(project_root, "show", ":#{relative_path}"),
        git_output(project_root, "show", "HEAD:#{relative_path}")
      ].each do |content|
        version = ruby_version_constant_value(content)
        return version.to_s if valid_gem_version?(version)
      end

      ""
    end

    def existing_version_namespace(project_root, relative_path)
      ruby_version_module_namespace(read_project_file(project_root, relative_path))
    end

    def reconcile_existing_version_namespace(project_root, entrypoint_path, version_path, namespace)
      namespace = namespace.to_s
      return namespace if namespace.empty?

      entrypoint_kind = ruby_namespace_declaration_kind(
        read_project_file(project_root, entrypoint_path),
        namespace
      )
      version_kind = ruby_namespace_declaration_kind(
        read_project_file(project_root, version_path),
        namespace
      )
      return namespace unless entrypoint_kind && version_kind && entrypoint_kind != version_kind
      return namespace unless error_class_namespace?(read_project_file(project_root, entrypoint_path), namespace)

      parent = namespace.split("::")[0...-1].join("::")
      return namespace if parent.empty?
      return namespace unless ruby_namespace_declaration_kind(
        read_project_file(project_root, entrypoint_path),
        parent
      )

      parent
    end

    def error_class_namespace?(content, namespace)
      return false unless namespace.to_s.split("::").last == "Error"

      node = ruby_namespace_declaration_node(content, namespace)
      return false unless node.is_a?(::Prism::ClassNode)

      superclass = node.superclass&.slice.to_s
      %w[Exception StandardError].include?(superclass)
    end

    def existing_version_file_includes_version_module?(project_root, relative_path)
      version_file_includes_version_module?(read_project_file(project_root, relative_path))
    end

    def version_file_includes_version_module?(content)
      ruby_call_records(content.to_s, :include).any? do |call|
        next false unless call.receiver.nil?

        arguments = call.arguments&.arguments || []
        arguments.length == 1 && arguments.first.slice.to_s == "Version"
      end
    end

    def existing_version_namespace_kinds(project_root, relative_path, namespace, entrypoint_path: nil)
      contents = [read_project_file(project_root, relative_path)]
      contents << read_project_file(project_root, entrypoint_path) if entrypoint_path
      segments = namespace.to_s.split("::").reject(&:empty?)
      return {} if segments.empty?

      contents.each_with_object({}) do |content, kinds|
        segments.each_index do |index|
          prefix = segments.first(index + 1).join("::")
          kind = ruby_namespace_declaration_kind(content, prefix)
          kinds[index] = kind if kind
        end
      end
    end

    def existing_version_namespace_superclasses(project_root, relative_path, namespace, entrypoint_path: nil)
      contents = [read_project_file(project_root, relative_path)]
      contents << read_project_file(project_root, entrypoint_path) if entrypoint_path
      segments = namespace.to_s.split("::").reject(&:empty?)
      return {} if segments.empty?

      contents.each_with_object({}) do |content, superclasses|
        segments.each_index do |index|
          prefix = segments.first(index + 1).join("::")
          node = ruby_namespace_declaration_node(content, prefix)
          next unless node.is_a?(::Prism::ClassNode)

          superclass = node.superclass&.slice.to_s.strip
          superclasses[index] = superclass unless superclass.empty?
        end
      end
    end

    def existing_namespace_superclass_details(project_root, namespace, preferred_path: nil)
      library_paths = [preferred_path, *ruby_library_source_paths(project_root)].compact.uniq
      library_paths.each do |relative_path|
        superclasses = existing_version_namespace_superclasses(project_root, relative_path, namespace)
        next if superclasses.empty?

        return {path: relative_path, superclasses: superclasses}
      end

      {path: nil, superclasses: {}}
    end

    def ruby_library_source_paths(project_root)
      Dir.glob(File.join(project_root, "lib", "**", "*.rb")).sort.filter_map do |path|
        relative_path = Pathname(path).relative_path_from(Pathname(project_root)).to_s
        next if relative_path.end_with?("/version.rb", "/version_gem.rb")

        relative_path
      end
    end

    def ruby_namespace_declaration_kind(content, namespace)
      target = namespace.to_s.split("::").reject(&:empty?)
      body = prism_parse_success(content)&.value&.statements&.body || []
      body.each do |node|
        kind = ruby_namespace_declaration_kind_for(node, [], target)
        return kind if kind
      end
      nil
    end

    def ruby_namespace_declaration_kind_for(node, namespace, target)
      return unless node.is_a?(::Prism::ModuleNode) || node.is_a?(::Prism::ClassNode)

      current = namespace + ruby_constant_path_segments(node.constant_path)
      return (node.is_a?(::Prism::ClassNode) ? :class : :module) if current == target

      node.body&.body&.each do |child|
        kind = ruby_namespace_declaration_kind_for(child, current, target)
        return kind if kind
      end
      nil
    end

    def ruby_namespace_declaration_node(content, namespace)
      target = namespace.to_s.split("::").reject(&:empty?)
      body = prism_parse_success(content)&.value&.statements&.body || []
      body.each do |node|
        found = ruby_namespace_declaration_node_for(node, [], target)
        return found if found
      end
      nil
    end

    def ruby_namespace_declaration_node_for(node, namespace, target)
      return unless node.is_a?(::Prism::ModuleNode) || node.is_a?(::Prism::ClassNode)

      current = namespace + ruby_constant_path_segments(node.constant_path)
      return node if current == target

      node.body&.body&.each do |child|
        found = ruby_namespace_declaration_node_for(child, current, target)
        return found if found
      end
      nil
    end

    def ruby_version_constant_value(content)
      result = prism_parse_success(content)
      return unless result

      node = result.value.breadth_first_search_all do |candidate|
        candidate.is_a?(::Prism::ConstantWriteNode) &&
          candidate.name == :VERSION &&
          candidate.value.is_a?(::Prism::StringNode)
      end.first
      node&.value&.unescaped
    end

    def ruby_version_module_namespace(content)
      body = prism_parse_success(content)&.value&.statements&.body || []
      body.each do |node|
        namespace = ruby_version_module_namespace_for(node, [])
        return namespace if namespace
      end
      nil
    end

    def ruby_version_module_namespace_for(node, namespace)
      return unless node.is_a?(::Prism::ModuleNode) || node.is_a?(::Prism::ClassNode)

      current = namespace + ruby_constant_path_segments(node.constant_path)
      if current.last == "Version" && current.length > 1
        return current[0...-1].join("::")
      end

      if node.body&.body&.any? { |child| child.is_a?(::Prism::ConstantWriteNode) && child.name == :VERSION }
        return current.join("::")
      end

      node.body&.body&.each do |child|
        child_namespace = ruby_version_module_namespace_for(child, current)
        return child_namespace if child_namespace
      end
      nil
    end

    def ruby_constant_path_segments(node)
      node&.slice.to_s.split("::").reject(&:empty?)
    end

    def existing_entrypoint_version_namespace(project_root, relative_path, expected_depth: nil)
      content = read_project_file(project_root, relative_path)
      if expected_depth
        return ruby_entrypoint_module_namespace(content, expected_depth: expected_depth) ||
            ruby_version_class_eval_namespaces(content).first
      end

      ruby_version_class_eval_namespaces(content).first || ruby_entrypoint_module_namespace(content)
    end

    def ruby_version_class_eval_namespaces(content)
      ruby_call_records(content, :class_eval).filter_map do |call|
        receiver = call.receiver&.slice.to_s
        next unless receiver.end_with?("::Version")
        next unless call.block

        receiver.delete_suffix("::Version")
      end
    end

    def ruby_entrypoint_module_namespace(content, expected_depth: nil)
      body = prism_parse_success(content)&.value&.statements&.body || []
      body.each do |node|
        namespace = ruby_entrypoint_module_namespace_for(node, [], expected_depth: expected_depth)
        return namespace if namespace
      end
      nil
    end

    def ruby_entrypoint_module_namespace_for(node, namespace, expected_depth: nil)
      return unless node.is_a?(::Prism::ModuleNode) || node.is_a?(::Prism::ClassNode)

      current = namespace + ruby_constant_path_segments(node.constant_path)
      return current.join("::") if expected_depth && current.length == expected_depth
      return if expected_depth && current.length > expected_depth

      node.body&.body&.each do |child|
        child_namespace = ruby_entrypoint_module_namespace_for(child, current, expected_depth: expected_depth)
        return child_namespace if child_namespace
      end
      current.join("::") unless expected_depth || current.empty?
    end

    def read_project_file(project_root, relative_path)
      path = File.join(project_root, relative_path)
      File.file?(path) ? File.read(path) : ""
    end

    def write_if_changed(project_root, relative_path, content)
      path = File.join(project_root, relative_path)
      current = File.file?(path) ? File.read(path) : ""
      return if current == content

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      relative_path
    end

    def shield_token(value)
      value.to_s.gsub("-", "--").gsub("_", "__").tr(" ", "_")
    end

    def normalize_generated_image_url(url)
      Addressable::URI.parse(url.to_s).normalize.to_s
    end

    def github_org_from_url(url)
      match = url.to_s.match(%r{\Ahttps?://github\.com/([^/]+)/})
      match && match[1]
    end

    def concrete_github_url(url)
      github_org_from_url(url) ? url.to_s : nil
    end

    def repository_name_from_source_url(source_url)
      base = source_url.to_s.split("?", 2).first.to_s.split("#", 2).first.to_s
      base = base[0...-1] while base.end_with?("/")
      name = base.split("/").last.to_s
      name.end_with?(".git") ? name[0...-4] : name
    end

    def repository_facts(project_root, source_url, package_name:, repository_topology:)
      topology = normalize_repository_topology(repository_topology)
      monorepo_subproject = topology == REPOSITORY_TOPOLOGY_MONOREPO_SUBPROJECT
      local_root = monorepo_subproject ? git_worktree_root(project_root) : nil
      repository_root = local_root || project_root
      git_source_url = git_remote_source_url(repository_root)
      repo_url = if monorepo_subproject
        repository_root_url(git_source_url || source_url)
      else
        repository_root_url(source_url)
      end
      repo_name = repository_name_from_source_url(repo_url)
      org = github_org_from_url(repo_url).to_s
      slug = [org, repo_name].reject(&:empty?).join("/")
      facts = compact_hash(
        mode: monorepo_subproject ? "monorepo_subproject" : "standalone",
        topology: topology,
        url: repo_url,
        name: repo_name,
        slug: slug,
        star_history: readme_star_history_facts(repository_root, git_source_url)
      )
      return facts unless monorepo_subproject

      package_path = git_worktree_prefix(project_root)
      package_path = package_path[0...-1] while package_path.end_with?("/")
      return facts.merge(local_root: local_root) if package_path.empty?

      facts.merge(
        local_root: local_root,
        package_path: package_path,
        package_source_url: source_tree_url(repo_url, package_path),
        gitlab_package_source_url: source_tree_url("https://gitlab.com/#{slug}", package_path),
        codeberg_package_source_url: source_tree_url("https://codeberg.org/#{slug}", package_path),
        checksums_url: source_tree_url("https://gitlab.com/#{slug}", "checksums")
      )
    end

    def repository_resource_urls(repository)
      repo_url = repository[:url].to_s
      repo_slug = repository[:slug].to_s
      github_org = repo_slug.split("/", 2).first.to_s
      repo_name = repository[:name].to_s
      gitlab_url = repository[:gitlab_url].to_s
      gitlab_url = "https://gitlab.com/#{repo_slug}" if gitlab_url.empty?
      codeberg_url = repository[:codeberg_url].to_s
      codeberg_url = "https://codeberg.org/#{repo_slug}" if codeberg_url.empty?
      package_source_url = repository[:package_source_url].to_s
      package_source_url = repo_url if package_source_url.empty?
      gitlab_package_source_url = repository[:gitlab_package_source_url].to_s
      gitlab_package_source_url = gitlab_url if gitlab_package_source_url.empty?
      codeberg_package_source_url = repository[:codeberg_package_source_url].to_s
      codeberg_package_source_url = codeberg_url if codeberg_package_source_url.empty?
      checksums_url = repository[:checksums_url].to_s
      checksums_url = source_tree_url(gitlab_url, "checksums") if checksums_url.empty?

      {
        github_repository_url: repo_url,
        github_package_source_url: package_source_url,
        github_releases_url: "#{repo_url}/releases",
        github_actions_url: "#{repo_url}/actions",
        github_discussions_url: "#{repo_url}/discussions",
        github_issues_url: "#{repo_url}/issues",
        github_pulls_url: "#{repo_url}/pulls",
        github_wiki_url: "#{repo_url}/wiki",
        github_codeql_url: "#{repo_url}/security/code-scanning",
        github_contributors_url: "#{repo_url}/graphs/contributors",
        github_contributing_url: source_blob_url(repo_url, "CONTRIBUTING.md"),
        github_changelog_url: source_blob_url(repo_url, "CHANGELOG.md"),
        github_security_url: source_blob_url(repo_url, "SECURITY.md"),
        github_code_of_conduct_url: source_blob_url(repo_url, "CODE_OF_CONDUCT.md"),
        github_rubocop_url: source_blob_url(repo_url, "RUBOCOP.md"),
        github_irp_url: source_blob_url(repo_url, "IRP.md"),
        gitlab_repository_url: gitlab_url,
        gitlab_package_source_url: gitlab_package_source_url,
        gitlab_issues_url: "#{gitlab_url}/-/issues",
        gitlab_pulls_url: "#{gitlab_url}/-/merge_requests",
        gitlab_wiki_url: "#{gitlab_url}/-/wikis/home",
        gitlab_contributors_url: "#{gitlab_url}/-/graphs/main",
        gitlab_contributing_url: source_blob_url(gitlab_url, "CONTRIBUTING.md"),
        gitlab_changelog_url: source_blob_url(gitlab_url, "CHANGELOG.md"),
        gitlab_code_of_conduct_url: source_blob_url(gitlab_url, "CODE_OF_CONDUCT.md"),
        gitlab_compare_url: "#{gitlab_url}/-/compare",
        gitlab_tags_url: "#{gitlab_url}/-/tags",
        codeberg_repository_url: codeberg_url,
        codeberg_package_source_url: codeberg_package_source_url,
        codeberg_issues_url: "#{codeberg_url}/issues",
        codeberg_pulls_url: "#{codeberg_url}/pulls",
        codecov_url: "https://codecov.io/gh/#{repo_slug}",
        codecov_badge_url: "https://codecov.io/gh/#{repo_slug}/graph/badge.svg",
        codecov_graph_url: "https://codecov.io/gh/#{repo_slug}/graph/badge.svg",
        coveralls_url: "https://coveralls.io/github/#{repo_slug}?branch=main",
        coveralls_badge_url: "https://coveralls.io/repos/github/#{repo_slug}/badge.svg?branch=main",
        qlty_project_url: "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}",
        qlty_maintainability_url: "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}/maintainability.svg",
        qlty_coverage_url: "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}/metrics/code?sort=coverageRating",
        qlty_coverage_badge_url: "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}/coverage.svg",
        checksums_url: checksums_url
      }
    end

    def repository_root_url(source_url)
      uri = URI.parse(source_url.to_s)
      return source_url.to_s unless uri.host == "github.com"

      segments = uri.path.to_s.split("/").reject(&:empty?)
      return source_url.to_s if segments.length < 2

      "#{uri.scheme}://#{uri.host}/#{segments[0]}/#{segments[1].delete_suffix(".git")}"
    rescue URI::InvalidURIError
      source_url.to_s
    end

    def source_tree_url(source_url, path)
      base = source_url.to_s.dup
      base = base[0...-1] while base.end_with?("/")
      escaped_path = path.to_s.split("/").map { |segment| segment.split(" ").join("%20") }.join("/")
      if base.start_with?("https://gitlab.com/", "http://gitlab.com/")
        "#{base}/-/tree/main/#{escaped_path}"
      elsif base.start_with?("https://codeberg.org/", "http://codeberg.org/")
        "#{base}/src/branch/main/#{escaped_path}"
      else
        "#{base}/tree/main/#{escaped_path}"
      end
    end

    def git_worktree_root(project_root)
      root = git_capture(project_root, "rev-parse", "--show-toplevel").strip
      root.empty? ? project_root.to_s : root
    rescue ArgumentError
      project_root.to_s
    end

    def git_worktree_prefix(project_root)
      git_capture(project_root, "rev-parse", "--show-prefix").strip
    rescue ArgumentError
      ""
    end

    def gitlab_repo_url(repository, repo_slug, suffix)
      resources = repository[:resource_urls] || {}
      return resources[:gitlab_issues_url] if suffix == "issues" && resources[:gitlab_issues_url]
      return resources[:gitlab_pulls_url] if suffix == "merge_requests" && resources[:gitlab_pulls_url]
      return resources[:gitlab_wiki_url] if suffix == "wikis/home" && resources[:gitlab_wiki_url]
      return resources[:gitlab_contributors_url] if suffix == "graphs/main" && resources[:gitlab_contributors_url]

      base = repository[:gitlab_url].to_s
      base = "https://gitlab.com/#{repo_slug}" if base.empty?
      "#{base}/-/#{suffix}"
    end

    def codeberg_repo_url(repository, repo_slug, suffix)
      resources = repository[:resource_urls] || {}
      return resources[:codeberg_issues_url] if suffix == "issues" && resources[:codeberg_issues_url]
      return resources[:codeberg_pulls_url] if suffix == "pulls" && resources[:codeberg_pulls_url]

      base = repository[:codeberg_url].to_s
      base = "https://codeberg.org/#{repo_slug}" if base.empty?
      "#{base}/#{suffix}"
    end

    def git_remote_source_url(project_root)
      normalize_git_source_url(git_capture(project_root, "config", "--get", "remote.origin.url").strip)
    rescue ArgumentError
      nil
    end

    def readme_star_history_facts(project_root, git_source_url)
      repository_slug = github_repository_slug(git_source_url)
      return {enabled: false, reason: "no_github_remote"} if repository_slug.to_s.empty?

      stars = github_repository_star_count(project_root, repository_slug)
      unless stars
        return {
          enabled: false,
          repository: repository_slug,
          reason: "star_count_unavailable"
        }
      end

      {
        enabled: stars >= README_STAR_HISTORY_MIN_STARS,
        repository: repository_slug,
        stars: stars,
        minimum_stars: README_STAR_HISTORY_MIN_STARS
      }
    end

    def github_repository_slug(url)
      normalized = normalize_git_source_url(url)
      match = normalized.to_s.match(%r{\Ahttps?://github\.com/([^/]+)/([^/?#]+)})
      return unless match

      repository = match[2].delete_suffix(".git")
      return if match[1].empty? || repository.empty?

      "#{match[1]}/#{repository}"
    end

    def github_repository_star_count(project_root, repository_slug)
      stdout, _stderr, status = Open3.capture3(
        "gh",
        "api",
        "repos/#{repository_slug}",
        "--jq",
        ".stargazers_count",
        chdir: project_root.to_s
      )
      return unless status.success?

      Integer(stdout.to_s.strip)
    rescue ArgumentError, IOError, SystemCallError
      nil
    end

    def normalize_git_source_url(url)
      value = url.to_s.strip
      return if value.empty?

      if value.start_with?("git@github.com:")
        slug = value.split(":", 2).last.to_s.delete_suffix(".git")
        return "https://github.com/#{slug}" if slug.split("/").length >= 2
      end

      uri = URI.parse(value)
      if uri.scheme == "ssh" && uri.host == "github.com"
        slug = uri.path.to_s.delete_prefix("/").delete_suffix(".git")
        return "https://github.com/#{slug}" if slug.split("/").length >= 2
      end

      if %w[http https].include?(uri.scheme) && uri.host == "github.com"
        slug = uri.path.to_s.delete_prefix("/").delete_suffix(".git")
        return "https://github.com/#{slug}" if slug.split("/").length >= 2
      end

      value
    rescue URI::InvalidURIError
      value
    end

    def readme_logo_facts(config, package_name:, github_org:, repository: {})
      top_entries = readme_top_logo_entries(
        config,
        org: github_org.to_s,
        gem_name: package_name.to_s,
        repository: repository || {}
      )
      h2_synopsis_entries = readme_h2_synopsis_logo_entries(
        config,
        org: github_org.to_s,
        gem_name: package_name.to_s,
        repository: repository || {}
      )
      all_entries = deduplicate_readme_top_logo_entries(top_entries + h2_synopsis_entries)
      compact_hash(
        top_logos: readme_top_logo_options(config).join(","),
        h2_synopsis_logos: readme_h2_synopsis_logo_options(config).join(","),
        top_logo_row: readme_top_logo_row(top_entries),
        h2_synopsis_logo_row: readme_h2_synopsis_logo_row(h2_synopsis_entries),
        top_logo_refs: readme_top_logo_refs(all_entries)
      )
    end

    def readme_corporate_sponsors_facts(config, env)
      sponsors = readme_corporate_sponsors(config, env)
      compact_hash(
        entries: sponsors,
        row: readme_corporate_sponsors_row(sponsors)
      )
    end

    def readme_corporate_sponsors(config, env)
      readme_config = readme_config_hash(config)
      configured = normalize_readme_corporate_sponsors(
        readme_config["corporate_sponsors"] || readme_config["sponsors"]
      )
      inherited = normalize_readme_corporate_sponsors_json(env["KETTLE_JEM_CORPORATE_SPONSORS_JSON"])
      deduplicate_readme_corporate_sponsors(configured + inherited)
    end

    def normalize_readme_corporate_sponsors_json(value)
      clean = value.to_s.strip
      return [] if clean.empty?

      parsed = JSON.parse(clean)
      normalize_readme_corporate_sponsors(parsed)
    rescue JSON::ParserError
      raise ArgumentError, "invalid KETTLE_JEM_CORPORATE_SPONSORS_JSON"
    end

    def normalize_readme_corporate_sponsors(value)
      Array(value).filter_map do |entry|
        unless entry.is_a?(Hash)
          raise ArgumentError, "corporate sponsor entries must be mappings with name, url, and img_src"
        end

        name = entry["name"].to_s.strip
        url = entry["url"].to_s.strip
        img_src = entry["img_src"].to_s.strip
        if name.empty? || url.empty? || img_src.empty?
          raise ArgumentError, "corporate sponsor entries require name, url, and img_src"
        end

        {
          name: name,
          url: url,
          img_src: img_src
        }
      end
    end

    def deduplicate_readme_corporate_sponsors(sponsors)
      sponsors
        .group_by { |sponsor| [sponsor[:name], sponsor[:url], sponsor[:img_src]] }
        .values
        .map(&:first)
    end

    def readme_corporate_sponsors_row(sponsors)
      return "" if sponsors.empty?

      label = sponsors.one? ? "Corporate sponsor:" : "Corporate sponsors:"
      logos = sponsors.map do |sponsor|
        [
          %(<a href="#{html_attribute_escape(sponsor.fetch(:url))}">),
          %(<img alt="#{html_attribute_escape(sponsor.fetch(:name))}"),
          %( src="#{html_attribute_escape(sponsor.fetch(:img_src))}" height="24"/>),
          "</a>"
        ].join
      end.join(" ")
      %(<p><sub>#{label} #{logos} <a href="#-floss-funding">Become a sponsor</a></sub></p>)
    end

    def readme_top_logo_options(config)
      readme_logo_options_from_config(config, "top_logos", "top_logo_options", README_TOP_LOGO_DEFAULTS)
    end

    def readme_h2_synopsis_logo_options(config)
      readme_h2_synopsis_logo_specs(config).map { |spec| spec.fetch(:type) }
    end

    def readme_h2_synopsis_logo_specs(config)
      readme_config = readme_config_hash(config)
      h2_synopsis_logos = readme_config["h2_synopsis_logos"]
      normalized = normalized_readme_logo_specs(h2_synopsis_logos)
      return normalized unless normalized.empty?

      raw_top_logos = readme_config["top_logos"] || readme_config["top_logo_options"]
      normalized_top_logos = normalized_readme_logo_specs(raw_top_logos)
      synopsis_from_top_logos = normalized_top_logos.select { |spec| README_H2_SYNOPSIS_LOGO_DEFAULTS.include?(spec.fetch(:type)) }
      return synopsis_from_top_logos unless synopsis_from_top_logos.empty?

      legacy_mode = readme_config["top_logo_mode"].to_s.strip.downcase.tr("-", "_")
      legacy_options = README_TOP_LOGO_LEGACY_MODE_MAP[legacy_mode]
      synopsis_from_legacy = Array(legacy_options).filter_map do |option|
        {type: option, width: nil} if README_H2_SYNOPSIS_LOGO_DEFAULTS.include?(option)
      end
      return synopsis_from_legacy unless synopsis_from_legacy.empty?

      raw_top_logos ? [] : README_H2_SYNOPSIS_LOGO_DEFAULTS.map { |option| {type: option, width: nil} }
    end

    def readme_logo_options_from_config(config, primary_key, secondary_key, defaults)
      readme_logo_specs_from_config(config, primary_key, secondary_key, defaults).map { |spec| spec.fetch(:type) }
    end

    def readme_logo_specs_from_config(config, primary_key, secondary_key, defaults)
      readme_config = readme_config_hash(config)
      raw_logos = readme_config[primary_key] || readme_config[secondary_key]
      normalized = normalized_readme_logo_specs(raw_logos)
      selected = normalized.select { |spec| defaults.include?(spec.fetch(:type)) }
      return selected unless selected.empty?
      return [] if raw_logos

      legacy_mode = readme_config["top_logo_mode"].to_s.strip.downcase.tr("-", "_")
      legacy_options = README_TOP_LOGO_LEGACY_MODE_MAP[legacy_mode]
      selected_legacy = Array(legacy_options).filter_map do |option|
        {type: option, width: nil} if defaults.include?(option)
      end
      return selected_legacy unless selected_legacy.empty?

      defaults.map { |option| {type: option, width: nil} }
    end

    def readme_config_hash(config)
      raw_config = config.is_a?(Hash) ? config["readme"] : nil
      raw_config.is_a?(Hash) ? raw_config : {}
    end

    def normalized_readme_top_logo_options(value)
      normalized_readme_logo_specs(value).map { |spec| spec.fetch(:type) }
    end

    def normalized_readme_logo_specs(value)
      raw_values = case value
      when String
        value.split(",")
      when Array
        value
      else
        []
      end
      raw_values.filter_map do |raw_value|
        raw_type, raw_width = raw_value.to_s.split("|", 2)
        normalized = raw_type.to_s.strip.downcase.tr("-", "_")
        next unless README_TOP_LOGO_OPTIONS.include?(normalized)

        {type: normalized, width: normalized_readme_logo_width(raw_width)}
      end.uniq
    end

    def normalized_readme_logo_width(value)
      clean = value.to_s.strip
      return nil if clean.empty?

      clean
    end

    def readme_top_logo_entries(config, org:, gem_name:, repository: {})
      configured = configured_readme_top_logo_entries(config, org: org, gem_name: gem_name, repository: repository)
      return readme_top_logo_entries_with_asset_size(configured) if configured

      entries = readme_logo_specs_from_config(config, "top_logos", "top_logo_options", README_TOP_LOGO_DEFAULTS).filter_map do |spec|
        readme_top_logo_entry_from_option(spec.fetch(:type), org: org, gem_name: gem_name, repository: repository)&.merge(width: spec[:width])
      end
      entries = deduplicate_readme_top_logo_entries(entries)
      readme_top_logo_entries_with_asset_size(entries)
    end

    def readme_h2_synopsis_logo_entries(config, org:, gem_name:, repository: {})
      entries = readme_h2_synopsis_logo_specs(config).filter_map do |spec|
        readme_top_logo_entry_from_option(spec.fetch(:type), org: org, gem_name: gem_name, repository: repository)&.merge(width: spec[:width])
      end
      entries = deduplicate_readme_top_logo_entries(entries)
      readme_top_logo_entries_with_asset_size(entries)
    end

    def readme_top_logo_entries_with_asset_size(entries)
      entries.map do |entry|
        image_url = entry.fetch(:image_url).to_s.sub(%r{/avatar-\d+px\.svg\z}, "/avatar-128px.svg")
        entry.merge(image_url: image_url)
      end
    end

    def configured_readme_top_logo_entries(config, org:, gem_name:, repository: {})
      readme_config = (config.is_a?(Hash) && config["readme"].is_a?(Hash)) ? config["readme"] : {}
      logo_row = readme_config["logo_row"]
      return unless logo_row.is_a?(Hash)
      return [] if falsey_config?(logo_row["enabled"])

      logos = Array(logo_row["logos"]).first(4)
      return [] if logos.empty?

      logos.filter_map do |logo|
        readme_top_logo_entry_from_config(logo, org: org, gem_name: gem_name, repository: repository)
      end.then { |entries| deduplicate_readme_top_logo_entries(entries) }
    end

    def deduplicate_readme_top_logo_entries(entries)
      entries.group_by { |entry| entry[:image_url].to_s }.values.map do |group|
        group.find { |entry| entry[:type] == "related_org" } || group.first
      end
    end

    def readme_top_logo_entry_from_config(logo, org:, gem_name:, repository: {})
      return unless logo.is_a?(Hash)

      type = logo["type"].to_s.strip.downcase.tr("-", "_")
      return unless README_TOP_LOGO_TYPES.include?(type)
      type = "ruby" if type == "language"

      slug = logo["slug"].to_s.strip
      slug = default_readme_top_logo_slug(type, org: org, gem_name: gem_name, repository: repository) if slug.empty?
      return if slug.empty?

      alt = logo["alt"].to_s.strip
      alt = readme_top_logo_default_alt(type, slug) if alt.empty?
      href = logo["href"].to_s.strip
      href = default_readme_top_logo_href(type, slug: slug, org: org, gem_name: gem_name, repository: repository) if href.empty?
      credit = logo["credit"].to_s.strip
      credit = default_readme_top_logo_credit(type) if credit.empty?
      ref_slug = slug.tr("/", "-")
      {
        type: type,
        label: alt.sub(/\s+logo\z/i, ""),
        credit: credit,
        credit_separator: readme_top_logo_credit_separator(type),
        image_ref: "#{ref_slug}-i",
        link_ref: ref_slug,
        image_url: readme_top_logo_image_url(type, slug),
        href: href
      }
    end

    def readme_top_logo_image_url(type, slug)
      return "https://github.com/#{slug}.png?size=192" if type == "org"

      "#{LOGOS_GALTZO_BASE_URL}/#{slug}/avatar-192px.svg"
    end

    def default_readme_top_logo_slug(type, org:, gem_name:, repository: {})
      case type
      when "related_org"
        "galtzo-floss"
      when "ruby"
        "ruby-lang"
      when "org"
        org.to_s
      when "project"
        repository_project_logo_slug(repository, org: org, gem_name: gem_name)
      else
        ""
      end
    end

    def readme_top_logo_default_alt(type, slug)
      label = slug.split("/").last.to_s
      case type
      when "related_org"
        "Galtzo FLOSS"
      when "ruby"
        "ruby-lang"
      when "org"
        label
      when "project"
        label
      else
        "#{label} affiliated project"
      end
    end

    def default_readme_top_logo_href(type, slug:, org:, gem_name:, repository: {})
      case type
      when "related_org"
        "https://discord.gg/3qme4XHNKN"
      when "ruby"
        "https://ruby-toolbox.com"
      when "org"
        org.to_s.empty? ? "#{LOGOS_GALTZO_BASE_URL}/#{slug}/" : "https://github.com/#{org}"
      when "project"
        repository_project_logo_href(repository, slug: slug, org: org, gem_name: gem_name)
      else
        "#{LOGOS_GALTZO_BASE_URL}/#{slug}/"
      end
    end

    def default_readme_top_logo_credit(type)
      case type
      when "ruby"
        "Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5"
      when "org"
        "GitHub"
      else
        "Aboling0, CC BY-SA 4.0"
      end
    end

    def readme_top_logo_credit_separator(type)
      (type == "ruby") ? ", " : " by "
    end

    def repository_project_logo_slug(repository, org:, gem_name:)
      package_path = repository.is_a?(Hash) ? repository[:package_path].to_s : ""
      return [org, repository[:name].to_s, File.basename(package_path)].reject(&:empty?).join("/") if repository.is_a?(Hash) && !package_path.empty?

      [org.to_s, gem_name.to_s].reject(&:empty?).join("/")
    end

    def repository_project_logo_href(repository, slug:, org:, gem_name:)
      package_source_url = repository.is_a?(Hash) ? repository[:package_source_url].to_s : ""
      return package_source_url unless package_source_url.empty?

      (org.to_s.empty? || gem_name.to_s.empty?) ? "#{LOGOS_GALTZO_BASE_URL}/#{slug}/" : "https://github.com/#{org}/#{gem_name}"
    end

    def readme_top_logo_entry_from_option(option, org:, gem_name:, repository: {})
      return if option == "org" && org.to_s.empty?
      return if option == "project" && (org.to_s.empty? || gem_name.to_s.empty?)

      readme_top_logo_entry_from_config({"type" => option}, org: org, gem_name: gem_name, repository: repository)
    end

    def readme_top_logo_row(entries)
      default_width = readme_default_logo_width(entries, one: "14%", two: "12%")
      entries.map do |entry|
        readme_logo_html(entry, align: "right", width: entry[:width] || default_width)
      end.join(" ")
    end

    def readme_h2_synopsis_logo_row(entries)
      default_width = readme_default_logo_width(entries, one: "10%", two: "8%")
      entries.map do |entry|
        readme_logo_html(entry, align: "right", width: entry[:width] || default_width)
      end.join(" ")
    end

    def readme_default_logo_width(entries, one:, two:)
      case entries.length
      when 1
        one
      when 2
        two
      end
    end

    def readme_top_logo_refs(entries)
      ""
    end

    def readme_logo_html(entry, align:, width: nil)
      attributes = [
        %(alt="#{html_attribute_escape("#{entry[:label]} Logo#{entry[:credit_separator]}#{entry[:credit]}")}"),
        %(src="#{html_attribute_escape(entry[:image_url])}")
      ]
      attributes << %(width="#{html_attribute_escape(width)}") if width
      attributes << %(align="#{html_attribute_escape(align)}")
      %(<a href="#{html_attribute_escape(entry[:href])}"><img #{attributes.join(" ")}/></a>)
    end

    def html_attribute_escape(value)
      value.to_s.gsub("&", "&amp;").gsub("\"", "&quot;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def readme_logo_template_tokens(readme_logo)
      {
        "KJ|README:H2_SYNOPSIS_LOGO_ROW" => readme_logo[:h2_synopsis_logo_row].to_s,
        "KJ|README:TOP_LOGO_ROW" => readme_logo[:top_logo_row].to_s,
        "KJ|README:TOP_LOGO_REFS" => readme_logo[:top_logo_refs].to_s
      }
    end

    def readme_corporate_sponsor_template_tokens(readme_sponsors)
      {
        "KJ|README:CORPORATE_SPONSORS" => readme_sponsors[:row].to_s
      }
    end

    def rubocop_template_tokens(min_ruby, ruby_style: {})
      constraint, gem_name, gem_constraint = rubocop_tokens_for(min_ruby_version(min_ruby))
      {
        "KJ|RUBOCOP_TARGET_RUBY" => rubocop_target_ruby_token(min_ruby),
        "KJ|RUBOCOP_LTS_CONSTRAINT" => constraint,
        "KJ|RUBOCOP_RUBY_GEM" => gem_name,
        "KJ|RUBOCOP_RUBY_CONSTRAINT" => gem_constraint
      }.merge(
        ruby_style_template_tokens(ruby_style)
      )
    end

    def ruby_style_template_tokens(ruby_style)
      style = ruby_style.is_a?(Hash) ? ruby_style : {}
      trailing_dot = style.fetch(:dot_position, style["dot_position"]).to_s == "trailing"
      trailing_array_comma = style.fetch(:trailing_array_comma, style["trailing_array_comma"]) == true
      family_gem_dirs_enumeration = if trailing_dot
        <<~RUBY.chomp
          Dir.glob(File.join(__dir__, "gems", "*", "*.gemspec")).
            map { |path| File.dirname(path) }.
            uniq.
            sort_by { |path| File.basename(path) }
        RUBY
      else
        <<~RUBY.chomp
          Dir.glob(File.join(__dir__, "gems", "*", "*.gemspec"))
            .map { |path| File.dirname(path) }
            .uniq
            .sort_by { |path| File.basename(path) }
        RUBY
      end

      {
        "KJ|RAKE:FAMILY_GEM_DIRS_ENUMERATION" => family_gem_dirs_enumeration.lines.map { |line| "    #{line}" }.join.chomp,
        "KJ|RUBY_STYLE:TRAILING_ARRAY_COMMA" => trailing_array_comma ? "," : ""
      }
    end

    def gemspec_template_facts(config)
      includes = Array(config.dig("gemspec", "package_files", "include"))
        .map { |path| path.to_s.strip }
        .reject(&:empty?)
        .uniq
      includes.empty? ? {} : {package_file_includes: includes}
    end

    def gemspec_template_tokens(gemspec, min_ruby: nil)
      {
        "KJ|GEMSPEC:ENUMERATE_PACKAGE_GLOB_BODY" => gemspec_enumerate_package_glob_body(min_ruby),
        "KJ|GEMSPEC:PACKAGE_FILE_INCLUDES" => gemspec_package_file_includes_token(gemspec),
        "KJ|GEMSPEC:RELATIVE_PACKAGE_PATH_BODY" => gemspec_relative_package_path_body(min_ruby)
      }
    end

    def gemspec_relative_package_path_body(min_ruby)
      if gemspec_modern_package_helper?(min_ruby)
        %(    path.delete_prefix("\#{gemspec_root}/"))
      else
        [
          %(    prefix = "\#{gemspec_root}/"),
          "    path[0, prefix.length] == prefix ? path[prefix.length..-1] : path"
        ].join("\n")
      end
    end

    def gemspec_enumerate_package_glob_body(min_ruby)
      if gemspec_modern_package_helper?(min_ruby)
        [
          "    Dir.glob(glob, File::FNM_DOTMATCH).filter_map do |path|",
          %(      next unless File.file?(path) && ![".", ".."].include?(File.basename(path))),
          "",
          "      relative_package_path.call(path)",
          "    end"
        ].join("\n")
      else
        [
          "    files = []",
          "    Dir.glob(glob, File::FNM_DOTMATCH).each do |path|",
          %(      next unless File.file?(path) && ![".", ".."].include?(File.basename(path))),
          "",
          "      files << relative_package_path.call(path)",
          "    end",
          "    files"
        ].join("\n")
      end
    end

    def gemspec_modern_package_helper?(min_ruby)
      token = minimum_ruby_token(min_ruby)
      return false if token.to_s.empty? || token == "0"

      Gem::Version.new(token) >= Gem::Version.new("2.7")
    rescue ArgumentError
      false
    end

    def gemspec_package_file_includes_token(gemspec)
      includes = Array(gemspec[:package_file_includes] || gemspec["package_file_includes"])
        .map { |path| path.to_s.strip }
        .reject(&:empty?)
        .uniq
      return "" if includes.empty?

      lines = [
        "",
        "    # Extra package files configured by .structuredmerge/kettle-jem.yml"
      ]
      includes.each_with_index do |pattern, index|
        comma = (index < includes.length - 1) ? "," : ""
        glob = %(File.join(gemspec_root, #{pattern.dump}))
        lines << %(    *enumerate_package_glob.call(#{glob})#{comma})
      end
      ",#{lines.join("\n")}"
    end

    def rubocop_target_ruby_token(min_ruby)
      token = minimum_ruby_token(min_ruby)
      return "0" if token == "0"

      segments = Gem::Version.new(token).segments
      segments.first(2).join(".")
    rescue ArgumentError
      ""
    end

    def rubocop_tokens_for(min_ruby)
      Kettle::Rb::CompatMatrix.rubocop_template_tokens(min_ruby)
    end

    def min_ruby_version(requirement)
      token = minimum_ruby_token(requirement)
      return if token.empty?

      Gem::Version.new(token)
    rescue ArgumentError
      nil
    end

    def license_facts(config, gemspec_licenses, author: {}, author_email: nil, copyright: {}, source_url: nil, license_txt: {})
      configured_licenses = Array(config["licenses"]).map { |license| license.to_s.strip }.reject(&:empty?)
      gemspec_licenses = Array(gemspec_licenses).map { |license| license.to_s.strip }.reject(&:empty?)
      licenses = if configured_licenses.any?
        configured_licenses
      elsif gemspec_licenses.any?
        gemspec_licenses
      elsif license_txt[:present] && !license_txt[:mit]
        []
      else
        ["MIT"]
      end
      custom_license = license_txt[:custom] && configured_licenses.empty? && gemspec_licenses.empty?
      primary = licenses.first
      compat_category = license_compat_category(licenses)
      copyright_prefix = polyform_licenses?(licenses) ? "Required Notice: " : ""
      copyright_lines = Array(copyright[:lines])
      # Git blame is authoritative for generated LICENSE.md notices. A legacy
      # MIT LICENSE.txt notice is only a fallback for projects without blame
      # data, such as an unpacked source tree being templated for the first time.
      copyright_lines = license_txt[:copyright_lines] if copyright_lines.empty? && license_txt[:mit]
      license_source_url = license_source_blob_url(source_url)
      compact_hash(
        spdx: licenses,
        expression: licenses.join(" OR "),
        primary_spdx: primary,
        license_md_content: license_md_content(licenses, author_email: author_email, license_source_url: license_source_url, custom_license: custom_license),
        readme_license_intro: readme_license_intro(licenses, author_email: author_email, license_source_url: license_source_url, custom_license: custom_license),
        readme_license_badge: license_badge(licenses.join(" OR "), ref: :license),
        readme_license_compat_badge: license_compat_badge(compat_category),
        readme_license_eye_workflow_badge: license_eye_workflow_badge(licenses, config),
        readme_license_refs: readme_license_refs(licenses.join(" OR "), compat_category, license_source_url: license_source_url),
        license_eye_primary_spdx: license_eye_primary_spdx(licenses, primary),
        license_eye_mode: license_eye_mode(licenses),
        license_eye_flags: license_eye_flags(licenses),
        license_eye_dependency_licenses: license_eye_dependency_licenses(config),
        license_copyright_notice: license_copyright_notice(copyright_lines, copyright_prefix, author),
        readme_copyright_notice: readme_copyright_notice(copyright_lines, copyright_prefix, author),
        copyright_prefix: copyright_prefix
      )
    end

    def license_txt_facts(project_root)
      path = File.join(project_root.to_s, "LICENSE.txt")
      return {} unless File.file?(path)

      migrator = LicenseTxtMigrator.new(File.read(path))
      if migrator.mit_license?
        {present: true, mit: true, copyright_lines: migrator.copyright_lines}
      else
        {present: true, custom: true, mit: false, copyright_lines: []}
      end
    rescue => error
      Kettle::Dev.debug_error(error, __method__)
      {present: true, custom: true, mit: false, copyright_lines: []}
    end

    def license_source_blob_url(source_url)
      repo_url = concrete_github_url(source_url)
      repo_url = source_url.to_s.sub(%r{/tree/[^/]+\z}, "") if repo_url.to_s.empty?
      return if repo_url.to_s.empty?

      "#{repo_url.to_s.sub(%r{/\z}, "")}/blob/main"
    end

    def resolved_licenses(config, gemspec_licenses)
      config_licenses = config.is_a?(Hash) ? config["licenses"] : nil
      licenses = Array(config_licenses).map { |license| license.to_s.strip }.reject(&:empty?)
      return licenses unless licenses.empty?

      licenses = Array(gemspec_licenses).map { |license| license.to_s.strip }.reject(&:empty?)
      licenses.empty? ? ["MIT"] : licenses
    end

    def license_template_tokens(license)
      {
        "KJ|LICENSE_MD_CONTENT" => license[:license_md_content].to_s,
        "KJ|GEMSPEC:ROOT_LICENSE_FILES" => gemspec_root_license_files_token(license),
        "KJ|README:LICENSE_INTRO" => license[:readme_license_intro].to_s,
        "KJ|LICENSE:PRIMARY_SPDX" => license[:primary_spdx].to_s,
        "KJ|LICENSE_EYE:PRIMARY_SPDX" => license[:license_eye_primary_spdx].to_s,
        "KJ|LICENSE_EYE:MODE" => license[:license_eye_mode].to_s,
        "KJ|LICENSE_EYE:FLAGS" => license[:license_eye_flags].to_s,
        "KJ|LICENSE_EYE:DEPENDENCY_LICENSES" => license[:license_eye_dependency_licenses].to_s,
        "KJ|README:LICENSE_BADGE" => license[:readme_license_badge].to_s,
        "KJ|README:LICENSE_COMPAT_BADGE" => license[:readme_license_compat_badge].to_s,
        "KJ|README:LICENSE_EYE_WORKFLOW_BADGE" => license[:readme_license_eye_workflow_badge].to_s,
        "KJ|README:LICENSE_REFS" => license[:readme_license_refs].to_s,
        "KJ|LICENSE_COPYRIGHT_NOTICE" => license[:license_copyright_notice].to_s,
        "KJ|README:COPYRIGHT_NOTICE" => license[:readme_copyright_notice].to_s,
        "KJ|COPYRIGHT_PREFIX" => license[:copyright_prefix].to_s
      }
    end

    def gemspec_root_license_files_token(_license)
      "    \"LICENSE.md\",\n"
    end

    def license_copyright_notice(copyright_lines, copyright_prefix, author)
      lines = copyright_notice_lines(copyright_lines, copyright_prefix, author).map { |line| "- #{line}" }
      "## Copyright Notice\n\n#{lines.join("\n")}"
    end

    def readme_copyright_notice(copyright_lines, copyright_prefix, author)
      lines = copyright_notice_lines(copyright_lines, copyright_prefix, author).map { |line| "- #{line}" }
      <<~MARKDOWN.chomp
        See [LICENSE.md][#{paperclip_ref(:license)}] for the official copyright notice.

        <details markdown="1">
        <summary>Copyright holders</summary>

        #{lines.join("\n")}

        </details>
      MARKDOWN
    end

    def copyright_notice_lines(copyright_lines, copyright_prefix, author)
      lines = Array(copyright_lines)
      lines = ["Copyright (c) #{Time.now.utc.year} #{[author[:given_names], author[:family_names]].compact.join(" ").strip}"] if lines.empty?
      lines.map { |line| "#{copyright_prefix}#{line}" }
    end

    def license_md_content(licenses, author_email: nil, license_source_url: nil, custom_license: false)
      return "# License\n\nThe licensing terms for this project are provided in [LICENSE.txt](LICENSE.txt)." if custom_license

      content = <<~MARKDOWN.chomp
        # License

        This project is made available under the following license#{"s" if licenses.size > 1}.
        Choose the option that best fits your use case:

        #{licenses.map { |license| "- #{license_link(license, license_source_url: license_source_url)}" }.join("\n")}
      MARKDOWN
      guide_table = license_use_case_guide_table(licenses, author_email: author_email, license_source_url: license_source_url)
      content += "\n\n## Use-case guide\n\n#{guide_table}" if guide_table
      content += "\n\n#{license_contact_line(author_email, context: :license_md)}" if non_mit_licenses?(licenses)
      content
    end

    def readme_license_intro(licenses, author_email: nil, license_source_url: nil, custom_license: false)
      return "The licensing terms for this project are provided in [LICENSE.txt](LICENSE.txt). See [LICENSE.md](LICENSE.md) for details." if custom_license

      return mit_readme_license_intro(license_source_url: license_source_url) if licenses == ["MIT"]

      intro = "The gem is available under the following license#{"s" if licenses.size > 1}: " \
        "#{licenses.map { |license| license_link(license, license_source_url: license_source_url) }.join(", ")}.\n" \
        "See [LICENSE.md][#{paperclip_ref(:license)}] for details."
      intro += "\n\n#{license_contact_line(author_email, context: :readme)}" if non_mit_licenses?(licenses)
      guide_table = license_use_case_guide_table(licenses, author_email: author_email, license_source_url: license_source_url)
      intro += "\n\n### License use-case guide\n\n#{guide_table}" if guide_table
      intro
    end

    def mit_readme_license_intro(license_source_url: nil)
      "The gem is available as open source under the terms of\n" \
        "the #{license_link("MIT", license_source_url: license_source_url)} #{license_badge("MIT")}."
    end

    def license_contact_line(author_email, context:)
      if author_email.to_s.empty?
        return "If none of the above licenses fit your use case, please contact the project maintainer to discuss a custom commercial license." if context == :license_md

        "If none of the available licenses suit your use case, please contact the project maintainer to discuss a custom commercial license."
      elsif context == :license_md
        "If none of the above licenses fit your use case, please [contact us](mailto:#{author_email}) to discuss a custom commercial license."
      else
        "If none of the available licenses suit your use case, please [contact us](mailto:#{author_email}) to discuss a custom commercial license."
      end
    end

    def readme_license_refs(expression, compat_category, license_source_url: nil)
      [
        "[#{paperclip_ref(:copyright_notice_explainer)}]: https://opensource.stackexchange.com/questions/5778/why-do-licenses-such-as-the-mit-license-specify-a-single-year",
        "[#{paperclip_ref(:license)}]: LICENSE.md",
        "[#{paperclip_ref(:license_ref)}]: #{license_badge_ref(expression, license_source_url: license_source_url)}",
        "[#{paperclip_ref(:license_img)}]: #{license_badge_img(expression)}",
        "[#{paperclip_ref(:license_compat)}]: #{license_compat_ref(compat_category)}",
        "[#{paperclip_ref(:license_compat_img)}]: #{license_compat_img(compat_category)}"
      ].join("\n")
    end

    def spdx_basename(spdx_id)
      spdx_id.to_s.sub(/\ALicenseRef-/, "")
    end

    def license_link(spdx_id, license_source_url: nil)
      base = spdx_basename(spdx_id)
      "[#{base}](#{license_detail_ref(base, license_source_url: license_source_url)})"
    end

    def license_badge(spdx_id, ref: :license_ref)
      base = spdx_basename(spdx_id)
      "[![License: #{base}][#{paperclip_ref(:license_img)}]][#{paperclip_ref(ref)}]"
    end

    def license_badge_ref(spdx_id, license_source_url: nil)
      base = spdx_basename(spdx_id)
      base.include?(" OR ") ? "LICENSE.md" : license_detail_ref(base, license_source_url: license_source_url)
    end

    def license_detail_ref(base, license_source_url: nil)
      file = "#{base}.md"
      license_source_url.to_s.empty? ? file : "#{license_source_url}/#{file}"
    end

    def license_badge_img(spdx_id)
      base = spdx_basename(spdx_id).gsub("-", "--").gsub("_", "__").tr(" ", "_")
      "https://img.shields.io/badge/License-#{base}-259D6C.svg"
    end

    def license_compat_category(licenses)
      categories = Array(licenses).filter_map { |license| APACHE_LICENSE_COMPAT_CATEGORIES[license.to_s] }.uniq
      return :a if categories.include?(:a)
      return :b if categories.include?(:b)
      return :x if categories.any? && categories.all?(:x)

      :unknown
    end

    def license_compat_badge(category)
      data = APACHE_LICENSE_COMPAT_BADGE_DATA.fetch(category)
      "[![#{data.fetch(:alt)}][#{paperclip_ref(:license_compat_img)}]][#{paperclip_ref(:license_compat)}]"
    end

    def license_eye_workflow_badge(licenses, config = {})
      disabled_integrations(config, license: {spdx: licenses}).include?(SKYWALKING_EYES_INTEGRATION) ? "" : README_LICENSE_EYE_WORKFLOW_BADGE
    end

    def license_eye_primary_spdx(licenses, fallback)
      Array(licenses).map(&:to_s).find { |license| LICENSE_EYE_COMPATIBILITY_LICENSES.include?(license) } || fallback
    end

    def license_eye_mode(licenses)
      (Array(licenses).map(&:to_s).any? { |license| LICENSE_EYE_COMPATIBILITY_LICENSES.include?(license) }) ? "check" : "resolve"
    end

    def license_eye_flags(licenses)
      (license_eye_mode(licenses) == "check") ? "--weak-compatible" : ""
    end

    def license_eye_dependency_licenses(config)
      entries = Array(config.dig("license_eye", "dependency_licenses")).filter_map do |entry|
        license_eye_dependency_license_entry(entry)
      end
      return "" if entries.empty?

      ["  licenses:", *entries].join("\n")
    end

    def license_eye_dependency_license_entry(entry)
      data = if entry.is_a?(Hash)
        entry
      else
        {}
      end
      name = data["name"] || data[:name]
      license = data["license"] || data[:license]
      version = data["version"] || data[:version]
      return if name.to_s.strip.empty? || license.to_s.strip.empty?

      lines = [
        "    - name: #{JSON.generate(name.to_s.strip)}",
        "      license: #{JSON.generate(license.to_s.strip)}"
      ]
      lines.insert(1, "      version: #{JSON.generate(version.to_s.strip)}") unless version.to_s.strip.empty?
      lines
    end

    def license_compat_ref(category)
      APACHE_LICENSE_COMPAT_BADGE_DATA.fetch(category).fetch(:ref)
    end

    def license_compat_img(category)
      data = APACHE_LICENSE_COMPAT_BADGE_DATA.fetch(category)
      normalize_generated_image_url(
        "https://img.shields.io/badge/#{data.fetch(:label)}-#{data.fetch(:message)}-#{data.fetch(:color)}.svg?style=flat&logo=Apache"
      )
    end

    def polyform_licenses?(licenses)
      licenses.any? { |license| license.to_s.start_with?("PolyForm-") }
    end

    def non_mit_licenses?(licenses)
      licenses.any? { |license| license != "MIT" }
    end

    def license_use_case_guide_table(licenses, author_email: nil, license_source_url: nil)
      has_floss_oss = licenses.include?("MIT") || licenses.include?("AGPL-3.0-only")
      has_polyform = licenses.include?("PolyForm-Noncommercial-1.0.0") || licenses.include?("PolyForm-Small-Business-1.0.0")
      has_big_time = licenses.include?("LicenseRef-Big-Time-Public-License")
      return unless has_floss_oss && has_polyform && has_big_time

      rows = license_use_case_rows(licenses, author_email: author_email, license_source_url: license_source_url)
      return if rows.empty?

      "| Use case | License |\n|---|---|\n" +
        rows.map { |use_case, license| "| #{use_case} | #{license} |" }.join("\n")
    end

    def license_use_case_rows(licenses, author_email: nil, license_source_url: nil)
      rows = []
      rows << ["FLOSS (free and open source)", license_link("MIT", license_source_url: license_source_url)] if licenses.include?("MIT")
      rows << ["Copy-left open source", license_link("AGPL-3.0-only", license_source_url: license_source_url)] if licenses.include?("AGPL-3.0-only")
      noncommercial_links = %w[PolyForm-Noncommercial-1.0.0 PolyForm-Small-Business-1.0.0 LicenseRef-Big-Time-Public-License]
        .select { |license| licenses.include?(license) }
        .map { |license| license_link(license, license_source_url: license_source_url) }
      rows << ["Non-commercial (research, education, personal use)", noncommercial_links.join(" or ")] unless noncommercial_links.empty?
      small_business_links = %w[PolyForm-Small-Business-1.0.0 LicenseRef-Big-Time-Public-License]
        .select { |license| licenses.include?(license) }
        .map { |license| license_link(license, license_source_url: license_source_url) }
      rows << ["Small business commercial", small_business_links.join(" or ")] unless small_business_links.empty?
      rows << ["Larger business commercial", large_business_license_cell(author_email, license_source_url: license_source_url)] if licenses.include?("LicenseRef-Big-Time-Public-License")
      rows
    end

    def large_business_license_cell(author_email, license_source_url: nil)
      cell = license_link("LicenseRef-Big-Time-Public-License", license_source_url: license_source_url)
      if author_email.to_s.empty?
        "#{cell} or contact us for a custom license"
      else
        "#{cell} or [contact us](mailto:#{author_email}) for a custom license"
      end
    end

    def paperclip_ref(name)
      {
        copyright_notice_explainer: "\u{1F4C4}copyright-notice-explainer",
        license: "\u{1F4C4}license",
        license_ref: "\u{1F4C4}license-ref",
        license_img: "\u{1F4C4}license-img",
        license_compat: "\u{1F4C4}license-compat",
        license_compat_img: "\u{1F4C4}license-compat-img"
      }.fetch(name)
    end

    def author_given_names(name)
      parts = name.to_s.strip.split(/\s+/)
      return "" if parts.size < 2

      parts[0...-1].join(" ")
    end

    def author_family_names(name)
      parts = name.to_s.strip.split(/\s+/)
      return "" if parts.size < 2

      parts[-1]
    end

    def resolve_template_tokens(content, tokens, scan_unresolved: true)
      resolver = Token::Resolver::Resolve.new(on_missing: :keep)
      document = Token::Resolver::Document.new(content.to_s, config: TEMPLATE_TOKEN_CONFIG)
      resolved = resolver.resolve(document, stringify_template_tokens(tokens))
      return resolved unless scan_unresolved

      unresolved = Token::Resolver::Document.new(resolved, config: TEMPLATE_TOKEN_CONFIG).token_keys.grep(/\AKJ\|/).sort
      return resolved if unresolved.empty?

      raise ArgumentError, "unresolved kettle-jem template tokens: #{unresolved.map { |token| "{#{token}}" }.join(", ")}"
    end

    def assert_no_unresolved_template_tokens_in_yaml_values(content, label)
      unresolved = yaml_scalar_value_template_tokens(content)
      return content if unresolved.empty?

      tokens = unresolved.map { |token| "{#{token}}" }.sort.join(", ")
      raise ArgumentError, "#{label}: unresolved kettle-jem template tokens: #{tokens}"
    end

    def yaml_scalar_value_template_tokens(content)
      yaml_scalar_pairs(content).flat_map do |_key_node, value_node|
        Token::Resolver::Document.new(value_node.value.to_s, config: TEMPLATE_TOKEN_CONFIG).token_keys.grep(/\AKJ\|/)
      end.uniq
    end

    def readme_style_facts(project_root, config, license, template_profile: nil, repository: nil)
      readme = config["readme"].is_a?(Hash) ? config["readme"] : {}
      conditional = readme["conditional_sections"].is_a?(Hash) ? readme["conditional_sections"] : {}
      disabled_integrations = readme_disabled_integrations(readme, integration_disabled: disabled_integrations(config, license: license))
      integration_root = readme_integration_project_root(project_root, template_profile, repository)
      missing_integrations = README_DISCOVERED_INTEGRATIONS.reject do |integration|
        disabled_integrations.include?(integration) || readme_integration_configured?(integration_root, integration)
      end
      workflow_paths = readme_workflow_paths(integration_root)
      omitted_sections = []
      security_enabled = repository_monorepo_subproject?(repository) ||
        File.exist?(File.join(project_root, "SECURITY.md"))
      floss_funding_enabled = readme_floss_funding_enabled?(license, conditional["floss_funding"])
      omitted_sections << "security" unless security_enabled
      omitted_sections << "floss_funding" unless floss_funding_enabled
      section_partials = readme_section_partials(project_root, config, readme)
      package_family = readme["package_family"].to_s.strip.downcase
      fossa_project = readme_fossa_project(readme, repository)
      compact_hash(
        profile: "slice-740-kettle-readme-style-profile",
        security_enabled: security_enabled,
        floss_funding_enabled: floss_funding_enabled,
        package_family: package_family,
        fossa_project: fossa_project,
        omitted_sections: omitted_sections,
        disabled_integrations: disabled_integrations,
        missing_integrations: missing_integrations,
        workflow_paths: workflow_paths,
        section_partials: section_partials
      )
    end

    def readme_fossa_project(readme, repository)
      badges = readme["badges"].is_a?(Hash) ? readme["badges"] : {}
      return "" unless badges.key?("fossa")

      value = badges["fossa"]
      return "" if falsey_config?(value)

      project = case value
      when Hash
        return "" if falsey_config?(value["enabled"])

        value["project"] || value["project_id"] || value["slug"]
      else
        value
      end
      normalized = project.to_s.strip
      return normalized unless normalized.empty? || %w[true yes 1 on enabled].include?(normalized.downcase)

      slug = repository.is_a?(Hash) ? repository[:slug].to_s : ""
      slug.empty? ? "" : "git+github.com/#{slug}"
    end

    def readme_integration_project_root(project_root, template_profile, repository)
      return project_root unless repository_monorepo_subproject?(repository)

      Array(repository && repository[:local_root]).find { |path| !path.to_s.empty? } || project_root
    end

    def repository_monorepo_subproject?(repository)
      return false unless repository.is_a?(Hash)

      repository[:topology].to_s == REPOSITORY_TOPOLOGY_MONOREPO_SUBPROJECT ||
        repository[:mode].to_s == "monorepo_subproject" ||
        repository[:mode].to_s == "monorepo_subgem"
    end

    def readme_workflow_paths(project_root)
      Dir.glob(File.join(project_root.to_s, ".github/workflows/*.{yml,yaml}")).map do |path|
        ".github/workflows/#{File.basename(path)}"
      end.sort
    end

    def readme_section_partials(project_root, config, readme)
      configured = readme["section_partials"]
      return {} unless configured.is_a?(Hash)

      root = template_root(project_root, config["templates"].is_a?(Hash) ? config["templates"] : {})
      configured.each_with_object({}) do |(section, source), result|
        normalized = normalize_readme_section_key(section)
        next if normalized.empty?

        source_path = source.to_s
        next if source_path.empty?

        selected = preferred_template_source(root.fetch(:path), source_path)
        next unless selected

        result[normalized] = {
          configured_source: source_path,
          selected_source: template_source_display_path(root, selected),
          source_relative_path: selected,
          source_root: root.fetch(:kind),
          content: File.read(File.join(root.fetch(:path), selected))
        }
      end
    end

    def normalize_readme_section_key(section)
      normalize_readme_heading(section.to_s.tr("_-", " "))
    end

    def readme_floss_funding_enabled?(license, config_value)
      return false if falsey_config?(config_value)
      return true if %w[true yes 1 always enabled].include?(config_value.to_s.strip.downcase)

      Array(license[:spdx]).map(&:to_s).include?("MIT")
    end

    def readme_disabled_integrations(readme, integration_disabled: [])
      disabled = []
      disabled.concat(Array(integration_disabled).map(&:to_s))
      integrations = readme["integrations"].is_a?(Hash) ? readme["integrations"] : {}
      badges = readme["badges"].is_a?(Hash) ? readme["badges"] : {}
      integrations.each do |name, value|
        disabled << name.to_s if falsey_config?(value)
      end
      disabled.concat(Array(badges["disabled"]).map(&:to_s))
      disabled.map { |name| normalize_integration_name(name) }.uniq & README_INTEGRATIONS
    end

    def disabled_integrations(config, license: nil)
      disabled = configured_disabled_integrations(config)
      disabled << SKYWALKING_EYES_INTEGRATION if skywalking_eyes_disabled_by_default?(config, license, disabled)
      disabled.map { |name| normalize_integration_name(name) }.uniq & MANAGED_INTEGRATIONS
    end

    def disabled_coverage_integrations(config)
      configured_disabled_integrations(config) & COVERAGE_INTEGRATIONS
    end

    def configured_disabled_integrations(config)
      integrations = if config.is_a?(Hash) && config["integrations"].is_a?(Hash)
        config["integrations"]
      else
        {}
      end
      disabled = Array(integrations["disabled"]).map(&:to_s)
      integrations.each do |name, value|
        normalized = normalize_integration_name(name)
        next if normalized.empty? || normalized == "disabled"

        disabled << normalized if falsey_config?(value)
      end
      disabled.map { |name| normalize_integration_name(name) }.uniq & MANAGED_INTEGRATIONS
    end

    def skywalking_eyes_disabled_by_default?(config, license, disabled)
      return false if disabled.include?(SKYWALKING_EYES_INTEGRATION)
      return false if explicit_integration_enabled?(config, SKYWALKING_EYES_INTEGRATION)

      licenses = integration_license_spdx(config, license)
      !license_eye_compatible_licenses?(licenses)
    end

    def integration_license_spdx(config, license)
      configured = if license.is_a?(Hash)
        license[:spdx] || license["spdx"]
      else
        []
      end
      configured = config["resolved_licenses"] if Array(configured).empty? && config.is_a?(Hash)
      Array(configured).map(&:to_s)
    end

    def license_eye_compatible_licenses?(licenses)
      Array(licenses).map(&:to_s).any? { |license_id| LICENSE_EYE_COMPATIBILITY_LICENSES.include?(license_id) }
    end

    def explicit_integration_enabled?(config, integration)
      return false unless config.is_a?(Hash) && config["integrations"].is_a?(Hash)

      config["integrations"].any? do |name, value|
        normalize_integration_name(name) == integration && truthy_config?(value)
      end
    end

    def normalize_integration_name(name)
      normalized = name.to_s.tr("_", "-").downcase
      return "codecov" if normalized == "code-cov"
      return "codeql" if normalized == "code-ql"
      return SKYWALKING_EYES_INTEGRATION if %w[license-eye license-eyes skywalking-eye skywalking-eyes apache-skywalking-eyes].include?(normalized)

      normalized
    end

    def readme_integration_configured?(project_root, integration)
      case integration
      when "codecov"
        File.exist?(File.join(project_root, ".codecov.yml")) ||
          File.exist?(File.join(project_root, "codecov.yml")) ||
          github_workflows_include?(project_root, "codecov/codecov-action")
      when "coveralls"
        File.exist?(File.join(project_root, ".coveralls.yml")) ||
          github_workflows_include?(project_root, "coverallsapp/github-action")
      when "qlty"
        File.exist?(File.join(project_root, ".qlty/qlty.toml")) ||
          File.exist?(File.join(project_root, ".qlty.yml")) ||
          github_workflows_include?(project_root, "qltysh/qlty-action")
      when "codeql"
        File.exist?(File.join(project_root, ".github/workflows/codeql.yml")) ||
          File.exist?(File.join(project_root, ".github/workflows/codeql-analysis.yml")) ||
          github_workflows_include?(project_root, "github/codeql-action")
      when "skywalking-eyes"
        File.exist?(File.join(project_root, ".github/workflows/license-eye.yml")) ||
          File.exist?(File.join(project_root, ".github/workflows/license-eye.yaml")) ||
          github_workflows_include?(project_root, "apache/skywalking-eyes/dependency")
      else
        false
      end
    end

    def github_workflows_include?(project_root, needle)
      Dir.glob(File.join(project_root, ".github/workflows/*.{yml,yaml}")).any? do |path|
        File.read(path).include?(needle)
      rescue Errno::ENOENT
        false
      end
    end

    def unresolved_template_scan?(recipe)
      return false if recipe.fetch(:target_path).to_s == KETTLE_CONFIG_PATH
      return false if recipe.dig(:template_preference, :skip_unresolved_scan)

      true
    end

    def stringify_template_tokens(tokens)
      tokens.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    end

    def falsey_config?(value)
      %w[false no 0].include?(value.to_s.strip.downcase)
    end

    def truthy_config?(value)
      %w[true yes 1 on enabled].include?(value.to_s.strip.downcase)
    end

    def merge_readme_template(template_content:, destination_content:, preserve_config: {})
      return template_content if destination_content.to_s.strip.empty?

      with_front_sections = preserve_readme_front_sections(template_content, destination_content)
      preserved = preserve_readme_sections(with_front_sections, destination_content, preserve_config)
      with_h1 = preserve_readme_h1(preserved, destination_content, preserve_config)
      preserve_readme_managed_block(with_h1, destination_content, "kettle-jem:metadata")
    end

    def preserve_readme_front_sections(template_content, destination_content)
      front_sections = readme_destination_front_sections(destination_content)
      return template_content if front_sections.empty?

      template_sections = markdown_sections(template_content)
      template_h1 = template_sections.find { |section| section.fetch(:level) == 1 }
      insert_before = template_sections.find do |section|
        section.fetch(:level) == 2 && section.fetch(:start) > template_h1.to_h.fetch(:start, -1)
      end
      return template_content unless insert_before

      lines = template_content.split("\n", -1)
      inserted = front_sections.map { |section| "#{section.fetch(:heading)}\n#{section.fetch(:body).rstrip}" }.join("\n\n")
      lines[(template_h1.fetch(:start) + 1)...insert_before.fetch(:start)] = ["", *inserted.split("\n"), ""]
      lines.join("\n")
    end

    def readme_destination_front_sections(destination_content)
      sections = markdown_sections(destination_content)
      h1 = sections.find { |section| section.fetch(:level) == 1 }
      synopsis = sections.find { |section| section.fetch(:level) == 2 && section.fetch(:base) == "synopsis" }
      return [] unless h1 && synopsis

      sections.select do |section|
        section.fetch(:level) == 2 &&
          section.fetch(:start) > h1.fetch(:start) &&
          section.fetch(:end) < synopsis.fetch(:start) &&
          readme_front_section_preserved?(section)
      end
    end

    def readme_front_section_preserved?(section)
      section.fetch(:base) == "important" || readme_section_contains_badge_cloud?(section)
    end

    def readme_section_contains_badge_cloud?(section)
      section.fetch(:body).to_s.lines.any? { |line| line.include?("[![") }
    end

    def preserve_readme_sections(template_content, destination_content, preserve_config)
      template_sections = markdown_sections(template_content)
      destination_sections = markdown_sections(destination_content)
      destination_lookup = destination_sections.to_h { |section| [section.fetch(:base), section] }
      preserve_targets = readme_preserve_targets(template_sections, destination_lookup, preserve_config)
      return template_content if preserve_targets.empty?

      template_bases = template_sections.map { |section| section.fetch(:base) }.to_set
      extra_sections_by_anchor = readme_extra_preserved_sections_by_anchor(
        destination_sections,
        template_bases,
        preserve_targets
      )
      lines = template_content.split("\n", -1)
      template_sections.reverse_each do |section|
        base = section.fetch(:base)
        extra_sections = extra_sections_by_anchor[base].to_a
        next if !preserve_targets.include?(base) && extra_sections.empty?

        replacement = if preserve_targets.include?(base)
          destination_section = destination_lookup[base] ||
            aliased_readme_destination_section(base, destination_lookup, preserve_config)
          next unless destination_section

          "#{section.fetch(:heading)}\n#{destination_section.fetch(:body)}"
        else
          lines[section.fetch(:start)..section.fetch(:end)].join("\n")
        end
        replacement = ([replacement] + extra_sections.map { |extra| "#{extra.fetch(:heading)}\n#{extra.fetch(:body)}" }).join("\n")
        lines[section.fetch(:start)..section.fetch(:end)] = replacement
      end
      lines.join("\n")
    end

    def readme_extra_preserved_sections_by_anchor(destination_sections, template_bases, preserve_targets)
      destination_sections.each_with_index.each_with_object({}) do |(section, index), result|
        base = section.fetch(:base)
        next if template_bases.include?(base)
        next unless preserve_targets.include?(base)
        next if readme_section_has_preserved_ancestor?(destination_sections, index, preserve_targets)

        anchor = destination_sections[0...index].reverse.find do |candidate|
          template_bases.include?(candidate.fetch(:base))
        end
        next unless anchor

        result[anchor.fetch(:base)] ||= []
        result[anchor.fetch(:base)] << section
      end
    end

    def readme_section_has_preserved_ancestor?(sections, index, preserve_targets)
      section = sections.fetch(index)
      section_level = section.fetch(:level).to_i
      sections[0...index].reverse_each do |candidate|
        next unless candidate.fetch(:level).to_i < section_level

        return preserve_targets.include?(candidate.fetch(:base))
      end
      false
    end

    def preserve_readme_h1(merged_content, destination_content, preserve_config)
      return merged_content if preserve_config.empty?

      merged_h1 = markdown_sections(merged_content).find { |section| section.fetch(:level) == 1 }
      destination_h1 = markdown_sections(destination_content).find { |section| section.fetch(:level) == 1 }
      return merged_content unless merged_h1 && destination_h1

      lines = merged_content.split("\n", -1)
      lines[merged_h1.fetch(:start)] = destination_h1.fetch(:heading)
      lines.join("\n")
    end

    def preserve_readme_managed_block(merged_content, destination_content, marker)
      destination_block = markdown_managed_block(destination_content, marker)
      return merged_content unless destination_block

      replace_markdown_managed_block(merged_content, marker, destination_block)
    end

    def markdown_managed_block(content, marker)
      ensure_runtime_dependencies!
      open = "<!-- #{marker}:start -->"
      close = "<!-- #{marker}:end -->"
      context = Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: "managed markdown block")
      target = Ast::Crispr::Markdown::Markly::Selectors.html_comment_block(
        start_text: open.delete_prefix("<!-- ").delete_suffix(" -->"),
        end_text: close.delete_prefix("<!-- ").delete_suffix(" -->"),
        span: :outermost,
        limit: {none_or_one: true}
      )
      target.locate_matches(context).first&.slice_from(content.to_s)
    end

    def markdown_sections(content)
      lines = content.to_s.split("\n", -1)
      markdown_heading_owners(content, source_label: "README.md").map do |owner|
        start = owner.location.start_line - 1
        branch_end = owner.location.end_line - 1
        body = (lines[(start + 1)..branch_end] || []).join("\n")
        {
          start: start,
          level: owner.level,
          heading: owner.heading_source,
          heading_text: owner.heading_text,
          base: owner.base,
          end: branch_end,
          body: body
        }
      end
    end

    def readme_preserve_targets(template_sections, destination_lookup, preserve_config)
      sections = if preserve_config.key?(:sections)
        Array(preserve_config[:sections]).map { |section| normalize_readme_heading(section) }
      else
        README_DEFAULT_PRESERVE_SECTIONS.dup
      end
      patterns = if preserve_config.key?(:patterns)
        Array(preserve_config[:patterns]).map { |pattern| pattern.to_s.strip.downcase }
      else
        README_DEFAULT_PRESERVE_PATTERNS.dup
      end
      aliases = preserve_config[:aliases] || README_SECTION_ALIASES
      targets = sections.dup
      template_sections.each do |section|
        base = section.fetch(:base)
        targets << base if patterns.any? { |pattern| File.fnmatch?(pattern, base, File::FNM_PATHNAME) }
      end
      aliases.each do |from, to|
        targets << to if destination_lookup.key?(from) && targets.include?(to)
      end
      targets.uniq
    end

    def aliased_readme_destination_section(template_base, destination_lookup, preserve_config)
      aliases = preserve_config[:aliases] || README_SECTION_ALIASES
      aliases.each do |from, to|
        return destination_lookup[from] if to == template_base && destination_lookup.key?(from)
      end
      nil
    end

    def readme_preserve_config(config)
      readme = config["readme"]
      return {} unless readme.is_a?(Hash)

      result = {}
      result[:sections] = Array(readme["preserve_sections"]) if readme.key?("preserve_sections")
      result[:patterns] = Array(readme["preserve_patterns"]) if readme.key?("preserve_patterns")
      if readme["section_aliases"].is_a?(Hash)
        result[:aliases] = README_SECTION_ALIASES.merge(
          readme["section_aliases"].transform_keys { |key| normalize_readme_heading(key) }
                                   .transform_values { |value| normalize_readme_heading(value) }
        )
      end
      result
    end

    def normalize_readme_heading(text)
      strip_readme_heading_adornment(text).strip.downcase
    end

    def semantic_readme_heading(text)
      normalize_readme_heading(text)
    end

    def strip_readme_heading_adornment(text)
      text.to_s.sub(/\A(?:\d\uFE0F?\u20E3|[^[:alnum:][:space:]])+[ \t]*/u, "")
    end

    def template_source_preferences(project_root, config, opencollective_disabled: false, include_patterns: nil)
      templates = template_activation_config(config)
      return [] unless templates.is_a?(Hash)

      root = template_root(project_root, templates)
      entries = template_entries(project_root, root, templates)
      return [] if entries.empty?

      apply_templates = templates["apply"] == true
      entries.filter_map do |entry|
        template_source_preference(
          project_root,
          root,
          entry,
          config,
          opencollective_disabled: opencollective_disabled,
          include_patterns: include_patterns,
          apply_templates: apply_templates
        )
      end
    end

    def existing_simplecov_bootstrap_template_preferences(project_root, config, preferences)
      templates = template_activation_config(config)
      return [] unless templates.is_a?(Hash)

      root = template_root(project_root, templates)
      return [] unless root.fetch(:kind) == "packaged"

      configured_paths = preferences.map { |preference| preference.fetch(:target_path).to_s }.to_set
      SIMPLECOV_BOOTSTRAP_TEMPLATE_PATHS.filter_map do |target_path|
        next if configured_paths.include?(target_path)
        next unless File.exist?(File.join(project_root, target_path))

        selected_source = preferred_template_source(root.fetch(:path), target_path)
        next unless selected_source

        {
          target_path: target_path,
          configured_source: target_path,
          selected_source: template_source_display_path(root, selected_source),
          selection_reason: template_source_selection_reason(target_path, template_source_display_path(root, selected_source)),
          apply: templates["apply"] == true,
          strategy: "merge",
          preference: "template",
          add_template_only_nodes: true,
          freeze_token: config.dig("defaults", "freeze_token").to_s.empty? ? "kettle-jem" : config.dig("defaults", "freeze_token").to_s,
          source_relative_path: selected_source,
          source_root: root.fetch(:kind),
          source_root_path: root.fetch(:path),
          migration: "simplecov_bootstrap"
        }
      end
    end

    def template_runtime_config(config, facts, license: {})
      result = deep_dup(config)
      result["rubygems"] = {} unless result["rubygems"].is_a?(Hash)
      result["rubygems"]["min_ruby"] ||= facts.dig(:rubygems, :min_ruby)
      result["ruby"] = {} unless result["ruby"].is_a?(Hash)
      result["ruby"]["test_minimum"] = config_test_min_ruby(result, facts.dig(:rubygems, :min_ruby)).to_s
      result["resolved_licenses"] = license[:spdx]
      if facts[:template_profile].to_s == SHIM_TEMPLATE_PROFILE
        result["templates"] = default_template_config.merge(result["templates"].is_a?(Hash) ? result["templates"] : {})
        result["templates"]["profile"] = SHIM_TEMPLATE_PROFILE
        result["templates"]["entries"] = shim_template_entries(facts, result)
        result["templates"]["entries"].each do |entry|
          target = entry.fetch("target").to_s

          set_template_file_strategy!(result, target, "accept_template")
        end
      end
      result
    end

    def set_template_file_strategy!(config, target_path, strategy)
      config["files"] = {} unless config["files"].is_a?(Hash)
      current = config["files"]
      target_path.to_s.split("/").each do |part|
        current[part] = {} unless current[part].is_a?(Hash)
        current = current[part]
      end
      current["strategy"] = strategy
    end

    def template_activation_config(config)
      return config["templates"] if config["templates"].is_a?(Hash)
      return default_template_config if generated_kettle_config_without_templates?(config)

      nil
    end

    def generated_kettle_config_without_templates?(config)
      return false unless config.is_a?(Hash)

      config["tokens"].is_a?(Hash)
    end

    def template_entries(project_root, root, templates)
      return templates["entries"] if templates["entries"].is_a?(Array)
      return [] if templates.key?("entries")

      template_inventory_entries(project_root, root.fetch(:path), templates: templates)
    end

    def shim_template_entries(facts, config)
      package_name = facts.dig(:package, :name).to_s
      entrypoint_require = facts.dig(:rubygems, :entrypoint_require).to_s
      shim = facts.fetch(:shim)
      targets = SHIM_TEMPLATE_STATIC_ENTRIES.map do |target|
        source = SHIM_TEMPLATE_SOURCE_TARGETS.fetch(target, target)
        {"source" => source, "target" => target}
      end
      targets << {"source" => "shim/gem.gemspec", "target" => "#{package_name}.gemspec"}
      targets << {"source" => "shim/lib/version.rb", "target" => File.join("lib", entrypoint_require, "version.rb")}
      targets << {"source" => "shim/lib/entrypoint.rb", "target" => File.join("lib", "#{entrypoint_require}.rb")}
      Array(shim[:legacy_requires]).map(&:to_s).reject { |path| path == entrypoint_require }.each do |require_path|
        targets << {"source" => "shim/lib/compat_require.rb", "target" => File.join("lib", "#{require_path}.rb")}
      end
      targets.uniq { |entry| entry.fetch("target") }
    end

    def template_inventory_entries(project_root, template_root_path, templates: {})
      logical_paths = []
      include_shim_templates = normalize_template_profile(templates["profile"]) == SHIM_TEMPLATE_PROFILE
      Find.find(template_root_path) do |path|
        next if File.directory?(path)

        relative_path = path.delete_prefix("#{template_root_path}/")
        logical_path = relative_path
          .sub(/\.no-osc\.example\z/, "")
          .sub(/\.example\z/, "")
        next if logical_path.start_with?("readme/partials/")
        next if logical_path.start_with?("shim/") && !include_shim_templates
        next if logical_path == "gemfiles/modular/shunted.gemfile"
        next if logical_path == TRANSFER_CHANGELOG_TEMPLATE_PATH

        logical_paths << logical_path unless logical_path.empty?
      end

      logical_paths.uniq.sort.map do |logical_path|
        target_path = template_inventory_target_path(project_root, logical_path)
        if target_path == logical_path
          logical_path
        else
          {"source" => logical_path, "target" => target_path}
        end
      end
    end

    def template_inventory_target_path(project_root, logical_path)
      return ".env.local.example" if logical_path == ".env.local"

      if VERSION_GEM_TEMPLATE_SOURCES.include?(logical_path)
        existing_gemspec = Dir.glob(File.join(project_root, "*.gemspec")).min
        return version_gem_template_target_path_for_project(project_root, File.basename(existing_gemspec), logical_path) if existing_gemspec
      end

      if logical_path.end_with?(".gemspec")
        existing_gemspec = Dir.glob(File.join(project_root, "*.gemspec")).min
        return File.basename(existing_gemspec) if existing_gemspec
      end

      logical_path
    end

    def copy_only_when_missing_template_path?(relative_path)
      COPY_ONLY_WHEN_MISSING_TEMPLATE_PATHS.include?(relative_path.to_s)
    end

    def default_template_strategy_config(template_root, target_path)
      return unless template_root.fetch(:kind) == "packaged"
      return {strategy: :merge, preference: :destination, add_template_only_nodes: true} if target_path.to_s == KETTLE_CONFIG_PATH
      return {strategy: :merge, preference: :destination, add_template_only_nodes: true} if target_path.to_s == ".gitignore"
      return {strategy: :accept_template} if target_path.to_s == "CITATION.cff"
      return {strategy: :merge, preference: :destination, add_template_only_nodes: true} if target_path.to_s == "Rakefile"
      return {strategy: :accept_template} if version_gem_template_target_path?(target_path)
      return {strategy: :accept_template} if target_path.to_s.start_with?(".github/workflows/")
      return {strategy: :accept_template} if target_path.to_s.start_with?("gemfiles/modular/")

      nil
    end

    def version_gem_template_target_path?(target_path)
      target = target_path.to_s
      target.end_with?("/version.rb", "/version.rbs")
    end

    def inactive_packaged_template_cleanup_files(project_root, config = {})
      gemfile_cleanups = Dir.glob(File.join(project_root, "gemfiles/**/*.gemfile")).filter_map do |path|
        relative_path = path.delete_prefix("#{project_root}/")
        next unless preferred_template_source(PACKAGED_TEMPLATE_ROOT, relative_path)

        {target_path: relative_path} if skip_packaged_gemfile_template?(relative_path, config, project_root: project_root)
      end
      (gemfile_cleanups + disabled_integration_config_cleanups(project_root, config)).sort_by { |cleanup| cleanup.fetch(:target_path) }
    end

    def shim_profile_cleanups(project_root, facts, preferences, template_selection: {})
      return [] unless facts[:template_profile].to_s == SHIM_TEMPLATE_PROFILE
      return [] unless Array(template_selection[:only]).empty?

      retained_paths = preferences.map { |preference| preference.fetch(:target_path).to_s }.to_set
      retained_paths << KETTLE_CONFIG_PATH
      SHIM_PROFILE_CLEANUP_GLOBS.flat_map do |pattern|
        Dir.glob(File.join(project_root, pattern), File::FNM_DOTMATCH).filter_map do |path|
          next unless File.file?(path)

          relative_path = path.delete_prefix("#{project_root}/")
          next if retained_paths.include?(relative_path)
          next if relative_path.start_with?(".git/")

          {target_path: relative_path}
        end
      end.uniq { |cleanup| cleanup.fetch(:target_path) }.sort_by { |cleanup| cleanup.fetch(:target_path) }
    end

    def kettle_config_bootstrap_facts(project_root, env, template_selection: {})
      return if File.exist?(File.join(project_root, KETTLE_CONFIG_PATH))
      return if File.exist?(File.join(project_root, LEGACY_KETTLE_CONFIG_PATH))

      selected_source = preferred_template_source(PACKAGED_TEMPLATE_ROOT, KETTLE_CONFIG_PATH)
      return unless selected_source

      {
        template_preference: {
          target_path: KETTLE_CONFIG_PATH,
          configured_source: KETTLE_CONFIG_PATH,
          selected_source: selected_source,
          source_relative_path: selected_source,
          source_root: "packaged",
          source_root_path: PACKAGED_TEMPLATE_ROOT,
          selection_reason: template_source_selection_reason(KETTLE_CONFIG_PATH, selected_source),
          apply: true
        },
        min_divergence_threshold: preferred_template_token_value(nil, nil, env, "KJ_MIN_DIVERGENCE_THRESHOLD").to_s,
        template_profile: template_selection[:template_profile].to_s
      }.compact
    end

    def kettle_config_bootstrap_recipe(bootstrap)
      recipe = recipe_entry(
        "kettle_config_bootstrap",
        KETTLE_CONFIG_PATH,
        "yaml",
        "supplied_kettle_config_bootstrap",
        facts: %w[kettle_config_bootstrap]
      )
      recipe[:template_preference] = bootstrap.fetch(:template_preference)
      recipe[:template_tokens] = {
        "KJ|MIN_DIVERGENCE_THRESHOLD" => bootstrap.fetch(:min_divergence_threshold).to_s,
        "KJ|MIN_RUBY" => bootstrap[:min_ruby].to_s,
        "KJ|MIN_TEST_RUBY" => bootstrap[:test_min_ruby].to_s,
        "KJ|YARD_HOST" => bootstrap[:yard_host].to_s,
        "KJ|HOMEPAGE_URI" => bootstrap[:homepage_uri].to_s,
        "KJ|RUBYFORUM:FAMILY_TAG" => bootstrap.dig(:rubyforum, :family_tag).to_s,
        "KJ|RUBYFORUM:PROJECT_TAG" => bootstrap.dig(:rubyforum, :project_tag).to_s
      }
      recipe[:bootstrap_licenses] = Array(bootstrap[:licenses]).map(&:to_s).reject(&:empty?)
      recipe[:bootstrap_template_profile] = bootstrap[:template_profile].to_s unless bootstrap[:template_profile].to_s.empty?
      recipe[:bootstrap_gemspec_path] = bootstrap[:gemspec_path].to_s unless bootstrap[:gemspec_path].to_s.empty?
      recipe[:bootstrap_project_emoji] = bootstrap[:project_emoji].to_s unless bootstrap[:project_emoji].to_s.empty?
      recipe[:bootstrap_rubyforum] = bootstrap[:rubyforum] if bootstrap[:rubyforum].is_a?(Hash)
      recipe[:bootstrap_shim] = bootstrap[:shim] if bootstrap[:shim].is_a?(Hash)
      recipe
    end

    def template_source_preference(project_root, template_root, entry, config, opencollective_disabled: false, include_patterns: nil, apply_templates: false)
      source_path, target_path = template_entry_paths(entry)
      if template_root.fetch(:kind) == "packaged" && VERSION_GEM_TEMPLATE_SOURCES.include?(source_path) && target_path == source_path
        existing_gemspec = Dir.glob(File.join(project_root, "*.gemspec")).min
        target_path = version_gem_template_target_path_for_project(project_root, File.basename(existing_gemspec), source_path) if existing_gemspec
      end
      return if source_path.to_s.empty? || target_path.to_s.empty?
      return if skip_packaged_workflow_template?(target_path, config, include_patterns: include_patterns)
      return if skip_disabled_integration_template?(target_path, config)
      return if skip_packaged_gemfile_template?(target_path, config, project_root: project_root, template_root_path: template_root.fetch(:path))
      return if skip_packaged_license_template?(target_path, config)
      return if skip_packaged_version_gem_entrypoint_template?(project_root, source_path, target_path, config)
      return if template_root.fetch(:kind) == "packaged" && opencollective_disabled && opencollective_disabled_file?(target_path)

      selected_source = preferred_template_source(template_root.fetch(:path), source_path, opencollective_disabled: opencollective_disabled)
      return unless selected_source

      strategy_config = if template_root.fetch(:kind) == "packaged" && target_path.to_s == KETTLE_CONFIG_PATH
        default_template_strategy_config(template_root, target_path)
      else
        template_strategy_config(config, target_path) ||
          default_template_strategy_config(template_root, target_path)
      end
      preference = {
        target_path: target_path,
        configured_source: source_path,
        selected_source: template_source_display_path(template_root, selected_source),
        selection_reason: template_source_selection_reason(source_path, template_source_display_path(template_root, selected_source)),
        apply: template_entry_apply?(entry, apply_templates)
      }
      preference[:strategy] = strategy_config.fetch(:strategy).to_s if strategy_config
      if strategy_config
        %i[file_type preference freeze_token method_move_policy max_recursion_depth comment_merge_policy].each do |key|
          preference[key] = strategy_config.fetch(key).to_s if strategy_config.key?(key)
        end
        preference[:add_template_only_nodes] = strategy_config.fetch(:add_template_only_nodes) if strategy_config.key?(:add_template_only_nodes)
        preference[:skip_unresolved_scan] = strategy_config.fetch(:skip_unresolved_scan) if strategy_config.key?(:skip_unresolved_scan)
      end
      if copy_only_when_missing_template_path?(target_path) && File.exist?(File.join(project_root, target_path))
        preference[:strategy] = "keep_destination"
        preference[:policy] = "copy_only_when_missing"
      end
      preserve_config = readme_preserve_config(config)
      preference[:readme_preserve_config] = preserve_config if target_path == "README.md" && !preserve_config.empty?
      if template_root.fetch(:kind) == "packaged"
        preference[:source_relative_path] = selected_source
        preference[:source_root] = template_root.fetch(:kind)
        preference[:source_root_path] = template_root.fetch(:path)
      end
      preference
    end

    def skip_packaged_version_gem_entrypoint_template?(project_root, source_path, target_path, config)
      return false unless source_path == "lib/gem/version_gem.rb"
      return true unless version_gem_runtime_compatible?({rubygems: {min_ruby: config.dig("rubygems", "min_ruby")}})

      mode = rubygems_version_gem_entrypoint_mode(config.fetch("rubygems", {}))
      return true if mode == "disabled" || mode == "inline"
      return false if mode == "dedicated"

      !File.file?(File.join(project_root, target_path))
    end

    def template_legacy_destination_cleanups(project_root, preferences)
      preferences.filter_map do |preference|
        canonical_path = preference.fetch(:target_path)
        legacy_path = LEGACY_DESTINATION_PATHS[canonical_path]
        next unless legacy_path
        next unless File.exist?(File.join(project_root, legacy_path))
        next if preference[:strategy] == "keep_destination" && !File.exist?(File.join(project_root, canonical_path))

        {
          canonical_path: canonical_path,
          legacy_path: legacy_path
        }
      end
    end

    def template_obsolete_license_cleanups(project_root, config, preferences, license_txt: {})
      active_basenames = active_license_basenames(config)
      return [] if active_basenames.empty?

      retained_paths = preferences.map { |preference| preference.fetch(:target_path) }.to_set
      cleanups = known_license_template_basenames.filter_map do |basename|
        license_path = "#{basename}.md"
        next if active_basenames.include?(basename)
        next if retained_paths.include?(license_path)
        next unless File.exist?(File.join(project_root, license_path))

        {license_path: license_path, license_basename: basename}
      end
      if license_txt[:mit] && retained_paths.include?("LICENSE.md") && File.exist?(File.join(project_root, "LICENSE.txt"))
        cleanups << {license_path: "LICENSE.txt", license_basename: "LICENSE"}
      end
      cleanups
    end

    def template_strategy_config(config, target_path)
      template_file_strategy_config(config, target_path) || template_pattern_strategy_config(config, target_path)
    end

    def template_file_strategy_config(config, target_path)
      files = config["files"]
      return unless files.is_a?(Hash)

      current = files
      parts = target_path.to_s.delete_prefix("./").split("/")
      until parts.empty?
        part = parts.shift
        return unless current.is_a?(Hash) && current.key?(part)

        current = current[part]
      end
      return unless current.is_a?(Hash) && current.key?("strategy")

      template_strategy_entry(config, nil, current)
    end

    def template_pattern_strategy_config(config, target_path)
      patterns = config["patterns"]
      return unless patterns.is_a?(Array)

      match = patterns.find do |entry|
        entry.is_a?(Hash) &&
          File.fnmatch?(entry["path"].to_s, target_path.to_s, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
      end
      return unless match

      template_strategy_entry(config, match["path"].to_s, match)
    end

    def template_strategy_entry(config, path, entry)
      strategy = entry["strategy"].to_s.strip.downcase.to_sym
      raise ArgumentError, "unknown kettle-jem template strategy: #{entry["strategy"]}" unless SUPPORTED_TEMPLATE_STRATEGIES.include?(strategy)

      result = {strategy: strategy}
      result[:path] = path if path
      result[:skip_unresolved_scan] = true if entry["skip_unresolved_scan"]
      if entry.key?("file_type")
        file_type = entry["file_type"].to_s.strip.downcase.tr("-", "_").to_sym
        raise ArgumentError, "unknown kettle-jem template file_type: #{entry["file_type"]}" unless SUPPORTED_TEMPLATE_FILE_TYPES.include?(file_type)

        result[:file_type] = file_type
      end
      if strategy == :merge
        defaults = config["defaults"].is_a?(Hash) ? config["defaults"] : {}
        result[:preference] = (entry.key?("preference") ? entry["preference"] : defaults["preference"]).to_s if entry.key?("preference") || defaults.key?("preference")
        if entry.key?("add_template_only_nodes") || defaults.key?("add_template_only_nodes")
          result[:add_template_only_nodes] = entry.key?("add_template_only_nodes") ? entry["add_template_only_nodes"] : defaults["add_template_only_nodes"]
        end
        result[:freeze_token] = (entry.key?("freeze_token") ? entry["freeze_token"] : defaults["freeze_token"]).to_s if entry.key?("freeze_token") || defaults.key?("freeze_token")
        result[:max_recursion_depth] = (entry.key?("max_recursion_depth") ? entry["max_recursion_depth"] : defaults["max_recursion_depth"]).to_s if entry.key?("max_recursion_depth") || defaults.key?("max_recursion_depth")
        if entry.key?("method_move_policy") || defaults.key?("method_move_policy")
          policy = (entry.key?("method_move_policy") ? entry["method_move_policy"] : defaults["method_move_policy"]).to_s
          raise ArgumentError, "unknown kettle-jem Ruby method_move_policy: #{policy}" unless SUPPORTED_RUBY_METHOD_MOVE_POLICIES.include?(policy)

          result[:method_move_policy] = policy
        end
        if entry.key?("comment_merge_policy") || defaults.key?("comment_merge_policy")
          policy = (entry.key?("comment_merge_policy") ? entry["comment_merge_policy"] : defaults["comment_merge_policy"]).to_s.strip.downcase.tr("-", "_")
          raise ArgumentError, "unknown kettle-jem YAML comment_merge_policy: #{policy}" unless SUPPORTED_YAML_COMMENT_MERGE_POLICIES.include?(policy)

          result[:comment_merge_policy] = policy
        end
      end
      result
    end

    def template_root(project_root, templates)
      configured_root = templates["root"].to_s
      if configured_root.empty?
        local_root = File.join(project_root, "template")
        return {kind: "project", path: local_root, display_prefix: "template"} if Dir.exist?(local_root)

        return {kind: "packaged", path: PACKAGED_TEMPLATE_ROOT}
      end

      return {kind: "packaged", path: PACKAGED_TEMPLATE_ROOT} if configured_root == "packaged"

      path = configured_root.start_with?("/") ? configured_root : File.join(project_root, configured_root)
      {kind: "project", path: path, display_prefix: configured_root}
    end

    def default_template_config
      {
        "root" => "packaged",
        "apply" => true
      }
    end

    def skip_packaged_license_template?(target_path, config)
      basename = managed_license_template_basename(target_path)
      return false unless basename

      active_basenames = active_license_basenames(config)
      return false if active_basenames.empty?

      !active_basenames.include?(basename)
    end

    def managed_license_template_basename(target_path)
      path = target_path.to_s
      return unless path.end_with?(".md")

      basename = File.basename(path, ".md")
      return if NON_LICENSE_MD_BASENAMES.include?(basename)

      known_license_template_basenames.include?(basename) ? basename : nil
    end

    def known_license_template_basenames
      KNOWN_LICENSE_TEMPLATE_BASENAMES
    end

    def active_license_basenames(config)
      Array(config["resolved_licenses"])
        .map { |license| spdx_basename(license) }
        .reject(&:empty?)
        .to_set
    end

    def skip_packaged_workflow_template?(target_path, config, include_patterns: nil)
      path = target_path.to_s
      return false unless path.start_with?(".github/workflows/")
      return true if disabled_integration_template_path?(path, config)
      return true if OPT_IN_GITHUB_WORKFLOWS.include?(path) && !selected_template_path?(path, Array(include_patterns))

      basename = File.basename(path, ".yml")
      if basename == "framework-ci"
        matrix = github_actions_framework_matrix(config)
        return matrix.empty? || !matrix.fetch(:workflow, true)
      end

      min_ruby = config_test_min_ruby(config)
      workflow_floor = Kettle::Rb::CompatMatrix.workflow_ruby_floor(basename)
      return true if workflow_floor && min_ruby && Gem::Version.new(workflow_floor) < min_ruby

      engine = Kettle::Rb::CompatMatrix.engine_workflow(basename)
      return true if engine && !enabled_ruby_engines(config).include?(engine)

      version = basename[/\Aruby-(\d+\.\d+)\z/, 1]
      return false unless version && min_ruby
      Gem::Version.new(version) < min_ruby
    end

    def skip_packaged_gemfile_template?(target_path, config, project_root: nil, template_root_path: PACKAGED_TEMPLATE_ROOT)
      return true if target_path.to_s.include?("gemfiles/modular/recording/") && !appraisal_recording_enabled?(config)

      return false if packaged_gemfile_referenced_by_x_std_libs?(target_path, project_root: project_root, template_root_path: template_root_path)

      version = packaged_gemfile_template_ruby_floor(target_path)
      return false unless version

      min_ruby = config_test_min_ruby(config)
      return false unless min_ruby

      Gem::Version.new(version) < min_ruby
    end

    def packaged_gemfile_referenced_by_x_std_libs?(target_path, project_root:, template_root_path:)
      relative_path = target_path.to_s.delete_prefix("gemfiles/modular/")
      return false unless relative_path.start_with?("x_std_libs/")

      aggregate_paths = [
        File.join(template_root_path.to_s, "gemfiles/modular/x_std_libs.gemfile.example"),
        File.join(project_root.to_s, "gemfiles/modular/x_std_libs.gemfile")
      ].select { |path| File.file?(path) }
      aggregate_paths.any? do |path|
        gemfile_eval_paths(File.read(path)).include?(relative_path)
      end
    rescue
      false
    end

    def skip_disabled_integration_template?(target_path, config)
      disabled_integration_template_path?(target_path, config)
    end

    def disabled_integration_config_cleanups(project_root, config)
      disabled_integrations(config).flat_map do |integration|
        INTEGRATION_TEMPLATE_PATHS.fetch(integration, []).filter_map do |relative_path|
          next if relative_path.start_with?(".github/workflows/")
          next unless File.exist?(File.join(project_root, relative_path))

          {target_path: relative_path}
        end
      end
    end

    def disabled_integration_template_path?(target_path, config)
      disabled = disabled_integrations(config)
      return false if disabled.empty?

      path = target_path.to_s
      disabled.any? { |integration| INTEGRATION_TEMPLATE_PATHS.fetch(integration, []).include?(path) }
    end

    def packaged_gemfile_template_ruby_floor(target_path)
      path = target_path.to_s
      if (match = path.match(%r{\Agemfiles/ruby_(\d+)_(\d+)\.gemfile\z}))
        return "#{match[1]}.#{match[2]}"
      end

      path[%r{(?:\A|/)r(\d+\.\d+)(?:/|\z)}, 1]
    end

    def enabled_ruby_engines(config)
      engines = ruby_engines_config(config)
      (engines.nil? || engines.empty?) ? DEFAULT_ENGINES : engines
    end

    def config_min_ruby(config)
      value = config.dig("rubygems", "min_ruby") || config["min_ruby"]
      version = value.to_s[/\d+\.\d+(?:\.\d+)?/]
      version && Gem::Version.new(version)
    end

    def config_test_min_ruby(config, gem_min_ruby = nil)
      config ||= {}
      configured = config.dig("ruby", "test_minimum")
      configured_version = configured.to_s[/\d+\.\d+(?:\.\d+)?/]
      test_minimum = configured_version ? Gem::Version.new(configured_version) : DEFAULT_TEST_MINIMUM_RUBY
      test_minimum = [test_minimum, DEFAULT_TEST_MINIMUM_RUBY].max
      gem_minimum = if gem_min_ruby
        token = minimum_ruby_token(gem_min_ruby)
        Gem::Version.new(token) unless token.empty?
      else
        config_min_ruby(config)
      end
      gem_minimum ? [test_minimum, gem_minimum].max : test_minimum
    rescue ArgumentError
      DEFAULT_TEST_MINIMUM_RUBY
    end

    def template_source_display_path(template_root, selected_source)
      prefix = template_root[:display_prefix].to_s
      return selected_source if prefix.empty?

      File.join(prefix, selected_source)
    end

    def template_entry_paths(entry)
      if entry.is_a?(Hash)
        source_path = entry.fetch("source", entry["target"]).to_s
        target_path = entry.fetch("target", source_path.sub(/\.example\z/, "")).to_s
        [source_path, target_path]
      else
        source_path = entry.to_s
        [source_path, source_path.sub(/\.example\z/, "")]
      end
    end

    def template_entry_apply?(entry, apply_templates)
      return entry["apply"] == true if entry.is_a?(Hash) && entry.key?("apply")

      apply_templates
    end

    def preferred_template_source(template_root, configured_source, opencollective_disabled: false)
      base = configured_source.sub(/\.example\z/, "")
      candidates = []
      candidates << "#{base}.no-osc.example" if opencollective_disabled && base != "README.md"
      candidates << "#{base}.example"
      candidates << configured_source
      candidates.find { |relative_path| File.exist?(File.join(template_root, relative_path)) }
    end

    def template_source_selection_reason(configured_source, selected_source)
      if selected_source.end_with?(".no-osc.example")
        "opencollective_disabled_no_osc_variant"
      elsif selected_source.end_with?(".example")
        "default_example_variant"
      elsif selected_source == configured_source
        "configured_source"
      else
        "fallback_source"
      end
    end

    def github_actions_framework_matrix(config)
      workflows = config["workflows"]
      return {} unless workflows.is_a?(Hash) && workflows["preset"].to_s.strip.downcase == "framework"

      raw = workflows["framework_matrix"]
      return {} unless raw.is_a?(Hash)

      dimension = raw["dimension"].to_s.strip
      versions = raw["versions"]
      pattern = raw["gemfile_pattern"].to_s.strip
      return {} unless !dimension.empty? && versions.is_a?(Array) && !versions.empty? && !pattern.empty?

      framework_gem = raw.fetch("gem", dimension).to_s.strip
      return {} if framework_gem.empty?

      version_entries = versions.filter_map { |version| framework_matrix_version_entry(version) }
      return {} if version_entries.empty?

      appraisal_gemfiles = framework_matrix_appraisal_gemfiles(raw)
      gemfiles = version_entries.map do |entry|
        gemfile = expand_framework_gemfile_pattern(pattern, entry.fetch(:slug))
        gemfile_entry = {
          path: framework_gemfile_path(gemfile),
          gem: framework_gem,
          requirement: entry.fetch(:requirement),
          env: entry.fetch(:env, {})
        }
        gemfile_entry[:default] = true if entry[:default]
        gemfile_entry[:replaces] = entry[:replaces] unless entry.fetch(:replaces, []).empty?
        gemfile_entry
      end.uniq { |entry| entry.fetch(:path) }
      default_gemfiles = gemfiles.select { |entry| entry[:default] }
      gemfiles.reject! { |entry| template_keep_destination_path?(config, entry.fetch(:path)) }
      {
        dimension: dimension,
        gem: framework_gem,
        workflow: framework_matrix_workflow_enabled?(raw),
        versions: version_entries.map { |entry| entry.fetch(:label) },
        gemfile_pattern: pattern,
        include: version_entries.map do |entry|
          {
            framework_version: entry.fetch(:label),
            appraisal: entry[:appraisal_name] || framework_matrix_appraisal_name(dimension, entry.fetch(:slug))
          }
        end,
        gemfiles: gemfiles,
        appraisals: version_entries.map do |entry|
          gemfile = framework_gemfile_path(expand_framework_gemfile_pattern(pattern, entry.fetch(:slug)))
          name = entry[:appraisal_name] || framework_matrix_appraisal_name(dimension, entry.fetch(:slug))
          {
            name: name,
            framework_version: entry.fetch(:label),
            gem: framework_gem,
            env: entry.fetch(:env, {}),
            standard_appraisal: entry.fetch(:standard_appraisal, false),
            eval_gemfiles: [framework_matrix_appraisal_gemfile_path(gemfile), *appraisal_gemfiles].uniq,
            replaces: framework_matrix_replaced_appraisal_names(dimension, entry, name)
          }
        end
      }.tap do |matrix|
        matrix[:default_gemfiles] = default_gemfiles unless default_gemfiles.empty?
      end
    end

    def framework_matrix_replaced_appraisal_names(dimension, entry, name)
      default_name = framework_matrix_appraisal_name(dimension, entry.fetch(:slug))
      return [] if default_name == name

      [default_name]
    end

    def framework_matrix_workflow_enabled?(raw)
      configured = raw["workflow"]
      configured = raw["generate_workflow"] if configured.nil?
      configured = raw["ci"] if configured.nil?
      return true if configured.nil?

      DecisionPolicy.value_to_boolean(configured) != false
    end

    def framework_matrix_appraisal_gemfiles(raw)
      Array(raw["appraisal_gemfiles"] || raw["appraisal_eval_gemfiles"]).filter_map do |path|
        normalized = framework_matrix_appraisal_gemfile_path(path.to_s.strip)
        normalized unless normalized.empty?
      end
    end

    def framework_matrix_appraisal_gemfile_path(path)
      path.to_s.sub(%r{\Agemfiles/}, "")
    end

    def framework_matrix_appraisal_name(dimension, slug)
      [dimension, slug].join("-").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
    end

    def framework_matrix_version_entry(raw)
      if raw.is_a?(Hash)
        label = raw.fetch("label", raw["version"]).to_s.strip
        slug = raw.fetch("slug", label).to_s.strip
        requirement = raw.fetch("requirement", default_framework_matrix_requirement(label)).to_s.strip
        appraisal_name = (raw["appraisal"] || raw["appraisal_name"] || raw["standard_appraisal"]).to_s.strip
        env = framework_matrix_env(raw["env"])
        default = DecisionPolicy.value_to_boolean(raw["default"]) == true
        replaces = Array(raw["replaces"]).filter_map { |name| nonempty_string(name) }
      else
        label = raw.to_s.strip
        slug = label
        requirement = default_framework_matrix_requirement(label)
        appraisal_name = ""
        env = {}
        default = false
        replaces = []
      end
      return if label.empty? || slug.empty? || requirement.empty?

      entry = {
        label: label,
        slug: slug,
        requirement: requirement
      }
      entry[:appraisal_name] = appraisal_name unless appraisal_name.empty?
      entry[:standard_appraisal] = true if raw.is_a?(Hash) && raw["standard_appraisal"]
      entry[:env] = env unless env.empty?
      entry[:default] = true if default
      entry[:replaces] = replaces unless replaces.empty?
      entry
    end

    # Configures the dependencies used by `bundle exec kettle-test` without a
    # BUNDLE_GEMFILE override. This intentionally does not alter Appraisals or
    # CI matrices: those are owned by appraisal_matrix/framework_matrix.
    def default_test_bundle_config(config, framework_matrix)
      raw = config["test_bundle"]
      raw = {} unless raw.is_a?(Hash)

      gemfiles = Array(raw["gemfiles"]).filter_map { |entry| default_test_bundle_gemfile_entry(entry) }
      gems = Array(raw["gems"]).filter_map { |entry| default_test_bundle_gem_entry(entry) }
      framework_defaults = framework_matrix.to_h.fetch(:default_gemfiles, []).select { |entry| entry[:default] }
      if framework_defaults.length > 1
        paths = framework_defaults.map { |entry| entry.fetch(:path) }.join(", ")
        raise ArgumentError, "workflows.framework_matrix has multiple default versions: #{paths}"
      end
      if (framework_default = framework_defaults.first)
        gemfiles << {
          path: framework_default.fetch(:path),
          replaces: framework_default.fetch(:replaces, [])
        }
      end

      return {} if gemfiles.empty? && gems.empty?

      {
        gemfiles: gemfiles.map { |entry| entry.fetch(:path) }.uniq,
        gems: gems,
        managed_gems: (gems.map { |entry| entry.fetch(:name) } + gemfiles.flat_map { |entry| entry.fetch(:replaces, []) }).uniq
      }
    end

    def default_test_bundle_gemfile_entry(raw)
      if raw.is_a?(Hash)
        path = raw["path"].to_s.strip
        replaces = Array(raw["replaces"]).filter_map { |name| nonempty_string(name) }
      else
        path = raw.to_s.strip
        replaces = []
      end
      return if path.empty?

      {path: path.start_with?("gemfiles/") ? path : "gemfiles/#{path}", replaces: replaces}
    end

    def default_test_bundle_gem_entry(raw)
      return unless raw.is_a?(Hash)

      name = (raw["name"] || raw["gem"]).to_s.strip
      return if name.empty?

      requirements = raw.key?("requirements") ? Array(raw["requirements"]) : [raw["requirement"]]
      entry = {
        name: name,
        requirements: requirements.filter_map { |requirement| nonempty_string(requirement) }
      }
      require_value = DecisionPolicy.value_to_boolean(raw["require"])
      entry[:require] = false if require_value == false
      entry
    end

    def nonempty_string(value)
      normalized = value.to_s.strip
      normalized unless normalized.empty?
    end

    def framework_matrix_env(raw)
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(key, value), result|
        name = key.to_s.strip
        next if name.empty?

        result[name] = value.to_s
      end
    end

    def template_keep_destination_path?(config, target_path)
      strategy = template_file_strategy_config(config, target_path) || template_pattern_strategy_config(config, target_path)
      strategy.to_h.fetch(:strategy, nil) == :keep_destination
    end

    def default_framework_matrix_requirement(version)
      normalized = version.to_s
      normalized = "#{normalized}.0" if normalized.match?(/\A\d+\.\d+\z/)
      "~> #{normalized}"
    end

    def github_actions_coverage_config(config, env = ENV)
      workflows = config["workflows"]
      return {} unless workflows.is_a?(Hash)

      raw = workflows["coverage"]
      enabled = raw == true || (raw.is_a?(Hash) && raw.fetch("enabled", false) == true)
      return {} unless enabled

      raw = {} unless raw.is_a?(Hash)
      {
        enabled: true,
        command: raw.fetch("command", github_actions_exec_cmd(config, env)).to_s,
        appraisal: raw.fetch("appraisal", "coverage").to_s
      }
    end

    def github_actions_exec_cmd(config, env)
      workflows = config["workflows"]
      workflows = {} unless workflows.is_a?(Hash)

      normalize_github_actions_exec_cmd(
        preferred_template_token_value("kettle-test", workflows["exec_cmd"], env, "KJ_EXEC_CMD").to_s
      )
    end

    # A generated workflow normally uses one command for every matrix entry.
    # Legacy engines occasionally need a narrower command while retaining the
    # rest of the generated workflow (setup, retries, cache keys, and pins).
    def github_actions_engine_exec_cmds(config)
      workflows = config["workflows"]
      return {} unless workflows.is_a?(Hash)

      raw = workflows["engine_exec_cmds"]
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(engine, command), overrides|
        engine_name = engine.to_s.strip
        command_text = command.to_s.strip
        overrides[engine_name] = command_text unless engine_name.empty? || command_text.empty?
      end
    end

    def normalize_github_actions_exec_cmd(command)
      normalized = command.to_s.strip
      return "kettle-test" if OBSOLETE_APPRAISAL_SPEC_EXEC_CMDS.include?(normalized)

      normalized
    end

    def appraisal_recording_enabled?(config)
      workflows = config["workflows"]
      workflows = {} unless workflows.is_a?(Hash)

      DecisionPolicy.value_to_boolean(workflows["recording"]) == true
    end

    def project_recording_enabled?(project_root, config)
      return true if appraisal_recording_enabled?(config)

      project_appraisals_recording_enabled?(project_root)
    end

    def project_appraisals_recording_enabled?(project_root)
      appraisals_path = File.join(project_root.to_s, "Appraisals")
      return false unless File.file?(appraisals_path)

      gemfile_eval_paths(File.read(appraisals_path)).any? { |path| path.to_s.include?("modular/recording/") }
    end

    def github_actions_standard_appraisal_gemfiles(config)
      workflows = config["workflows"]
      workflows = {} unless workflows.is_a?(Hash)
      appraisal_matrix = config["appraisal_matrix"]
      appraisal_matrix = {} unless appraisal_matrix.is_a?(Hash)

      raw_paths =
        workflows["standard_appraisal_gemfiles"] ||
        appraisal_matrix["appraisal_gemfiles"] ||
        appraisal_matrix["appraisal_eval_gemfiles"]

      Array(raw_paths).filter_map do |path|
        normalized = path.to_s.strip.sub(%r{\Agemfiles/}, "")
        normalized unless normalized.empty?
      end.uniq
    end

    def expand_framework_gemfile_pattern(pattern, version)
      replacement = if pattern.include?("_{version}") || pattern.include?("{version}_")
        version.tr(".", "_")
      else
        version
      end
      pattern.gsub("{version}", replacement)
    end

    def framework_gemfile_path(gemfile)
      gemfile.include?("/") ? gemfile : "gemfiles/#{gemfile}"
    end

    def classify_namespace(name)
      name.to_s.split(/[-_]/).map { |part| part[0].to_s.upcase + part[1..].to_s }.join("::")
    end

    def readme_metadata_block(facts)
      package = facts.fetch(:package)
      funding_urls = facts.fetch(:funding, {}).fetch(:urls, [])
      rows = [
        ["Package", package[:name]],
        ["Description", package[:description]],
        ["Homepage", package[:homepage_url]],
        ["Source", package[:source_url]],
        ["License", readme_metadata_license_expression(facts)],
        ["Funding", funding_urls.join(", ")]
      ].reject { |(_, value)| value.to_s.empty? }

      [
        "<!-- kettle-jem:metadata:start -->",
        "| Field | Value |",
        "|---|---|",
        *rows.map do |field, value|
          "| #{readme_metadata_table_cell(field)} | #{readme_metadata_table_cell(value)} |"
        end,
        "<!-- kettle-jem:metadata:end -->"
      ].join("\n")
    end

    def readme_metadata_table_cell(value)
      value.to_s.split(/\r\n?|\n/).map(&:strip).join("<br>").gsub("|", "\\|")
    end

    def readme_metadata_license_expression(facts)
      package = facts.fetch(:package)
      expression = package[:license_expression].to_s
      spdx_ids = Array(facts.dig(:license, :spdx)).map(&:to_s).reject(&:empty?)
      return expression if expression.empty? || spdx_ids.empty?

      spdx_ids.sort_by { |spdx_id| -spdx_id.length }.reduce(expression) do |formatted, spdx_id|
        formatted.gsub(/\b#{Regexp.escape(spdx_id)}\b/, "`#{spdx_id}`")
      end
    end

    def synchronize_github_funding_yml(content, facts)
      output = content.to_s
      enabled_platforms = facts.fetch(:funding, {}).fetch(:platforms, {})
      enabled_platforms = enabled_platforms.merge("open_collective" => false) if facts.fetch(:funding, {})[:open_collective_disabled]
      FUNDING_YML_PLATFORMS.each do |platform|
        next if funding_platform_enabled?(enabled_platforms, platform)

        output = remove_top_level_yaml_key_lines(output, platform)
      end
      tidelift_value = "rubygems/#{facts.fetch(:package).fetch(:name)}"
      if funding_platform_enabled?(enabled_platforms, "tidelift") && !yaml_top_level_key_lines(output).key?("tidelift")
        lines = output.lines
        lines << "\n" unless lines.empty? || lines.last.to_s.strip.empty?
        lines << "tidelift: #{tidelift_value}\n"
        output = lines.join
      end
      ensure_trailing_newline(output)
    end

    def remove_top_level_yaml_key_lines(content, key)
      lines = content.to_s.lines
      document = Psych.parse_stream(content.to_s).children.first
      root = document&.root
      return content unless root.is_a?(Psych::Nodes::Mapping)

      pairs = root.children.each_slice(2).to_a
      pairs.each_with_index do |(key_node, value_node), index|
        next unless key_node.is_a?(Psych::Nodes::Scalar) && key_node.value.to_s == key.to_s

        next_key = pairs[index + 1]&.first
        end_line = next_key&.start_line || value_node.end_line
        end_line += 1 if end_line <= key_node.start_line
        return [*lines[0...key_node.start_line], *lines[end_line..].to_a].join
      end

      content
    rescue Psych::Exception
      content
    end

    def delete_rakefile_scaffold(content)
      selectors = rakefile_scaffold_delete_selectors(content)
      return {content: content.to_s, delete_selectors: selectors} if selectors.empty?

      {
        content: delete_line_ranges(content.to_s, selectors),
        delete_selectors: selectors
      }
    end

    def rakefile_scaffold_delete_selectors(content)
      selectors = []

      rakefile_require_records(content).each do |record|
        selector_id = case record.fetch(:name)
        when "bundler/gem_tasks"
          "rakefile_scaffold_require_bundler_gem_tasks"
        when "rspec/core/rake_task"
          "rakefile_scaffold_require_rspec_core_rake_task"
        when "rubocop/rake_task"
          "rakefile_scaffold_require_rubocop_rake_task"
        end
        next unless selector_id

        selectors << rakefile_selector(selector_id, record.fetch(:start_line), record.fetch(:end_line), "wrapper_selected_scaffold_require")
      end

      rakefile_task_class_records(content).each do |record|
        selector_id = case record.fetch(:receiver)
        when "RSpec::Core::RakeTask"
          "rakefile_scaffold_rspec_task"
        when "RuboCop::RakeTask"
          "rakefile_scaffold_rubocop_task"
        end
        next unless selector_id

        selectors << rakefile_selector(selector_id, record.fetch(:start_line), record.fetch(:end_line), "wrapper_selected_scaffold_task")
      end

      selectors.concat(rakefile_task_block_selectors(content))
      selectors.sort_by { |selector| [selector.fetch(:start_line), selector.fetch(:end_line)] }
    end

    def rakefile_require_records(content)
      top_level_ruby_call_records(content, :require).filter_map do |call|
        name = ruby_string_argument(call)
        next unless name

        {
          name: name,
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call)
        }
      end
    end

    def rakefile_task_class_records(content)
      top_level_ruby_call_records(content, :new).filter_map do |call|
        receiver = call.receiver&.slice
        next unless %w[RSpec::Core::RakeTask RuboCop::RakeTask].include?(receiver)

        {
          receiver: receiver,
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call)
        }
      end
    end

    def rakefile_task_block_selectors(content)
      rakefile_default_task_records(content).filter_map do |record|
        next if rakefile_template_default_task?(content, record)

        rakefile_selector(
          "rakefile_scaffold_task_default",
          record.fetch(:start_line),
          record.fetch(:end_line),
          "wrapper_selected_scaffold_task"
        )
      end
    end

    def rakefile_default_task_records(content)
      top_level_ruby_call_records(content, :task).filter_map do |call|
        next unless rakefile_default_task_call?(call)

        {
          start_line: call.location.start_line,
          end_line: ruby_node_source_end_line(call)
        }
      end
    end

    def rakefile_default_task_call?(call)
      argument = call.arguments&.arguments&.first
      case argument
      when ::Prism::SymbolNode
        argument.unescaped.to_s == "default"
      when ::Prism::KeywordHashNode
        argument.elements.any? { |element| element.key.is_a?(::Prism::SymbolNode) && element.key.unescaped.to_s == "default" }
      else
        false
      end
    end

    def rakefile_template_default_task?(content, record)
      desc_lines = top_level_ruby_call_records(content, :desc).filter_map do |call|
        next unless ruby_string_argument(call) == "Default tasks aggregator"

        call.location.start_line
      end
      desc_lines.include?(previous_nonblank_line_number(content, record.fetch(:start_line)))
    end

    def top_level_ruby_call_records(content, call_name)
      result = prism_parse_success(content)
      return [] unless result

      result.value.statements&.body.to_a.select { |node| node.is_a?(::Prism::CallNode) && node.name == call_name }
    end

    def previous_nonblank_line_number(content, line_number)
      lines = content.to_s.lines
      cursor = line_number - 2
      cursor -= 1 while cursor >= 0 && lines[cursor].strip.empty?
      (cursor >= 0) ? cursor + 1 : nil
    end

    def rakefile_selector(selector_id, start_line, end_line, reason)
      {
        selector_id: selector_id,
        selector_family: "structural_owner_range",
        start_line: start_line,
        end_line: end_line,
        reason: reason
      }
    end

    def delete_line_ranges(content, selectors)
      lines = content.lines
      selectors.sort_by { |selector| -selector.fetch(:start_line) }.each do |selector|
        start_index = selector.fetch(:start_line) - 1
        end_index = selector.fetch(:end_line) - 1
        lines.slice!(start_index..end_index)
      end
      lines.join.gsub(/\n{3,}/, "\n\n")
    end

    def synchronize_github_actions_ci(content, facts)
      package = facts.fetch(:package)
      ci = facts.fetch(:ci)
      ruby_versions = ci.fetch(:ruby_versions)
      lines = [
        "name: CI",
        "",
        "permissions:",
        "  contents: read",
        "",
        "on:",
        "  push:",
        "    branches:",
        *github_actions_push_branches_yaml(content, default_branch: ci.fetch(:default_branch), indent: "      ").lines(chomp: true),
        "    tags:",
        "      - \"!*\" # Do not execute on tags",
        "  pull_request:",
        "    branches:",
        "      - \"*\"",
        "  workflow_dispatch:",
        "",
        "concurrency:",
        "  group: \"${{ github.workflow }}-${{ github.ref }}\"",
        "  cancel-in-progress: true",
        "",
        "jobs:",
        "  test:",
        "    if: \"!contains(github.event.commits[0].message, '[ci skip]') && !contains(github.event.commits[0].message, '[skip ci]')\"",
        "    name: Specs ${{ matrix.ruby }}",
        "    runs-on: ubuntu-latest",
        "    continue-on-error: ${{ endsWith(matrix.ruby, 'head') }}",
        "    strategy:",
        "      fail-fast: false",
        "      matrix:",
        "        ruby:",
        *ruby_versions.map { |version| "          - \"#{version}\"" },
        "        rubygems:",
        "          - default",
        "        bundler:",
        "          - default",
        "",
        "    steps:",
        "      - name: Checkout #{package.fetch(:name)}",
        "        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
        "",
        *github_actions_setup_ruby_steps(indent: "      ").lines(chomp: true),
        "",
        *github_actions_rspec_status_cache_step(
          cache_scope: "ci",
          key_parts: ["${{matrix.ruby}}"],
          indent: "      "
        ).lines(chomp: true),
        "",
        "      - name: Tests",
        "        run: bundle exec #{ci.fetch(:exec_cmd)}"
      ]
      "#{lines.join("\n")}\n"
    end

    def synchronize_github_actions_framework_ci(content, facts)
      ci = facts.fetch(:ci)
      framework_matrix = ci.fetch(:framework_matrix)
      dimension = framework_matrix.fetch(:dimension)
      label = dimension.split(/[-_]/).map { |part| part[0].to_s.upcase + part[1..].to_s }.join(" ")
      framework_axis = framework_matrix.fetch(:include).flat_map do |entry|
        [
          "          - framework_version: \"#{entry.fetch(:framework_version)}\"",
          "            appraisal: \"#{entry.fetch(:appraisal)}\""
        ]
      end
      lines = [
        "name: #{label} CI",
        "",
        "permissions:",
        "  contents: read",
        "",
        "on:",
        "  push:",
        "    branches:",
        *github_actions_push_branches_yaml(content, default_branch: ci.fetch(:default_branch), indent: "      ").lines(chomp: true),
        "    tags:",
        "      - \"!*\" # Do not execute on tags",
        "  pull_request:",
        "    branches:",
        "      - \"*\"",
        "  workflow_dispatch:",
        "",
        "concurrency:",
        "  group: \"${{ github.workflow }}-${{ github.ref }}\"",
        "  cancel-in-progress: true",
        "",
        "jobs:",
        "  test:",
        "    if: \"!contains(github.event.commits[0].message, '[ci skip]') && !contains(github.event.commits[0].message, '[skip ci]')\"",
        "    name: Specs ${{ matrix.ruby }}@${{ matrix.framework.framework_version }}",
        "    runs-on: ubuntu-latest",
        "    continue-on-error: ${{ endsWith(matrix.ruby, 'head') }}",
        "    env:",
        "      BUNDLE_GEMFILE: ${{ github.workspace }}/Appraisal.root.gemfile",
        "    strategy:",
        "      fail-fast: false",
        "      matrix:",
        "        ruby:",
        *ci.fetch(:ruby_versions).map { |version| "          - \"#{version}\"" },
        "        rubygems:",
        "          - default",
        "        bundler:",
        "          - default",
        "        framework:",
        *framework_axis,
        "",
        "    steps:",
        "      - name: Checkout",
        "        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
        "",
        *github_actions_setup_ruby_steps(indent: "      ").lines(chomp: true),
        "",
        "      - name: \"[Attempt 1] Appraisal for ${{ matrix.ruby }}@${{ matrix.framework.framework_version }}\"",
        "        id: bundleAppraisalAttempt1",
        "        run: bundle exec appraisal ${{ matrix.framework.appraisal }} install",
        "        continue-on-error: true",
        "",
        "      - name: \"[Attempt 2] Appraisal for ${{ matrix.ruby }}@${{ matrix.framework.framework_version }}\"",
        "        id: bundleAppraisalAttempt2",
        "        if: ${{ steps.bundleAppraisalAttempt1.outcome == 'failure' }}",
        "        run: bundle exec appraisal ${{ matrix.framework.appraisal }} install",
        "",
        *github_actions_rspec_status_cache_step(
          cache_scope: "framework-ci",
          key_parts: ["${{matrix.ruby}}", "${{matrix.framework.appraisal}}"],
          indent: "      "
        ).lines(chomp: true),
        "",
        "      - name: Tests for ${{ matrix.ruby }}@${{ matrix.framework.framework_version }}",
        "        run: bundle exec appraisal ${{ matrix.framework.appraisal }} bundle exec #{ci.fetch(:exec_cmd)}"
      ]
      "#{lines.join("\n")}\n"
    end

    def github_actions_setup_ruby_steps(indent:)
      yaml = <<~YAML
        - name: Setup Ruby & RubyGems
          uses: appraisal-rb/setup-ruby-flash@925395edf973d2dc0a629919f407f3547a03d4b5 # v2.1
          with:
            ruby-version: "${{ matrix.ruby }}"
            rubygems: "${{ matrix.rubygems }}"
            bundler: "${{ matrix.bundler }}"
            bundler-cache: ${{ matrix.ruby != 'ruby-2.4' && matrix.ruby != 'ruby-2.5' && matrix.ruby != 'ruby-2.6' && matrix.ruby != 'ruby-2.7' && matrix.ruby != 'truffleruby-25.0' && matrix.ruby != 'jruby-9.2' && matrix.ruby != 'jruby-9.3' && matrix.ruby != 'jruby-9.4' }}

        - name: Bundle install for legacy Ruby engine
          if: ${{ matrix.ruby == 'ruby-2.4' || matrix.ruby == 'ruby-2.5' || matrix.ruby == 'ruby-2.6' || matrix.ruby == 'ruby-2.7' || matrix.ruby == 'truffleruby-25.0' || matrix.ruby == 'jruby-9.2' || matrix.ruby == 'jruby-9.3' || matrix.ruby == 'jruby-9.4' }}
          run: |
            bundle config set --local path "${RUNNER_TEMP}/bundle"
            bundle config set --local mirror.https://gem.coop https://rubygems.org
            bundle install --jobs 1
      YAML
      yaml.lines.map { |line| line.strip.empty? ? line : "#{indent}#{line}" }.join.rstrip
    end

    def github_actions_rspec_status_cache_step(cache_scope:, key_parts:, indent:, if_condition: "${{!env.ACT}}")
      cache_prefix = ["rspec-status", cache_scope, *key_parts].join("-")
      yaml = <<~YAML
        - name: Restore RSpec status log
          if: #{if_condition}
          uses: #{github_actions_step_pins.fetch("actions/cache")}
          with:
            path: .rspec_status
            key: #{cache_prefix}-${{hashFiles('**/Gemfile.lock','Appraisal.root.gemfile','gemfiles/**/*.gemfile')}}-${{github.run_id}}-${{github.run_attempt}}
            restore-keys: |
              #{cache_prefix}-${{hashFiles('**/Gemfile.lock','Appraisal.root.gemfile','gemfiles/**/*.gemfile')}}-
              #{cache_prefix}-
      YAML
      yaml.lines.map { |line| line.strip.empty? ? line : "#{indent}#{line}" }.join.rstrip
    end

    def synchronize_github_actions_framework_gemfile(target_path, facts)
      gemfile = facts.dig(:ci, :framework_matrix, :gemfiles).to_a.find do |entry|
        entry.fetch(:path).to_s == target_path.to_s
      end
      raise ArgumentError, "missing framework matrix gemfile config for #{target_path}" unless gemfile

      lines = [
        "# frozen_string_literal: true",
        "",
        "# Generated by kettle-jem from workflows.framework_matrix.",
        %(ENV["KJ_FRAMEWORK_MATRIX_GEM"] = #{gemfile.fetch(:gem).inspect})
      ]
      gemfile.fetch(:env, {}).each do |key, value|
        lines << %(ENV[#{key.inspect}] = #{value.inspect})
      end
      lines << ""
      lines << %(gem #{gemfile.fetch(:gem).inspect}, #{gemfile.fetch(:requirement).inspect})
      "#{lines.join("\n")}\n"
    end

    def synchronize_github_actions_coverage_ci(content, facts)
      ci = facts.fetch(:ci)
      coverage = ci.fetch(:coverage)
      coverage_steps = github_actions_coverage_steps(disabled_integrations: facts.dig(:integrations, :disabled))
      lines = [
        "name: Test Coverage",
        "",
        "permissions:",
        "  contents: read",
        "  pull-requests: write",
        "  id-token: write",
        "",
        "env:",
        "  K_SOUP_COV_MIN_BRANCH: 100",
        "  K_SOUP_COV_MIN_LINE: 100",
        "  K_SOUP_COV_MIN_HARD: true",
        "  K_SOUP_COV_FORMATTERS: \"xml,rcov,lcov,tty\"",
        "  K_SOUP_COV_DO: true",
        "  K_SOUP_COV_MULTI_FORMATTERS: true",
        "  K_SOUP_COV_COMMAND_NAME: \"Test Coverage\"",
        "",
        "on:",
        "  push:",
        "    branches:",
        *github_actions_push_branches_yaml(content, default_branch: ci.fetch(:default_branch), indent: "      ").lines(chomp: true),
        "    tags:",
        "      - \"!*\" # Do not execute on tags",
        "  pull_request:",
        "    branches:",
        "      - \"*\"",
        "  workflow_dispatch:",
        "",
        "concurrency:",
        "  group: \"${{ github.workflow }}-${{ github.ref }}\"",
        "  cancel-in-progress: true",
        "",
        "jobs:",
        "  coverage:",
        "    if: \"!contains(github.event.commits[0].message, '[ci skip]') && !contains(github.event.commits[0].message, '[skip ci]')\"",
        "    name: Code Coverage on ${{ matrix.ruby }}@current",
        "    runs-on: ubuntu-latest",
        "    continue-on-error: ${{ matrix.experimental || endsWith(matrix.ruby, 'head') }}",
        "    env:",
        "      BUNDLE_GEMFILE: ${{ github.workspace }}/Appraisal.root.gemfile",
        "    strategy:",
        "      fail-fast: false",
        "      matrix:",
        "        include:",
        "          - ruby: \"ruby\"",
        "            appraisal: \"#{coverage.fetch(:appraisal)}\"",
        "            exec_cmd: \"#{coverage.fetch(:command)}\"",
        "            rubygems: latest",
        "            bundler: latest",
        "",
        "    steps:",
        "      - name: Checkout",
        "        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
        "",
        "      - name: Setup Ruby & RubyGems",
        "        uses: appraisal-rb/setup-ruby-flash@925395edf973d2dc0a629919f407f3547a03d4b5 # v2.1",
        "        with:",
        "          ruby-version: \"${{ matrix.ruby }}\"",
        "          rubygems: \"${{ matrix.rubygems }}\"",
        "          bundler: \"${{ matrix.bundler }}\"",
        "          bundler-cache: true",
        "",
        "      - name: \"[Attempt 1] Appraisal for ${{ matrix.ruby }}@${{ matrix.appraisal }}\"",
        "        id: bundleAppraisalAttempt1",
        "        run: bundle exec appraisal ${{ matrix.appraisal }} install",
        "        continue-on-error: true",
        "",
        "      - name: \"[Attempt 2] Appraisal for ${{ matrix.ruby }}@${{ matrix.appraisal }}\"",
        "        id: bundleAppraisalAttempt2",
        "        if: ${{ steps.bundleAppraisalAttempt1.outcome == 'failure' }}",
        "        run: bundle exec appraisal ${{ matrix.appraisal }} install",
        "",
        *github_actions_rspec_status_cache_step(
          cache_scope: "coverage",
          key_parts: ["${{matrix.ruby}}", "${{matrix.appraisal}}"],
          indent: "      "
        ).lines(chomp: true),
        "",
        "      - name: Tests for ${{ matrix.ruby }}@current via ${{ matrix.exec_cmd }}",
        "        run: bundle exec appraisal ${{ matrix.appraisal }} bundle exec ${{ matrix.exec_cmd }}",
        "",
        "      - name: Verify coverage reports",
        "        run: |",
        "          test -s coverage/lcov.info",
        "          test -s coverage/coverage.xml",
        *coverage_steps.lines(chomp: true).map { |line| line.empty? ? line : "      #{line}" }
      ]
      "#{lines.join("\n")}\n"
    end

    def synchronize_github_actions_workflow_snippets(content, facts: {})
      updated = ensure_workflow_top_level_section(
        content.to_s,
        "permissions",
        "permissions:\n  contents: read\n\n",
        before: "on"
      )
      updated = ensure_workflow_top_level_section(
        updated,
        "concurrency",
        "concurrency:\n  group: \"${{ github.workflow }}-${{ github.ref }}\"\n  cancel-in-progress: true\n\n",
        before: "jobs"
      )
      updated = append_github_actions_coverage_steps(updated, disabled_integrations: facts.dig(:integrations, :disabled)) if github_actions_coverage_enabled?(updated)
      update_github_actions_pins(updated)
    end

    def github_actions_push_branches_yaml(content, default_branch:, indent: "              ")
      github_actions_push_branches(content, default_branch: default_branch).map do |branch|
        "#{indent}- #{branch.inspect}"
      end.join("\n")
    end

    def github_actions_push_branches(content, default_branch:)
      managed = [default_branch.to_s, "*-stable"]
      existing = yaml_scalar_sequence_at_path(content, %w[on push branches])
      (managed + existing).uniq
    end

    def yaml_scalar_sequence_at_path(content, path)
      document = Psych.parse_stream(content.to_s).children.first
      node = path.reduce(document&.root) do |current, key|
        break nil unless current.is_a?(Psych::Nodes::Mapping)

        pair = current.children.each_slice(2).find do |key_node, _value_node|
          key_node.is_a?(Psych::Nodes::Scalar) && key_node.value.to_s == key.to_s
        end
        pair&.last
      end
      return [] unless node.is_a?(Psych::Nodes::Sequence)

      node.children.filter_map do |child|
        child.value.to_s if child.is_a?(Psych::Nodes::Scalar)
      end
    rescue Psych::Exception
      []
    end

    def github_actions_coverage_enabled?(content)
      yaml_contains_key_value?(YAML.safe_load(content.to_s, aliases: true), "K_SOUP_COV_DO", "true")
    rescue Psych::Exception
      false
    end

    def yaml_contains_key_value?(node, key, value)
      case node
      when Hash
        node.any? do |candidate_key, candidate_value|
          (candidate_key.to_s == key.to_s && candidate_value.to_s == value.to_s) ||
            yaml_contains_key_value?(candidate_value, key, value)
        end
      when Array
        node.any? { |candidate| yaml_contains_key_value?(candidate, key, value) }
      else
        false
      end
    end

    def http_url?(value)
      uri = URI.parse(value.to_s)
      %w[http https].include?(uri.scheme)
    rescue URI::InvalidURIError
      false
    end

    def append_github_actions_coverage_steps(content, disabled_integrations: [])
      return content if content.include?("Upload coverage to Coveralls") ||
        content.include?("Upload coverage to QLTY") ||
        content.include?("Upload coverage to CodeCov") ||
        content.include?("Code Coverage Summary Report")

      lines = content.lines
      steps_sequence = yaml_mapping_value_node(content, "steps", Psych::Nodes::Sequence)
      return content unless steps_sequence

      insert_index = steps_sequence.end_line
      lines.insert(insert_index, "#{github_actions_coverage_steps(disabled_integrations: disabled_integrations)}\n")
      lines.join
    end

    def github_actions_coverage_steps(disabled_integrations: [])
      disabled = Array(disabled_integrations).map { |name| normalize_integration_name(name) }.to_set
      steps = []
      unless disabled.include?("coveralls")
        steps << <<~YAML
          - name: Upload coverage to Coveralls
            if: ${{ !env.ACT }}
            uses: coverallsapp/github-action@8d6379e14d29928660c4ba802d8e85393440b329 # v2.3.8
            with:
              github-token: ${{ secrets.GITHUB_TOKEN }}
              file: coverage/lcov.info
              format: lcov
              fail-on-error: false
            continue-on-error: true
        YAML
      end

      unless disabled.include?("qlty")
        steps << <<~YAML
          - name: Upload coverage to QLTY
            if: ${{ !env.ACT }}
            uses: qltysh/qlty-action/coverage@08a0a862c159eae9b9003081da6663d96efef637 # v2.3.0
            with:
              oidc: true
              files: coverage/lcov.info
              format: lcov
              skip-errors: true
            continue-on-error: true
        YAML
      end

      unless disabled.include?("codecov")
        steps << <<~YAML
          - name: Upload coverage to CodeCov
            if: ${{ !env.ACT }}
            uses: codecov/codecov-action@fb8b3582c8e4def4969c97caa2f19720cb33a72f # v7.0.0
            with:
              use_oidc: true
              disable_search: true
              fail_ci_if_error: false
              files: coverage/lcov.info,coverage/coverage.xml
              verbose: true
            continue-on-error: true
        YAML
      end

      steps << <<~YAML
        - name: Code Coverage Summary Report
          if: ${{ !env.ACT && github.event_name == 'pull_request' }}
          uses: irongut/CodeCoverageSummary@51cc3a756ddcd398d447c044c02cb6aa83fdae95 # v1.3.0
          with:
            filename: ./coverage/coverage.xml
            badge: true
            fail_below_min: true
            format: markdown
            hide_branch_rate: false
            hide_complexity: true
            indicators: true
            output: both
            thresholds: '${{ env.K_SOUP_COV_MIN_LINE }} ${{ env.K_SOUP_COV_MIN_BRANCH }}'
          continue-on-error: ${{ matrix.experimental || endsWith(matrix.ruby, 'head') }}

        - name: Add Coverage PR Comment
          uses: marocchino/sticky-pull-request-comment@5770ad5eb8f42dd2c4f34da00c94c5381e49af88 # v3.0.5
          if: ${{ !env.ACT && github.event_name == 'pull_request' }}
          with:
            recreate: true
            path: code-coverage-results.md
          continue-on-error: ${{ matrix.experimental || endsWith(matrix.ruby, 'head') }}
      YAML
      steps.join("\n").lines.map { |line| line.strip.empty? ? line : "      #{line}" }.join.chomp
    end

    def ensure_workflow_top_level_section(content, key, section, before:)
      top_level_keys = yaml_top_level_key_lines(content)
      return content if top_level_keys.key?(key.to_s)

      lines = content.lines
      index = top_level_keys[before.to_s]
      if index
        prepared_section = (index.zero? || lines[index - 1].strip.empty?) ? section : "\n#{section}"
        lines.insert(index, prepared_section)
      else
        lines << "\n" unless lines.empty? || lines.last == "\n"
        lines << section
      end
      lines.join
    end

    def yaml_top_level_key_lines(content)
      document = Psych.parse_stream(content.to_s).children.first
      root = document&.root
      return {} unless root.is_a?(Psych::Nodes::Mapping)

      root.children.each_slice(2).each_with_object({}) do |(key_node, _value_node), keys|
        next unless key_node.is_a?(Psych::Nodes::Scalar)

        keys[key_node.value.to_s] = key_node.start_line
      end
    rescue Psych::Exception
      {}
    end

    def update_github_actions_pins(content)
      lines = content.to_s.lines
      yaml_scalar_pairs(content).each do |key_node, value_node|
        next unless key_node.value.to_s == "uses"

        pinned_value = github_actions_step_pins.find do |action_prefix, _pin|
          value_node.value.to_s.start_with?("#{action_prefix}@")
        end&.last
        next unless pinned_value

        line_index = key_node.start_line
        line = lines[line_index].to_s
        key_index = line.index("uses:")
        next unless key_index

        lines[line_index] = "#{line[0...key_index]}uses: #{pinned_value}\n"
      end
      lines.join
    rescue Psych::Exception
      content
    end

    def preserve_newer_github_workflow_action_pins(content, destination_content)
      destination_records = github_workflow_action_pin_records(destination_content)
      return content if destination_records.empty?

      destination_by_key = destination_records.to_h { |record| [github_workflow_action_pin_key(record), record] }
      lines = content.to_s.lines
      github_workflow_action_pin_records(content).each do |record|
        destination = destination_by_key[github_workflow_action_pin_key(record)]
        next unless destination
        next if destination.fetch(:sha) == record.fetch(:sha)

        lines[record.fetch(:line_index)] = replace_github_workflow_action_pin_sha(
          lines.fetch(record.fetch(:line_index)),
          destination.fetch(:sha)
        )
      end
      lines.join
    end

    def stale_github_workflow_template_pin_records(relative_path, final_content, destination_content)
      destination_records = github_workflow_action_pin_records(destination_content)
      final_records = github_workflow_action_pin_records(final_content)
      canonical_records = github_actions_step_pins.values.flat_map do |pin|
        github_workflow_action_pin_records("uses: #{pin}\n")
      end
      return [] if destination_records.empty? || final_records.empty? || canonical_records.empty?

      destination_by_key = destination_records.to_h { |record| [github_workflow_action_pin_key(record), record] }
      canonical_by_key = canonical_records.to_h { |record| [github_workflow_action_pin_key(record), record] }
      final_records.filter_map do |record|
        key = github_workflow_action_pin_key(record)
        destination = destination_by_key[key]
        canonical = canonical_by_key[key]
        next unless destination && canonical
        next unless destination.fetch(:sha) == record.fetch(:sha)
        next if canonical.fetch(:sha) == record.fetch(:sha)

        {
          path: relative_path.to_s,
          action: record.fetch(:action),
          version: record.fetch(:version),
          preserved_sha: record.fetch(:sha),
          template_sha: canonical.fetch(:sha)
        }
      end
    end

    def github_workflow_template_pin_warnings(recipe_reports)
      records = recipe_reports.flat_map do |report|
        Array(report.dig(:metadata, :stale_github_workflow_template_pins))
      end
      return [] if records.empty?

      grouped = records.group_by { |record| record.fetch(:path) }
      grouped.map do |path, path_records|
        actions = path_records.map { |record| "#{record.fetch(:action)} #{record.fetch(:version)}" }.uniq.sort.join(", ")
        [
          "GitHub Actions template pins appear stale for #{path}:",
          "preserved existing project pin(s) for #{actions}.",
          "Update kettle-jem's workflow template pins."
        ].join(" ")
      end
    end

    def github_workflow_action_pin_records(content)
      lines = content.to_s.lines
      yaml_scalar_pairs(content).filter_map do |key_node, value_node|
        next unless key_node.value.to_s == "uses"
        next unless value_node.value.to_s.include?("@")

        github_workflow_action_pin_line_record(lines[key_node.start_line], key_node.start_line)
      end
    rescue Psych::Exception
      []
    end

    def github_workflow_action_pin_key(record)
      [record.fetch(:action), record.fetch(:version)]
    end

    def github_workflow_action_pin_line_record(line, line_index)
      # Psych intentionally drops comments, but the managed pin contract uses
      # the trailing comment as the human version label paired with the SHA.
      match = line.to_s.match(
        %r{
          \A\s*(?:-\s*)?uses:\s*
          (?<action>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*)
          @(?<sha>[a-f0-9]{40})\s+\#\s*(?<version>v?[^#\s]+)
        }x
      )
      return unless match

      {
        action: match[:action],
        sha: match[:sha],
        version: match[:version],
        line_index: line_index
      }
    end

    def replace_github_workflow_action_pin_sha(line, sha)
      line.to_s.sub(/@[a-f0-9]{40}/, "@#{sha}")
    end

    def yaml_scalar_pairs(content)
      yaml_mapping_nodes(content).flat_map do |mapping|
        mapping.children.each_slice(2).filter_map do |key_node, value_node|
          [key_node, value_node] if key_node.is_a?(Psych::Nodes::Scalar) && value_node.is_a?(Psych::Nodes::Scalar)
        end
      end
    end

    def yaml_scalar_path_entries(content)
      document = Psych.parse_stream(content.to_s)
      entries = []
      document.children.each { |node| collect_yaml_scalar_path_entries(node, [], entries) }
      entries
    rescue Psych::Exception
      []
    end

    def yaml_mapping_path_entries(content)
      document = Psych.parse_stream(content.to_s)
      entries = []
      document.children.each { |node| collect_yaml_mapping_path_entries(node, [], entries) }
      entries
    rescue Psych::Exception
      []
    end

    def collect_yaml_scalar_path_entries(node, path, entries)
      unless node.is_a?(Psych::Nodes::Mapping)
        node.children.each { |child| collect_yaml_scalar_path_entries(child, path, entries) } if node.respond_to?(:children)
        return
      end

      node.children.each_slice(2) do |key_node, value_node|
        next unless key_node.is_a?(Psych::Nodes::Scalar)

        child_path = path + [key_node.value.to_s]
        if value_node.is_a?(Psych::Nodes::Scalar)
          entries << {path: child_path, line: key_node.start_line}
        elsif value_node.is_a?(Psych::Nodes::Mapping)
          collect_yaml_scalar_path_entries(value_node, child_path, entries)
        end
      end
    end

    def collect_yaml_mapping_path_entries(node, path, entries)
      unless node.is_a?(Psych::Nodes::Mapping)
        Array(node.respond_to?(:children) ? node.children : nil).each do |child|
          collect_yaml_mapping_path_entries(child, path, entries)
        end
        return
      end

      node.children.each_slice(2) do |key_node, value_node|
        next unless key_node.is_a?(Psych::Nodes::Scalar)

        child_path = path + [key_node.value.to_s]
        if value_node.is_a?(Psych::Nodes::Mapping)
          entries << {
            path: child_path,
            start_line: key_node.start_line,
            end_line: value_node.end_line
          }
          collect_yaml_mapping_path_entries(value_node, child_path, entries)
        else
          Array(value_node.respond_to?(:children) ? value_node.children : nil).each do |child|
            collect_yaml_mapping_path_entries(child, child_path, entries)
          end
        end
      end
    end

    def yaml_mapping_value_node(content, key, node_class)
      yaml_mapping_nodes(content).each do |mapping|
        mapping.children.each_slice(2) do |key_node, value_node|
          next unless key_node.is_a?(Psych::Nodes::Scalar) && key_node.value.to_s == key.to_s

          return value_node if value_node.is_a?(node_class)
        end
      end
      nil
    end

    def github_actions_step_pins
      {
        "actions/checkout" => "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
        "actions/cache" => "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0",
        "appraisal-rb/setup-ruby-flash" => "appraisal-rb/setup-ruby-flash@925395edf973d2dc0a629919f407f3547a03d4b5 # v2.1",
        "ruby/setup-ruby" => "ruby/setup-ruby@95ef2b042f9d7a56d8268cba8559e2842e2ad01b # v1.321.0",
        "coverallsapp/github-action" => "coverallsapp/github-action@8d6379e14d29928660c4ba802d8e85393440b329 # v2.3.8",
        "qltysh/qlty-action/coverage" => "qltysh/qlty-action/coverage@08a0a862c159eae9b9003081da6663d96efef637 # v2.3.0",
        "codecov/codecov-action" => "codecov/codecov-action@fb8b3582c8e4def4969c97caa2f19720cb33a72f # v7.0.0",
        "irongut/CodeCoverageSummary" => "irongut/CodeCoverageSummary@51cc3a756ddcd398d447c044c02cb6aa83fdae95 # v1.3.0",
        "marocchino/sticky-pull-request-comment" => "marocchino/sticky-pull-request-comment@5770ad5eb8f42dd2c4f34da00c94c5381e49af88 # v3.0.5",
        "actions/upload-artifact" => "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1",
        "amancevice/setup-code-climate" => "amancevice/setup-code-climate@0daf2985a225e8ac15975b4d233010e94d65b76a # v2",
        "actions/dependency-review-action" => "actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294 # v5.0.0",
        "github/codeql-action/init" => "github/codeql-action/init@cdf488f595d80d6e07e03d4674febd5ab45fa938 # v4.37.9",
        "github/codeql-action/autobuild" => "github/codeql-action/autobuild@cdf488f595d80d6e07e03d4674febd5ab45fa938 # v4.37.9",
        "github/codeql-action/analyze" => "github/codeql-action/analyze@cdf488f595d80d6e07e03d4674febd5ab45fa938 # v4.37.9",
        "pozil/auto-assign-issue" => "pozil/auto-assign-issue@af6beea6bdf1e8eb373f061c5bc168681fc6d011 # v4.0.1",
        "apache/skywalking-eyes/dependency" => "apache/skywalking-eyes/dependency@a196742f472feaffafea537ce5a2a4c3c53a8de4 # v0.9.0",
        "sarisia/actions-status-discord" => "sarisia/actions-status-discord@eb045afee445dc055c18d3d90bd0f244fd062708 # v1.16.0"
      }
    end

    def replace_markdown_managed_block(content, marker, replacement)
      open = "<!-- #{marker}:start -->"
      close = "<!-- #{marker}:end -->"
      replace_markdown_managed_block_with_crispr(content, open, close, replacement) do
        ensure_trailing_newline([content.rstrip, "", replacement.to_s.rstrip].join("\n"))
      end
    end

    def replace_existing_markdown_managed_block(content, marker, replacement)
      open = "<!-- #{marker}:start -->"
      close = "<!-- #{marker}:end -->"
      replace_markdown_managed_block_with_crispr(content, open, close, replacement) do
        content
      end
    end

    def replace_text_managed_block(content, replacement)
      replace_text_managed_block_with_crispr(content, MANAGED_BLOCK_OPEN, MANAGED_BLOCK_CLOSE, replacement) do
        ensure_trailing_newline([content.rstrip, replacement.to_s.rstrip].reject(&:empty?).join("\n"))
      end
    end

    def replace_ruby_managed_block(content, replacement)
      replace_ruby_managed_block_with_crispr(content, MANAGED_BLOCK_OPEN, MANAGED_BLOCK_CLOSE, replacement) do
        ensure_trailing_newline([content.rstrip, replacement.to_s.rstrip].reject(&:empty?).join("\n"))
      end
    end

    def replace_markdown_managed_block_with_crispr(content, open_marker, close_marker, replacement)
      ensure_runtime_dependencies!
      prepared_replacement = ensure_trailing_newline(replacement.to_s)
      actor = Ast::Crispr::Replace.call(
        content: content.to_s,
        target: Ast::Crispr::Markdown::Markly::Selectors.html_comment_block(
          start_text: open_marker.delete_prefix("<!-- ").delete_suffix(" -->"),
          end_text: close_marker.delete_prefix("<!-- ").delete_suffix(" -->"),
          span: :outermost,
          include_trailing_gap: true,
          limit: {none_or_one: true}
        ),
        replacement: prepared_replacement,
        source_label: "managed markdown block"
      )
      return actor.updated_content if actor.match_count.positive?

      yield
    end

    def replace_text_managed_block_with_crispr(content, open_marker, close_marker, replacement)
      ensure_runtime_dependencies!
      prepared_replacement = ensure_trailing_newline(replacement.to_s)
      actor = Ast::Crispr::Replace.call(
        content: content.to_s,
        target: Ast::Crispr::Selectors.line_block(
          start_line_text: open_marker,
          end_line_text: close_marker,
          include_trailing_gap: true,
          limit: {none_or_one: true}
        ),
        replacement: prepared_replacement,
        source_label: "managed text block"
      )
      return actor.updated_content if actor.match_count.positive?

      yield
    end

    def replace_ruby_managed_block_with_crispr(content, open_marker, close_marker, replacement)
      ensure_runtime_dependencies!
      prepared_replacement = ensure_trailing_newline(replacement.to_s)
      actor = Ast::Crispr::Replace.call(
        content: content.to_s,
        target: Ast::Crispr::Ruby::Prism::Selectors.comment_line_block(
          start_text: open_marker,
          end_text: close_marker,
          span: :outermost,
          include_trailing_gap: true,
          limit: {none_or_one: true}
        ),
        replacement: prepared_replacement,
        source_label: "managed Ruby block"
      )
      return actor.updated_content if actor.match_count.positive?

      yield
    end

    def ensure_trailing_newline(text)
      return "" if text.to_s.empty?

      text.end_with?("\n") ? text : "#{text}\n"
    end

    def compact_hash(hash)
      hash.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
    end

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end

require_relative "jem/tasks/install_task"
require_relative "jem/tasks/template_task"
require_relative "jem/tasks/prepare_task"
require_relative "jem/tasks/self_test_task"

if File.basename(Process.argv0).match?(/\Arake(?:\z|\.)/) || defined?(Rake.application)
  Kettle::Jem.install_tasks
end
