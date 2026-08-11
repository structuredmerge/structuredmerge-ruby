# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"

module Kettle
  module Jem
    module CLI
      USAGE = <<~USAGE
        Usage:
          kettle-jem [PROJECT_ROOT] [--accept-config] [--bootstrap-mode] [--changelog|--no-changelog] [--quiet|--verbose]
          kettle-jem setup [PROJECT_ROOT] [--accept-config] [--bootstrap-mode] [--changelog|--no-changelog] [--quiet|--verbose]
          kettle-jem prepare [PROJECT_ROOT] [--json|--events[=TYPE,...]] [--report PATH] [--accept|--force] [--changelog|--no-changelog] [--quiet|--verbose]
          kettle-jem plan [PROJECT_ROOT] [--json|--events[=TYPE,...]] [--report PATH] [--accept|--force|--interactive] [--failure-mode MODE] [--prompt-answer ID=ACTION]
          kettle-jem apply [PROJECT_ROOT] [--json|--events[=TYPE,...]] [--report PATH] [--accept|--force|--interactive] [--failure-mode MODE] [--prompt-answer ID=ACTION] [--changelog|--no-changelog]
          kettle-jem template [PROJECT_ROOT] [--json|--events[=TYPE,...]] [--report PATH] [--accept|--force|--interactive] [--failure-mode MODE] [--prompt-answer ID=ACTION] [--changelog|--no-changelog]
          kettle-jem install [PROJECT_ROOT] [--json|--events[=TYPE,...]] [--report PATH] [--accept|--force|--interactive] [--failure-mode MODE] [--prompt-answer ID=ACTION] [--changelog|--no-changelog]
          kettle-jem manifest [PROJECT_ROOT] [--json]
          kettle-jem selftest [PROJECT_ROOT] [--json] [--report PATH] [--destination PATH] [--template-root PATH] [--selftest-output PATH]
          kettle-jem version
      USAGE

      module_function

      def run(argv = ARGV, env: ENV, out: $stdout, err: $stderr)
        command, args = normalize_command(argv)
        return print_help(out) if command == "help"
        return print_version(out) if command == "version"

        options = parse_options(args)
        project_root = File.expand_path(options.fetch(:project_root) || Dir.pwd)
        ensure_not_running_from_own_context!(command, project_root)
        print_debug_snapshot(command, project_root: project_root, env: env, err: err) if debug_enabled?(env)
        options[:event_io] = out
        result = execute(command, project_root: project_root, env: env, options: options)
        write_report(options[:report_path], result) if options[:report_path]
        print_result(command, result, options: options, out: out)
        0
      rescue OptionParser::ParseError, ArgumentError => error
        err.puts(error.message)
        err.puts(USAGE)
        2
      rescue => error
        err.puts("#{error.class}: #{error.message}")
        err.puts(error.backtrace.join("\n")) if debug_enabled?(env)
        1
      end

      def normalize_command(argv)
        args = Array(argv).dup
        command = args.shift
        return ["help", []] if command == "help" || command == "--help" || command == "-h"
        return ["setup", []] if command.nil?

        unless command_allowed?(command)
          args.unshift(command)
          command = "setup"
        end
        command = "version" if command == "version" || command == "--version" || command == "-v"
        raise ArgumentError, "Unsupported kettle-jem command #{command.inspect}" unless command_allowed?(command)

        [command, args]
      end

      def command_allowed?(command)
        %w[setup prepare plan apply template install manifest selftest help version].include?(command)
      end

      def parse_options(args)
        options = {
          json: false,
          events: false,
          run_options: {}
        }
        parser = OptionParser.new do |opts|
          opts.banner = USAGE
          opts.on("--json", "Print the full machine-readable result as JSON.") { options[:json] = true }
          opts.on("--events[=TYPES]", "Print newline-delimited JSON progress events. Optional comma-separated TYPES filter.") do |value|
            options[:events] = true
            options[:event_types] = value if value
          end
          opts.on("--report PATH", "Write the full machine-readable result to PATH as JSON.") do |path|
            options[:report_path] = path
          end
          opts.on("--accept", "Use non-interactive default decisions.") { options[:run_options][:accept] = true }
          opts.on("--force", "Alias for --accept.") { options[:run_options][:force] = true }
          opts.on("--interactive", "Use interactive decision mode when supported.") do
            options[:run_options][:interactive] = true
          end
          opts.on("--quiet", "Suppress normal text output.") do
            options[:run_options][:quiet] = true
          end
          opts.on("--verbose", "Request verbose diagnostics where supported.") do
            options[:run_options][:verbose] = true
          end
          opts.on("--failure-mode MODE", "Set the template failure mode.") do |mode|
            options[:run_options][:failure_mode] = mode
          end
          opts.on("--prompt-answer ID=ACTION", "Answer an interactive decision prompt.") do |value|
            id, action = value.to_s.split("=", 2)
            raise OptionParser::InvalidArgument, "--prompt-answer must use ID=ACTION" if id.to_s.empty? || action.to_s.empty?

            (options[:run_options][:prompt_answers] ||= {})[id] = action
            options[:run_options][:interactive] = true
          end
          opts.on("--allowed VALUE", "Set the env-file change policy.") do |value|
            options[:run_options][:allowed] = value
          end
          opts.on("--hook-templates VALUE", "Set hook template handling.") do |value|
            options[:run_options][:hook_templates] = value
          end
          opts.on("--hook_templates VALUE", "Alias for --hook-templates.") do |value|
            options[:run_options][:hook_templates] = value
          end
          opts.on("--git-drivers VALUE", "Set Git diff/merge driver setup handling.") do |value|
            options[:run_options][:git_drivers] = value
          end
          opts.on("--git_drivers VALUE", "Alias for --git-drivers.") do |value|
            options[:run_options][:git_drivers] = value
          end
          opts.on("--dry-run", "Plan supported post-template actions without applying them.") do
            options[:run_options][:dry_run] = true
          end
          opts.on("--check", "Verify supported post-template setup without changing files.") do
            options[:run_options][:git_drivers] = "check"
          end
          opts.on("--undo", "Undo supported post-template setup.") do
            options[:run_options][:git_drivers] = "undo"
          end
          opts.on("--only PATHS", "Restrict templating to comma-separated paths or patterns.") do |value|
            (options[:run_options][:only] ||= []) << value
          end
          opts.on("--include PATHS", "Include comma-separated paths or patterns.") do |value|
            (options[:run_options][:include] ||= []) << value
          end
          opts.on("--skip-commit", "Skip bootstrap commit behavior.") do
            options[:run_options][:skip_commit] = true
          end
          opts.on("--skip-drift-check", "Skip post-apply duplicate drift checking.") do
            options[:run_options][:skip_drift_check] = true
          end
          opts.on("--skip-duplicate-drift", "Alias for --skip-drift-check.") do
            options[:run_options][:skip_drift_check] = true
          end
          opts.on("--skip-rubocop-gradual", "Skip post-template RuboCop Gradual autocorrect.") do
            options[:run_options][:skip_rubocop_gradual] = true
          end
          opts.on("--[no-]changelog", "Add a Changed entry summarizing actual template changes (default).") do |value|
            options[:run_options][:skip_changelog] = !value
          end
          opts.on("--skip-binstubs", "Skip post-template curated Bundler binstub generation.") do
            options[:run_options][:skip_binstubs] = true
          end
          opts.on("--checksums VALUE", "Set checksum skip mode: template, dest, ignore-template, ignore-dest, or off.") do |value|
            options[:run_options][:checksums] = value
          end
          opts.on("--ignore-checksums", "Alias for --checksums off.") do
            options[:run_options][:checksums] = "off"
          end
          opts.on("--accept-config", "Accept first-run template config bootstrap.") do
            options[:run_options][:accept_config] = true
          end
          opts.on("--bootstrap-mode", "Force first-run bootstrap mode.") do
            options[:run_options][:bootstrap_mode] = true
          end
          opts.on("--template-profile PROFILE", "Use a packaged template profile.") do |value|
            options[:run_options][:template_profile] = value
          end
          opts.on("--shimmed-gem GEM", "Runtime gem required by the shim profile.") do |value|
            options[:run_options][:shimmed_gem] = value
          end
          opts.on("--shimmed-require REQUIRE", "Require path loaded by the shim profile.") do |value|
            options[:run_options][:shimmed_require] = value
          end
          opts.on("--destination PATH", "Selftest destination root.") do |path|
            options[:destination_root] = path
          end
          opts.on("--template-root PATH", "Selftest template root.") do |path|
            options[:template_root] = path
          end
          opts.on("--selftest-output PATH", "Selftest output root.") do |path|
            options[:selftest_output_root] = path
          end
          opts.on("--min-divergence-threshold PERCENT", "Fail selftest when divergence exceeds PERCENT.") do |value|
            options[:min_divergence_threshold] = Float(value)
          end
        end
        remaining = parser.parse(args)
        raise ArgumentError, "Expected at most one PROJECT_ROOT" if remaining.length > 1
        raise OptionParser::InvalidOption, "--events cannot be combined with --json" if options[:events] && options[:json]

        options[:project_root] = remaining.first
        options
      end

      def execute(command, project_root:, env:, options:)
        run_options = options.fetch(:run_options)
        if options[:events]
          run_options[:event_stream] = Kettle::Jem.event_stream(
            options.fetch(:event_io),
            types: options[:event_types]
          )
        end
        result = case command
        when "setup"
          Kettle::Jem.setup_project(project_root, env: env, run_options: run_options)
        when "prepare"
          Kettle::Jem::Tasks::PrepareTask.run(project_root: project_root, env: env, run_options: run_options)
        when "plan"
          Kettle::Jem.plan_project(project_root, env: env, run_options: run_options)
        when "apply"
          Kettle::Jem.apply_project(project_root, env: env, run_options: run_options)
        when "template"
          if scoped_template_run?(run_options)
            Kettle::Jem::Tasks::TemplateTask.run(project_root: project_root, env: env, run_options: run_options)
          else
            Kettle::Jem::Tasks::InstallTask.run(project_root: project_root, env: env, run_options: run_options)
          end
        when "install"
          Kettle::Jem::Tasks::InstallTask.run(project_root: project_root, env: env, run_options: run_options)
        when "manifest"
          Kettle::Jem.template_manifest(project_root: project_root)
        when "selftest"
          Kettle::Jem::Tasks::SelfTestTask.run(
            project_root: project_root,
            destination_root: options[:destination_root] || project_root,
            template_root: options[:template_root],
            output_root: options[:selftest_output_root],
            min_divergence_threshold: options[:min_divergence_threshold]
          )
        else
          raise ArgumentError, "Unsupported kettle-jem command #{command.inspect}"
        end
        return result unless %w[setup prepare apply template install].include?(command)

        Kettle::Jem::MaintenanceChangelog.record_template_run(
          project_root: project_root,
          report: result,
          run_options: run_options,
          label: (command == "prepare") ? "Prepare project for kettle-jem templates" : "Apply kettle-jem templates"
        )
      end

      def scoped_template_run?(run_options)
        run_options = run_options.to_h
        run_options.key?(:only) || run_options.key?(:include)
      end

      def ensure_not_running_from_own_context!(command, project_root)
        return if %w[help version].include?(command)

        current_root = canonical_path(Dir.pwd)
        own_root = canonical_path(File.expand_path("../../..", __dir__))
        target_root = canonical_path(project_root)
        return unless current_root == own_root && target_root != own_root

        raise ArgumentError,
          "Refusing to run kettle-jem from its own project root against #{project_root}; " \
          "run from the destination repository so its environment is loaded, or target kettle-jem itself."
      end

      def canonical_path(path)
        File.realpath(path)
      rescue Errno::ENOENT
        File.expand_path(path)
      end

      def print_result(command, result, options:, out:)
        return if options[:events]
        return if options.fetch(:run_options, {})[:quiet] && !options[:json]

        if options[:json]
          out.puts(JSON.pretty_generate(result))
          return
        end

        case command
        when "setup"
          out.puts("setup: #{result.fetch(:setup_status)}")
          result.fetch(:changed_files, []).each { |path| out.puts("  #{path}") }
          result.fetch(:diagnostics, []).each do |diagnostic|
            message = diagnostic.is_a?(Hash) ? diagnostic[:message] || diagnostic["message"] : diagnostic
            out.puts("  #{message}") unless message.to_s.empty?
          end
        when "manifest"
          entries = result.fetch(:entries, [])
          out.puts("template manifest: #{entries.length} entr#{(entries.length == 1) ? "y" : "ies"}")
        when "selftest"
          comparison = result.fetch(:comparison, {})
          divergent = comparison.fetch(:changed, []).size +
            comparison.fetch(:added, []).size +
            comparison.fetch(:removed, []).size
          out.puts("selftest: #{divergent} divergent file#{"s" unless divergent == 1}")
          out.puts("  report: #{result.fetch(:report_path)}") if result[:report_path]
        else
          changed_files = result.fetch(:changed_files, [])
          out.puts("#{result.fetch(:mode)}: #{changed_files.length} changed file#{"s" unless changed_files.length == 1}")
          changed_files.each { |path| out.puts("  #{path}") }
          Array(result[:warnings]).map(&:to_s).reject(&:empty?).uniq.each do |warning|
            out.puts("  warning: #{warning}")
          end
        end
      end

      def write_report(path, result)
        FileUtils.mkdir_p(File.dirname(File.expand_path(path)))
        File.write(path, "#{JSON.pretty_generate(result)}\n")
      end

      def print_debug_snapshot(command, project_root:, env:, err:)
        err.puts("[kettle-jem] DEBUG: early environment snapshot")
        err.puts("  command=#{command.inspect}")
        err.puts("  project_root=#{project_root.inspect}")
        %w[DEBUG KETTLE_JEM_DEBUG KETTLE_DEV_DEBUG KETTLE_DEV_DEV BUNDLE_GEMFILE BUNDLE_PATH GEM_HOME GEM_PATH RUBYOPT RUBYLIB PWD].each do |key|
          err.puts("  #{key}=#{env_value(env, key).inspect}")
        end
      end

      def debug_enabled?(env)
        %w[DEBUG KETTLE_JEM_DEBUG KETTLE_DEV_DEBUG].any? { |key| env_true?(env_value(env, key)) }
      end

      def env_true?(value)
        /\A(?:true|t|yes|y|on|1)\z/i.match?(value.to_s.strip)
      end

      def env_value(env, key)
        env.fetch(key, nil)
      rescue KeyError
        nil
      end

      def print_help(out)
        out.puts(USAGE)
        0
      end

      def print_version(out)
        out.puts(Kettle::Jem::Version::VERSION)
        0
      end
    end
  end
end
