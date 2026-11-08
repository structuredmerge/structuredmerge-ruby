# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe "generated commit-msg hook", :system do
  let(:template) { File.expand_path("../../lib/kettle/jem/templates/.git-hooks/commit-msg.example", __dir__) }

  def run_hook(message)
    Dir.mktmpdir do |dir|
      hook = File.join(dir, "commit-msg")
      message_file = File.join(dir, "message")
      FileUtils.cp(template, hook)
      File.write(message_file, message)
      Open3.capture3({"RUBYOPT" => nil}, RbConfig.ruby, hook, message_file)
    end
  end

  it "accepts conventional prefixes and legacy emoji-first subjects" do
    ["feat(core): ✨ add feature", "fix: 🐛 repair bug", "feat(api)!: ✨ break API", "✨ add feature"].each do |subject|
      stdout, stderr, status = run_hook(subject)
      expect(status.success?).to be(true), "#{subject}: #{stdout} #{stderr}"
      expect(stderr).not_to include("Skipping gitmoji check")
    end
  end

  it "rejects missing, misplaced, and body-only emoji" do
    ["feat(core): add feature", "feat: add ✨ feature", "feat: add feature\n\n✨ body", "invalid prefix: ✨ feature"].each do |subject|
      stdout, _stderr, status = run_hook(subject)
      expect(status.success?).to be(false), subject
      expect(stdout).to include("Conventional Commit prefix")
    end
  end
end

RSpec.describe "generated commit-subjects-goalie.txt", :system do
  let(:template) { File.expand_path("../../lib/kettle/jem/templates/.git-hooks/commit-subjects-goalie.txt.example", __dir__) }

  def prefixes
    File.read(template).lines.map(&:strip).reject { |l| l.empty? || l.start_with?("#") }
  end

  it "allows footer appending for both legacy emoji-first and prefixed generated subjects" do
    generated_subjects = [
      "🔖 Prepare release v1.0.0",
      "🔒️ Checksums for v1.0.0",
      "chore(release): 🔖 prepare release v1.0.0",
      "chore(checksums): 🔒️ update checksums for v1.0.0",
      "chore(deps): 🔒️ update Bundler lockfiles"
    ]

    generated_subjects.each do |subject|
      expect(prefixes.any? { |p| subject.start_with?(p) }).to be(true), subject
    end
  end

  it "does not match ordinary feature commits" do
    expect(prefixes.any? { |p| "feat(core): ✨ add feature".start_with?(p) }).to be(false)
  end
end
