# frozen_string_literal: true

require "tmpdir"

module Kettle
  module Jem
    module Tasks
      module SelfTestTask
        SKIPPED_PREFIXES = %w[
          examples/
          exe/
          lib/
          sig/
          spec/
          template/
        ].freeze
        SKIPPED_FILES = %w[
          .kettle-jem.yml
          .rubocop_gradual.lock
          Gemfile.lock
        ].freeze
        GENERATED_RUNTIME_PREFIXES = %w[
          tmp/kettle-jem/templating-report-
        ].freeze
        SELFTEST_IGNORED_FILES = %w[
          gemfiles/modular/shunted.gemfile
          results/test_results.html
          tmp/.gitignore
        ].freeze

        module_function

        def run(project_root: Dir.pwd, destination_root: project_root, template_root: nil, output_root: nil, min_divergence_threshold: nil)
          root = File.expand_path(destination_root)
          base_dir = output_root || File.join(root, "tmp", "template_test")
          before_dir = File.join(base_dir, "destination")
          after_dir = File.join(base_dir, "output")
          report_dir = File.join(base_dir, "report")
          diffs_dir = File.join(report_dir, "diffs")

          FileUtils.rm_rf(base_dir)
          [before_dir, after_dir, report_dir, diffs_dir].each { |path| FileUtils.mkdir_p(path) }
          copy_tree(root, before_dir)
          copy_tree(root, after_dir)

          before = Kettle::Jem::SelfTest::Manifest.generate(before_dir)
          File.write(File.join(report_dir, "before.json"), "#{JSON.pretty_generate(before)}\n")

          write_template_root_override(after_dir, template_root) if template_root
          Kettle::Jem.apply_project(after_dir, env: ENV, run_options: {accept: true, force: true, skip_commit: true})

          after = Kettle::Jem::SelfTest::Manifest.generate(after_dir)
          File.write(File.join(report_dir, "after.json"), "#{JSON.pretty_generate(after)}\n")

          comparison = classify_comparison(Kettle::Jem::SelfTest::Manifest.compare(before, after))
          diff_count = write_diffs(comparison, before_dir: before_dir, after_dir: after_dir, diffs_dir: diffs_dir)
          drift = drift_report(after_dir: after_dir, template_root: template_root || Kettle::Jem.template_root_path(after_dir))
          summary = Kettle::Jem::SelfTest::Reporter.summary(
            comparison,
            output_dir: after_dir,
            templating_environment: Kettle::Jem::TemplatingReport.snapshot,
            diff_count: diff_count,
          )
          summary = append_drift_summary(summary, drift)
          summary_path = File.join(report_dir, "summary.md")
          File.write(summary_path, summary)
          score, divergence = score_and_divergence(comparison)
          threshold = selftest_threshold(min_divergence_threshold, root)

          result = {
            mode: "selftest",
            destination_root: root,
            template_root: template_root || Kettle::Jem.template_root_path(root),
            output_root: after_dir,
            report_path: summary_path,
            comparison: comparison,
            score: score,
            divergence: divergence,
            min_divergence_threshold: threshold,
            drift: drift,
          }
          if threshold && divergence > threshold
            raise Kettle::Jem::Error, "selftest divergence #{divergence}% exceeds threshold #{threshold}%"
          end
          result
        end

        def copy_tree(source, destination)
          Find.find(source) do |path|
            relative = path.sub(%r{\A#{Regexp.escape(source)}/?}, "")
            next if relative.empty?
            next Find.prune if ignored_tree_entry?(relative, path)

            target = File.join(destination, relative)
            if File.directory?(path)
              FileUtils.mkdir_p(target)
            else
              FileUtils.mkdir_p(File.dirname(target))
              FileUtils.cp(path, target)
            end
          end
        end

        def ignored_tree_entry?(relative, path)
          return false unless File.directory?(path)

          %w[.git .yardoc coverage docs node_modules pkg tmp].include?(relative.split("/").first)
        end

        def write_diffs(comparison, before_dir:, after_dir:, diffs_dir:)
          count = 0
          comparison.fetch(:changed, []).each do |relative|
            diff = Kettle::Jem::SelfTest::Reporter.diff(
              File.join(before_dir, relative),
              File.join(after_dir, relative),
            )
            next if diff.empty?

            diff_path = File.join(diffs_dir, "#{relative}.diff")
            FileUtils.mkdir_p(File.dirname(diff_path))
            File.write(diff_path, diff)
            count += 1
          end
          count
        end

        def classify_comparison(comparison)
          changed = comparison.fetch(:changed, []).reject { |relative| ignored_selftest_artifact?(relative) }
          added = comparison.fetch(:added, []).reject { |relative| ignored_selftest_artifact?(relative) }
          skipped, removed = comparison.fetch(:removed, []).partition do |relative|
            ignored_selftest_artifact?(relative) || expected_non_templated_path?(relative)
          end
          comparison.merge(changed: changed, added: added, removed: removed, skipped: skipped)
        end

        def expected_non_templated_path?(relative_path)
          path_parts = relative_path.to_s.split("/")
          SKIPPED_FILES.include?(relative_path) ||
            SKIPPED_PREFIXES.any? { |prefix| relative_path.start_with?(prefix) } ||
            (path_parts.length == 2 && path_parts.first == "gemfiles" && path_parts.last.end_with?(".gemfile")) ||
            relative_path.to_s.end_with?(".gemspec")
        end

        def ignored_selftest_artifact?(relative_path)
          generated_runtime_artifact?(relative_path) || SELFTEST_IGNORED_FILES.include?(relative_path)
        end

        def generated_runtime_artifact?(relative_path)
          GENERATED_RUNTIME_PREFIXES.any? { |prefix| relative_path.start_with?(prefix.to_s) }
        end

        def score_and_divergence(comparison)
          total = comparison.fetch(:matched, []).size +
            comparison.fetch(:changed, []).size +
            comparison.fetch(:added, []).size +
            comparison.fetch(:removed, []).size
          score = total.zero? ? 0.0 : (comparison.fetch(:matched, []).size.to_f / total * 100).round(1)
          [score, (100.0 - score).round(1)]
        end

        def selftest_threshold(explicit, root)
          return explicit.to_f if explicit

          env_threshold = ENV["KJ_MIN_DIVERGENCE_THRESHOLD"].to_s.strip
          return env_threshold.to_f unless env_threshold.empty?

          config_path = File.join(root, ".kettle-jem.yml")
          return unless File.file?(config_path)

          config = YAML.load_file(config_path)
          value = config["min_divergence_threshold"] if config.is_a?(Hash)
          return if value.nil? || value.to_s.strip.empty?

          Float(value)
        rescue ArgumentError, TypeError
          raise Kettle::Jem::Error, "Invalid selftest min_divergence_threshold"
        end

        def write_template_root_override(root, template_root)
          config_path = File.join(root, ".kettle-jem.yml")
          content = File.file?(config_path) ? File.read(config_path) : ""
          File.write(config_path, upsert_template_root_override(content, File.expand_path(template_root)))
        end

        def upsert_template_root_override(content, template_root)
          # This is line-oriented instead of YAML round-tripping because the self-test fixture config must preserve
          # comments, key order, and scalar spellings while injecting a temporary local template root.
          lines = content.to_s.lines
          template_index = lines.index { |line| line.match?(/\Atemplates:\s*(?:#.*)?\n?\z/) }
          if template_index
            root_index = ((template_index + 1)...lines.length).find do |index|
              line = lines[index]
              break nil unless line.strip.empty? || line.start_with?(" ")

              line.match?(/\A\s+root\s*:/)
            end
            if root_index
              lines[root_index] = "  root: #{template_root}\n"
            else
              lines.insert(template_index + 1, "  root: #{template_root}\n")
            end
          else
            lines << "\n" unless lines.empty? || lines.last.to_s.strip.empty?
            lines << "templates:\n"
            lines << "  root: #{template_root}\n"
          end
          output = lines.join
          output.end_with?("\n") ? output : "#{output}\n"
        end

        def drift_report(after_dir:, template_root:)
          begin
            require "kettle/drift"
          rescue LoadError
            return {
              available: false,
              reason: "kettle-drift is not available",
            }
          end

          outcome = Kettle::Drift.run(
            project_root: after_dir,
            template_dir: template_root,
            lock_path: File.join("tmp", "template_test", ".kettle-drift.lock"),
            mode: :force_update,
            printer_class: nil,
          )
          {
            available: true,
            warning_count: outcome.warning_count,
            json_path: outcome.json_path,
            lock_path: outcome.lock_path,
            exit_code: outcome.exit_code,
          }
        rescue StandardError => error
          {
            available: false,
            reason: "#{error.class}: #{error.message}",
          }
        end

        def append_drift_summary(summary, drift)
          return summary unless drift

          lines = [summary, "", "## Drift Analysis", ""]
          if drift[:available]
            lines << "**Duplicate drift warnings**: #{drift.fetch(:warning_count)}"
            lines << "**Drift report**: `#{drift[:json_path]}`" if drift[:json_path]
          else
            lines << "Drift analysis unavailable: #{drift[:reason]}"
          end
          lines << ""
          lines.join("\n")
        end
      end
    end
  end
end
