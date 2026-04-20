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
end
