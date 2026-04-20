# frozen_string_literal: true

module TreeHaver
  module BackendRegistry
    module_function

    def register(backend)
      mutex.synchronize do
        backends[backend.id] = deep_dup(backend.to_h)
      end
      nil
    end

    def fetch(id)
      data = mutex.synchronize { backends[id] }
      data && BackendReference.new(**deep_dup(data))
    end

    def all
      mutex.synchronize do
        backends.values.map { |backend| BackendReference.new(**deep_dup(backend)) }
      end
    end

    def clear!
      mutex.synchronize { backends.clear }
    end

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
    private_class_method :deep_dup

    def backends
      @backends ||= {} # rubocop:disable ThreadSafety/MutableClassInstanceVariable
    end
    private_class_method :backends

    def mutex
      @mutex ||= Mutex.new # rubocop:disable ThreadSafety/MutableClassInstanceVariable
    end
    private_class_method :mutex
  end
end
