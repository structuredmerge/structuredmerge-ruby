# frozen_string_literal: true

module Kettle
  module Jem
    module Tasks
      module TemplateTask
        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: env_run_options(env), command_runner: Kettle::Jem::Tasks::InstallTask.method(:run_system_command))
          original_lockfile_platforms = Kettle::Jem::Tasks::InstallTask.existing_lockfile_platforms(project_root)
          report = Kettle::Jem.apply_project(project_root, env: env, run_options: run_options)
          setup_env = Kettle::Jem::Tasks::InstallTask.setup_command_env(project_root, env)
          lock_step = Kettle::Jem::Tasks::InstallTask.normalize_lockfile_step(project_root, env: setup_env, platforms: original_lockfile_platforms)
          lock_step = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
            [lock_step],
            project_root: project_root,
            env: setup_env,
            run_options: run_options,
            command_runner: command_runner
          ).first
          report.merge(template_steps: [lock_step])
        end

        def env_run_options(env)
          {
            accept: truthy?(env["accept"]) || truthy?(env["force"]),
            force: truthy?(env["force"]),
            interactive: falsey?(env["force"]),
            failure_mode: env["FAILURE_MODE"] || env["failure_mode"],
            allowed: env["allowed"],
            hook_templates: env["hook_templates"],
            only: env["only"],
            include: env["include"],
            skip_commit: truthy?(env["KETTLE_JEM_SKIP_COMMIT"]),
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
      end
    end
  end
end
