# frozen_string_literal: true

require "tmpdir"

# Covers the top-level `docs` task token.
#
# The gate is inverted from the obvious reading, which is why it needs explicit
# coverage per profile: a token that reads `monorepo_root_template_profile?` and
# returns the task would look correct while fixing the wrong profile.
RSpec.describe Kettle::Jem do
  include_context "with isolated kettle-jem environment"

  # Wraps the profile in a facts hash, which is the shape real runs produce. The
  # token method reads facts[:template_profile], so passing a bare nil would
  # raise; that case is covered separately below.
  def docs_task_token(profile)
    described_class.send(:rake_top_level_docs_task_token, {template_profile: profile})
  end

  def rendered_rakefile(profile)
    template = File.read(File.join(described_class::PACKAGED_TEMPLATE_ROOT, "Rakefile.example"))
    template.gsub("{KJ|RAKE:TOP_LEVEL_DOCS_TASK}", docs_task_token(profile).rstrip)
  end

  # At a monorepo root the family namespace loads, so family:docs exists, and the
  # root has no docs/ directory. `rake docs` there fails loudly with "Don't know
  # how to build task 'docs'", which is an honest error that points at
  # family:docs. Adding a delegating task would only create a second path to
  # behavior the family task already owns.
  it "emits nothing for a monorepo root, where rake docs already fails loudly" do
    expect(docs_task_token(described_class::MONOREPO_ROOT_TEMPLATE_PROFILE)).to eq("")
  end

  # Everywhere else a generated docs/ directory makes Rake resolve the bare name
  # `docs` as an implicit file task that is already up to date, so `rake docs`
  # exits 0 having regenerated nothing. Verified per profile: standalone and
  # monorepo-subgem both have docs/ and no top-level docs task.
  it "emits the delegating task for a standalone gem, where rake docs silently no-ops" do
    token = docs_task_token(described_class::FULL_TEMPLATE_PROFILE)

    expect(token).to include('task docs: "yard"')
    expect(token).to include('desc "Generate YARD documentation"')
  end

  it "emits the delegating task for every monorepo subgem profile" do
    [
      described_class::MONOREPO_SUBGEM_PACKAGE_TEMPLATE_PROFILE,
      described_class::MONOREPO_SUBGEM_RELEASE_TEMPLATE_PROFILE,
      described_class::MONOREPO_SUBGEM_FULL_TEMPLATE_PROFILE
    ].each do |profile|
      expect(docs_task_token(profile)).to include('task docs: "yard"'), "expected a docs task for #{profile}"
    end
  end

  # The task delegates rather than reimplementing document generation, and it must
  # not re-derive at runtime a fact templating already knows. A Dir.exist? probe
  # inside the generated Rakefile would duplicate the profile gate the token
  # itself expresses.
  it "delegates to yard without re-deriving topology at runtime" do
    token = docs_task_token(described_class::FULL_TEMPLATE_PROFILE)

    expect(token).not_to include("Dir.exist?")
    expect(token).not_to include("family:docs")
  end

  # template_tokens rejects any empty-valued token not listed in
  # EMPTY_TEMPLATE_TOKENS, and the resolver runs with on_missing: :keep, so an
  # unlisted empty token is left in the output verbatim and the
  # unresolved-token guard then aborts templating. At a monorepo root this token
  # is exactly empty, so the allowlist entry is what makes the suppressed case
  # render at all rather than failing the run.
  it "is allowlisted so its empty value survives the empty-token rejection" do
    expect(described_class::EMPTY_TEMPLATE_TOKENS).to include("KJ|RAKE:TOP_LEVEL_DOCS_TASK")
  end

  it "is referenced in the packaged Rakefile template" do
    template = File.read(File.join(described_class::PACKAGED_TEMPLATE_ROOT, "Rakefile.example"))

    expect(template).to include("{KJ|RAKE:TOP_LEVEL_DOCS_TASK}")
  end

  # An unknown profile is not a monorepo root, so it must fall through to emitting
  # the task rather than being treated as the suppressed case.
  # normalize_template_profile governs real runs; this asserts the token is
  # tolerant when handed an unrecognized value.
  it "treats an unknown profile as needing the task rather than raising" do
    expect(docs_task_token("no-such-profile")).to include('task docs: "yard"')
  end

  # An explicitly nil profile value is likewise not a root.
  it "treats a nil profile value as needing the task" do
    expect(docs_task_token(nil)).to include('task docs: "yard"')
  end

  # A bare nil facts hash raises, matching monorepo_root_template_profile?, which
  # this delegates to. Asserted so the failure mode is documented rather than
  # discovered later by a caller.
  it "raises on bare nil facts rather than silently emitting" do
    expect do
      described_class.send(:rake_top_level_docs_task_token, nil)
    end.to raise_error(NoMethodError)
  end

  # The token renders empty for monorepo-root, which leaves the surrounding blank
  # lines behind. The render pipeline runs collapse_excess_blank_lines, so this
  # asserts the empty case collapses cleanly rather than trusting that in prose.
  it "collapses to clean spacing when the token renders empty" do
    collapsed = described_class.send(
      :collapse_excess_blank_lines,
      rendered_rakefile(described_class::MONOREPO_ROOT_TEMPLATE_PROFILE)
    )

    # Three or more consecutive newlines would be stray blank lines.
    expect(collapsed.scan(/\n{3,}/)).to be_empty
  end

  # The emitted task lands in a generated Rakefile, so the substituted template
  # must parse. This subsumes checking the token in isolation: if the whole
  # rendered file is valid Ruby, so is the fragment it contributed.
  it "renders parseable Rake when the token is substituted" do
    # Strip the other unresolved tokens so the result is parseable Ruby.
    stripped = rendered_rakefile(described_class::FULL_TEMPLATE_PROFILE).gsub(/\{KJ\|[A-Z0-9_:|]+\}/, "x")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "Rakefile")
      File.write(path, stripped)
      expect(system(RbConfig.ruby, "-c", path, out: File::NULL, err: File::NULL)).to be(true)
    end
  end
end
