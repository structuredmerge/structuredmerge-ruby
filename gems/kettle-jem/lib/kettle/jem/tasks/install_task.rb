# frozen_string_literal: true

require "fileutils"
require "bundler"
require "json"
require "open3"
require "toml-rb"
require "uri"
require "yaml"
require "kettle/rb/compat_matrix"
require "kettle/jem/maintenance_changelog"

module Kettle
  module Jem
    module Tasks
      module InstallTask
        module_function

        CURATED_BINSTUB_GEMS = %w[appraisal2 rake rbs rspec-core yard kettle-dev kettle-test kettle-soup-cover kettle-gha-pins stone_checksums].freeze
        CURATED_BINSTUB_DISCRETE_EXECUTABLES = %w[
          kettle-drift
          yard
        ].freeze
        GIT_OPERATION_LOCK_ENV_KEYS = %w[KETTLE_JEM_GIT_LOCK KETTLE_JEM_GIT_COMMIT_LOCK].freeze
        GIT_OPERATION_LOCK_RETRY_ATTEMPTS = 5
        GIT_OPERATION_LOCK_RETRY_SLEEP_SECONDS = 0.25

        def run(project_root: Dir.pwd, env: ENV, run_options: {}, command_runner: method(:run_system_command))
          effective_run_options = install_run_options(env, run_options)
          config_migration_step = kettle_config_migration_step(project_root)
          report = Kettle::Jem.apply_project(project_root, env: env, run_options: effective_run_options)
          report = followup_apply_after_config_bootstrap(project_root, env: env, run_options: effective_run_options, report: report)
          install_steps = []
          install_steps << config_migration_step if config_migration_step
          install_steps << gemspec_dependency_sync_step(report)
          install_steps.concat(version_gem_bootstrap_steps(project_root, report))
          mise_step = mise_trust_step(project_root, report, env: env)
          install_steps << mise_step if mise_step
          install_steps.concat(post_template_project_fix_steps(project_root, report, env: env))
          install_steps << hook_templates_step(project_root, effective_run_options)
          install_steps << git_drivers_step(project_root, effective_run_options)
          install_steps << ensure_bin_setup_executable(project_root)
          setup_env = setup_command_env(project_root, env)
          rubocop_lts_branch_step = rubocop_lts_local_branch_step(report, env: setup_env, project_root: project_root)
          install_steps << rubocop_lts_branch_step if rubocop_lts_branch_step
          install_steps << run_distinct_bundle_install_step(project_root, env: env, setup_env: setup_env, run_options: effective_run_options, command_runner: command_runner)
          install_steps.concat(run_bundle_setup_commands(project_root, env: setup_env, run_options: effective_run_options, command_runner: command_runner))
          install_steps << appraisal_generate_step(project_root, env: setup_env, run_options: effective_run_options)
          install_steps << rubocop_gradual_autocorrect_step(project_root, env: setup_env, run_options: effective_run_options)
          install_steps << normalize_lockfile_platforms_step(project_root, env: setup_env, run_options: effective_run_options)
          install_steps << normalize_lockfile_step(project_root, env: setup_env, run_options: effective_run_options)
          install_steps << bundled_handoff_step(project_root: project_root, env: env, run_options: effective_run_options)
          install_steps = execute_orchestration_steps(install_steps, project_root: project_root, env: setup_env, run_options: effective_run_options, command_runner: command_runner)

          final_report = report.merge(
            mode: "install",
            installed: true,
            install_steps: install_steps,
            install_phase_reports: install_phase_reports(install_steps),
            install_summary: install_step_summary(install_steps),
            diagnostics: report.fetch(:diagnostics) + [{
              severity: "advisory",
              message: "kettle:jem:install applied templates, completed local post-template checks, and executed available orchestration steps."
            }]
          )
          final_report = Kettle::Jem::MaintenanceChangelog.record_template_run(
            project_root: project_root,
            report: final_report,
            run_options: effective_run_options
          )
          bootstrap_commit = bootstrap_commit_step(project_root, run_options: effective_run_options)
          install_steps.concat(
            execute_orchestration_steps(
              [bootstrap_commit],
              project_root: project_root,
              env: setup_env,
              run_options: effective_run_options,
              command_runner: command_runner
            )
          )
          final_report = final_report.merge(
            install_steps: install_steps,
            install_phase_reports: install_phase_reports(install_steps),
            install_summary: install_step_summary(install_steps)
          )
          Kettle::Jem.emit_summary_event(Kettle::Jem.event_stream_from_options(effective_run_options), final_report)
          final_report
        end

        def install_run_options(env, run_options)
          Kettle::Jem::Tasks::TemplateTask.templating_run_options(env || {}, run_options || {})
        end

        def followup_apply_after_config_bootstrap(project_root, env:, run_options:, report:)
          return report unless config_bootstrap_changed?(report)

          followup = Kettle::Jem.apply_project(project_root, env: env, run_options: run_options)
          merge_apply_reports(report, followup).merge(
            bootstrap_followup_apply: {
              status: "applied",
              reason: "canonical_config_bootstrapped"
            }
          )
        end

        def config_bootstrap_changed?(report)
          report.fetch(:recipe_reports, []).any? do |recipe_report|
            recipe_report.fetch(:relative_path, nil) == Kettle::Jem::KETTLE_CONFIG_PATH && recipe_report.fetch(:changed, false)
          end
        end

        def merge_apply_reports(initial, followup)
          merged = followup.merge(
            changed_files: (initial.fetch(:changed_files, []) + followup.fetch(:changed_files, [])).uniq,
            recipe_reports: initial.fetch(:recipe_reports, []) + followup.fetch(:recipe_reports, []),
            post_apply_steps: initial.fetch(:post_apply_steps, []) + followup.fetch(:post_apply_steps, []),
            diagnostics: initial.fetch(:diagnostics, []) + followup.fetch(:diagnostics, [])
          )
          merged[:changed] = initial.fetch(:changed, false) || followup.fetch(:changed, false) if initial.key?(:changed) || followup.key?(:changed)
          merged
        end

        def kettle_config_migration_step(project_root)
          canonical_relative = Kettle::Jem::KETTLE_CONFIG_PATH
          legacy_relative = Kettle::Jem::LEGACY_KETTLE_CONFIG_PATH
          canonical = File.join(project_root.to_s, canonical_relative)
          legacy = File.join(project_root.to_s, legacy_relative)
          return nil unless File.exist?(legacy)

          if File.exist?(canonical)
            return {
              name: "kettle_config_migration",
              status: "blocked",
              reason: "legacy_kettle_config_conflict",
              canonical_path: canonical_relative,
              legacy_path: legacy_relative,
              diagnostics: [{
                key: "legacy_kettle_config_conflict",
                severity: "warning",
                blocking: false,
                path: legacy_relative,
                canonical_path: canonical_relative
              }]
            }
          end

          FileUtils.mkdir_p(File.dirname(canonical))
          FileUtils.mv(legacy, canonical)
          {
            name: "kettle_config_migration",
            status: "migrated",
            reason: "legacy_kettle_config_migrated",
            canonical_path: canonical_relative,
            legacy_path: legacy_relative,
            changed_files: [legacy_relative, canonical_relative]
          }
        end

        def gemspec_dependency_sync_step(report)
          gemspec_report = report.fetch(:recipe_reports, []).find do |recipe_report|
            recipe_report.fetch(:relative_path, "").end_with?(".gemspec")
          end
          unless gemspec_report
            return {
              name: "gemspec_dependency_sync",
              status: "unavailable",
              reason: "no_gemspec_recipe"
            }
          end

          {
            name: "gemspec_dependency_sync",
            path: gemspec_report.fetch(:relative_path),
            status: gemspec_report.fetch(:changed, false) ? "applied" : "already_current",
            development_dependencies: development_dependency_names(gemspec_report.fetch(:final_content, ""))
          }
        end

        def development_dependency_names(content)
          Kettle::Jem.gemspec_dependency_records(content)
            .select { |dependency| dependency.fetch(:kind) == "add_development_dependency" }
            .map { |dependency| dependency.fetch(:name) }
            .uniq
        end

        def version_gem_bootstrap_steps(project_root, report)
          existing = report.fetch(:post_apply_steps, []).select do |step|
            %w[version_gem_bootstrap version_gem_cleanup legacy_rbs_consolidation].include?(step.fetch(:name, nil))
          end
          return existing unless existing.empty?

          [Kettle::Jem.template_version_gem_bootstrap_step(project_root, report)].flatten.compact
        end

        def install_phase_reports(install_steps)
          phases = {
            "template_apply" => %w[gemspec_dependency_sync],
            "post_template" => %w[
              kettle_config_migration
              version_gem_bootstrap
              version_gem_cleanup
              legacy_rbs_consolidation
              mise_trust
              legacy_ruby_version_file_cleanup
              readme_compatibility_badges
              readme_gemspec_grapheme_sync
              gemspec_homepage_literal
              env_local_gitignore
              hook_templates
              git_drivers
              rubocop_lts_local_branch
              bundle_install_requested_env
              appraisal_generate
              bin_setup_executable
              bin_setup
              bundle_binstubs
              curated_binstubs_executable
              bundle_binstub_pruning
              bundle_binstub_location_validation
              rubocop_gradual_autocorrect
              bundle_lock_normalization
            ],
            "orchestration" => %w[bundled_handoff bootstrap_commit]
          }
          phases.map do |phase, names|
            steps = install_steps.select { |step| names.include?(step.fetch(:name).to_s) }
            {
              phase: phase,
              steps: steps.map { |step| step.fetch(:name) },
              statuses: steps.to_h { |step| [step.fetch(:name), step.fetch(:status)] }
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
            summary: "install steps #{install_steps.length}; #{statuses.map { |status, count| "#{status} #{count}" }.join("; ")}"
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
            status: ((before == after) ? "already_executable" : "updated")
          }
        end

        def mise_trust_step(project_root, report, env:)
          mise_report = report.fetch(:recipe_reports, []).find do |recipe_report|
            recipe_report.fetch(:relative_path, "") == "mise.toml"
          end
          return nil unless mise_report&.fetch(:changed, false)

          command = ["mise", "trust", "-C", project_root.to_s]
          if mise_installed?(env)
            return {
              name: "mise_trust",
              path: "mise.toml",
              command: command,
              status: "ready",
              reason: "mise_toml_changed"
            }
          end

          {
            name: "mise_trust",
            path: "mise.toml",
            command: command,
            status: "unavailable",
            reason: "mise_not_installed",
            install_url: "https://mise.jdx.dev/getting-started.html"
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
            ensure_env_local_gitignore(project_root)
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
            removed_files: removed
          }
        end

        def trim_readme_compatibility_badges(project_root, report)
          readme_path = File.join(project_root.to_s, "README.md")
          return nil unless File.file?(readme_path)

          min_ruby = report.dig(:facts, :rubygems, :min_ruby)
          if min_ruby.to_s.empty?
            return {
              name: "readme_compatibility_badges",
              status: "skipped",
              reason: "missing_min_ruby"
            }
          end

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
            status: (after == before) ? "already_current" : "applied"
          }
        rescue => error
          {
            name: "readme_compatibility_badges",
            path: "README.md",
            status: "skipped",
            reason: error.message
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
          gemspec_path = Dir.glob(File.join(project_root.to_s, "*.gemspec")).min
          return nil unless File.file?(readme_path) && gemspec_path

          readme = File.read(readme_path)
          gemspec = File.read(gemspec_path)
          grapheme = configured_project_grapheme(project_root, env) || readme_h1_grapheme(readme)
          if grapheme.to_s.empty?
            return {
              name: "readme_gemspec_grapheme_sync",
              status: "skipped",
              reason: "missing_grapheme"
            }
          end

          updated_readme = normalize_readme_h1_grapheme(readme, grapheme)
          updated_gemspec = normalize_gemspec_grapheme(gemspec, grapheme)
          File.write(readme_path, updated_readme) if updated_readme != readme
          File.write(gemspec_path, updated_gemspec) if updated_gemspec != gemspec
          {
            name: "readme_gemspec_grapheme_sync",
            paths: ["README.md", File.basename(gemspec_path)],
            status: (updated_readme == readme && updated_gemspec == gemspec) ? "already_current" : "applied",
            grapheme: grapheme
          }
        rescue => error
          {
            name: "readme_gemspec_grapheme_sync",
            status: "skipped",
            reason: error.message
          }
        end

        def configured_project_grapheme(project_root, env)
          env_value = (env || {})["KJ_PROJECT_EMOJI"].to_s.strip
          return first_grapheme(env_value) unless env_value.empty? || Kettle::Jem::DecisionPolicy.falsey?(env_value)

          config_path = Kettle::Jem.kettle_jem_config_path(project_root.to_s)
          return nil unless File.file?(config_path)

          config = YAML.safe_load_file(config_path, permitted_classes: [], aliases: false)
          value = config["project_emoji"].to_s.strip if config.is_a?(Hash)
          value.to_s.empty? ? nil : first_grapheme(value)
        rescue
          nil
        end

        def readme_h1_grapheme(content)
          h1 = Kettle::Jem.markdown_heading_owners(content, source_label: "README.md").find { |owner| owner.level == 1 }
          return nil unless h1

          first = first_grapheme(h1.heading_text)
          decorative_grapheme?(first) ? first : nil
        end

        def normalize_readme_h1_grapheme(content, grapheme)
          lines = content.to_s.split("\n", -1)
          h1 = Kettle::Jem.markdown_heading_owners(content, source_label: "README.md").find { |owner| owner.level == 1 }
          return content unless h1

          index = h1.location.start_line - 1
          rest = h1.heading_text
          lines[index] = "# #{grapheme} #{strip_leading_decorative_graphemes(rest)}".rstrip
          lines.join("\n")
        end

        def normalize_gemspec_grapheme(content, grapheme)
          replacements = gemspec_grapheme_assignment_replacements(content, grapheme)
          replace_character_ranges(content.to_s, replacements)
        end

        def gemspec_grapheme_assignment_replacements(content, grapheme)
          Kettle::Jem.ruby_call_records(content, nil).filter_map do |call|
            next unless %i[summary= description=].include?(call.name)
            next unless call.receiver&.slice == "spec"

            argument = call.arguments&.arguments&.first
            next unless argument.is_a?(::Prism::StringNode) && argument.content_loc

            replacement = "#{grapheme} #{strip_leading_decorative_graphemes(argument.unescaped)}"
            [
              argument.content_loc.start_character_offset,
              argument.content_loc.end_character_offset,
              ruby_string_literal_content(replacement, argument.opening_loc&.slice)
            ]
          end
        end

        def ruby_string_literal_content(value, quote)
          escaped = value.to_s.gsub("\\", "\\\\\\\\")
          quote.to_s.empty? ? escaped : escaped.gsub(quote.to_s, "\\#{quote}")
        end

        def replace_character_ranges(content, replacements)
          replacements.sort_by(&:first).reverse.reduce(content.to_s) do |updated, (start_character_offset, end_character_offset, replacement)|
            "#{updated[0...start_character_offset]}#{replacement}#{updated[end_character_offset..]}"
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
          gemspec_path = Dir.glob(File.join(project_root.to_s, "*.gemspec")).min
          return nil unless gemspec_path

          content = File.read(gemspec_path)
          homepage_record = Kettle::Jem.gemspec_assignment_records(content, receiver: "spec")
            .find { |record| record.fetch(:field) == "homepage" }
          unless homepage_record
            return {
              name: "gemspec_homepage_literal",
              status: "skipped",
              reason: "missing_homepage"
            }
          end

          assigned = homepage_record[:value]
          if literal_github_homepage?(assigned)
            return {
              name: "gemspec_homepage_literal",
              path: File.basename(gemspec_path),
              status: "already_current"
            }
          end

          org = github_org_from_env(env) || github_org_from_origin(project_root)
          gem_name = gemspec_name(content, gemspec_path)
          if org.to_s.empty? || gem_name.to_s.empty?
            return {
              name: "gemspec_homepage_literal",
              path: File.basename(gemspec_path),
              status: "skipped",
              reason: "missing_github_org"
            }
          end

          homepage = "https://github.com/#{org}/#{gem_name}"
          receiver = homepage_record.fetch(:receiver)
          field = homepage_record.fetch(:field)
          indent = Kettle::Jem.leading_whitespace(homepage_record.fetch(:source))
          updated = Kettle::Jem.replace_source_range_lines(
            content,
            homepage_record.fetch(:start_line),
            homepage_record.fetch(:end_line),
            "#{indent}#{receiver}.#{field} = #{homepage.dump}\n"
          )
          File.write(gemspec_path, updated) if updated != content
          {
            name: "gemspec_homepage_literal",
            path: File.basename(gemspec_path),
            status: (updated == content) ? "already_current" : "applied",
            homepage: homepage
          }
        end

        def literal_github_homepage?(assigned)
          value = assigned.to_s.strip
          return false if value.include?('#{')

          if (value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'"))
            value = value[1..-2]
          end
          uri = URI.parse(value)
          segments = uri.path.to_s.split("/").reject(&:empty?)
          %w[http https].include?(uri.scheme) && uri.host == "github.com" && segments.length == 2
        rescue URI::InvalidURIError
          false
        end

        def github_org_from_env(env)
          %w[FORGE_ORG KJ_GH_ORG GITHUB_ORG].each do |key|
            value = (env || {})[key].to_s.strip
            return value unless value.empty? || Kettle::Jem::DecisionPolicy.falsey?(value)
          end
          nil
        end

        def github_org_from_origin(project_root)
          stdout, _stderr, status = Open3.capture3("git", "-C", project_root.to_s, "remote", "get-url", "origin")
          return nil unless status.success?

          remote = stdout.to_s.strip
          path = if remote.start_with?("git@github.com:")
            remote.split(":", 2).last
          else
            uri = URI.parse(remote)
            return nil unless uri.host == "github.com"

            uri.path
          end
          path.to_s.delete_prefix("/").split("/").first
        rescue URI::InvalidURIError
          nil
        end

        def gemspec_name(content, gemspec_path)
          Kettle::Jem.gemspec_assignment_records(content, receiver: "spec")
            .find { |record| record.fetch(:field) == "name" }
            &.fetch(:value) ||
            File.basename(gemspec_path, ".gemspec")
        end

        def ensure_env_local_gitignore(project_root)
          return nil unless File.file?(File.join(project_root.to_s, ".env.local.example"))

          gitignore_path = File.join(project_root.to_s, ".gitignore")
          content = File.file?(gitignore_path) ? File.read(gitignore_path) : ""
          if content.lines.any? { |line| line.strip == ".env.local" }
            return {
              name: "env_local_gitignore",
              path: ".gitignore",
              status: "already_current"
            }
          end

          addition = [
            "# Local environment overrides (KEY=value, loaded by mise via dotenvy)",
            ".env.local"
          ].join("\n")
          updated = content.dup
          updated << "\n" unless updated.empty? || updated.end_with?("\n")
          updated << addition << "\n"
          File.write(gitignore_path, updated)
          {
            name: "env_local_gitignore",
            path: ".gitignore",
            status: "applied"
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
            )
          ]
          steps << if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:skip_binstubs])
            {
              name: "bundle_binstubs",
              status: "skipped",
              reason: "skip_binstubs"
            }
          else
            run_command_step(
              "bundle_binstubs",
              bundle_binstubs_command(project_root, env: env),
              project_root: project_root,
              env: env,
              quiet: quiet,
              command_runner: command_runner
            )
          end
          if steps.any? { |step| step.fetch(:name) == "bundle_binstubs" && step.fetch(:status) == "succeeded" }
            steps << rewrite_yard_binstub(project_root)
            steps << prune_unwanted_bundler_binstubs(project_root)
            steps << ensure_curated_binstubs_executable(project_root)
            steps << validate_bundle_binstub_location(project_root)
          end
          steps
        end

        def appraisal_generate_step(project_root, env: nil, run_options: {})
          if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:skip_appraisal_generate])
            return {
              name: "appraisal_generate",
              status: "skipped",
              reason: "skip_appraisal_generate"
            }
          end

          unless Array((run_options || {})[:only]).empty?
            return {
              name: "appraisal_generate",
              status: "skipped",
              reason: "template_selection"
            }
          end

          unless File.file?(File.join(project_root.to_s, "Appraisals")) && File.file?(File.join(project_root.to_s, "bin", "rake"))
            return {
              name: "appraisal_generate",
              status: "skipped",
              reason: "missing_appraisals_entrypoint"
            }
          end

          unless rake_task_available?(project_root, "appraisal:generate", env: env)
            return {
              name: "appraisal_generate",
              status: "skipped",
              reason: "missing_appraisal_generate_task"
            }
          end

          {
            name: "appraisal_generate",
            command: ["bin/rake", "appraisal:generate"],
            status: "ready",
            reason: "post_template_appraisal_generation"
          }
        end

        def bundle_binstubs_command(project_root = Dir.pwd, env: ENV)
          %w[bundle binstubs] + curated_binstub_gems_in_bundle(project_root, env: env)
        end

        def curated_binstub_gems_in_bundle(project_root = Dir.pwd, env: ENV)
          stdout, _stderr, status = Open3.capture3(env.to_h, "bundle", "list", "--name-only", chdir: project_root.to_s)
          return CURATED_BINSTUB_GEMS unless status.success?

          bundled = stdout.lines.map(&:strip).reject(&:empty?)
          CURATED_BINSTUB_GEMS & bundled
        end

        def bundle_includes_gem?(project_root, gem_name, env: ENV)
          stdout, _stderr, status = Open3.capture3(env.to_h, "bundle", "list", "--name-only", chdir: project_root.to_s)
          return true unless status.success?

          stdout.lines.map(&:strip).include?(gem_name.to_s)
        end

        def normalize_lockfile_step(project_root, env:, run_options: {})
          if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:skip_lock_normalization])
            return {
              name: "bundle_lock_normalization",
              status: "skipped",
              reason: "skip_lock_normalization"
            }
          end

          if local_path_development_env?(env)
            return {
              name: "bundle_lock_normalization",
              status: "skipped",
              reason: "local_path_development_env"
            }
          end

          unless File.file?(File.join(project_root.to_s, "Gemfile.lock"))
            return {
              name: "bundle_lock_normalization",
              status: "skipped",
              reason: "missing Gemfile.lock"
            }
          end

          {
            name: "bundle_lock_normalization",
            command: lockfile_normalization_command(project_root),
            status: "ready",
            env: normal_lockfile_env(project_root, env),
            reason: "bundle_lock_update_preserving_platforms_without_templating_overrides"
          }
        end

        def normalize_lockfile_platforms_step(project_root, env:, run_options: {})
          return skipped_lockfile_normalization_step("lockfile_platform_normalization", "skip_lock_normalization") if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:skip_lock_normalization])
          return skipped_lockfile_normalization_step("lockfile_platform_normalization", "local_path_development_env") if local_path_development_env?(env)
          return skipped_lockfile_normalization_step("lockfile_platform_normalization", "missing_Gemfile.lock") unless File.file?(File.join(project_root.to_s, "Gemfile.lock"))

          {
            name: "lockfile_platform_normalization",
            status: "ready",
            reason: "preserve_locked_dependencies_and_add_local_platform"
          }
        end

        def normalize_lockfile_platforms(project_root)
          lock_path = File.join(project_root.to_s, "Gemfile.lock")
          contents = Bundler.read_file(lock_path)
          platforms = (Bundler::LockfileParser.new(contents).platforms.map(&:to_s) + [Gem::Platform.local.to_s]).reject(&:empty?).uniq.sort
          lines = contents.lines
          platforms_index = lines.index { |line| line == "PLATFORMS\n" }
          raise Bundler::LockfileError, "Gemfile.lock does not contain a PLATFORMS section" unless platforms_index

          next_section_index = lines.each_index.find do |index|
            index > platforms_index && !lines[index].start_with?("  ") && lines[index] != "\n"
          end
          raise Bundler::LockfileError, "Gemfile.lock PLATFORMS section has no following section" unless next_section_index

          normalized_section = ["PLATFORMS\n", *platforms.map { |platform| "  #{platform}\n" }, "\n"]
          return {changed: false, platforms: platforms} if lines[platforms_index...next_section_index] == normalized_section

          # Bundler exposes a parser but no public platform-only writer. Keep the
          # locked dependency graph byte-for-byte intact while rewriting this
          # validated, line-oriented section.
          lines[platforms_index...next_section_index] = normalized_section
          File.write(lock_path, lines.join)
          {changed: true, platforms: platforms}
        end

        def skipped_lockfile_normalization_step(name, reason)
          {name: name, status: "skipped", reason: reason}
        end

        def lockfile_normalization_command(project_root)
          platforms = lockfile_normalization_platforms(project_root)
          ["bundle", "lock", *platforms.map { |platform| "--add-platform=#{platform}" }, "--update", "--add-checksums"]
        end

        def lockfile_normalization_platforms(project_root)
          lock_path = File.join(project_root.to_s, "Gemfile.lock")
          existing = Bundler::LockfileParser.new(Bundler.read_file(lock_path)).platforms.map(&:to_s)
          (existing + [Gem::Platform.local.to_s]).reject(&:empty?).uniq.sort
        rescue Bundler::LockfileError, Errno::ENOENT
          [Gem::Platform.local.to_s]
        end

        def distinct_bundle_install_step(project_root, env:, setup_env:)
          bundle_env = bundler_command_env(project_root, env)
          if same_bundle_env?(bundle_env, setup_env)
            return {
              name: "bundle_install_requested_env",
              status: "skipped",
              reason: "same_as_setup_bundle_env"
            }
          end

          {
            name: "bundle_install_requested_env",
            command: %w[bundle install],
            status: "ready",
            env: bundle_env,
            reason: "distinct_bundle_env"
          }
        end

        def run_distinct_bundle_install_step(project_root, env:, setup_env:, run_options:, command_runner:)
          step = distinct_bundle_install_step(project_root, env: env, setup_env: setup_env)
          return step unless step.fetch(:status) == "ready"

          execute_ready_command_step(
            step,
            project_root: project_root,
            env: setup_env,
            quiet: Kettle::Jem::DecisionPolicy.value_to_boolean(run_options[:quiet]),
            command_runner: command_runner
          )
        end

        def rubocop_gradual_autocorrect_step(project_root, env: nil, run_options: {})
          if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:skip_rubocop_gradual])
            return {
              name: "rubocop_gradual_autocorrect",
              status: "skipped",
              reason: "skip_rubocop_gradual"
            }
          end

          rakefile = File.join(project_root.to_s, "Rakefile")
          bin_rake = File.join(project_root.to_s, "bin", "rake")
          unless File.file?(rakefile) && File.file?(bin_rake)
            return {
              name: "rubocop_gradual_autocorrect",
              status: "skipped",
              reason: "missing_rake_entrypoint"
            }
          end
          unless rake_task_available?(project_root, "rubocop_gradual:autocorrect", env: env)
            return {
              name: "rubocop_gradual_autocorrect",
              status: "skipped",
              reason: "missing_rubocop_gradual_task"
            }
          end

          {
            name: "rubocop_gradual_autocorrect",
            command: rubocop_gradual_autocorrect_command,
            status: "ready",
            reason: "post_template_style_normalization"
          }
        end

        def rubocop_gradual_autocorrect_command
          ["sh", "-c", "rm -f .rubocop_gradual.lock && bin/rake rubocop_gradual:autocorrect"]
        end

        def rake_task_available?(project_root, task_name, env: nil)
          stdout, _stderr, status = Open3.capture3((env || {}).to_h, "bin/rake", "--tasks", chdir: project_root.to_s)
          status.success? && stdout.lines.any? { |line| line.include?(task_name.to_s) }
        rescue Errno::EACCES, Errno::ENOENT
          false
        end

        def rubocop_lts_local_branch_step(report, env:, project_root: nil)
          local_root = rubocop_lts_local_root(env)
          return nil unless local_root

          ruby_gem = report.dig(:facts, :templates, :tokens, "KJ|RUBOCOP_RUBY_GEM").to_s
          branch = Kettle::Rb::CompatMatrix.rubocop_lts_branch_for_gem(ruby_gem)
          unless branch
            raise Kettle::Jem::Error, "Cannot select RUBOCOP_LTS_LOCAL branch for #{ruby_gem.inspect}"
          end

          checkout = File.join(local_root, "rubocop-lts")
          if project_root && same_path?(project_root, checkout)
            return {
              name: "rubocop_lts_local_branch",
              status: "skipped",
              path: checkout,
              branch: branch,
              reason: "destination_is_rubocop_lts_checkout"
            }
          end

          current = current_git_branch(checkout)
          if current == branch
            return {
              name: "rubocop_lts_local_branch",
              status: "already_current",
              path: checkout,
              branch: branch
            }
          end

          {
            name: "rubocop_lts_local_branch",
            command: %W[git -C #{checkout} switch #{branch}],
            status: "ready",
            path: checkout,
            current_branch: current,
            branch: branch,
            reason: "rubocop_lts_local_branch_matrix"
          }
        end

        def same_path?(left, right)
          File.realpath(left.to_s) == File.realpath(right.to_s)
        rescue Errno::ENOENT
          File.expand_path(left.to_s) == File.expand_path(right.to_s)
        end

        def rubocop_lts_local_root(env)
          value = (env || {})["RUBOCOP_LTS_LOCAL"].to_s.strip
          return nil if value.empty? || Kettle::Jem::DecisionPolicy.falsey?(value)
          return File.join((env || {})["HOME"].to_s.empty? ? Dir.home : (env || {})["HOME"].to_s, "src", "rubocop-lts") if value.casecmp("true").zero? || value == "1" || value.casecmp("yes").zero? || value.casecmp("on").zero?
          return value if value.start_with?("/")

          File.join((env || {})["HOME"].to_s.empty? ? Dir.home : (env || {})["HOME"].to_s, value)
        end

        def current_git_branch(path)
          stdout, _stderr, status = Open3.capture3("git", "-C", path.to_s, "branch", "--show-current")
          return "" unless status.success?

          stdout.to_s.strip
        end

        def normal_lockfile_env(project_root, env)
          command_env = (env || {}).to_h.dup
          strip_inherited_bundler_activation!(command_env)
          command_env["K_JEM_TEMPLATING"] = "false"
          %w[KETTLE_DEV_DEV GALTZO_FLOSS_DEV STRUCTUREDMERGE_DEV].each do |key|
            command_env[key] = "false" if command_env.key?(key)
          end
          gemfile = File.join(project_root.to_s, "Gemfile")
          command_env["BUNDLE_GEMFILE"] = gemfile if File.file?(gemfile)
          apply_direct_sibling_lockfile_env!(project_root, command_env)
          %w[
            BUNDLE_PATH
            BUNDLE_WITH
            BUNDLE_WITHOUT
          ].each do |key|
            command_env[key] = nil
          end
          command_env
        end

        def apply_direct_sibling_lockfile_env!(project_root, command_env)
          gemspec_path = Dir.glob(File.join(project_root.to_s, "*.gemspec")).min
          return unless gemspec_path

          metadata = Kettle::Jem.send(:project_gemspec_metadata, project_root, gemspec_path)
          package_name = metadata[:gem_name] || metadata["gem_name"] || File.basename(gemspec_path, ".gemspec")
          direct_sibling_gems = Kettle::Jem.send(
            :direct_sibling_runtime_gems,
            project_root,
            metadata,
            package_name: package_name
          )
          return if direct_sibling_gems.empty?

          source_url = metadata[:source_code_uri] || metadata["source_code_uri"] ||
            metadata[:homepage] || metadata["homepage"]
          workspace_slug = Kettle::Jem.send(:direct_sibling_workspace_slug, source_url, project_root)
          prefix = workspace_slug.to_s.upcase.tr("-", "_")
          prefix = "LOCAL" if prefix.empty?
          dev_env = "#{prefix}_DEV"
          command_env[dev_env] = File.expand_path("..", project_root.to_s) if local_env_disabled?(command_env[dev_env])
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
              parent_binstubs: parent_binstubs.map { |path| File.basename(path) }.sort
            }
          end

          {
            name: "bundle_binstub_location_validation",
            status: destination_binstubs.empty? ? "unverified" : "succeeded",
            reason: destination_binstubs.empty? ? "no_destination_binstubs_found" : "destination_bin_has_binstubs",
            destination_bin: relative_or_absolute_path(destination_bin, project_root),
            destination_binstubs: destination_binstubs.map { |path| File.basename(path) }.sort
          }
        end

        def rewrite_yard_binstub(project_root)
          yard_binstub = File.join(project_root.to_s, "bin", "yard")
          unless File.file?(yard_binstub)
            return {
              name: "yard_binstub_rake_handoff",
              status: "skipped",
              reason: "missing_yard_binstub",
              path: "bin/yard"
            }
          end

          content = yard_binstub_rake_handoff_content
          if File.read(yard_binstub) == content
            return {
              name: "yard_binstub_rake_handoff",
              status: "already_current",
              reason: "yard_binstub_already_runs_rake_yard",
              path: "bin/yard"
            }
          end

          executable = File.executable?(yard_binstub)
          File.write(yard_binstub, content)
          FileUtils.chmod("+x", yard_binstub) if executable
          {
            name: "yard_binstub_rake_handoff",
            status: "updated",
            reason: "yard_plugins_require_rake_yard_postprocess_hooks",
            path: "bin/yard"
          }
        end

        def yard_binstub_rake_handoff_content
          <<~RUBY
            #!/usr/bin/env ruby
            # frozen_string_literal: true

            # Generated by kettle-jem after curated `bundle binstubs`.
            #
            # Bundler's normal yard binstub executes the raw YARD CLI. That skips
            # Rake task enhancements installed by documentation plugins such as
            # yard-timekeeper. Those plugins run after YARD finishes and may restore
            # checked-in docs files whose only diff is generated timestamp churn.
            #
            # The canonical docs entrypoint is therefore the Rake task, not raw
            # `yard` / `bin/yard`. Keep this binstub as a handoff to the task so
            # humans and tools that reach for `bin/yard` still run the full docs
            # workflow with post-processing hooks.
            exec("bundle", "exec", "rake", "yard")
          RUBY
        end

        def ensure_curated_binstubs_executable(project_root)
          bin_dir = File.join(project_root.to_s, "bin")
          executable_binstubs = binstub_files(bin_dir).select { |path| curated_binstub?(path) }
          updated = executable_binstubs.filter_map do |path|
            next if File.executable?(path)

            FileUtils.chmod("+x", path)
            File.basename(path)
          end

          {
            name: "curated_binstubs_executable",
            status: updated.empty? ? "already_executable" : "updated",
            path: "bin",
            executable_binstubs: executable_binstubs.map { |path| File.basename(path) }.sort,
            updated_binstubs: updated.sort
          }
        end

        def prune_unwanted_bundler_binstubs(project_root)
          bin_dir = File.join(project_root.to_s, "bin")
          removed = []
          preserved = []
          binstub_files(bin_dir).each do |path|
            basename = File.basename(path)
            next if curated_binstub?(path)
            next unless bundler_generated_binstub?(path)

            if tracked_binstub?(project_root, path)
              preserved << basename
              next
            end

            FileUtils.rm_f(path)
            removed << basename
          end

          {
            name: "bundle_binstub_pruning",
            status: removed.empty? ? "already_current" : "pruned",
            reason: removed.empty? ? "no_unwanted_bundler_binstubs" : "removed_unwanted_bundler_binstubs",
            removed_binstubs: removed.sort,
            preserved_binstubs: preserved.sort
          }
        end

        def tracked_binstub?(project_root, path)
          relative_path = path.to_s.delete_prefix("#{File.expand_path(project_root.to_s)}/")
          _stdout, _stderr, status = Open3.capture3(
            "git",
            "-C",
            project_root.to_s,
            "ls-files",
            "--error-unmatch",
            "--",
            relative_path
          )
          status.success?
        rescue
          false
        end

        def binstub_files(bin_dir)
          return [] unless File.directory?(bin_dir)

          Dir.glob(File.join(bin_dir, "*")).select do |path|
            next false unless File.file?(path)
            next false if File.basename(path) == "setup"

            content = File.read(path, 256)
            content.start_with?("#!") && content.include?("ruby")
          rescue
            false
          end
        end

        def curated_binstub?(path)
          basename = File.basename(path)
          return true if CURATED_BINSTUB_DISCRETE_EXECUTABLES.include?(basename)

          gem_name = bundler_binstub_gem_name(path)
          !gem_name.to_s.empty? && CURATED_BINSTUB_GEMS.include?(gem_name)
        end

        def bundler_generated_binstub?(path)
          File.read(path, 512).include?("This file was generated by Bundler")
        rescue
          false
        end

        def bundler_binstub_gem_name(path)
          content = File.read(path)
          return unless content.include?("This file was generated by Bundler")

          Kettle::Jem.ruby_call_records(content, :bin_path).filter_map do |call|
            next unless call.receiver&.slice == "Gem"

            argument = call.arguments&.arguments&.first
            next unless argument.is_a?(::Prism::StringNode)

            argument.unescaped
          end.first
        rescue
          nil
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

        def execute_orchestration_steps(install_steps, project_root:, env:, run_options:, command_runner:, event_phase: "install")
          quiet = Kettle::Jem::DecisionPolicy.value_to_boolean(run_options[:quiet])
          events = Kettle::Jem.event_stream_from_options(run_options)
          install_steps.map do |step|
            Kettle::Jem.emit_step_event(
              events,
              "command_step",
              step.merge(status: "started"),
              phase: event_phase
            )
            result = case step.fetch(:name)
            when "mise_trust"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "bundled_handoff"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "bundle_lock_normalization"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "lockfile_platform_normalization"
              execute_lockfile_platform_normalization_step(step, project_root: project_root)
            when "rubocop_lts_local_branch"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "bundle_install_requested_env"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "appraisal_generate"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "rubocop_gradual_autocorrect"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "hook_templates"
              execute_hook_templates_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "git_drivers"
              execute_git_drivers_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "bootstrap_commit"
              execute_ready_commands_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            else
              step
            end
            Kettle::Jem.emit_step_event(events, "command_step", result, phase: event_phase)
            result
          end
        end

        def execute_lockfile_platform_normalization_step(step, project_root:)
          return step unless step.fetch(:status) == "ready"

          result = normalize_lockfile_platforms(project_root)
          step.merge(
            status: "succeeded",
            reason: result.fetch(:changed) ? "local_platform_added" : "local_platform_already_present",
            platforms: result.fetch(:platforms)
          )
        rescue Bundler::LockfileError, Errno::ENOENT => error
          step.merge(status: "failed", reason: "lockfile_platform_normalization_failed", stderr: error.message)
        end

        def setup_command_env(project_root, env)
          command_env = (env || {}).to_h.dup
          templating_requested = command_env.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
          requested_bundler_version = command_env["KJ_BUNDLER_VERSION"].to_s.strip
          requested_gemfile = command_env["BUNDLE_GEMFILE"].to_s
          disable_checksum_validation = command_env["BUNDLE_DISABLE_CHECKSUM_VALIDATION"]
          strip_inherited_bundler_activation!(command_env)
          command_env["BUNDLER_VERSION"] = requested_bundler_version unless requested_bundler_version.empty?
          gemfile = File.join(project_root.to_s, "Gemfile")
          if File.file?(gemfile) || (!requested_gemfile.empty? && same_path?(requested_gemfile, gemfile))
            command_env["BUNDLE_GEMFILE"] = gemfile
          end
          command_env["K_JEM_TEMPLATING"] = "true" if templating_requested
          command_env["BUNDLE_DISABLE_CHECKSUM_VALIDATION"] = disable_checksum_validation unless disable_checksum_validation.nil?
          apply_kettle_family_local_install_env!(command_env)
          command_env["K_JEM_TEMPLATING"] = if templating_requested && local_path_development_env?(command_env)
            "true"
          else
            "false"
          end
          command_env
        end

        def bundler_command_env(project_root, env)
          command_env = (env || {}).to_h.dup
          requested_bundler_version = command_env["KJ_BUNDLER_VERSION"].to_s.strip
          disable_checksum_validation = command_env["BUNDLE_DISABLE_CHECKSUM_VALIDATION"]
          strip_inherited_bundler_activation!(command_env)
          command_env["BUNDLER_VERSION"] = requested_bundler_version unless requested_bundler_version.empty?
          gemfile = File.join(project_root.to_s, "Gemfile")
          command_env["BUNDLE_GEMFILE"] = gemfile if File.file?(gemfile)
          command_env["BUNDLE_DISABLE_CHECKSUM_VALIDATION"] = disable_checksum_validation unless disable_checksum_validation.nil?
          command_env["K_JEM_TEMPLATING"] = "false" unless command_env.key?("K_JEM_TEMPLATING")
          apply_kettle_family_local_install_env!(command_env)
          command_env
        end

        def same_bundle_env?(left, right)
          bundle_env_fingerprint(left) == bundle_env_fingerprint(right)
        end

        def bundle_env_fingerprint(env)
          env.to_h.transform_values { |value| value&.to_s }.reject { |key, _value| ignored_bundle_env_key?(key) }
        end

        def ignored_bundle_env_key?(key)
          key.to_s.match?(/\A(?:BUNDLE_BIN_PATH|BUNDLE_LOCKFILE|BUNDLER_SETUP|BUNDLER_VERSION|RUBYLIB|RUBYOPT)\z/)
        end

        def apply_kettle_family_local_install_env!(command_env)
          return unless command_env.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?

          marker = kettle_family_local_install_marker(command_env)
          return unless Array(marker["installed_members"]).include?("kettle-jem")

          members_root = marker["members_root"].to_s
          if !command_env.key?("STRUCTUREDMERGE_DEV") && Dir.exist?(File.join(members_root, "kettle-jem"))
            command_env["STRUCTUREDMERGE_DEV"] = members_root
          end

          kettle_root = kettle_family_dependency_root(marker)
          command_env["KETTLE_DEV_DEV"] = kettle_root if kettle_root && !command_env.key?("KETTLE_DEV_DEV")
        end

        def kettle_family_local_install_marker(command_env)
          path = command_env["KETTLE_FAMILY_LOCAL_INSTALL_MARKER"].to_s
          path = File.join(Dir.home, ".kettle-family", "local-install.json") if path.empty?
          return {} unless File.file?(path)

          JSON.parse(File.read(path))
        rescue JSON::ParserError
          {}
        end

        def kettle_family_dependency_root(marker)
          Array(marker["local_dependencies"]).map(&:to_s).each do |path|
            return File.dirname(path) if File.basename(path) == "kettle-dev"
          end
          nil
        end

        def local_env_disabled?(value)
          raw_value = value.to_s.strip
          raw_value.empty? || Kettle::Jem::DecisionPolicy.falsey?(raw_value)
        end

        def local_path_development_env?(env)
          (env || {}).any? do |key, value|
            key.to_s.end_with?("_DEV") && !local_env_disabled?(value)
          end
        end

        def strip_inherited_bundler_activation!(command_env)
          (ENV.keys + command_env.keys).grep(/\ABUNDLE_/).each { |key| command_env[key] = nil }
          (ENV.keys + command_env.keys).grep(/\ABUNDLER_/).each { |key| command_env[key] = nil }
          (ENV.keys + command_env.keys).grep(/\AGIT_CONFIG_(?:COUNT|KEY_\d+|VALUE_\d+)\z/).each { |key| command_env[key] = nil }
          %w[RUBYLIB RUBYOPT].each { |key| command_env[key] = nil }
        end

        def hook_templates_step(project_root, run_options)
          mode = normalize_hook_templates_mode((run_options || {})[:hook_templates])
          if mode.empty? || mode == "none"
            return {
              name: "hook_templates",
              status: "skipped",
              reason: "not_requested"
            }
          end

          if mode == "global"
            return {
              name: "hook_templates",
              status: "unsupported",
              reason: "global_hooks_not_implemented",
              requested: mode
            }
          end

          hooks_dir = File.join(project_root.to_s, ".git-hooks")
          missing_hooks = %w[commit-msg prepare-commit-msg].reject { |hook| File.file?(File.join(hooks_dir, hook)) }
          unless missing_hooks.empty?
            return {
              name: "hook_templates",
              status: "unavailable",
              reason: "missing_local_hook_templates",
              missing_hooks: missing_hooks
            }
          end

          {
            name: "hook_templates",
            status: "ready",
            command: %w[git config core.hooksPath .git-hooks],
            chmod_paths: %w[.git-hooks/commit-msg .git-hooks/prepare-commit-msg],
            reason: "ready_for_local_hooks"
          }
        end

        def normalize_hook_templates_mode(value)
          normalized = value.to_s.strip.downcase
          return "" if normalized.empty?
          return "none" if %w[0 false f no n none off skip].include?(normalized)
          return "local" if %w[1 true t yes y on l local].include?(normalized)
          return "global" if %w[g global].include?(normalized)

          normalized
        end

        DEFAULT_GIT_DRIVER_DEFINITIONS = Ractor.make_shareable([
          {
            language: "ruby",
            pattern: "*.rb",
            diff: "smorg-rb",
            merge: "smorg-rb",
            diff_command: "smorg-rb diff-driver",
            merge_command: "smorg-rb merge-driver %O %A %B %P"
          },
          {
            language: "go",
            pattern: "*.go",
            diff: "smorg-go",
            merge: "smorg-go",
            diff_command: "smorg-go diff-driver",
            merge_command: "smorg-go merge-driver %O %A %B %P"
          },
          {
            language: "rust",
            pattern: "*.rs",
            diff: "smorg-rs",
            merge: "smorg-rs",
            diff_command: "smorg-rs diff-driver",
            merge_command: "smorg-rs merge-driver %O %A %B %P"
          }
        ])
        GIT_DRIVER_LANGUAGE_REGISTRY = Ractor.make_shareable(DEFAULT_GIT_DRIVER_DEFINITIONS.to_h { |definition| [definition.fetch(:language), definition] })

        BUILTIN_GIT_DIFF_ATTRIBUTES = Ractor.make_shareable([
          {path: ".gitattributes", pattern: "*.rb", attributes: {"diff" => "ruby"}},
          {path: ".gitattributes", pattern: "*.go", attributes: {"diff" => "golang"}},
          {path: ".gitattributes", pattern: "*.rs", attributes: {"diff" => "rust"}}
        ])

        def git_drivers_step(project_root, run_options)
          mode = normalize_git_drivers_mode((run_options || {})[:git_drivers])
          dry_run = Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:dry_run])
          manifest = git_driver_manifest(project_root)
          if mode == "none"
            return {
              name: "git_drivers",
              status: "skipped",
              reason: "not_requested",
              mode: mode
            }
          end

          case mode
          when "check"
            {
              name: "git_drivers",
              status: "ready",
              mode: mode,
              profile: "semantic-diff",
              scope: "check",
              attribute_updates: git_driver_attribute_updates(manifest, "semantic-diff"),
              config_checks: git_driver_local_config_checks(manifest, "semantic-diff"),
              reason: "ready_for_git_driver_check"
            }
          when "undo"
            {
              name: "git_drivers",
              status: dry_run ? "planned" : "ready",
              mode: mode,
              profile: "all",
              scope: "local",
              attribute_removals: [
                {path: ".gitattributes", managed_block: "structuredmerge:git-drivers"},
                {path: ".gitattributes", managed_block: "structuredmerge:git-builtins"}
              ],
              commands: git_driver_global_unset_commands,
              reason: dry_run ? "dry_run_git_driver_undo" : "ready_for_git_driver_undo"
            }
          when "global"
            {
              name: "git_drivers",
              status: dry_run ? "planned" : "ready",
              mode: mode,
              profile: "semantic-diff",
              scope: "global",
              commands: git_driver_global_commands(manifest, "semantic-diff"),
              diagnostics: [git_driver_forge_warning_diagnostic],
              reason: dry_run ? "dry_run_global_git_drivers" : "ready_for_global_git_drivers"
            }
          when "include-file"
            {
              name: "git_drivers",
              status: dry_run ? "planned" : "ready",
              mode: mode,
              profile: "semantic-diff",
              scope: "include-file",
              include_file: ".git/smorg/config",
              config_entries: git_driver_global_commands(manifest, "semantic-diff").map { |command| {key: command[3], value: command[4]} },
              commands: [["git", "config", "--local", "include.path", ".git/smorg/config"]],
              diagnostics: [git_driver_forge_warning_diagnostic],
              reason: dry_run ? "dry_run_git_driver_include_file" : "ready_for_git_driver_include_file"
            }
          when "builtin-diff"
            updates = git_driver_attribute_updates(manifest, "builtin-diff")
            diagnostics = git_driver_attribute_diagnostics(project_root, updates, managed_block: "structuredmerge:git-builtins")
            {
              name: "git_drivers",
              status: git_driver_attribute_status(diagnostics, dry_run: dry_run),
              mode: mode,
              profile: "builtin-diff",
              scope: "local",
              attribute_updates: updates,
              managed_block: "structuredmerge:git-builtins",
              commands: [],
              diagnostics: diagnostics,
              reason: git_driver_attribute_reason(diagnostics, dry_run: dry_run, ready: "ready_for_builtin_git_attributes")
            }
          else
            updates = git_driver_attribute_updates(manifest, "semantic-diff")
            diagnostics = git_driver_attribute_diagnostics(project_root, updates, managed_block: "structuredmerge:git-drivers")
            {
              name: "git_drivers",
              status: git_driver_attribute_status(diagnostics, dry_run: dry_run),
              mode: "local",
              profile: "semantic-diff",
              scope: "local",
              attribute_updates: updates,
              managed_block: "structuredmerge:git-drivers",
              commands: git_driver_local_commands(manifest, "semantic-diff"),
              diagnostics: diagnostics + [git_driver_forge_warning_diagnostic],
              reason: git_driver_attribute_reason(diagnostics, dry_run: dry_run, ready: "ready_for_local_git_drivers")
            }
          end
        end

        def normalize_git_drivers_mode(value)
          normalized = value.to_s.strip.downcase.tr("_", "-")
          return "local" if normalized.empty?
          return "none" if %w[0 false f no n none off skip].include?(normalized)
          return "local" if %w[1 true t yes y on l local semantic semantic-diff].include?(normalized)
          return "global" if %w[g global].include?(normalized)
          return "include-file" if %w[include include-file].include?(normalized)
          return "builtin-diff" if %w[b builtin builtin-diff].include?(normalized)
          return "check" if normalized == "check"
          return "undo" if normalized == "undo"

          normalized
        end

        def semantic_git_driver_attribute_updates
          GIT_DRIVER_LANGUAGE_REGISTRY.values.map do |definition|
            {
              path: ".gitattributes",
              pattern: definition.fetch(:pattern),
              attributes: {"diff" => definition.fetch(:diff)}
            }
          end
        end

        def git_driver_forge_warning_diagnostic
          {
            key: "forge_ignores_external_diff_drivers",
            severity: "advisory",
            blocking: false,
            message: "External StructuredMerge diff drivers are local Git configuration and are generally not honored by hosted forges."
          }
        end

        def git_driver_attribute_updates(manifest, profile)
          profile_hash = git_driver_manifest_profile(manifest, profile)
          return semantic_git_driver_attribute_updates if profile == "semantic-diff" && !profile_hash
          return BUILTIN_GIT_DIFF_ATTRIBUTES if profile == "builtin-diff" && !profile_hash

          Array(profile_hash.fetch("attributes", [])).map do |entry|
            attributes = entry.except("pattern").transform_values(&:to_s)
            {path: ".gitattributes", pattern: entry.fetch("pattern"), attributes: attributes}
          end
        end

        def git_driver_global_commands(manifest = nil, profile = "semantic-diff")
          profile_hash = git_driver_manifest_profile(manifest, profile)
          return default_git_driver_global_commands unless profile_hash

          Array(profile_hash.fetch("git_config", [])).map do |entry|
            ["git", "config", "--global", entry.fetch("key"), entry.fetch("value")]
          end
        end

        def git_driver_local_commands(manifest = nil, profile = "semantic-diff")
          git_driver_global_commands(manifest, profile).map do |command|
            ["git", "config", "--local", command[3], command[4]]
          end
        end

        def default_git_driver_global_commands
          DEFAULT_GIT_DRIVER_DEFINITIONS.flat_map do |definition|
            [
              ["git", "config", "--global", "diff.#{definition.fetch(:diff)}.command", definition.fetch(:diff_command)],
              ["git", "config", "--global", "merge.#{definition.fetch(:merge)}.driver", definition.fetch(:merge_command)],
              ["git", "config", "--global", "merge.#{definition.fetch(:merge)}.name", "StructuredMerge #{definition.fetch(:language)} merge driver"]
            ]
          end
        end

        def git_driver_global_unset_commands
          DEFAULT_GIT_DRIVER_DEFINITIONS.flat_map do |definition|
            [
              ["git", "config", "--global", "--unset-all", "diff.#{definition.fetch(:diff)}.command"],
              ["git", "config", "--global", "--unset-all", "merge.#{definition.fetch(:merge)}.driver"],
              ["git", "config", "--global", "--unset-all", "merge.#{definition.fetch(:merge)}.name"]
            ]
          end
        end

        def git_driver_global_config_checks(manifest = nil, profile = "semantic-diff")
          git_driver_global_commands(manifest, profile).map do |command|
            {key: command[3], expected: command[4], argv: ["git", "config", "--global", "--get", command[3]]}
          end
        end

        def git_driver_local_config_checks(manifest = nil, profile = "semantic-diff")
          git_driver_local_commands(manifest, profile).map do |command|
            {key: command[3], expected: command[4], argv: ["git", "config", "--local", "--get", command[3]]}
          end
        end

        def git_driver_manifest(project_root)
          path = File.join(project_root.to_s, ".structuredmerge", "git-drivers.toml")
          return nil unless File.file?(path)

          manifest = TomlRB.parse(File.read(path))
          validate_git_driver_manifest!(manifest)
          manifest
        rescue TomlRB::ParseError => error
          raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: #{error.message}"
        end

        def git_driver_manifest_profile(manifest, profile)
          return nil unless manifest

          manifest.fetch("profiles").fetch(profile)
        end

        def validate_git_driver_manifest!(manifest)
          raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: root must be a mapping" unless manifest.is_a?(Hash)
          raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: version must be 1" unless manifest["version"] == 1

          profiles = manifest["profiles"]
          raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: profiles must be a mapping" unless profiles.is_a?(Hash)

          profiles.each do |profile_name, profile|
            validate_git_driver_profile!(profile_name, profile)
          end
        end

        def validate_git_driver_profile!(profile_name, profile)
          raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: profile name is required" if profile_name.to_s.empty?
          raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: profile #{profile_name} must be a mapping" unless profile.is_a?(Hash)

          Array(profile.fetch("attributes", [])).each do |entry|
            raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: profile #{profile_name} attribute pattern is required" if entry["pattern"].to_s.empty?
          end
          Array(profile.fetch("git_config", [])).each do |entry|
            raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: profile #{profile_name} git_config scope must be global" unless entry["scope"] == "global"
            raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: profile #{profile_name} git_config key is required" if entry["key"].to_s.empty?
            if entry["key"].to_s.end_with?(".cachetextconv") && !profile_name.to_s.include?("textconv")
              raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: cachetextconv requires an explicit textconv profile"
            end
            value = entry["value"].to_s
            raise Kettle::Jem::Error, "Invalid .structuredmerge/git-drivers.toml: unsafe command interpolation" if unsafe_git_driver_command_value?(value)
          end
        end

        def unsafe_git_driver_command_value?(value)
          value.include?("$(") || value.include?("${") || value.include?("`")
        end

        def git_driver_attribute_status(diagnostics, dry_run:)
          return "blocked" if diagnostics.any? { |diagnostic| diagnostic.fetch(:blocking, false) }

          dry_run ? "planned" : "ready"
        end

        def git_driver_attribute_reason(diagnostics, dry_run:, ready:)
          return "git_driver_attribute_conflict" if diagnostics.any? { |diagnostic| diagnostic.fetch(:key) == "conflicting_attributes" }
          return "dirty_managed_block" if diagnostics.any? { |diagnostic| diagnostic.fetch(:key) == "dirty_managed_block" }

          dry_run ? "dry_run_git_driver_attributes" : ready
        end

        def git_driver_attribute_diagnostics(project_root, updates, managed_block:)
          path = File.join(project_root.to_s, ".gitattributes")
          return [] unless File.file?(path)

          content = File.read(path)
          diagnostics = []
          if dirty_git_attribute_managed_block?(content, managed_block)
            diagnostics << {
              key: "dirty_managed_block",
              severity: "error",
              blocking: true,
              path: ".gitattributes",
              managed_block: managed_block
            }
          end
          diagnostics.concat(conflicting_git_attribute_diagnostics(content, updates, managed_block: managed_block))
          diagnostics
        end

        def dirty_git_attribute_managed_block?(content, managed_block)
          start_line = git_attribute_block_start(managed_block)
          end_line = git_attribute_block_end(managed_block)
          content.lines.any? { |line| line.chomp == start_line } &&
            content.lines.none? { |line| line.chomp == end_line }
        end

        def conflicting_git_attribute_diagnostics(content, updates, managed_block:)
          lines = remove_git_attribute_managed_block(content, managed_block: managed_block).fetch(:lines)
          updates.filter_map do |update|
            conflict = lines.find { |line| git_attribute_line_conflicts?(line, update) }
            next unless conflict

            {
              key: "conflicting_attributes",
              severity: "error",
              blocking: true,
              path: update.fetch(:path, ".gitattributes"),
              pattern: update.fetch(:pattern),
              line: conflict
            }
          end
        end

        def git_attribute_line_conflicts?(line, update)
          parts = line.to_s.strip.split
          return false if parts.empty? || parts.first.start_with?("#")
          return false unless parts.first == update.fetch(:pattern)

          attributes = update.fetch(:attributes)
          parts.drop(1).any? do |token|
            key, value = token.split("=", 2)
            attributes.key?(key) && attributes.fetch(key) != value
          end
        end

        def bundled_handoff_step(project_root:, env:, run_options:)
          if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:bootstrap_mode])
            return {
              name: "bundled_handoff",
              status: "skipped",
              reason: "bootstrap_mode"
            }
          end

          bundle_gemfile = (env || {})["BUNDLE_GEMFILE"].to_s.strip
          project_gemfile = File.expand_path(File.join(project_root.to_s, "Gemfile"))
          if !bundle_gemfile.empty? && File.expand_path(bundle_gemfile) == project_gemfile
            return {
              name: "bundled_handoff",
              status: "already_bundled",
              bundle_gemfile: bundle_gemfile
            }
          end

          unless bundle_includes_gem?(project_root, "kettle-jem", env: setup_command_env(project_root, env))
            return {
              name: "bundled_handoff",
              status: "skipped",
              reason: "kettle_jem_not_in_bundle"
            }
          end

          {
            name: "bundled_handoff",
            command: bundled_handoff_command(run_options),
            status: "ready",
            reason: "ready_for_orchestration"
          }
        end

        def bootstrap_commit_step(project_root, run_options:)
          if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:skip_commit])
            return {
              name: "bootstrap_commit",
              status: "skipped",
              reason: "skip_commit"
            }
          end

          unless git_success?(project_root, "rev-parse", "--is-inside-work-tree")
            return {
              name: "bootstrap_commit",
              status: "unavailable",
              reason: "not_git_repository"
            }
          end

          dirty_entries = git_output(project_root, "status", "--porcelain").lines.map(&:chomp).reject(&:empty?)
          if dirty_entries.empty?
            return {
              name: "bootstrap_commit",
              status: "clean_noop",
              dirty_entries: []
            }
          end

          commands = []
          commands << %w[git add -A -- .]
          commands << ["git", "commit", "-m", "🎨 Template bootstrap by kettle-jem v#{Kettle::Jem::Version::VERSION}"]
          {
            name: "bootstrap_commit",
            status: "ready",
            dirty_entries: dirty_entries,
            commands: commands,
            reason: "ready_for_orchestration"
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
          argv << "--skip-drift-check" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:skip_drift_check])
          argv << "--skip-rubocop-gradual" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:skip_rubocop_gradual])
          argv << "--skip-binstubs" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:skip_binstubs])
          argv << "--quiet" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:quiet])
          argv << "--verbose" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:verbose])
          argv << "--force" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:force])
          argv << "--accept" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:accept])
          argv << "--interactive" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:interactive])
          argv << "--dry-run" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:dry_run])
          argv.concat(value_arg("--checksums", options[:checksums]))
          argv.concat(value_arg("--failure-mode", options[:failure_mode]))
          argv.concat(value_arg("--allowed", options[:allowed]))
          argv.concat(value_arg("--hook-templates", options[:hook_templates]))
          argv.concat(value_arg("--git-drivers", options[:git_drivers]))
          argv.concat(list_arg("--only", options[:only]))
          argv.concat(list_arg("--include", options[:include]))
          argv
        end

        def bundled_handoff_command(run_options)
          [
            "bundle",
            "exec",
            "ruby",
            "-e",
            %(load Gem.bin_path("kettle-jem", "kettle-jem")),
            "--"
          ] + handoff_argv(run_options)
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
              reason: "missing bin/setup"
            }
          end

          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = command_runner.call(command, chdir: project_root, env: env, quiet: quiet)
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(3)
          success = result.fetch(:success)
          if success
            return {
              name: name,
              command: command,
              status: "succeeded",
              exitstatus: result[:exitstatus],
              duration_ms: duration_ms
            }
          end

          recovered = retry_after_unsupported_templating_platform(
            name: name,
            command: command,
            project_root: project_root,
            env: env,
            quiet: quiet,
            command_runner: command_runner,
            failure: result
          )
          return recovered if recovered

          raise Kettle::Jem::Error, "#{name} failed: #{command.join(" ")}\n#{result[:stderr]}"
        end

        def retry_after_unsupported_templating_platform(name:, command:, project_root:, env:, quiet:, command_runner:, failure:)
          platform = unsupported_templating_platform(failure[:stderr], project_root)
          return unless platform

          recovery_command = ["bundle", "lock", "--remove-platform=#{platform}"]
          recovery = command_runner.call(recovery_command, chdir: project_root, env: env, quiet: quiet)
          return unless recovery.fetch(:success)

          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          retried = command_runner.call(command, chdir: project_root, env: env, quiet: quiet)
          return unless retried.fetch(:success)

          {
            name: name,
            command: command,
            status: "succeeded",
            exitstatus: retried[:exitstatus],
            duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(3),
            recovered: true,
            recovery: {
              command: recovery_command,
              platform: platform,
              status: "succeeded",
              changed_files: ["Gemfile.lock"]
            }
          }
        end

        def unsupported_templating_platform(stderr, project_root)
          # Bundler exposes this compatibility failure only as stderr text; match
          # its exact quoted diagnostic rather than guessing from lockfile content.
          match = /Could not find gem 'tree_sitter_language_pack' with platform '([^']+)'/.match(stderr.to_s)
          return unless match

          lock_path = File.join(project_root.to_s, "Gemfile.lock")
          return unless File.file?(lock_path)

          platforms = Bundler::LockfileParser.new(Bundler.read_file(lock_path)).platforms.map(&:to_s)
          platform = match[1]
          platforms.include?(platform) ? platform : nil
        rescue Bundler::LockfileError
          nil
        end

        def execute_ready_command_step(step, project_root:, env:, quiet:, command_runner:)
          return step unless step.fetch(:status) == "ready"

          command_env = step.fetch(:env, env)
          result = run_ready_step_command(step.fetch(:name), step.fetch(:command), project_root: project_root, env: command_env, quiet: quiet, command_runner: command_runner)
          step.merge(
            status: "succeeded",
            exitstatus: result[:exitstatus],
            duration_ms: result.fetch(:duration_ms),
            reason: "executed"
          ).tap do |report|
            report[:attempts] = result.fetch(:attempts) if result.fetch(:attempts) > 1
          end
        end

        def execute_ready_commands_step(step, project_root:, env:, quiet:, command_runner:)
          return step unless step.fetch(:status) == "ready"

          if step.fetch(:name) == "bootstrap_commit"
            return execute_bootstrap_commit_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
          end

          execute_unlocked_ready_commands_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
        end

        def execute_bootstrap_commit_step(step, project_root:, env:, quiet:, command_runner:)
          with_git_operation_lock(env, metadata_key: :git_commit_lock) do
            execute_unlocked_ready_commands_step(
              step,
              project_root: project_root,
              env: env,
              quiet: quiet,
              command_runner: command_runner
            )
          end
        end

        def execute_unlocked_ready_commands_step(step, project_root:, env:, quiet:, command_runner:)
          if step.fetch(:name) == "bootstrap_commit"
            dirty_entries = git_output(project_root, "status", "--porcelain").lines.map(&:chomp).reject(&:empty?)
            if dirty_entries.empty?
              return step.merge(
                status: "clean_noop",
                dirty_entries: [],
                reason: "clean_before_execution"
              )
            end
          end

          command_env = step.fetch(:env, env)
          results = step.fetch(:commands).map do |command|
            result = run_ready_step_command(step.fetch(:name), command, project_root: project_root, env: command_env, quiet: quiet, command_runner: command_runner)
            {
              command: command,
              exitstatus: result[:exitstatus],
              duration_ms: result.fetch(:duration_ms)
            }.tap do |report|
              report[:attempts] = result.fetch(:attempts) if result.fetch(:attempts) > 1
            end
          end
          step.merge(
            status: "succeeded",
            command_results: results,
            duration_ms: results.sum { |result| result.fetch(:duration_ms, 0).to_f }.round(3),
            reason: "executed"
          )
        end

        def run_ready_step_command(step_name, command, project_root:, env:, quiet:, command_runner:)
          attempts = git_operation_step_name?(step_name) ? GIT_OPERATION_LOCK_RETRY_ATTEMPTS : 1
          attempt = 0
          last_result = nil
          last_duration_ms = 0.0
          loop do
            attempt += 1
            started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            last_result = command_runner.call(command, chdir: project_root, env: env, quiet: quiet)
            last_duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(3)
            if last_result.fetch(:success)
              return {
                success: true,
                exitstatus: last_result[:exitstatus],
                duration_ms: last_duration_ms,
                attempts: attempt
              }
            end

            break unless attempt < attempts && git_lock_conflict?(last_result[:stderr])

            sleep(GIT_OPERATION_LOCK_RETRY_SLEEP_SECONDS * attempt)
          end

          raise Kettle::Jem::Error, "#{step_name} failed: #{command.join(" ")}\n#{last_result[:stderr]}"
        end

        def git_operation_step_name?(step_name)
          %w[bootstrap_commit git_drivers].include?(step_name.to_s)
        end

        def git_lock_conflict?(stderr)
          text = stderr.to_s
          text.include?("could not lock config file") ||
            text.include?("config.lock") ||
            text.include?("index.lock") ||
            text.include?("Unable to create") && text.include?(".lock")
        end

        def git_operation_lock_path(env)
          GIT_OPERATION_LOCK_ENV_KEYS.each do |key|
            value = env.fetch(key, nil).to_s
            return value unless value.empty?
          end
          nil
        end

        def with_git_operation_lock(env, metadata_key:)
          lock_path = git_operation_lock_path(env || {})
          return yield if lock_path.to_s.empty?

          FileUtils.mkdir_p(File.dirname(lock_path))
          File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
            lock.flock(File::LOCK_EX)
            yield.merge(metadata_key => lock_path)
          ensure
            lock&.flock(File::LOCK_UN)
          end
        end

        def execute_hook_templates_step(step, project_root:, env:, quiet:, command_runner:)
          return step unless step.fetch(:status) == "ready"

          step.fetch(:chmod_paths, []).each do |relative_path|
            path = File.join(project_root.to_s, relative_path)
            FileUtils.chmod(0o755, path) if File.file?(path)
          end
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = command_runner.call(step.fetch(:command), chdir: project_root, env: env, quiet: quiet)
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(3)
          unless result.fetch(:success)
            raise Kettle::Jem::Error, "hook_templates failed: #{step.fetch(:command).join(" ")}\n#{result[:stderr]}"
          end
          step.merge(
            status: "succeeded",
            exitstatus: result[:exitstatus],
            duration_ms: duration_ms,
            reason: "executed"
          )
        end

        def execute_git_drivers_step(step, project_root:, env:, quiet:, command_runner:)
          return step unless step.fetch(:status) == "ready"

          if step.fetch(:mode) == "check"
            return execute_git_drivers_check_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
          end

          with_git_operation_lock(env, metadata_key: :git_lock) do
            execute_unlocked_git_drivers_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
          end
        end

        def execute_unlocked_git_drivers_step(step, project_root:, env:, quiet:, command_runner:)
          changed_files = []
          if step.fetch(:mode) == "include-file"
            include_path = File.join(project_root.to_s, step.fetch(:include_file))
            FileUtils.mkdir_p(File.dirname(include_path))
            before = File.file?(include_path) ? File.read(include_path) : ""
            after = render_git_driver_include_config(step.fetch(:config_entries))
            if before != after
              File.write(include_path, after)
              changed_files << step.fetch(:include_file)
            end
          end
          Array(step[:attribute_removals]).each do |removal|
            path = File.join(project_root.to_s, removal.fetch(:path))
            next unless File.file?(path)

            before = File.read(path)
            after = remove_git_attribute_managed_block(before, managed_block: removal.fetch(:managed_block)).fetch(:lines).join("\n")
            after = "#{after}\n" unless after.empty?
            next if after == before

            File.write(path, after)
            changed_files << removal.fetch(:path)
          end

          unless Array(step[:attribute_updates]).empty?
            path = File.join(project_root.to_s, ".gitattributes")
            before = File.file?(path) ? File.read(path) : ""
            after = render_git_attributes(before, step.fetch(:attribute_updates), managed_block: step.fetch(:managed_block))
            if after != before
              File.write(path, after)
              changed_files << ".gitattributes"
            end
          end

          command_step = execute_ready_commands_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
          command_step.merge(
            status: "succeeded",
            changed_files: changed_files.uniq,
            reason: "executed"
          )
        end

        def execute_git_drivers_check_step(step, project_root:, env:, quiet:, command_runner:)
          missing = []
          content = File.file?(File.join(project_root.to_s, ".gitattributes")) ? File.read(File.join(project_root.to_s, ".gitattributes")) : ""
          Array(step[:attribute_updates]).each do |update|
            next if content.include?(render_git_attribute_line(update))

            missing << {kind: "attributes", path: update.fetch(:path), pattern: update.fetch(:pattern)}
          end
          Array(step[:config_checks]).each do |check|
            result = command_runner.call(check.fetch(:argv), chdir: project_root, env: env, quiet: quiet)
            next if result.fetch(:success) && result.fetch(:stdout).to_s.strip == check.fetch(:expected)

            missing << {kind: "local_config", key: check.fetch(:key)}
          end
          status = missing.empty? ? "succeeded" : "failed"
          report = step.merge(status: status, ok: missing.empty?, missing: missing, reason: "checked")
          return report if missing.empty?

          raise Kettle::Jem::Error, "git_drivers check failed: #{missing.map { |entry| entry.fetch(:kind) }.uniq.join(", ")} missing"
        end

        def render_git_driver_include_config(config_entries)
          lines = ["# Generated by kettle-jem; do not commit this file."]
          Array(config_entries).each do |entry|
            section, name = entry.fetch(:key).split(".", 2)
            lines << ""
            lines << "[#{section} \"#{name.split(".").first}\"]"
            lines << "\t#{name.split(".").drop(1).join(".")} = #{entry.fetch(:value).inspect}"
          end
          "#{lines.join("\n")}\n"
        end

        def render_git_attributes(content, updates, managed_block:)
          unmanaged_lines = remove_git_attribute_managed_block(content, managed_block: managed_block).fetch(:lines)
          rendered_lines = unmanaged_lines.reject { |line| line.empty? && unmanaged_lines.last == line }
          rendered_lines << git_attribute_block_start(managed_block)
          updates.each { |update| rendered_lines << render_git_attribute_line(update) }
          rendered_lines << git_attribute_block_end(managed_block)
          "#{rendered_lines.join("\n")}\n"
        end

        def remove_git_attribute_managed_block(content, managed_block:)
          start_line = git_attribute_block_start(managed_block)
          end_line = git_attribute_block_end(managed_block)
          skipping = false
          removed = false
          lines = []
          content.lines(chomp: true).each do |line|
            if line == start_line
              skipping = true
              removed = true
              next
            end
            if skipping
              skipping = false if line == end_line
              next
            end
            lines << line
          end
          {lines: lines, removed: removed}
        end

        def render_git_attribute_line(update)
          attributes = update.fetch(:attributes).map { |key, value| "#{key}=#{value}" }.join(" ")
          "#{update.fetch(:pattern)} #{attributes}"
        end

        def git_attribute_block_start(managed_block)
          "# <<#{managed_block}>> do not edit below this line"
        end

        def git_attribute_block_end(managed_block)
          "# <</#{managed_block}>>"
        end

        def run_system_command(command, chdir:, env:, quiet:)
          command_env = quiet ? quiet_command_env(env) : (env || {})
          stdout, stderr, status = Open3.capture3(command_env, *quiet_command(command, quiet: quiet), chdir: chdir)
          $stdout.print(stdout) if !quiet && !stdout.empty?
          $stderr.print(stderr) if !quiet && !stderr.empty?
          {
            success: status.success?,
            exitstatus: status.exitstatus,
            stdout: stdout,
            stderr: stderr
          }
        end

        def quiet_command(command, quiet:)
          argv = command.map(&:to_s)
          return argv unless quiet
          return argv unless argv.first == "bundle"
          return argv if argv.include?("--quiet")

          subcommand = argv[1]
          return [*argv, "--quiet"] if %w[install update].include?(subcommand)

          argv
        end

        def quiet_command_env(env)
          (env || {}).to_h.merge(
            "DEBUG" => "false",
            "KETTLE_JEM_DEBUG" => "false",
            "KETTLE_DEV_DEBUG" => "false",
            "BUNDLE_IGNORE_MESSAGES" => "true",
            "BUNDLE_SILENCE_DEPRECATIONS" => "true",
            "BUNDLE_SILENCE_ROOT_WARNING" => "true",
            "BUNDLE_VERBOSE" => "false"
          )
        end
      end
    end
  end
end
