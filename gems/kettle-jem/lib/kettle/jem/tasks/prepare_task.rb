# frozen_string_literal: true

require "bundler"
require "kettle/dev/lockfile_reset"
require "pathname"
require "shellwords"

module Kettle
  module Jem
    module Tasks
      module PrepareTask
        PREPARE_ONLY_PATHS = [
          Kettle::Jem::KETTLE_CONFIG_PATH,
          "Gemfile",
          # Gemfile evaluates these fragments immediately.  Preparing only the
          # templating pair leaves a newly migrated project with references to
          # files that do not exist yet, so Bundler cannot perform the bootstrap.
          "gemfiles/modular/**",
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
          setup_env["K_JEM_TEMPLATING"] = "true" if local_path_development_env?(env)
          events = Kettle::Jem.event_stream_from_options(effective_run_options)
          reset_step = reset_release_lockfiles_step(
            project_root: project_root,
            setup_env: setup_env,
            quiet: Kettle::Jem::DecisionPolicy.value_to_boolean(effective_run_options[:quiet]),
            command_runner: command_runner,
            events: events
          )
          Kettle::Jem.emit_step_event(events, "command_step", reset_step, phase: "prepare")
          bootstrap_name = templating_bootstrap_step_name(project_root)
          bootstrap_command = templating_bootstrap_command(project_root)
          Kettle::Jem.emit_step_event(
            events,
            "command_step",
            {name: bootstrap_name, status: "started", command: bootstrap_command},
            phase: "prepare"
          )
          bootstrap_step = templating_bootstrap_step(
            bootstrap_name: bootstrap_name,
            bootstrap_command: bootstrap_command,
            project_root: project_root,
            setup_env: setup_env,
            quiet: Kettle::Jem::DecisionPolicy.value_to_boolean(effective_run_options[:quiet]),
            command_runner: command_runner,
            events: events
          )
          Kettle::Jem.emit_step_event(events, "command_step", bootstrap_step, phase: "prepare")
          bundle_step = bundle_install_after_bootstrap_step(
            project_root: project_root,
            setup_env: setup_env,
            quiet: Kettle::Jem::DecisionPolicy.value_to_boolean(effective_run_options[:quiet]),
            command_runner: command_runner,
            events: events,
            bootstrap_command: bootstrap_command
          )
          Kettle::Jem.emit_step_event(events, "command_step", bundle_step, phase: "prepare")

          final_report = report.merge(
            mode: "prepare",
            prepared: bootstrap_step.fetch(:status) == "succeeded" &&
              %w[skipped succeeded].include?(reset_step.fetch(:status)) &&
              %w[skipped succeeded].include?(bundle_step.fetch(:status)),
            prepare_only: PREPARE_ONLY_PATHS,
            prepare_steps: [reset_step, bootstrap_step, bundle_step],
            changed_files: (
              report.fetch(:changed_files, []) +
                reset_step.fetch(:changed_files, []) +
                bootstrap_step.fetch(:changed_files, []) +
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

        def reset_release_lockfiles_step(project_root:, setup_env:, quiet:, command_runner:, events:)
          if local_path_development_env?(setup_env)
            return {
              name: "reset_release_lockfiles",
              command: %w[kettle-reset release-lockfiles],
              status: "skipped",
              reason: "local_path_development_env"
            }
          end

          reset_command_runner = lambda do |command|
            command_runner.call(Shellwords.split(command), chdir: project_root, env: setup_env, quiet: quiet)
          end
          resetter = Kettle::Dev::LockfileReset.new(
            root: project_root,
            command_runner: reset_command_runner
          )
          paths = resetter.lockfile_paths
          if paths.empty?
            return {
              name: "reset_release_lockfiles",
              command: %w[kettle-reset release-lockfiles],
              status: "skipped",
              reason: "no_release_lockfiles"
            }
          end

          Kettle::Jem.emit_step_event(
            events,
            "command_step",
            {name: "reset_release_lockfiles", status: "started", command: %w[kettle-reset release-lockfiles]},
            phase: "prepare"
          )
          before = snapshot_files(paths)
          resetter.reset(Kettle::Dev::LockfileReset::RELEASE_LOCKFILES_TARGET)
          changed_files = changed_files_since(project_root, before)
          {
            name: "reset_release_lockfiles",
            command: %w[kettle-reset release-lockfiles],
            status: "succeeded",
            changed_files: changed_files,
            quiet: quiet
          }
        end

        def local_path_development_env?(env)
          (env || {}).any? do |key, raw_value|
            next false unless key.to_s.end_with?("_DEV")

            value = raw_value.to_s.strip
            !value.empty? && !Kettle::Jem::DecisionPolicy.falsey?(value)
          end
        end

        def bundle_update_templating_bootstrap_command(project_root = Dir.pwd)
          %w[bundle update] + CRITICAL_TEMPLATING_GEMS + locked_templating_gems(project_root)
        end

        def templating_bootstrap_command(project_root = Dir.pwd)
          return %w[bundle install] unless templating_bootstrap_lockfile_ready?(project_root)

          bundle_update_templating_bootstrap_command(project_root)
        end

        def templating_bootstrap_step_name(project_root = Dir.pwd)
          return "bundle_install_templating_bootstrap" unless templating_bootstrap_lockfile_ready?(project_root)

          "bundle_update_templating_bootstrap"
        end

        def templating_bootstrap_lockfile_ready?(project_root)
          lock_path = File.join(project_root.to_s, "Gemfile.lock")
          return false unless File.file?(lock_path)

          locked_gem_names(project_root).then do |names|
            CRITICAL_TEMPLATING_GEMS.all? { |gem_name| names.include?(gem_name) }
          end
        rescue Bundler::LockfileError
          false
        end

        def bundle_install_after_bootstrap_step(project_root:, setup_env:, quiet:, command_runner:, events:, bootstrap_command:)
          if bootstrap_command == %w[bundle install]
            return {
              name: "bundle_install",
              command: %w[bundle install],
              status: "skipped",
              reason: "already_ran_as_templating_bootstrap"
            }
          end

          Kettle::Jem.emit_step_event(
            events,
            "command_step",
            {name: "bundle_install", status: "started", command: %w[bundle install]},
            phase: "prepare"
          )
          Kettle::Jem::Tasks::InstallTask.run_command_step(
            "bundle_install",
            %w[bundle install],
            project_root: project_root,
            env: setup_env,
            quiet: quiet,
            command_runner: command_runner
          )
        end

        def templating_bootstrap_step(bootstrap_name:, bootstrap_command:, project_root:, setup_env:, quiet:, command_runner:, events:)
          Kettle::Jem::Tasks::InstallTask.run_command_step(
            bootstrap_name,
            bootstrap_command,
            project_root: project_root,
            env: setup_env,
            quiet: quiet,
            command_runner: command_runner
          )
        rescue Kettle::Jem::Error => error
          recovery_step = repair_unsupported_templating_platform_step(
            error: error,
            project_root: project_root,
            setup_env: setup_env,
            quiet: quiet,
            command_runner: command_runner,
            events: events
          )
          raise unless recovery_step

          Kettle::Jem::Tasks::InstallTask.run_command_step(
            bootstrap_name,
            bootstrap_command,
            project_root: project_root,
            env: setup_env,
            quiet: quiet,
            command_runner: command_runner
          ).merge(
            recovered: true,
            recovery: recovery_step,
            changed_files: recovery_step.fetch(:changed_files, [])
          )
        end

        def repair_unsupported_templating_platform_step(error:, project_root:, setup_env:, quiet:, command_runner:, events:)
          gem_name, platform = unsupported_templating_platform(error.message)
          return nil unless gem_name && locked_platforms(project_root).include?(platform)

          command = ["bundle", "lock", "--remove-platform=#{platform}"]
          name = "bundle_lock_remove_unsupported_platform"
          Kettle::Jem.emit_step_event(
            events,
            "command_step",
            {name: name, status: "started", command: command, gem: gem_name, platform: platform},
            phase: "prepare"
          )
          step = Kettle::Jem::Tasks::InstallTask.run_command_step(
            name,
            command,
            project_root: project_root,
            env: setup_env,
            quiet: quiet,
            command_runner: command_runner
          ).merge(changed_files: ["Gemfile.lock"])
          Kettle::Jem.emit_step_event(events, "command_step", step, phase: "prepare")
          step
        end

        def unsupported_templating_platform(message)
          # Bundler exposes this compatibility failure only as stderr text; match
          # its exact quoted diagnostic rather than guessing from lockfile content.
          match = /Could not find gem '([^']+)' with platform '([^']+)'/.match(message.to_s)
          return [nil, nil] unless match

          gem_name = match[1]
          return [nil, nil] unless LOCKED_TEMPLATING_GEMS.include?(gem_name)

          [gem_name, match[2]]
        end

        def locked_templating_gems(project_root)
          LOCKED_TEMPLATING_GEMS & locked_gem_names(project_root)
        end

        def locked_gem_names(project_root)
          lock_path = File.join(project_root.to_s, "Gemfile.lock")
          return [] unless File.file?(lock_path)

          Bundler::LockfileParser.new(Bundler.read_file(lock_path)).specs.map(&:name)
        end

        def locked_platforms(project_root)
          lock_path = File.join(project_root.to_s, "Gemfile.lock")
          return [] unless File.file?(lock_path)

          Bundler::LockfileParser.new(Bundler.read_file(lock_path)).platforms.map(&:to_s)
        end

        def snapshot_files(paths)
          paths.each_with_object({}) do |path, snapshot|
            snapshot[path] = File.file?(path) ? File.binread(path) : nil
          end
        end

        def changed_files_since(project_root, snapshot)
          snapshot.filter_map do |path, before|
            after = File.file?(path) ? File.binread(path) : nil
            next if before == after

            Pathname.new(path).relative_path_from(Pathname.new(project_root)).to_s
          end.sort
        end
      end
    end
  end
end
