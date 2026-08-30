# frozen_string_literal: true

RSpec.describe Kettle::Jem, "install and local orchestration behavior" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "applies bootstrap with non-interactive defaults and converges on the next run" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-bootstrap-contract", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      bootstrap_target = bootstrap_contract.fetch(:expected).fetch(:bootstrap_target)

      expect(apply.fetch(:decision_policy).fetch(:mode)).to eq(
        bootstrap_contract.fetch(:expected).fetch(:non_interactive_mode)
      )
      expect(apply.fetch(:changed_files)).to include(bootstrap_target)
      expect(File).to exist(File.join(root, bootstrap_target))

      described_class.apply_project(root, env: {}, run_options: {accept: true})
      selected = bootstrap_contract.fetch(:expected).fetch(:idempotent_selected_paths).to_h do |relative_path|
        [relative_path, File.exist?(File.join(root, relative_path)) ? File.read(File.join(root, relative_path)) : nil]
      end
      third_apply = described_class.apply_project(root, env: {}, run_options: {accept: true})

      expect(third_apply.fetch(:decision_policy).fetch(:mode)).to eq(
        bootstrap_contract.fetch(:expected).fetch(:non_interactive_mode)
      )
      expect(bootstrap_contract.fetch(:expected).fetch(:idempotent_selected_paths).to_h { |relative_path|
        [relative_path, File.exist?(File.join(root, relative_path)) ? File.read(File.join(root, relative_path)) : nil]
      }).to eq(selected)
      expect(third_apply.fetch(:changed_files)).not_to include(
        *bootstrap_contract.fetch(:expected).fetch(:idempotent_selected_paths)
      )
    end
  end

  it "hard-fails malformed Ruby project entrypoints during preflight" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    parser_error_paths = bootstrap_contract.fetch(:expected).fetch(:parser_error_paths)

    parser_error_paths.each do |relative_path|
      Dir.mktmpdir("kettle-jem-bootstrap-preflight", tmp_root) do |root|
        files = {
          "example.gemspec" => <<~RUBY
            Gem::Specification.new do |spec|
              spec.name = "example"
              spec.summary = "Example gem"
              spec.required_ruby_version = ">= 4.0"
            end
          RUBY
        }
        files["Gemfile"] = "source \"https://gem.coop\"\n" if relative_path == "example.gemspec"
        files[relative_path] = "if true\n"
        write_tree(root, files)

        expect {
          described_class.plan_project(root, env: {}, run_options: {accept: true})
        }.to raise_error(Kettle::Jem::Error, /Preflight failed for #{Regexp.escape(relative_path)}/)
      end
    end
  end

  it "hard-fails invalid kettle config shape before later discovery" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    {
      "root_scalar" => ["true\n", /root must be a mapping/],
      "templates_scalar" => ["templates: packaged\n", /templates must be a mapping/],
      "entries_scalar" => ["templates:\n  entries: README.md\n", /templates\.entries must be a list/]
    }.each do |case_name, (config, message)|
      Dir.mktmpdir("kettle-jem-config-validation-#{case_name}", tmp_root) do |root|
        write_tree(root, {
          "example.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "example"
              spec.summary = "Example gem"
            end
          RUBY
          ".kettle-jem.yml" => config
        })

        expect {
          described_class.plan_project(root, env: {})
        }.to raise_error(Kettle::Jem::Error, message)
      end
    end
  end

  it "classifies template entries with files and patterns strategy config" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-strategy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          patterns:
            - path: "certs/**"
              strategy: raw_copy
          files:
            README.md:
              strategy: keep_destination
          templates:
            root: packaged
            apply: true
            entries:
              - README.md
              - source: certs/pboling.pem.example
                target: certs/pboling.pem
        YAML
        "README.md" => "# destination\n"
      })

      packaged_cert = File.read(project_root.join("lib/kettle/jem/templates/certs/pboling.pem.example"))
      plan = described_class.plan_project(root, env: {})
      readme_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      cert_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_certs_pboling_pem"
      end
      expect(readme_report.fetch(:changed)).to be(false)
      expect(readme_report.fetch(:final_content)).to eq("# destination\n")
      expect(readme_report.dig(:metadata, :template_source_preference)).to include(strategy: "keep_destination")
      expect(cert_report.fetch(:changed)).to be(true)
      expect(cert_report.fetch(:final_content)).to eq(packaged_cert)
      expect(cert_report.dig(:metadata, :template_source_preference)).to include(strategy: "raw_copy")
    end
  end

  it "projects full per-file merge options into recipe metadata and runtime context" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-merge-option-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          defaults:
            preference: template
            add_template_only_nodes: true
            freeze_token: kettle-jem
            max_recursion_depth: 7
          files:
            config:
              settings.yml:
                strategy: merge
                file_type: yaml
                freeze_token: destination-token
                skip_unresolved_scan: true
          templates:
            root: template
            apply: true
            entries:
              - config/settings.yml
        YAML
        "config/settings.yml" => <<~YAML,
          enabled: false
        YAML
        "template/config/settings.yml.example" => <<~YAML
          enabled: true
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_config_settings_yml"
      end
      expected_policy = {
        strategy: "merge",
        file_type: "yaml",
        preference: "template",
        add_template_only_nodes: true,
        freeze_token: "destination-token",
        skip_unresolved_scan: true,
        max_recursion_depth: "7"
      }

      expect(report.dig(:metadata, :template_source_preference)).to include(expected_policy)
      expect(report.dig(:request_envelope, :request, :runtime_context, :template_source_preference)).to include(expected_policy)
    end
  end

  it "plans packaged template inventory when entries are omitted" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-inventory-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          funding:
            open_collective: false
          patterns:
            - path: "certs/**"
              strategy: raw_copy
          files:
            AGENTS.md:
              strategy: accept_template
          templates:
            root: packaged
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      preferences = plan.dig(:facts, :templates, :source_preferences)
      expect(preferences.size).to be > 100

      agents = preferences.find { |preference| preference.fetch(:target_path) == "AGENTS.md" }
      cert = preferences.find { |preference| preference.fetch(:target_path) == "certs/pboling.pem" }
      envrc = preferences.find { |preference| preference.fetch(:target_path) == ".envrc" }
      env_local = preferences.find { |preference| preference.fetch(:target_path) == ".env.local.example" }
      gemspec = preferences.find { |preference| preference.fetch(:target_path) == "example.gemspec" }

      expect(agents).to include(selected_source: "AGENTS.md.example", strategy: "accept_template")
      expect(cert).to include(selected_source: "certs/pboling.pem.example", strategy: "raw_copy")
      expect(envrc).to include(selected_source: ".envrc.no-osc.example")
      expect(env_local).to include(configured_source: ".env.local", selected_source: ".env.local.example")
      expect(gemspec).to include(configured_source: "gem.gemspec", selected_source: "gem.gemspec.example")
    end
  end

  it "applies remaining-files copy-only and legacy destination policies" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-remaining-files-policy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
              - .github/copilot_instructions.md
        YAML
        "bin/setup" => "custom setup\n",
        ".github/COPILOT_INSTRUCTIONS.md" => "legacy copilot instructions\n"
      })

      plan = described_class.plan_project(root, env: {})
      setup_preference = plan.dig(:facts, :templates, :source_preferences).find do |preference|
        preference.fetch(:target_path) == "bin/setup"
      end
      setup_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_bin_setup"
      end
      legacy_cleanup = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_legacy_destination_cleanup_github_COPILOT_INSTRUCTIONS_md"
      end

      expect(setup_preference).to include(
        strategy: "keep_destination",
        policy: "copy_only_when_missing"
      )
      expect(setup_report.fetch(:changed)).to be(false)
      expect(setup_report.fetch(:final_content)).to eq("custom setup\n")
      expect(legacy_cleanup.dig(:metadata, :delete_file)).to be(true)
      expect(legacy_cleanup.dig(:report_envelope, :report, :step_reports, 0, :metadata)).to include(
        policy_kind: "delete_legacy_destination_file",
        deleted_file: ".github/COPILOT_INSTRUCTIONS.md"
      )

      apply = described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "bin/setup"))).to eq("custom setup\n")
      expect(File.exist?(File.join(root, ".github/copilot_instructions.md"))).to be(true)
      expect(File.exist?(File.join(root, ".github/COPILOT_INSTRUCTIONS.md"))).to be(false)
      expect(apply.fetch(:changed_files)).to include(".github/COPILOT_INSTRUCTIONS.md")
    end
  end

  it "runs install as active apply plus local post-template checks" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    curated_binstubs = %w[bundle binstubs appraisal2 rake rbs rspec-core yard kettle-dev kettle-test kettle-soup-cover kettle-gha-pins stone_checksums]
    Dir.mktmpdir("kettle-jem-install-post-template-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => [
          "templates:",
          "  root: packaged",
          "  apply: true",
          "  entries:",
          "    - bin/setup",
          ""
        ].join("\n"),
        "Rakefile" => "task :default\n",
        "bin/rake" => "#!/usr/bin/env ruby\n"
      })

      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:bundle_includes_gem?).and_return(true)

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "bin/setup", quiet: true, skip_commit: true},
        command_runner: command_runner
      )
      setup_path = File.join(root, "bin", "setup")

      expect(install.fetch(:mode)).to eq("install")
      expect(install.fetch(:installed)).to be(true)
      expect(install.fetch(:changed_files)).to eq(["bin/setup"])
      expect(install.fetch(:changelog)).to include(status: "skipped", reason: "missing_changelog")
      expect(install.fetch(:install_steps)).to include(
        name: "bin_setup_executable",
        path: "bin/setup",
        status: "updated"
      )
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "bin_setup",
        command: ["bin/setup", "--quiet"],
        status: "succeeded",
        exitstatus: 0
      ))
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "bundle_binstubs",
        command: curated_binstubs,
        status: "succeeded",
        exitstatus: 0
      ))
      expect(install.fetch(:install_steps)).to include(
        name: "rubocop_gradual_autocorrect",
        status: "skipped",
        reason: "missing_rubocop_gradual_task"
      )
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "bundled_handoff",
        command: kettle_jem_handoff_command("--skip-commit", "--quiet", "--only", "bin/setup"),
        status: "succeeded",
        exitstatus: 0,
        reason: "executed"
      ))
      expect(install.fetch(:install_steps)).to include(
        name: "bootstrap_commit",
        status: "skipped",
        reason: "skip_commit"
      )
      expect(install.fetch(:install_phase_reports)).to include(hash_including(
        phase: "post_template",
        steps: include("bin_setup_executable", "bin_setup", "bundle_binstubs", "rubocop_gradual_autocorrect"),
        statuses: hash_including(
          "bin_setup_executable" => "updated",
          "bin_setup" => "succeeded",
          "bundle_binstubs" => "succeeded",
          "rubocop_gradual_autocorrect" => "skipped",
          "bundle_binstub_pruning" => "already_current"
        )
      ))
      expect(install.fetch(:install_phase_reports)).to include(
        phase: "orchestration",
        steps: %w[bundled_handoff bootstrap_commit],
        statuses: {
          "bundled_handoff" => "succeeded",
          "bootstrap_commit" => "skipped"
        }
      )
      autocorrect_command = ["sh", "-c", "rm -f .rubocop_gradual.lock && bin/rake rubocop_gradual:autocorrect"]
      handoff_command = kettle_jem_handoff_command("--skip-commit", "--quiet", "--only", "bin/setup")
      command_names = commands.map { |entry| entry.fetch(:command) }
      expect(command_names).to include(
        ["bin/setup", "--quiet"],
        curated_binstubs,
        handoff_command
      )
      expect(command_names).not_to include(autocorrect_command)
      expect(commands).to all(include(chdir: root, quiet: true))
      expect(commands.map { |entry| entry.fetch(:env) }).to all(include(
        "BUNDLE_GEMFILE" => nil,
        "BUNDLE_LOCKFILE" => nil,
        "RUBYLIB" => nil,
        "RUBYOPT" => nil
      ))
      expect(File).to exist(setup_path)
      expect(File.executable?(setup_path)).to be(true)

      commands.clear
      second = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "bin/setup", quiet: true},
        command_runner: command_runner
      )
      expect(second.fetch(:changed_files)).to be_empty
      expect(second.fetch(:install_steps)).to include(
        name: "bin_setup_executable",
        path: "bin/setup",
        status: "already_executable"
      )
      expect(second.fetch(:install_steps)).to include(hash_including(
        name: "bundled_handoff",
        command: kettle_jem_handoff_command("--quiet", "--only", "bin/setup"),
        status: "succeeded",
        exitstatus: 0,
        reason: "executed"
      ))
      second_commit_step = second.fetch(:install_steps).find { |step| step.fetch(:name) == "bootstrap_commit" }
      expect(second_commit_step.fetch(:status)).to eq("unavailable")
      expect(second_commit_step.fetch(:reason)).to eq("not_git_repository")
      expect(commands.map { |entry| entry.fetch(:command) }).to include(
        ["bin/setup", "--quiet"],
        curated_binstubs,
        kettle_jem_handoff_command("--quiet", "--only", "bin/setup")
      )

      bootstrap_install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "bin/setup", bootstrap_mode: true},
        command_runner: command_runner
      )
      expect(bootstrap_install.fetch(:install_steps)).to include(
        name: "bundled_handoff",
        status: "skipped",
        reason: "bootstrap_mode"
      )

      expect(system("git", "init", root, out: File::NULL, err: File::NULL)).to be(true)
      git_ready = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "bin/setup"},
        command_runner: command_runner
      )
      bootstrap_step = git_ready.fetch(:install_steps).find { |step| step.fetch(:name) == "bootstrap_commit" }
      expect(bootstrap_step).to include(
        status: "succeeded",
        commands: [
          %w[git add -A -- .],
          ["git", "commit", "-m", "🎨 Template bootstrap by kettle-jem v#{Kettle::Jem::Version::VERSION}"]
        ],
        reason: "executed",
        duration_ms: be >= 0
      )
      expect(bootstrap_step.fetch(:command_results)).to contain_exactly(
        hash_including(command: %w[git add -A -- .], exitstatus: 0, duration_ms: be >= 0),
        hash_including(command: ["git", "commit", "-m", "🎨 Template bootstrap by kettle-jem v#{Kettle::Jem::Version::VERSION}"], exitstatus: 0, duration_ms: be >= 0)
      )
      expect(git_ready.fetch(:install_steps).find { |step| step.fetch(:name) == "bootstrap_commit" }.fetch(:dirty_entries)).not_to be_empty

      Dir.mktmpdir("kettle-jem-locked-bootstrap", tmp_root) do |locked_root|
        expect(system("git", "init", locked_root, out: File::NULL, err: File::NULL)).to be(true)
        File.write(File.join(locked_root, "tracked.txt"), "changed\n")
        lock_path = File.join(locked_root, ".git", "kettle-family-template-commit.lock")
        lock_observations = []
        locked_runner = lambda do |command, chdir:, env:, quiet:|
          commands << {command: command, chdir: chdir, env: env, quiet: quiet}
          File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
            locked = !lock.flock(File::LOCK_EX | File::LOCK_NB)
            lock_observations << locked if command.first == "git"
          end
          {success: true, exitstatus: 0, stdout: "", stderr: ""}
        end

        locked_step = Kettle::Jem::Tasks::InstallTask.send(
          :execute_ready_commands_step,
          {
            name: "bootstrap_commit",
            status: "ready",
            dirty_entries: ["?? tracked.txt"],
            commands: [%w[git add -A -- .], ["git", "commit", "-m", "locked"]]
          },
          project_root: locked_root,
          env: {"KETTLE_JEM_GIT_COMMIT_LOCK" => lock_path},
          quiet: false,
          command_runner: locked_runner
        )
        expect(locked_step).to include(
          status: "succeeded",
          git_commit_lock: lock_path
        )
        expect(lock_observations).to all(be(true))
      end

      Dir.mktmpdir("kettle-jem-clean-bootstrap", tmp_root) do |clean_root|
        expect(system("git", "init", clean_root, out: File::NULL, err: File::NULL)).to be(true)
        stale_commit_step = Kettle::Jem::Tasks::InstallTask.send(
          :execute_ready_commands_step,
          {
            name: "bootstrap_commit",
            status: "ready",
            dirty_entries: [" M bin/setup"],
            commands: [%w[git add -A -- .], ["git", "commit", "-m", "stale"]]
          },
          project_root: clean_root,
          env: {},
          quiet: false,
          command_runner: command_runner
        )
        expect(stale_commit_step.fetch(:status)).to eq("clean_noop")
        expect(stale_commit_step.fetch(:reason)).to eq("clean_before_execution")
      end

      Dir.mktmpdir("kettle-jem-install-monorepo", tmp_root) do |repo_root|
        expect(system("git", "init", repo_root, out: File::NULL, err: File::NULL)).to be(true)
        gem_root = File.join(repo_root, "gems", "example")
        write_tree(gem_root, {
          "Gemfile" => <<~RUBY,
            source "https://gem.coop"
            gemspec
          RUBY
          "example.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "example"
              spec.summary = "Example gem"
            end
          RUBY
          ".kettle-jem.yml" => <<~YAML
            templates:
              root: packaged
              apply: true
              entries:
                - bin/setup
          YAML
        })

        commands.clear
        inherited_env = {"BUNDLE_GEMFILE" => File.join(repo_root, "Gemfile")}
        monorepo_install = Kettle::Jem::Tasks::InstallTask.run(
          project_root: gem_root,
          env: inherited_env,
          run_options: {only: "bin/setup"},
          command_runner: command_runner
        )
        expect(monorepo_install.fetch(:git_preflight)).to include(git_repository: true)
        expect(monorepo_install.fetch(:install_steps)).to include(hash_including(
          name: "bootstrap_commit",
          status: "succeeded",
          reason: "executed"
        ))
        expect(commands.map { |entry| entry.fetch(:env).fetch("BUNDLE_GEMFILE") }.uniq).to eq([File.join(gem_root, "Gemfile")])
        expect(monorepo_install.fetch(:install_steps)).to include(hash_including(
          name: "bundled_handoff",
          status: satisfy { |status| %w[succeeded already_bundled].include?(status) }
        ))

        commands.clear
        bundler_binstub = lambda do |gem_name, executable|
          <<~RUBY
            #!/usr/bin/env ruby
            # frozen_string_literal: true

            #
            # This file was generated by Bundler.
            #
            load Gem.bin_path("#{gem_name}", "#{executable}")
          RUBY
        end
        binstub_runner = lambda do |command, chdir:, env:, quiet:|
          commands << {command: command, chdir: chdir, env: env, quiet: quiet}
          if command == curated_binstubs
            FileUtils.mkdir_p(File.join(chdir, "bin"))
            File.write(File.join(chdir, "bin", "appraisal"), bundler_binstub.call("appraisal2", "appraisal"))
            File.write(File.join(chdir, "bin", "kettle-bump"), bundler_binstub.call("kettle-dev", "kettle-bump"))
            File.write(File.join(chdir, "bin", "rake"), bundler_binstub.call("rake", "rake"))
            File.write(File.join(chdir, "bin", "yard"), bundler_binstub.call("yard", "yard"))
            File.write(File.join(chdir, "bin", "reek"), bundler_binstub.call("reek", "reek"))
            FileUtils.chmod("+x", File.join(chdir, "bin", "appraisal"))
            FileUtils.chmod("+x", File.join(chdir, "bin", "reek"))
          end
          {success: true, exitstatus: 0, stdout: "", stderr: ""}
        end
        validated_install = Kettle::Jem::Tasks::InstallTask.run(
          project_root: gem_root,
          env: inherited_env,
          run_options: {only: "bin/setup", skip_commit: true},
          command_runner: binstub_runner
        )
        expect(validated_install.fetch(:install_steps)).to include(hash_including(
          name: "bundle_binstub_location_validation",
          status: "succeeded",
          reason: "destination_bin_has_binstubs",
          destination_bin: "bin",
          destination_binstubs: include("appraisal", "rake")
        ))
        expect(validated_install.fetch(:install_steps)).to include(hash_including(
          name: "yard_binstub_rake_handoff",
          status: "updated",
          reason: "yard_plugins_require_rake_yard_postprocess_hooks",
          path: "bin/yard"
        ))
        expect(validated_install.fetch(:install_steps)).to include(hash_including(
          name: "curated_binstubs_executable",
          status: "updated",
          path: "bin",
          updated_binstubs: %w[kettle-bump rake yard]
        ))
        expect(validated_install.fetch(:install_steps)).to include(hash_including(
          name: "bundle_binstub_pruning",
          status: "pruned",
          reason: "removed_unwanted_bundler_binstubs",
          removed_binstubs: ["reek"],
          preserved_binstubs: []
        ))
        expect(File.read(File.join(gem_root, "bin", "yard"))).to include('exec("bundle", "exec", "rake", "yard")')
        expect(File).to exist(File.join(gem_root, "bin", "appraisal"))
        expect(File).to exist(File.join(gem_root, "bin", "kettle-bump"))
        expect(File.executable?(File.join(gem_root, "bin", "kettle-bump"))).to be(true)
        expect(File.executable?(File.join(gem_root, "bin", "yard"))).to be(true)
        expect(File).not_to exist(File.join(gem_root, "bin", "reek"))
        expect(commands.find { |entry| entry.fetch(:command) == curated_binstubs }).to include(
          chdir: gem_root,
          env: include("BUNDLE_GEMFILE" => File.join(gem_root, "Gemfile"))
        )
      end
    end
  end

  it "records the template changelog before the bootstrap commit" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-changelog-order", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => [
          "templates:",
          "  root: packaged",
          "  apply: true",
          "  entries:",
          "    - bin/setup",
          ""
        ].join("\n"),
        "bin/setup" => "#!/usr/bin/env ruby\n"
      })
      expect(system("git", "init", root, out: File::NULL, err: File::NULL)).to be(true)

      order = []
      allow(Kettle::Jem::MaintenanceChangelog).to receive(:record_template_run) do |project_root:, report:, **|
        order << :changelog
        File.write(File.join(project_root, "CHANGELOG.md"), "## [Unreleased]\n")
        report.merge(changelog: {status: "updated"})
      end
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:bundle_includes_gem?).and_return(true)
      command_runner = lambda do |command, chdir:, env:, quiet:|
        order << command
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "bin/setup"},
        command_runner: command_runner
      )

      git_add_index = order.index(%w[git add -A -- .])
      expect(git_add_index).to be_a(Integer)
      expect(order.index(:changelog)).to be < git_add_index
      expect(install.fetch(:install_steps).find { |step| step.fetch(:name) == "bootstrap_commit" }).to include(
        dirty_entries: include("?? CHANGELOG.md")
      )
    end
  end

  it "generates Appraisal gemfiles during a full install" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-appraisal-generation-step", tmp_root) do |root|
      write_tree(root, {
        "Appraisals" => "appraise \"current\" do\nend\n",
        "bin/rake" => "#!/usr/bin/env ruby\n",
        "Rakefile" => "task \"appraisal:generate\"\n"
      })
      FileUtils.chmod("+x", File.join(root, "bin/rake"))

      allow(Kettle::Jem::Tasks::InstallTask).to receive(:rake_task_available?)
        .with(root, "appraisal:generate", env: {})
        .and_return(true)

      expect(Kettle::Jem::Tasks::InstallTask.appraisal_generate_step(root, env: {})).to eq(
        name: "appraisal_generate",
        command: ["bin/rake", "appraisal:generate"],
        status: "ready",
        reason: "post_template_appraisal_generation"
      )
      expect(Kettle::Jem::Tasks::InstallTask.appraisal_generate_step(root, env: {}, run_options: {only: "Appraisals"})).to include(
        name: "appraisal_generate",
        status: "skipped",
        reason: "template_selection"
      )
    end
  end

  it "preserves tracked project-owned Bundler binstubs during pruning" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-tracked-binstub", tmp_root) do |root|
      path = File.join(root, "bin", "rackup")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, <<~RUBY)
        #!/usr/bin/env ruby
        # This file was generated by Bundler.
        load Gem.bin_path("rackup", "rackup")
      RUBY

      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3).with(
        "git", "-C", root, "ls-files", "--error-unmatch", "--", "bin/rackup"
      ).and_return(["bin/rackup\n", "", status])

      result = Kettle::Jem::Tasks::InstallTask.prune_unwanted_bundler_binstubs(root)

      expect(result).to include(
        status: "already_current",
        removed_binstubs: [],
        preserved_binstubs: ["rackup"]
      )
      expect(File).to exist(path)
    end
  end

  it "applies full templates after accepting a newly bootstrapped config before bundled handoff" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    curated_binstubs = %w[bundle binstubs appraisal2 rake rbs rspec-core yard kettle-dev kettle-test kettle-soup-cover kettle-gha-pins stone_checksums]
    Dir.mktmpdir("kettle-jem-install-bootstrap-followup", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"
          gemspec
        RUBY
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "💎 Example gem"
            spec.authors = ["Peter H. Boling"]
            spec.email = ["floss@galtzo.com"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:bundle_includes_gem?).and_return(true)

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: {accept_config: true, force: true, skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:bootstrap_followup_apply)).to eq(
        status: "applied",
        reason: "canonical_config_bootstrapped"
      )
      expect(install.fetch(:changed_files)).to include(
        ".structuredmerge/kettle-jem.yml",
        "Gemfile",
        "gemfiles/modular/templating.gemfile",
        "gemfiles/modular/templating_local.gemfile"
      )
      expect(File.read(File.join(root, "Gemfile"))).to include(
        'eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?'
      )
      expect_gem_dependency_declared(File.read(File.join(root, "gemfiles", "modular", "templating.gemfile")), "kettle-jem")
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "bundled_handoff",
        command: kettle_jem_handoff_command("--accept-config", "--skip-commit", "--force"),
        status: "succeeded"
      ))
      expect(commands.map { |entry| entry.fetch(:command) }).to include(
        ["bin/setup"],
        curated_binstubs,
        kettle_jem_handoff_command("--accept-config", "--skip-commit", "--force")
      )
    end
  end

  it "uses KJ_MIN_RUBY during the accepted config one-shot followup apply" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-bootstrap-min-ruby", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"
          gemspec
        RUBY
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "💎 Example gem"
            spec.authors = ["Peter H. Boling"]
            spec.email = ["floss@galtzo.com"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      command_runner = lambda do |_command, chdir:, env:, quiet:|
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {
          "K_JEM_TEMPLATING" => "true",
          "KJ_MIN_RUBY" => "1.8.7"
        },
        run_options: {accept_config: true, force: true, skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:bootstrap_followup_apply)).to eq(
        status: "applied",
        reason: "canonical_config_bootstrapped"
      )
      expect(install.dig(:facts, :rubygems, :min_ruby)).to eq("1.8.7")
      expect(YAML.safe_load_file(File.join(root, Kettle::Jem::KETTLE_CONFIG_PATH)).dig("rubygems", "min_ruby")).to eq("1.8.7")
    end
  end

  it "silences Bundler and debug environment for quiet orchestration commands" do
    expect(Kettle::Jem::Tasks::InstallTask.quiet_command(%w[bundle install], quiet: true)).to eq(%w[bundle install --quiet])
    expect(Kettle::Jem::Tasks::InstallTask.quiet_command(%w[bundle install --quiet], quiet: true)).to eq(%w[bundle install --quiet])
    expect(Kettle::Jem::Tasks::InstallTask.quiet_command(%w[bundle update], quiet: true)).to eq(%w[bundle update --quiet])
    expect(Kettle::Jem::Tasks::InstallTask.quiet_command(%w[bundle binstubs rake], quiet: true)).to eq(%w[bundle binstubs rake])
    expect(Kettle::Jem::Tasks::InstallTask.quiet_command(%w[bundle lock], quiet: true)).to eq(%w[bundle lock])
    expect(Kettle::Jem::Tasks::InstallTask.quiet_command(%w[bin/setup --quiet], quiet: true)).to eq(%w[bin/setup --quiet])
    expect(Kettle::Jem::Tasks::InstallTask.quiet_command_env("DEBUG" => "true")).to include(
      "DEBUG" => "false",
      "KETTLE_JEM_DEBUG" => "false",
      "KETTLE_DEV_DEBUG" => "false",
      "BUNDLE_IGNORE_MESSAGES" => "true",
      "BUNDLE_SILENCE_DEPRECATIONS" => "true",
      "BUNDLE_SILENCE_ROOT_WARNING" => "true",
      "BUNDLE_VERBOSE" => "false"
    )
  end

  it "generates only curated documented binstubs" do
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return(["", "", status])

    expect(Kettle::Jem::Tasks::InstallTask.bundle_binstubs_command).to eq(
      %w[bundle binstubs appraisal2 rake rbs rspec-core yard kettle-dev kettle-test kettle-soup-cover kettle-gha-pins stone_checksums]
    )
  end

  it "omits curated binstubs for gems missing from the destination bundle" do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return([
      "appraisal2\nrake\nrbs\nrspec-core\nkettle-dev\nkettle-test\nkettle-soup-cover\nstone_checksums\n",
      "",
      status
    ])

    expect(Kettle::Jem::Tasks::InstallTask.bundle_binstubs_command("/example", env: {})).to eq(
      %w[bundle binstubs appraisal2 rake rbs rspec-core kettle-dev kettle-test kettle-soup-cover stone_checksums]
    )
  end

  it "skips bundled handoff when kettle-jem is absent from the destination bundle" do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return([
      "rake\nrspec-core\n",
      "",
      status
    ])

    expect(Kettle::Jem::Tasks::InstallTask.bundled_handoff_step(project_root: "/example", env: {}, run_options: {})).to eq(
      name: "bundled_handoff",
      status: "skipped",
      reason: "kettle_jem_not_in_bundle"
    )
  end

  it "runs setup commands when the caller passes Ruby ENV" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-env-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        "Gemfile" => "source \"https://gem.coop\"\n",
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
        YAML
      })

      command_envs = []
      command_runner = lambda do |_command, chdir:, env:, quiet:|
        expect(chdir).to eq(root)
        expect(quiet).to be(true)
        command_envs << env
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      expect {
        Kettle::Jem::Tasks::InstallTask.run(
          project_root: root,
          env: ENV,
          run_options: {only: "bin/setup", quiet: true, skip_commit: true},
          command_runner: command_runner
        )
      }.not_to raise_error

      expect(command_envs).not_to be_empty
      expect(command_envs).to all(be_a(Hash))
      expect(command_envs).to all(include("BUNDLE_GEMFILE" => File.join(root, "Gemfile")))
    end
  end

  it "runs setup commands without inherited Bundler activation" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-env-bundler-strip", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
        YAML
      })

      inherited_env = {
        "BUNDLE_GEMFILE" => "/workspace/kettle-jem/Gemfile",
        "BUNDLE_BIN_PATH" => "/workspace/kettle-jem/bin/bundle",
        "BUNDLE_LOCKFILE" => "/workspace/kettle-jem/Gemfile.lock",
        "BUNDLER_SETUP" => "/workspace/kettle-jem/bundler/setup",
        "BUNDLER_VERSION" => "4.0.12",
        "GIT_CONFIG_COUNT" => "1",
        "GIT_CONFIG_KEY_0" => "safe.bareRepository",
        "GIT_CONFIG_VALUE_0" => "explicit",
        "RUBYLIB" => "/workspace/kettle-jem/lib",
        "RUBYOPT" => "-rbundler/setup"
      }
      command_envs = []
      command_runner = lambda do |_command, chdir:, env:, quiet:|
        expect(chdir).to eq(root)
        expect(quiet).to be(true)
        command_envs << env
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: inherited_env,
        run_options: {only: "bin/setup", quiet: true, skip_commit: true},
        command_runner: command_runner
      )

      expect(command_envs).not_to be_empty
      expect(command_envs).to all(include("BUNDLE_GEMFILE" => File.join(root, "Gemfile")))
      expect(command_envs).to all(include(
        "BUNDLE_BIN_PATH" => nil,
        "BUNDLE_LOCKFILE" => nil,
        "BUNDLER_SETUP" => nil,
        "BUNDLER_VERSION" => nil,
        "GIT_CONFIG_COUNT" => nil,
        "GIT_CONFIG_KEY_0" => nil,
        "GIT_CONFIG_VALUE_0" => nil,
        "RUBYLIB" => nil,
        "RUBYOPT" => nil
      ))
    end
  end

  it "preserves an explicit KJ Bundler version through setup environment sanitization" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-env-bundler-override", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })
      command_envs = []
      command_runner = lambda do |_command, chdir:, env:, quiet:|
        expect(chdir).to eq(root)
        expect(quiet).to be(true)
        command_envs << env
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {"BUNDLER_VERSION" => "4.0.12", "KJ_BUNDLER_VERSION" => "2.7.2"},
        run_options: {only: "bin/setup", quiet: true, skip_commit: true},
        command_runner: command_runner
      )

      expect(command_envs).not_to be_empty
      expect(command_envs).to all(include("BUNDLER_VERSION" => "2.7.2"))
    end
  end

  it "uses kettle-family local install roots for templating setup" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-family-marker", tmp_root) do |root|
      marker_path = File.join(root, "local-install.json")
      marker = {
        "members_root" => File.join(root, "structuredmerge", "ruby", "gems"),
        "local_dependencies" => [
          File.join(root, "kettle-dev", "nomono"),
          File.join(root, "kettle-dev", "kettle-dev")
        ],
        "installed_members" => ["nomono", "kettle-dev", "kettle-jem"]
      }
      FileUtils.mkdir_p(File.join(marker.fetch("members_root"), "kettle-jem"))
      File.write(marker_path, JSON.pretty_generate(marker))
      File.write(File.join(root, "Gemfile"), "source \"https://gem.coop\"\n")

      env = {
        "K_JEM_TEMPLATING" => "true",
        "KETTLE_FAMILY_LOCAL_INSTALL_MARKER" => marker_path
      }

      expect(Kettle::Jem::Tasks::InstallTask.setup_command_env(root, env)).to include(
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "K_JEM_TEMPLATING" => "true",
        "STRUCTUREDMERGE_DEV" => marker.fetch("members_root"),
        "KETTLE_DEV_DEV" => File.join(root, "kettle-dev")
      )

      disabled_env = env.merge(
        "STRUCTUREDMERGE_DEV" => "false",
        "KETTLE_DEV_DEV" => "false"
      )
      expect(Kettle::Jem::Tasks::InstallTask.setup_command_env(root, disabled_env)).to include(
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "K_JEM_TEMPLATING" => "false",
        "STRUCTUREDMERGE_DEV" => "false",
        "KETTLE_DEV_DEV" => "false"
      )
    end
  end

  it "preserves explicit checksum validation settings for setup commands" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-checksum-env", tmp_root) do |root|
      File.write(File.join(root, "Gemfile"), "source \"https://gem.coop\"\n")

      env = {
        "BUNDLE_DISABLE_CHECKSUM_VALIDATION" => "true",
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "BUNDLE_BIN_PATH" => "/inherited/bundler"
      }

      expect(Kettle::Jem::Tasks::InstallTask.setup_command_env(root, env)).to include(
        "BUNDLE_DISABLE_CHECKSUM_VALIDATION" => "true",
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "BUNDLE_BIN_PATH" => nil
      )
      expect(Kettle::Jem::Tasks::InstallTask.bundler_command_env(root, env)).to include(
        "BUNDLE_DISABLE_CHECKSUM_VALIDATION" => "true",
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "BUNDLE_BIN_PATH" => nil
      )
    end
  end

  it "detects rake tasks using the same bundle environment as command execution" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rake-task-env", tmp_root) do |root|
      write_tree(root, {
        "Rakefile" => "task default: []\n",
        "bin/rake" => <<~RUBY
          #!/usr/bin/env ruby
          puts "rake rubocop_gradual:autocorrect" if ENV.fetch("K_JEM_TEMPLATING", "false") == "true"
        RUBY
      })
      FileUtils.chmod("+x", File.join(root, "bin", "rake"))

      expect(Kettle::Jem::Tasks::InstallTask.rake_task_available?(root, "rubocop_gradual:autocorrect", env: {"K_JEM_TEMPLATING" => "false"})).to be(false)
      expect(Kettle::Jem::Tasks::InstallTask.rake_task_available?(root, "rubocop_gradual:autocorrect", env: {"K_JEM_TEMPLATING" => "true"})).to be(true)
      expect(Kettle::Jem::Tasks::InstallTask.rubocop_gradual_autocorrect_step(root, env: {"K_JEM_TEMPLATING" => "true"})).to include(
        name: "rubocop_gradual_autocorrect",
        status: "ready"
      )
    end
  end

  it "skips rubocop gradual autocorrect before probing rake tasks when requested" do
    expect(Kettle::Jem::Tasks::InstallTask).not_to receive(:rake_task_available?)

    expect(Kettle::Jem::Tasks::InstallTask.rubocop_gradual_autocorrect_step("/missing", run_options: {skip_rubocop_gradual: true})).to eq(
      name: "rubocop_gradual_autocorrect",
      status: "skipped",
      reason: "skip_rubocop_gradual"
    )
  end

  it "runs install follow-up templating whenever the canonical config changes" do
    report = {
      recipe_reports: [
        {
          relative_path: Kettle::Jem::KETTLE_CONFIG_PATH,
          recipe_name: "template_source_application_structuredmerge_kettle_jem_yml",
          changed: true
        }
      ]
    }

    expect(Kettle::Jem::Tasks::InstallTask.config_bootstrap_changed?(report)).to be(true)
  end

  it "skips rubocop gradual autocorrect when the destination Rakefile does not define the task" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-missing-rubocop-gradual-task", tmp_root) do |root|
      write_tree(root, {
        "Rakefile" => "task default: []\n",
        "bin/rake" => <<~SH
          #!/usr/bin/env sh
          echo "rake default"
        SH
      })
      FileUtils.chmod("+x", File.join(root, "bin", "rake"))

      expect(Kettle::Jem::Tasks::InstallTask.rubocop_gradual_autocorrect_step(root)).to eq(
        name: "rubocop_gradual_autocorrect",
        status: "skipped",
        reason: "missing_rubocop_gradual_task"
      )
    end
  end

  it "skips curated binstub generation when requested" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-skip-binstubs", tmp_root) do |root|
      write_tree(root, {"bin/setup" => "#!/usr/bin/env sh\n"})
      FileUtils.chmod("+x", File.join(root, "bin", "setup"))
      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      steps = Kettle::Jem::Tasks::InstallTask.run_bundle_setup_commands(
        root,
        env: {},
        run_options: {skip_binstubs: true},
        command_runner: command_runner
      )

      expect(steps).to include(
        name: "bundle_binstubs",
        status: "skipped",
        reason: "skip_binstubs"
      )
      expect(commands.map { |entry| entry.fetch(:command) }).to eq([["bin/setup"]])
    end
  end

  it "records command duration metadata for install command steps" do
    command_runner = lambda do |_command, chdir:, env:, quiet:|
      expect(chdir).to eq("/project")
      expect(env).to eq({})
      expect(quiet).to be(true)
      {success: true, exitstatus: 0, stdout: "", stderr: ""}
    end

    step = Kettle::Jem::Tasks::InstallTask.run_command_step(
      "example",
      %w[echo ok],
      project_root: "/project",
      env: {},
      quiet: true,
      command_runner: command_runner
    )

    expect(step).to include(
      name: "example",
      command: %w[echo ok],
      status: "succeeded",
      exitstatus: 0,
      duration_ms: be >= 0
    )
  end

  it "repairs an obsolete parser platform after Bundler rejects it, then retries setup" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-unsupported-platform", tmp_root) do |root|
      write_tree(root, {"bin/setup" => "#!/usr/bin/env sh\n"})
      File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
        GEM
          specs:

        PLATFORMS
          arm64-darwin-23
          ruby
      LOCK
      commands = []
      setup_attempts = 0
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        if command == ["bin/setup"]
          setup_attempts += 1
          next {success: true, exitstatus: 0, stdout: "", stderr: ""} if setup_attempts == 2

          {
            success: false,
            exitstatus: 7,
            stdout: "",
            stderr: "Could not find gem 'tree_sitter_language_pack' with platform 'arm64-darwin-23'"
          }
        else
          {success: true, exitstatus: 0, stdout: "", stderr: ""}
        end
      end

      step = Kettle::Jem::Tasks::InstallTask.run_command_step(
        "bin_setup",
        ["bin/setup"],
        project_root: root,
        env: {},
        quiet: false,
        command_runner: command_runner
      )

      expect(step).to include(
        name: "bin_setup",
        status: "succeeded",
        recovered: true,
        recovery: include(
          command: %w[bundle lock --remove-platform=arm64-darwin-23],
          platform: "arm64-darwin-23",
          status: "succeeded"
        )
      )
      expect(commands.map { |entry| entry.fetch(:command) }).to eq([
        ["bin/setup"],
        %w[bundle lock --remove-platform=arm64-darwin-23],
        ["bin/setup"]
      ])
    end
  end

  it "honors install ENV skip-commit and skips lockfile normalization in local path development env" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-env-skip-lock", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => <<~LOCK,
          GEM
            remote: https://gem.coop/
            specs:

          PLATFORMS
            arm64-darwin
            ruby
            x86_64-darwin

          DEPENDENCIES

          BUNDLED WITH
             4.0.10
        LOCK
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
        YAML
      })

      env = {
        "KETTLE_JEM_SKIP_COMMIT" => "true",
        "K_JEM_TEMPLATING" => "true",
        "KETTLE_DEV_DEV" => "/workspace/my",
        "GALTZO_FLOSS_DEV" => "/workspace/galtzo-floss",
        "STRUCTUREDMERGE_DEV" => "/workspace/smorg-rb"
      }
      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: env,
        run_options: {only: "bin/setup"},
        command_runner: command_runner
      )

      expect(install.fetch(:install_steps)).to include(
        name: "bootstrap_commit",
        status: "skipped",
        reason: "skip_commit"
      )
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "bundle_install_requested_env",
        status: "skipped",
        reason: "same_as_setup_bundle_env"
      ))
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "bundle_lock_normalization",
        status: "skipped",
        reason: "local_path_development_env"
      ))
      requested_bundle_install = commands.find { |entry| entry.fetch(:command) == %w[bundle install] }
      expect(requested_bundle_install).to be_nil
      command_names = commands.map { |entry| entry.fetch(:command) }
      expect(command_names).not_to include(%w[bundle update])
      expect(command_names).not_to include(%w[git add -A -- .])
    end
  end

  it "can skip install lockfile normalization from ENV" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-skip-lock-normalization", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => "GEM\n  remote: https://gem.coop/\n  specs:\n",
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {"KETTLE_JEM_SKIP_LOCK_NORMALIZATION" => "true"},
        run_options: {only: "example.gemspec", skip_commit: true},
        command_runner: lambda { |_command, chdir:, env:, quiet:| {success: true, exitstatus: 0, stdout: "", stderr: ""} }
      )

      expect(install.fetch(:install_steps)).to include(
        name: "bundle_lock_normalization",
        status: "skipped",
        reason: "skip_lock_normalization"
      )
    end
  end

  it "skips lockfile normalization while local path development env is active" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-local-lock-normalization", tmp_root) do |root|
      File.write(File.join(root, "Gemfile.lock"), "GEM\n")

      expect(
        Kettle::Jem::Tasks::InstallTask.normalize_lockfile_step(
          root,
          env: {
            "K_JEM_TEMPLATING" => "true",
            "STRUCTUREDMERGE_DEV" => "/workspace/structuredmerge/ruby/gems"
          }
        )
      ).to include(
        name: "bundle_lock_normalization",
        status: "skipped",
        reason: "local_path_development_env"
      )
    end
  end

  it "normalizes lockfiles from the template task without templating env overrides" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-lock-normalization", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => <<~LOCK,
          GEM
            remote: https://gem.coop/
            specs:

          PLATFORMS
            arm64-darwin
            ruby
            x86_64-darwin

          DEPENDENCIES

          BUNDLED WITH
             4.0.10
        LOCK
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries: []
        YAML
      })

      env = {
        "K_JEM_TEMPLATING" => "true",
        "KETTLE_DEV_DEV" => "false",
        "GALTZO_FLOSS_DEV" => "false",
        "STRUCTUREDMERGE_DEV" => "false",
        "RUBYOPT" => "-rbundler/setup",
        "RUBYLIB" => "/workspace/kettle-jem/lib",
        "BUNDLE_BIN_PATH" => "/workspace/kettle-jem/bin/bundle",
        "BUNDLE_LOCKFILE" => "/workspace/kettle-jem/Gemfile.lock",
        "BUNDLER_SETUP" => "/workspace/kettle-jem/bundler/setup",
        "BUNDLER_VERSION" => "4.0.12"
      }
      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      report = Kettle::Jem::Tasks::TemplateTask.run(
        project_root: root,
        env: env,
        run_options: {quiet: true},
        command_runner: command_runner
      )

      expected_lock_command = [
        "bundle",
        "lock",
        *["arm64-darwin", "ruby", "x86_64-darwin", Gem::Platform.local.to_s].uniq.sort.map { |platform| "--add-platform=#{platform}" },
        "--update"
      ]
      expect(report.fetch(:template_steps)).to include(hash_including(
        name: "bundle_lock_normalization",
        command: expected_lock_command,
        status: "succeeded",
        reason: "executed"
      ))
      lock_command = commands.find { |entry| entry.fetch(:command) == expected_lock_command }
      expect(lock_command).not_to be_nil
      expect(lock_command.fetch(:env)).to include(
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "K_JEM_TEMPLATING" => "false",
        "KETTLE_DEV_DEV" => "false",
        "GALTZO_FLOSS_DEV" => "false",
        "STRUCTUREDMERGE_DEV" => "false"
      )
      expect(lock_command.fetch(:env)).to include(
        "RUBYOPT" => nil,
        "RUBYLIB" => nil,
        "BUNDLE_BIN_PATH" => nil,
        "BUNDLE_LOCKFILE" => nil,
        "BUNDLER_SETUP" => nil,
        "BUNDLER_VERSION" => nil
      )
    end
  end

  it "activates local git hooks when requested by the template task" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-hook-activation", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => <<~LOCK,
          GEM
            remote: https://gem.coop/
            specs:

          PLATFORMS
            ruby

          DEPENDENCIES

          BUNDLED WITH
             4.0.10
        LOCK
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries: []
        YAML
        ".git-hooks/commit-msg" => "#!/bin/sh\n",
        ".git-hooks/prepare-commit-msg" => "#!/bin/sh\n"
      })

      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      report = Kettle::Jem::Tasks::TemplateTask.run(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: {hook_templates: "l", quiet: true},
        command_runner: command_runner
      )

      expect(report.fetch(:template_steps)).to include(hash_including(
        name: "hook_templates",
        command: %w[git config core.hooksPath .git-hooks],
        status: "succeeded",
        reason: "executed"
      ))
      expect(commands.map { |entry| entry.fetch(:command) }).to include(%w[git config core.hooksPath .git-hooks])
      expect(File.stat(File.join(root, ".git-hooks", "commit-msg")).mode & 0o111).not_to eq(0)
      expect(File.stat(File.join(root, ".git-hooks", "prepare-commit-msg")).mode & 0o111).not_to eq(0)
    end
  end

  it "keeps post-apply work scoped when only selected template paths are requested" do
    allow(described_class).to receive(:kettle_jem_state_sync_step).and_return(
      name: "kettle_jem_state_sync",
      status: "already_current",
      changed_files: []
    )
    allow(described_class).to receive(:monorepo_subgem_kettle_config_profile_sync_step)

    steps = described_class.send(
      :post_apply_steps,
      "/workspace/project",
      template_selection: {only: ["gemfiles/modular/style.gemfile"]}
    )

    expect(steps.map { |step| step.fetch(:name) }).to eq(["kettle_jem_state_sync"])
    expect(described_class).not_to have_received(:monorepo_subgem_kettle_config_profile_sync_step)
  end

  it "makes generated git hook scripts executable during template apply" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-hook-mode", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "1.0.0"
            spec.summary = "Demo"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries: []
        YAML
        ".git-hooks/commit-msg" => "#!/bin/sh\n",
        ".git-hooks/prepare-commit-msg" => "#!/bin/sh\n"
      })
      FileUtils.chmod(0o644, File.join(root, ".git-hooks", "commit-msg"))
      FileUtils.chmod(0o644, File.join(root, ".git-hooks", "prepare-commit-msg"))

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})

      expect(apply.fetch(:post_apply_steps)).to include(hash_including(
        name: "git_hooks_executable",
        status: "updated",
        changed_files: contain_exactly(".git-hooks/commit-msg", ".git-hooks/prepare-commit-msg")
      ))
      expect(File.executable?(File.join(root, ".git-hooks", "commit-msg"))).to be(true)
      expect(File.executable?(File.join(root, ".git-hooks", "prepare-commit-msg"))).to be(true)
    end
  end

  it "plans local semantic Git driver setup by default" do
    step = Kettle::Jem::Tasks::InstallTask.git_drivers_step("/example", {})

    expect(step).to include(
      name: "git_drivers",
      status: "ready",
      mode: "local",
      profile: "semantic-diff",
      scope: "local",
      reason: "ready_for_local_git_drivers"
    )
    expect(step.fetch(:attribute_updates)).to include(hash_including(
      pattern: "*.rb",
      attributes: {"diff" => "smorg-rb"}
    ))
    expect(step.fetch(:commands)).to include(
      ["git", "config", "--local", "diff.smorg-rb.command", "smorg-rb diff-driver"],
      ["git", "config", "--local", "merge.smorg-rb.driver", "smorg-rb merge-driver %O %A %B %P"]
    )
  end

  it "plans builtin Git diff attributes when requested" do
    step = Kettle::Jem::Tasks::InstallTask.git_drivers_step("/example", {git_drivers: "builtin-diff"})

    expect(step).to include(
      name: "git_drivers",
      status: "ready",
      mode: "builtin-diff",
      profile: "builtin-diff",
      scope: "local"
    )
    expect(step.fetch(:attribute_updates)).to include(hash_including(
      pattern: "*.rb",
      attributes: {"diff" => "ruby"}
    ))
  end

  it "normalizes Git driver mode aliases" do
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode(nil)).to eq("local")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("off")).to eq("none")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("yes")).to eq("local")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("g")).to eq("global")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("include")).to eq("include-file")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("b")).to eq("builtin-diff")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("check")).to eq("check")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("undo")).to eq("undo")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("custom")).to eq("custom")
  end

  it "plans a RuboCop-LTS branch switch for local RuboCop-LTS templating" do
    report = {
      facts: {
        templates: {
          tokens: {
            "KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby2_4"
          }
        }
      }
    }

    allow(Kettle::Jem::Tasks::InstallTask).to receive(:current_git_branch).and_return("r1_8-even-v0")

    step = Kettle::Jem::Tasks::InstallTask.rubocop_lts_local_branch_step(
      report,
      env: {"RUBOCOP_LTS_LOCAL" => "/workspace/rubocop-lts"}
    )

    expect(step).to include(
      name: "rubocop_lts_local_branch",
      command: ["git", "-C", "/workspace/rubocop-lts/rubocop-lts", "switch", "r2_4-even-v12"],
      status: "ready",
      path: "/workspace/rubocop-lts/rubocop-lts",
      current_branch: "r1_8-even-v0",
      branch: "r2_4-even-v12",
      reason: "rubocop_lts_local_branch_matrix"
    )
  end

  it "skips the RuboCop-LTS branch switch when the local checkout is already on the matrix branch" do
    report = {
      facts: {
        templates: {
          tokens: {
            "KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby2_4"
          }
        }
      }
    }

    allow(Kettle::Jem::Tasks::InstallTask).to receive(:current_git_branch).and_return("r2_4-even-v12")

    step = Kettle::Jem::Tasks::InstallTask.rubocop_lts_local_branch_step(
      report,
      env: {"RUBOCOP_LTS_LOCAL" => "/workspace/rubocop-lts"}
    )

    expect(step).to include(
      name: "rubocop_lts_local_branch",
      status: "already_current",
      path: "/workspace/rubocop-lts/rubocop-lts",
      branch: "r2_4-even-v12"
    )
  end

  it "skips the RuboCop-LTS branch switch when templating the RuboCop-LTS checkout itself" do
    report = {
      facts: {
        templates: {
          tokens: {
            "KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby3_2"
          }
        }
      }
    }

    step = Kettle::Jem::Tasks::InstallTask.rubocop_lts_local_branch_step(
      report,
      env: {"RUBOCOP_LTS_LOCAL" => "/workspace/rubocop-lts"},
      project_root: "/workspace/rubocop-lts/rubocop-lts"
    )

    expect(step).to include(
      name: "rubocop_lts_local_branch",
      status: "skipped",
      path: "/workspace/rubocop-lts/rubocop-lts",
      branch: "r3_2-even-v24",
      reason: "destination_is_rubocop_lts_checkout"
    )
  end

  it "skips the RuboCop-LTS branch switch when the checkout paths differ only by realpath" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rubocop-lts-realpath", tmp_root) do |root|
      local_root = File.join(root, "rubocop-lts")
      checkout = File.join(local_root, "rubocop-lts")
      FileUtils.mkdir_p(checkout)
      alias_path = File.join(root, "rubocop-lts-alias")
      File.symlink(local_root, alias_path)

      report = {
        facts: {
          templates: {
            tokens: {
              "KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby3_2"
            }
          }
        }
      }

      step = Kettle::Jem::Tasks::InstallTask.rubocop_lts_local_branch_step(
        report,
        env: {"RUBOCOP_LTS_LOCAL" => alias_path},
        project_root: checkout
      )

      expect(step).to include(
        name: "rubocop_lts_local_branch",
        status: "skipped",
        path: File.join(alias_path, "rubocop-lts"),
        branch: "r3_2-even-v24",
        reason: "destination_is_rubocop_lts_checkout"
      )
    end
  end

  it "does not plan a RuboCop-LTS branch switch when local RuboCop-LTS is disabled" do
    report = {
      facts: {
        templates: {
          tokens: {
            "KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby2_4"
          }
        }
      }
    }

    expect(Kettle::Jem::Tasks::InstallTask.rubocop_lts_local_branch_step(
      report,
      env: {"RUBOCOP_LTS_LOCAL" => "off"}
    )).to be_nil
  end

  it "fails local RuboCop-LTS branch planning when the selected wrapper is unknown" do
    report = {
      facts: {
        templates: {
          tokens: {
            "KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby9_9"
          }
        }
      }
    }

    expect {
      Kettle::Jem::Tasks::InstallTask.rubocop_lts_local_branch_step(
        report,
        env: {"RUBOCOP_LTS_LOCAL" => "/workspace/rubocop-lts"}
      )
    }.to raise_error(Kettle::Jem::Error, /Cannot select RUBOCOP_LTS_LOCAL branch/)
  end

  it "executes the RuboCop-LTS branch switch before later orchestration commands" do
    commands = []
    command_runner = lambda do |command, **|
      commands << command
      {success: true, exitstatus: 0, stdout: "", stderr: ""}
    end

    result = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
      [
        {
          name: "rubocop_lts_local_branch",
          command: ["git", "-C", "/workspace/rubocop-lts/rubocop-lts", "switch", "r2_4-even-v12"],
          status: "ready"
        },
        {
          name: "rubocop_gradual_autocorrect",
          command: ["sh", "-c", "rm -f .rubocop_gradual.lock && bin/rake rubocop_gradual:autocorrect"],
          status: "ready"
        }
      ],
      project_root: "/project",
      env: {},
      run_options: {},
      command_runner: command_runner
    )

    expect(result).to include(
      hash_including(name: "rubocop_lts_local_branch", status: "succeeded"),
      hash_including(name: "rubocop_gradual_autocorrect", status: "succeeded")
    )
    expect(commands).to eq([
      ["git", "-C", "/workspace/rubocop-lts/rubocop-lts", "switch", "r2_4-even-v12"],
      ["sh", "-c", "rm -f .rubocop_gradual.lock && bin/rake rubocop_gradual:autocorrect"]
    ])
  end

  it "writes managed .gitattributes and local config for local semantic Git driver setup" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-drivers", tmp_root) do |root|
      write_tree(root, {".gitattributes" => "*.md diff=markdown\n"})
      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      commands = []
      command_runner = lambda do |command, **|
        commands << command
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      result = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
        [step],
        project_root: root,
        env: {},
        run_options: {},
        command_runner: command_runner
      ).first

      expect(result).to include(status: "succeeded", changed_files: [".gitattributes"])
      expect(File.read(File.join(root, ".gitattributes"))).to eq(<<~ATTRIBUTES)
        *.md diff=markdown
        # <<structuredmerge:git-drivers>> do not edit below this line
        *.rb diff=smorg-rb
        *.go diff=smorg-go
        *.rs diff=smorg-rs
        # <</structuredmerge:git-drivers>>
      ATTRIBUTES
      expect(commands).to include(
        ["git", "config", "--local", "diff.smorg-rb.command", "smorg-rb diff-driver"],
        ["git", "config", "--local", "merge.smorg-rb.driver", "smorg-rb merge-driver %O %A %B %P"]
      )
    end
  end

  it "serializes local semantic Git driver setup with the shared Git operation lock" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-lock", tmp_root) do |root|
      lock_path = File.join(root, ".git", "kettle-family-template-git.lock")
      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      command_runner = lambda do |_command, **|
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      result = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
        [step],
        project_root: root,
        env: {"KETTLE_JEM_GIT_LOCK" => lock_path},
        run_options: {},
        command_runner: command_runner
      ).first

      expect(result).to include(
        status: "succeeded",
        git_lock: lock_path
      )
    end
  end

  it "retries local semantic Git driver setup after transient Git lock conflicts" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-lock-retry", tmp_root) do |root|
      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      calls = 0
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:sleep)
      command_runner = lambda do |_command, **|
        calls += 1
        if calls == 1
          {success: false, exitstatus: 1, stdout: "", stderr: "error: could not lock config file .git/config: File exists"}
        else
          {success: true, exitstatus: 0, stdout: "", stderr: ""}
        end
      end

      result = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
        [step],
        project_root: root,
        env: {},
        run_options: {},
        command_runner: command_runner
      ).first

      expect(result).to include(status: "succeeded")
      expect(result.fetch(:command_results).first).to include(attempts: 2)
    end
  end

  it "reports conflicting unmanaged .gitattributes entries" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-conflict", tmp_root) do |root|
      write_tree(root, {".gitattributes" => "*.rb diff=ruby\n"})

      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})

      expect(step).to include(
        status: "blocked",
        reason: "git_driver_attribute_conflict"
      )
      expect(step.fetch(:diagnostics)).to include(hash_including(
        key: "conflicting_attributes",
        path: ".gitattributes",
        pattern: "*.rb",
        blocking: true
      ))
    end
  end

  it "plans local Git driver setup without writing attributes in dry-run mode" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-dry-run", tmp_root) do |root|
      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {dry_run: true})

      expect(step).to include(
        status: "planned",
        reason: "dry_run_git_driver_attributes"
      )
    end
  end

  it "plans global Git driver command registration when requested" do
    step = Kettle::Jem::Tasks::InstallTask.git_drivers_step("/example", {git_drivers: "global"})

    expect(step).to include(
      name: "git_drivers",
      status: "ready",
      mode: "global",
      profile: "semantic-diff",
      scope: "global",
      reason: "ready_for_global_git_drivers"
    )
    expect(step.fetch(:commands)).to include(
      ["git", "config", "--global", "diff.smorg-rb.command", "smorg-rb diff-driver"],
      ["git", "config", "--global", "merge.smorg-rb.driver", "smorg-rb merge-driver %O %A %B %P"]
    )
    expect(step.fetch(:diagnostics)).to include(hash_including(key: "forge_ignores_external_diff_drivers"))
  end

  it "plans global Git driver command removal with unset-all when requested" do
    step = Kettle::Jem::Tasks::InstallTask.git_drivers_step("/example", {git_drivers: "undo"})

    expect(step).to include(
      name: "git_drivers",
      status: "ready",
      mode: "undo",
      profile: "all",
      scope: "local",
      reason: "ready_for_git_driver_undo"
    )
    expect(step.fetch(:commands)).to include(
      ["git", "config", "--global", "--unset-all", "diff.smorg-rb.command"],
      ["git", "config", "--global", "--unset-all", "merge.smorg-rb.driver"],
      ["git", "config", "--global", "--unset-all", "merge.smorg-rb.name"]
    )
  end

  it "writes include-file Git driver configuration when requested" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-include", tmp_root) do |root|
      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {git_drivers: "include-file"})
      commands = []
      command_runner = lambda do |command, **|
        commands << command
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      result = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
        [step],
        project_root: root,
        env: {},
        run_options: {},
        command_runner: command_runner
      ).first

      expect(result).to include(status: "succeeded", changed_files: [".git/smorg/config"])
      expect(commands).to include(["git", "config", "--local", "include.path", ".git/smorg/config"])
      expect(File.read(File.join(root, ".git", "smorg", "config"))).to include("[diff \"smorg-rb\"]")
    end
  end

  it "loads project Git driver manifests for attribute and command planning" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-manifest", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1
          driver_namespace = "smorg"

          [profiles.semantic-diff]
          description = "Custom Ruby driver"

          [[profiles.semantic-diff.attributes]]
          pattern = "*.rake"
          diff = "smorg-rb"

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-rb.command"
          value = "bundle exec smorg-rb diff-driver"
        TOML
      })

      local = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      global = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {git_drivers: "global"})

      expect(local.fetch(:attribute_updates)).to eq([
        {path: ".gitattributes", pattern: "*.rake", attributes: {"diff" => "smorg-rb"}}
      ])
      expect(global.fetch(:commands)).to eq([
        ["git", "config", "--global", "diff.smorg-rb.command", "bundle exec smorg-rb diff-driver"]
      ])
    end
  end

  it "keeps committed Git driver manifests on the smorg-rb executable name" do
    repo_root = project_root.join("../..").expand_path
    manifest_paths = [
      repo_root.join(".structuredmerge/git-drivers.toml"),
      project_root.join(".structuredmerge/git-drivers.toml")
    ]

    manifest_paths.each do |path|
      content = File.read(path)

      expect(content).to include('diff = "smorg-rb"')
      expect(content).to include('key = "diff.smorg-rb.command"')
      expect(content).to include('value = "smorg-rb diff-driver"')
      expect(content).not_to include("smorg-ruby")
    end
  end

  it "rejects unsafe interpolation in committed Git driver manifests" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-unsafe-manifest", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1

          [profiles.semantic-diff]

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-rb.command"
          value = "smorg-rb $(danger)"
        TOML
      })

      expect do
        Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      end.to raise_error(Kettle::Jem::Error, /unsafe command interpolation/)
    end
  end

  it "rejects cachetextconv outside explicit textconv profiles" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-cachetextconv", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1

          [profiles.semantic-diff]

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-rb.cachetextconv"
          value = "true"
        TOML
      })

      expect do
        Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      end.to raise_error(Kettle::Jem::Error, /cachetextconv requires an explicit textconv profile/)
    end
  end

  it "keeps semantic diff commands separate from textconv projections" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-textconv-separation", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1

          [profiles.semantic-diff]

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-rb.command"
          value = "smorg-rb diff-driver"

          [profiles.textconv-normalized]

          [[profiles.textconv-normalized.git_config]]
          scope = "global"
          key = "diff.smorg-json-textconv.textconv"
          value = "smorg-rb textconv --format json"

          [[profiles.textconv-normalized.git_config]]
          scope = "global"
          key = "diff.smorg-json-textconv.cachetextconv"
          value = "true"
        TOML
      })

      manifest = Kettle::Jem::Tasks::InstallTask.git_driver_manifest(root)
      semantic_commands = Kettle::Jem::Tasks::InstallTask.git_driver_global_commands(manifest, "semantic-diff")
      semantic_local_commands = Kettle::Jem::Tasks::InstallTask.git_driver_local_commands(manifest, "semantic-diff")
      textconv_commands = Kettle::Jem::Tasks::InstallTask.git_driver_global_commands(manifest, "textconv-normalized")

      expect(semantic_commands).to eq([
        ["git", "config", "--global", "diff.smorg-rb.command", "smorg-rb diff-driver"]
      ])
      expect(semantic_local_commands).to eq([
        ["git", "config", "--local", "diff.smorg-rb.command", "smorg-rb diff-driver"]
      ])
      expect(textconv_commands).to contain_exactly(
        ["git", "config", "--global", "diff.smorg-json-textconv.textconv", "smorg-rb textconv --format json"],
        ["git", "config", "--global", "diff.smorg-json-textconv.cachetextconv", "true"]
      )
    end
  end

  it "keeps textconv projections display-only and out of merge inputs" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-textconv-display-only", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1

          [profiles.textconv-normalized]

          [[profiles.textconv-normalized.attributes]]
          pattern = "*.json"
          diff = "smorg-json-textconv"

          [[profiles.textconv-normalized.git_config]]
          scope = "global"
          key = "diff.smorg-json-textconv.textconv"
          value = "smorg-rb textconv --format json"
        TOML
      })

      manifest = Kettle::Jem::Tasks::InstallTask.git_driver_manifest(root)
      attributes = Kettle::Jem::Tasks::InstallTask.git_driver_attribute_updates(manifest, "textconv-normalized")
      commands = Kettle::Jem::Tasks::InstallTask.git_driver_global_commands(manifest, "textconv-normalized")

      expect(attributes).to eq([
        {path: ".gitattributes", pattern: "*.json", attributes: {"diff" => "smorg-json-textconv"}}
      ])
      expect(attributes.flat_map { |update| update.fetch(:attributes).keys }).not_to include("merge")
      expect(commands.map { |command| command[3] }).to contain_exactly("diff.smorg-json-textconv.textconv")
      expect(commands.map { |command| command[3] }).not_to include(a_string_matching(/\Amerge\./))
    end
  end

  it "skips Git driver setup when explicitly disabled" do
    step = Kettle::Jem::Tasks::InstallTask.git_drivers_step("/example", {git_drivers: "none"})

    expect(step).to include(
      name: "git_drivers",
      status: "skipped",
      reason: "not_requested",
      mode: "none"
    )
  end

  it "loads canonical structuredmerge kettle-jem config before legacy root config" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-discovery", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => "templates:\n  root: legacy\n",
        ".structuredmerge/kettle-jem.yml" => "templates:\n  root: canonical\n"
      })

      expect(described_class.kettle_jem_config(root).fetch("templates").fetch("root")).to eq("canonical")
    end
  end

  it "migrates legacy kettle-jem config to the structuredmerge directory" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-migration", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => "templates:\n  root: packaged\n"
      })

      step = Kettle::Jem::Tasks::InstallTask.kettle_config_migration_step(root)

      expect(step).to include(
        name: "kettle_config_migration",
        status: "migrated",
        reason: "legacy_kettle_config_migrated",
        canonical_path: ".structuredmerge/kettle-jem.yml",
        legacy_path: ".kettle-jem.yml"
      )
      expect(File).not_to exist(File.join(root, ".kettle-jem.yml"))
      expect(File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))).to eq("templates:\n  root: packaged\n")
    end
  end

  it "reports a conflict when canonical and legacy kettle-jem configs both exist" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-migration-conflict", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => "templates:\n  root: legacy\n",
        ".structuredmerge/kettle-jem.yml" => "templates:\n  root: canonical\n"
      })

      step = Kettle::Jem::Tasks::InstallTask.kettle_config_migration_step(root)

      expect(step).to include(
        name: "kettle_config_migration",
        status: "blocked",
        reason: "legacy_kettle_config_conflict"
      )
      expect(step.fetch(:diagnostics)).to include(hash_including(
        key: "legacy_kettle_config_conflict",
        path: ".kettle-jem.yml",
        canonical_path: ".structuredmerge/kettle-jem.yml"
      ))
    end
  end

  it "reports gemspec dependency sync through the install task" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-gemspec-sync", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: example.gemspec
                target: example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "template"
            spec.summary = "Template gem"
            spec.add_development_dependency "rake", "~> 13.0"
          end
        RUBY
      })
      command_runner = lambda do |_command, **|
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "example.gemspec", skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:install_steps)).to include(
        name: "gemspec_dependency_sync",
        path: "example.gemspec",
        status: "applied",
        development_dependencies: ["rake"]
      )
      expect(File.read(File.join(root, "example.gemspec"))).to include('spec.add_development_dependency "rake", "~> 13.0"')
    end
  end

  it "drops retired gemspec development dependencies during gemspec sync" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-retired-gemspec-dev-dependency", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.add_development_dependency "kettle-drift"
            spec.add_development_dependency "rubocop-rspec", "~> 2.10"
            spec.add_development_dependency "yard-junk", "~> 0.0.10"
            spec.add_development_dependency "rake", "~> 13.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: example.gemspec
                target: example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "template"
            spec.summary = "Template gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {}, run_options: {only: "example.gemspec"})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "example.gemspec"
      end
      content = report.fetch(:final_content)

      expect(content).not_to include("kettle-drift")
      expect(content).not_to include("rubocop-rspec")
      expect(content).not_to include("yard-junk")
      expect(content).to include('spec.add_development_dependency "rake", "~> 13.0"')
    end
  end

  it "ports old install post-template project cleanup and safety checks" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-post-processing", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "🥘 Example gem"
            spec.description = "Example description"
            spec.homepage = "\#{homepage}"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🔧"
          templates:
            root: packaged
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => <<~MARKDOWN,
          # 🍲 Example

          | Runtime | Works |
          | --- | --- |
          | Works with MRI Ruby | [![ruby-2.7][💎ruby-2.7i]][🚎2.7] <br/> [![ruby-3.2][💎ruby-3.2i]][🚎3.2] <br/> [![ruby-current][💎ruby-c-i]][🚎current] |

          [💎ruby-2.7i]: https://img.shields.io/badge/Ruby-2.7-red.svg
          [💎ruby-3.2i]: https://img.shields.io/badge/Ruby-3.2-red.svg
          [💎ruby-c-i]: https://img.shields.io/badge/Ruby-current-red.svg
          [🚎2.7]: https://github.com/example-org/example/actions/workflows/ruby-2.7.yml
          [🚎3.2]: https://github.com/example-org/example/actions/workflows/ruby-3.2.yml
          [🚎current]: https://github.com/example-org/example/actions/workflows/current.yml
        MARKDOWN
        ".github/workflows/ruby-3.2.yml" => "name: Ruby 3.2\n",
        "mise.toml" => "[tools]\nruby = \"3.4.1\"\n",
        ".ruby-version" => "3.4.1\n",
        ".tool-versions" => "ruby 3.4.1\n",
        ".env.local.example" => "KETTLE_DEV_DEV=false\n",
        ".gitignore" => "tmp/\n"
      })
      command_runner = lambda do |_command, **|
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {
          "FORGE_ORG" => "example-org",
          "KJ_GH_ORG" => "ignored-gh-org",
          "KJ_GH_USER" => "personal-user"
        },
        run_options: {only: "README.md", skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:install_steps)).to include(
        name: "legacy_ruby_version_file_cleanup",
        status: "applied",
        removed_files: [".ruby-version", ".tool-versions"]
      )
      expect(install.fetch(:install_steps)).to include(
        name: "gemspec_homepage_literal",
        path: "example.gemspec",
        status: "applied",
        homepage: "https://github.com/example-org/example"
      )
      expect(install.fetch(:install_steps)).to include(
        name: "env_local_gitignore",
        path: ".gitignore",
        status: "applied"
      )
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "readme_gemspec_grapheme_sync",
        paths: ["README.md", "example.gemspec"],
        status: "applied",
        grapheme: "🔧"
      ))
      expect(File).not_to exist(File.join(root, ".ruby-version"))
      expect(File).not_to exist(File.join(root, ".tool-versions"))
      gemspec = File.read(File.join(root, "example.gemspec"))
      expect(gemspec).to include('spec.homepage = "https://github.com/example-org/example"')
      expect(gemspec.scan('spec.homepage = "https://github.com/example-org/example"').size).to eq(1)
      expect(gemspec).to include('spec.summary = "🔧 Example gem"')
      expect(gemspec).to include('spec.description = "🔧 Example description"')
      expect(File.read(File.join(root, ".gitignore"))).to include(".env.local")
      readme = File.read(File.join(root, "README.md"))
      expect(readme).to include("# 🔧 Example")
      expect(readme).not_to include("ruby-2.7")
      expect(readme).to include("ruby-3.2")
      expect(readme).not_to include("ruby-current")
      expect(readme).not_to include("[🚎current]:")
      expect(readme).to include("[🚎ruby-3.2-wf]:")
      expect(install.fetch(:install_phase_reports)).to include(hash_including(
        phase: "post_template",
        statuses: hash_including(
          "legacy_ruby_version_file_cleanup" => "applied",
          "readme_compatibility_badges" => satisfy { |status| %w[applied already_current].include?(status) },
          "readme_gemspec_grapheme_sync" => "applied",
          "gemspec_homepage_literal" => "applied",
          "env_local_gitignore" => "applied"
        )
      ))
      expect(install.fetch(:install_summary)).to include(
        steps: install.fetch(:install_steps).length,
        statuses: include("applied" => be >= 4),
        summary: include("install steps")
      )
    end
  end

  it "keeps maintainer GitHub user separate from scaffold repository owner" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-gh-org", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.description = "Example description"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.homepage = "https://example.test"
          end
        RUBY
      })
      command_runner = lambda do |_command, **|
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {"KJ_GH_USER" => "personal-user"},
        run_options: {skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "gemspec_homepage_literal",
        path: "example.gemspec",
        status: "skipped",
        reason: "missing_github_org"
      ))
      expect(File.read(File.join(root, "example.gemspec"))).to include('spec.homepage = "https://example.test"')
    end
  end
end
