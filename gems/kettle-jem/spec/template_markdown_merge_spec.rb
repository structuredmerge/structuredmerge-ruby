# frozen_string_literal: true

RSpec.describe Kettle::Jem do
  it "preserves destination-only Markdown sections while adding template sections" do
    recipe = {target_path: "spec/README.md"}
    template = <<~MARKDOWN
      # Specs

      ## Harness Helpers

      Template-owned helper documentation.
    MARKDOWN
    destination = <<~MARKDOWN
      # Specs

      ## Harness Helpers

      Existing helper documentation.

      ## Worktree Integration Scenarios

      Project-owned worktree documentation.
    MARKDOWN

    result = described_class.send(:merge_config_template_source, recipe, template, destination)

    expect(result).to include("Existing helper documentation.", "## Worktree Integration Scenarios", "Project-owned worktree documentation.")
  end
end
