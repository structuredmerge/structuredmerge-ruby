# frozen_string_literal: true

require "rake"
require "tmpdir"
require "fileutils"

# In case spec_helper loaded kettle/test/rspec before Rake was defined, load the
# shared context directly, as kettle-test's own with_rake_spec does.
require "kettle/test/support/shared_contexts/with_rake"

# Behavioral coverage for the task the KJ|RAKE:TOP_LEVEL_DOCS_TASK template token
# emits. The token generator itself is covered by jem_rake_docs_task_spec.rb, which
# asserts on the emitted text. This spec loads that text into a real Rake
# application through kettle-test's shared "with rake" context and proves the
# behavior it exists for, rather than trusting the string.
#
# The bug being prevented: a gem with a generated docs/ directory has no top-level
# `docs` task, so Rake resolves the bare name `docs` against the existing directory
# as an implicit file task that is already up to date. `rake docs` then exits 0
# having regenerated nothing, and `--trace` reports `not_needed` instead of
# invoking anything. Verified live in turbo_tests2 and kettle-rb.
RSpec.describe "rake docs", :check_output do # rubocop:disable RSpec/DescribeClass
  include_context "with rake", "docs" do
    let(:tmp_rakelib) { Dir.mktmpdir("docs_rake_spec_") }
    # Required by the shared context (override the raising defaults).
    let(:task_dir) { tmp_rakelib }
    let(:rakelib) { tmp_rakelib }
  end

  # Writes the rakelib BEFORE the shared context's before(:each) runs, since that
  # hook rake_requires "<task_base_name>.rake" from rakelib.
  around do |example|
    File.write(File.join(tmp_rakelib, "docs.rake"), <<~RAKE)
      task :yard do
        # Simulate document generation so the test can observe delegation.
        puts "YARD_RAN"
      end

      #{Kettle::Jem.send(:rake_top_level_docs_task_token, {template_profile: Kettle::Jem::FULL_TEMPLATE_PROFILE})}
    RAKE

    begin
      example.run
    ensure
      Rake::Task.tasks.each(&:clear)
      FileUtils.rm_rf(tmp_rakelib) if File.directory?(tmp_rakelib)
    end
  end

  it "derives task_name from the top-level description" do
    expect(task_name).to eq("docs")
  end

  it "delegates to yard even when a docs directory already exists" do
    # The trap: an existing docs/ directory is what makes bare `docs` satisfy as an
    # up-to-date implicit file task when no real task is declared. Running from a
    # project directory that has one proves the declared task wins.
    Dir.mktmpdir do |project|
      FileUtils.mkdir_p(File.join(project, "docs"))
      File.write(File.join(project, "docs", "index.html"), "stale\n")

      # rubocop:disable ThreadSafety/DirChdir
      Dir.chdir(project) do
        expect { invoke }.to output(/YARD_RAN/).to_stdout
      end
      # rubocop:enable ThreadSafety/DirChdir
    end
  end

  it "is a declared task that delegates to yard, not an implicit file task" do
    expect(rake_task).to be_a(Rake::Task)
    # The distinction that matters: an implicit file task on an existing docs/
    # directory is a Rake::FileTask. A declared task is not.
    expect(rake_task).not_to be_a(Rake::FileTask)
    expect(rake_task.prerequisites).to include("yard")
    # Deliberately no action of its own: `task docs: "yard"` delegates, so the
    # work belongs to yard. Asserting a non-empty action list would require the
    # task to duplicate what yard already does.
    expect(rake_task.actions).to be_empty
  end

  it "reports the task as needed, so it actually executes" do
    # An implicit file task on an existing directory reports needed? == false,
    # which is precisely how `rake docs` became a silent no-op.
    expect(rake_task.needed?).to be(true)
  end
end
