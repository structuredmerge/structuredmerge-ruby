# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "securerandom"

module Kettle
  module Jem
    # Updates the GitHub Actions SHA pin index used by kettle-jem workflow templates.
    class WorkflowPinsCLI
      VALID_UPGRADE_LEVELS = %w[major minor patch].freeze
      DEFAULT_UPGRADE_LEVEL = "patch"

      def initialize(project_root:, env: ENV, options: {})
        @project_root = File.expand_path(project_root)
        @env = env
        @options = {
          write: false,
          check: false,
          upgrade: DEFAULT_UPGRADE_LEVEL
        }.merge(options.transform_keys(&:to_sym))
      end

      def run
        upgrade = @options.fetch(:upgrade, DEFAULT_UPGRADE_LEVEL).to_s
        unless VALID_UPGRADE_LEVELS.include?(upgrade)
          raise ArgumentError, "Invalid --upgrade value #{upgrade.inspect}; use one of: #{VALID_UPGRADE_LEVELS.join(", ")}"
        end

        pins = Kettle::Jem.github_actions_step_pins
        raise ArgumentError, "No GitHub Actions pins found in kettle-jem" if pins.empty?

        validate_template_pin_coverage!(pins)
        report = resolve_updates(pins, upgrade)
        replacements = replacement_map(report.fetch("planned_changes", []), pins)
        apply_replacements(replacements) if @options[:write] && replacements.any?

        if @options[:check] && replacements.any?
          raise "GitHub Actions pins are stale; run kettle-jem workflow-pins --write --upgrade #{upgrade}"
        end

        {
          mode: @options[:write] ? "write" : "dry-run",
          check: !!@options[:check],
          upgrade: upgrade,
          pin_count: pins.length,
          updates: replacements.length,
          updated_actions: replacements.keys.sort,
          planned_changes: report.fetch("planned_changes", []),
          outdated_pins: report.fetch("outdated_pins", [])
        }
      end

      private

      def template_workflow_dir
        File.join(@project_root, "lib", "kettle", "jem", "templates", ".github", "workflows")
      end

      def source_paths
        [
          File.join(@project_root, "lib", "kettle", "jem.rb"),
          *Dir.glob(File.join(template_workflow_dir, "*.yml.example")).sort
        ]
      end

      def validate_template_pin_coverage!(pins)
        source_pin_actions = source_paths.flat_map do |path|
          File.read(path).scan(/uses:\s*([^@\s]+)@[0-9a-f]{40}\s*#\s*\S+/).flatten
        end.uniq
        missing = source_pin_actions - pins.keys
        return if missing.empty?

        raise ArgumentError, "Pinned workflow actions missing from github_actions_step_pins: #{missing.sort.join(", ")}"
      end

      def resolve_updates(pins, upgrade)
        temp_root = File.join(@project_root, "tmp", "kettle-jem-workflow-pins-#{Process.pid}-#{SecureRandom.hex(4)}")
        workflow_dir = File.join(temp_root, ".github", "workflows")
        FileUtils.mkdir_p(workflow_dir)
        File.write(File.join(workflow_dir, "action-pin-index.yml"), synthetic_workflow(pins))

        command = [
          "kettle-gha-sha-pins",
          "--root", workflow_dir,
          "--upgrade", upgrade,
          "--json",
          "--no-progress"
        ]
        stdout, stderr, status = Open3.capture3(@env.to_hash, *command, chdir: @project_root)
        unless status.success? || status.exitstatus == 3
          raise "kettle-gha-sha-pins failed with exit #{status.exitstatus}: #{stderr}"
        end

        JSON.parse(stdout)
      ensure
        FileUtils.rm_rf(temp_root) if temp_root && File.directory?(temp_root)
      end

      def synthetic_workflow(pins)
        steps = pins.sort.map.with_index do |(action, pin), index|
          <<~YAML
            - name: #{action}
              id: action_#{index}
              uses: #{pin}
          YAML
        end.join

        <<~YAML
          name: kettle-jem action pin index
          on: workflow_dispatch
          jobs:
            pins:
              runs-on: ubuntu-latest
              steps:
          #{steps}
        YAML
      end

      def replacement_map(planned_changes, pins)
        planned_changes.each_with_object({}) do |change, replacements|
          action = change.fetch("action")
          next unless pins.key?(action)

          new_ref = change.fetch("new_ref").to_s
          new_version = change["new_version"].to_s
          next if new_ref.empty?

          desired = "#{action}@#{new_ref}"
          desired += " # v#{new_version}" unless new_version.empty?
          replacements[action] = [pins.fetch(action), desired]
        end
      end

      def apply_replacements(replacements)
        source_paths.each do |path|
          original = File.read(path)
          updated = replacements.values.reduce(original) do |content, (old_pin, new_pin)|
            content.gsub(old_pin, new_pin)
          end
          File.write(path, updated) if updated != original
        end
      end
    end
  end
end
