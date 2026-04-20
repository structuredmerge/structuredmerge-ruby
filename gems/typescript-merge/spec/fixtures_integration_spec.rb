# frozen_string_literal: true

RSpec.describe TypeScript::Merge do
  def fixtures_root = Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  def read_json(path) = Ast::Merge.normalize_value(JSON.parse(path.read))
  def json_ready(value) = Ast::Merge.json_ready(value)

  it "conforms to the TypeScript source-family fixtures" do
    feature = read_json(fixtures_root.join("diagnostics", "slice-101-typescript-family-feature-profile", "typescript-feature-profile.json"))
    expect(json_ready(described_class.type_script_feature_profile)).to eq(json_ready(feature[:feature_profile]))

    analysis_fixture = read_json(fixtures_root.join("typescript", "slice-102-analysis", "module-owners.json"))
    analysis = described_class.parse_type_script(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(analysis_fixture.dig(:expected, :owners)))

    matching_fixture = read_json(fixtures_root.join("typescript", "slice-103-matching", "path-equality.json"))
    template = described_class.parse_type_script(matching_fixture[:template], "typescript")
    destination = described_class.parse_type_script(matching_fixture[:destination], "typescript")
    matching = described_class.match_type_script_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(json_ready(matching_fixture.dig(:expected, :matched)))

    merge_fixture = read_json(fixtures_root.join("typescript", "slice-104-merge", "module-merge.json"))
    merge = described_class.merge_type_script(merge_fixture[:template], merge_fixture[:destination], "typescript")
    expect(merge[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge[:output]).to eq(merge_fixture.dig(:expected, :output))
  end
end
