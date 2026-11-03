# frozen_string_literal: true

# Structural edits (Replace / Delete / Insert) against entries that are not single-line scalars.
# Examples marked `pending` document known gaps (structuredmerge-ruby#105); each one fails if it starts
# passing, which is the cue to drop the `pending` call.
RSpec.describe "Ast::Crispr YAML owner edits" do
  let(:selectors) { Ast::Crispr::Yaml::Psych::Selectors }
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
  let(:context) { Ast::Crispr::Yaml::Psych.document_context(content: source) }
  let(:owners) { context.structural_owners(owner_scope: :mapping_entries) }

  def owner_at(path)
    owners.find { |owner| owner.path == path }
  end

  def key_lines(text, key)
    text.lines.grep(/\A\s*'#{Regexp.escape(key)}':/)
  end

  describe "entries whose key and value share a line" do
    it "reports the line of the entry" do
      owner = owner_at(%w[stars 2025-01-05])

      expect([owner.start_line, owner.end_line]).to eq([2, 2])
    end

    it "replaces the entry in place" do
      result = Ast::Crispr::Replace.result(content: source, target: selectors.mapping_entry(path: %w[stars 2025-01-05]),
                                           replacement: "  '2025-01-05': ['09:00:00']\n")

      expect(result).to be_success
      expect(result.updated_content.lines.first(3)).to eq(["stars:\n", "  '2025-01-05': ['09:00:00']\n", "  '2025-01-06':\n"])
    end

    it "deletes the entry" do
      result = Ast::Crispr::Delete.result(content: source, target: selectors.mapping_entry(path: %w[stars 2025-01-05]))

      expect(result).to be_success
      expect(key_lines(result.updated_content, "2025-01-05")).to be_empty
      expect(YAML.safe_load(result.updated_content)["stars"].keys).to eq(%w[2025-01-06 2025-01-07])
    end
  end

  describe "entries whose value starts on the following line" do
    let(:path) { %w[stars 2025-01-06] }

    it "starts the owner at the line holding the key" do
      pending "owner span starts at the first value line (4), not the key line (3)"
      owner = owner_at(path)

      expect([owner.start_line, owner.end_line]).to eq([3, 5])
    end

    it "replaces the whole entry without leaving the old key behind" do
      pending "the key line survives, leaving a duplicate key"
      result = Ast::Crispr::Replace.result(content: source, target: selectors.mapping_entry(path: path),
                                           replacement: "  '2025-01-06': ['09:00:00']\n")

      expect(result).to be_success
      expect(key_lines(result.updated_content, "2025-01-06").size).to eq(1)
      expect(YAML.safe_load(result.updated_content)["stars"]["2025-01-06"]).to eq(["09:00:00"])
    end

    it "deletes the whole entry without leaving a dangling key" do
      pending "the key line survives as a null value"
      result = Ast::Crispr::Delete.result(content: source, target: selectors.mapping_entry(path: path))

      expect(result).to be_success
      expect(key_lines(result.updated_content, "2025-01-06")).to be_empty
      expect(YAML.safe_load(result.updated_content)["stars"].keys).to eq(%w[2025-01-05 2025-01-07])
    end
  end

  describe "sequence items spanning several lines" do
    let(:list) { "include:\n  - os: ubuntu\n    node: 18\n  - os: macos\n    node: 20\n" }
    let(:list_context) { Ast::Crispr::Yaml::Psych.document_context(content: list) }

    it "spans the whole item, from its dash to its last line" do
      owner = list_context.structural_owners(owner_scope: :sequence_items).find { |o| o.path == ["include", 0] }

      expect([owner.start_line, owner.end_line]).to eq([2, 3])
    end

    it "replaces and deletes the whole item" do
      target = selectors.sequence_item(path: %w[include], index: 0)
      replaced = Ast::Crispr::Replace.result(content: list, target: target, replacement: "  - os: debian\n")
      deleted = Ast::Crispr::Delete.result(content: list, target: target)

      expect(YAML.safe_load(replaced.updated_content)["include"]).to eq([{"os" => "debian"}, {"os" => "macos", "node" => 20}])
      expect(YAML.safe_load(deleted.updated_content)["include"]).to eq([{"os" => "macos", "node" => 20}])
    end
  end

  describe "Insert with a YAML selector as the destination" do
    it "inserts after a mapping entry" do
      pending "YAML selectors define no anchor, so Insert cannot resolve the destination"
      result = Ast::Crispr::Insert.result(content: source, text: "  '2025-01-05b': ['13:00:00']\n",
                                          destination: selectors.mapping_entry(path: %w[stars 2025-01-05]))

      expect(result).to be_success
      expect(YAML.safe_load(result.updated_content)["stars"].keys)
        .to eq(%w[2025-01-05 2025-01-05b 2025-01-06 2025-01-07])
    end

    it "inserts after a sequence item" do
      pending "YAML selectors define no anchor, so Insert cannot resolve the destination"
      list = "plugins:\n  - rubocop\n  - reek\n"
      result = Ast::Crispr::Insert.result(content: list, text: "  - flay\n",
                                          destination: selectors.sequence_item(path: %w[plugins], index: 0))

      expect(result).to be_success
      expect(YAML.safe_load(result.updated_content)["plugins"]).to eq(%w[rubocop flay reek])
    end
  end
end
