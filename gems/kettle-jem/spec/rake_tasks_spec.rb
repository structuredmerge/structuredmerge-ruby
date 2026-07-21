# frozen_string_literal: true

require "rake"

RSpec.describe Kettle::Jem do
  around do |example|
    previous = Rake.application
    Rake.application = Rake::Application.new
    described_class.install_tasks
    example.run
  ensure
    Rake.application = previous
  end

  it "registers the public kettle:jem task surface" do
    expect(Rake::Task.task_defined?("kettle:jem:prepare")).to be(true)
    expect(Rake::Task.task_defined?("kettle:jem:template")).to be(true)
    expect(Rake::Task.task_defined?("kettle:jem:install")).to be(true)
    expect(Rake::Task.task_defined?("kettle:jem:selftest")).to be(true)
  end

  it "delegates prepare to the active task implementation" do
    expect(Kettle::Jem::Tasks::PrepareTask).to receive(:run)

    Rake::Task["kettle:jem:prepare"].invoke
  end

  it "delegates template to the active task implementation" do
    expect(Kettle::Jem::Tasks::TemplateTask).to receive(:run)

    Rake::Task["kettle:jem:template"].invoke
  end

  it "delegates install to the active task implementation without invoking template" do
    expect(Kettle::Jem::Tasks::InstallTask).to receive(:run)
    expect(Kettle::Jem::Tasks::TemplateTask).not_to receive(:run)

    Rake::Task["kettle:jem:install"].invoke
  end

  it "delegates selftest to the active task implementation" do
    expect(Kettle::Jem::Tasks::SelfTestTask).to receive(:run)

    Rake::Task["kettle:jem:selftest"].invoke
  end

  it "maps old ENV-style template arguments into shared run options" do
    env = {
      "force" => "true",
      "FAILURE_MODE" => "warn",
      "allowed" => "env",
      "hook_templates" => "false",
      "git_drivers" => "builtin-diff",
      "only" => "Gemfile,Rakefile",
      "include" => "gemfiles/modular/**",
      "KETTLE_JEM_SKIP_COMMIT" => "true",
      "KETTLE_JEM_ACCEPT_CONFIG" => "true",
      "KETTLE_JEM_BOOTSTRAP_MODE" => "true",
      "KETTLE_JEM_QUIET" => "true",
      "KETTLE_JEM_VERBOSE" => "true"
    }

    expect(Kettle::Jem::Tasks::TemplateTask.env_run_options(env)).to include(
      accept: true,
      force: true,
      interactive: false,
      failure_mode: "warn",
      allowed: "env",
      hook_templates: "false",
      git_drivers: "builtin-diff",
      only: "Gemfile,Rakefile",
      include: "gemfiles/modular/**",
      skip_commit: true,
      accept_config: true,
      bootstrap_mode: true,
      quiet: true,
      verbose: true
    )
  end

  it "defaults templating to half-core thread workers when no worker options are set" do
    allow(Etc).to receive(:nprocessors).and_return(22)

    expect(Kettle::Jem::Tasks::TemplateTask.templating_run_options({}, {})).to include(
      recipe_planning_strategy: "classified",
      recipe_planning_thread_workers: 11,
      file_work_thread_workers: 11
    )
  end

  it "preserves explicit templating worker options" do
    allow(Etc).to receive(:nprocessors).and_return(22)

    expect(
      Kettle::Jem::Tasks::TemplateTask.templating_run_options(
        {"KETTLE_JEM_THREAD_WORKERS" => "3"},
        {}
      )
    ).not_to include(:file_work_thread_workers)
    expect(
      Kettle::Jem::Tasks::TemplateTask.templating_run_options(
        {},
        {recipe_planning_strategy: "sequential"}
      )
    ).not_to include(:recipe_planning_thread_workers, :file_work_thread_workers)
  end
end
