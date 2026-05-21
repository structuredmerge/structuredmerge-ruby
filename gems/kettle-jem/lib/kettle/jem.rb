# frozen_string_literal: true

require "version_gem"

require "fileutils"
require "find"
require "English"
require "digest"
require "json"
require "net/http"
require "open3"
require "rbconfig"
require "set"
require "time"
require "uri"
require "ruby/merge"
require "prism/merge"
require "bash/merge"
require "json/merge"
require "dotenv/merge"
require "rbs/merge"
require "token/resolver"
require "toml-merge"
require "psych-merge"
require "yaml"
require "ast/merge"
require "ast/crispr/markdown/markly"
require "ast/crispr/ruby/prism"
require_relative "jem/version"

module Kettle
  module Jem
    class Error < StandardError; end

    PACKAGE_NAME = "kettle-jem"
    CONTENT_RECIPE_TRANSPORT_VERSION = Ast::Merge::STRUCTURED_EDIT_TRANSPORT_VERSION
    MANAGED_BLOCK_OPEN = "# <<kettle-jem:generated>> do not edit below this line"
    MANAGED_BLOCK_CLOSE = "# <</kettle-jem:generated>>"
    OBSOLETE_GITHUB_WORKFLOWS = %w[ancient.yml legacy.yml supported.yml unsupported.yml main.yml hoary.yml].freeze
    OPENCOLLECTIVE_DISABLED_FILES = %w[.opencollective.yml .github/workflows/opencollective.yml].freeze
    OPT_IN_GITHUB_WORKFLOWS = %w[.github/workflows/discord-notifier.yml].freeze
    DEFAULT_ENGINES = %w[ruby jruby truffleruby].freeze
    ENGINE_WORKFLOW_MAP = {
      "jruby" => "jruby",
      "jruby-9.1" => "jruby",
      "jruby-9.2" => "jruby",
      "jruby-9.3" => "jruby",
      "jruby-9.4" => "jruby",
      "truffle" => "truffleruby",
      "truffleruby-22.3" => "truffleruby",
      "truffleruby-23.0" => "truffleruby",
      "truffleruby-23.1" => "truffleruby",
      "truffleruby-24.2" => "truffleruby",
      "truffleruby-25.0" => "truffleruby",
    }.freeze
    FILE_DELETION_PRIMITIVES = %w[
      supplied_obsolete_file_deletion
      supplied_opt_in_workflow_deletion
      supplied_disabled_opencollective_file_deletion
      supplied_legacy_destination_file_deletion
      supplied_obsolete_license_file_deletion
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
    COPY_ONLY_WHEN_MISSING_TEMPLATE_PATHS = %w[REEK bin/setup].freeze
    MONOREPO_ROOT_TEMPLATE_PROFILE = "monorepo-root"
    MONOREPO_SUBGEM_TEMPLATE_PROFILE = "monorepo-subgem"
    MONOREPO_ROOT_TEMPLATE_ENTRIES = [
      "CHANGELOG.md",
      "CODE_OF_CONDUCT.md",
      "CONTRIBUTING.md",
      "FUNDING.md",
      "IRP.md",
      "RUBOCOP.md",
      "SECURITY.md",
      ".github/FUNDING.yml",
    ].freeze
    MONOREPO_SUBGEM_TEMPLATE_ENTRIES = [
      "README.md",
      "LICENSE.md",
      "MIT.md",
      "AGPL-3.0-only.md",
      "PolyForm-Noncommercial-1.0.0.md",
      "PolyForm-Small-Business-1.0.0.md",
      "Big-Time-Public-License.md",
      "certs/pboling.pem",
      "tmp/.gitignore",
    ].freeze
    VERSION_GEM_TEMPLATE_SOURCES = [
      "lib/gem/version.rb",
      "sig/gem/version.rbs",
    ].freeze
    NON_LICENSE_MD_BASENAMES = %w[
      AGENTS
      CHANGELOG
      CODE_OF_CONDUCT
      CONTRIBUTING
      FUNDING
      LICENSE
      README
      RUBOCOP
      SECURITY
    ].freeze
    MONOREPO_SUBGEM_README_BLOB_PATHS = %w[
      CHANGELOG.md
      CODE_OF_CONDUCT.md
      CONTRIBUTING.md
      IRP.md
      RUBOCOP.md
      SECURITY.md
    ].freeze
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
      "license",
    ].freeze
    LEGACY_DESTINATION_PATHS = {
      ".github/copilot_instructions.md" => ".github/COPILOT_INSTRUCTIONS.md",
    }.freeze
    SUPPORTED_TEMPLATE_STRATEGIES = %i[merge accept_template keep_destination raw_copy].freeze
    SUPPORTED_TEMPLATE_FILE_TYPES = %i[ruby gemfile appraisals gemspec rakefile yaml toml markdown json jsonc dotenv rbs bash text].freeze
    SUPPORTED_RUBY_METHOD_MOVE_POLICIES = %w[destination_order].freeze
    DEFAULT_RUBY_METHOD_MOVE_POLICY = "destination_order"
    SUPPORTED_YAML_COMMENT_MERGE_POLICIES = %w[preserve_destination template_fallback_when_missing template_documentation].freeze
    DEFAULT_TEMPLATE_YAML_COMMENT_MERGE_POLICY = "template_fallback_when_missing"
    RUBY_TEMPLATE_BASENAMES = %w[Gemfile Rakefile Appraisals Appraisal.root.gemfile .simplecov].freeze
    RUBY_TEMPLATE_SUFFIXES = %w[.gemspec .gemfile].freeze
    RUBY_TEMPLATE_EXTENSIONS = %w[.rb .rake].freeze
    TEMPLATE_TOKEN_CONFIG = Token::Resolver::Config.new(separators: ["|", ":"]).freeze
    EMPTY_TEMPLATE_TOKENS = %w[
      KJ|CB:USER
      KJ|COPYRIGHT_PREFIX
      KJ|FUNDING:BUYMEACOFFEE
      KJ|FUNDING:ISSUEHUNT
      KJ|FUNDING:KOFI
      KJ|FUNDING:LIBERAPAY
      KJ|FUNDING:PATREON
      KJ|FUNDING:PAYPAL
      KJ|FUNDING:POLAR
      KJ|GH:USER
      KJ|GL:USER
      KJ|MIN_DIVERGENCE_THRESHOLD
      KJ|OPENCOLLECTIVE_ORG
      KJ|README:COPYRIGHT_NOTICE
      KJ|README:LICENSE_BADGE
      KJ|README:LICENSE_COMPAT_BADGE
      KJ|README:LICENSE_EYE_WORKFLOW_BADGE
      KJ|README:LICENSE_INTRO
      KJ|README:LICENSE_REFS
      KJ|README:TOP_LOGO_REFS
      KJ|README:TOP_LOGO_ROW
      KJ|SH:USER
      KJ|SOCIAL:BLUESKY
      KJ|SOCIAL:DEVTO
      KJ|SOCIAL:LINKTREE
      KJ|SOCIAL:MASTODON
    ].freeze
    COPYRIGHT_NAME_RE = /\ACopyright \(c\) [\d,\s\-]+ (.+)\z/
    BOT_EMAIL_PATTERN = /\A\d+\+[^@]+\[bot\]@/i
    BOT_NAME_SUFFIX = /\[bot\]\z/i
    NOT_COMMITTED_EMAIL = "not.committed.yet"
    LOGOS_GALTZO_BASE_URL = "https://logos.galtzo.com/assets/images"
    README_TOP_LOGO_MODE_DEFAULT = "org_and_project"
    README_TOP_LOGO_MODES = %w[org project org_and_project].freeze
    README_TOP_LOGO_TYPES = %w[language org project affiliated_project].freeze
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
      "rom-sql" => "rsql",
    }.freeze
    APPRAISAL_WORKFLOW_LIFECYCLE_RANGES = {
      "current" => { min: Gem::Version.new("3.4"), max: Gem::Version.new("3.99") },
      "supported" => { min: Gem::Version.new("3.2"), max: Gem::Version.new("3.3") },
      "legacy" => { min: Gem::Version.new("3.0"), max: Gem::Version.new("3.1") },
      "unsupported" => { min: Gem::Version.new("2.6"), max: Gem::Version.new("2.7") },
      "ancient" => { min: Gem::Version.new("2.3"), max: Gem::Version.new("2.5") },
    }.freeze
    APPRAISAL_ALWAYS_EXCLUDED_GEMS = %w[version_gem].freeze
    APPRAISAL_VERSION_SELECTION_MODES = %w[major minor patch minor-minmax semver].freeze
    APPRAISAL_MINIMUM_RUBY_FLOOR = Gem::Version.new("2.3")
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
      :prompt,
      keyword_init: true
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
          prompt: prompt,
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
            choices: DECISION_ACTIONS,
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
          prompt_answers: prompt_answers.empty? ? nil : prompt_answers,
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

    module ReadmePostProcessor
      module_function

      ENGINE_COMPATIBILITY_MRI_VERSION = {
        "jruby" => {
          "9.1" => Gem::Version.new("2.3"),
          "9.2" => Gem::Version.new("2.5"),
          "9.3" => Gem::Version.new("2.6"),
          "9.4" => Gem::Version.new("3.1"),
          "10.0" => Gem::Version.new("3.4"),
        }.freeze,
        "truby" => {
          "22.3" => Gem::Version.new("3.0"),
          "23.0" => Gem::Version.new("3.0"),
          "23.1" => Gem::Version.new("3.1"),
          "24.2" => Gem::Version.new("3.3"),
          "25.0" => Gem::Version.new("3.3"),
          "33.0" => Gem::Version.new("3.3"),
        }.freeze,
      }.freeze
      COMPATIBILITY_ROW_PREFIX_RE = /\A\| Works with (?:MRI Ruby|JRuby|Truffle Ruby)/
      COMPATIBILITY_REFERENCE_LABEL_RE = /\A(?:💎(?:ruby|jruby|truby)-|🚎)/
      ENGINE_ROW_PATTERNS = {
        "jruby" => {
          row_re: /\A\| Works with JRuby/,
          badge_prefixes: %w[💎jruby-],
          ref_prefixes: [/\A🚎jruby-/, /\A🚎\d+-j-/],
        }.freeze,
        "truffleruby" => {
          row_re: /\A\| Works with Truffle Ruby/,
          badge_prefixes: %w[💎truby-],
          ref_prefixes: [/\A🚎truby-/, /\A🚎\d+-t-/],
        }.freeze,
      }.freeze

      def process(content:, min_ruby:, engines: nil, workflow_paths: nil)
        processed = content.to_s
        processed = remove_disabled_engine_content(processed, engines) if engines
        processed = remove_missing_workflow_badges(processed, workflow_paths) if workflow_paths
        return processed if min_ruby.to_s.empty?

        processed = remove_incompatible_compatibility_badges(processed, Gem::Version.new(min_ruby.to_s))
        processed = normalize_compatibility_rows(processed)
        prune_unused_compatibility_reference_definitions(processed)
      end

      def remove_disabled_engine_content(content, engines)
        enabled = Array(engines).map { |engine| engine.to_s.strip.downcase }
        processed = content.to_s

        ENGINE_ROW_PATTERNS.each do |engine, patterns|
          next if enabled.include?(engine)

          processed = processed.lines.reject { |line| patterns.fetch(:row_re).match?(line) }.join
          labels = processed.scan(/\[(💎(?:ruby|jruby|truby)-[^\]]+)\]/).flatten.uniq
          labels.each do |label|
            next unless patterns.fetch(:badge_prefixes).any? { |prefix| label.start_with?(prefix) }

            processed = remove_badge_occurrences(processed, label)
          end
          processed = processed.lines.reject do |line|
            ref_label = line[/^\[([^\]]+)\]:/, 1]
            ref_label && patterns.fetch(:ref_prefixes).any? { |pattern| pattern.match?(ref_label) }
          end.join
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
        content.to_s.lines.each_with_object({}) do |line, references|
          label, url = line.match(/^\[([^\]]+)\]:\s+(\S+)/)&.captures
          next unless label && url

          workflow = url[%r{/actions/workflows/([^/?#]+)}, 1]
          next unless workflow

          references[label] = ".github/workflows/#{workflow}"
        end
      end

      def remove_workflow_badge_occurrences(content, workflow_label)
        label_re = Regexp.escape(workflow_label)
        content.gsub(/[ \t]*\[!\[[^\]]*?\]\s*\[[^\]]+\]\]\s*\[#{label_re}\][ \t]*/, " ")
      end

      def remove_incompatible_compatibility_badges(content, min_ruby)
        content.scan(/\[(💎(?:ruby|jruby|truby)-[^\]]+)\]/).flatten.uniq.each do |label|
          badge_min_mri = compatibility_badge_min_mri(label)
          next unless badge_min_mri && badge_min_mri < min_ruby

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
      rescue StandardError
        nil
      end

      def remove_badge_occurrences(content, label)
        label_re = Regexp.escape(label)
        content = content.gsub(/\s*\[!\[[^\]]*?\]\s*\[#{label_re}\]\s*\]\s*\[[^\]]+\]\s*/, " ")
        content.gsub(/\s*!\[[^\]]*?\]\s*\[#{label_re}\]\s*/, " ")
      end

      def normalize_compatibility_rows(content)
        content.lines.filter_map do |line|
          next line unless COMPATIBILITY_ROW_PREFIX_RE.match?(line)

          cells = line.split("|", -1)
          badge_cell = normalize_compatibility_badge_cell(cells[2])
          next if badge_cell.empty?

          cells[2] = " #{badge_cell}"
          cells.join("|")
        end.join
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
        referenced_labels = {}
        content.lines.each do |line|
          next if line.match?(/^\[[^\]]+\]:/)

          line.scan(/\]\[([^\]]+)\]/) { |match| referenced_labels[match.first] = true }
        end

        content.lines.reject do |line|
          label = line[/^\[([^\]]+)\]:/, 1]
          label && COMPATIBILITY_REFERENCE_LABEL_RE.match?(label) && !referenced_labels[label]
        end.join
      end
    end

    class RubyGemsResolver
      RUBYGEMS_V1_API_BASE = "https://rubygems.org/api/v1"
      RUBYGEMS_V2_API_BASE = "https://rubygems.org/api/v2/rubygems"

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
            prerelease: !!entry["prerelease"],
          }
        end.sort_by { |entry| Gem::Version.new(entry.fetch(:number)) }
      end

      def version_info(gem_name, version)
        data = fetch_gem_info(gem_name, version)
        return unless data

        runtime_dependencies = Array(data.dig("dependencies", "runtime")).map do |dependency|
          {
            name: dependency["name"],
            requirements: dependency["requirements"],
          }
        end

        {
          number: data["number"] || version.to_s,
          ruby_version: data["ruby_version"],
          runtime_dependencies: runtime_dependencies,
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
            minors: minors.to_a.sort_by { |minor| Gem::Version.new(minor) },
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
    README_DEFAULT_PRESERVE_SECTIONS = ["synopsis", "configuration", "basic usage"].freeze
    README_DEFAULT_PRESERVE_PATTERNS = ["note:*"].freeze
    README_CODETRIAGE_BADGE = "[![Open Source Helpers][👽oss-helpi]][👽oss-help]"
    README_CODETRIAGE_LINK_LABELS = ["👽oss-help", "👽oss-helpi"].freeze
    README_LICENSE_EYE_WORKFLOW_BADGE = "[![Apache SkyWalking Eyes License Compatibility Check][🚎15-🪪-wfi]][🚎15-🪪-wf]"
    README_LICENSE_EYE_WORKFLOW_LINK_LABELS = ["🚎15-🪪-wf", "🚎15-🪪-wfi"].freeze
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
      "🖇osc-sponsors-bottom-img",
    ].freeze
    README_INTEGRATIONS = %w[codecov coveralls qlty codeql].freeze
    README_INTEGRATION_BADGE_PATTERNS = {
      "codecov" => [
        /\s*\[!\[CodeCov Test Coverage\]\[[^\]]+\]\]\[[^\]]+\]/,
        /\n\[!\[Coverage Graph\]\[[^\]]+\]\]\[[^\]]+\]\n/,
      ],
      "coveralls" => [
        /\s*\[!\[Coveralls Test Coverage\]\[[^\]]+\]\]\[[^\]]+\]/,
      ],
      "qlty" => [
        /\s*\[!\[QLTY Test Coverage\]\[[^\]]+\]\]\[[^\]]+\]/,
        /\s*\[!\[QLTY Maintainability\]\[[^\]]+\]\]\[[^\]]+\]/,
      ],
      "codeql" => [
        /\s*\[!\[CodeQL\]\[[^\]]+\]\]\[[^\]]+\]/,
      ],
    }.freeze
    README_INTEGRATION_LINK_LABELS = {
      "codecov" => %w[🏀codecov 🏀codecovi 🏀codecov-g],
      "coveralls" => %w[🏀coveralls 🏀coveralls-img],
      "qlty" => %w[🏀qlty-mnt 🏀qlty-mnti 🏀qlty-cov 🏀qlty-covi],
      "codeql" => %w[🖐codeQL 🖐codeQL-img],
    }.freeze
    README_SECTION_ALIASES = {
      "summary" => "synopsis",
      "usage" => "basic usage",
      "configuration options" => "configuration",
      "setup" => "basic usage",
    }.freeze
    README_STATIC_TOP_LOGO_ROW = "[![Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-i]][🖼️galtzo-discord] [![ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang]"
    README_STATIC_TOP_LOGO_REFS = [
      "[🖼️galtzo-i]: https://logos.galtzo.com/assets/images/galtzo-floss/avatar-192px.svg",
      "[🖼️galtzo-discord]: https://discord.gg/3qme4XHNKN",
      "[🖼️ruby-lang-i]: https://logos.galtzo.com/assets/images/ruby-lang/avatar-192px.svg",
      "[🖼️ruby-lang]: https://www.ruby-lang.org/",
    ].join("\n").freeze
    VAR_HOME_PREFIX = %r{\A/var/home(?=/|\z)}
    VAR_HOME_TEXT = %r{/var/home(?=/|\z)}
    RUBOCOP_VERSION_MAP = [
      [Gem::Version.new("1.8"), "~> 0.1"],
      [Gem::Version.new("1.9"), "~> 2.0"],
      [Gem::Version.new("2.0"), "~> 4.0"],
      [Gem::Version.new("2.1"), "~> 6.0"],
      [Gem::Version.new("2.2"), "~> 8.0"],
      [Gem::Version.new("2.3"), "~> 10.0"],
      [Gem::Version.new("2.4"), "~> 12.0"],
      [Gem::Version.new("2.5"), "~> 14.0"],
      [Gem::Version.new("2.6"), "~> 16.0"],
      [Gem::Version.new("2.7"), "~> 18.0"],
      [Gem::Version.new("3.0"), "~> 20.0"],
      [Gem::Version.new("3.1"), "~> 22.0"],
      [Gem::Version.new("3.2"), "~> 24.0"],
    ].freeze
    FORGE_USER_ENV_KEYS = {
      gh_user: "KJ_GH_USER",
      gl_user: "KJ_GL_USER",
      cb_user: "KJ_CB_USER",
      sh_user: "KJ_SH_USER",
    }.freeze
    FUNDING_TOKEN_ENV_KEYS = {
      patreon: "KJ_FUNDING_PATREON",
      kofi: "KJ_FUNDING_KOFI",
      paypal: "KJ_FUNDING_PAYPAL",
      buymeacoffee: "KJ_FUNDING_BUYMEACOFFEE",
      polar: "KJ_FUNDING_POLAR",
      liberapay: "KJ_FUNDING_LIBERAPAY",
      issuehunt: "KJ_FUNDING_ISSUEHUNT",
    }.freeze
    SOCIAL_TOKEN_ENV_KEYS = {
      mastodon: "KJ_SOCIAL_MASTODON",
      bluesky: "KJ_SOCIAL_BLUESKY",
      linktree: "KJ_SOCIAL_LINKTREE",
      devto: "KJ_SOCIAL_DEVTO",
    }.freeze
    APACHE_LICENSE_COMPAT_CATEGORIES = {
      "Apache-2.0" => :a,
      "MIT" => :a,
      "AGPL-3.0-only" => :x,
      "PolyForm-Noncommercial-1.0.0" => :x,
      "PolyForm-Small-Business-1.0.0" => :x,
      "LicenseRef-Big-Time-Public-License" => :x,
    }.freeze
    APACHE_LICENSE_COMPAT_BADGE_DATA = {
      a: {
        alt: "Apache license compatibility: Category A",
        label: "Apache_Compatible:_Category_A",
        message: "\u2713",
        color: "259D6C",
        ref: "https://www.apache.org/legal/resolved.html#category-a",
      },
      b: {
        alt: "Apache license compatibility: Category B",
        label: "Apache_Maybe_Compatible:_Category_B",
        message: "?",
        color: "D9A407",
        ref: "https://www.apache.org/legal/resolved.html#category-b",
      },
      x: {
        alt: "Apache license compatibility: Category X",
        label: "Apache_Incompatible:_Category_X",
        message: "\u2717",
        color: "C0392B",
        ref: "https://www.apache.org/legal/resolved.html#category-x",
      },
      unknown: {
        alt: "Apache license compatibility: Unknown",
        label: "Apache_Compatibility",
        message: "Unknown",
        color: "6C757D",
        ref: "https://www.apache.org/legal/resolved.html",
      },
    }.freeze

    class PluginRegistry
      Hook = Struct.new(:plugin_name, :phase, :timing, :callback, keyword_init: true)
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
      attr_reader :project_root, :mode, :facts, :recipe_pack, :recipe_reports, :phase_reports,
        :changed_files, :diagnostics, :helpers, :out

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
        @changed_files << relative_path unless @changed_files.include?(relative_path)
        @diagnostics << {
          kind: "plugin_file_change",
          path: relative_path,
          action: action.to_s
        }
      end

      private

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
        @diagnostics << { kind: "plugin_detail", message: message.to_s }
      end

      def warning(message)
        @diagnostics << { kind: "plugin_warning", message: message.to_s }
      end
    end

    module TemplateChecksums
      YAML_KEY = "kettle-jem"
      CHECKSUMS_SUBKEY = "checksums"
      VERSION_SUBKEY = "version"

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

        data = YAML.safe_load_file(config_path.to_s, permitted_classes: [], aliases: false)
        entry = data.is_a?(Hash) ? data[YAML_KEY] : nil
        stored = entry.is_a?(Hash) ? entry[CHECKSUMS_SUBKEY] : nil
        stored.is_a?(Hash) ? stored : {}
      rescue StandardError
        {}
      end

      def diff(current:, stored:)
        current_keys = current.keys.to_set
        stored_keys = stored.keys.to_set

        {
          added: (current_keys - stored_keys).sort,
          changed: (current_keys & stored_keys).select { |path| current[path] != stored[path] }.sort,
          removed: (stored_keys - current_keys).sort,
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
          *diff.fetch(:removed, []).map { |path| "  - #{path}" },
        ]
      end

      def build_yaml_block(checksums:, version: nil)
        lines = [YAML_KEY]
        lines[0] = "#{lines[0]}:"
        lines << "  #{VERSION_SUBKEY}: #{version.to_s.dump}" if version
        lines << "  #{CHECKSUMS_SUBKEY}:"
        checksums.sort.each do |path, sha|
          lines << "    #{path.dump}: #{sha.dump}"
        end
        lines.join("\n")
      end

      def write_to_config(config_path:, checksums:, version: nil)
        return unless File.exist?(config_path.to_s)

        content = File.read(config_path.to_s)
        new_block = build_yaml_block(checksums: checksums, version: version)
        updated =
          if content.match?(/^#{Regexp.escape(YAML_KEY)}:\s*(?:#[^\n]*)?\n/)
            content.gsub(/^#{Regexp.escape(YAML_KEY)}:[^\n]*\n(?:[ \t][^\n]*\n)*/, "#{new_block}\n")
          else
            "#{content.rstrip}\n\n#{new_block}\n"
          end
        File.write(config_path.to_s, updated)
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
          merge_gems: MERGE_GEM_NAMES.map { |name| build_entry(name, loaded_specs[name], workspace_root: workspace_root) },
        }
      end

      def build_entry(name, spec, workspace_root:)
        path = spec&.full_gem_path.to_s
        {
          name: name,
          version: spec&.version&.to_s,
          path: path.empty? ? nil : path,
          local_path: !path.empty? && local_path?(path, workspace_root: workspace_root),
          loaded: !spec.nil?,
        }
      end

      def default_workspace_root
        env_root = ENV["KETTLE_RB_DEV"].to_s.strip
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
      rescue StandardError
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
          "Hint: set KETTLE_RB_DEV=true (or configure it in .env.local) to use sibling workspace gems.",
        ]
      end

      def local_warning_section(warning)
        <<~MARKDOWN.chomp
          ## Local Workspace Warning

          #{warning}

          Set `KETTLE_RB_DEV=true` (or configure it in `.env.local`) to use sibling workspace gems instead of the installed release.
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

        env_value = ENV.fetch("KETTLE_RB_DEV", "<unset>")
        "Detected sibling workspace checkout at `#{Kettle::Jem.display_path(local_checkout)}`, but this run is using installed `kettle-jem` " \
          "(KETTLE_RB_DEV=#{env_value.inspect})."
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
          rescue StandardError
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
          a = File.exist?(file_a.to_s) ? file_a.to_s : "/dev/null"
          b = File.exist?(file_b.to_s) ? file_b.to_s : "/dev/null"
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
          lines << "<details>"
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
      autoload :InstallTask, "kettle/jem/tasks/install_task"
      autoload :PrepareTask, "kettle/jem/tasks/prepare_task"
      autoload :SelfTestTask, "kettle/jem/tasks/self_test_task"
      autoload :TemplateTask, "kettle/jem/tasks/template_task"
    end

    module_function

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
        checksums: TemplateChecksums.compute(template_root: root),
      }
    end

    def install_tasks
      require "rake"
      load File.expand_path("jem/tasks.rb", __dir__)
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
        appraisal_format_version(tier1_version),
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
        %(gem "#{gem_name}", "#{appraisal_version_requirement(version)}"),
      ]
      sub_dependencies.each do |name, requirement|
        lines << %(gem "#{name}", "~> #{requirement}")
      end
      ensure_trailing_newline(lines.join("\n"))
    end

    def appraisal_version_requirement(version)
      segments = version.to_s.split(".")
      segments.length >= 3 ? "~> #{version}" : "~> #{version}.0"
    end

    def appraisal_file_content(matrix_entries)
      lines = [
        "# frozen_string_literal: true",
        "",
        "# Generated by kettle-jem",
        "# Do not edit directly; regenerate from Kettle/Jem appraisal matrix metadata.",
        "",
      ]
      matrix_entries.each do |entry|
        lines << %(appraise "#{entry.fetch(:name)}" do)
        lines << %(  eval_gemfile "#{entry.fetch(:tier1_gemfile)}") if entry[:tier1_gemfile]
        lines << %(  eval_gemfile "#{entry.fetch(:tier2_gemfile)}") if entry[:tier2_gemfile]
        lines << %(  eval_gemfile "#{entry.fetch(:x_std_libs_gemfile)}") if entry[:x_std_libs_gemfile]
        lines << "end"
        lines << ""
      end
      ensure_trailing_newline(lines.join("\n"))
    end

    def appraisal_workflow_groups(matrix_entries, bucket_ranges:, exec_cmd: "rake spec")
      grouped = Hash.new { |hash, key| hash[key] = [] }
      normalized_ranges = bucket_ranges.transform_values do |range|
        {
          floor: Gem::Version.new((range[:floor] || range["floor"]).to_s),
          ceiling: Gem::Version.new((range[:ceiling] || range["ceiling"]).to_s),
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
          gemfile: "Appraisal.root",
          rubygems: "latest",
          bundler: "latest",
        }
      end
      grouped.transform_values { |entries| entries.sort_by { |entry| entry.fetch(:appraisal).to_s } }
    end

    def appraisal_workflow_yaml_snippets(matrix_entries, bucket_ranges:, exec_cmd: "rake spec")
      appraisal_workflow_groups(matrix_entries, bucket_ranges: bucket_ranges, exec_cmd: exec_cmd).transform_values do |entries|
        lines = ["strategy:", "  matrix:", "    include:"]
        entries.each do |entry|
          lines << %(      - ruby: "#{entry.fetch(:ruby)}")
          lines << %(        appraisal: "#{entry.fetch(:appraisal)}")
          lines << %(        exec_cmd: "#{entry.fetch(:exec_cmd)}")
          lines << %(        gemfile: "#{entry.fetch(:gemfile)}")
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
      ruby_floor < APPRAISAL_WORKFLOW_LIFECYCLE_RANGES.fetch("ancient").fetch(:min) ? "ancient" : "current"
    end

    def appraisal_workflow_ruby(ruby_floor, lifecycle)
      return "ruby" if lifecycle == "current"

      segments = ruby_floor.segments
      "#{segments[0]}.#{segments[1] || 0}"
    end

    def appraisal_x_stdlib_exclusions(template_content)
      gems = template_content.to_s.lines.filter_map do |line|
        line[%r{eval_gemfile\s+["']\.\./([\w-]+)/}, 1]
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
          entry.fetch(:major) < current_major ? [minors.first, minors.last].uniq : minors
        end
      when "semver"
        by_major.flat_map do |entry|
          entry.fetch(:major) < current_major ? [entry.fetch(:minors).last] : entry.fetch(:minors)
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
              ruby_series: ruby_series,
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
                  tier2_version: tier2_version,
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
          ruby_series: ruby_series,
        ),
        tier1_gemfile: appraisal_modular_gemfile_path(gem_name: tier1_name, version: tier1_version, ruby_series: ruby_series),
        tier2_gemfile: tier2_name ? appraisal_modular_gemfile_path(gem_name: tier2_name, version: tier2_version, ruby_series: ruby_series) : nil,
        x_std_libs_gemfile: File.join("gemfiles", "modular", "x_std_libs", ruby_series.to_s, "libs.gemfile"),
        ruby_series: ruby_series.to_s,
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
          minor: "#{segments[0]}.#{segments[1] || 0}",
        }
      end.uniq.group_by { |entry| entry.fetch(:major) }.map do |major, entries|
        {
          major: major,
          minors: entries.map { |entry| entry.fetch(:minor) }.sort_by { |minor| Gem::Version.new(minor) },
        }
      end.sort_by { |entry| entry.fetch(:major) }
    end

    def appraisal_find_ruby_seams(version_metadata)
      minors = appraisal_latest_patch_by_minor(version_metadata)
      seams = []
      previous = nil
      minors.sort_by { |minor, _entry| Gem::Version.new(minor) }.each do |minor, entry|
        min_ruby = Gem::Version.new((entry[:min_ruby] || entry["min_ruby"]).to_s)
        min_ruby = [min_ruby, APPRAISAL_MINIMUM_RUBY_FLOOR].max
        if previous.nil? || min_ruby > previous
          seams << { version: minor, min_ruby: min_ruby }
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
        { version: version, bucket: bucket } if bucket
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
          bucket = index == sorted.length - 1 ? "r#{major}" : "r#{major}.#{[sorted[index + 1].split(".").last.to_i - 1, minor.split(".").last.to_i].max}"
          next if ranges.key?(bucket)

          buckets << bucket
          ceiling = index == sorted.length - 1 ? "#{major}.99" : bucket.split(".").last ? "#{major}.#{bucket.split(".").last}" : "#{major}.99"
          ranges[bucket] = { floor: Gem::Version.new(minor), ceiling: Gem::Version.new(ceiling) }
        end
      end
      { buckets: buckets.sort_by { |bucket| appraisal_bucket_sort_key(bucket) }, bucket_ranges: ranges }
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
          ceiling: Gem::Version.new((range[:ceiling] || range["ceiling"]).to_s),
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
          current = [current, APPRAISAL_MINIMUM_RUBY_FLOOR].max
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
          ruby && ruby.between?(range.fetch(:floor), range.fetch(:ceiling))
        end
        filler ||= all_versions.sort_by { |version| Gem::Version.new(version) }.reverse.find do |version|
          ruby = version_min_rubies[version]
          ruby && ruby <= range.fetch(:ceiling)
        end
        assignments << { version: filler, bucket: bucket, filler: true } if filler
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
      gemspec_content.to_s.lines.filter_map do |line|
        stripped = line.lstrip
        next if stripped.start_with?("#")

        stripped[/add_(?:runtime_)?dependency\s*\(?\s*["']([^"']+)["']/, 1]
      end.uniq
    end

    def appraisal_scaffold_config(gemspec_content:, existing_config: {}, exclusions: [], default_mode: "semver", freshness_ttl: APPRAISAL_DEFAULT_FRESHNESS_TTL)
      excluded = exclusions.map(&:to_s).to_set
      runtime_dependencies = appraisal_extract_runtime_dependencies(gemspec_content)
      tier1 = runtime_dependencies.reject { |name| excluded.include?(name) }.map { |name| { "name" => name } }
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

      ceiling = Gem::Version.new(((range[:ceiling] || range["ceiling"]).to_s))
      exact_version = appraisal_latest_minor_patch(resolver: resolver, gem_name: gem_name, version: version)
      min_ruby = resolver.min_ruby_version(gem_name, exact_version)
      min_ruby.nil? || Gem::Version.new(min_ruby.to_s) <= ceiling
    rescue StandardError
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

    def discover_monorepo_root_facts(project_root, kettle_config, env, template_selection)
      source_url = git_remote_source_url(project_root)
      package_name = repository_name_from_source_url(source_url)
      package_name = File.basename(project_root.to_s) if package_name.empty?
      license = license_facts(kettle_config, Array(kettle_config["licenses"]), author: {}, author_email: nil, copyright: {})
      author = author_facts("", kettle_config, env)
      copyright = copyright_facts(project_root, kettle_config)
      project_runtime = project_runtime_facts(
        kettle_config,
        env,
        package_name: package_name,
        source_url: source_url,
        author_domain: author[:domain],
        min_ruby: nil,
        version: nil
      )
      facts = {
        package: compact_hash(
          ecosystem: "monorepo",
          name: package_name,
          slug: package_name,
          description: "#{package_name} monorepo",
          homepage_url: source_url,
          source_url: source_url,
          license_expression: license[:expression],
        ),
        rubygems: compact_hash(
          namespace: classify_namespace(package_name),
          min_ruby: nil,
          engines: ruby_engines_config(kettle_config),
        ),
        template_profile: MONOREPO_ROOT_TEMPLATE_PROFILE,
      }
      bootstrap = kettle_config_bootstrap_facts(project_root, env, template_selection: template_selection)
      bootstrap[:licenses] = Array(kettle_config["licenses"]) if bootstrap && kettle_config["licenses"]
      facts[:kettle_config_bootstrap] = bootstrap if bootstrap
      facts[:author] = author unless author.empty?
      facts[:copyright] = copyright unless copyright.empty?
      forge = forge_facts(kettle_config, env, derived_github_user: nil)
      social = social_facts(kettle_config, env)
      facts[:forge] = forge unless forge.empty?
      facts[:social] = social unless social.empty?
      facts[:license] = license unless license.empty?
      facts[:project_runtime] = project_runtime unless project_runtime.empty?
      funding = compact_hash(
        urls: funding_urls(project_root, "", package_name, opencollective_disabled: false),
        platform_tokens: funding_platform_token_facts(kettle_config, env)
      )
      detected_open_collective_org = opencollective_org(project_root, env, opencollective_disabled: false)
      if detected_open_collective_org
        funding[:open_collective_org] = detected_open_collective_org.fetch(:org)
        funding[:open_collective_org_source] = detected_open_collective_org.fetch(:source)
      end
      facts[:funding] = funding unless funding.empty?
      readme_logo = readme_logo_facts(kettle_config, package_name: package_name, github_org: project_runtime[:github_org])
      facts[:readme_logo] = readme_logo unless readme_logo.empty?
      template_facts = {}
      template_preferences = template_source_preferences(
        project_root,
        kettle_config,
        opencollective_disabled: false,
        include_patterns: template_selection[:include]
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
      configured_template_profile = kettle_config.dig("templates", "profile").to_s
      if template_selection[:template_profile].to_s.empty? && !configured_template_profile.empty?
        template_selection[:template_profile] = configured_template_profile
      end
      gemspec_path = Dir.glob(File.join(project_root, "*.gemspec")).sort.first
      if !gemspec_path && template_selection[:template_profile].to_s == MONOREPO_ROOT_TEMPLATE_PROFILE
        return discover_monorepo_root_facts(project_root, kettle_config, env, template_selection)
      end
      raise ArgumentError, "no gemspec found in #{project_root}" unless gemspec_path

      gemspec = File.read(gemspec_path)
      name = extract_gemspec_assignment(gemspec, "spec.name") || File.basename(gemspec_path, ".gemspec")
      homepage_url = extract_gemspec_assignment(gemspec, "spec.homepage")
      metadata_source_url = extract_metadata_value(gemspec, "source_code_uri")
      metadata_github_url = concrete_github_url(metadata_source_url)
      homepage_github_url = concrete_github_url(homepage_url)
      git_source_url = git_remote_source_url(project_root)
      git_github_url = concrete_github_url(git_source_url)
      source_url = metadata_github_url ||
        homepage_github_url ||
        git_github_url ||
        metadata_source_url ||
        homepage_url ||
        git_source_url
      derived_github_user = git_github_url && source_url == git_github_url ? github_org_from_url(git_github_url) : nil
      entrypoint_require = name.tr("-", "/")
      version_path = File.join("lib", entrypoint_require, "version.rb")
      entrypoint_path = File.join("lib", "#{entrypoint_require}.rb")
      namespace = existing_entrypoint_version_namespace(project_root, entrypoint_path) ||
        existing_version_namespace(project_root, version_path) ||
        classify_namespace(name)

      author = author_facts(gemspec, kettle_config, env)
      copyright = copyright_facts(project_root, kettle_config)
      license = license_facts(
        kettle_config,
        extract_gemspec_array(gemspec, "spec.licenses"),
        author: author,
        author_email: author[:email],
        copyright: copyright
      )
      gemspec_license_spdx = extract_gemspec_array(gemspec, "spec.licenses")
        .map { |license_id| license_id.to_s.strip }
        .reject(&:empty?)
      project_runtime = project_runtime_facts(
        kettle_config,
        env,
        package_name: name,
        source_url: source_url,
        author_domain: author[:domain],
        min_ruby: extract_gemspec_assignment(gemspec, "spec.required_ruby_version"),
        version: extract_gemspec_assignment(gemspec, "spec.version")
      )
      facts = {
        package: compact_hash(
          ecosystem: "rubygems",
          name: name,
          slug: name,
          description: extract_gemspec_assignment(gemspec, "spec.description") ||
            extract_gemspec_assignment(gemspec, "spec.summary"),
          homepage_url: homepage_url,
          source_url: source_url,
          license_expression: license[:expression],
        ),
        rubygems: compact_hash(
          gemspec_path: File.basename(gemspec_path),
          namespace: namespace,
          min_ruby: extract_gemspec_assignment(gemspec, "spec.required_ruby_version"),
          engines: ruby_engines_config(kettle_config),
        ),
      }
      repository = repository_facts(project_root, source_url, package_name: name, template_profile: template_selection[:template_profile])
      facts[:repository] = repository unless repository.empty?
      generated_blocks = generated_blocks_facts(gemspec, facts, run_options)
      facts[:generated_blocks] = generated_blocks unless generated_blocks.empty?
      bootstrap = kettle_config_bootstrap_facts(project_root, env, template_selection: template_selection)
      bootstrap[:licenses] = gemspec_license_spdx if bootstrap && !gemspec_license_spdx.empty?
      bootstrap[:gemspec_path] = File.basename(gemspec_path) if bootstrap && gemspec_path
      if bootstrap
        project_emoji = preferred_template_token_value(nil, nil, env, "KJ_PROJECT_EMOJI")
        project_emoji ||= readme_project_emoji(project_root)
        project_emoji ||= "💎" if template_selection[:template_profile].to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE
        bootstrap[:project_emoji] = project_emoji
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
      open_collective_org = opencollective_org(project_root, env, opencollective_disabled: opencollective_disabled)
      funding = compact_hash(
        urls: funding_urls(
          project_root,
          gemspec,
          name,
          opencollective_disabled: opencollective_disabled,
          open_collective_org: open_collective_org && open_collective_org.fetch(:org)
        )
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
      opt_in_workflows = opt_in_workflow_cleanup_files(project_root, template_selection)
      facts[:template_profile] = template_selection[:template_profile] unless template_selection[:template_profile].to_s.empty?
      facts[:ci] = {
        provider: "github_actions",
        default_branch: "main",
        ruby_versions: github_actions_ruby_versions(facts.fetch(:rubygems).fetch(:min_ruby, nil)),
        obsolete_workflows: github_actions_obsolete_workflows(project_root),
        custom_workflows: github_actions_custom_workflows(project_root, opencollective_disabled: opencollective_disabled),
      }
      facts[:ci][:opt_in_workflow_cleanups] = opt_in_workflows unless opt_in_workflows.empty?
      coverage_config = github_actions_coverage_config(kettle_config)
      facts[:ci][:coverage] = coverage_config unless coverage_config.empty?
      framework_matrix = github_actions_framework_matrix(kettle_config)
      facts[:ci][:framework_matrix] = framework_matrix unless framework_matrix.empty?
      template_facts = {}
      template_config = template_runtime_config(kettle_config, facts, license: license)
      template_preferences = template_source_preferences(
        project_root,
        template_config,
        opencollective_disabled: opencollective_disabled,
        include_patterns: template_selection[:include]
      )
      template_facts[:source_preferences] = template_preferences unless template_preferences.empty?
      legacy_cleanups = template_legacy_destination_cleanups(project_root, template_preferences)
      template_facts[:legacy_destination_cleanups] = legacy_cleanups unless legacy_cleanups.empty?
      license_cleanups = template_obsolete_license_cleanups(project_root, template_config, template_preferences)
      template_facts[:obsolete_license_cleanups] = license_cleanups unless license_cleanups.empty?
      unless template_preferences.empty?
        facts[:license] = license unless license.empty?
        facts[:project_runtime] = project_runtime unless project_runtime.empty?
        readme_logo = readme_logo_facts(kettle_config, package_name: name, github_org: project_runtime[:github_org])
        facts[:readme_logo] = readme_logo unless readme_logo.empty?
        readme_style = readme_style_facts(
          project_root,
          kettle_config,
          license,
          template_profile: template_selection[:template_profile],
          repository: facts[:repository]
        )
        facts[:readme_style] = readme_style unless readme_style.empty?
        template_tokens = template_tokens(facts, funding)
        template_facts[:tokens] = template_tokens unless template_tokens.empty?
      end
      facts[:templates] = template_facts unless template_facts.empty?
      facts
    end

    def recipe_pack(facts)
      recipes = if monorepo_template_profile?(facts)
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
          ),
        ]
      end
      if facts[:kettle_config_bootstrap]
        recipes.unshift(kettle_config_bootstrap_recipe(facts.fetch(:kettle_config_bootstrap)))
      end
      unless monorepo_template_profile?(facts)
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
      recipes << recipe_entry(
        "rakefile_scaffold_cleanup",
        "Rakefile",
        "generic_ast",
        "supplied_source_selector_deletion",
        provider_backend: "generic_structural_owners",
        facts: %w[rubygems rakefile],
        selectors: %w[rakefile_scaffold]
      )

      {
        name: "kettle-jem-core",
        version: 1,
        ecosystem: "rubygems",
        recipes: recipes,
      }
    end

    def generated_blocks_facts(gemspec, facts, run_options)
      shunted = shunted_gemfile_block(gemspec, facts, run_options)
      shunted ? { shunted_gemfile: shunted } : {}
    end

    def shunted_gemfile_block(gemspec, facts, run_options)
      resolver = run_options[:rubygems_resolver] || run_options["rubygems_resolver"] || RubyGemsResolver.new
      dependencies = extract_gemspec_development_dependencies(gemspec)
      return nil if dependencies.empty?

      floor = shunted_effective_floor(facts.dig(:rubygems, :min_ruby))
      shunted = dependencies.filter_map do |dependency|
        versions = resolver.versions(dependency.fetch(:name), requirements: dependency[:requirement])
        version = versions.max_by { |entry| Gem::Version.new((entry[:number] || entry["number"]).to_s) }
        next unless version

        number = (version[:number] || version["number"]).to_s
        min_ruby = resolver.min_ruby_version(dependency.fetch(:name), number) ||
          resolver.parse_min_ruby(version[:ruby_version] || version["ruby_version"])
        next unless min_ruby && Gem::Version.new(min_ruby.to_s) > floor

        dependency.merge(version: number, min_ruby: min_ruby.to_s)
      rescue StandardError
        nil
      end
      return nil if shunted.empty?

      shunted_gemfile_managed_block(shunted)
    rescue StandardError
      nil
    end

    def extract_gemspec_development_dependencies(gemspec)
      gemspec_dependency_records(gemspec).filter_map do |record|
        next unless record.fetch(:kind) == "add_development_dependency"

        { name: record.fetch(:name), requirement: record[:requirement] }
      end.uniq { |dependency| dependency.fetch(:name) }
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
        MANAGED_BLOCK_OPEN,
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
      preflight_project!(project_root)
      template_selection = template_selection_for(env, run_options)
      decision_policy = decision_policy_for(env, run_options)
      git_preflight = git_preflight_report(project_root, template_selection: template_selection)
      enforce_git_preflight!(git_preflight, decision_policy: decision_policy, template_selection: template_selection)
      facts = discover_facts(project_root, env: env, run_options: run_options)
      pack = recipe_pack(facts)
      pack = filter_recipe_pack(pack, template_selection)
      files = read_project_files(project_root, pack)
      recipe_reports = pack.fetch(:recipes).map do |recipe|
        execute_recipe(project_root: project_root, recipe: recipe, facts: facts, files: files, decision_policy: decision_policy)
      end
      plugin_registry = plugin_registry_for_project(project_root)
      changed_files = recipe_reports.filter_map { |report| report[:relative_path] if report[:changed] }.uniq.sort
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
      run_stats = recipe_run_stats(recipe_reports, diagnostics: diagnostics)

      {
        mode: "plan",
        ready: true,
        facts: facts,
        recipe_pack: pack,
        recipe_reports: recipe_reports,
        phase_reports: phase_reports,
        decision_policy: decision_policy.to_h,
        template_selection: template_selection,
        git_preflight: git_preflight,
        decision_evaluations: decision_evaluations,
        prompt_requests: prompt_requests,
        changed_files: changed_files,
        diagnostics: diagnostics,
        run_stats: run_stats,
      }
    end

    def apply_project(project_root, env: ENV, run_options: {})
      report = plan_project(project_root, env: env, run_options: run_options).merge(mode: "apply")
      run_apply_phases(project_root, report)
      report[:post_apply_steps] = post_apply_steps(project_root, report)
      report[:changed_files] = (report.fetch(:changed_files, []) + report.fetch(:post_apply_steps).flat_map do |step|
        step.fetch(:changed_files, [])
      end).uniq.sort
      report[:duplicate_drift] = duplicate_drift_report(
        project_root: project_root,
        template_root: template_root_path(project_root, config: kettle_jem_config(project_root)),
        run_options: run_options
      )
      report
    end

    def post_apply_steps(project_root, report)
      [
        template_version_gem_bootstrap_step(project_root, report),
      ].compact
    end

    def template_version_gem_bootstrap_step(project_root, report)
      gemspec_report = report.fetch(:recipe_reports, []).find do |recipe_report|
        recipe_report.fetch(:relative_path, "").end_with?(".gemspec")
      end
      gemspec_content = gemspec_report&.fetch(:final_content, "").to_s
      gemspec_content = project_gemspec_content(project_root) if gemspec_content.empty?
      return nil unless gemspec_declares_version_gem?(gemspec_content)

      facts = report.fetch(:facts)
      entrypoint_require = facts.dig(:package, :name).to_s.tr("-", "/")
      templated_paths = report.fetch(:recipe_reports, []).map { |recipe_report| recipe_report.fetch(:relative_path, "") }
      version_path = File.join("lib", entrypoint_require, "version.rb")
      signature_path = File.join("sig", entrypoint_require, "version.rbs")
      version_gem_bootstrap_step_for_paths(
        project_root,
        facts,
        manage_version_file: !templated_paths.include?(version_path),
        manage_signature_file: !templated_paths.include?(signature_path)
      )
    end

    def project_gemspec_content(project_root)
      candidates = Dir.glob(File.join(project_root, "*.gemspec"))
      return "" unless candidates.length == 1

      File.read(candidates.first)
    end

    def project_gemspec_version(project_root)
      extract_gemspec_assignment(project_gemspec_content(project_root), "spec.version").to_s
    end

    def gemspec_declares_version_gem?(content)
      gemspec_dependency_records(content).any? { |record| record.fetch(:name) == "version_gem" && record.fetch(:kind) != "add_development_dependency" }
    end

    def duplicate_drift_report(project_root:, template_root:, run_options: {})
      runner = run_options[:duplicate_drift_runner] || run_options["duplicate_drift_runner"]
      unless runner
        begin
          require "kettle/drift"
          runner = Kettle::Drift
        rescue LoadError
          return {
            available: false,
            reason: "kettle-drift is not available",
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
        exit_code: outcome.respond_to?(:exit_code) ? outcome.exit_code : outcome[:exit_code],
      }.compact
    rescue StandardError => error
      {
        available: false,
        reason: "#{error.class}: #{error.message}",
      }
    end

    def setup_project(project_root, env: ENV, run_options: {}, command_runner: nil)
      root = File.expand_path(project_root.to_s)
      config_path = File.join(root, ".kettle-jem.yml")
      config_existed = File.exist?(config_path)
      execution_context = setup_execution_context(env, run_options)
      plan = plan_project(root, env: env, run_options: run_options)
      selection = plan.fetch(:template_selection)
      bootstrap_only = selection[:bootstrap_mode] || (!config_existed && !selection[:accept_config])

      if bootstrap_only
        bootstrap_report = plan.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == ".kettle-jem.yml" }
        apply_recipe_report(root, bootstrap_report) if bootstrap_report&.fetch(:changed, false)
        changed_files = bootstrap_report&.fetch(:changed, false) ? [".kettle-jem.yml"] : []
        return plan.merge(
          mode: "setup",
          setup_status: config_existed ? "bootstrap_config_already_present" : "bootstrap_config_written",
          setup_execution_context: execution_context,
          ready: config_existed,
          changed_files: changed_files,
          diagnostics: plan.fetch(:diagnostics) + [setup_guidance_diagnostic(config_existed: config_existed)],
        )
      end

      install_kwargs = {project_root: root, env: env, run_options: run_options}
      install_kwargs[:command_runner] = command_runner if command_runner
      Tasks::InstallTask.run(**install_kwargs).merge(
        mode: "setup",
        setup_execution_context: execution_context,
        setup_status: config_existed ? "configured_project_applied" : "accepted_config_applied",
      )
    end

    def plan_readme_style(project_root, env: ENV)
      facts = discover_facts(project_root, env: env)
      config = kettle_jem_config(project_root)
      readme_style = facts[:readme_style] ||
        readme_style_facts(project_root, config, facts.fetch(:license, {}), template_profile: facts[:template_profile])
      original_path = File.join(project_root, "README.md")
      original = File.exist?(original_path) ? File.read(original_path) : ""
      final_content = render_thin_readme(facts, readme_style, original, readme_preserve_config(config))

      {
        mode: "plan",
        readme_path: "README.md",
        changed: final_content != original,
        readme_style: readme_style,
        final_content: final_content,
        diagnostics: [],
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
        license_expression.empty? ? nil : "![License](https://img.shields.io/badge/license-#{shield_token(license_expression)}-259D6C.svg)",
      ].compact.join(" ")
      funding_enabled = readme_style.fetch(:floss_funding_enabled, false)
      security_enabled = readme_style.fetch(:security_enabled, false)
      section_partials = readme_section_partials_for_render(readme_style, facts)
      rendered = [
        "# 💎 #{title}",
        badges,
        "## 🌻 Synopsis\n\n#{section_partials.fetch("synopsis", "")}",
        "## 💡 Info you can shake a stick at\n\nCompatible with MRI Ruby #{min_ruby}+.\n\n#{readme_family_intro_and_backend_matrix}",
        "## ✨ Installation\n\n```console\ngem install #{package.fetch(:name)}\n```",
        "## ⚙️ Configuration\n\n#{section_partials.fetch("configuration", "")}",
        "## 🔧 Basic Usage\n\n#{section_partials.fetch("basic usage", "")}",
      ]
      rendered << "## 🦷 FLOSS Funding\n\nThis free software project accepts funding support when configured by the package maintainer." if funding_enabled
      rendered << "## 🔐 Security\n\nSee [SECURITY.md](SECURITY.md)." if security_enabled
      rendered.concat([
        "## 🤝 Contributing\n\nContributions are welcome. Missing optional service integrations are reported by the generator instead of rendered as broken badges.",
        "## 📌 Versioning\n\nThis project follows semantic versioning for its public API where practical.",
        "## 📄 License\n\nThis project is made available under the following license expression: #{license_expression.empty? ? "unspecified" : license_expression}.",
        "## 🤑 A request for help\n\nPlease support the project by using it, reporting issues, and contributing improvements.",
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
        "KJ|FUNDING:PATREON" => "",
        "KJ|FUNDING:PAYPAL" => "",
        "KJ|FUNDING:POLAR" => "",
        "KJ|GH:USER" => "",
        "KJ|GH_ORG" => github_org_from_url(facts.dig(:package, :source_url)).to_s,
        "KJ|GL:USER" => "",
        "KJ|PROJECT_EMOJI" => "💎",
        "KJ|README:COPYRIGHT_NOTICE" => "",
        "KJ|README:LICENSE_BADGE" => "",
        "KJ|README:LICENSE_COMPAT_BADGE" => "",
        "KJ|README:LICENSE_INTRO" => "",
        "KJ|README:LICENSE_REFS" => "",
        "KJ|README:TOP_LOGO_REFS" => "",
        "KJ|README:TOP_LOGO_ROW" => "",
        "KJ|SH:USER" => "",
        "KJ|SOCIAL:BLUESKY" => "",
        "KJ|SOCIAL:DEVTO" => "",
        "KJ|SOCIAL:LINKTREE" => "",
        "KJ|SOCIAL:MASTODON" => "",
        "KJ|YARD_HOST" => "rubydoc.info",
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
        metadata: deep_dup(metadata || {}),
      )
    end

    def content_recipe_execution_request_envelope(request)
      {
        kind: "content_recipe_execution_request",
        version: CONTENT_RECIPE_TRANSPORT_VERSION,
        request: deep_dup(request),
      }
    end

    def content_recipe_execution_report(request:, final_content:, changed:, step_reports:, diagnostics:, metadata: nil)
      compact_hash(
        request: deep_dup(request),
        final_content: final_content.to_s,
        changed: changed ? true : false,
        step_reports: deep_dup(step_reports),
        diagnostics: deep_dup(diagnostics),
        metadata: deep_dup(metadata || {}),
      )
    end

    def content_recipe_execution_report_envelope(report)
      {
        kind: "content_recipe_execution_report",
        version: CONTENT_RECIPE_TRANSPORT_VERSION,
        report: deep_dup(report),
      }
    end

    def synchronize_readme(content, facts)
      package = facts.fetch(:package)
      lines = content.to_s.split("\n", -1)
      heading = "# #{package.fetch(:name)}"
      h1_index = lines.index { |line| line.start_with?("# ") }
      unless h1_index
        lines.unshift(heading, "")
      end
      postprocess_readme_content(
        replace_markdown_managed_block(lines.join("\n"), "kettle-jem:metadata", readme_metadata_block(facts)),
        facts
      )
    end

    def normalize_changelog(content, facts)
      text = content.to_s
      title = "# Changelog"
      text = "#{title}\n\n#{text}" unless text.lines.first&.start_with?("# ")
      return ensure_trailing_newline(text) if text.match?(/^##\s+\[?Unreleased\]?/i)

      lines = text.split("\n", -1)
      insert_at = lines.index { |line| line.start_with?("## ") } || lines.length
      section = [
        "## [Unreleased]",
        "",
        "### Added",
        "",
        "### Changed",
        "",
        "### Fixed",
        "",
      ]
      lines.insert(insert_at, *section)
      ensure_trailing_newline(lines.join("\n").gsub(/\n{3,}/, "\n\n"))
    end

    def synchronize_managed_block(content, facts)
      replacement = facts.dig(:generated_blocks, :shunted_gemfile) || [
        MANAGED_BLOCK_OPEN,
        "# package: #{facts.fetch(:package).fetch(:name)}",
        "# generated by kettle-jem vNext",
        MANAGED_BLOCK_CLOSE,
        "",
      ].join("\n")
      replace_ruby_managed_block(content.to_s, replacement)
    end

    def execute_recipe(project_root:, recipe:, facts:, files:, decision_policy:)
      relative_path = recipe.fetch(:target_path)
      destination_existed = File.exist?(File.join(project_root, relative_path))
      original = files.fetch(relative_path, "")
      deletion = recipe.fetch(:name) == "rakefile_scaffold_cleanup" ? delete_rakefile_scaffold(original) : nil
      final = case recipe.fetch(:name)
      when "readme_metadata"
        synchronize_readme(original, facts)
      when "changelog_unreleased"
        normalize_changelog(original, facts)
      when "generated_block_sync"
        synchronize_managed_block(original, facts)
      when "github_funding_yml"
        synchronize_github_funding_yml(original, facts)
      when "github_actions_ci"
        synchronize_github_actions_ci(original, facts)
      when "github_actions_framework_ci"
        synchronize_github_actions_framework_ci(original, facts)
      when "github_actions_coverage_ci"
        synchronize_github_actions_coverage_ci(original, facts)
      when /\Agithub_actions_obsolete_workflow_cleanup_/
        ""
      when /\Agithub_actions_opt_in_workflow_cleanup_/
        ""
      when /\Aopencollective_disabled_file_cleanup_/
        ""
      when /\Atemplate_legacy_destination_cleanup_/
        ""
      when /\Atemplate_obsolete_license_cleanup_/
        ""
      when /\Agithub_actions_workflow_snippets_/
        synchronize_github_actions_workflow_snippets(original)
      when "kettle_config_bootstrap"
        apply_kettle_config_bootstrap(project_root, recipe)
      when /\Atemplate_source_preference_/
        original
      when /\Atemplate_source_application_/
        apply_template_source(project_root, recipe, original, facts: facts)
      when "rakefile_scaffold_cleanup"
        deletion.fetch(:content)
      else
        original
      end
      final = normalize_generated_rakefile(final) if relative_path == "Rakefile"

      template_content = recipe_template_content(project_root, recipe)
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
        metadata: { packaging_recipe: recipe.fetch(:name), project_root: project_root.to_s },
      )
      changed = delete_file_recipe?(recipe) || final != original
      metadata = recipe_report_metadata(recipe).merge(destination_existed: destination_existed)
      decision_evaluation = recipe_decision_evaluation(
        decision_policy: decision_policy,
        recipe: recipe,
        changed: changed,
        destination_existed: destination_existed
      )
      if %w[keep skip].include?(decision_evaluation.fetch(:selected_action))
        final = original
        changed = false
        deletion = nil
      end
      step_report = content_recipe_step_report(recipe: recipe, request: request, original: original, final: final, changed: changed, deletion: deletion)
      metadata[:decision_evaluation] = decision_evaluation
      report = content_recipe_execution_report(
        request: request,
        final_content: final,
        changed: changed,
        step_reports: [step_report],
        diagnostics: [],
        metadata: metadata,
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
        diagnostics: [],
      }
    end

    def content_recipe_step(recipe)
      step = {
        step_id: recipe.fetch(:name),
        step_kind: recipe.fetch(:primitive),
        name: recipe.fetch(:name),
        provider_family: recipe.fetch(:provider_family),
        metadata: { target_path: recipe.fetch(:target_path) },
      }
      step[:provider_backend] = recipe[:provider_backend] if recipe[:provider_backend]
      if recipe.fetch(:primitive) == "supplied_source_selector_deletion"
        step[:step_kind] = "native_policy"
        step[:policy] = {
          policy_kind: "delete_supplied_structural_owners",
          required_context: "delete_selectors",
          operation: "delete",
          selector_family: "structural_owner_range",
          normalize_blank_lines: true,
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
        operation_family: "kettle-jem",
      )
      result = Ast::Merge.structured_edit_result(
        operation_kind: recipe.fetch(:primitive),
        updated_content: final,
        changed: changed,
        operation_profile: operation_profile,
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
        ),
      }
    end

    def ruby_template_policy_report(recipe:, request:, original:, final:)
      return {} unless recipe.fetch(:primitive) == "supplied_template_source_application"

      file_type = template_file_type(recipe)
      return {} unless %i[gemfile gemspec appraisals].include?(file_type)

      template_content = request.fetch(:template_content, "")
      report = {
        policy_kind: "kettle_jem_ruby_template_policy",
        file_type: file_type.to_s,
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
      { ruby_template_policy: report }
    end

    def gemfile_policy_operations(template_content, original, final, request)
      package_name = runtime_context_value(request, :package, :name).to_s
      deleted = gemfile_dependency_names("#{template_content}\n#{original}") - gemfile_dependency_names(final)
      expected = ["appraisal"]
      expected << package_name unless package_name.empty?
      [
        {
          operation: "delete_dependency_declarations",
          deleted_gems: (deleted & expected).sort,
        },
      ]
    end

    def appraisals_policy_operations(template_content, original, final, request)
      package_name = runtime_context_value(request, :package, :name).to_s
      min_ruby = minimum_ruby_token(runtime_context_value(request, :rubygems, :min_ruby))
      source = "#{template_content}\n#{original}"
      [
        {
          operation: "merge_appraisal_blocks",
          inserted_appraisals: (appraisal_names(template_content) - appraisal_names(original)).sort,
          preserved_destination_appraisals: (appraisal_names(original) - appraisal_names(template_content) & appraisal_names(final)).sort,
        },
        {
          operation: "delete_self_dependency_declarations",
          deleted_dependency_count: [gemfile_dependency_names(source).count(package_name) - gemfile_dependency_names(final).count(package_name), 0].max,
        },
        {
          operation: "prune_minimum_ruby_appraisals",
          min_ruby: min_ruby,
          deleted_appraisals: (ruby_appraisal_names_below(original, min_ruby) - appraisal_names(final)).sort,
        },
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
          end.sort,
        },
        {
          operation: "preserve_dependency_declarations",
          preserved_dependencies: gemspec_dependency_line_index(original, receiver: destination_receiver).keys.map(&:last).select do |gem_name|
            final.include?(%("#{gem_name}"))
          end.sort,
        },
        {
          operation: "delete_self_dependency_declarations",
          deleted_dependency_count: [
            gemspec_dependency_names("#{template_content}\n#{original}").count { |name| self_dependency_names.include?(name) } -
              gemspec_dependency_names(final).count { |name| self_dependency_names.include?(name) },
            0,
          ].max,
        },
      ]
      if template_receiver != destination_receiver
        operations << {
          operation: "normalize_gemspec_receiver",
          from: destination_receiver,
          to: template_receiver,
        }
      end
      operations
    end

    def runtime_context_value(request, *path)
      context = request[:runtime_context] || request["runtime_context"] || {}
      path.reduce(context) do |value, key|
        break nil unless value.respond_to?(:[])

        value[key] || value[key.to_s]
      end
    end

    def gemfile_dependency_names(content)
      gemfile_gem_call_records(content).map { |record| record.fetch(:name) }
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
      pack.fetch(:recipes).to_h do |recipe|
        relative_path = recipe.fetch(:target_path)
        path = File.join(project_root, relative_path)
        [relative_path, File.exist?(path) ? File.read(path) : ""]
      end
    end

    def recipe_template_content(project_root, recipe)
      return "" unless %w[
        supplied_kettle_config_bootstrap
        supplied_template_source_preference
        supplied_template_source_application
      ].include?(recipe.fetch(:primitive))

      preference = recipe.fetch(:template_preference)
      path = File.join(
        preference.fetch(:source_root_path, project_root),
        preference.fetch(:source_relative_path, preference.fetch(:selected_source))
      )
      File.read(path)
    end

    def normalize_generated_rakefile(content)
      strip_orphaned_rake_task_requires(content.to_s)
    end

    def strip_orphaned_rake_task_requires(content)
      guarded_requires = %w[kettle/dev kettle/jem stone_checksums]
      remove_indexes = Set.new
      ruby_top_level_require_records(content).each do |record|
        next unless guarded_requires.include?(record.fetch(:name))

        (record.fetch(:start_line)..record.fetch(:end_line)).each { |line_number| remove_indexes << (line_number - 1) }
      end
      content.to_s.lines.each_with_index.reject { |_line, index| remove_indexes.include?(index) }.map(&:first).join
    end

    def apply_template_source(project_root, recipe, original, facts: nil)
      strategy = recipe.dig(:template_preference, :strategy).to_s
      return original if strategy == "keep_destination"

      content = recipe_template_content(project_root, recipe)
      return content if strategy == "raw_copy"

      resolved = resolve_template_tokens(
        content,
        recipe.fetch(:template_tokens, {}),
        scan_unresolved: unresolved_template_scan?(recipe)
      )
    rescue ArgumentError => e
      raise ArgumentError, "#{recipe.fetch(:target_path)}: #{e.message}"
    else
      resolved = prepare_readme_template(resolved, recipe[:readme_style]) if recipe.fetch(:target_path) == "README.md"
      resolved = prepare_github_workflow_template(resolved, recipe, facts)
      if recipe.fetch(:target_path) == "README.md" && (strategy.empty? || strategy == "merge")
        return postprocess_readme_content(
          merge_readme_template(
            template_content: resolved,
            destination_content: original,
            preserve_config: recipe.dig(:template_preference, :readme_preserve_config) || {}
          ),
          facts
        )
      end
      return merge_config_template_source(recipe, resolved, original, facts: facts) if strategy.empty? || strategy == "merge"
      if strategy == "accept_template"
        accepted = finalize_accepted_template_source(recipe, resolved, original, facts: facts)
        return recipe.fetch(:target_path) == "README.md" ? postprocess_readme_content(accepted, facts) : accepted
      end

      recipe.fetch(:target_path) == "README.md" ? postprocess_readme_content(resolved, facts) : resolved
    end

    def finalize_accepted_template_source(recipe, content, destination_content, facts:)
      case template_file_type(recipe)
      when :gemfile
        finalize_gemfile_template_source(recipe, content, destination_content, facts: facts, template_content: content)
      when :appraisals
        merge_appraisals_template_policy(content, facts: facts)
      when :gemspec
        package_name = facts.dig(:package, :name).to_s if facts
        receiver = gemspec_block_param(content) || "spec"
        remove_gemspec_self_dependency_lines(content, package_name, receiver: receiver)
      else
        content
      end
    end

    def prepare_github_workflow_template(content, recipe, facts)
      return content unless recipe.fetch(:target_path).to_s == ".github/workflows/framework-ci.yml"
      return content if facts.to_h.dig(:ci, :framework_matrix).to_h.empty?

      synchronize_github_actions_framework_ci(content, facts)
    end

    def postprocess_readme_content(content, facts)
      return content unless facts

      processed = ReadmePostProcessor.process(
        content: content,
        min_ruby: minimum_ruby_token(facts.dig(:rubygems, :min_ruby)),
        engines: facts.dig(:rubygems, :engines)
      )
      processed = normalize_readme_project_heading(processed, facts)
      processed = apply_readme_conditional_blocks(processed, facts)
      processed = apply_readme_badge_policy(processed, facts)
      processed = apply_monorepo_subgem_thin_readme_projection(processed, facts)
      apply_monorepo_subgem_readme_recipe(processed, facts)
    end

    def apply_readme_conditional_blocks(content, facts)
      open_collective_enabled = !facts.dig(:funding, :open_collective_disabled)
      processed = apply_markdown_conditional_block(content, "OPEN_COLLECTIVE", keep: open_collective_enabled)
      apply_markdown_conditional_block(processed, "NO_OPEN_COLLECTIVE", keep: !open_collective_enabled)
    end

    def apply_readme_badge_policy(content, facts)
      processed = remove_readme_badge_and_refs(content, README_CODETRIAGE_BADGE, README_CODETRIAGE_LINK_LABELS)
      unless Array(facts.dig(:license, :spdx)).map(&:to_s).include?("MIT")
        processed = remove_readme_badge_and_refs(
          processed,
          README_LICENSE_EYE_WORKFLOW_BADGE,
          README_LICENSE_EYE_WORKFLOW_LINK_LABELS
        )
      end
      if facts.dig(:funding, :open_collective_disabled)
        processed = remove_readme_badge_and_refs(
          processed,
          README_OPEN_COLLECTIVE_FUNDING_BADGES,
          README_OPEN_COLLECTIVE_LINK_LABELS
        )
      end
      processed
    end

    def remove_readme_badge_and_refs(content, badge_source, link_labels)
      processed = content.to_s.gsub(badge_source, "").lines.map(&:rstrip).join("\n")
      processed = "#{processed}\n" if content.to_s.end_with?("\n")
      Array(link_labels).reduce(processed) do |memo, label|
        delete_markdown_with_ast_crispr(
          memo,
          Ast::Crispr::Markdown::Markly::Selectors.link_definition(label: label, limit: {at_least: 0})
        )
      end
    end

    def apply_markdown_conditional_block(content, name, keep:)
      start_text = "KJ:#{name}:START"
      end_text = "KJ:#{name}:END"
      if keep
        processed = delete_markdown_with_ast_crispr(
          content,
          Ast::Crispr::Markdown::Markly::Selectors.html_comment(text: start_text, limit: {at_least: 0})
        )
        delete_markdown_with_ast_crispr(
          processed,
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

    def delete_markdown_with_ast_crispr(content, target)
      Ast::Crispr::Delete.call(content: content.to_s, target: target, source_label: "README.md").updated_content
    end

    def replace_markdown_with_ast_crispr(content, target, replacement)
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
      namespace = facts.dig(:rubygems, :namespace).to_s
      emoji = facts.dig(:project_runtime, :project_emoji).to_s
      return content if namespace.empty? || emoji.empty?

      lines = content.to_s.split("\n", -1)
      h1 = markdown_heading_owners(content, source_label: "README.md").find { |owner| owner.level == 1 }
      return content unless h1

      index = h1.location.start_line - 1
      lines[index] = "# #{emoji} #{namespace}"
      lines.join("\n")
    end

    def markdown_heading_owners(content, source_label: "README.md")
      context = Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: source_label)
      context.structural_owners(owner_scope: :heading_sections)
    rescue Ast::Crispr::Error
      []
    end

    def prepare_readme_template(content, readme_style)
      style = readme_style || {}
      prepared = prune_readme_integration_badges(content, style)
      prepared = ReadmePostProcessor.process(
        content: prepared,
        min_ruby: "0",
        workflow_paths: style[:workflow_paths]
      ) if style[:workflow_paths]
      prepared = prune_missing_workflow_link_definitions(prepared, style[:workflow_paths]) if style[:workflow_paths]
      omitted_sections = Array(style[:omitted_sections]).map(&:to_s)
      omitted_sections << "security" if style.key?(:security_enabled) && !style[:security_enabled]
      omitted_sections << "floss_funding" if style.key?(:floss_funding_enabled) && !style[:floss_funding_enabled]
      remove_readme_sections(prepared, omitted_sections.map { |section| section.tr("_", " ") })
    end

    def prune_readme_integration_badges(content, readme_style)
      integrations = Array(readme_style[:missing_integrations]) + Array(readme_style[:disabled_integrations])
      integrations.uniq.reduce(content.to_s) do |result, integration|
        pruned_badges = README_INTEGRATION_BADGE_PATTERNS.fetch(integration.to_s, []).reduce(result) do |memo, pattern|
          memo.gsub(pattern, "")
        end
        README_INTEGRATION_LINK_LABELS.fetch(integration.to_s, []).reduce(pruned_badges) do |memo, label|
          delete_markdown_with_ast_crispr(
            memo,
            Ast::Crispr::Markdown::Markly::Selectors.link_definition(label: label, limit: {at_least: 0})
          )
        end
      end.gsub(/[ \t]{2,}/, " ")
    end

    def prune_missing_workflow_link_definitions(content, workflow_paths)
      existing = Array(workflow_paths).map { |path| path.to_s.delete_prefix("./") }.to_set
      Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: "README.md")
        .structural_owners(owner_scope: :link_definitions)
        .reduce(content.to_s) do |processed, owner|
          workflow_path = readme_workflow_path_from_url(owner.url)
          next processed if workflow_path.empty? || existing.include?(workflow_path)

          delete_markdown_with_ast_crispr(
            processed,
            Ast::Crispr::Markdown::Markly::Selectors.link_definition(label: owner.label, limit: {at_least: 0})
          )
        end
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

    def merge_config_template_source(recipe, template_content, destination_content, facts: nil)
      file_type = template_file_type(recipe)
      if destination_content.to_s.strip.empty?
        if file_type == :gemfile
          return finalize_gemfile_template_source(recipe, template_content, destination_content, facts: facts, template_content: template_content)
        end
        return prune_github_workflow_matrix_by_min_ruby(template_content, facts) if github_workflow_template_recipe?(recipe)

        return template_content
      end
      return destination_content if destination_content == template_content

      case file_type
      when :gemspec
        return merge_gemspec_template_source(template_content, destination_content, facts: facts)
      when :appraisals
        return merge_appraisals_template_source(template_content, destination_content, facts: facts)
      when :ruby, :gemfile, :rakefile
        merge_result = merge_ruby_template_source(file_type, recipe, template_content, destination_content)
      when :yaml
        merge_result = Psych::Merge.merge_yaml(
          template_content,
          destination_content,
          "yaml",
          **yaml_merge_options(recipe)
        )
      when :toml
        merge_result = Toml::Merge.merge_toml(template_content, destination_content, "toml")
      when :json, :jsonc
        merge_result = merge_json_template_source(template_content, destination_content, recipe, file_type)
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
          output = merge_gemfile_eval_bucket_entries(template_content, output)
          return finalize_gemfile_template_source(recipe, output, destination_content, facts: facts, template_content: template_content)
        end
        return merge_appraisals_template_policy(output, facts: facts) if file_type == :appraisals

        output = prune_github_workflow_matrix_by_min_ruby(output, facts) if github_workflow_template_recipe?(recipe)
        return output
      end

      return fallback_adapter_failure_template_source(file_type, recipe, template_content, destination_content, facts) if process_result_adapter_failure?(merge_result)
      return template_content if github_workflow_template_recipe?(recipe)

      diagnostics = merge_result.fetch(:diagnostics, [])
      message = diagnostics.map { |diagnostic| diagnostic[:message] || diagnostic["message"] }.compact.join("; ")
      raise ArgumentError, "failed to merge #{file_type} template #{recipe.fetch(:target_path)}: #{message}"
    end

    def finalize_gemfile_template_source(recipe, content, destination_content, facts:, template_content:)
      output = merge_gemfile_template_policy(content, facts: facts, template_content: template_content)
      return output unless local_gemfile_template_recipe?(recipe)

      merge_local_gem_overrides(output, destination_content, facts: facts, template_content: template_content)
    end

    def local_gemfile_template_recipe?(recipe)
      recipe.fetch(:target_path).to_s.end_with?("_local.gemfile")
    end

    def merge_local_gem_overrides(content, destination_content, facts:, template_content: nil)
      package_name = facts.to_h.dig(:package, :name).to_s
      template_gems = local_gems_assignment(content)
      template_gems = local_gems_assignment(template_content) if template_gems.empty?
      destination_gems = local_gems_assignment(destination_content)
      return content if template_gems.empty? && destination_gems.empty?

      gems = (template_gems + destination_gems).map(&:to_s).reject(&:empty?).uniq
      gems.delete(package_name) unless package_name.empty?
      replace_local_gems_assignment(content, gems)
    end

    def local_gems_assignment(content)
      local_gems_assignment_record(content)&.fetch(:names) || []
    end

    def replace_local_gems_assignment(content, gems)
      replacement = ["local_gems = %w["]
      gems.each { |gem_name| replacement << "  #{gem_name}" }
      replacement << "]"
      if (record = local_gems_assignment_record(content))
        replace_source_range_lines(content, record.fetch(:start_line), record.fetch(:end_line), ensure_trailing_newline(replacement.join("\n")))
      else
        ensure_trailing_newline([content.to_s.rstrip, replacement.join("\n")].reject(&:empty?).join("\n\n"))
      end
    end

    def local_gems_assignment_record(content)
      result = prism_parse_success(content)
      return unless result

      result.value.breadth_first_search_all do |node|
        node.is_a?(::Prism::LocalVariableWriteNode) &&
          node.name == :local_gems &&
          ruby_word_array_node?(node.value)
      end.first&.then do |node|
        {
          names: ruby_word_array_names(node.value),
          start_line: node.location.start_line,
          end_line: node.location.end_line,
        }
      end
    end

    def prune_github_workflow_matrix_by_min_ruby(content, facts)
      min_ruby = minimum_ruby_token(facts.to_h.dig(:rubygems, :min_ruby))
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
    rescue StandardError
      content
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
      ruby = yaml_mapping_scalar_value(mapping, "ruby")
      return true if ruby && Gem::Version.new(ruby) < minimum

      appraisal_ruby_version = appraisal_ruby_version(yaml_mapping_scalar_value(mapping, "appraisal"))
      appraisal_ruby_version && Gem::Version.new(appraisal_ruby_version) < minimum
    rescue ArgumentError
      false
    end

    def yaml_mapping_scalar_value(mapping, key)
      mapping.children.each_slice(2) do |key_node, value_node|
        next unless key_node.is_a?(Psych::Nodes::Scalar) && key_node.value.to_s == key.to_s
        next unless value_node.is_a?(Psych::Nodes::Scalar)

        return value_node.value.to_s
      end
      nil
    end

    def appraisal_ruby_version(value)
      parts = value.to_s.split("-")
      return nil unless parts.length == 3 && parts.first == "ruby"

      major = Integer(parts[1], exception: false)
      minor = Integer(parts[2], exception: false)
      return nil unless major && minor

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

    def fallback_adapter_failure_template_source(file_type, recipe, template_content, destination_content, facts)
      case file_type
      when :gemfile
        finalize_gemfile_template_source(recipe, template_content, destination_content, facts: facts, template_content: template_content)
      when :appraisals
        merge_appraisals_template_policy(template_content, facts: facts)
      when :yaml
        raise ArgumentError, "failed to merge yaml template #{recipe.fetch(:target_path)}: provider adapter failure"
      else
        template_content
      end
    end

    def ruby_merge_options(recipe, merge_template_requires:)
      options = { merge_template_requires: merge_template_requires }
      parameters = Ruby::Merge.method(:merge_ruby).parameters
      if parameters.include?([:key, :method_move_policy]) || parameters.any? { |kind, _name| kind == :keyrest }
        options[:method_move_policy] = ruby_method_move_policy(recipe)
      end
      options
    end

    def merge_ruby_template_source(file_type, recipe, template_content, destination_content)
      return merge_prism_gemfile_template_source(template_content, destination_content) if file_type == :gemfile

      result = Prism::Merge.merge_ruby(
        template_content,
        destination_content,
        "ruby",
        preference: :destination,
        add_template_only_nodes: true,
        signature_generator: Prism::Merge.ruby_dsl_signature_generator,
        **prism_ruby_merge_options(recipe)
      )
      if file_type == :ruby && result[:ok]
        result = result.merge(output: remove_template_only_require_calls(template_content, destination_content, result.fetch(:output)))
      end
      result
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
      }
    end

    def merge_gemfile_template_policy(content, facts:, template_content: nil)
      package_name = facts.dig(:package, :name).to_s if facts
      removable_gems = ["appraisal"]
      removable_gems << package_name unless package_name.to_s.empty?
      pruned = remove_gemfile_dependency_lines(content, removable_gems)
      pruned = remove_gemfile_percent_w_entries(pruned, [package_name])
      pruned = merge_template_gemfile_dependency_blocks(template_content, pruned, removable_gems)
      apply_commented_gem_dependency_policy(template_content, pruned)
    end

    def merge_template_gemfile_dependency_blocks(template_content, content, removable_gems)
      template = remove_gemfile_dependency_lines(template_content, removable_gems)
      template = remove_gemfile_percent_w_entries(template, removable_gems)
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

    def gemfile_gem_call_records(content)
      ruby_call_records(content, :gem).filter_map do |call|
        name = ruby_string_argument(call)
        next unless name

        {
          name: name,
          start_line: call.location.start_line,
          end_line: call.location.end_line,
        }
      end
    end

    def remove_template_only_require_calls(template_content, destination_content, merged_content)
      template_requires = ruby_require_call_records(template_content).map { |record| record.fetch(:name) }
      destination_requires = ruby_require_call_records(destination_content).map { |record| record.fetch(:name) }
      removable = template_requires - destination_requires
      return merged_content if removable.empty?

      remove_indexes = Set.new
      ruby_require_call_records(merged_content).each do |record|
        next unless removable.include?(record.fetch(:name))

        (record.fetch(:start_line)..record.fetch(:end_line)).each { |line_number| remove_indexes << (line_number - 1) }
      end
      ensure_trailing_newline(
        merged_content.to_s.lines.each_with_index.reject { |_line, index| remove_indexes.include?(index) }.map(&:first).join.gsub(/\n{3,}/, "\n\n")
      )
    end

    def ruby_require_call_records(content)
      ruby_call_records(content, :require).filter_map do |call|
        name = ruby_string_argument(call)
        next unless name

        {
          name: name,
          start_line: call.location.start_line,
          end_line: call.location.end_line,
        }
      end
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
          end_line: node.location.end_line,
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
          end_line: comment.location.end_line,
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
      argument.unescaped if argument.is_a?(::Prism::StringNode)
    end

    def prism_parse_success(content)
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
          ruby_multiline_word_array_source(kept, indent: record.fetch(:start_column))
        end
        { start_offset: record.fetch(:start_offset), end_offset: record.fetch(:end_offset), replacement: replacement }
      end
      return content if replacements.empty?

      replaced = replace_source_offsets(content, replacements)
      ensure_trailing_newline(replaced.gsub(/\n{3,}/, "\n\n"))
    end

    def ruby_word_array_records(content)
      ruby_word_array_nodes(content).map do |node|
        {
          names: ruby_word_array_names(node),
          source: node.location.slice,
          start_line: node.location.start_line,
          end_line: node.location.end_line,
          start_column: node.location.start_column,
          start_offset: node.location.start_offset,
          end_offset: node.location.end_offset,
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
      prefix = " " * indent.to_i
      element_prefix = "#{prefix}  "
      ([ "#{prefix}%w[" ] + names.map { |name| "#{element_prefix}#{name}" } + [ "#{prefix}]" ]).join("\n")
    end

    def replace_source_offsets(content, replacements)
      output = content.to_s.dup
      replacements.sort_by { |replacement| -replacement.fetch(:start_offset) }.each do |replacement|
        output[replacement.fetch(:start_offset)...replacement.fetch(:end_offset)] = replacement.fetch(:replacement)
      end
      output
    end

    def merge_gemfile_eval_bucket_entries(template_content, merged_content)
      template_entries = gemfile_eval_bucket_entries(template_content)
      return merged_content if template_entries.empty?

      template_by_key = template_entries.to_h { |entry| [entry.fetch(:key), entry] }
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

      missing_lines = template_entries.reject { |entry| emitted_paths.include?(entry.fetch(:path)) }.map { |entry| entry.fetch(:line) }
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

        {
          path: path,
          key: key,
          line: (lines[(call.location.start_line - 1)..(call.location.end_line - 1)] || []).join,
          start_line: call.location.start_line,
          end_line: call.location.end_line,
        }
      end
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

      version.split(".", -1).all? { |part| !part.empty? && part.each_char.all? { |char| char >= "0" && char <= "9" } }
    end

    def merge_appraisals_template_policy(content, facts:)
      package_name = facts.dig(:package, :name).to_s if facts
      min_ruby = minimum_ruby_token(facts.dig(:rubygems, :min_ruby)) if facts
      pruned = prune_appraisals_below_min_ruby(content, min_ruby)
      pruned = remove_gemfile_dependency_lines(pruned, [package_name])
      remove_gemfile_percent_w_entries(pruned, [package_name])
    end

    def yaml_merge_options(recipe)
      policy = recipe.dig(:template_preference, :comment_merge_policy).to_s
      policy = DEFAULT_TEMPLATE_YAML_COMMENT_MERGE_POLICY if policy.empty? && recipe.fetch(:primitive) == "supplied_template_source_application"
      return {} if policy.empty?

      { comment_merge_policy: policy.to_sym }
    end

    def json_merge_options(recipe)
      options = {
        preference: (recipe.dig(:template_preference, :preference) || "destination").to_sym,
        add_template_only_nodes: true,
        freeze_token: recipe.dig(:template_preference, :freeze_token) || "kettle-jem",
      }
      if recipe.dig(:template_preference, :add_template_only_nodes) != nil
        configured = DecisionPolicy.value_to_boolean(recipe.dig(:template_preference, :add_template_only_nodes))
        options[:add_template_only_nodes] = configured unless configured.nil?
      end
      options
    end

    def merge_json_template_source(template_content, destination_content, recipe, file_type)
      output = Json::Merge::SmartMerger.new(
        template_content,
        destination_content,
        **json_merge_options(recipe)
      ).merge
      { ok: true, output: output, diagnostics: [] }
    rescue Json::Merge::Error => e
      { ok: false, output: destination_content, diagnostics: [{ kind: "#{file_type}_merge_failed", message: e.message }] }
    end

    def dotenv_merge_options(recipe)
      options = {
        preference: (recipe.dig(:template_preference, :preference) || "destination").to_sym,
        add_template_only_nodes: true,
        freeze_token: recipe.dig(:template_preference, :freeze_token) || "kettle-jem",
      }
      if recipe.dig(:template_preference, :add_template_only_nodes) != nil
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
      { ok: true, output: output, diagnostics: [] }
    rescue Dotenv::Merge::Error => e
      { ok: false, output: destination_content, diagnostics: [{ kind: "dotenv_merge_failed", message: e.message }] }
    end

    def rbs_merge_options(recipe)
      options = {
        preference: (recipe.dig(:template_preference, :preference) || "destination").to_sym,
        add_template_only_nodes: true,
        freeze_token: recipe.dig(:template_preference, :freeze_token) || "kettle-jem",
      }
      if recipe.dig(:template_preference, :add_template_only_nodes) != nil
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
      { ok: true, output: output, diagnostics: [] }
    rescue Rbs::Merge::Error => e
      { ok: false, output: destination_content, diagnostics: [{ kind: "rbs_merge_failed", message: e.message }] }
    end

    def bash_merge_options(recipe)
      options = {
        preference: (recipe.dig(:template_preference, :preference) || "destination").to_sym,
        add_template_only_nodes: true,
        freeze_token: recipe.dig(:template_preference, :freeze_token) || "kettle-jem",
      }
      if recipe.dig(:template_preference, :add_template_only_nodes) != nil
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
            details: availability.diagnostics,
          }],
        }
      end

      output = Bash::Merge::SmartMerger.new(
        template_content,
        destination_content,
        **bash_merge_options(recipe)
      ).merge
      { ok: true, output: output, diagnostics: [] }
    rescue Bash::Merge::Error => e
      { ok: false, output: destination_content, diagnostics: [{ kind: "bash_merge_failed", message: e.message }] }
    end

    def merge_appraisals_template_source(template_content, destination_content, facts:)
      template = appraisal_blocks(template_content)
      destination = appraisal_blocks(destination_content)
      ordered_blocks = template.fetch(:order).map { |name| template.fetch(:blocks).fetch(name) }
      destination.fetch(:order).each do |name|
        next if template.fetch(:blocks).key?(name)

        ordered_blocks << destination.fetch(:blocks).fetch(name)
      end
      prelude = template.fetch(:prelude).to_s.strip.empty? ? destination.fetch(:prelude) : template.fetch(:prelude)
      merged = ([prelude.to_s.rstrip] + ordered_blocks.map { |block| block.rstrip }).reject(&:empty?).join("\n\n")
      merge_appraisals_template_policy(ensure_trailing_newline(merged), facts: facts)
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
      { prelude: prelude, blocks: blocks, order: order }
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
          end_line: call.location.end_line,
          source: (lines[(call.location.start_line - 1)..(call.location.end_line - 1)] || []).join,
        }
      end
    end

    def ruby_appraisal_name_version(name)
      text = name.to_s
      return unless text.start_with?("ruby-")

      major, minor, extra = text.delete_prefix("ruby-").split("-", -1)
      return if extra || major.to_s.empty? || minor.to_s.empty?
      return unless [major, minor].all? { |part| part.each_char.all? { |char| char >= "0" && char <= "9" } }

      Gem::Version.new("#{major}.#{minor}")
    end

    def merge_gemspec_template_source(template_content, destination_content, facts: nil)
      template_receiver = gemspec_block_param(template_content) || "spec"
      destination_receiver = gemspec_block_param(destination_content) || "spec"
      package_name = facts.dig(:package, :name).to_s if facts
      replacements = gemspec_preserved_assignments(destination_content, receiver: destination_receiver)
      normalized_replacements = replacements.to_h do |field, source|
        replacement = normalize_gemspec_receiver(source.rstrip, from: destination_receiver, to: template_receiver)
        [field, normalize_gemspec_project_emoji(replacement, facts, field: field)]
      end
      merged = replace_gemspec_assignment_sources(template_content, normalized_replacements, receiver: template_receiver)
      merged = preserve_gemspec_dependency_lines(
        merged,
        destination_content,
        template_receiver: template_receiver,
        destination_receiver: destination_receiver
      )
      merged = preserve_gemspec_freeze_blocks(merged, destination_content, receiver: template_receiver)
      merged = apply_configured_gemspec_licenses(merged, facts, receiver: template_receiver)
      remove_gemspec_self_dependency_lines(merged, package_name, receiver: template_receiver)
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

    def gemspec_block_param(source)
      call = gemspec_new_call(source)
      required = call&.block&.parameters&.parameters&.requireds&.first
      required&.name&.to_s
    end

    def normalize_gemspec_receiver(line, from:, to:)
      return line if from.to_s.empty? || to.to_s.empty? || from == to

      leading = line.to_s.length - line.to_s.lstrip.length
      stripped = line.to_s[leading..].to_s
      return line unless stripped.start_with?("#{from}.")

      "#{line.to_s[0...leading]}#{to}#{stripped[from.to_s.length..]}"
    end

    def normalize_gemspec_project_emoji(line, facts, field:)
      return line unless %w[summary description].include?(field.to_s)
      return line unless facts&.dig(:project_runtime, :project_emoji_configured)

      project_emoji = facts&.dig(:project_runtime, :project_emoji).to_s
      return line if project_emoji.empty?

      record = gemspec_assignment_records(line).find { |candidate| candidate.fetch(:field) == field.to_s }
      value = record&.fetch(:value)
      return line unless value.is_a?(String)

      line.sub(value, "#{project_emoji} #{strip_leading_decorative_graphemes(value)}")
    end

    def gemspec_preserved_assignments(source, receiver:)
      preserved_fields = %w[
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
      gemspec_assignment_records(source, receiver: receiver).each_with_object({}) do |record, assignments|
        field = record.fetch(:field)
        next unless preserved_fields.include?(field)
        next if assignments.key?(field)
        next if record.fetch(:source).include?("TODO:")

        assignments[field] = record.fetch(:source)
      end
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

    def preserve_gemspec_dependency_lines(template_content, destination_content, template_receiver:, destination_receiver:)
      destination_dependencies = gemspec_dependency_line_index(destination_content, receiver: destination_receiver).transform_values do |source|
        normalize_gemspec_receiver(source, from: destination_receiver, to: template_receiver)
      end
      return template_content if destination_dependencies.empty?

      merged = replace_matching_gemspec_dependency_lines(template_content, destination_dependencies, receiver: template_receiver)
      append_missing_gemspec_dependency_lines(merged, destination_dependencies, receiver: template_receiver)
    end

    def preserve_gemspec_freeze_blocks(content, destination_content, receiver:)
      blocks = freeze_marker_blocks(destination_content)
      return content if blocks.empty?

      merged = content.to_s
      blocks.each do |block|
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

    def freeze_marker_blocks(content)
      lines = content.to_s.lines
      blocks = []
      index = 0
      while index < lines.length
        unless lines[index].include?("# kettle-jem:freeze")
          index += 1
          next
        end

        start_index = index
        while index < lines.length
          index += 1
          break if lines[index - 1].include?("# kettle-jem:unfreeze")
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

    def append_missing_gemspec_dependency_lines(content, destination_dependencies, receiver:)
      existing_keys = gemspec_dependency_line_index(content, receiver: receiver).keys
      missing_lines = destination_dependencies.reject { |key, _line| existing_keys.include?(key) }.values
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

    def gemspec_assignment_records(source, receiver: nil)
      lines = source.to_s.lines
      ruby_call_records(source, nil).filter_map do |call|
        field = gemspec_assignment_field(call)
        next unless field
        next if receiver && call.receiver&.slice != receiver.to_s

        {
          field: field,
          value: gemspec_assignment_value(call),
          receiver: call.receiver&.slice,
          start_line: call.location.start_line,
          end_line: call.location.end_line,
          source: (lines[(call.location.start_line - 1)..(call.location.end_line - 1)] || []).join,
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
      when ::Prism::StringNode
        argument.unescaped
      when ::Prism::ArrayNode
        argument.elements.filter_map { |element| element.unescaped if element.is_a?(::Prism::StringNode) }
      else
        argument&.slice
      end
    end

    def gemspec_assignment_record(source, field)
      receiver, assignment_field = gemspec_field_receiver_and_name(field)
      gemspec_assignment_records(source, receiver: receiver).find { |record| record.fetch(:field) == assignment_field }
    end

    def gemspec_field_receiver_and_name(field)
      parts = field.to_s.split(".")
      return [nil, field.to_s] if parts.length == 1

      [parts[0...-1].join("."), parts.last]
    end

    def gemspec_metadata_records(source)
      ruby_call_records(source, :[]=).filter_map do |call|
        next unless call.receiver&.slice.to_s.end_with?(".metadata")

        key = ruby_string_argument_at(call, 0)
        value = ruby_string_argument_at(call, 1)
        next unless key

        { key: key, value: value, receiver: call.receiver&.slice }
      end
    end

    def replace_record_ranges(content, records_by_line)
      return content if records_by_line.empty?

      skip_until = 0
      content.to_s.lines.each_with_index.flat_map do |line, index|
        line_number = index + 1
        next [] if line_number < skip_until

        record = records_by_line[line_number]
        unless record
          line
        else
          skip_until = record.fetch(:end_line) + 1
          record.fetch(:replacement)
        end
      end.join
    end

    def replace_source_range_lines(content, start_line, end_line, replacement)
      replace_record_ranges(content, { start_line => { end_line: end_line, replacement: replacement } })
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
          receiver: call.receiver&.slice,
          start_line: call.location.start_line,
          end_line: call.location.end_line,
          source: (lines[(call.location.start_line - 1)..(call.location.end_line - 1)] || []).join,
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
      return :gemfile if basename == "Gemfile" || basename.end_with?(".gemfile")
      return :appraisals if basename.start_with?("Appraisals") || basename == "Appraisal.root.gemfile"
      return :gemspec if basename.end_with?(".gemspec")
      return :rakefile if basename == "Rakefile" || extension == ".rake"
      return :ruby if RUBY_TEMPLATE_BASENAMES.include?(basename) ||
        RUBY_TEMPLATE_SUFFIXES.any? { |suffix| basename.end_with?(suffix) } ||
        RUBY_TEMPLATE_EXTENSIONS.include?(extension)
      return :yaml if extension.match?(/\A\.ya?ml\z/) || File.basename(relative_path).casecmp("citation.cff").zero?
      return :toml if extension == ".toml"
      return :jsonc if extension == ".jsonc"
      return :json if extension == ".json"
      return :markdown if extension.match?(/\A\.md(?:own)?\z/)
      return :dotenv if basename.start_with?(".env") || basename.end_with?(".env") || extension == ".env"
      return :rbs if extension == ".rbs"

      :text
    end

    def apply_kettle_config_bootstrap(project_root, recipe)
      content = recipe_template_content(project_root, recipe)
      tokens = stringify_template_tokens(recipe.fetch(:template_tokens, {}))
      content = content.gsub("{KJ|MIN_DIVERGENCE_THRESHOLD}", tokens.fetch("KJ|MIN_DIVERGENCE_THRESHOLD", ""))
      bootstrap_licenses = Array(recipe[:bootstrap_licenses]).map(&:to_s).reject(&:empty?)
      content = replace_kettle_config_bootstrap_licenses(content, bootstrap_licenses) unless bootstrap_licenses.empty?
      content = replace_kettle_config_bootstrap_project_emoji(content, recipe[:bootstrap_project_emoji]) unless recipe[:bootstrap_project_emoji].to_s.empty?
      apply_kettle_config_bootstrap_profile(content, recipe[:bootstrap_template_profile], recipe[:bootstrap_gemspec_path])
    end

    def replace_kettle_config_bootstrap_project_emoji(content, emoji)
      updated = content.sub(/^project_emoji:\s*.*$/, "project_emoji: #{emoji}")
      return updated unless updated == content

      raise Error, "Could not replace project_emoji in .kettle-jem.yml bootstrap template"
    end

    def replace_kettle_config_bootstrap_licenses(content, licenses)
      license_block = ["licenses:", *licenses.map { |license_id| "  - #{license_id}" }].join("\n")
      updated = content.sub(/^licenses:\n(?:  - .+\n?)+/, "#{license_block}\n")
      return updated unless updated == content

      raise Error, "Could not replace licenses block in .kettle-jem.yml bootstrap template"
    end

    def apply_kettle_config_bootstrap_profile(content, profile, gemspec_path)
      return content if profile.to_s.empty?
      return apply_monorepo_root_template_profile(content) if profile.to_s == MONOREPO_ROOT_TEMPLATE_PROFILE
      return apply_monorepo_subgem_template_profile(content, gemspec_path) if profile.to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE

      raise Error, "Unknown kettle-jem template profile: #{profile}"
    end

    def apply_monorepo_root_template_profile(content)
      entry_lines = MONOREPO_ROOT_TEMPLATE_ENTRIES.map { |entry| "    - #{entry}" }
      entries_block = ["  profile: #{MONOREPO_ROOT_TEMPLATE_PROFILE}", "  entries:", *entry_lines].join("\n")
      updated = insert_after_line_sequence(
        content,
        ["templates:", "  root: packaged", "  apply: true"],
        entries_block,
        "Could not apply monorepo-root template profile to .kettle-jem.yml bootstrap template"
      )
      add_monorepo_root_file_overrides(updated)
    end

    def apply_monorepo_subgem_template_profile(content, gemspec_path)
      entries = monorepo_subgem_template_entries(gemspec_path)
      entry_lines = entries.flat_map do |entry|
        if entry.is_a?(Hash)
          [
            "    - source: #{entry.fetch("source")}",
            "      target: #{entry.fetch("target")}",
          ]
        else
          ["    - #{entry}"]
        end
      end
      entries_block = ["  profile: #{MONOREPO_SUBGEM_TEMPLATE_PROFILE}", "  entries:", *entry_lines].join("\n")
      updated = insert_after_line_sequence(
        content,
        ["templates:", "  root: packaged", "  apply: true"],
        entries_block,
        "Could not apply monorepo-subgem template profile to .kettle-jem.yml bootstrap template"
      )

      add_monorepo_subgem_file_overrides(updated, gemspec_path)
    end

    def add_monorepo_root_file_overrides(content)
      override_lines = MONOREPO_ROOT_TEMPLATE_ENTRIES.reject { |entry| entry.to_s.include?("/") }.flat_map do |entry|
        kettle_config_file_override_lines(entry, "accept_template")
      end
      insert_after_line_sequence(
        content,
        ["files:"],
        override_lines.join("\n"),
        "Could not apply monorepo-root file overrides to .kettle-jem.yml bootstrap template"
      )
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

    def monorepo_subgem_template_entries(gemspec_path)
      entries = MONOREPO_SUBGEM_TEMPLATE_ENTRIES.dup
      gemspec = gemspec_path.to_s.strip
      return entries if gemspec.empty?

      entries.insert(1, { "source" => "gem.gemspec", "target" => gemspec })
      entries.concat(version_gem_template_entries(gemspec))
      entries
    end

    def version_gem_template_entries(gemspec_path)
      VERSION_GEM_TEMPLATE_SOURCES.map do |source|
        { "source" => source, "target" => version_gem_template_target_path(gemspec_path, source) }
      end
    end

    def version_gem_template_target_path(gemspec_path, source)
      package_name = File.basename(gemspec_path.to_s, ".gemspec")
      entrypoint_require = package_name.tr("-", "/")
      case source
      when "lib/gem/version.rb"
        File.join("lib", entrypoint_require, "version.rb")
      when "sig/gem/version.rbs"
        File.join("sig", entrypoint_require, "version.rbs")
      else
        source
      end
    end

    def add_monorepo_subgem_file_overrides(content, gemspec_path)
      override_lines = [
        "  README.md:",
        "    strategy: merge",
      ]
      gemspec = gemspec_path.to_s.strip
      unless gemspec.empty?
        override_lines.concat([
          "  #{gemspec}:",
          "    strategy: keep_destination",
        ])
      end
      insert_after_line_sequence(
        content,
        ["files:"],
        override_lines.join("\n"),
        "Could not apply monorepo-subgem file overrides to .kettle-jem.yml bootstrap template"
      )
    end

    def insert_after_line_sequence(content, sequence, insertion, error_message)
      lines = content.to_s.lines(chomp: true)
      index = (0..(lines.length - sequence.length)).find do |candidate|
        lines[candidate, sequence.length] == sequence
      end
      raise Error, error_message unless index

      insertion_lines = insertion.to_s.lines(chomp: true)
      updated = lines.dup
      updated.insert(index + sequence.length, *insertion_lines)
      "#{updated.join("\n")}\n"
    end

    def monorepo_subgem_template_profile?(facts)
      facts[:template_profile].to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE
    end

    def monorepo_root_template_profile?(facts)
      facts[:template_profile].to_s == MONOREPO_ROOT_TEMPLATE_PROFILE
    end

    def monorepo_template_profile?(facts)
      monorepo_root_template_profile?(facts) || monorepo_subgem_template_profile?(facts)
    end

    def readme_project_emoji(project_root)
      readme_path = File.join(project_root, "README.md")
      return nil unless File.exist?(readme_path)

      heading = File.read(readme_path).lines.find { |line| line.match?(/\A#\s+\S+/) }
      candidate = first_grapheme(heading.to_s.sub(/\A#\s+/, ""))
      decorative_grapheme?(candidate) ? candidate : nil
    end

    def first_grapheme(text)
      text.to_s.strip[/\A\X/u].to_s
    end

    def decorative_grapheme?(grapheme)
      value = grapheme.to_s
      return false if value.empty?

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

    def recipe_report_metadata(recipe)
      metadata = { packaging_recipe: recipe.fetch(:name) }
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
        only: normalize_list_option(option_hash.fetch(:only, env_hash["only"])),
        include: normalize_list_option(option_hash.fetch(:include, env_hash["include"])),
        template_profile: option_hash.fetch(:template_profile, env_hash["KETTLE_JEM_TEMPLATE_PROFILE"]).to_s,
        skip_commit: DecisionPolicy.value_to_boolean(option_hash.fetch(:skip_commit, env_hash["KETTLE_JEM_SKIP_COMMIT"])),
        accept_config: DecisionPolicy.value_to_boolean(option_hash.fetch(:accept_config, env_hash["KETTLE_JEM_ACCEPT_CONFIG"])),
        bootstrap_mode: DecisionPolicy.value_to_boolean(option_hash.fetch(:bootstrap_mode, env_hash["KETTLE_JEM_BOOTSTRAP_MODE"])),
        quiet: DecisionPolicy.value_to_boolean(option_hash.fetch(:quiet, env_hash["KETTLE_JEM_QUIET"])),
        verbose: DecisionPolicy.value_to_boolean(option_hash.fetch(:verbose, env_hash["KETTLE_JEM_VERBOSE"])),
      }.compact
    end

    def normalize_list_option(value)
      values = Array(value).flat_map { |entry| entry.to_s.split(",") }.map(&:strip).reject(&:empty?)
      values.empty? ? nil : values
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
          "Kettle/Jem setup bootstrap mode found existing .kettle-jem.yml; run kettle-jem apply to template the project."
        else
          "Created .kettle-jem.yml. Review it, then run kettle-jem --accept-config to continue setup."
        end,
      }
    end

    def setup_execution_context(env, run_options)
      return {bundled: false, source: "bootstrap_mode", bundle_gemfile: nil} if DecisionPolicy.value_to_boolean((run_options || {})[:bootstrap_mode])

      bundle_gemfile = (env || {})["BUNDLE_GEMFILE"].to_s.strip
      {
        bundled: !bundle_gemfile.empty?,
        source: bundle_gemfile.empty? ? "process" : "BUNDLE_GEMFILE",
        bundle_gemfile: bundle_gemfile.empty? ? nil : bundle_gemfile,
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
        selectors: selectors,
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
        provider_family: recipe.fetch(:provider_family),
      }
      if recipe.fetch(:primitive) == "supplied_obsolete_file_deletion"
        metadata.merge!(
          policy_kind: "delete_obsolete_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path),
        )
      end
      if recipe.fetch(:primitive) == "supplied_disabled_opencollective_file_deletion"
        metadata.merge!(
          policy_kind: "delete_disabled_opencollective_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path),
        )
      end
      if recipe.fetch(:primitive) == "supplied_legacy_destination_file_deletion"
        metadata.merge!(
          policy_kind: "delete_legacy_destination_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path),
        )
      end
      if recipe.fetch(:primitive) == "supplied_obsolete_license_file_deletion"
        metadata.merge!(
          policy_kind: "delete_obsolete_license_file",
          operation: "delete",
          deleted_file: recipe.fetch(:target_path),
        )
      end
      if recipe.fetch(:primitive) == "supplied_template_source_preference"
        metadata.merge!(
          policy_kind: "select_template_source",
          operation: "select",
          template_source_preference: deep_dup(recipe.fetch(:template_preference)),
        )
        metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
        metadata[:readme_style] = deep_dup(recipe[:readme_style]) if recipe[:readme_style]
      end
      if recipe.fetch(:primitive) == "supplied_template_source_application"
        metadata.merge!(
          policy_kind: "apply_template_source",
          operation: "replace",
          template_source_preference: deep_dup(recipe.fetch(:template_preference)),
        )
        metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      end
      if recipe.fetch(:primitive) == "supplied_kettle_config_bootstrap"
        metadata.merge!(
          policy_kind: "bootstrap_kettle_config",
          operation: "create",
          template_source_preference: deep_dup(recipe.fetch(:template_preference)),
        )
        metadata[:template_tokens] = deep_dup(recipe[:template_tokens]) if recipe[:template_tokens]
      end
      return metadata unless deletion

      metadata.merge(
        policy_kind: "delete_supplied_structural_owners",
        operation: "delete",
        consumed_context: "delete_selectors",
        deleted_ranges: deletion.fetch(:delete_selectors).length,
        deleted_selector_ids: deletion.fetch(:delete_selectors).map { |selector| selector.fetch(:selector_id) },
      )
    end

    def extract_gemspec_assignment(source, field)
      value = gemspec_assignment_record(source, field)&.fetch(:value)
      value if value.is_a?(String)
    end

    def extract_gemspec_array(source, field)
      value = gemspec_assignment_record(source, field)&.fetch(:value)
      value.is_a?(Array) ? value : []
    end

    def ruby_engines_config(config)
      engines = config["engines"]
      return nil unless engines.is_a?(Array)

      engines.map { |engine| engine.to_s.strip.downcase }.reject(&:empty?).uniq
    end

    def extract_metadata_value(source, key)
      gemspec_metadata_records(source).find { |record| record.fetch(:key) == key.to_s }&.fetch(:value)
    end

    def funding_urls(project_root, gemspec_source, package_name, opencollective_disabled: false, open_collective_org: nil)
      urls = [extract_metadata_value(gemspec_source, "funding_uri")]
      path = File.join(project_root, ".github", "FUNDING.yml")
      urls.concat(github_funding_urls(path, opencollective_disabled: opencollective_disabled)) if File.exist?(path)
      urls << github_funding_platform_urls("open_collective", [open_collective_org]).first unless opencollective_disabled
      urls << github_funding_platform_urls("tidelift", ["rubygems/#{package_name}"]).first

      urls.compact.uniq.sort
    end

    def github_funding_urls(path, opencollective_disabled: false)
      funding = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) || {}
      return [] unless funding.is_a?(Hash)

      funding.flat_map do |platform, value|
        next [] if opencollective_disabled && platform.to_s == "open_collective"

        github_funding_platform_urls(platform.to_s, Array(value).compact)
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
          handle if handle.match?(%r{\Ahttps?://})
        when "github"
          "https://github.com/sponsors/#{handle}"
        when "issuehunt"
          "https://issuehunt.io/u/#{handle}"
        when "ko_fi"
          "https://ko-fi.com/#{handle}"
        when "liberapay"
          "https://liberapay.com/#{handle}/donate"
        when "open_collective"
          "https://opencollective.com/#{handle}"
        when "patreon"
          "https://patreon.com/#{handle}"
        when "polar"
          "https://polar.sh/#{handle}"
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

    def github_actions_custom_workflows(project_root, opencollective_disabled: false)
      workflow_root = File.join(project_root, ".github", "workflows")
      return [] unless Dir.exist?(workflow_root)

      Dir.glob(File.join(workflow_root, "*.{yml,yaml}")).filter_map do |path|
        relative_path = path.delete_prefix("#{project_root}/")
        next if opencollective_disabled && opencollective_disabled_file?(relative_path)
        next if generated_or_obsolete_github_workflow?(relative_path)

        relative_path
      end.sort
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
      return true if relative_path == ".github/workflows/opencollective.yml"

      OBSOLETE_GITHUB_WORKFLOWS.include?(File.basename(relative_path))
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

    def git_preflight_report(project_root, template_selection:)
      inside = git_success?(project_root, "rev-parse", "--is-inside-work-tree")
      status = inside ? git_output(project_root, "status", "--porcelain") : nil
      dirty_entries = status.to_s.lines.map(&:chomp).reject(&:empty?)
      {
        git_repository: inside,
        clean_worktree: inside && dirty_entries.empty?,
        dirty_entries: dirty_entries,
        skip_commit: template_selection.fetch(:skip_commit, false),
      }
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
      path = File.join(project_root, ".kettle-jem.yml")
      return {} unless File.exist?(path)

      config = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) || {}
      validate_kettle_jem_config!(config)
      config
    rescue Psych::SyntaxError => error
      raise Error, "Invalid .kettle-jem.yml: #{error.message}"
    end

    def validate_kettle_jem_config!(config)
      raise Error, "Invalid .kettle-jem.yml: root must be a mapping" unless config.is_a?(Hash)

      templates = config["templates"]
      if templates && !templates.is_a?(Hash)
        raise Error, "Invalid .kettle-jem.yml: templates must be a mapping"
      end
      return unless templates&.key?("entries")
      return if templates["entries"].is_a?(Array)

      raise Error, "Invalid .kettle-jem.yml: templates.entries must be a list"
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

    def run_apply_phases(project_root, report)
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
        reports_by_phase.fetch(phase, []).each do |recipe_report|
          apply_recipe_report(project_root, recipe_report)
        end
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

    def apply_recipe_report(project_root, recipe_report)
      return unless recipe_report[:changed]

      path = File.join(project_root, recipe_report.fetch(:relative_path))
      if recipe_report.dig(:metadata, :delete_file)
        FileUtils.rm_f(path)
      else
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, recipe_report.fetch(:final_content))
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
            changed_count: changed_reports.length,
          },
        }
      end
    end

    def recipe_report_phase(recipe_report)
      phase_for_recipe(recipe_report[:recipe_name], recipe_report[:relative_path])
    end

    def phase_for_recipe(recipe_name, relative_path)
      path = relative_path.to_s
      name = recipe_name.to_s
      return :config_sync if path == ".kettle-jem.yml" || name.include?("kettle_config")
      return :dev_container if path.start_with?(".devcontainer/")
      return :github_workflows if path.start_with?(".github/workflows/") || path == ".github/FUNDING.yml"
      return :modular_gemfiles if path.start_with?("gemfiles/modular/")
      return :spec_helper if path == "spec/spec_helper.rb" || path.start_with?("spec/support/")
      return :environment_templates if path.start_with?(".env") || path.end_with?(".env")
      return :git_hooks if path.start_with?(".git/hooks/") || path.start_with?("git-hooks/")
      return :license_files if path.start_with?("LICENSE") || path.start_with?("NOTICE") || managed_license_template_basename(path)
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
        plugin_file_changes: diagnostics.count { |diagnostic| diagnostic[:kind] == "plugin_file_change" },
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
        "plugin_file_changes #{stats.fetch(:plugin_file_changes)}",
      ].join(" ")
    end

    def opencollective_disabled?(config, env: ENV)
      opencollective_policy(config, env).fetch(:disabled)
    end

    def opencollective_policy(config, env)
      funding = config["funding"]
      if funding.is_a?(Hash) && funding.key?("open_collective")
        config_value = funding["open_collective"]
        return {
          disabled: falsey_config?(config_value),
          source: "config.funding.open_collective",
          value: config_value.to_s,
        }
      end

      env_falsey = opencollective_falsey_env(env)
      return { disabled: true, source: "env.#{env_falsey.fetch(:key)}", value: env_falsey.fetch(:value).to_s } if env_falsey

      if config.dig("templates", "profile").to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE
        return { disabled: true, source: "config.templates.profile", value: MONOREPO_SUBGEM_TEMPLATE_PROFILE }
      end

      { disabled: false }
    end

    def opencollective_falsey_env(env)
      %w[OPENCOLLECTIVE_HANDLE FUNDING_ORG].each do |key|
        value = env[key]
        return { key: key, value: value } if falsey_config?(value)
      end
      nil
    end

    def opencollective_org(project_root, env, opencollective_disabled: false)
      return nil if opencollective_disabled

      env_org = opencollective_org_env(env)
      return env_org if env_org

      opencollective_org_file(project_root)
    end

    def opencollective_org_env(env)
      %w[OPENCOLLECTIVE_HANDLE FUNDING_ORG].each do |key|
        value = env[key].to_s.strip
        next if value.empty? || falsey_config?(value)

        return { org: value, source: "env.#{key}" }
      end
      nil
    end

    def opencollective_org_file(project_root)
      path = File.join(project_root, ".opencollective.yml")
      return nil unless File.exist?(path)

      config = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) || {}
      return nil unless config.is_a?(Hash)

      org = config.fetch("collective", config["org"]).to_s.strip
      return nil if org.empty?

      { org: org, source: ".opencollective.yml" }
    end

    def template_tokens(facts, funding)
      package = facts.fetch(:package)
      rubygems = facts.fetch(:rubygems)
      tokens = {
        "KJ|GEM_NAME" => package.fetch(:name).to_s,
        "KJ|GEM_NAME_PATH" => package.fetch(:name).to_s.tr("-", "/"),
        "KJ|GEM_SHIELD" => shield_token(package.fetch(:name).to_s),
        "KJ|GEM_MAJOR" => gem_major_token(facts.fetch(:project_runtime, {})[:version]),
        "KJ|GH_ORG" => facts.fetch(:project_runtime, {})[:github_org].to_s,
        "KJ|NAMESPACE" => rubygems.fetch(:namespace).to_s,
        "KJ|NAMESPACE_SHIELD" => shield_token(rubygems.fetch(:namespace).to_s),
        "KJ|MIN_RUBY" => minimum_ruby_token(rubygems[:min_ruby]),
        "KJ|MIN_DEV_RUBY" => minimum_dev_ruby_token(rubygems[:min_ruby]),
      }.merge(
        rubocop_template_tokens(rubygems[:min_ruby])
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
        project_runtime_template_tokens(facts.fetch(:project_runtime, {}))
      ).merge(
        readme_url_template_tokens(facts.fetch(:repository, {}), package.fetch(:name).to_s, facts.fetch(:project_runtime, {})[:github_org].to_s)
      ).merge(
        readme_logo_template_tokens(facts.fetch(:readme_logo, {}))
      )
      org = funding[:open_collective_org].to_s
      tokens["KJ|OPENCOLLECTIVE_ORG"] = org
      tokens["KJ|README:FAMILY_INTRO_BACKEND_MATRIX"] = readme_family_intro_and_backend_matrix
      tokens.merge!(version_gem_template_tokens(facts))

      tokens.reject { |key, value| value.empty? && !EMPTY_TEMPLATE_TOKENS.include?(key) }
    end

    def readme_url_template_tokens(repository, package_name, github_org)
      repo_url = repository[:url].to_s
      repo_name = repository[:name].to_s
      repo_slug = repository[:slug].to_s
      package_path = repository[:package_path].to_s
      package_source_url = repository[:package_source_url].to_s
      package_source_url = repo_url if package_source_url.empty?
      repo_url = "https://github.com/#{github_org}/#{package_name}" if repo_url.empty?
      repo_name = package_name if repo_name.empty?
      repo_slug = "#{github_org}/#{repo_name}" if repo_slug.empty?

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
        "KJ|README:GH_REPOSITORY_URL" => repo_url,
        "KJ|README:GH_PACKAGE_SOURCE_URL" => package_source_url,
        "KJ|README:GH_RELEASES_URL" => "#{repo_url}/releases",
        "KJ|README:GH_TAG_BADGE_REPO" => repo_slug,
        "KJ|README:GH_DISCUSSIONS_URL" => "#{repo_url}/discussions",
        "KJ|README:GH_ISSUES_URL" => "#{repo_url}/issues",
        "KJ|README:GH_PULLS_URL" => "#{repo_url}/pulls",
        "KJ|README:GH_WIKI_URL" => "#{repo_url}/wiki",
        "KJ|README:GH_CODEQL_URL" => "#{repo_url}/security/code-scanning",
        "KJ|README:GH_CONTRIBUTORS_URL" => "#{repo_url}/graphs/contributors",
        "KJ|README:GL_PACKAGE_SOURCE_URL" => gitlab_source,
        "KJ|README:GL_ISSUES_URL" => gitlab_repo_url(repository, repo_slug, "issues"),
        "KJ|README:GL_PULLS_URL" => gitlab_repo_url(repository, repo_slug, "merge_requests"),
        "KJ|README:GL_WIKI_URL" => gitlab_repo_url(repository, repo_slug, "wikis/home"),
        "KJ|README:GL_CONTRIBUTORS_URL" => gitlab_repo_url(repository, repo_slug, "graphs/main"),
        "KJ|README:CB_PACKAGE_SOURCE_URL" => codeberg_source,
        "KJ|README:CB_ISSUES_URL" => codeberg_repo_url(repository, repo_slug, "issues"),
        "KJ|README:CB_PULLS_URL" => codeberg_repo_url(repository, repo_slug, "pulls"),
        "KJ|README:CODECOV_URL" => "https://codecov.io/gh/#{repo_slug}",
        "KJ|README:CODECOV_BADGE_URL" => "https://codecov.io/gh/#{repo_slug}/graph/badge.svg",
        "KJ|README:CODECOV_GRAPH_URL" => "https://codecov.io/gh/#{repo_slug}/graphs/tree.svg",
        "KJ|README:COVERALLS_URL" => "https://coveralls.io/github/#{repo_slug}?branch=main",
        "KJ|README:COVERALLS_BADGE_URL" => "https://coveralls.io/repos/github/#{repo_slug}/badge.svg?branch=main",
        "KJ|README:QLTY_PROJECT_URL" => "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}",
        "KJ|README:QLTY_MAINTAINABILITY_URL" => "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}/maintainability.svg",
        "KJ|README:QLTY_COVERAGE_URL" => "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}/metrics/code?sort=coverageRating",
        "KJ|README:QLTY_COVERAGE_BADGE_URL" => "https://qlty.sh/gh/#{github_org}/projects/#{repo_name}/coverage.svg",
        "KJ|README:CONTRIBUTORS_IMAGE_REPO" => repo_slug,
        "KJ|README:STAR_HISTORY_REPO" => repo_slug,
        "KJ|README:SHA_CHECKSUMS_URL" => checksums_url,
      }
    end

    def version_gem_template_tokens(facts)
      namespace = facts.dig(:rubygems, :namespace).to_s
      version = facts.dig(:project_runtime, :version).to_s
      version = "0.0.1.pre" if version.empty?
      return {} if namespace.empty?

      {
        "KJ|VERSION_GEM:VERSION_RB" => version_gem_version_file_content(existing_version: "", namespace: namespace, version: version),
        "KJ|VERSION_GEM:VERSION_RBS" => version_gem_signature_file_content(namespace: namespace),
      }
    end

    def readme_family_intro_and_backend_matrix
      [
        "<details markdown=\"1\">",
        "<summary>StructuredMerge package family</summary>",
        "",
        "This gem is part of the StructuredMerge Ruby package family. The implementation inventory, layering model, and backend notes live in the [root package-family guide][sm-family-guide]. Shared behavior is defined by the [StructuredMerge fixtures][sm-family-fixtures] and implemented by the [Go][sm-family-go], [Ruby][sm-family-ruby], [Rust][sm-family-rust], and [TypeScript][sm-family-typescript] repositories.",
        "",
        "</details>",
        "",
        "[sm-family-guide]: https://github.com/structuredmerge/structuredmerge-ruby#package-family",
        "[sm-family-fixtures]: https://github.com/structuredmerge/structuredmerge-fixtures",
        "[sm-family-go]: https://github.com/structuredmerge/structuredmerge-go",
        "[sm-family-ruby]: https://github.com/structuredmerge/structuredmerge-ruby",
        "[sm-family-rust]: https://github.com/structuredmerge/structuredmerge-rust",
        "[sm-family-typescript]: https://github.com/structuredmerge/structuredmerge-typescript",
      ].join("\n")
    end

    def minimum_ruby_token(requirement)
      requirement.to_s[/\d+(?:\.\d+){1,2}/].to_s
    end

    def minimum_dev_ruby_token(requirement)
      min_ruby = minimum_ruby_token(requirement)
      return "" if min_ruby.empty?

      [Gem::Version.new(min_ruby), Gem::Version.new("2.3")].max.to_s
    rescue ArgumentError
      "2.3"
    end

    def gem_major_token(version)
      Gem::Version.new(version.to_s).segments.first.to_s
    rescue ArgumentError
      "0"
    end

    def author_facts(gemspec_source, config, env)
      token_config = token_config_values(config)
      author_config = token_config["author"].is_a?(Hash) ? token_config["author"] : {}
      derived_name = extract_gemspec_array(gemspec_source, "spec.authors").first
      derived_email = extract_gemspec_array(gemspec_source, "spec.email").first
      name = preferred_template_token_value(derived_name, author_config["name"], env, "KJ_AUTHOR_NAME").to_s
      email = preferred_template_token_value(derived_email, author_config["email"], env, "KJ_AUTHOR_EMAIL").to_s
      given_names = preferred_template_token_value(author_given_names(name), author_config["given_names"], env, "KJ_AUTHOR_GIVEN_NAMES")
      family_names = preferred_template_token_value(author_family_names(name), author_config["family_names"], env, "KJ_AUTHOR_FAMILY_NAMES")
      domain = preferred_template_token_value(email.split("@", 2)[1], author_config["domain"], env, "KJ_AUTHOR_DOMAIN")
      orcid = preferred_template_token_value(nil, author_config["orcid"], env, "KJ_AUTHOR_ORCID")
      compact_hash(
        name: name,
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

    def author_template_tokens(author)
      {
        "KJ|AUTHOR:NAME" => author[:name].to_s,
        "KJ|AUTHOR:GIVEN_NAMES" => author[:given_names].to_s,
        "KJ|AUTHOR:FAMILY_NAMES" => author[:family_names].to_s,
        "KJ|AUTHOR:EMAIL" => author[:email].to_s,
        "KJ|AUTHOR:DOMAIN" => author[:domain].to_s,
        "KJ|AUTHOR:ORCID" => author[:orcid].to_s,
      }
    end

    def copyright_facts(project_root, config)
      lines = git_copyright_lines(project_root, copyright_machine_users(config))
      compact_hash(lines: lines)
    end

    def copyright_machine_users(config)
      copyright = config["copyright"].is_a?(Hash) ? config["copyright"] : {}
      Array(copyright["machine_users"]).map { |user| user.to_s.downcase.strip }.reject(&:empty?)
    end

    def git_copyright_lines(project_root, machine_users)
      files = git_capture(project_root, "ls-files", "-z")
      return [] if files.to_s.empty?

      author_map = Hash.new { |hash, email| hash[email] = { name: nil, years: [], email: email } }
      files.split("\0").reject(&:empty?).each do |relative_path|
        next unless File.exist?(File.join(project_root, relative_path))

        parse_blame_porcelain(git_capture(project_root, "blame", "--porcelain", "--", relative_path), author_map)
      rescue ArgumentError
        next
      end
      resolve_uncommitted_author!(project_root, author_map)
      author_map.values
        .reject { |entry| copyright_bot_entry?(entry) }
        .reject { |entry| copyright_machine_user_entry?(entry, machine_users) }
        .reject { |entry| entry[:name].to_s.strip.empty? || entry[:years].empty? }
        .sort_by { |entry| [entry[:years].map(&:to_i).min, entry[:name].to_s.downcase] }
        .map { |entry| "Copyright (c) #{format_copyright_years(entry[:years])} #{entry[:name]}" }
    rescue ArgumentError
      []
    end

    def git_capture(project_root, *args)
      output = IO.popen(["git", "-C", project_root.to_s, *args], err: File::NULL, &:read)
      raise ArgumentError, "git #{args.join(" ")} failed" unless $CHILD_STATUS&.success?

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

          commit_meta[current_sha] ||= { name: current_name, email: current_email, time: current_time }
          year = current_time && current_time.positive? ? Time.at(current_time).utc.year.to_s : Time.now.utc.year.to_s
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
      entry[:name].to_s.match?(BOT_NAME_SUFFIX) || entry[:email].to_s.match?(BOT_EMAIL_PATTERN)
    end

    def copyright_machine_user_entry?(entry, machine_users)
      return false if machine_users.empty?

      machine_users.include?(entry[:name].to_s.downcase.strip) ||
        machine_users.include?(entry[:email].to_s.downcase.strip)
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
        "KJ|SH:USER" => forge[:sh_user].to_s,
      }
    end

    def funding_platform_token_facts(config, env)
      token_config = token_config_values(config)
      funding_config = token_config["funding"].is_a?(Hash) ? token_config["funding"] : {}
      compact_hash(
        patreon: funding_platform_token_value(funding_config, env, :patreon).to_s,
        kofi: funding_platform_token_value(funding_config, env, :kofi).to_s,
        paypal: funding_platform_token_value(funding_config, env, :paypal).to_s,
        buymeacoffee: funding_platform_token_value(funding_config, env, :buymeacoffee).to_s,
        polar: funding_platform_token_value(funding_config, env, :polar).to_s,
        liberapay: funding_platform_token_value(funding_config, env, :liberapay).to_s,
        issuehunt: funding_platform_token_value(funding_config, env, :issuehunt).to_s
      )
    end

    def funding_platform_token_value(funding_config, env, key)
      preferred_template_token_value(nil, funding_config[key.to_s], env, FUNDING_TOKEN_ENV_KEYS.fetch(key))
    end

    def funding_template_tokens(funding)
      platform_tokens = funding.fetch(:platform_tokens, {})
      {
        "KJ|FUNDING:PATREON" => platform_tokens[:patreon].to_s,
        "KJ|FUNDING:KOFI" => platform_tokens[:kofi].to_s,
        "KJ|FUNDING:PAYPAL" => platform_tokens[:paypal].to_s,
        "KJ|FUNDING:BUYMEACOFFEE" => platform_tokens[:buymeacoffee].to_s,
        "KJ|FUNDING:POLAR" => platform_tokens[:polar].to_s,
        "KJ|FUNDING:LIBERAPAY" => platform_tokens[:liberapay].to_s,
        "KJ|FUNDING:ISSUEHUNT" => platform_tokens[:issuehunt].to_s,
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
        "KJ|SOCIAL:DEVTO" => social[:devto].to_s,
      }
    end

    def project_runtime_facts(config, env, package_name:, source_url:, author_domain:, min_ruby:, version:)
      run_timestamp = Time.now
      configured_project_emoji = preferred_template_token_value(nil, config["project_emoji"], env, "KJ_PROJECT_EMOJI")
      compact_hash(
        freeze_token: config.dig("defaults", "freeze_token").to_s.empty? ? "kettle-jem" : config.dig("defaults", "freeze_token").to_s,
        kettle_jem_version: VERSION,
        template_run_date: run_timestamp.strftime("%Y-%m-%d"),
        template_run_year: run_timestamp.year.to_s,
        kettle_dev_gem: "kettle-dev",
        yard_host: "#{package_name.to_s.tr("_", "-")}.#{author_domain.to_s.empty? ? "example.com" : author_domain}",
        project_emoji: preferred_template_token_value("💎", config["project_emoji"], env, "KJ_PROJECT_EMOJI").to_s,
        project_emoji_configured: !configured_project_emoji.to_s.empty?,
        min_divergence_threshold: preferred_template_token_value(nil, config["min_divergence_threshold"], env, "KJ_MIN_DIVERGENCE_THRESHOLD").to_s,
        min_dev_ruby: minimum_dev_ruby_token(min_ruby),
        version: version.to_s,
        github_org: github_org_from_url(source_url).to_s
      )
    end

    def project_runtime_template_tokens(project_runtime)
      {
        "KJ|FREEZE_TOKEN" => project_runtime[:freeze_token].to_s,
        "KJ|KETTLE_JEM_VERSION" => project_runtime[:kettle_jem_version].to_s,
        "KJ|TEMPLATE_RUN_DATE" => project_runtime[:template_run_date].to_s,
        "KJ|TEMPLATE_RUN_YEAR" => project_runtime[:template_run_year].to_s,
        "KJ|KETTLE_DEV_GEM" => project_runtime[:kettle_dev_gem].to_s,
        "KJ|YARD_HOST" => project_runtime[:yard_host].to_s,
        "KJ|PROJECT_EMOJI" => project_runtime[:project_emoji].to_s,
        "KJ|MIN_DIVERGENCE_THRESHOLD" => project_runtime[:min_divergence_threshold].to_s,
      }
    end

    def version_gem_bootstrap_step(project_root, facts)
      version_gem_bootstrap_step_for_paths(project_root, facts)
    end

    def version_gem_bootstrap_step_for_paths(project_root, facts, manage_version_file: true, manage_signature_file: true)
      package_name = facts.dig(:package, :name).to_s
      return {name: "version_gem_bootstrap", status: "unavailable", reason: "missing_package_facts"} if package_name.empty?

      entrypoint_require = package_name.tr("-", "/")
      version_path = File.join("lib", entrypoint_require, "version.rb")
      entrypoint_path = File.join("lib", "#{entrypoint_require}.rb")
      signature_path = File.join("sig", entrypoint_require, "version.rbs")
      namespace = existing_entrypoint_version_namespace(project_root, entrypoint_path) ||
        existing_version_namespace(project_root, version_path) ||
        facts.dig(:rubygems, :namespace).to_s
      return {name: "version_gem_bootstrap", status: "unavailable", reason: "missing_package_facts"} if namespace.empty?

      version = facts.dig(:project_runtime, :version).to_s
      version = project_gemspec_version(project_root) if version.empty?
      version = "0.0.1.pre" if version.empty?
      changes = []

      if manage_version_file
        changes << write_if_changed(
          project_root,
          version_path,
          version_gem_version_file_content(existing_version: existing_version_file_value(project_root, version_path), namespace: namespace, version: version)
        )
      end
      current_entrypoint = read_project_file(project_root, entrypoint_path)
      entrypoint_content = if current_entrypoint.empty?
        version_gem_entrypoint_file_content(namespace: namespace, entrypoint_require: entrypoint_require)
      else
        version_gem_bootstrap_entrypoint_content(current_entrypoint, namespace: namespace, entrypoint_require: entrypoint_require)
      end
      changes << write_if_changed(project_root, entrypoint_path, entrypoint_content)
      changes << write_if_changed(project_root, signature_path, version_gem_signature_file_content(namespace: namespace)) if manage_signature_file
      changed_files = changes.compact

      {
        name: "version_gem_bootstrap",
        status: changed_files.empty? ? "already_current" : "applied",
        changed_files: changed_files,
        version_path: version_path,
        entrypoint_path: entrypoint_path,
        signature_path: signature_path,
      }
    end

    def version_gem_version_file_content(existing_version:, namespace:, version:)
      resolved_version = existing_version.to_s.empty? ? version.to_s : existing_version.to_s
      body = [
        "module Version",
        "  VERSION = #{resolved_version.dump}",
        "end",
        "VERSION = Version::VERSION # Traditional Constant Location",
      ]

      <<~RUBY
        # frozen_string_literal: true

        #{wrap_ruby_namespace(namespace, body).join("\n")}
      RUBY
    end

    def version_gem_entrypoint_file_content(namespace:, entrypoint_require:)
      sections = ["# frozen_string_literal: true"]
      requires = []
      requires << 'require "version_gem"' unless File.basename(entrypoint_require) == "version_gem"
      requires << %(require_relative "#{File.join(File.basename(entrypoint_require), "version")}")
      sections << requires.join("\n")
      sections << wrap_ruby_namespace(namespace, []).join("\n")
      sections << version_gem_class_eval_block(namespace).chomp
      "#{sections.reject(&:empty?).join("\n\n")}\n"
    end

    def version_gem_signature_file_content(namespace:)
      body = [
        "module Version",
        "  VERSION: String",
        "end",
        "VERSION: String",
      ]

      "#{wrap_ruby_namespace(namespace, body).join("\n")}\n"
    end

    def version_gem_bootstrap_entrypoint_content(content, namespace:, entrypoint_require:)
      current = content.to_s
      lines = current.lines
      insert_lines = []
      if File.basename(entrypoint_require) != "version_gem" && !ruby_top_level_require?(current, "require", "version_gem")
        insert_lines << "require \"version_gem\"\n"
      end
      relative_path = File.join(File.basename(entrypoint_require), "version")
      insert_lines << %(require_relative "#{relative_path}"\n) unless ruby_top_level_require?(current, "require_relative", relative_path)
      if insert_lines.any?
        after_version_gem = insert_lines.none? { |line| line.include?('"version_gem"') }
        lines.insert(version_gem_require_insertion_index(current, after_version_gem: after_version_gem), *insert_lines, "\n")
      end

      updated = lines.join
      unless ruby_version_class_eval_namespaces(updated).include?(namespace.to_s)
        updated += "\n" unless updated.end_with?("\n")
        updated += "\n#{version_gem_class_eval_block(namespace)}"
      end
      collapse_excess_blank_lines(updated)
    end

    def version_gem_require_insertion_index(content, after_version_gem: false)
      context = Ast::Crispr::Ruby::Prism.document_context(content: content.to_s, source_label: "entrypoint.rb")
      owners = context.structural_owners(owner_scope: :top_level_statements)
      if after_version_gem
        owner = owners.find { |candidate| ruby_require_call?(candidate, "require", "version_gem") }
        return owner.location.end_line if owner
      end

      first_owner = owners.first
      first_owner ? first_owner.location.start_line - 1 : context.ast.comments.map { |comment| comment.location.end_line }.max.to_i
    end

    def ruby_top_level_require?(content, method_name, argument)
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

    def version_gem_class_eval_block(namespace)
      <<~RUBY
        #{namespace}::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
    end

    def wrap_ruby_namespace(namespace, body_lines)
      segments = namespace.to_s.split("::").reject(&:empty?)
      return body_lines if segments.empty?

      lines = []
      segments.each_with_index { |segment, index| lines << ("  " * index) + "module #{segment}" }
      body_lines.each { |line| lines << ("  " * segments.length) + line unless line.empty? }
      (segments.length - 1).downto(0) { |index| lines << ("  " * index) + "end" }
      lines
    end

    def existing_version_file_value(project_root, relative_path)
      ruby_version_constant_value(read_project_file(project_root, relative_path)).to_s
    end

    def existing_version_namespace(project_root, relative_path)
      ruby_version_module_namespace(read_project_file(project_root, relative_path))
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
      return unless node.is_a?(::Prism::ModuleNode)

      current = namespace + ruby_constant_path_segments(node.constant_path)
      if current.last == "Version" && current.length > 1
        return current[0...-1].join("::")
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

    def existing_entrypoint_version_namespace(project_root, relative_path)
      ruby_version_class_eval_namespaces(read_project_file(project_root, relative_path)).first
    end

    def ruby_version_class_eval_namespaces(content)
      ruby_call_records(content, :class_eval).filter_map do |call|
        receiver = call.receiver&.slice.to_s
        next unless receiver.end_with?("::Version")
        next unless call.block

        receiver.delete_suffix("::Version")
      end
    end

    def read_project_file(project_root, relative_path)
      path = File.join(project_root, relative_path)
      File.file?(path) ? File.read(path) : ""
    end

    def write_if_changed(project_root, relative_path, content)
      path = File.join(project_root, relative_path)
      current = File.file?(path) ? File.read(path) : ""
      return nil if current == content

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      relative_path
    end

    def shield_token(value)
      value.to_s.gsub("-", "--").gsub("_", "__").gsub("::", "%3A%3A").tr(" ", "_")
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

    def repository_facts(project_root, source_url, package_name:, template_profile:)
      local_root = template_profile.to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE ? git_worktree_root(project_root) : nil
      repo_url = if template_profile.to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE
        repository_root_url(git_remote_source_url(local_root || project_root) || source_url)
      else
        repository_root_url(source_url)
      end
      repo_name = repository_name_from_source_url(repo_url)
      org = github_org_from_url(repo_url).to_s
      slug = [org, repo_name].reject(&:empty?).join("/")
      facts = compact_hash(
        mode: template_profile.to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE ? "monorepo_subgem" : "standalone",
        url: repo_url,
        name: repo_name,
        slug: slug
      )
      return facts unless template_profile.to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE

      package_path = git_worktree_prefix(project_root)
      package_path = "gems/#{package_name}" if package_path.empty?
      package_path = package_path[0...-1] while package_path.end_with?("/")
      facts.merge(
        local_root: local_root,
        package_path: package_path,
        package_source_url: source_tree_url(repo_url, package_path),
        gitlab_package_source_url: source_tree_url("https://gitlab.com/#{slug}", package_path),
        codeberg_package_source_url: source_tree_url("https://codeberg.org/#{slug}", package_path),
        checksums_url: source_tree_url("https://gitlab.com/#{slug}", "checksums")
      )
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
    end

    def git_worktree_prefix(project_root)
      git_capture(project_root, "rev-parse", "--show-prefix").strip
    end

    def gitlab_repo_url(repository, repo_slug, suffix)
      base = repository[:gitlab_url].to_s
      base = "https://gitlab.com/#{repo_slug}" if base.empty?
      "#{base}/-/#{suffix}"
    end

    def codeberg_repo_url(repository, repo_slug, suffix)
      base = repository[:codeberg_url].to_s
      base = "https://codeberg.org/#{repo_slug}" if base.empty?
      "#{base}/#{suffix}"
    end

    def git_remote_source_url(project_root)
      normalize_git_source_url(git_capture(project_root, "config", "--get", "remote.origin.url").strip)
    rescue ArgumentError
      nil
    end

    def normalize_git_source_url(url)
      value = url.to_s.strip
      return nil if value.empty?

      if (match = value.match(/\Agit@github\.com:([^\/]+)\/(.+?)(?:\.git)?\z/))
        return "https://github.com/#{match[1]}/#{match[2]}"
      end
      if (match = value.match(%r{\Ahttps?://github\.com/([^/]+)/(.+?)(?:\.git)?\z}))
        return "https://github.com/#{match[1]}/#{match[2]}"
      end

      value
    end

    def readme_logo_facts(config, package_name:, github_org:)
      entries = readme_top_logo_entries(config, org: github_org.to_s, gem_name: package_name.to_s)
      compact_hash(
        top_logo_mode: readme_top_logo_mode(config),
        top_logo_row: [README_STATIC_TOP_LOGO_ROW, readme_top_logo_row(entries)].reject(&:empty?).join(" "),
        top_logo_refs: [README_STATIC_TOP_LOGO_REFS, readme_top_logo_refs(entries)].reject(&:empty?).join("\n")
      )
    end

    def readme_top_logo_mode(config)
      raw_config = config.is_a?(Hash) ? config["readme"] : nil
      readme_config = raw_config.is_a?(Hash) ? raw_config : {}
      normalized = readme_config["top_logo_mode"].to_s.strip.downcase.tr("-", "_")
      return README_TOP_LOGO_MODE_DEFAULT if normalized.empty?
      return normalized if README_TOP_LOGO_MODES.include?(normalized)

      README_TOP_LOGO_MODE_DEFAULT
    end

    def readme_top_logo_entries(config, org:, gem_name:)
      configured = configured_readme_top_logo_entries(config, org: org, gem_name: gem_name)
      return configured if configured

      readme_top_logo_mode_entries(readme_top_logo_mode(config), org: org, gem_name: gem_name)
    end

    def configured_readme_top_logo_entries(config, org:, gem_name:)
      readme_config = config.is_a?(Hash) && config["readme"].is_a?(Hash) ? config["readme"] : {}
      logo_row = readme_config["logo_row"]
      return nil unless logo_row.is_a?(Hash)
      return [] if falsey_config?(logo_row["enabled"])

      logos = Array(logo_row["logos"]).first(3)
      return [] if logos.empty?

      logos.filter_map do |logo|
        readme_top_logo_entry_from_config(logo, org: org, gem_name: gem_name)
      end.uniq { |entry| [entry[:image_ref], entry[:link_ref], entry[:image_url], entry[:href]] }
    end

    def readme_top_logo_entry_from_config(logo, org:, gem_name:)
      return nil unless logo.is_a?(Hash)

      type = logo["type"].to_s.strip.downcase.tr("-", "_")
      return nil unless README_TOP_LOGO_TYPES.include?(type)

      slug = logo["slug"].to_s.strip
      slug = default_readme_top_logo_slug(type, org: org, gem_name: gem_name) if slug.empty?
      return nil if slug.empty?

      alt = logo["alt"].to_s.strip
      alt = readme_top_logo_default_alt(type, slug) if alt.empty?
      href = logo["href"].to_s.strip
      href = default_readme_top_logo_href(type, slug: slug, org: org, gem_name: gem_name) if href.empty?
      ref_slug = slug.tr("/", "-")
      {
        label: alt.sub(/\s+logo\z/i, ""),
        image_ref: "#{ref_slug}-i",
        link_ref: ref_slug,
        image_url: "#{LOGOS_GALTZO_BASE_URL}/#{slug}/avatar-192px.svg",
        href: href,
      }
    end

    def default_readme_top_logo_slug(type, org:, gem_name:)
      case type
      when "language"
        "ruby-lang"
      when "org"
        org.to_s
      when "project"
        [org, gem_name].reject(&:empty?).join("/")
      else
        ""
      end
    end

    def readme_top_logo_default_alt(type, slug)
      label = slug.split("/").last.to_s
      case type
      when "language"
        "#{label} language"
      when "org"
        "#{label} organization"
      when "project"
        "#{label} project"
      else
        "#{label} affiliated project"
      end
    end

    def default_readme_top_logo_href(type, slug:, org:, gem_name:)
      case type
      when "language"
        slug == "ruby-lang" ? "https://www.ruby-lang.org/" : "#{LOGOS_GALTZO_BASE_URL}/#{slug}/"
      when "org"
        org.to_s.empty? ? "#{LOGOS_GALTZO_BASE_URL}/#{slug}/" : "https://github.com/#{org}"
      when "project"
        org.to_s.empty? || gem_name.to_s.empty? ? "#{LOGOS_GALTZO_BASE_URL}/#{slug}/" : "https://github.com/#{org}/#{gem_name}"
      else
        "#{LOGOS_GALTZO_BASE_URL}/#{slug}/"
      end
    end

    def readme_top_logo_mode_entries(mode, org:, gem_name:)
      return [] if org.empty?

      entries = []
      if mode == "org" || mode == "org_and_project"
        entries << {
          label: org,
          image_ref: "#{org}-i",
          link_ref: org,
          image_url: "#{LOGOS_GALTZO_BASE_URL}/#{org}/avatar-192px.svg",
          href: "https://github.com/#{org}",
        }
      end
      if mode == "project" || mode == "org_and_project"
        entries << {
          label: gem_name,
          image_ref: "#{gem_name}-i",
          link_ref: gem_name,
          image_url: "#{LOGOS_GALTZO_BASE_URL}/#{org}/#{gem_name}/avatar-192px.svg",
          href: "https://github.com/#{org}/#{gem_name}",
        }
      end
      entries.uniq { |entry| [entry[:image_ref], entry[:link_ref], entry[:image_url], entry[:href]] }
    end

    def readme_top_logo_row(entries)
      entries.map do |entry|
        "[![#{entry[:label]} Logo by Aboling0, CC BY-SA 4.0][🖼️#{entry[:image_ref]}]][🖼️#{entry[:link_ref]}]"
      end.join(" ")
    end

    def readme_top_logo_refs(entries)
      entries.flat_map do |entry|
        [
          "[🖼️#{entry[:image_ref]}]: #{entry[:image_url]}",
          "[🖼️#{entry[:link_ref]}]: #{entry[:href]}",
        ]
      end.join("\n")
    end

    def readme_logo_template_tokens(readme_logo)
      {
        "KJ|README:TOP_LOGO_ROW" => readme_logo[:top_logo_row].to_s,
        "KJ|README:TOP_LOGO_REFS" => readme_logo[:top_logo_refs].to_s,
      }
    end

    def rubocop_template_tokens(min_ruby)
      constraint, gem_name = rubocop_tokens_for(min_ruby_version(min_ruby))
      {
        "KJ|RUBOCOP_LTS_CONSTRAINT" => constraint,
        "KJ|RUBOCOP_RUBY_GEM" => gem_name,
      }
    end

    def rubocop_tokens_for(min_ruby)
      fallback = RUBOCOP_VERSION_MAP.first
      selected = nil
      RUBOCOP_VERSION_MAP.reverse_each do |minimum, constraint|
        next unless min_ruby && min_ruby >= minimum

        selected = [minimum, constraint]
        break
      end
      selected ||= fallback
      [selected[1], "rubocop-ruby#{selected[0].segments.join("_")}"]
    end

    def min_ruby_version(requirement)
      token = minimum_ruby_token(requirement)
      return nil if token.empty?

      Gem::Version.new(token)
    rescue ArgumentError
      nil
    end

    def license_facts(config, gemspec_licenses, author: {}, author_email: nil, copyright: {})
      licenses = resolved_licenses(config, gemspec_licenses)
      primary = licenses.first
      compat_category = license_compat_category(licenses)
      copyright_prefix = polyform_licenses?(licenses) ? "Required Notice: " : ""
      copyright_lines = Array(copyright[:lines])
      compact_hash(
        spdx: licenses,
        expression: licenses.join(" OR "),
        primary_spdx: primary,
        license_md_content: license_md_content(licenses, author_email: author_email),
        readme_license_intro: readme_license_intro(licenses, author_email: author_email),
        readme_license_badge: license_badge(licenses.join(" OR "), ref: :license),
        readme_license_compat_badge: license_compat_badge(compat_category),
        readme_license_eye_workflow_badge: license_eye_workflow_badge(licenses),
        readme_license_refs: readme_license_refs(licenses.join(" OR "), compat_category),
        license_copyright_notice: license_copyright_notice(copyright_lines, copyright_prefix, author),
        readme_copyright_notice: readme_copyright_notice(copyright_lines, copyright_prefix, author),
        copyright_prefix: copyright_prefix
      )
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
        "KJ|README:LICENSE_INTRO" => license[:readme_license_intro].to_s,
        "KJ|LICENSE:PRIMARY_SPDX" => license[:primary_spdx].to_s,
        "KJ|README:LICENSE_BADGE" => license[:readme_license_badge].to_s,
        "KJ|README:LICENSE_COMPAT_BADGE" => license[:readme_license_compat_badge].to_s,
        "KJ|README:LICENSE_EYE_WORKFLOW_BADGE" => license[:readme_license_eye_workflow_badge].to_s,
        "KJ|README:LICENSE_REFS" => license[:readme_license_refs].to_s,
        "KJ|LICENSE_COPYRIGHT_NOTICE" => license[:license_copyright_notice].to_s,
        "KJ|README:COPYRIGHT_NOTICE" => license[:readme_copyright_notice].to_s,
        "KJ|COPYRIGHT_PREFIX" => license[:copyright_prefix].to_s,
      }
    end

    def license_copyright_notice(copyright_lines, copyright_prefix, author)
      lines = copyright_notice_lines(copyright_lines, copyright_prefix, author)
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

    def license_md_content(licenses, author_email: nil)
      content = <<~MARKDOWN.chomp
        # License

        This project is made available under the following license#{"s" if licenses.size > 1}.
        Choose the option that best fits your use case:

        #{licenses.map { |license| "- #{license_link(license)}" }.join("\n")}
      MARKDOWN
      guide_table = license_use_case_guide_table(licenses, author_email: author_email)
      content += "\n\n## Use-case guide\n\n#{guide_table}" if guide_table
      content += "\n\n#{license_contact_line(author_email, context: :license_md)}" if non_mit_licenses?(licenses)
      content
    end

    def readme_license_intro(licenses, author_email: nil)
      return mit_readme_license_intro if licenses == ["MIT"]

      intro = "The gem is available under the following license#{"s" if licenses.size > 1}: " \
        "#{licenses.map { |license| license_link(license) }.join(", ")}.\n" \
        "See [LICENSE.md][#{paperclip_ref(:license)}] for details."
      intro += "\n\n#{license_contact_line(author_email, context: :readme)}" if non_mit_licenses?(licenses)
      guide_table = license_use_case_guide_table(licenses, author_email: author_email)
      intro += "\n\n### License use-case guide\n\n#{guide_table}" if guide_table
      intro
    end

    def mit_readme_license_intro
      "The gem is available as open source under the terms of\n" \
        "the #{license_link("MIT")} #{license_badge("MIT")}."
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

    def readme_license_refs(expression, compat_category)
      [
        "[#{paperclip_ref(:copyright_notice_explainer)}]: https://opensource.stackexchange.com/questions/5778/why-do-licenses-such-as-the-mit-license-specify-a-single-year",
        "[#{paperclip_ref(:license)}]: LICENSE.md",
        "[#{paperclip_ref(:license_ref)}]: #{license_badge_ref(expression)}",
        "[#{paperclip_ref(:license_img)}]: #{license_badge_img(expression)}",
        "[#{paperclip_ref(:license_compat)}]: #{license_compat_ref(compat_category)}",
        "[#{paperclip_ref(:license_compat_img)}]: #{license_compat_img(compat_category)}",
      ].join("\n")
    end

    def spdx_basename(spdx_id)
      spdx_id.to_s.sub(/\ALicenseRef-/, "")
    end

    def license_link(spdx_id)
      base = spdx_basename(spdx_id)
      "[#{base}](#{base}.md)"
    end

    def license_badge(spdx_id, ref: :license_ref)
      base = spdx_basename(spdx_id)
      "[![License: #{base}][#{paperclip_ref(:license_img)}]][#{paperclip_ref(ref)}]"
    end

    def license_badge_ref(spdx_id)
      base = spdx_basename(spdx_id)
      base.include?(" OR ") ? "LICENSE.md" : "#{base}.md"
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

    def license_eye_workflow_badge(licenses)
      Array(licenses).map(&:to_s).include?("MIT") ? README_LICENSE_EYE_WORKFLOW_BADGE : ""
    end

    def license_compat_ref(category)
      APACHE_LICENSE_COMPAT_BADGE_DATA.fetch(category).fetch(:ref)
    end

    def license_compat_img(category)
      data = APACHE_LICENSE_COMPAT_BADGE_DATA.fetch(category)
      "https://img.shields.io/badge/#{data.fetch(:label)}-#{data.fetch(:message)}-#{data.fetch(:color)}.svg?style=flat&logo=Apache"
    end

    def polyform_licenses?(licenses)
      licenses.any? { |license| license.to_s.start_with?("PolyForm-") }
    end

    def non_mit_licenses?(licenses)
      licenses.any? { |license| license != "MIT" }
    end

    def license_use_case_guide_table(licenses, author_email: nil)
      has_floss_oss = licenses.include?("MIT") || licenses.include?("AGPL-3.0-only")
      has_polyform = licenses.include?("PolyForm-Noncommercial-1.0.0") || licenses.include?("PolyForm-Small-Business-1.0.0")
      has_big_time = licenses.include?("LicenseRef-Big-Time-Public-License")
      return unless has_floss_oss && has_polyform && has_big_time

      rows = license_use_case_rows(licenses, author_email: author_email)
      return if rows.empty?

      "| Use case | License |\n|---|---|\n" +
        rows.map { |use_case, license| "| #{use_case} | #{license} |" }.join("\n")
    end

    def license_use_case_rows(licenses, author_email: nil)
      rows = []
      rows << ["FLOSS (free and open source)", license_link("MIT")] if licenses.include?("MIT")
      rows << ["Copy-left open source", license_link("AGPL-3.0-only")] if licenses.include?("AGPL-3.0-only")
      noncommercial_links = %w[PolyForm-Noncommercial-1.0.0 PolyForm-Small-Business-1.0.0 LicenseRef-Big-Time-Public-License]
        .select { |license| licenses.include?(license) }
        .map { |license| license_link(license) }
      rows << ["Non-commercial (research, education, personal use)", noncommercial_links.join(" or ")] unless noncommercial_links.empty?
      small_business_links = %w[PolyForm-Small-Business-1.0.0 LicenseRef-Big-Time-Public-License]
        .select { |license| licenses.include?(license) }
        .map { |license| license_link(license) }
      rows << ["Small business commercial", small_business_links.join(" or ")] unless small_business_links.empty?
      rows << ["Larger business commercial", large_business_license_cell(author_email)] if licenses.include?("LicenseRef-Big-Time-Public-License")
      rows
    end

    def large_business_license_cell(author_email)
      cell = license_link("LicenseRef-Big-Time-Public-License")
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
        license_compat_img: "\u{1F4C4}license-compat-img",
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

    def readme_style_facts(project_root, config, license, template_profile: nil, repository: nil)
      readme = config["readme"].is_a?(Hash) ? config["readme"] : {}
      conditional = readme["conditional_sections"].is_a?(Hash) ? readme["conditional_sections"] : {}
      disabled_integrations = readme_disabled_integrations(readme)
      integration_root = readme_integration_project_root(project_root, template_profile, repository)
      missing_integrations = README_INTEGRATIONS.reject do |integration|
        disabled_integrations.include?(integration) || readme_integration_configured?(integration_root, integration)
      end
      workflow_paths = readme_workflow_paths(integration_root)
      omitted_sections = []
      security_enabled = template_profile.to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE ||
        File.exist?(File.join(project_root, "SECURITY.md"))
      floss_funding_enabled = readme_floss_funding_enabled?(license, conditional["floss_funding"])
      omitted_sections << "security" unless security_enabled
      omitted_sections << "floss_funding" unless floss_funding_enabled
      section_partials = readme_section_partials(project_root, config, readme)
      compact_hash(
        profile: "slice-740-kettle-readme-style-profile",
        security_enabled: security_enabled,
        floss_funding_enabled: floss_funding_enabled,
        omitted_sections: omitted_sections,
        disabled_integrations: disabled_integrations,
        missing_integrations: missing_integrations,
        workflow_paths: workflow_paths,
        section_partials: section_partials,
      )
    end

    def readme_integration_project_root(project_root, template_profile, repository)
      return project_root unless template_profile.to_s == MONOREPO_SUBGEM_TEMPLATE_PROFILE

      Array(repository && repository[:local_root]).find { |path| !path.to_s.empty? } || project_root
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
          content: File.read(File.join(root.fetch(:path), selected)),
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

    def readme_disabled_integrations(readme)
      disabled = []
      integrations = readme["integrations"].is_a?(Hash) ? readme["integrations"] : {}
      badges = readme["badges"].is_a?(Hash) ? readme["badges"] : {}
      integrations.each do |name, value|
        disabled << name.to_s if falsey_config?(value)
      end
      disabled.concat(Array(badges["disabled"]).map(&:to_s))
      disabled.map { |name| name.tr("_", "-").downcase }.map { |name| name == "code-ql" ? "codeql" : name }.uniq & README_INTEGRATIONS
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
      return false if recipe.fetch(:target_path).to_s == ".kettle-jem.yml"
      return false if recipe.dig(:template_preference, :skip_unresolved_scan)

      true
    end

    def stringify_template_tokens(tokens)
      tokens.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    end

    def falsey_config?(value)
      %w[false no 0].include?(value.to_s.strip.downcase)
    end

    def merge_readme_template(template_content:, destination_content:, preserve_config: {})
      return template_content if destination_content.to_s.strip.empty?

      preserved = preserve_readme_sections(template_content, destination_content, preserve_config)
      with_h1 = preserve_readme_h1(preserved, destination_content, preserve_config)
      preserve_readme_managed_block(with_h1, destination_content, "kettle-jem:metadata")
    end

    def preserve_readme_sections(template_content, destination_content, preserve_config)
      template_sections = markdown_sections(template_content)
      destination_sections = markdown_sections(destination_content)
      destination_lookup = destination_sections.to_h { |section| [section.fetch(:base), section] }
      preserve_targets = readme_preserve_targets(template_sections, destination_lookup, preserve_config)
      return template_content if preserve_targets.empty?

      lines = template_content.split("\n", -1)
      template_sections.reverse_each do |section|
        next unless preserve_targets.include?(section.fetch(:base))

        destination_section = destination_lookup[section.fetch(:base)] ||
          aliased_readme_destination_section(section.fetch(:base), destination_lookup, preserve_config)
        next unless destination_section

        replacement = "#{section.fetch(:heading)}\n#{destination_section.fetch(:body)}".split("\n", -1)
        lines[section.fetch(:start)..section.fetch(:end)] = replacement
      end
      lines.join("\n")
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
      open = "<!-- #{marker}:start -->"
      close = "<!-- #{marker}:end -->"
      context = Ast::Crispr::Markdown::Markly.document_context(content: content.to_s, source_label: "managed markdown block")
      target = Ast::Crispr::Markdown::Markly::Selectors.html_comment_block(
        start_text: open.delete_prefix("<!-- ").delete_suffix(" -->"),
        end_text: close.delete_prefix("<!-- ").delete_suffix(" -->"),
        span: :outermost,
        limit: {none_or_one: true},
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
          body: body,
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

    def template_runtime_config(config, facts, license: {})
      result = deep_dup(config)
      result["rubygems"] = {} unless result["rubygems"].is_a?(Hash)
      result["rubygems"]["min_ruby"] ||= facts.dig(:rubygems, :min_ruby)
      result["resolved_licenses"] = license[:spdx]
      result
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

      template_inventory_entries(project_root, root.fetch(:path))
    end

    def template_inventory_entries(project_root, template_root_path)
      logical_paths = []
      Find.find(template_root_path) do |path|
        next if File.directory?(path)

        relative_path = path.delete_prefix("#{template_root_path}/")
        logical_path = relative_path
          .sub(/\.no-osc\.example\z/, "")
          .sub(/\.example\z/, "")
        next if logical_path.start_with?("readme/partials/")
        next if logical_path == "gemfiles/modular/shunted.gemfile"

        logical_paths << logical_path unless logical_path.empty?
      end

      logical_paths.uniq.sort.map do |logical_path|
        target_path = template_inventory_target_path(project_root, logical_path)
        if target_path == logical_path
          logical_path
        else
          { "source" => logical_path, "target" => target_path }
        end
      end
    end

    def template_inventory_target_path(project_root, logical_path)
      return ".env.local.example" if logical_path == ".env.local"

      if VERSION_GEM_TEMPLATE_SOURCES.include?(logical_path)
        existing_gemspec = Dir.glob(File.join(project_root, "*.gemspec")).sort.first
        return version_gem_template_target_path(File.basename(existing_gemspec), logical_path) if existing_gemspec
      end

      if logical_path.end_with?(".gemspec")
        existing_gemspec = Dir.glob(File.join(project_root, "*.gemspec")).sort.first
        return File.basename(existing_gemspec) if existing_gemspec
      end

      logical_path
    end

    def copy_only_when_missing_template_path?(relative_path)
      COPY_ONLY_WHEN_MISSING_TEMPLATE_PATHS.include?(relative_path.to_s)
    end

    def kettle_config_bootstrap_facts(project_root, env, template_selection: {})
      return if File.exist?(File.join(project_root, ".kettle-jem.yml"))

      selected_source = preferred_template_source(PACKAGED_TEMPLATE_ROOT, ".kettle-jem.yml")
      return unless selected_source

      {
        template_preference: {
          target_path: ".kettle-jem.yml",
          configured_source: ".kettle-jem.yml",
          selected_source: selected_source,
          source_relative_path: selected_source,
          source_root: "packaged",
          source_root_path: PACKAGED_TEMPLATE_ROOT,
          selection_reason: template_source_selection_reason(".kettle-jem.yml", selected_source),
          apply: true,
        },
        min_divergence_threshold: preferred_template_token_value(nil, nil, env, "KJ_MIN_DIVERGENCE_THRESHOLD").to_s,
        template_profile: template_selection[:template_profile].to_s,
      }.compact
    end

    def kettle_config_bootstrap_recipe(bootstrap)
      recipe = recipe_entry(
        "kettle_config_bootstrap",
        ".kettle-jem.yml",
        "yaml",
        "supplied_kettle_config_bootstrap",
        facts: %w[kettle_config_bootstrap]
      )
      recipe[:template_preference] = bootstrap.fetch(:template_preference)
      recipe[:template_tokens] = {
        "KJ|MIN_DIVERGENCE_THRESHOLD" => bootstrap.fetch(:min_divergence_threshold).to_s,
      }
      recipe[:bootstrap_licenses] = Array(bootstrap[:licenses]).map(&:to_s).reject(&:empty?)
      recipe[:bootstrap_template_profile] = bootstrap[:template_profile].to_s unless bootstrap[:template_profile].to_s.empty?
      recipe[:bootstrap_gemspec_path] = bootstrap[:gemspec_path].to_s unless bootstrap[:gemspec_path].to_s.empty?
      recipe[:bootstrap_project_emoji] = bootstrap[:project_emoji].to_s unless bootstrap[:project_emoji].to_s.empty?
      recipe
    end

    def template_source_preference(project_root, template_root, entry, config, opencollective_disabled: false, include_patterns: nil, apply_templates: false)
      source_path, target_path = template_entry_paths(entry)
      return nil if source_path.to_s.empty? || target_path.to_s.empty?
      return nil if skip_packaged_workflow_template?(target_path, config, include_patterns: include_patterns)
      return nil if skip_packaged_license_template?(target_path, config)

      selected_source = preferred_template_source(template_root.fetch(:path), source_path, opencollective_disabled: opencollective_disabled)
      return nil unless selected_source

      strategy_config = template_strategy_config(config, target_path)
      preference = {
        target_path: target_path,
        configured_source: source_path,
        selected_source: template_source_display_path(template_root, selected_source),
        selection_reason: template_source_selection_reason(source_path, template_source_display_path(template_root, selected_source)),
        apply: template_entry_apply?(entry, apply_templates),
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

    def template_legacy_destination_cleanups(project_root, preferences)
      preferences.filter_map do |preference|
        canonical_path = preference.fetch(:target_path)
        legacy_path = LEGACY_DESTINATION_PATHS[canonical_path]
        next unless legacy_path
        next unless File.exist?(File.join(project_root, legacy_path))
        next if preference[:strategy] == "keep_destination" && !File.exist?(File.join(project_root, canonical_path))

        {
          canonical_path: canonical_path,
          legacy_path: legacy_path,
        }
      end
    end

    def template_obsolete_license_cleanups(project_root, config, preferences)
      active_basenames = active_license_basenames(config)
      return [] if active_basenames.empty?

      retained_paths = preferences.map { |preference| preference.fetch(:target_path) }.to_set
      known_license_template_basenames.filter_map do |basename|
        license_path = "#{basename}.md"
        next if active_basenames.include?(basename)
        next if retained_paths.include?(license_path)
        next unless File.exist?(File.join(project_root, license_path))

        { license_path: license_path, license_basename: basename }
      end
    end

    def template_strategy_config(config, target_path)
      template_file_strategy_config(config, target_path) || template_pattern_strategy_config(config, target_path)
    end

    def template_file_strategy_config(config, target_path)
      files = config["files"]
      return unless files.is_a?(Hash)

      current = files
      target_path.to_s.delete_prefix("./").split("/").each do |part|
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

      result = { strategy: strategy }
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
        return { kind: "project", path: local_root, display_prefix: "template" } if Dir.exist?(local_root)

        return { kind: "packaged", path: PACKAGED_TEMPLATE_ROOT }
      end

      return { kind: "packaged", path: PACKAGED_TEMPLATE_ROOT } if configured_root == "packaged"

      path = configured_root.start_with?("/") ? configured_root : File.join(project_root, configured_root)
      { kind: "project", path: path, display_prefix: configured_root }
    end

    def default_template_config
      {
        "root" => "packaged",
        "apply" => true,
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
      @known_license_template_basenames ||= Dir.glob(File.join(PACKAGED_TEMPLATE_ROOT, "*.md.example"))
        .map { |path| File.basename(path, ".md.example") }
        .reject { |basename| NON_LICENSE_MD_BASENAMES.include?(basename) }
        .to_set
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
      return true if OPT_IN_GITHUB_WORKFLOWS.include?(path) && !selected_template_path?(path, Array(include_patterns))

      basename = File.basename(path, ".yml")
      return github_actions_framework_matrix(config).empty? if basename == "framework-ci"

      engine = ENGINE_WORKFLOW_MAP[basename]
      return true if engine && !enabled_ruby_engines(config).include?(engine)

      version = basename[/\Aruby-(\d+\.\d+)\z/, 1]
      return false unless version

      min_ruby = config_min_ruby(config)
      return false unless min_ruby

      Gem::Version.new(version) < min_ruby
    end

    def enabled_ruby_engines(config)
      engines = ruby_engines_config(config)
      engines.nil? || engines.empty? ? DEFAULT_ENGINES : engines
    end

    def config_min_ruby(config)
      value = config.dig("rubygems", "min_ruby") || config["min_ruby"]
      version = value.to_s[/\d+\.\d+(?:\.\d+)?/]
      version && Gem::Version.new(version)
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

      normalized_versions = versions.map { |version| version.to_s.strip }.reject(&:empty?)
      return {} if normalized_versions.empty?

      {
        dimension: dimension,
        versions: normalized_versions,
        gemfile_pattern: pattern,
        include: normalized_versions.map do |version|
          gemfile = expand_framework_gemfile_pattern(pattern, version)
          { framework_version: version, gemfile: framework_gemfile_path(gemfile) }
        end,
      }
    end

    def github_actions_coverage_config(config)
      workflows = config["workflows"]
      return {} unless workflows.is_a?(Hash)

      raw = workflows["coverage"]
      enabled = raw == true || (raw.is_a?(Hash) && raw.fetch("enabled", false) == true)
      return {} unless enabled

      raw = {} unless raw.is_a?(Hash)
      {
        enabled: true,
        command: raw.fetch("command", "rake test").to_s,
        appraisal: raw.fetch("appraisal", "coverage").to_s,
      }
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
        ["Funding", funding_urls.join(", ")],
      ].reject { |(_, value)| value.to_s.empty? }

      [
        "<!-- kettle-jem:metadata:start -->",
        "| Field | Value |",
        "|---|---|",
        *rows.map { |field, value| "| #{field} | #{value} |" },
        "<!-- kettle-jem:metadata:end -->",
      ].join("\n")
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
      output = content.to_s.lines
      output = remove_top_level_yaml_key_lines(output, "open_collective") if facts.fetch(:funding, {})[:open_collective_disabled]
      tidelift_value = "rubygems/#{facts.fetch(:package).fetch(:name)}"
      if output.none? { |line| line.match?(/\A\s*tidelift\s*:/) }
        output << "\n" unless output.empty? || output.last.to_s.strip.empty?
        output << "tidelift: #{tidelift_value}\n"
      end
      ensure_trailing_newline(output.join)
    end

    def remove_top_level_yaml_key_lines(lines, key)
      result = []
      index = 0
      while index < lines.length
        line = lines[index]
        if line.match?(/\A#{Regexp.escape(key)}\s*:/)
          index += 1
          index += 1 while index < lines.length && lines[index].match?(/\A\s+/)
          next
        end
        result << line
        index += 1
      end
      result
    end

    def delete_rakefile_scaffold(content)
      selectors = rakefile_scaffold_delete_selectors(content)
      {
        content: delete_line_ranges(content.to_s, selectors),
        delete_selectors: selectors,
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
          end_line: call.location.end_line,
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
          end_line: call.location.end_line,
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
          end_line: call.location.end_line,
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
      cursor >= 0 ? cursor + 1 : nil
    end

    def rakefile_selector(selector_id, start_line, end_line, reason)
      {
        selector_id: selector_id,
        selector_family: "structural_owner_range",
        start_line: start_line,
        end_line: end_line,
        reason: reason,
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

    def synchronize_github_actions_ci(_content, facts)
      package = facts.fetch(:package)
      ci = facts.fetch(:ci)
      ruby_versions = ci.fetch(:ruby_versions)
      ruby_matrix = ruby_versions.map { |version| "          - \"#{version}\"" }.join("\n")

      <<~YAML
        name: CI

        permissions:
          contents: read

        on:
          push:
            branches:
              - "#{ci.fetch(:default_branch)}"
              - "*-stable"
            tags:
              - "!*" # Do not execute on tags
          pull_request:
            branches:
              - "*"
          workflow_dispatch:

        concurrency:
          group: "${{ github.workflow }}-${{ github.ref }}"
          cancel-in-progress: true

        jobs:
          test:
            if: "!contains(github.event.commits[0].message, '[ci skip]') && !contains(github.event.commits[0].message, '[skip ci]')"
            name: Specs ${{ matrix.ruby }}
            runs-on: ubuntu-latest
            continue-on-error: ${{ endsWith(matrix.ruby, 'head') }}
            strategy:
              fail-fast: false
              matrix:
                ruby:
        #{ruby_matrix}
                rubygems:
                  - default
                bundler:
                  - default

            steps:
              - name: Checkout #{package.fetch(:name)}
                uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

              - name: Setup Ruby & RubyGems
                uses: ruby/setup-ruby@e65c17d16e57e481586a6a5a0282698790062f92 # v1.300.0
                with:
                  ruby-version: "${{ matrix.ruby }}"
                  rubygems: "${{ matrix.rubygems }}"
                  bundler: "${{ matrix.bundler }}"
                  bundler-cache: true

              - name: Tests
                run: bundle exec rake
      YAML
    end

    def synchronize_github_actions_framework_ci(_content, facts)
      ci = facts.fetch(:ci)
      framework_matrix = ci.fetch(:framework_matrix)
      ruby_matrix = ci.fetch(:ruby_versions).map { |version| "          - \"#{version}\"" }.join("\n")
      include_matrix = framework_matrix.fetch(:include).map do |entry|
        [
          "          - framework_version: \"#{entry.fetch(:framework_version)}\"",
          "            gemfile: \"#{entry.fetch(:gemfile)}\"",
        ].join("\n")
      end.join("\n")
      dimension = framework_matrix.fetch(:dimension)
      label = dimension.split(/[-_]/).map { |part| part[0].to_s.upcase + part[1..].to_s }.join(" ")

      <<~YAML
        name: #{label} CI

        permissions:
          contents: read

        on:
          push:
            branches:
              - "#{ci.fetch(:default_branch)}"
              - "*-stable"
            tags:
              - "!*" # Do not execute on tags
          pull_request:
            branches:
              - "*"
          workflow_dispatch:

        concurrency:
          group: "${{ github.workflow }}-${{ github.ref }}"
          cancel-in-progress: true

        jobs:
          test:
            if: "!contains(github.event.commits[0].message, '[ci skip]') && !contains(github.event.commits[0].message, '[skip ci]')"
            name: Specs ${{ matrix.ruby }}@${{ matrix.framework_version }}
            runs-on: ubuntu-latest
            continue-on-error: ${{ endsWith(matrix.ruby, 'head') }}
            env:
              BUNDLE_GEMFILE: ${{ github.workspace }}/${{ matrix.gemfile }}
            strategy:
              fail-fast: false
              matrix:
                ruby:
        #{ruby_matrix}
                rubygems:
                  - default
                bundler:
                  - default
                include:
        #{include_matrix}

            steps:
              - name: Checkout
                uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

              - name: Setup Ruby & RubyGems
                uses: ruby/setup-ruby@e65c17d16e57e481586a6a5a0282698790062f92 # v1.300.0
                with:
                  ruby-version: "${{ matrix.ruby }}"
                  rubygems: "${{ matrix.rubygems }}"
                  bundler: "${{ matrix.bundler }}"
                  bundler-cache: true

              - name: Tests for ${{ matrix.ruby }}@${{ matrix.framework_version }}
                run: bundle exec rake test
      YAML
    end

    def synchronize_github_actions_coverage_ci(_content, facts)
      ci = facts.fetch(:ci)
      coverage = ci.fetch(:coverage)
      <<~YAML
        name: Test Coverage

        permissions:
          contents: read
          pull-requests: write
          id-token: write

        env:
          K_SOUP_COV_MIN_BRANCH: 100
          K_SOUP_COV_MIN_LINE: 100
          K_SOUP_COV_MIN_HARD: true
          K_SOUP_COV_FORMATTERS: "xml,rcov,lcov,tty"
          K_SOUP_COV_DO: true
          K_SOUP_COV_MULTI_FORMATTERS: true
          K_SOUP_COV_COMMAND_NAME: "Test Coverage"

        on:
          push:
            branches:
              - "#{ci.fetch(:default_branch)}"
              - "*-stable"
            tags:
              - "!*" # Do not execute on tags
          pull_request:
            branches:
              - "*"
          workflow_dispatch:

        concurrency:
          group: "${{ github.workflow }}-${{ github.ref }}"
          cancel-in-progress: true

        jobs:
          coverage:
            if: "!contains(github.event.commits[0].message, '[ci skip]') && !contains(github.event.commits[0].message, '[skip ci]')"
            name: Code Coverage on ${{ matrix.ruby }}@current
            runs-on: ubuntu-latest
            continue-on-error: ${{ matrix.experimental || endsWith(matrix.ruby, 'head') }}
            env:
              BUNDLE_GEMFILE: ${{ github.workspace }}/${{ matrix.gemfile }}.gemfile
            strategy:
              fail-fast: false
              matrix:
                include:
                  - ruby: "ruby"
                    appraisal: "#{coverage.fetch(:appraisal)}"
                    exec_cmd: "#{coverage.fetch(:command)}"
                    gemfile: "Appraisal.root"
                    rubygems: latest
                    bundler: latest

            steps:
              - name: Checkout
                uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

              - name: Setup Ruby & RubyGems
                uses: ruby/setup-ruby@e65c17d16e57e481586a6a5a0282698790062f92 # v1.300.0
                with:
                  ruby-version: "${{ matrix.ruby }}"
                  rubygems: "${{ matrix.rubygems }}"
                  bundler: "${{ matrix.bundler }}"
                  bundler-cache: true

              - name: "[Attempt 1] Appraisal for ${{ matrix.ruby }}@${{ matrix.appraisal }}"
                id: bundleAppraisalAttempt1
                run: bundle exec appraisal ${{ matrix.appraisal }} install
                continue-on-error: true

              - name: "[Attempt 2] Appraisal for ${{ matrix.ruby }}@${{ matrix.appraisal }}"
                id: bundleAppraisalAttempt2
                if: ${{ steps.bundleAppraisalAttempt1.outcome == 'failure' }}
                run: bundle exec appraisal ${{ matrix.appraisal }} install

              - name: Tests for ${{ matrix.ruby }}@current via ${{ matrix.exec_cmd }}
                run: bundle exec appraisal ${{ matrix.appraisal }} bundle exec ${{ matrix.exec_cmd }}
        #{github_actions_coverage_steps}
      YAML
    end

    def synchronize_github_actions_workflow_snippets(content)
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
      updated = append_github_actions_coverage_steps(updated) if github_actions_coverage_enabled?(updated)
      update_github_actions_pins(updated)
    end

    def github_actions_coverage_enabled?(content)
      content.match?(/K_SOUP_COV_DO:\s*["']?true["']?/)
    end

    def append_github_actions_coverage_steps(content)
      return content if content.include?("Upload coverage to Coveralls") || content.include?("Upload coverage to CodeCov")

      lines = content.lines
      steps_index = lines.index { |line| line.match?(/^    steps:\s*$/) }
      return content unless steps_index

      insert_index = lines.length
      ((steps_index + 1)...lines.length).each do |index|
        line = lines[index]
        next if line.strip.empty?
        next unless line.match?(/^\S|^  \S|^    \S/) && !line.match?(/^      /)

        insert_index = index
        break
      end
      lines.insert(insert_index, github_actions_coverage_steps)
      lines.join
    end

    def github_actions_coverage_steps
      <<~YAML.lines.map { |line| line.strip.empty? ? line : "      #{line}" }.join
        - name: Upload coverage to Coveralls
          if: ${{ !env.ACT }}
          uses: coverallsapp/github-action@0a51d2e0b5417d06e4ecceb534aec87defc53926 # main
          with:
            github-token: ${{ secrets.GITHUB_TOKEN }}
          continue-on-error: ${{ matrix.experimental != 'false' }}

        - name: Upload coverage to QLTY
          if: ${{ !env.ACT }}
          uses: qltysh/qlty-action/coverage@a19242102d17e497f437d7466aa01b528537e899 # v2.2.0
          with:
            token: ${{secrets.QLTY_COVERAGE_TOKEN}}
            files: coverage/.resultset.json
          continue-on-error: ${{ matrix.experimental != 'false' }}

        - name: Upload coverage to CodeCov
          if: ${{ !env.ACT }}
          uses: codecov/codecov-action@57e3a136b779b570ffcdbf80b3bdc90e7fab3de2 # v6.0.0
          with:
            use_oidc: true
            fail_ci_if_error: false
            files: coverage/lcov.info,coverage/coverage.xml
            verbose: true

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
            thresholds: '100 100'
          continue-on-error: ${{ matrix.experimental != 'false' }}

        - name: Add Coverage PR Comment
          uses: marocchino/sticky-pull-request-comment@0ea0beb66eb9baf113663a64ec522f60e49231c0 # v3.0.4
          if: ${{ !env.ACT && github.event_name == 'pull_request' }}
          with:
            recreate: true
            path: code-coverage-results.md
          continue-on-error: ${{ matrix.experimental != 'false' }}
      YAML
    end

    def ensure_workflow_top_level_section(content, key, section, before:)
      return content if content.match?(/^#{Regexp.escape(key)}:/)

      lines = content.lines
      index = lines.index { |line| line.match?(/^#{Regexp.escape(before)}:/) }
      if index
        prepared_section = index.zero? || lines[index - 1].strip.empty? ? section : "\n#{section}"
        lines.insert(index, prepared_section)
      else
        lines << "\n" unless lines.empty? || lines.last == "\n"
        lines << section
      end
      lines.join
    end

    def update_github_actions_pins(content)
      github_actions_step_pins.reduce(content) do |updated, (action_prefix, pinned_value)|
        updated.gsub(/^(\s*(?:-\s*)?uses:\s*)#{Regexp.escape(action_prefix)}@\S+(?:\s+#.*)?$/) do
          "#{$1}#{pinned_value}"
        end
      end
    end

    def github_actions_step_pins
      {
        "actions/checkout" => "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2",
        "ruby/setup-ruby" => "ruby/setup-ruby@e65c17d16e57e481586a6a5a0282698790062f92 # v1.300.0",
        "coverallsapp/github-action" => "coverallsapp/github-action@0a51d2e0b5417d06e4ecceb534aec87defc53926 # main",
        "qltysh/qlty-action/coverage" => "qltysh/qlty-action/coverage@a19242102d17e497f437d7466aa01b528537e899 # v2.2.0",
        "codecov/codecov-action" => "codecov/codecov-action@57e3a136b779b570ffcdbf80b3bdc90e7fab3de2 # v6.0.0",
        "irongut/CodeCoverageSummary" => "irongut/CodeCoverageSummary@51cc3a756ddcd398d447c044c02cb6aa83fdae95 # v1.3.0",
        "marocchino/sticky-pull-request-comment" => "marocchino/sticky-pull-request-comment@0ea0beb66eb9baf113663a64ec522f60e49231c0 # v3.0.4",
      }
    end

    def replace_markdown_managed_block(content, marker, replacement)
      open = "<!-- #{marker}:start -->"
      close = "<!-- #{marker}:end -->"
      replace_markdown_managed_block_with_crispr(content, open, close, replacement) do
        ensure_trailing_newline([content.rstrip, "", replacement.to_s.rstrip].join("\n"))
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
      prepared_replacement = ensure_trailing_newline(replacement.to_s)
      actor = Ast::Crispr::Replace.call(
        content: content.to_s,
        target: Ast::Crispr::Markdown::Markly::Selectors.html_comment_block(
          start_text: open_marker.delete_prefix("<!-- ").delete_suffix(" -->"),
          end_text: close_marker.delete_prefix("<!-- ").delete_suffix(" -->"),
          span: :outermost,
          include_trailing_gap: true,
          limit: {none_or_one: true},
        ),
        replacement: prepared_replacement,
        source_label: "managed markdown block",
      )
      return actor.updated_content if actor.match_count.positive?

      yield
    end

    def replace_text_managed_block_with_crispr(content, open_marker, close_marker, replacement)
      prepared_replacement = ensure_trailing_newline(replacement.to_s)
      actor = Ast::Crispr::Replace.call(
        content: content.to_s,
        target: Ast::Crispr::Selectors.line_block(
          start_line_text: open_marker,
          end_line_text: close_marker,
          include_trailing_gap: true,
          limit: {none_or_one: true},
        ),
        replacement: prepared_replacement,
        source_label: "managed text block",
      )
      return actor.updated_content if actor.match_count.positive?

      yield
    end

    def replace_ruby_managed_block_with_crispr(content, open_marker, close_marker, replacement)
      prepared_replacement = ensure_trailing_newline(replacement.to_s)
      actor = Ast::Crispr::Replace.call(
        content: content.to_s,
        target: Ast::Crispr::Ruby::Prism::Selectors.comment_line_block(
          start_text: open_marker,
          end_text: close_marker,
          span: :outermost,
          include_trailing_gap: true,
          limit: {none_or_one: true},
        ),
        replacement: prepared_replacement,
        source_label: "managed Ruby block",
      )
      return actor.updated_content if actor.match_count.positive?

      yield
    end

    def ensure_trailing_newline(text)
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

if File.basename($PROGRAM_NAME).match?(/\Arake(?:\z|\.)/) || defined?(Rake.application)
  Kettle::Jem.install_tasks
end

Kettle::Jem::Version.class_eval do
  extend VersionGem::Basic
end
