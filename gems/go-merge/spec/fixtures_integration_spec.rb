# frozen_string_literal: true

RSpec.describe Go::Merge do
  def fixtures_root = Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  def read_json(path) = Ast::Merge.normalize_value(JSON.parse(path.read))
  def json_ready(value) = Ast::Merge.json_ready(value)

  it "conforms to the Go source-family fixtures" do
    feature = read_json(fixtures_root.join("diagnostics", "slice-109-go-family-feature-profile", "go-feature-profile.json"))
    expect(json_ready(described_class.go_feature_profile)).to eq(json_ready(feature[:feature_profile]))

    analysis_fixture = read_json(fixtures_root.join("go", "slice-110-analysis", "module-owners.json"))
    analysis = described_class.parse_go(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(analysis_fixture.dig(:expected, :owners)))

    matching_fixture = read_json(fixtures_root.join("go", "slice-111-matching", "path-equality.json"))
    template = described_class.parse_go(matching_fixture[:template], "go")
    destination = described_class.parse_go(matching_fixture[:destination], "go")
    matching = described_class.match_go_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(json_ready(matching_fixture.dig(:expected, :matched)))

    merge_fixture = read_json(fixtures_root.join("go", "slice-112-merge", "module-merge.json"))
    merge = described_class.merge_go(merge_fixture[:template], merge_fixture[:destination], "go")
    expect(merge[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge[:output]).to eq(merge_fixture.dig(:expected, :output))
  end
end
