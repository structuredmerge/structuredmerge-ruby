# frozen_string_literal: true

require "etc"

module Kettle
  module Jem
    module Tasks
      module TemplateTask
        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: nil, command_runner: Kettle::Jem::Tasks::InstallTask.method(:run_system_command))
          effective_run_options = templating_run_options(env, run_options)
          report = if Dir.glob(File.join(project_root.to_s, "*.gemspec")).empty? && !monorepo_root_profile?(project_root, env, effective_run_options)
            {
              mode: "apply",
              changed_files: [],
              diagnostics: [],
              recipe_reports: []
            }
          else
            Kettle::Jem.apply_project(project_root, env: env, run_options: effective_run_options)
          end
          setup_env = Kettle::Jem::Tasks::InstallTask.setup_command_env(project_root, env)
          hook_step = Kettle::Jem::Tasks::InstallTask.hook_templates_step(project_root, effective_run_options)
          git_drivers_step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(project_root, effective_run_options)
          lock_step = Kettle::Jem::Tasks::InstallTask.normalize_lockfile_step(project_root, env: setup_env, run_options: effective_run_options)
          template_steps = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
            [hook_step, git_drivers_step, lock_step],
            project_root: project_root,
            env: setup_env,
            run_options: effective_run_options,
            command_runner: command_runner,
            event_phase: "template"
          )
          final_report = report.merge(mode: "template", template_steps: template_steps)
          Kettle::Jem.emit_summary_event(Kettle::Jem.event_stream_from_options(effective_run_options), final_report)
          final_report
        end

        def templating_run_options(env, run_options)
          options = env_run_options(env || {}).merge(run_options || {})
          return options if worker_or_strategy_option_provided?(env || {}, options)

          workers = default_thread_worker_count
          options.merge(
            recipe_planning_strategy: "classified",
            recipe_planning_thread_workers: workers,
            file_work_thread_workers: workers
          )
        end

        def env_run_options(env)
          {
            accept: truthy?(env["accept"]) || truthy?(env["force"]),
            force: truthy?(env["force"]),
            interactive: falsey?(env["force"]),
            failure_mode: env["FAILURE_MODE"] || env["failure_mode"],
            allowed: env["allowed"],
            hook_templates: env["hook_templates"],
            git_drivers: env["git_drivers"] || env["KETTLE_JEM_GIT_DRIVERS"],
            only: env["only"],
            include: env["include"],
            template_profile: env["KETTLE_JEM_TEMPLATE_PROFILE"],
            dry_run: truthy?(env["KETTLE_JEM_DRY_RUN"]),
            skip_commit: truthy?(env["KETTLE_JEM_SKIP_COMMIT"]),
            skip_drift_check: truthy?(env["KETTLE_JEM_SKIP_DRIFT_CHECK"]),
            skip_rubocop_gradual: truthy?(env["KETTLE_JEM_SKIP_RUBOCOP_GRADUAL"]),
            skip_binstubs: truthy?(env["KETTLE_JEM_SKIP_BINSTUBS"]),
            skip_appraisal_generate: truthy?(env["KETTLE_JEM_SKIP_APPRAISAL_GENERATE"]),
            skip_lock_normalization: truthy?(env["KETTLE_JEM_SKIP_LOCK_NORMALIZATION"]),
            skip_changelog: truthy?(env["KETTLE_JEM_SKIP_CHANGELOG"]),
            checksums: env["KETTLE_JEM_CHECKSUMS"],
            accept_config: truthy?(env["KETTLE_JEM_ACCEPT_CONFIG"]),
            bootstrap_mode: truthy?(env["KETTLE_JEM_BOOTSTRAP_MODE"]),
            quiet: truthy?(env["KETTLE_JEM_QUIET"]),
            verbose: truthy?(env["KETTLE_JEM_VERBOSE"])
          }.compact
        end

        def default_thread_worker_count
          [1, Etc.nprocessors / 2].max
        end

        def worker_or_strategy_option_provided?(env, run_options)
          option_keys = %i[
            ractor_workers
            recipe_planning_workers
            thread_workers
            recipe_planning_thread_workers
            ractor_file_workers
            file_work_workers
            thread_file_workers
            file_work_thread_workers
            recipe_planning_strategy
          ]
          string_option_keys = option_keys.map(&:to_s)
          env_keys = %w[
            KETTLE_JEM_RACTOR_WORKERS
            KETTLE_JEM_THREAD_WORKERS
            KETTLE_JEM_RACTOR_FILE_WORKERS
            KETTLE_JEM_THREAD_FILE_WORKERS
            KETTLE_JEM_RECIPE_PLANNING_STRATEGY
          ]
          option_keys.any? { |key| run_options.key?(key) } ||
            string_option_keys.any? { |key| run_options.key?(key) } ||
            env_keys.any? { |key| env.key?(key) && !env[key].to_s.strip.empty? }
        end

        def truthy?(value)
          Kettle::Jem::DecisionPolicy.truthy?(value)
        end

        def falsey?(value)
          Kettle::Jem::DecisionPolicy.falsey?(value)
        end

        def monorepo_root_profile?(project_root, env, run_options)
          profile = (run_options || {})[:template_profile] || (run_options || {})["template_profile"] || (env || {})["KETTLE_JEM_TEMPLATE_PROFILE"]
          profile = Kettle::Jem.kettle_jem_config(project_root).dig("templates", "profile") if profile.to_s.empty?
          Kettle::Jem.normalize_template_profile(profile) == Kettle::Jem::MONOREPO_ROOT_TEMPLATE_PROFILE
        end
      end
    end
  end
end
