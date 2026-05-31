# frozen_string_literal: true

module Kettle
  module Jem
    module Tasks
      module TemplateTask
        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: env_run_options(env), command_runner: Kettle::Jem::Tasks::InstallTask.method(:run_system_command))
          report = if Dir.glob(File.join(project_root.to_s, "*.gemspec")).empty? && !monorepo_root_profile?(project_root, env, run_options)
            {
              mode: "apply",
              changed_files: [],
              diagnostics: [],
              recipe_reports: [],
            }
          else
            Kettle::Jem.apply_project(project_root, env: env, run_options: run_options)
          end
          setup_env = Kettle::Jem::Tasks::InstallTask.setup_command_env(project_root, env)
          hook_step = Kettle::Jem::Tasks::InstallTask.hook_templates_step(project_root, run_options)
          git_drivers_step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(project_root, run_options)
          lock_step = Kettle::Jem::Tasks::InstallTask.normalize_lockfile_step(project_root, env: setup_env, run_options: run_options)
          template_steps = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
            [hook_step, git_drivers_step, lock_step],
            project_root: project_root,
            env: setup_env,
            run_options: run_options,
            command_runner: command_runner,
          )
          report.merge(template_steps: template_steps)
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
            dry_run: truthy?(env["KETTLE_JEM_DRY_RUN"]),
            skip_commit: truthy?(env["KETTLE_JEM_SKIP_COMMIT"]),
            skip_lock_normalization: truthy?(env["KETTLE_JEM_SKIP_LOCK_NORMALIZATION"]),
            accept_config: truthy?(env["KETTLE_JEM_ACCEPT_CONFIG"]),
            bootstrap_mode: truthy?(env["KETTLE_JEM_BOOTSTRAP_MODE"]),
            quiet: truthy?(env["KETTLE_JEM_QUIET"]),
            verbose: truthy?(env["KETTLE_JEM_VERBOSE"]),
          }.compact
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
