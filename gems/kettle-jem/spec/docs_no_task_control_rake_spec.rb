# frozen_string_literal: true

# Control for docs_rake_spec.rb: proves the assertion there is not vacuous.
#
# With NO declared top-level `docs` task but an existing docs/ directory, bare
# `docs` resolves to an implicit Rake::FileTask that is already up to date, so
# invoking it runs nothing. This is the exact silent no-op the template token
# prevents. If this control ever stops reproducing, the positive spec would pass
# for the wrong reason.

require "rake"
require "tmpdir"
require "fileutils"
require "kettle/test/support/shared_contexts/with_rake"

RSpec.describe "rake docs", :check_output do # rubocop:disable RSpec/DescribeClass
  include_context "with rake", "docs" do
    let(:tmp_rakelib) { Dir.mktmpdir("docs_no_task_spec_") }
    let(:task_dir) { tmp_rakelib }
    let(:rakelib) { tmp_rakelib }
  end

  around do |example|
    # Only `yard` is declared here. No `docs` task, which is the pre-fix state.
    File.write(File.join(tmp_rakelib, "docs.rake"), <<~RAKE)
      task :yard do
        puts "YARD_RAN"
      end
    RAKE

    begin
      example.run
    ensure
      Rake::Task.tasks.each(&:clear)
      FileUtils.rm_rf(tmp_rakelib) if File.directory?(tmp_rakelib)
    end
  end

  it "reproduces the silent no-op when no docs task is declared" do
    Dir.mktmpdir do |project|
      FileUtils.mkdir_p(File.join(project, "docs"))
      File.write(File.join(project, "docs", "index.html"), "stale\n")

      # rubocop:disable ThreadSafety/DirChdir
      Dir.chdir(project) do
        # `docs` resolves against the existing directory as an implicit file task.
        task = Rake::Task["docs"]
        expect(task).to be_a(Rake::FileTask)
        expect(task.needed?).to be(false)
        expect(task.prerequisites).to be_empty

        # Invoking it runs nothing: yard is never reached.
        expect { invoke }.not_to output.to_stdout
      end
      # rubocop:enable ThreadSafety/DirChdir
    end
  end
end
