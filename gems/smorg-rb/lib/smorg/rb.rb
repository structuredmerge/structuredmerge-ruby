# frozen_string_literal: true

require 'English'
require 'bash/merge'
require 'go-merge'
require 'html/merge'
require 'ast/merge'
require 'ast-merge-git'
require 'diff/lcs'
require 'diff/lcs/hunk'
require 'dotenv/merge'
require 'json'
require 'json-merge'
require 'kettle/jem'
require 'kettle/jem/tasks/install_task'
require 'markdown/merge'
require 'plain-merge'
require 'rbs/merge'
require 'toml/merge'
require 'typescript/merge'
require 'prism/merge'
require 'psych/merge'
require_relative 'rb/version'

module Smorg
  module RB
    EXIT_SUCCESS = 0
    EXIT_UNRESOLVED_CONFLICT = 1
    EXIT_USER_ERROR = 2
    EXIT_INTERNAL_ERROR = 3
    REVIEW_DIFF_CONTEXT_LINES = 3

    module_function

    def run(args, stdout: $stdout, stderr: $stderr)
      command, *rest = args
      case command
      when 'merge-driver'
        run_merge_driver(rest, stdout, stderr)
      when 'diff-driver'
        run_diff_driver(rest, stdout, stderr)
      when 'conflicts'
        run_conflicts(rest, stdout, stderr)
      when 'languages'
        run_languages(rest, stdout, stderr)
      when 'git'
        run_git(rest, stdout, stderr)
      when 'help', '-h', '--help'
        print_usage(stdout)
        EXIT_SUCCESS
      else
        stderr.puts("unknown command #{command.inspect}") if command
        print_usage(stderr)
        EXIT_USER_ERROR
      end
    end

    def print_usage(out)
      out.puts('usage: smorg-rb merge-driver [--path-name PATH] [--output PATH] [--report PATH] [--strict] [--fallback=none|line|local|full-file] %O %A %B [%P]')
      out.puts('       smorg-rb merge-driver --ancestor %O --current %A --other %B --path-name %P')
      out.puts('       smorg-rb diff-driver [--path-name PATH] OLD NEW')
      out.puts('       smorg-rb diff-driver PATH OLD-FILE OLD-HEX OLD-MODE NEW-FILE NEW-HEX NEW-MODE [OLD-PREFIX NEW-PREFIX]')
      out.puts('       smorg-rb conflicts diff [--path-name PATH] [--exit-code] FILE')
      out.puts('       smorg-rb languages --gitattributes')
      out.puts('       smorg-rb git install [--scope local|global|include-file] [--profile semantic-diff|builtin-diff] [--check] [--undo] [--dry-run] [--json]')
    end

    def run_git(args, stdout, stderr)
      subcommand, *rest = args
      return git_usage(stderr) unless subcommand == 'install'

      options = parse_git_install_options(rest, stderr)
      return EXIT_USER_ERROR unless options

      run_options = git_install_run_options(options)
      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(Dir.pwd, run_options)
      step = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
        [step],
        project_root: Dir.pwd,
        env: ENV.to_h,
        run_options: run_options,
        command_runner: Kettle::Jem::Tasks::InstallTask.method(:run_system_command)
      ).first
      report = {
        report_version: 1,
        ok: step.fetch(:status) != 'failed',
        profile: step.fetch(:profile, 'semantic-diff'),
        scope: step.fetch(:scope, run_options.fetch(:git_drivers, 'local')),
        install_steps: [step],
        missing: step.fetch(:missing, [])
      }
      if options[:json]
        stdout.puts(JSON.pretty_generate(report))
      else
        stdout.puts("git install: #{step.fetch(:status)} #{report.fetch(:profile)} #{report.fetch(:scope)}")
        step.fetch(:diagnostics, []).each do |diagnostic|
          stdout.puts("  #{diagnostic.fetch(:message)}") if diagnostic[:message]
        end
      end
      report.fetch(:ok) ? EXIT_SUCCESS : EXIT_USER_ERROR
    rescue Kettle::Jem::Error => e
      stderr.puts(e.message)
      EXIT_USER_ERROR
    end

    def git_usage(stderr)
      stderr.puts('usage: smorg-rb git install [--scope local|global|include-file] [--profile semantic-diff|builtin-diff] [--check] [--undo] [--dry-run] [--json]')
      EXIT_USER_ERROR
    end

    def parse_git_install_options(args, stderr)
      options = { scope: 'local', profile: 'semantic-diff', json: false, dry_run: false }
      until args.empty?
        value = args.shift
        case value
        when '--scope'
          options[:scope] = args.shift.to_s
        when '--profile'
          options[:profile] = args.shift.to_s
        when '--check'
          options[:check] = true
        when '--undo'
          options[:undo] = true
        when '--dry-run'
          options[:dry_run] = true
        when '--json'
          options[:json] = true
        else
          stderr.puts("unknown git install option #{value.inspect}")
          return nil
        end
      end
      options
    end

    def git_install_run_options(options)
      git_drivers = if options[:check]
                      'check'
                    elsif options[:undo]
                      'undo'
                    elsif options.fetch(:scope) == 'global'
                      'global'
                    elsif options.fetch(:scope) == 'include-file'
                      'include-file'
                    elsif options.fetch(:profile) == 'builtin-diff'
                      'builtin-diff'
                    else
                      'semantic-diff'
                    end
      { git_drivers: git_drivers, dry_run: options[:dry_run] }.compact
    end

    def run_merge_driver(args, stdout, stderr)
      options = parse_merge_driver_options(args, stderr)
      return EXIT_USER_ERROR unless options

      ancestor_source = File.read(options[:ancestor])
      current_source = File.read(options[:current])
      other_source = File.read(options[:other])

      effective_path = options[:path_name] || options[:current]
      settings = load_path_settings(effective_path)
      options[:profile_id] ||= settings[:profile_id]
      options[:require_profile_status] ||= settings[:require_profile_status]
      profile_exit = report_and_enforce_profile(options, stdout, stderr)
      return profile_exit unless profile_exit == EXIT_SUCCESS

      fallback_policy = options[:strict] ? 'none' : options[:fallback]
      result = merge_by_path(effective_path, settings[:language], settings[:conflict_marker_size], fallback_policy,
                             ancestor_source, current_source, other_source)
      fallbacks = []
      if merge_driver_fallback_eligible?(result, options)
        result, fallbacks = apply_merge_fallbacks(
          result,
          options[:fallback],
          settings[:conflict_marker_size],
          ancestor_source,
          current_source,
          other_source
        )
      end
      output = result[:output]
      unless result[:ok]
        print_diagnostics(stderr, result)
        unless options[:strict] || options[:fallback] == 'none'
          output ||= full_file_conflict_output(settings[:conflict_marker_size], ancestor_source, current_source,
                                               other_source)
        end
        if output && !result[:output] && !options[:strict] && options[:fallback] != 'none'
          fallbacks << {
            mode: 'full_file',
            requested_mode: options[:fallback],
            reason: fallback_reason(result.fetch(:diagnostics, [])),
            applied: true
          }
        end
        report_exit = write_merge_driver_machine_report(options[:report], effective_path, false,
                                                        EXIT_UNRESOLVED_CONFLICT, fallbacks, result, stderr)
        return report_exit unless report_exit == EXIT_SUCCESS
        return EXIT_UNRESOLVED_CONFLICT if options[:check_only]

        File.write(options[:output] || options[:current], output) if output
        return EXIT_UNRESOLVED_CONFLICT
      end
      unless output
        stderr.puts('merge completed without output')
        return EXIT_INTERNAL_ERROR
      end

      if options[:check_only]
        exit_code = options[:exit_code] && output != current_source ? EXIT_UNRESOLVED_CONFLICT : EXIT_SUCCESS
        report_exit = write_merge_driver_machine_report(options[:report], effective_path, true, exit_code, fallbacks,
                                                        result, stderr)
        return report_exit unless report_exit == EXIT_SUCCESS

        return exit_code
      end

      File.write(options[:output] || options[:current], output)
      report_exit = write_merge_driver_machine_report(options[:report], effective_path, true, EXIT_SUCCESS, fallbacks,
                                                      result, stderr)
      return report_exit unless report_exit == EXIT_SUCCESS

      EXIT_SUCCESS
    rescue Errno::ENOENT, Errno::EACCES => e
      stderr.puts("file error: #{e.message}")
      EXIT_USER_ERROR
    rescue StandardError => e
      stderr.puts("internal error: #{e.message}")
      EXIT_INTERNAL_ERROR
    end

    def apply_merge_fallbacks(result, requested_mode, marker_size, ancestor_source, current_source, other_source)
      fallback_reason_value = fallback_reason(result.fetch(:diagnostics, []))
      git_result = merge_git_file_fallback(marker_size, ancestor_source, current_source, other_source)
      if git_result[:output]
        return [
          merge_fallback_result(result, git_result),
          [
            {
              mode: 'git_merge_file',
              requested_mode: requested_mode,
              reason: fallback_reason_value,
              applied: true
            }
          ]
        ]
      end

      plain_result = merge_plain_fallback(other_source, current_source)
      if plain_result[:ok] && plain_result[:output]
        return [
          merge_fallback_result(result, plain_result),
          [
            {
              mode: 'git_merge_file',
              requested_mode: requested_mode,
              reason: fallback_reason_value,
              applied: false
            },
            {
              mode: 'plain_text',
              requested_mode: requested_mode,
              reason: fallback_reason(git_result.fetch(:diagnostics, [])),
              applied: true
            }
          ]
        ]
      end

      [result, []]
    end

    def merge_driver_fallback_eligible?(result, options)
      return false if result[:ok] || options[:strict] || options[:fallback] == 'none'

      result.fetch(:diagnostics, []).any? do |diagnostic|
        (diagnostic[:category] || diagnostic['category']).to_s == 'unsupported_language'
      end
    end

    def merge_plain_fallback(other_source, current_source)
      Plain::Merge.merge_text(other_source, current_source)
    rescue StandardError => e
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'plain_text_fallback_error', message: e.message }],
        policies: []
      }
    end

    def merge_git_file_fallback(marker_size, ancestor_source, current_source, other_source)
      require 'tempfile'

      files = Array.new(3) { Tempfile.new('smorg-rb-merge-file') }
      files[0].write(current_source)
      files[1].write(ancestor_source)
      files[2].write(other_source)
      files.each(&:flush)
      output = IO.popen(
        [
          'git',
          'merge-file',
          '-p',
          '-L',
          'ours',
          '-L',
          'base',
          '-L',
          'theirs',
          "--marker-size=#{marker_size}",
          files[0].path,
          files[1].path,
          files[2].path
        ],
        err: %i[child out],
        &:read
      )
      {
        ok: $CHILD_STATUS.success?,
        diagnostics: if $CHILD_STATUS.success?
                       []
                     else
                       [{ severity: 'error', category: 'git_merge_file_conflict',
                          message: 'git merge-file reported unresolved conflicts' }]
                     end,
        output: output,
        policies: []
      }
    rescue Errno::ENOENT => e
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'git_merge_file_unavailable', message: e.message }],
        policies: []
      }
    ensure
      files&.each do |file|
        file.close
        file.unlink
      end
    end

    def merge_fallback_result(original_result, fallback_result)
      original_diagnostics = original_result.fetch(:diagnostics, [])
      fallback_diagnostics = fallback_result.fetch(:diagnostics, [])
      {
        **original_result,
        ok: fallback_result[:ok],
        diagnostics: original_diagnostics + fallback_diagnostics,
        output: fallback_result[:output],
        policies: fallback_result.fetch(:policies, original_result.fetch(:policies, []))
      }
    end

    def full_file_conflict_output(marker_size, ancestor_source, current_source, other_source)
      marker_size = marker_size.to_i
      marker_size = 7 unless marker_size.positive?
      [
        "#{'<' * marker_size} ours",
        current_source,
        "#{'|' * marker_size} base",
        ancestor_source,
        '=' * marker_size,
        other_source,
        "#{'>' * marker_size} theirs",
        ''
      ].join("\n")
    end

    def parse_merge_driver_options(args, stderr)
      options = { strict: false, fallback: 'full-file', check_only: false, exit_code: false, profile_report: false }
      positionals = []
      index = 0
      while index < args.length
        value = args[index]
        case value
        when '--ancestor'
          index += 1
          options[:ancestor] = args[index]
        when '--current'
          index += 1
          options[:current] = args[index]
        when '--other'
          index += 1
          options[:other] = args[index]
        when '--path-name'
          index += 1
          options[:path_name] = args[index]
        when '--output'
          index += 1
          options[:output] = args[index]
        when '--report'
          index += 1
          options[:report] = args[index]
        when '--strict'
          options[:strict] = true
        when '--check-only'
          options[:check_only] = true
        when '--exit-code'
          options[:exit_code] = true
        when '--profile'
          index += 1
          options[:profile_id] = args[index]
        when '--profile-report'
          options[:profile_report] = true
        when '--require-profile-status'
          index += 1
          options[:require_profile_status] = args[index]
        when '--fallback'
          index += 1
          options[:fallback] = args[index]
        else
          if value.start_with?('--fallback=')
            options[:fallback] = value.delete_prefix('--fallback=')
          elsif value.start_with?('--')
            stderr.puts("unknown merge-driver option #{value.inspect}")
            return nil
          else
            positionals << value
          end
        end
        index += 1
      end

      options[:ancestor] ||= positionals[0]
      options[:current] ||= positionals[1]
      options[:other] ||= positionals[2]
      options[:path_name] ||= positionals[3]

      unless options[:ancestor] && options[:current] && options[:other]
        stderr.puts('merge-driver requires ancestor, current, and other paths')
        return nil
      end
      unless %w[none line local full-file].include?(options[:fallback])
        stderr.puts("unsupported fallback mode #{options[:fallback].inspect}")
        return nil
      end
      options
    end

    def write_merge_driver_machine_report(report_path, path_name, ok, exit_code, fallbacks, result, stderr)
      return EXIT_SUCCESS unless report_path

      report = {
        command: 'merge-driver',
        path_name: path_name,
        ok: ok,
        exit_code: exit_code,
        fallbacks: result.fetch(:fallbacks, []) + fallbacks,
        conflicts: result.fetch(:conflicts, []),
        change_classifications: result.fetch(:change_classifications, []),
        owned_regions: result.fetch(:owned_regions, []),
        render_report: result[:render_report],
        reparse_after_render: result[:reparse_after_render],
        formatting_preservation: result[:formatting_preservation],
        secondary_formatting_metrics: result[:secondary_formatting_metrics],
        default_driver_evaluation: result[:default_driver_evaluation],
        profile: result[:profile],
        provider: result[:provider],
        verification: result[:verification],
        diagnostics: result.fetch(:diagnostics, [])
      }
      File.write(report_path, "#{JSON.pretty_generate(Ast::Merge.json_ready(report))}\n")
      EXIT_SUCCESS
    rescue StandardError => e
      stderr.puts("write report: #{e.message}")
      EXIT_INTERNAL_ERROR
    end

    def fallback_reason(diagnostics)
      first = diagnostics.first
      return 'structured_merge_failed' unless first

      (first[:category] || first['category'] || 'structured_merge_failed').to_s
    end

    def report_and_enforce_profile(options, stdout, stderr)
      return EXIT_SUCCESS unless options[:profile_id] || options[:profile_report] || options[:require_profile_status]

      profile_id = options[:profile_id] || Ast::Merge::PROMOTION_PROFILE_JSON_KEYED_OBJECT
      evaluation = Ast::Merge::ProfilePromotionEvaluation.new(
        profile_id: profile_id,
        status: 'available',
        blocking_reasons: ['profile promotion evidence is not loaded by this CLI command'],
        diagnostics: []
      )
      decision = Ast::Merge.evaluate_profile_selection_requirement(
        Ast::Merge::ProfileSelectionRequirement.new(
          profile_id: profile_id,
          promotion_policy_id: Ast::Merge.initial_profile_promotion_policy.policy_id,
          minimum_profile_status: options[:require_profile_status] || 'available',
          enforcement_mode: options[:require_profile_status] ? 'required' : 'advisory'
        ),
        nil,
        evaluation
      )
      stdout.puts(JSON.generate(Ast::Merge.json_ready(decision.to_h))) if options[:profile_report]
      unless decision.allowed
        stderr.puts(decision.blocking_reasons.first)
        return EXIT_USER_ERROR
      end
      EXIT_SUCCESS
    end

    def run_diff_driver(args, stdout, stderr)
      options = parse_diff_driver_options(args, stderr)
      return EXIT_USER_ERROR unless options

      print_structured_diff(
        stdout,
        options[:path_name] || options[:new_path],
        File.read(options[:old_path]),
        File.read(options[:new_path])
      )
      EXIT_SUCCESS
    rescue Errno::ENOENT, Errno::EACCES => e
      stderr.puts("read diff input: #{e.message}")
      EXIT_USER_ERROR
    end

    def parse_diff_driver_options(args, stderr)
      options = {}
      positionals = []
      index = 0
      while index < args.length
        value = args[index]
        if value == '--path-name'
          index += 1
          options[:path_name] = args[index]
        elsif value.start_with?('--')
          stderr.puts("unknown diff-driver option #{value.inspect}")
          return nil
        else
          positionals << value
        end
        index += 1
      end

      case positionals.length
      when 2
        options.merge(old_path: positionals[0], new_path: positionals[1])
      when 7, 9
        options.merge(path_name: options[:path_name] || positionals[0], old_path: positionals[1],
                      new_path: positionals[4])
      else
        stderr.puts('diff-driver requires either 2, 7, or 9 positional arguments')
        nil
      end
    end

    def print_structured_diff(stdout, path_name, old_source, new_source)
      stdout.puts("structured-diff #{path_name}")
      if old_source == new_source
        stdout.puts('status unchanged')
      else
        stdout.puts('status changed')
        stdout.puts("old-lines #{line_count(old_source)}")
        stdout.puts("new-lines #{line_count(new_source)}")
        print_structured_diff_review_hunk(stdout, path_name, old_source, new_source)
      end
    end

    def print_structured_diff_review_hunk(stdout, path_name, old_source, new_source)
      old_lines = diff_source_lines(old_source)
      new_lines = diff_source_lines(new_source)
      stdout.puts('review-diff unified')
      stdout.puts("--- a/#{path_name}")
      stdout.puts("+++ b/#{path_name}")

      file_length_difference = 0
      Diff::LCS.diff(old_lines, new_lines).each do |piece|
        hunk = Diff::LCS::Hunk.new(old_lines, new_lines, piece, REVIEW_DIFF_CONTEXT_LINES, file_length_difference)
        file_length_difference = hunk.file_length_difference
        write_diff_text(stdout, hunk.diff(:unified))
      end
    end

    def diff_source_lines(source)
      source.to_s.lines.to_a
    end

    def write_diff_text(stdout, text)
      return if text.to_s.empty?

      stdout.write(text)
      stdout.write("\n") unless text.end_with?("\n")
    end

    def run_conflicts(args, stdout, stderr)
      subcommand, *rest = args
      return run_conflicts_diff(rest, stdout, stderr) if subcommand == 'diff'

      stderr.puts('conflicts requires the diff subcommand')
      EXIT_USER_ERROR
    end

    def run_conflicts_diff(args, stdout, stderr)
      options = parse_conflicts_diff_options(args, stderr)
      return EXIT_USER_ERROR unless options

      effective_path = options[:path_name] || options[:file_path]
      settings = load_path_settings(effective_path)
      regions = find_conflict_regions(File.read(options[:file_path]), settings[:conflict_marker_size])
      print_conflict_diff(stdout, effective_path, regions)
      options[:exit_code] && !regions.empty? ? EXIT_UNRESOLVED_CONFLICT : EXIT_SUCCESS
    rescue Errno::ENOENT, Errno::EACCES => e
      stderr.puts("read conflicted file: #{e.message}")
      EXIT_USER_ERROR
    end

    def parse_conflicts_diff_options(args, stderr)
      options = { exit_code: false }
      positionals = []
      index = 0
      while index < args.length
        value = args[index]
        case value
        when '--path-name'
          index += 1
          options[:path_name] = args[index]
        when '--exit-code'
          options[:exit_code] = true
        else
          if value.start_with?('--')
            stderr.puts("unknown conflicts diff option #{value.inspect}")
            return nil
          end
          positionals << value
        end
        index += 1
      end
      if positionals.length != 1
        stderr.puts('conflicts diff requires exactly one file path')
        return nil
      end
      options.merge(file_path: positionals[0])
    end

    def run_languages(args, stdout, stderr)
      unless args == ['--gitattributes']
        stderr.puts('languages currently requires --gitattributes')
        return EXIT_USER_ERROR
      end

      [
        '*.bash merge=smorg-rb diff=smorg-rb smorg.language=bash',
        '*.go merge=smorg-rb diff=smorg-rb smorg.language=go',
        '*.htm merge=smorg-rb diff=smorg-rb smorg.language=html',
        '*.html merge=smorg-rb diff=smorg-rb smorg.language=html',
        '*.env merge=smorg-rb diff=smorg-rb smorg.language=dotenv',
        '.env merge=smorg-rb diff=smorg-rb smorg.language=dotenv',
        '.env.* merge=smorg-rb diff=smorg-rb smorg.language=dotenv',
        '*.json merge=smorg-rb diff=smorg-rb smorg.language=json',
        '*.jsonc merge=smorg-rb diff=smorg-rb smorg.language=jsonc',
        '*.json5 merge=smorg-rb diff=smorg-rb smorg.language=json5',
        '*.md merge=smorg-rb diff=smorg-rb smorg.language=markdown',
        '*.markdown merge=smorg-rb diff=smorg-rb smorg.language=markdown',
        '*.rb merge=smorg-rb diff=smorg-rb smorg.language=ruby',
        '*.rbs merge=smorg-rb diff=smorg-rb smorg.language=rbs',
        '*.rs merge=smorg-rb diff=smorg-rb smorg.language=rust',
        '*.sh merge=smorg-rb diff=smorg-rb smorg.language=bash',
        '*.toml merge=smorg-rb diff=smorg-rb smorg.language=toml',
        '*.ts merge=smorg-rb diff=smorg-rb smorg.language=typescript',
        '*.tsx merge=smorg-rb diff=smorg-rb smorg.language=tsx',
        '*.yml merge=smorg-rb diff=smorg-rb smorg.language=yaml',
        '*.yaml merge=smorg-rb diff=smorg-rb smorg.language=yaml'
      ].each { |line| stdout.puts(line) }
      EXIT_SUCCESS
    end

    def merge_by_path(path_name, language, conflict_marker_size, fallback_policy, ancestor_source, current_source,
                      other_source)
      case normalize_language(language, path_name)
      when 'bash'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            provider_id: 'ruby.bash',
            family: 'bash',
            dialect: 'bash',
            backend: 'kreuzberg-language-pack',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'go'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            provider_id: 'ruby.go',
            family: 'go',
            dialect: 'go',
            backend: 'kreuzberg-language-pack',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'html'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            provider_id: 'ruby.html',
            family: 'html',
            dialect: 'html',
            backend: 'kreuzberg-language-pack',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'dotenv'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            family: 'dotenv',
            dialect: 'dotenv',
            backend: 'dotenv-line',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'json', 'jsonc', 'json5'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            family: 'json',
            dialect: normalize_language(language, path_name),
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'markdown'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            provider_id: 'ruby.markdown',
            family: 'markdown',
            dialect: 'markdown',
            backend: 'kreuzberg-language-pack',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'ruby'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            family: 'ruby',
            dialect: 'ruby',
            backend: 'prism',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'rbs'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            provider_id: 'ruby.rbs',
            family: 'rbs',
            dialect: 'rbs',
            backend: 'rbs',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'rust'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            provider_id: 'ruby.rust',
            family: 'rust',
            dialect: 'rust',
            backend: 'kreuzberg-language-pack',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'toml'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            provider_id: 'ruby.toml',
            family: 'toml',
            dialect: 'toml',
            backend: 'kreuzberg-language-pack',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'typescript', 'tsx'
        dialect = normalize_language(language, path_name)
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            provider_id: 'ruby.typescript',
            family: 'typescript',
            dialect: dialect,
            backend: 'kreuzberg-language-pack',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'yaml'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            provider_id: 'ruby.yaml.psych',
            family: 'yaml',
            dialect: 'yaml',
            backend: 'psych',
            profile_id: 'source_preserving',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      when 'text'
        merge3_result(
          Ast::Merge::Git.merge3(
            base_source: ancestor_source,
            ours_source: current_source,
            theirs_source: other_source,
            path_name: path_name,
            family: 'text',
            dialect: 'text',
            profile_id: 'coarse_document',
            fallback_policy: fallback_policy,
            conflict_marker_size: conflict_marker_size
          )
        )
      else
        unsupported_language_result(normalize_language(language, path_name), path_name)
      end
    end

    def unsupported_language_result(language, path_name)
      {
        ok: false,
        diagnostics: [
          {
            severity: 'error',
            category: 'unsupported_language',
            message: "no structured merge driver is configured for #{language.inspect} at #{path_name}"
          }
        ],
        policies: []
      }
    end

    def merge3_result(result)
      merge3_report_fields = {
        change_classifications: result.fetch(:change_classifications, []),
        conflicts: result.fetch(:conflicts, []),
        fallbacks: result.fetch(:fallbacks, []),
        provider: result.fetch(:provider, {}),
        verification: result.fetch(:verification, {})
      }
      if result[:ok] && result[:merged_source]
        {
          ok: true,
          diagnostics: result.fetch(:diagnostics),
          output: result.fetch(:merged_source),
          owned_regions: result.fetch(:owned_regions, []),
          render_report: result.fetch(:render_report),
          profile: result.fetch(:profile),
          policies: [],
          **merge3_report_fields
        }
      elsif !result[:ok] && result[:conflicted_source]
        {
          ok: false,
          diagnostics: result.fetch(:diagnostics),
          output: result.fetch(:conflicted_source),
          owned_regions: result.fetch(:owned_regions, []),
          render_report: result.fetch(:render_report),
          profile: result.fetch(:profile),
          policies: [],
          **merge3_report_fields
        }
      else
        {
          ok: false,
          diagnostics: result.fetch(:diagnostics),
          owned_regions: result.fetch(:owned_regions, []),
          render_report: result.fetch(:render_report),
          profile: result.fetch(:profile),
          policies: [],
          **merge3_report_fields
        }
      end
    end

    def normalize_language(language, path_name)
      return 'bash' if language.to_s.strip.empty? && %w[.bash .sh].include?(File.extname(path_name.to_s).downcase)
      return 'go' if language.to_s.strip.empty? && File.extname(path_name.to_s).downcase == '.go'
      return 'html' if language.to_s.strip.empty? && %w[.htm .html].include?(File.extname(path_name.to_s).downcase)
      return 'rust' if language.to_s.strip.empty? && File.extname(path_name.to_s).downcase == '.rs'
      return 'typescript' if language.to_s.strip.empty? && File.extname(path_name.to_s).downcase == '.ts'
      return 'tsx' if language.to_s.strip.empty? && File.extname(path_name.to_s).downcase == '.tsx'

      case language.to_s.strip.downcase
      when 'bash', 'sh', 'application/x-sh', 'text/x-shellscript'
        'bash'
      when 'go', 'golang'
        'go'
      when 'html', 'htm', 'text/html', 'html5'
        'html'
      when 'dotenv', 'env', 'config-env'
        'dotenv'
      when 'json'
        'json'
      when 'jsonc', 'json with comments'
        'jsonc'
      when 'json5'
        'json5'
      when 'markdown', 'md', 'gfm', 'text/markdown'
        'markdown'
      when 'ruby', 'rb', 'application/x-ruby'
        'ruby'
      when 'rbs'
        'rbs'
      when 'rust', 'rs', 'application/rust', 'text/rust'
        'rust'
      when 'toml', 'application/toml'
        'toml'
      when 'typescript', 'ts', 'application/typescript', 'text/typescript'
        'typescript'
      when 'tsx', 'typescriptreact'
        'tsx'
      when 'yaml', 'yml', 'application/yaml', 'text/yaml'
        'yaml'
      when 'plain', 'text', 'plaintext', 'text/plain'
        'text'
      else
        Ast::Merge.classify_template_target_path(path_name)[:family]
      end
    end

    def load_path_settings(path_name)
      settings = { conflict_marker_size: 7 }
      attribute_files_for_path(path_name).each do |attributes_path|
        next unless File.file?(attributes_path)

        apply_attributes(settings, path_name, File.read(attributes_path))
      end
      settings
    end

    def attribute_files_for_path(path_name)
      clean_path = if File.expand_path(path_name,
                                       Dir.pwd).start_with?(Dir.pwd)
                     Pathname.new(path_name).cleanpath.to_s
                   else
                     path_name
                   end
      dir = File.dirname(clean_path)
      return ['.gitattributes'] if dir == '.' || clean_path.start_with?('..') || Pathname.new(clean_path).absolute?

      files = ['.gitattributes']
      parts = dir.split(File::SEPARATOR).reject(&:empty?)
      parts.each_index do |index|
        files << File.join(*parts[0..index], '.gitattributes')
      end
      files
    end

    def apply_attributes(settings, path_name, source)
      source.each_line do |raw_line|
        line = raw_line.strip
        next if line.empty? || line.start_with?('#')

        pattern, *fields = line.split(/\s+/)
        next if fields.empty? || !attribute_pattern_matches?(pattern, path_name)

        fields.each do |field|
          key, value = field.split('=', 2)
          next unless value

          case key
          when 'smorg.language', 'linguist-language'
            settings[:language] = value
          when 'smorg.profile'
            settings[:profile_id] = value
          when 'smorg.requireProfileStatus'
            settings[:require_profile_status] = value
          when 'conflict-marker-size'
            marker_size = value.to_i
            settings[:conflict_marker_size] = marker_size if marker_size.positive?
          end
        end
      end
    end

    def attribute_pattern_matches?(pattern, path_name)
      return true if pattern == path_name

      if !pattern.include?('/')
        File.fnmatch?(pattern, File.basename(path_name))
      else
        File.fnmatch?(pattern, path_name)
      end
    end

    def find_conflict_regions(source, marker_size)
      marker_size = [marker_size.to_i, 1].max
      start_prefix = '<' * marker_size
      separator_prefix = '=' * marker_size
      end_prefix = '>' * marker_size
      regions = []
      current = nil
      source.split("\n").each_with_index do |line, index|
        line_number = index + 1
        if line.start_with?(start_prefix)
          current = { start_line: line_number, separator_line: 0 }
        elsif current && current[:separator_line].zero? && line.start_with?(separator_prefix)
          current[:separator_line] = line_number
        elsif current && line.start_with?(end_prefix)
          regions << current.merge(end_line: line_number)
          current = nil
        end
      end
      regions
    end

    def print_conflict_diff(stdout, path_name, regions)
      stdout.puts("conflicts #{path_name}")
      stdout.puts("count #{regions.length}")
      regions.each_with_index do |region, index|
        stdout.puts("conflict #{index + 1} lines #{region[:start_line]}-#{region[:end_line]} separator #{region[:separator_line]}")
      end
    end

    def line_count(source)
      return 0 if source.empty?

      source.end_with?("\n") ? source.count("\n") : source.count("\n") + 1
    end

    def print_diagnostics(stderr, result)
      result.fetch(:diagnostics, []).each do |diagnostic|
        stderr.puts("#{diagnostic[:category]}: #{diagnostic[:message]}")
      end
    end
  end
end

require 'rust/merge'
