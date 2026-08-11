# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "rubygems"

module Kettle
  module Jem
    module MaintenanceChangelog
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
    end
  end
end
