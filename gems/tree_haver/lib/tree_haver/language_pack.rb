# frozen_string_literal: true

require "json"
require "tree_sitter_language_pack"

module TreeHaver
  KREUZBERG_LANGUAGE_PACK_BACKEND = BackendReference.new(
    id: "kreuzberg-language-pack",
    family: "tree-sitter"
  ).freeze

  BackendRegistry.register(KREUZBERG_LANGUAGE_PACK_BACKEND)

  module_function

  def language_pack_adapter_info
    AdapterInfo.new(
      backend: KREUZBERG_LANGUAGE_PACK_BACKEND.id,
      backend_ref: KREUZBERG_LANGUAGE_PACK_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def language_pack_feature_profile
    FeatureProfile.new(
      backend: KREUZBERG_LANGUAGE_PACK_BACKEND.id,
      backend_ref: KREUZBERG_LANGUAGE_PACK_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def parse_with_language_pack(request)
    ensure_language_pack_language(request.language)
    raw = TreeSitterLanguagePack.process(
      request.source,
      JSON.generate(language: request.language, diagnostics: true)
    )
    diagnostics = Array(raw["diagnostics"])
    return parse_error_result(request.language) unless diagnostics.empty?

    analysis = LanguagePackAnalysis.new(
      language: request.language,
      dialect: request.dialect,
      root_type: inferred_root_type(request),
      has_error: false,
      backend_ref: KREUZBERG_LANGUAGE_PACK_BACKEND
    )
    parse_result(ok: true, analysis: analysis, diagnostics: [])
  rescue StandardError => e
    parse_result(
      ok: false,
      diagnostics: [diagnostic("error", "unsupported_feature", e.message)]
    )
  end

  def process_with_language_pack(request)
    ensure_language_pack_language(request.language)
    raw = TreeSitterLanguagePack.process(
      request.source,
      JSON.generate(language: request.language, structure: true, imports: true, diagnostics: true)
    )
    analysis = LanguagePackProcessAnalysis.new(
      language: raw.fetch("language"),
      structure: Array(raw["structure"]).map do |item|
        ProcessStructureItem.new(
          kind: item.fetch("kind").downcase,
          name: item["name"],
          span: process_span(item.fetch("span"))
        )
      end,
      imports: normalize_imports(request.language, Array(raw["imports"])),
      diagnostics: Array(raw["diagnostics"]).map do |item|
        ProcessDiagnostic.new(
          message: item.fetch("message"),
          severity: item.fetch("severity")
        )
      end,
      backend_ref: KREUZBERG_LANGUAGE_PACK_BACKEND
    )
    parse_result(ok: true, analysis: analysis, diagnostics: [])
  rescue StandardError => e
    parse_result(
      ok: false,
      diagnostics: [diagnostic("error", "unsupported_feature", e.message)]
    )
  end

  def ensure_language_pack_language(language)
    return if TreeSitterLanguagePack.has_language(language)

    TreeSitterLanguagePack.init(JSON.generate(languages: [language]))
  end
  private_class_method :ensure_language_pack_language

  def parse_error_result(language)
    parse_result(
      ok: false,
      diagnostics: [
        diagnostic(
          "error",
          "parse_error",
          "tree-sitter-language-pack reported syntax errors for #{language}."
        )
      ]
    )
  end
  private_class_method :parse_error_result

  def process_span(raw)
    ProcessSpan.new(
      start_byte: raw.fetch("start_byte"),
      end_byte: raw.fetch("end_byte"),
      start_row: raw["start_row"] || raw.fetch("start_line"),
      start_col: raw["start_col"] || raw.fetch("start_column"),
      end_row: raw["end_row"] || raw.fetch("end_line"),
      end_col: raw["end_col"] || raw.fetch("end_column")
    )
  end
  private_class_method :process_span

  def inferred_root_type(request)
    stripped = request.source.lstrip
    case request.language
    when "json"
      return "object" if stripped.start_with?("{")
      return "array" if stripped.start_with?("[")

      "scalar"
    else
      request.language
    end
  end
  private_class_method :inferred_root_type

  def normalize_imports(language, raw_imports)
    raw_imports.map do |item|
      source, items =
        if language == "typescript"
          normalize_typescript_import(item)
        else
          [item["module"] || item["source"] || "", Array(item["names"] || item["items"])]
        end

      ProcessImportInfo.new(
        source: source,
        items: items,
        span: process_span(item.fetch("span"))
      )
    end
  end
  private_class_method :normalize_imports

  def normalize_typescript_import(item)
    raw_source = item["module"] || item["source"] || ""
    source_match = raw_source.match(/from\s+['"]([^'"]+)['"]|import\s+['"]([^'"]+)['"]/)
    source = source_match&.captures&.compact&.first || raw_source.strip
    names = if (named_items = raw_source.match(/\{([^}]+)\}/))
      named_items[1]
        .split(",")
        .map { |part| part.gsub(/\btype\b/, "").strip }
        .reject(&:empty?)
    else
      Array(item["names"] || item["items"])
    end

    [source, names]
  end
  private_class_method :normalize_typescript_import

  def parse_result(ok:, diagnostics:, analysis: nil, policies: [])
    {
      ok: ok,
      diagnostics: diagnostics,
      **(analysis ? { analysis: analysis } : {}),
      policies: policies
    }
  end
  private_class_method :parse_result

  def diagnostic(severity, category, message)
    {
      severity: severity,
      category: category,
      message: message
    }
  end
  private_class_method :diagnostic
end
