# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "rubygems"

module Kettle
  module Jem
    module MaintenanceChangelog
      TEMPLATE_CHANGELOG_INTERNAL_PATHS = %w[
        CHANGELOG.md
        .structuredmerge/kettle-jem.lock
        .kettle-jem.lock
      ].freeze
      TEMPLATE_CHANGE_CATEGORIES = {
        workflows: ->(path) { path.start_with?(".github/workflows/") },
        dependencies: ->(path) {
          path == "Gemfile" || path == "Appraisals" || path.end_with?(".gemspec", ".gemfile", ".gemfile.lock") ||
            path.start_with?("gemfiles/")
        },
        documentation: ->(path) { %w[README.md CONTRIBUTING.md SECURITY.md].include?(path) || path.start_with?("docs/") },
        configuration: ->(path) { path.start_with?(".structuredmerge/") || path == "mise.toml" || path == ".gitignore" },
        code_and_tests: ->(path) { path.start_with?("lib/", "spec/", "test/", "bin/") || path == "Rakefile" }
      }.freeze
      BUNDLER_ENVIRONMENT = %w[
        BUNDLE_BIN_PATH
        BUNDLE_FROZEN
        BUNDLE_GEMFILE
        BUNDLE_LOCKFILE
        BUNDLER_SETUP
        BUNDLER_VERSION
        RUBYLIB
        RUBYOPT
      ].freeze

      module_function

      def add_unreleased_entry(project_root:, section:, entry:)
        command = [
          RbConfig.ruby,
          "-rrubygems",
          "-e",
          'exec Gem.ruby, Gem.bin_path("kettle-changelog", "kettle-changelog"), *ARGV',
          "--",
          "--add-unreleased-entry",
          "--json",
          "--section",
          section.to_s,
          "--entry",
          entry.to_s
        ]
        environment = BUNDLER_ENVIRONMENT.to_h { |key| [key, nil] }
        stdout, stderr, status = Open3.capture3(environment, *command, chdir: project_root)
        unless status.success?
          detail = [stdout, stderr].reject(&:empty?).join("\n")
          raise "kettle-changelog failed (exit #{status.exitstatus}): #{detail}"
        end

        result = JSON.parse(stdout)
        {
          status: result.fetch("changed") ? "updated" : "unchanged",
          section: result.fetch("section"),
          entry: result.fetch("entry")
        }
      rescue JSON::ParserError => error
        raise "kettle-changelog returned invalid JSON: #{error.message}"
      rescue Gem::Exception => error
        raise "kettle-changelog executable is not installed: #{error.message}"
      end

      def record_template_run(project_root:, report:, run_options: {}, label: "Apply kettle-jem templates")
        report = report.to_h
        if template_changelog_disabled?(run_options) || bootstrap_only_report?(report)
          return report.merge(changelog: {status: "skipped", reason: template_changelog_disabled?(run_options) ? "disabled" : "bootstrap_only"})
        end

        changed_files = template_changed_files(report.fetch(:changed_files, []))
        if changed_files.empty?
          return report.merge(changelog: {status: "skipped", reason: "no_template_changes", changed_files: []})
        end

        entry = template_run_entry(label, changed_files)
        result = add_unreleased_entry(project_root: project_root, section: "Changed", entry: entry)
        changelog = result.merge(changed_files: changed_files, entry: entry)
        changed_files_with_changelog = if result.fetch(:status) == "updated"
          (Array(report.fetch(:changed_files, [])) + ["CHANGELOG.md"]).uniq.sort
        else
          Array(report.fetch(:changed_files, [])).uniq.sort
        end
        report.merge(changelog: changelog, changed_files: changed_files_with_changelog)
      end

      def template_changed_files(changed_files)
        Array(changed_files).map(&:to_s).uniq.sort.reject do |path|
          TEMPLATE_CHANGELOG_INTERNAL_PATHS.include?(path)
        end
      end

      def template_run_entry(label, changed_files)
        counts = changed_files.group_by { |path| template_change_category(path) }
          .sort_by { |category, _paths| category.to_s }
          .map { |category, paths| "#{category.to_s.tr("_", " ")} (#{paths.length})" }
        areas = counts.empty? ? "project files" : counts.join(", ")
        "#{label}: updated #{changed_files.length} project file#{"s" unless changed_files.length == 1} across #{areas}."
      end

      def template_change_category(path)
        TEMPLATE_CHANGE_CATEGORIES.each do |category, matcher|
          return category if matcher.call(path)
        end
        :other
      end

      def template_changelog_disabled?(run_options)
        options = run_options.to_h
        DecisionPolicy.value_to_boolean(options[:skip_changelog] || options["skip_changelog"])
      end

      def bootstrap_only_report?(report)
        report.fetch(:setup_status, "").to_s.start_with?("bootstrap_")
      end
    end
  end
end
