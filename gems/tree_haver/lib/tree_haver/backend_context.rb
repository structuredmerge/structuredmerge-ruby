# frozen_string_literal: true

module TreeHaver
  BACKEND_CONTEXT_KEY = :structured_merge_tree_haver_backend

  module_function

  def current_backend_id
    Thread.current[BACKEND_CONTEXT_KEY]
  end

  def with_backend(backend_id)
    validate_backend_id!(backend_id)

    previous_backend = Thread.current[BACKEND_CONTEXT_KEY]
    Thread.current[BACKEND_CONTEXT_KEY] = backend_id.to_s
    yield
  ensure
    Thread.current[BACKEND_CONTEXT_KEY] = previous_backend
  end

  def validate_backend_id!(backend_id)
    return if BackendRegistry.fetch(backend_id.to_s)

    raise ArgumentError, "Unknown tree_haver backend #{backend_id}."
  end
  private_class_method :validate_backend_id!
end
