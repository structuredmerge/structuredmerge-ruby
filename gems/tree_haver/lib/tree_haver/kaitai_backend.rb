# frozen_string_literal: true

module TreeHaver
  KAITAI_STRUCT_BACKEND = BackendReference.new(
    id: 'kaitai-struct',
    family: 'kaitai'
  ).freeze

  BackendRegistry.register(KAITAI_STRUCT_BACKEND)

  module_function

  def kaitai_adapter_info
    AdapterInfo.new(
      backend: KAITAI_STRUCT_BACKEND.id,
      backend_ref: KAITAI_STRUCT_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def kaitai_feature_profile
    FeatureProfile.new(
      backend: KAITAI_STRUCT_BACKEND.id,
      backend_ref: KAITAI_STRUCT_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end
end
