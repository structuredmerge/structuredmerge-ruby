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

  it "conforms to the tree_haver backend architecture doc inventory fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-847-tree-haver-backend-architecture-doc-inventory",
        "tree-haver-backend-architecture-doc-inventory.json"
      )
    )

    expect(fixture.fetch(:kept_contracts).map { |contract| contract.fetch(:id) }).to eq(
      [
        "normalized-position-api",
        "capability-reporting",
        "explicit-backend-context",
        "scoped-context-restoration",
        "single-normalized-tree-shape"
      ]
    )
    expect(fixture.fetch(:retired_or_downgraded_claims).map { |claim| claim.fetch(:id) }).to include(
      "universal-ruby-backend-adapter",
      "raw-object-wrapping-as-api",
      "thread-local-backend-switching",
      "backend-availability-as-rspec-tags"
    )
    expect(fixture.dig(:provider_guidance, :native_object_retention)).to eq("allowed_internal_only")
    expect(fixture.dig(:provider_guidance, :downstream_tree_shape)).to eq("normalized_tree")
    expect(fixture.dig(:provider_guidance, :project_parser_specific_value_into)).to include(
      "node metadata",
      "semantic sidecars"
    )
    expect(fixture.fetch(:decision)).to include("Port the old position and capability ideas")
  end

  it "conforms to the tree_haver backend implementation inventory fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-848-tree-haver-old-backend-implementation-inventory",
        "tree-haver-old-backend-implementation-inventory.json"
      )
    )
    classifications = fixture.fetch(:classifications).to_h do |entry|
      [entry.fetch(:old_surface), entry]
    end

    expect(classifications.fetch("Backends::MRI").fetch(:classification)).to eq("restored_native_backend")
    expect(classifications.fetch("Backends::FFI").fetch(:replacement)).to eq("TreeHaver::Backends::FFI")
    expect(classifications.fetch("Backends::Rust").fetch(:classification)).to eq("restored_native_backend")
    expect(classifications.fetch("Backends::Java").fetch(:classification)).to eq("restored_native_backend")
    expect(classifications.fetch("Backends::Prism").fetch(:classification)).to eq("provider_local")
    expect(classifications.fetch("Backends::Psych").fetch(:classification)).to eq("provider_local")
    expect(classifications.fetch("Backends::Citrus").fetch(:classification)).to eq("survives_as_peg_primitive")
    expect(classifications.fetch("Backends::Parslet").fetch(:classification)).to eq("survives_as_peg_primitive")
    expect(classifications.fetch("PathValidator").fetch(:classification)).to eq("restored_security_primitive")
    expect(fixture.fetch(:active_backend_requirements)).to include(
      "backend_reference",
      "capability_or_feature_profile_fixture",
      "conformance_path_using_backend"
    )
    expect(fixture.fetch(:current_active_backends).map { |backend| backend.fetch(:backend) }).to include(
      "tslp",
      "kreuzberg-language-pack",
      "mri",
      "rust",
      "ffi",
      "java",
      "citrus",
      "parslet",
      "kaitai-struct"
    )
  end

  it "conforms to the tree_haver grammar library path security model fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-849-tree-haver-grammar-library-path-security-model",
        "tree-haver-grammar-library-path-security-model.json"
      )
    )

    expect(fixture.fetch(:active_security_checks).map { |check| check.fetch(:id) }).to eq(
      [
        "library-path-shape",
        "versioned-shared-object",
        "name-validation",
        "registry-backed-backend-names",
        "stable-error-list"
      ]
    )
    expect(fixture.fetch(:retired_or_inactive_old_behavior).map { |entry| entry.fetch(:id) }).to include(
      "manual-tree-sitter-env-paths",
      "trusted-directory-allowlist",
      "safe-library-search-order"
    )
    expect(fixture.fetch(:current_environment_vocabulary).map { |entry| entry.fetch(:name) }).to include(
      "TREE_HAVER_BACKEND",
      "KETTLE_DEV_DEBUG"
    )
    expect(fixture.fetch(:current_environment_vocabulary).map { |entry| entry.fetch(:loads_native_code) }.uniq).to eq(
      [false]
    )
    expect(fixture.fetch(:future_manual_path_requirements)).to include(
      "trusted_directory_fixture",
      "no_silent_fallback_after_invalid_explicit_path"
    )
    expect(fixture.fetch(:decision)).to include("Do not reintroduce manual grammar shared-library search")
  end

  it "conforms to the Ruby tree_haver reference contract fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-1003-ruby-tree-haver-reference-contract",
        "ruby-tree-haver-reference-contract.json"
      )
    )

    expect(json_ready(described_class.ruby_reference_parser_backend_contract_report)).to eq(
      json_ready(fixture[:expected])
    )
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

  it "conforms to the slice-721 Kaitai tree-haver substrate fixture" do
    fixture = diagnostics_fixture("kaitai_tree_haver_substrate")

    expect(json_ready(described_class::KAITAI_STRUCT_BACKEND.to_h)).to eq(json_ready(fixture[:backend]))
    expect(json_ready(described_class.kaitai_adapter_info.to_h)).to eq(json_ready(fixture[:adapter_info]))
    expect(json_ready(described_class.kaitai_feature_profile.to_h)).to eq(json_ready(fixture[:feature_profile]))

    node_fixture = fixture[:tree_node]
    analysis_fixture = fixture[:analysis]
    child_fixture = node_fixture[:children].first
    node = described_class::KaitaiTreeNode.new(
      kind: node_fixture[:kind],
      schema_path: node_fixture[:schema_path],
      span: described_class::KaitaiByteSpan.new(**node_fixture[:span]),
      fields: node_fixture[:fields],
      children: [
        described_class::KaitaiTreeNode.new(
          kind: child_fixture[:kind],
          schema_path: child_fixture[:schema_path],
          span: described_class::KaitaiByteSpan.new(**child_fixture[:span]),
          fields: child_fixture[:fields],
          children: []
        )
      ]
    )
    analysis = described_class::KaitaiTreeAnalysis.new(
      schema: analysis_fixture[:schema],
      root: node,
      backend_ref: described_class::KAITAI_STRUCT_BACKEND,
      source_byte_length: analysis_fixture[:source_byte_length],
      diagnostics: analysis_fixture[:diagnostics].map do |diagnostic|
        described_class::BinaryDiagnostic.new(
          severity: diagnostic[:severity],
          category: diagnostic[:category],
          message: diagnostic[:message],
          schema_path: diagnostic[:schema_path],
          byte_range: described_class::ByteRange.new(**diagnostic[:byte_range])
        )
      end
    )

    expect(analysis.kind).to eq("kaitai-tree")
    expect(analysis.source_byte_length).to eq(analysis_fixture[:source_byte_length])
    expect(analysis.diagnostics.first.schema_path).to eq(analysis_fixture.dig(:diagnostics, 0, :schema_path))
    expect(json_ready(analysis.root.to_h)).to eq(json_ready(node_fixture))
  end

  it "conforms to the slice-722 portable byte location contract fixture" do
    fixture = diagnostics_fixture("portable_byte_location_contract")
    byte_range = described_class::ByteRange.new(**fixture[:byte_range])
    point = described_class::SourcePoint.new(**fixture[:source_point])
    edit_fixture = fixture[:edit_span]
    edit_span = described_class::ByteEditSpan.new(
      start_byte: edit_fixture[:start_byte],
      old_end_byte: edit_fixture[:old_end_byte],
      new_end_byte: edit_fixture[:new_end_byte],
      start_point: described_class::SourcePoint.new(**edit_fixture[:start_point]),
      old_end_point: described_class::SourcePoint.new(**edit_fixture[:old_end_point]),
      new_end_point: described_class::SourcePoint.new(**edit_fixture[:new_end_point])
    )
    overlapping_range = described_class::ByteRange.new(**fixture.dig(:comparison_ranges, :overlapping))
    disjoint_range = described_class::ByteRange.new(**fixture.dig(:comparison_ranges, :disjoint))

    expect(byte_range.length).to eq(fixture.dig(:expected, :length))
    expect(described_class.slice_byte_range(fixture[:source], byte_range)).to eq(fixture.dig(:expected, :slice))
    expect(byte_range.contains_byte?(byte_range.start_byte)).to eq(fixture.dig(:expected, :contains_start))
    expect(byte_range.contains_byte?(byte_range.end_byte)).to eq(fixture.dig(:expected, :contains_end))
    expect(byte_range.overlaps?(overlapping_range)).to eq(fixture.dig(:expected, :overlaps))
    expect(byte_range.overlaps?(disjoint_range)).to eq(fixture.dig(:expected, :disjoint))
    expect(described_class.byte_offset_for_point(fixture[:source], point)).to eq(fixture.dig(:expected, :line_column_offset))
    expect(edit_span.old_range.length).to eq(fixture.dig(:expected, :old_edit_length))
    expect(edit_span.new_range.length).to eq(fixture.dig(:expected, :new_edit_length))
    expect(edit_span.byte_delta).to eq(fixture.dig(:expected, :edit_delta))
    expect(described_class.slice_byte_range(fixture[:source], edit_span.old_range)).to eq(fixture.dig(:expected, :old_edit_slice))
  end

  it "conforms to the slice-782 normalized tree node fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-782-normalized-tree-node", "normalized-tree-node.json"))

    expect(described_class.node_roles).to eq(fixture[:node_roles])
    node = normalized_tree_node(fixture[:node])
    child = normalized_tree_node(fixture[:child])

    expect(node.role).to eq("structural")
    expect(node.child_ids.fetch(1)).to eq(child.id)
    expect(child.parent_id).to eq(node.id)
    expect(child.field_name).to eq("declaration")
    expect(child.has_source_text).to be(true)
  end

  it "conforms to the slice-786 progressive node metadata fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-786-progressive-node-metadata", "progressive-node-metadata.json"))
    enhanced = normalized_tree_node(fixture[:enhanced_node])
    limited = normalized_tree_node(fixture[:limited_node])

    expect(enhanced.backend_kind).to eq("FuncDecl")
    expect(enhanced.semantic_roles.first).to eq("declaration")
    expect(enhanced.metadata.dig(:go_dst, :node_path)).to eq("decls[0]")
    expect(limited.has_source_text).to be(false)
    expect(limited.unsupported_features.fetch(1)).to eq("source_fragment")
    expect(limited.metadata.dig(:psych, :location_support)).to eq("line_column_only")
  end

  it "conforms to the slice-787 native parser adapter contract fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-787-native-parser-adapter-contract", "native-parser-adapter-contract.json"))
    provider_fixture = fixture[:provider]
    provider = described_class::NativeParserProvider.new(
      id: provider_fixture[:id],
      family: provider_fixture[:family],
      language: provider_fixture[:language],
      operations: provider_fixture[:operations],
      retains_native_tree: provider_fixture[:retains_native_tree],
      native_tree_visibility: provider_fixture[:native_tree_visibility],
      metadata_policy: provider_fixture[:metadata_policy]
    )
    result_fixture = fixture[:parse_result]
    result = described_class::NormalizedParseResult.new(
      ok: result_fixture[:ok],
      backend_capability: backend_capability(result_fixture[:backend_capability]),
      root_id: result_fixture[:root_id],
      nodes: result_fixture[:nodes].map { |node| normalized_tree_node(node) },
      parse_error_tolerance: parse_error_tolerance(result_fixture[:parse_error_tolerance]),
      source_fragments_available: result_fixture[:source_fragments_available],
      diagnostics: result_fixture[:diagnostics],
      metadata: result_fixture[:metadata]
    )

    expect(provider.id).to eq("go-dst")
    expect(provider.retains_native_tree).to be(true)
    expect(provider.native_tree_visibility).to eq("provider_internal")
    expect(result.root_id).to eq(result.nodes.first.id)
    expect(result.nodes.fetch(1).semantic_roles.fetch(1)).to eq("function")
    expect(result.metadata.dig(:go_dst, :native_tree_visibility)).to eq("provider_internal")
    expect(result.source_fragments_available).to be(true)
  end

  it "conforms to the slice-822 native provider metadata fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-822-native-provider-metadata", "native-provider-metadata.json"))
    metadata = described_class::NativeProviderMetadata.new(**fixture[:provider_metadata])

    expect(metadata.provider_id).to eq(fixture.dig(:expected, :provider_id))
    expect(metadata.family).to eq(fixture.dig(:expected, :family))
    expect(metadata.host_language).to eq(fixture.dig(:expected, :host_language))
    expect(metadata.target_language).to eq(fixture.dig(:expected, :target_language))
    expect(metadata.parser_name).to eq(fixture.dig(:expected, :parser_name))
    expect(metadata.parse_error_behavior).to eq(fixture.dig(:expected, :parse_error_behavior))
    expect(metadata.source_span_support).to eq(fixture.dig(:expected, :source_span_support))
    expect(metadata.render_support).to eq(fixture.dig(:expected, :render_support))
    expect(metadata.semantic_role_support).to eq(fixture.dig(:expected, :semantic_role_support))
    expect(metadata.retains_native_tree).to eq(fixture.dig(:expected, :retains_native_tree))
    expect(metadata.metadata_policy).to eq(fixture.dig(:expected, :metadata_policy))
  end

  it "conforms to the slice-788 tree-haver profile fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-788-tree-haver-profile", "tree-haver-profile.json"))
    profile_fixture = fixture[:profile]
    profile = described_class::TreeHaverProfile.new(
      profile_id: profile_fixture[:profile_id],
      language: profile_fixture[:language],
      backend_ref: described_class::BackendReference.new(**profile_fixture[:backend_ref]),
      provider_id: profile_fixture[:provider_id],
      node_roles: profile_fixture[:node_roles],
      normalized_node_fields: profile_fixture[:normalized_node_fields],
      optional_node_features: profile_fixture[:optional_node_features],
      unsupported_defaults: profile_fixture[:unsupported_defaults],
      capability: backend_capability(profile_fixture[:capability]),
      fixture_slices: profile_fixture[:fixture_slices],
      diagnostics: profile_fixture[:diagnostics]
    )

    expect(profile.profile_id).to eq("go-dst-normalized-tree-v1")
    expect(profile.backend_ref.id).to eq("go-dst")
    expect(profile.node_roles.first).to eq("structural")
    expect(profile.normalized_node_fields.last).to eq("metadata")
    expect(profile.unsupported_defaults[:field_name]).to eq("null")
    expect(profile.capability.parser_identity.name).to eq("github.com/dave/dst")
    expect(profile.fixture_slices.first).to eq("slice-782-normalized-tree-node")
  end

  it "conforms to the slice-789 ordered tree primitives fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-789-ordered-tree-primitives", "ordered-tree-primitives.json"))
    ordered_fixture = fixture[:ordered_tree]
    ordered = described_class::OrderedTreePrimitives.new(
      root_id: ordered_fixture[:root_id],
      child_order: ordered_fixture[:child_order],
      sibling_edges: ordered_fixture[:sibling_edges].map do |edge|
        described_class::OrderedSiblingEdge.new(
          parent_id: edge[:parent_id],
          node_id: edge[:node_id],
          previous_sibling_id: edge[:previous_sibling_id],
          next_sibling_id: edge[:next_sibling_id]
        )
      end,
      diagnostics: ordered_fixture[:diagnostics]
    )

    ordered.diagnostics.each do |diagnostic|
      fixture[:forbidden_merge_terms].each do |term|
        expect(diagnostic.downcase).not_to include(term.downcase)
      end
    end

    expect(ordered.root_id).to eq(fixture[:root_id])
    expect(ordered.child_order[:file].fetch(0)).to eq("imports")
    expect(ordered.child_order[:imports].fetch(1)).to eq("import-strings")
    expect(ordered.sibling_edges.fetch(2).previous_sibling_id).to be_nil
    expect(ordered.sibling_edges.fetch(2).next_sibling_id).to eq("import-strings")
  end

  it "conforms to the slice-783 backend capability report fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-783-backend-capability-report", "backend-capability-report.json"))
    capability_fixture = fixture[:capability]
    capability = described_class::BackendCapability.new(
      backend_ref: described_class::BackendReference.new(**capability_fixture[:backend_ref]),
      language: capability_fixture[:language],
      parser_identity: described_class::ParserIdentity.new(**capability_fixture[:parser_identity]),
      language_version: described_class::LanguageVersion.new(**capability_fixture[:language_version]),
      parse_error_behavior: capability_fixture[:parse_error_behavior],
      source_span_support: capability_fixture[:source_span_support],
      source_fragment_support: capability_fixture[:source_fragment_support],
      render_strategies: capability_fixture[:render_strategies],
      semantic_role_support: capability_fixture[:semantic_role_support],
      normalized_tree_support: capability_fixture[:normalized_tree_support],
      native_node_access: capability_fixture[:native_node_access],
      diagnostics: capability_fixture[:diagnostics]
    )

    expect(capability.backend_ref.id).to eq("go-dst")
    expect(capability.backend_ref.family).to eq("native")
    expect(capability.language).to eq("go")
    expect(capability.parser_identity.name).to eq("github.com/dave/dst")
    expect(capability.parse_error_behavior).to eq("diagnostic_and_partial_tree")
    expect(capability.render_strategies.first).to eq("source_fragment_reuse")
    expect(capability.normalized_tree_support).to be(true)
    expect(capability.native_node_access).to be(true)
  end

  it "conforms to the slice-784 source fragment extraction fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-784-source-fragment-extraction", "source-fragment-extraction.json"))
    fragment = described_class.extract_source_fragment(
      fixture[:source],
      source_span(fixture[:span]),
      fixture[:strategy]
    )

    expect(fragment.text).to eq(fixture.dig(:fragment, :text))
    expect(fragment.available).to eq(fixture.dig(:fragment, :available))
    expect(fragment.strategy).to eq(fixture.dig(:fragment, :strategy))
    expect(fragment.byte_length).to eq(fixture.dig(:fragment, :byte_length))
    expect(fragment.diagnostics.length).to eq(fixture.dig(:fragment, :diagnostics).length)
  end

  it "conforms to the slice-785 parse error tolerance fixture" do
    fixture = read_json(fixtures_root.join("diagnostics", "slice-785-parse-error-tolerance", "parse-error-tolerance.json"))
    tolerance_fixture = fixture[:parse_error_tolerance]
    tolerance = described_class::ParseErrorTolerance.new(
      backend_ref: described_class::BackendReference.new(**tolerance_fixture[:backend_ref]),
      language: tolerance_fixture[:language],
      behavior: tolerance_fixture[:behavior],
      tolerates_errors: tolerance_fixture[:tolerates_errors],
      error_nodes: tolerance_fixture[:error_nodes].map do |node|
        described_class::ParseErrorNode.new(
          kind: node[:kind],
          span: source_span(node[:span]),
          message: node[:message]
        )
      end,
      diagnostics: tolerance_fixture[:diagnostics]
    )

    expect(tolerance.backend_ref.id).to eq("tree-sitter-go")
    expect(tolerance.behavior).to eq("diagnostic_and_partial_tree")
    expect(tolerance.tolerates_errors).to be(true)
    expect(tolerance.error_nodes.first.span.range.start_byte).to eq(27)
    expect(tolerance.diagnostics.first).to eq("partial tree contains parser error nodes")
  end

  it "conforms to the slice-723 binary core contract fixture" do
    fixture = diagnostics_fixture("binary_core_contract")
    payload_fixture = fixture[:raw_payload]
    payload = described_class::BinaryRawPayload.new(
      encoding: payload_fixture[:encoding],
      value: payload_fixture[:value],
      byte_length: payload_fixture[:byte_length],
      regions: payload_fixture[:regions].map do |region|
        described_class::BinaryPayloadRegion.new(
          kind: region[:kind],
          schema_path: region[:schema_path],
          byte_range: described_class::ByteRange.new(**region[:byte_range]),
          expected_hex: region[:expected_hex]
        )
      end
    )
    scalar_values = fixture[:scalar_values].map do |item|
      described_class::BinaryScalarValue.new(**item)
    end
    render_policies = fixture[:render_policies].map do |item|
      described_class::BinaryRenderPolicy.new(
        schema_path: item[:schema_path],
        byte_range: described_class::ByteRange.new(**item[:byte_range]),
        operation: item[:operation],
        disposition: item[:disposition],
        reason: item[:reason]
      )
    end
    report_fixture = fixture[:merge_report]
    report = described_class::BinaryMergeReport.new(
      format: report_fixture[:format],
      schema: report_fixture[:schema],
      matched_schema_paths: report_fixture[:matched_schema_paths],
      preserved_ranges: report_fixture[:preserved_ranges].map { |range| described_class::ByteRange.new(**range) },
      rewritten_nodes: report_fixture[:rewritten_nodes],
      checksum_updates: report_fixture[:checksum_updates],
      nested_dispatches: report_fixture[:nested_dispatches].map { |dispatch| described_class::BinaryNestedDispatch.new(**dispatch) },
      diagnostics: report_fixture[:diagnostics].map do |diagnostic|
        described_class::BinaryDiagnostic.new(
          severity: diagnostic[:severity],
          category: diagnostic[:category],
          message: diagnostic[:message],
          schema_path: diagnostic[:schema_path],
          byte_range: diagnostic[:byte_range] && described_class::ByteRange.new(**diagnostic[:byte_range])
        )
      end
    )

    payload_bytes = [payload.value].pack("H*")
    expect(payload.encoding).to eq("hex")
    expect(payload_bytes.bytesize).to eq(payload.byte_length)
    expect(payload.regions.map(&:kind)).to eq(%w[header length body checksum])
    expect(payload.regions.first.byte_range.length).to eq(8)
    expect(payload_bytes.byteslice(payload.regions.last.byte_range.start_byte...payload.regions.last.byte_range.end_byte).unpack1("H*")).to eq(payload.regions.last.expected_hex)
    expect(scalar_values.length).to eq(9)
    expect(scalar_values.first.kind).to eq("string")
    expect(scalar_values.last.kind).to eq("null")
    expect(render_policies[0].operation).to eq("preserve")
    expect(render_policies[1].disposition).to eq("requires_renderer")
    expect(render_policies[2].disposition).to eq("unsafe")
    expect(report.format).to eq("png")
    expect(report.preserved_ranges.first.length).to eq(25)
    expect(report.nested_dispatches.first.family).to eq("text")
    expect(report.diagnostics.first.category).to eq("unsupported_checksum_rewrite")
  end

  def normalized_tree_node(fixture)
    described_class::NormalizedTreeNode.new(
      id: fixture[:id],
      kind: fixture[:kind],
      role: fixture[:role],
      parent_id: fixture[:parent_id],
      child_ids: fixture[:child_ids],
      span: source_span(fixture[:span]),
      field_name: fixture[:field_name],
      named: fixture[:named],
      anonymous: fixture[:anonymous],
      has_source_text: fixture[:has_source_text],
      source_fragment: fixture[:source_fragment],
      backend_kind: fixture[:backend_kind],
      semantic_roles: fixture[:semantic_roles] || [],
      backend_roles: fixture[:backend_roles] || [],
      unsupported_features: fixture[:unsupported_features] || [],
      metadata: fixture[:metadata] || {}
    )
  end

  def backend_capability(fixture)
    described_class::BackendCapability.new(
      backend_ref: described_class::BackendReference.new(**fixture[:backend_ref]),
      language: fixture[:language],
      parser_identity: described_class::ParserIdentity.new(**fixture[:parser_identity]),
      language_version: described_class::LanguageVersion.new(**fixture[:language_version]),
      parse_error_behavior: fixture[:parse_error_behavior],
      source_span_support: fixture[:source_span_support],
      source_fragment_support: fixture[:source_fragment_support],
      render_strategies: fixture[:render_strategies],
      semantic_role_support: fixture[:semantic_role_support],
      normalized_tree_support: fixture[:normalized_tree_support],
      native_node_access: fixture[:native_node_access],
      diagnostics: fixture[:diagnostics]
    )
  end

  def edit_projection_support(fixture)
    described_class::EditProjectionSupport.new(
      backend_ref: described_class::BackendReference.new(**fixture[:backend_ref]),
      language: fixture[:language],
      supports_edit_projection: fixture[:supports_edit_projection],
      native_edit_target: fixture[:native_edit_target],
      normalized_edit_target: fixture[:normalized_edit_target],
      supported_operations: fixture[:supported_operations],
      required_node_fields: fixture[:required_node_fields],
      correlation_keys: fixture[:correlation_keys],
      preserves_source_fragments: fixture[:preserves_source_fragments],
      unsupported_reason: fixture[:unsupported_reason],
      diagnostics: fixture[:diagnostics]
    )
  end

  def backend_availability_report(fixture)
    described_class::BackendAvailabilityReport.new(
      backend_ref: described_class::BackendReference.new(**fixture[:backend_ref]),
      status: fixture[:status],
      checks: fixture[:checks].map do |check|
        described_class::BackendAvailabilityCheck.new(**check)
      end,
      diagnostics: fixture[:diagnostics]
    )
  end

  def provider_diagnostics_report(fixture)
    described_class::ProviderDiagnosticsReport.new(
      provider_id: fixture[:provider_id],
      backend_ref: described_class::BackendReference.new(**fixture[:backend_ref]),
      language: fixture[:language],
      status: fixture[:status],
      diagnostics: fixture[:diagnostics].map do |diagnostic|
        described_class::ProviderDiagnostic.new(**diagnostic)
      end
    )
  end

  def edit_projection_execution_result(fixture)
    described_class::EditProjectionExecutionResult.new(
      ok: fixture[:ok],
      status: fixture[:status],
      source: fixture[:source],
      applied_operations: fixture[:applied_operations].map do |operation|
        described_class::AppliedEditProjectionOperation.new(**operation)
      end,
      diagnostics: fixture[:diagnostics].map do |diagnostic|
        described_class::ProviderDiagnostic.new(**diagnostic)
      end
    )
  end

  def edit_projection_provider_matrix_entry(fixture)
    described_class::EditProjectionProviderMatrixEntry.new(
      provider_id: fixture[:provider_id],
      backend_ref: described_class::BackendReference.new(**fixture[:backend_ref]),
      language: fixture[:language],
      formatting_preservation: fixture[:formatting_preservation],
      preserves_source_fragments: fixture[:preserves_source_fragments],
      operations: fixture[:operations].map do |operation|
        described_class::EditProjectionProviderOperation.new(**operation)
      end
    )
  end

  def edit_projection_provider_matrix(fixture)
    described_class::EditProjectionProviderMatrix.new(
      operations: fixture[:operations],
      providers: fixture[:providers].map { |provider| edit_projection_provider_matrix_entry(provider) },
      diagnostics: fixture[:diagnostics]
    )
  end

  def parse_error_tolerance(fixture)
    described_class::ParseErrorTolerance.new(
      backend_ref: described_class::BackendReference.new(**fixture[:backend_ref]),
      language: fixture[:language],
      behavior: fixture[:behavior],
      tolerates_errors: fixture[:tolerates_errors],
      error_nodes: fixture[:error_nodes].map do |node|
        described_class::ParseErrorNode.new(
          kind: node[:kind],
          span: source_span(node[:span]),
          message: node[:message]
        )
      end,
      diagnostics: fixture[:diagnostics]
    )
  end

  def source_span(fixture)
    described_class::SourceSpan.new(
      range: described_class::ByteRange.new(**fixture[:range]),
      start_point: described_class::SourcePoint.new(**fixture[:start_point]),
      end_point: described_class::SourcePoint.new(**fixture[:end_point])
    )
  end

  it "conforms to the slice-724 and slice-729 ZIP family fixtures" do
    fixture = diagnostics_fixture("zip_family_contract")
    report_fixture = fixture[:merge_report]
    report = described_class::ZipFamilyReport.new(
      archive: described_class::ZipArchiveInfo.new(
        format: fixture.dig(:archive, :format),
        schema: fixture.dig(:archive, :schema),
        entry_count: fixture.dig(:archive, :entry_count),
        central_directory_range: described_class::ByteRange.new(**fixture.dig(:archive, :central_directory_range))
      ),
      entries: fixture[:entries].map do |entry|
        described_class::ZipArchiveEntry.new(
          path: entry[:path],
          normalized_path: entry[:normalized_path],
          directory: entry[:directory],
          compression: entry[:compression],
          compressed_size: entry[:compressed_size],
          uncompressed_size: entry[:uncompressed_size],
          crc32: entry[:crc32],
          local_header_range: described_class::ByteRange.new(**entry[:local_header_range]),
          data_range: described_class::ByteRange.new(**entry[:data_range]),
          central_directory_range: described_class::ByteRange.new(**entry[:central_directory_range])
        )
      end,
      member_decisions: fixture[:member_decisions].map { |decision| described_class::ZipMemberDecision.new(**decision) },
      unsafe_entries: fixture[:unsafe_entries].map { |entry| described_class::ZipUnsafeEntry.new(**entry) },
      merge_report: described_class::BinaryMergeReport.new(
        format: report_fixture[:format],
        schema: report_fixture[:schema],
        matched_schema_paths: report_fixture[:matched_schema_paths],
        preserved_ranges: report_fixture[:preserved_ranges].map { |range| described_class::ByteRange.new(**range) },
        rewritten_nodes: report_fixture[:rewritten_nodes],
        checksum_updates: report_fixture[:checksum_updates],
        nested_dispatches: report_fixture[:nested_dispatches].map { |dispatch| described_class::BinaryNestedDispatch.new(**dispatch) },
        diagnostics: report_fixture[:diagnostics].map { |diagnostic| described_class::BinaryDiagnostic.new(**diagnostic) }
      )
    )

    expect(report.archive.entry_count).to eq(report.entries.length)
    expect(report.member_decisions[1].nested_family).to eq("xml")
    expect(report.unsafe_entries.map(&:category)).to include("path_traversal", "duplicate_normalized_path", "encrypted_member")
    expect(report.merge_report.preserved_ranges.first.length).to eq(76)
  end

  it "conforms to the slice-924 tree_haver edit projection support fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-924-tree-haver-edit-projection-support",
      "edit-projection-support.json"
    ))
    support = edit_projection_support(fixture[:support])
    unsupported = edit_projection_support(fixture[:unsupported])

    expect(support.supports_edit_projection).to be(true)
    expect(support.backend_ref.id).to eq("go-dst")
    expect(support.supported_operations.first).to eq("replace_node")
    expect(support.correlation_keys.fetch(1)).to eq("metadata.go_dst.node_path")
    expect(support.preserves_source_fragments).to be(true)
    expect(support.unsupported_reason).to be_nil

    expect(unsupported.supports_edit_projection).to be(false)
    expect(unsupported.backend_ref.id).to eq("psych")
    expect(unsupported.unsupported_reason).to eq("backend_does_not_retain_native_tree")
    expect(unsupported.supported_operations).to be_empty
    expect(unsupported.diagnostics.first).to eq("edit projection unavailable: native tree not retained")
  end

  it "conforms to the slice-925 tree_haver path validation fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-925-tree-haver-path-validation",
      "path-validation.json"
    ))

    fixture[:library_path_cases].each do |test_case|
      validation = described_class.validate_library_path(test_case[:path])
      expect(validation.path).to eq(test_case[:path])
      expect(validation.valid).to eq(test_case[:expected_valid]), test_case[:name]
      expect(validation.errors).to eq(test_case[:expected_errors]), test_case[:name]
      expect(described_class.library_path_errors(test_case[:path])).to eq(test_case[:expected_errors])
    end

    fixture[:language_name_cases].each do |test_case|
      expect(described_class.safe_language_name?(test_case[:value])).to eq(test_case[:expected_valid]), test_case[:name]
      expect(described_class.sanitize_language_name(test_case[:value])).to eq(test_case[:expected_sanitized]), test_case[:name]
    end

    fixture[:symbol_name_cases].each do |test_case|
      expect(described_class.safe_symbol_name?(test_case[:value])).to eq(test_case[:expected_valid]), test_case[:name]
    end

    fixture[:backend_name_cases].each do |test_case|
      expect(described_class.safe_backend_name?(test_case[:value])).to eq(test_case[:expected_valid]), test_case[:name]
    end
  end

  it "conforms to the slice-926 tree_haver backend availability fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-926-tree-haver-backend-availability",
      "backend-availability.json"
    ))

    %i[available_report unavailable_report unknown_report].each do |name|
      expected = backend_availability_report(fixture[name])
      report = described_class.build_backend_availability_report(expected.backend_ref, expected.checks)
      expect(json_ready(report.to_h)).to eq(json_ready(expected.to_h)), name.to_s
    end
  end

  it "conforms to the slice-927 tree_haver provider diagnostics fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-927-tree-haver-provider-diagnostics",
      "provider-diagnostics.json"
    ))

    %i[clean_report warning_report blocked_report].each do |name|
      expected = provider_diagnostics_report(fixture[name])
      report = described_class.build_provider_diagnostics_report(
        expected.provider_id,
        expected.backend_ref,
        expected.language,
        expected.diagnostics
      )
      expect(json_ready(report.to_h)).to eq(json_ready(expected.to_h)), name.to_s
    end
  end

  it "conforms to the slice-928 edit projection execution contract fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-928-go-dst-edit-projection-execution",
      "edit-projection-execution.json"
    ))

    expected = edit_projection_execution_result(fixture[:expected_result])
    result = described_class.build_edit_projection_execution_result(
      expected.source,
      expected.applied_operations,
      expected.diagnostics
    )
    expect(json_ready(result.to_h)).to eq(json_ready(expected.to_h))

    unsupported = edit_projection_execution_result(fixture[:unsupported_result])
    rejected = described_class.build_edit_projection_execution_result(
      unsupported.source,
      [],
      unsupported.diagnostics
    )
    expect(json_ready(rejected.to_h)).to eq(json_ready(unsupported.to_h))
  end

  it "conforms to the slice-929 insert-child edit projection contract fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-929-go-dst-insert-child-edit-projection",
      "insert-child-edit-projection.json"
    ))

    expected = edit_projection_execution_result(fixture[:expected_result])
    result = described_class.build_edit_projection_execution_result(
      expected.source,
      expected.applied_operations,
      expected.diagnostics
    )
    expect(json_ready(result.to_h)).to eq(json_ready(expected.to_h))
  end

  it "conforms to the slice-930 delete-node edit projection contract fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-930-go-dst-delete-node-edit-projection",
      "delete-node-edit-projection.json"
    ))

    expected = edit_projection_execution_result(fixture[:expected_result])
    result = described_class.build_edit_projection_execution_result(
      expected.source,
      expected.applied_operations,
      expected.diagnostics
    )
    expect(json_ready(result.to_h)).to eq(json_ready(expected.to_h))
  end

  it "conforms to the slice-931 go-parser edit projection contract fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-931-go-parser-edit-projection-execution",
      "edit-projection-execution.json"
    ))

    expected = edit_projection_execution_result(fixture[:expected_result])
    result = described_class.build_edit_projection_execution_result(
      expected.source,
      expected.applied_operations,
      expected.diagnostics
    )
    expect(json_ready(result.to_h)).to eq(json_ready(expected.to_h))
  end

  it "conforms to the slice-932 edit projection provider operation matrix fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-932-edit-projection-provider-operation-matrix",
      "provider-operation-matrix.json"
    ))

    providers = fixture[:providers].map { |provider| edit_projection_provider_matrix_entry(provider) }
    expected = edit_projection_provider_matrix(fixture[:expected_matrix])
    result = described_class.build_edit_projection_provider_matrix(
      fixture[:operations],
      providers,
      []
    )
    expect(json_ready(result.to_h)).to eq(json_ready(expected.to_h))
  end

  it "conforms to the slice-933 go-parser insert-child edit projection contract fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-933-go-parser-insert-child-edit-projection",
      "insert-child-edit-projection.json"
    ))

    expected = edit_projection_execution_result(fixture[:expected_result])
    result = described_class.build_edit_projection_execution_result(
      expected.source,
      expected.applied_operations,
      expected.diagnostics
    )
    expect(json_ready(result.to_h)).to eq(json_ready(expected.to_h))
  end

  it "conforms to the slice-934 go-parser delete-node edit projection contract fixture" do
    fixture = read_json(fixtures_root.join(
      "diagnostics",
      "slice-934-go-parser-delete-node-edit-projection",
      "delete-node-edit-projection.json"
    ))

    expected = edit_projection_execution_result(fixture[:expected_result])
    result = described_class.build_edit_projection_execution_result(
      expected.source,
      expected.applied_operations,
      expected.diagnostics
    )
    expect(json_ready(result.to_h)).to eq(json_ready(expected.to_h))
  end

  it "conforms to the slice-100 process baseline fixture" do
    fixture = diagnostics_fixture("process_baseline")
    result = described_class.process_with_language_pack(
      described_class::ProcessRequest.new(**fixture[:request])
    )

    if result[:ok]
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
    else
      expect(result[:diagnostics]).to contain_exactly(
        include(
          severity: "error",
          category: "unsupported_feature",
          message: include("Please report this to tree-sitter-language-pack")
        )
      )
    end
  end

  it "fails closed when the language-pack result object is unreadable" do
    unreadable_result = Class.new do
      def language
        raise TypeError, "binding accessor failed"
      end
    end.new

    allow(TreeSitterLanguagePack).to receive(:has_language).and_return(true)
    allow(TreeSitterLanguagePack).to receive(:process).and_return(unreadable_result)

    result = described_class.process_with_language_pack(
      described_class::ProcessRequest.new(
        language: "ruby",
        source: "module A\nend\n"
      )
    )

    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to contain_exactly(
      include(
        severity: "error",
        category: "unsupported_feature",
        message: include("Please report this to tree-sitter-language-pack")
      )
    )
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

  it "uses temporary backend context selection when resolving registered parsers" do
    require "toml"
    require "toml-rb"

    described_class.register_language(
      :backend_context_toml,
      grammar_module: TomlRB::Document,
      gem_name: "toml-rb",
    )
    described_class.register_language(
      :backend_context_toml,
      grammar_class: TOML::Parslet,
      gem_name: "toml",
    )

    described_class.with_backend("citrus") do
      expect(described_class.parser_for(:backend_context_toml).backend).to eq(:citrus)
    end

    described_class.with_backend("parslet") do
      expect(described_class.parser_for(:backend_context_toml).backend).to eq(:parslet)
    end
  end

  it "resolves registered external native backend modules without explicit backend selection" do
    backend = Module.new do
      class self::Language
        def self.rbs
          :rbs_language
        end
      end

      class self::Parser
        attr_accessor :language
      end
    end

    described_class.register_language(
      :rbs,
      backend_module: backend,
      backend_type: :rbs,
      gem_name: "rbs",
    )

    parser = described_class.parser_for(:rbs)

    expect(parser).to be_a(backend::Parser)
    expect(parser.language).to eq(:rbs_language)
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
