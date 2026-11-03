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

  describe "multi-line mapping entries" do
    let(:selectors) { described_class::Selectors }
    let(:source) do
      <<~YAML
        stars:
          '2025-01-05': ['12:00:00']
          '2025-01-06':
            - '01:00:00'
            - '02:00:00'
          '2025-01-07': ['03:00:00']
      YAML
    end
    let(:target) { selectors.mapping_entry(path: %w[stars 2025-01-06]) }

    it "spans from the key line through the last value line" do
      owner = described_class.document_context(content: source).structural_owners(owner_scope: :mapping_entries)
                             .find { |o| o.path == %w[stars 2025-01-06] }

      expect([owner.start_line, owner.end_line]).to eq([3, 5])
    end

    it "replaces the whole entry without orphaning the key" do
      result = Ast::Crispr::Replace.result(content: source, target: target,
                                           replacement: "  '2025-01-06': ['09:00:00']\n")

      expect(result.updated_content.scan("'2025-01-06'").length).to eq(1)
      expect(result.updated_content).to include("'2025-01-06': ['09:00:00']")
    end

    it "deletes the whole entry" do
      result = Ast::Crispr::Delete.result(content: source, target: target)

      expect(result.updated_content).not_to include("2025-01-06")
      expect(result.updated_content).not_to include("01:00:00")
    end

    it "inserts after a mapping entry destination" do
      result = Ast::Crispr::Insert.result(content: source, text: "  '2025-01-06b': ['13:00:00']\n",
                                          destination: target)

      expect(result).to be_success
      lines = result.updated_content.lines.map(&:strip).reject(&:empty?)
      expect(lines.index("'2025-01-06b': ['13:00:00']")).to eq(lines.index("- '02:00:00'") + 1)
    end

    it "inserts after a sequence item destination" do
      result = Ast::Crispr::Insert.result(
        content: "list:\n  - a\n  - b\n", text: "  - a2\n",
        destination: selectors.sequence_item(path: %w[list], index: 0)
      )

      expect(result).to be_success
      expect(result.updated_content.lines.map(&:strip).reject(&:empty?)).to eq(["list:", "- a", "- a2", "- b"])
    end
  end
end
