# frozen_string_literal: true

module TreeHaver
  CITRUS_BACKEND = BackendReference.new(
    id: "citrus",
    family: "peg"
  ).freeze

  PARSLET_BACKEND = BackendReference.new(
    id: "parslet",
    family: "peg"
  ).freeze

  BackendRegistry.register(CITRUS_BACKEND)
  BackendRegistry.register(PARSLET_BACKEND)

  module_function

  def peg_adapter_info(backend_ref)
    AdapterInfo.new(
      backend: backend_ref.id,
      backend_ref: backend_ref,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def peg_feature_profile(backend_ref)
    FeatureProfile.new(
      backend: backend_ref.id,
      backend_ref: backend_ref,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def parse_with_citrus(source, grammar_module:)
    raw = grammar_module.parse(source)
    if raw&.respond_to?(:captures)
      {
        ok: true,
        backend_ref: CITRUS_BACKEND,
        raw: raw,
        diagnostics: []
      }
    else
      {
        ok: false,
        backend_ref: CITRUS_BACKEND,
        diagnostics: [{ severity: "error", category: "parse_error", message: "Citrus parse failed." }]
      }
    end
  rescue StandardError => e
    {
      ok: false,
      backend_ref: CITRUS_BACKEND,
      diagnostics: [{ severity: "error", category: "parse_error", message: e.message }]
    }
  end

  def parse_with_parslet(source, grammar_class:)
    raw = grammar_class.new.parse(source)
    {
      ok: true,
      backend_ref: PARSLET_BACKEND,
      raw: raw,
      diagnostics: []
    }
  rescue StandardError => e
    {
      ok: false,
      backend_ref: PARSLET_BACKEND,
      diagnostics: [{ severity: "error", category: "parse_error", message: e.message }]
    }
  end
end
