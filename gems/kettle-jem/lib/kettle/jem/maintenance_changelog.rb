# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "rubygems"

module Kettle
  module Jem
    module MaintenanceChangelog
      module_function

      def add_unreleased_entry(project_root:, section:, entry:)
        command = [RbConfig.ruby, Gem.bin_path("kettle-changelog", "kettle-changelog"), "--add-unreleased-entry", "--json", "--section", section.to_s, "--entry", entry.to_s]
        stdout, stderr, status = Open3.capture3(*command, chdir: project_root)
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
