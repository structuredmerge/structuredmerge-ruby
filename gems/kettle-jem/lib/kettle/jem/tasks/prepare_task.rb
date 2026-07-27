# frozen_string_literal: true

require "bundler"

module Kettle
  module Jem
    module Tasks
      module PrepareTask
        PREPARE_ONLY_PATHS = [
          Kettle::Jem::KETTLE_CONFIG_PATH,
          "Gemfile",
          "gemfiles/modular/templating.gemfile",
          "gemfiles/modular/templating_local.gemfile",
          "mise.toml"
        ].freeze
        CRITICAL_TEMPLATING_GEMS = %w[nomono].freeze
        LOCKED_TEMPLATING_GEMS = %w[tree_sitter_language_pack].freeze

        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: {}, command_runner: Kettle::Jem::Tasks::InstallTask.method(:run_system_command))
          effective_run_options = Kettle::Jem::Tasks::TemplateTask.env_run_options(env || {}).merge(run_options || {})
          prepare_run_options = effective_run_options.merge(
            only: PREPARE_ONLY_PATHS,
            skip_lock_normalization: true
          )
          report = Kettle::Jem.apply_project(project_root, env: env, run_options: prepare_run_options)
          setup_env = Kettle::Jem::Tasks::InstallTask.setup_command_env(project_root, env)
          events = Kettle::Jem.event_stream_from_options(effective_run_options)
          Kettle::Jem.emit_step_event(
            events,
            "command_step",
            {name: "bundle_update_templating_bootstrap", status: "started", command: bundle_update_templating_bootstrap_command(project_root)},
            phase: "prepare"
          )
          update_step = Kettle::Jem::Tasks::InstallTask.run_command_step(
            "bundle_update_templating_bootstrap",
            bundle_update_templating_bootstrap_command(project_root),
            project_root: project_root,
            env: setup_env,
            quiet: Kettle::Jem::DecisionPolicy.value_to_boolean(effective_run_options[:quiet]),
            command_runner: command_runner
          )
          Kettle::Jem.emit_step_event(events, "command_step", update_step, phase: "prepare")
          Kettle::Jem.emit_step_event(
            events,
            "command_step",
            {name: "bundle_install", status: "started", command: %w[bundle install]},
            phase: "prepare"
          )
          bundle_step = Kettle::Jem::Tasks::InstallTask.run_command_step(
            "bundle_install",
            %w[bundle install],
            project_root: project_root,
            env: setup_env,
            quiet: Kettle::Jem::DecisionPolicy.value_to_boolean(effective_run_options[:quiet]),
            command_runner: command_runner
          )
          Kettle::Jem.emit_step_event(events, "command_step", bundle_step, phase: "prepare")

          final_report = report.merge(
            mode: "prepare",
            prepared: update_step.fetch(:status) == "succeeded" &&
              bundle_step.fetch(:status) == "succeeded",
            prepare_only: PREPARE_ONLY_PATHS,
            prepare_steps: [update_step, bundle_step],
            changed_files: (
              report.fetch(:changed_files, []) +
                update_step.fetch(:changed_files, []) +
                bundle_step.fetch(:changed_files, [])
            ).uniq.sort,
            diagnostics: report.fetch(:diagnostics, []) + [{
              severity: "advisory",
              message: "kettle:jem:prepare applied the templating dependency bootstrap payload, " \
                "updated critical templating gems, and ran bundle install."
            }]
          )
          Kettle::Jem.emit_summary_event(events, final_report)
          final_report
        end

        def bundle_update_templating_bootstrap_command(project_root = Dir.pwd)
          %w[bundle update] + CRITICAL_TEMPLATING_GEMS + locked_templating_gems(project_root)
        end

        def locked_templating_gems(project_root)
          lock_path = File.join(project_root.to_s, "Gemfile.lock")
          return [] unless File.file?(lock_path)

          locked_names = Bundler::LockfileParser.new(Bundler.read_file(lock_path)).specs.map(&:name)
          LOCKED_TEMPLATING_GEMS & locked_names
        end
      end
    end
  end
end
