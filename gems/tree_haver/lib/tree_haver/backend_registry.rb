# frozen_string_literal: true

module TreeHaver
  module BackendRegistry
    CATEGORIES = %i[backend gem parsing grammar engine capability other].freeze

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

    def register_availability_checker(name, checker = nil, &block)
      callable = checker || block
      raise ArgumentError, 'Must provide a checker callable or block' unless callable
      raise ArgumentError, 'Checker must respond to #call' unless callable.respond_to?(:call)

      mutex.synchronize do
        availability_checkers[name.to_sym] = callable
        availability_cache.delete(name.to_sym)
      end
      nil
    end

    def available?(name)
      key = name.to_sym
      checker = mutex.synchronize do
        return availability_cache[key] if availability_cache.key?(key)

        availability_checkers[key]
      end
      return false unless checker

      result = checker.call ? true : false
      mutex.synchronize { availability_cache[key] = result }
      result
    rescue StandardError
      false
    end

    def register_tag(tag_name, category:, backend_name: nil, require_path: nil, checker: nil, &block)
      callable = checker || block
      raise ArgumentError, 'Must provide a checker callable or block' unless callable
      raise ArgumentError, 'Checker must respond to #call' unless callable.respond_to?(:call)
      raise ArgumentError, "Invalid category: #{category}" unless CATEGORIES.include?(category)

      tag = tag_name.to_sym
      backend = backend_name || inferred_backend_name(tag)

      mutex.synchronize do
        tag_registry[tag] = {
          category: category,
          backend_name: backend.to_sym,
          require_path: require_path,
          checker: callable
        }
        availability_checkers[backend.to_sym] = callable
        availability_cache.delete(backend.to_sym)
      end

      define_availability_method(backend.to_sym, tag)
      nil
    end

    def registered?(name)
      mutex.synchronize { availability_checkers.key?(name.to_sym) }
    end

    def registered_backends
      mutex.synchronize { availability_checkers.keys.dup }
    end

    def registered_tags
      mutex.synchronize { tag_registry.keys.dup }
    end

    def tags_by_category(category)
      mutex.synchronize do
        tag_registry.select { |_, metadata| metadata[:category] == category }.keys
      end
    end

    def tag_metadata(tag_name)
      mutex.synchronize { tag_registry[tag_name.to_sym]&.dup }
    end

    def tag_registered?(tag_name)
      mutex.synchronize { tag_registry.key?(tag_name.to_sym) }
    end

    def tag_available?(tag_name)
      tag = tag_name.to_sym
      metadata = mutex.synchronize { tag_registry[tag]&.dup }
      return available?(inferred_backend_name(tag)) unless metadata

      if metadata[:require_path]
        begin
          require metadata[:require_path]
        rescue LoadError
          return false
        end
      end

      available?(metadata[:backend_name])
    end

    def tag_summary
      registered_tags.each_with_object({}) do |tag, summary|
        summary[tag] = tag_available?(tag)
      end
    end

    def clear_cache!
      mutex.synchronize { availability_cache.clear }
      nil
    end

    def clear!
      mutex.synchronize do
        backends.clear
        availability_checkers.clear
        availability_cache.clear
        tag_registry.clear
      end
    end

    def inferred_backend_name(tag_name)
      tag = tag_name.to_s
      tag = tag.delete_suffix('_backend')
      tag.to_sym
    end
    private_class_method :inferred_backend_name

    def define_availability_method(backend_name, tag_name)
      return unless defined?(TreeHaver::RSpec::DependencyTags)

      deps = TreeHaver::RSpec::DependencyTags
      method_name = :"#{backend_name}_available?"
      return if deps.respond_to?(method_name)

      ivar = :"@#{backend_name}_available"
      deps.define_singleton_method(method_name) do
        return instance_variable_get(ivar) if instance_variable_defined?(ivar)

        instance_variable_set(ivar, TreeHaver::BackendRegistry.tag_available?(tag_name))
      end
    end
    private_class_method :define_availability_method

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
    private_class_method :deep_dup

    def backends
      @backends ||= {}
    end
    private_class_method :backends

    def mutex
      @mutex ||= Mutex.new
    end
    private_class_method :mutex

    def availability_checkers
      @availability_checkers ||= {}
    end
    private_class_method :availability_checkers

    def availability_cache
      @availability_cache ||= {}
    end
    private_class_method :availability_cache

    def tag_registry
      @tag_registry ||= {}
    end
    private_class_method :tag_registry
  end
end
