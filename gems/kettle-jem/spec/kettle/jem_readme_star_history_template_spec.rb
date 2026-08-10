# frozen_string_literal: true

RSpec.describe Kettle::Jem do
  include_context "with isolated kettle-jem environment"

  it "keeps Star History at the minimum live GitHub star count" do
    expect(described_class.send(:github_repository_slug, "ssh://git@github.com/acme/example-gem.git")).to eq(
      "acme/example-gem"
    )

    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).with(
      "gh",
      "api",
      "repos/acme/example-gem",
      "--jq",
      ".stargazers_count",
      chdir: "/project"
    ).and_return(["149\n", "", status], ["150\n", "", status])

    below_minimum = described_class.send(
      :readme_star_history_facts,
      "/project",
      "git@github.com:acme/example-gem.git"
    )
    at_minimum = described_class.send(
      :readme_star_history_facts,
      "/project",
      "https://github.com/acme/example-gem"
    )

    expect(below_minimum).to include(
      enabled: false,
      repository: "acme/example-gem",
      stars: 149,
      minimum_stars: 150
    )
    expect(at_minimum).to include(
      enabled: true,
      repository: "acme/example-gem",
      stars: 150,
      minimum_stars: 150
    )
  end

  it "fails closed when there is no GitHub remote" do
    expect(described_class).not_to receive(:github_repository_star_count)

    facts = described_class.send(:readme_star_history_facts, "/project", nil)

    expect(facts).to eq(enabled: false, reason: "no_github_remote")
  end

  it "fails closed when gh cannot return a star count" do
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).and_return(["", "not authenticated", status])

    facts = described_class.send(
      :readme_star_history_facts,
      "/project",
      "https://github.com/acme/example-gem"
    )

    expect(facts).to eq(
      enabled: false,
      repository: "acme/example-gem",
      reason: "star_count_unavailable"
    )
  end

  it "removes the complete Star History block when it is disabled" do
    content = <<~MARKDOWN
      Before.

      <details markdown="1">
      <summary>⭐️ Star History</summary>

      chart
      </details>
      After.
    MARKDOWN

    kept = described_class.send(
      :apply_readme_conditional_blocks,
      content,
      repository: {star_history: {enabled: true}}
    )
    removed = described_class.send(
      :apply_readme_conditional_blocks,
      content,
      repository: {star_history: {enabled: false}}
    )

    expect(kept).to include("<summary>⭐️ Star History</summary>")
    expect(kept).not_to include("KJ:STAR_HISTORY")
    expect(removed).not_to include("Star History")
    expect(removed).not_to include("chart")
  end
end
