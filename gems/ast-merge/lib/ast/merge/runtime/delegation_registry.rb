# frozen_string_literal: true

module Ast
  module Merge
    module Runtime
      # Registry for selecting a runtime delegate for a surface.
      class DelegationRegistry
        attr_reader :metadata

        def initialize(delegates: [], metadata: {})
          @delegates = []
          @metadata = metadata.dup.freeze
          Array(delegates).each { |delegate| register(delegate) }
        end

        def register(delegate)
          @delegates.reject! { |existing| existing.name == delegate.name }
          @delegates << delegate
          delegate
        end

        def fetch(name)
          @delegates.find { |delegate| delegate.name == name.to_s }
        end

        def delegates
          @delegates.sort_by { |delegate| [-delegate.priority, delegate.name] }
        end

        def matching_delegates(surface, capability: nil)
          delegates.select do |delegate|
            next false unless delegate.supports?(surface)
            next true if capability.nil?

            delegate.capability_supported?(capability, surface)
          end
        end

        def resolve(surface, capability: nil)
          matching_delegates(surface, capability: capability).first
        end

        def to_h
          {
            delegates: delegates.map(&:to_h),
            metadata: metadata
          }
        end
      end
    end
  end
end
