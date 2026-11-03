# frozen_string_literal: true

RSpec.describe Ast::Crispr::Yaml::Psych do
  it "has a version number" do
    expect(Ast::Crispr::Yaml::Psych::VERSION).not_to be_nil
  end

  describe ".document_context" do
    let(:source) do
      <<~YAML
        jobs:
          test:
            strategy:
              matrix:
                include:
                  - os: ubuntu-latest

                  - os: macos-latest
      YAML
    end
    let(:context) { described_class.document_context(content: source, source_label: ".github/workflows/current.yml") }

    it "reads YAML through psych-merge" do
      expect(context.ast).to be_a(::Psych::Merge::FileAnalysis)
      expect(context.ast).to be_valid
    end

    it "exposes nested mapping entries as structural owners" do
      owners = context.structural_owners(owner_scope: :nested_mapping_entries)

      expect(owners.map(&:key)).to include("os")
      expect(owners.map(&:path)).to include(["jobs", "test", "strategy", "matrix", "include", 0, "os"])
    end

    it "exposes sequence items with their nested owner path and index" do
      owners = context.structural_owners(owner_scope: :sequence_items)
      macos = owners.find { |owner| owner.path == %w[jobs test strategy matrix include].append(1) }

      expect(macos).not_to be_nil
      expect(macos.index).to eq(1)
      expect(macos.node).to be_a(::Psych::Nodes::Mapping)
    end

    it "returns source text for comment regions" do
      commented = described_class.document_context(content: "plugins:\n  # keep this entry\n  - rubocop\n")
      owner = commented.structural_owners(owner_scope: :sequence_items).first
      region = commented.comment_regions_for(owner, owner_scope: :sequence_items).first

      expect(commented.comment_region_text(region)).to include("keep this entry")
    end

    it "populates nested sibling layout gaps for sequence items" do
      analysis = context.ast
      owners = context.structural_owners(owner_scope: :sequence_items)
      ubuntu = owners.find { |owner| owner.index == 0 }
      macos = owners.find { |owner| owner.index == 1 }
      ubuntu_attachment = analysis.layout_attachment_for(ubuntu.wrapper)
      attachment = analysis.layout_attachment_for(macos.wrapper)
      shared_gap = ubuntu_attachment.trailing_gap

      expect(attachment).not_to be_nil
      expect(shared_gap).not_to be_nil
      expect(attachment.leading_gap).to equal(shared_gap)
      expect(shared_gap.effective_controller(removed_owners: [macos.wrapper])).to equal(ubuntu.wrapper)
    end

    it "selects and deletes a nested sequence entry without damaging YAML" do
      selector = described_class::Selectors.sequence_item(
        path: %w[jobs test strategy matrix include],
        index: 1
      )
      result = Ast::Crispr::Delete.result(content: source, target: selector,
                                          source_label: ".github/workflows/current.yml")

      expect(result).to be_success
      expect(result.updated_content).to include("ubuntu-latest")
      expect(result.updated_content).not_to include("macos-latest")
      expect(::Psych::Merge::FileAnalysis.new(result.updated_content)).to be_valid
    end
  end
end
