# frozen_string_literal: true

module TreeHaver
  TSLP_BACKEND = BackendReference.new(
    id: 'tslp',
    family: 'tree-sitter'
  ).freeze
  KREUZBERG_LANGUAGE_PACK_BACKEND = BackendReference.new(
    id: 'kreuzberg-language-pack',
    family: 'tree-sitter'
  ).freeze

  BackendRegistry.register(TSLP_BACKEND)
  BackendRegistry.register(KREUZBERG_LANGUAGE_PACK_BACKEND)
  BackendRegistry.register_availability_checker(:tslp) do
    Backends::Tslp.available?
  end
  BackendRegistry.register_availability_checker(:"kreuzberg-language-pack") do
    BackendRegistry.available?(:tslp)
  end

  module_function

  def language_pack_adapter_info
    AdapterInfo.new(
      backend: TSLP_BACKEND.id,
      backend_ref: TSLP_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def language_pack_feature_profile
    FeatureProfile.new(
      backend: TSLP_BACKEND.id,
      backend_ref: TSLP_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end
end
