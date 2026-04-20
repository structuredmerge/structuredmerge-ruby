# frozen_string_literal: true

require "pathname"

RSpec.describe TreeHaver do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def manifest
    @manifest ||= read_json(fixtures_root.join("conformance", "slice-24-manifest", "family-feature-profiles.json"))
  end

  def diagnostics_fixture(role)
    path = Ast::Merge.conformance_fixture_path(manifest, "diagnostics", role)
    raise "missing diagnostics fixture for #{role}" unless path

    read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "conforms to the slice-06 parser request fixture" do
    fixture = diagnostics_fixture("parser_request")

    request = described_class::ParserRequest.new(**fixture[:request])
    expect(json_ready(request.to_h)).to eq(json_ready(fixture[:request]))

    adapter_info = described_class::AdapterInfo.new(
      backend: fixture.dig(:adapter_info, :backend),
      supports_dialects: fixture.dig(:adapter_info, :supports_dialects),
      supported_policies: []
    )
    expect(json_ready(adapter_info.to_h.slice(:backend, :supports_dialects))).to eq(json_ready(fixture[:adapter_info]))
  end

  it "conforms to the slice-19 adapter policy support fixture" do
    fixture = diagnostics_fixture("adapter_policy_support")
    adapter_info = described_class::AdapterInfo.new(
      backend: fixture.dig(:adapter_info, :backend),
      supports_dialects: fixture.dig(:adapter_info, :supports_dialects),
      supported_policies: fixture.dig(:adapter_info, :supported_policies)
    )
    expect(json_ready(adapter_info.to_h.slice(:backend, :supports_dialects, :supported_policies))).to eq(json_ready(fixture[:adapter_info]))
  end

  it "conforms to the slice-20 adapter feature profile fixture" do
    fixture = diagnostics_fixture("adapter_feature_profile")
    profile = described_class::FeatureProfile.new(
      backend: fixture.dig(:feature_profile, :backend),
      supports_dialects: fixture.dig(:feature_profile, :supports_dialects),
      supported_policies: fixture.dig(:feature_profile, :supported_policies)
    )
    expect(json_ready(profile.to_h.slice(:backend, :supports_dialects, :supported_policies))).to eq(json_ready(fixture[:feature_profile]))
  end

  it "conforms to the slice-25 backend registry fixture" do
    fixture = diagnostics_fixture("backend_registry")
    backends = [
      described_class::BackendReference.new(id: "native", family: "builtin"),
      described_class::BackendReference.new(id: "tree-sitter", family: "tree-sitter")
    ]
    expect(json_ready(backends.map(&:to_h))).to eq(json_ready(fixture[:backends]))

    profile = described_class::FeatureProfile.new(
      backend: "tree-sitter",
      backend_ref: backends[1],
      supports_dialects: true,
      supported_policies: []
    )
    expect(json_ready(profile.to_h[:backend_ref])).to eq(json_ready(fixture[:backends][1]))
  end

  it "exposes PEG backend references for parser-plurality slices" do
    expect(json_ready(described_class::CITRUS_BACKEND.to_h)).to eq(
      json_ready({ id: "citrus", family: "peg" })
    )
    expect(json_ready(described_class::PARSLET_BACKEND.to_h)).to eq(
      json_ready({ id: "parslet", family: "peg" })
    )

    expect(json_ready(described_class.peg_adapter_info(described_class::CITRUS_BACKEND).to_h[:backend_ref])).to eq(
      json_ready({ id: "citrus", family: "peg" })
    )
    expect(json_ready(described_class.peg_feature_profile(described_class::PARSLET_BACKEND).to_h[:backend_ref])).to eq(
      json_ready({ id: "parslet", family: "peg" })
    )
  end

  it "conforms to the slice-100 process baseline fixture" do
    fixture = diagnostics_fixture("process_baseline")
    result = described_class.process_with_language_pack(
      described_class::ProcessRequest.new(**fixture[:request])
    )

    expect(result[:ok]).to be(true)
    analysis = result[:analysis]
    expect(analysis.language).to eq(fixture.dig(:expected, :language))
    expect(
      json_ready(
        analysis.structure.map do |item|
          {
            kind: item.kind,
            **(item.name ? { name: item.name } : {})
          }
        end
      )
    ).to eq(json_ready(fixture.dig(:expected, :structure)))
    expect(
      json_ready(
        analysis.imports.map do |item|
          {
            source: item.source,
            items: item.items
          }
        end
      )
    ).to eq(json_ready(fixture.dig(:expected, :imports)))
  end

  it "supports temporary backend context selection" do
    expect(described_class.current_backend_id).to be_nil

    described_class.with_backend("citrus") do
      expect(described_class.current_backend_id).to eq("citrus")

      described_class.with_backend("parslet") do
        expect(described_class.current_backend_id).to eq("parslet")
      end

      expect(described_class.current_backend_id).to eq("citrus")
    end

    expect(described_class.current_backend_id).to be_nil
  end

  it "provides PEG framework parsing helpers" do
    require "toml"
    require "toml-rb"

    citrus = described_class.parse_with_citrus("title = \"x\"\n", grammar_module: TomlRB::Document)
    expect(citrus[:ok]).to be(true)
    expect(json_ready(citrus[:backend_ref].to_h)).to eq(json_ready({ id: "citrus", family: "peg" }))

    parslet = described_class.parse_with_parslet("title = \"x\"\n", grammar_class: TOML::Parslet)
    expect(parslet[:ok]).to be(true)
    expect(json_ready(parslet[:backend_ref].to_h)).to eq(json_ready({ id: "parslet", family: "peg" }))
  end
end
