# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "yaml"

module Kettle
  module Jem
    module Tasks
      module InstallTask
        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: {}, command_runner: method(:run_system_command))
          report = Kettle::Jem.apply_project(project_root, env: env, run_options: run_options)
          install_steps = []
          install_steps << gemspec_dependency_sync_step(report)
          version_step = version_gem_bootstrap_step(project_root, report)
          install_steps << version_step if version_step
          mise_step = mise_trust_step(project_root, report, env: env)
          install_steps << mise_step if mise_step
          install_steps.concat(post_template_project_fix_steps(project_root, report, env: env))
          install_steps << ensure_bin_setup_executable(project_root)
          setup_env = setup_command_env(project_root, env)
          install_steps.concat(run_bundle_setup_commands(project_root, env: setup_env, run_options: run_options, command_runner: command_runner))
          install_steps << bundled_handoff_step(project_root: project_root, env: env, run_options: run_options)
          install_steps << bootstrap_commit_step(project_root, run_options: run_options)
          install_steps = execute_orchestration_steps(install_steps, project_root: project_root, env: setup_env, run_options: run_options, command_runner: command_runner)

          report.merge(
            mode: "install",
            installed: true,
            install_steps: install_steps,
            install_phase_reports: install_phase_reports(install_steps),
            install_summary: install_step_summary(install_steps),
            diagnostics: report.fetch(:diagnostics) + [{
              severity: "advisory",
              message: "kettle:jem:install applied templates, completed local post-template checks, and executed available orchestration steps.",
            }]
          )
        end

        def gemspec_dependency_sync_step(report)
          gemspec_report = report.fetch(:recipe_reports, []).find do |recipe_report|
            recipe_report.fetch(:relative_path, "").end_with?(".gemspec")
          end
          return {
            name: "gemspec_dependency_sync",
            status: "unavailable",
            reason: "no_gemspec_recipe",
          } unless gemspec_report

          {
            name: "gemspec_dependency_sync",
            path: gemspec_report.fetch(:relative_path),
            status: gemspec_report.fetch(:changed, false) ? "applied" : "already_current",
            development_dependencies: development_dependency_names(gemspec_report.fetch(:final_content, "")),
          }
        end

        def development_dependency_names(content)
          Kettle::Jem.extract_gemspec_development_dependencies(content).map { |dependency| dependency.fetch(:name) }.uniq
        end

        def version_gem_bootstrap_step(project_root, report)
          report.fetch(:post_apply_steps, []).find { |step| step.fetch(:name, nil) == "version_gem_bootstrap" } ||
            Kettle::Jem.template_version_gem_bootstrap_step(project_root, report)
        end

        def install_phase_reports(install_steps)
          phases = {
            "template_apply" => %w[gemspec_dependency_sync],
            "post_template" => %w[
              version_gem_bootstrap
              mise_trust
              legacy_ruby_version_file_cleanup
              readme_compatibility_badges
              readme_gemspec_grapheme_sync
              gemspec_homepage_literal
              env_local_gitignore
              bin_setup_executable
              bin_setup
              bundle_binstubs
              bundle_binstub_location_validation
            ],
            "orchestration" => %w[bundled_handoff bootstrap_commit],
          }
          phases.map do |phase, names|
            steps = install_steps.select { |step| names.include?(step.fetch(:name).to_s) }
            {
              phase: phase,
              steps: steps.map { |step| step.fetch(:name) },
              statuses: steps.to_h { |step| [step.fetch(:name), step.fetch(:status)] },
            }
          end
        end

        def install_step_summary(install_steps)
          statuses = install_steps.each_with_object(Hash.new(0)) do |step, counts|
            counts[step.fetch(:status, "unknown").to_s] += 1
          end.sort.to_h
          {
            steps: install_steps.length,
            statuses: statuses,
            summary: "install steps #{install_steps.length}; #{statuses.map { |status, count| "#{status} #{count}" }.join("; ")}",
          }
        end

        def ensure_bin_setup_executable(project_root)
          path = File.join(project_root, "bin", "setup")
          return {name: "bin_setup_executable", path: "bin/setup", status: "missing"} unless File.exist?(path)

          before = File.stat(path).mode
          FileUtils.chmod(before | 0o111, path)
          after = File.stat(path).mode
          {
            name: "bin_setup_executable",
            path: "bin/setup",
            status: (before == after ? "already_executable" : "updated"),
          }
        end

        def mise_trust_step(project_root, report, env:)
          mise_report = report.fetch(:recipe_reports, []).find do |recipe_report|
            recipe_report.fetch(:relative_path, "") == "mise.toml"
          end
          return nil unless mise_report&.fetch(:changed, false)

          command = ["mise", "trust", "-C", project_root.to_s]
          return {
            name: "mise_trust",
            path: "mise.toml",
            command: command,
            status: "ready",
            reason: "mise_toml_changed",
          } if mise_installed?(env)

          {
            name: "mise_trust",
            path: "mise.toml",
            command: command,
            status: "unavailable",
            reason: "mise_not_installed",
            install_url: "https://mise.jdx.dev/getting-started.html",
          }
        end

        def mise_installed?(env)
          path = (env || {})["PATH"].to_s
          path = ENV["PATH"].to_s if path.empty?
          path.split(File::PATH_SEPARATOR).any? do |dir|
            candidate = File.join(dir, "mise")
            File.file?(candidate) && File.executable?(candidate)
          end
        end

        def post_template_project_fix_steps(project_root, report, env:)
          [
            cleanup_legacy_ruby_version_files(project_root),
            trim_readme_compatibility_badges(project_root, report),
            sync_readme_gemspec_grapheme(project_root, env),
            repair_gemspec_homepage(project_root, env),
            ensure_env_local_gitignore(project_root),
          ].compact
        end

        def cleanup_legacy_ruby_version_files(project_root)
          return nil unless File.file?(File.join(project_root.to_s, "mise.toml"))

          removed = %w[.ruby-version .ruby-gemset .tool-versions].filter_map do |relative_path|
            path = File.join(project_root.to_s, relative_path)
            next unless File.exist?(path)

            FileUtils.rm_f(path)
            relative_path
          end
          {
            name: "legacy_ruby_version_file_cleanup",
            status: removed.empty? ? "already_current" : "applied",
            removed_files: removed,
          }
        end

        def trim_readme_compatibility_badges(project_root, report)
          readme_path = File.join(project_root.to_s, "README.md")
          return nil unless File.file?(readme_path)

          min_ruby = report.dig(:facts, :rubygems, :min_ruby)
          return {
            name: "readme_compatibility_badges",
            status: "skipped",
            reason: "missing_min_ruby",
          } if min_ruby.to_s.empty?

          before = File.read(readme_path)
          after = Kettle::Jem::ReadmePostProcessor.process(
            content: before,
            min_ruby: Gem::Version.new(Kettle::Jem.minimum_ruby_token(min_ruby)),
            engines: report.dig(:facts, :rubygems, :engines),
            workflow_paths: github_workflow_paths(project_root)
          )
          File.write(readme_path, after) if after != before
          {
            name: "readme_compatibility_badges",
            path: "README.md",
            status: after == before ? "already_current" : "applied",
          }
        rescue StandardError => error
          {
            name: "readme_compatibility_badges",
            path: "README.md",
            status: "skipped",
            reason: error.message,
          }
        end

        def github_workflow_paths(project_root)
          workflow_root = File.join(project_root.to_s, ".github", "workflows")
          return [] unless Dir.exist?(workflow_root)

          Dir.glob(File.join(workflow_root, "*.{yml,yaml}")).map do |path|
            Pathname(path).relative_path_from(Pathname(project_root.to_s)).to_s
          end.sort
        end

        def sync_readme_gemspec_grapheme(project_root, env)
          readme_path = File.join(project_root.to_s, "README.md")
          gemspec_path = Dir.glob(File.join(project_root.to_s, "*.gemspec")).sort.first
          return nil unless File.file?(readme_path) && gemspec_path

          readme = File.read(readme_path)
          gemspec = File.read(gemspec_path)
          grapheme = configured_project_grapheme(project_root, env) || readme_h1_grapheme(readme)
          return {
            name: "readme_gemspec_grapheme_sync",
            status: "skipped",
            reason: "missing_grapheme",
          } if grapheme.to_s.empty?

          updated_readme = normalize_readme_h1_grapheme(readme, grapheme)
          updated_gemspec = normalize_gemspec_grapheme(gemspec, grapheme)
          File.write(readme_path, updated_readme) if updated_readme != readme
          File.write(gemspec_path, updated_gemspec) if updated_gemspec != gemspec
          {
            name: "readme_gemspec_grapheme_sync",
            paths: ["README.md", File.basename(gemspec_path)],
            status: updated_readme == readme && updated_gemspec == gemspec ? "already_current" : "applied",
            grapheme: grapheme,
          }
        rescue StandardError => error
          {
            name: "readme_gemspec_grapheme_sync",
            status: "skipped",
            reason: error.message,
          }
        end

        def configured_project_grapheme(project_root, env)
          env_value = (env || {})["KJ_PROJECT_EMOJI"].to_s.strip
          return first_grapheme(env_value) unless env_value.empty? || Kettle::Jem::DecisionPolicy.falsey?(env_value)

          config_path = File.join(project_root.to_s, ".kettle-jem.yml")
          return nil unless File.file?(config_path)

          config = YAML.safe_load(File.read(config_path), permitted_classes: [], aliases: false)
          value = config["project_emoji"].to_s.strip if config.is_a?(Hash)
          value.to_s.empty? ? nil : first_grapheme(value)
        rescue StandardError
          nil
        end

        def readme_h1_grapheme(content)
          h1 = content.to_s.lines.find { |line| line.match?(/\A#\s+/) }
          return nil unless h1

          first = first_grapheme(h1.sub(/\A#\s+/, ""))
          decorative_grapheme?(first) ? first : nil
        end

        def normalize_readme_h1_grapheme(content, grapheme)
          lines = content.to_s.split("\n", -1)
          index = lines.index { |line| line.match?(/\A#\s+/) }
          return content unless index

          rest = lines.fetch(index).sub(/\A#\s+/, "")
          lines[index] = "# #{grapheme} #{strip_leading_decorative_graphemes(rest)}".rstrip
          lines.join("\n")
        end

        def normalize_gemspec_grapheme(content, grapheme)
          %w[spec.summary spec.description].reduce(content.to_s) do |text, field|
            text.gsub(/(\b#{Regexp.escape(field)}\s*=\s*)(["'])([^"']*)(\2)/) do
              "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{grapheme} #{strip_leading_decorative_graphemes(Regexp.last_match(3))}#{Regexp.last_match(4)}"
            end
          end
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

        def first_grapheme(text)
          text.to_s.strip[/\A\X/u].to_s
        end

        def decorative_grapheme?(grapheme)
          value = grapheme.to_s
          return false if value.empty?

          !value.match?(/\A[[:alnum:][:space:]]\z/u)
        end

        def repair_gemspec_homepage(project_root, env)
          gemspec_path = Dir.glob(File.join(project_root.to_s, "*.gemspec")).sort.first
          return nil unless gemspec_path

          content = File.read(gemspec_path)
          homepage_line = content.lines.find { |line| line.match?(/\bspec\.homepage\s*=/) }
          return {
            name: "gemspec_homepage_literal",
            status: "skipped",
            reason: "missing_homepage",
          } unless homepage_line

          assigned = homepage_line.split("=", 2).last.to_s.strip
          return {
            name: "gemspec_homepage_literal",
            path: File.basename(gemspec_path),
            status: "already_current",
          } if literal_github_homepage?(assigned)

          org = github_org_from_env(env) || github_org_from_origin(project_root)
          gem_name = gemspec_name(content, gemspec_path)
          return {
            name: "gemspec_homepage_literal",
            path: File.basename(gemspec_path),
            status: "skipped",
            reason: "missing_github_org",
          } if org.to_s.empty? || gem_name.to_s.empty?

          homepage = "https://github.com/#{org}/#{gem_name}"
          updated = content.sub(homepage_line, homepage_line.sub(/=.*/, "= #{homepage.dump}\n"))
          File.write(gemspec_path, updated) if updated != content
          {
            name: "gemspec_homepage_literal",
            path: File.basename(gemspec_path),
            status: updated == content ? "already_current" : "applied",
            homepage: homepage,
          }
        end

        def literal_github_homepage?(assigned)
          value = assigned.to_s.strip
          return false if value.include?('#{')

          if (value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'"))
            value = value[1..-2]
          end
          !!value.match(%r{\Ahttps?://github\.com/[^/\s]+/[^/\s]+/?\z}i)
        end

        def github_org_from_env(env)
          %w[FORGE_ORG KJ_GH_USER GITHUB_ORG].each do |key|
            value = (env || {})[key].to_s.strip
            return value unless value.empty? || Kettle::Jem::DecisionPolicy.falsey?(value)
          end
          nil
        end

        def github_org_from_origin(project_root)
          stdout, _stderr, status = Open3.capture3("git", "-C", project_root.to_s, "remote", "get-url", "origin")
          return nil unless status.success?

          stdout[%r{github\.com[/:]([^/\s:]+)/}i, 1]
        end

        def gemspec_name(content, gemspec_path)
          content[/\bspec\.name\s*=\s*["']([^"']+)["']/, 1] || File.basename(gemspec_path, ".gemspec")
        end

        def ensure_env_local_gitignore(project_root)
          return nil unless File.file?(File.join(project_root.to_s, ".env.local.example"))

          gitignore_path = File.join(project_root.to_s, ".gitignore")
          content = File.file?(gitignore_path) ? File.read(gitignore_path) : ""
          return {
            name: "env_local_gitignore",
            path: ".gitignore",
            status: "already_current",
          } if content.lines.any? { |line| line.strip == ".env.local" }

          addition = [
            "# Local environment overrides (KEY=value, loaded by mise via dotenvy)",
            ".env.local",
          ].join("\n")
          updated = content.dup
          updated << "\n" unless updated.empty? || updated.end_with?("\n")
          updated << addition << "\n"
          File.write(gitignore_path, updated)
          {
            name: "env_local_gitignore",
            path: ".gitignore",
            status: "applied",
          }
        end

        def run_bundle_setup_commands(project_root, env:, run_options:, command_runner:)
          quiet = Kettle::Jem::DecisionPolicy.value_to_boolean(run_options[:quiet])
          steps = [
            run_command_step(
              "bin_setup",
              bin_setup_command(project_root, quiet: quiet),
              project_root: project_root,
              env: env,
              quiet: quiet,
              command_runner: command_runner
            ),
            run_command_step(
              "bundle_binstubs",
              %w[bundle binstubs --all],
              project_root: project_root,
              env: env,
              quiet: quiet,
              command_runner: command_runner
            ),
          ]
          steps << validate_bundle_binstub_location(project_root) if steps.any? do |step|
            step.fetch(:name) == "bundle_binstubs" && step.fetch(:status) == "succeeded"
          end
          steps
        end

        def validate_bundle_binstub_location(project_root)
          destination_bin = File.join(project_root.to_s, "bin")
          destination_binstubs = binstub_files(destination_bin)
          parent_root = git_toplevel(project_root)
          parent_binstubs = if parent_root && File.expand_path(parent_root) != File.expand_path(project_root.to_s)
            binstub_files(File.join(parent_root, "bin"))
          else
            []
          end

          if destination_binstubs.empty? && parent_binstubs.any?
            return {
              name: "bundle_binstub_location_validation",
              status: "warning",
              reason: "parent_bin_has_binstubs_but_destination_bin_has_none",
              destination_bin: relative_or_absolute_path(destination_bin, project_root),
              parent_bin: relative_or_absolute_path(File.join(parent_root, "bin"), project_root),
              parent_binstubs: parent_binstubs.map { |path| File.basename(path) }.sort,
            }
          end

          {
            name: "bundle_binstub_location_validation",
            status: destination_binstubs.empty? ? "unverified" : "succeeded",
            reason: destination_binstubs.empty? ? "no_destination_binstubs_found" : "destination_bin_has_binstubs",
            destination_bin: relative_or_absolute_path(destination_bin, project_root),
            destination_binstubs: destination_binstubs.map { |path| File.basename(path) }.sort,
          }
        end

        def binstub_files(bin_dir)
          return [] unless File.directory?(bin_dir)

          Dir.glob(File.join(bin_dir, "*")).select do |path|
            next false unless File.file?(path)
            next false if File.basename(path) == "setup"

            content = File.read(path, 256)
            content.start_with?("#!") && content.include?("ruby")
          rescue StandardError
            false
          end
        end

        def git_toplevel(project_root)
          stdout, _stderr, status = Open3.capture3("git", "-C", project_root.to_s, "rev-parse", "--show-toplevel")
          status.success? ? stdout.strip : nil
        end

        def relative_or_absolute_path(path, project_root)
          expanded_path = File.expand_path(path.to_s)
          expanded_root = File.expand_path(project_root.to_s)
          return "." if expanded_path == expanded_root
          return expanded_path.delete_prefix("#{expanded_root}/") if expanded_path.start_with?("#{expanded_root}/")

          expanded_path
        end

        def execute_orchestration_steps(install_steps, project_root:, env:, run_options:, command_runner:)
          quiet = Kettle::Jem::DecisionPolicy.value_to_boolean(run_options[:quiet])
          install_steps.map do |step|
            case step.fetch(:name)
            when "mise_trust"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "bundled_handoff"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "bootstrap_commit"
              execute_ready_commands_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            else
              step
            end
          end
        end

        def setup_command_env(project_root, env)
          command_env = (env || {}).to_h
          gemfile = File.join(project_root.to_s, "Gemfile")
          command_env["BUNDLE_GEMFILE"] = gemfile if File.file?(gemfile)
          command_env
        end

        def bundled_handoff_step(project_root:, env:, run_options:)
          if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:bootstrap_mode])
            return {
              name: "bundled_handoff",
              status: "skipped",
              reason: "bootstrap_mode",
            }
          end

          bundle_gemfile = (env || {})["BUNDLE_GEMFILE"].to_s.strip
          project_gemfile = File.expand_path(File.join(project_root.to_s, "Gemfile"))
          if !bundle_gemfile.empty? && File.expand_path(bundle_gemfile) == project_gemfile
            return {
              name: "bundled_handoff",
              status: "already_bundled",
              bundle_gemfile: bundle_gemfile,
            }
          end

          {
            name: "bundled_handoff",
            command: ["bundle", "exec", "kettle-jem"] + handoff_argv(run_options),
            status: "ready",
            reason: "ready_for_orchestration",
          }
        end

        def bootstrap_commit_step(project_root, run_options:)
          if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:skip_commit])
            return {
              name: "bootstrap_commit",
              status: "skipped",
              reason: "skip_commit",
            }
          end

          unless git_success?(project_root, "rev-parse", "--is-inside-work-tree")
            return {
              name: "bootstrap_commit",
              status: "unavailable",
              reason: "not_git_repository",
            }
          end

          dirty_entries = git_output(project_root, "status", "--porcelain").lines.map(&:chomp).reject(&:empty?)
          return {
            name: "bootstrap_commit",
            status: "clean_noop",
            dirty_entries: [],
          } if dirty_entries.empty?

          commands = []
          commands << %w[bundle lock] if File.exist?(File.join(project_root, "Gemfile.lock"))
          commands << %w[git add -A]
          commands << ["git", "commit", "-m", "🎨 Template bootstrap by kettle-jem v#{Kettle::Jem::Version::VERSION}"]
          {
            name: "bootstrap_commit",
            status: "ready",
            dirty_entries: dirty_entries,
            commands: commands,
            reason: "ready_for_orchestration",
          }
        end

        def git_success?(project_root, *args)
          _stdout, _stderr, status = Open3.capture3("git", "-C", project_root.to_s, *args)
          status.success?
        end

        def git_output(project_root, *args)
          stdout, _stderr, status = Open3.capture3("git", "-C", project_root.to_s, *args)
          status.success? ? stdout : ""
        end

        def handoff_argv(run_options)
          options = run_options || {}
          argv = []
          argv << "--accept-config" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:accept_config])
          argv << "--skip-commit" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:skip_commit])
          argv << "--quiet" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:quiet])
          argv << "--verbose" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:verbose])
          argv << "--force" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:force])
          argv << "--accept" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:accept])
          argv << "--interactive" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:interactive])
          argv.concat(value_arg("--failure-mode", options[:failure_mode]))
          argv.concat(value_arg("--allowed", options[:allowed]))
          argv.concat(value_arg("--hook-templates", options[:hook_templates]))
          argv.concat(list_arg("--only", options[:only]))
          argv.concat(list_arg("--include", options[:include]))
          argv
        end

        def value_arg(flag, value)
          value.to_s.strip.empty? ? [] : [flag, value.to_s]
        end

        def list_arg(flag, value)
          values = Array(value).flat_map { |entry| entry.to_s.split(",") }.map(&:strip).reject(&:empty?)
          values.empty? ? [] : [flag, values.join(",")]
        end

        def bin_setup_command(project_root, quiet:)
          command = [File.join("bin", "setup")]
          command << "--quiet" if quiet && File.exist?(File.join(project_root, "bin", "setup"))
          command
        end

        def run_command_step(name, command, project_root:, env:, quiet:, command_runner:)
          if command.first == File.join("bin", "setup") && !File.exist?(File.join(project_root, "bin", "setup"))
            return {
              name: name,
              command: command,
              status: "skipped",
              reason: "missing bin/setup",
            }
          end

          result = command_runner.call(command, chdir: project_root, env: env, quiet: quiet)
          success = result.fetch(:success)
          return {
            name: name,
            command: command,
            status: "succeeded",
            exitstatus: result[:exitstatus],
          } if success

          raise Kettle::Jem::Error, "#{name} failed: #{command.join(" ")}\n#{result[:stderr]}"
        end

        def execute_ready_command_step(step, project_root:, env:, quiet:, command_runner:)
          return step unless step.fetch(:status) == "ready"

          result = command_runner.call(step.fetch(:command), chdir: project_root, env: env, quiet: quiet)
          return step.merge(
            status: "succeeded",
            exitstatus: result[:exitstatus],
            reason: "executed"
          ) if result.fetch(:success)

          raise Kettle::Jem::Error, "#{step.fetch(:name)} failed: #{step.fetch(:command).join(" ")}\n#{result[:stderr]}"
        end

        def execute_ready_commands_step(step, project_root:, env:, quiet:, command_runner:)
          return step unless step.fetch(:status) == "ready"

          results = step.fetch(:commands).map do |command|
            result = command_runner.call(command, chdir: project_root, env: env, quiet: quiet)
            unless result.fetch(:success)
              raise Kettle::Jem::Error, "#{step.fetch(:name)} failed: #{command.join(" ")}\n#{result[:stderr]}"
            end
            {
              command: command,
              exitstatus: result[:exitstatus],
            }
          end
          step.merge(
            status: "succeeded",
            command_results: results,
            reason: "executed"
          )
        end

        def run_system_command(command, chdir:, env:, quiet:)
          stdout, stderr, status = Open3.capture3(env || {}, *command, chdir: chdir)
          $stdout.print(stdout) if !quiet && !stdout.empty?
          $stderr.print(stderr) if !quiet && !stderr.empty?
          {
            success: status.success?,
            exitstatus: status.exitstatus,
            stdout: stdout,
            stderr: stderr,
          }
        end
      end
    end
  end
end
