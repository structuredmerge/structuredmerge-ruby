# frozen_string_literal: true

RSpec.describe Kettle::Jem do
  it "documents the disposable Bundler lockfile used by kettle-release" do
    path = File.expand_path("../../lib/kettle/jem/templates/CONTRIBUTING.md.example", __dir__)
    template = File.read(path)

    expect(template).to include(<<~MARKDOWN.chomp)
      The automated `kettle-release` flow runs the build and release tasks with a
      temporary `BUNDLE_LOCKFILE`. Bundler can rewrite a tracked lockfile while
      reconciling the host platform even after the release lockfile has been
      normalized with `bundle lock --add-platform`; that rewrite trips the clean-tree
      guard in `bundler/gem_tasks`. The disposable lockfile preserves the committed
      release inputs while allowing Bundler's runtime reconciliation. Do not replace
      this with `BUNDLE_FROZEN=true`: frozen mode fails when Bundler needs that
      reconciliation.
    MARKDOWN
  end
end
