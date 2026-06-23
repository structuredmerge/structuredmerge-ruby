# frozen_string_literal: true

module Ast
  module Merge
    module Runtime
      # Runtime-facing adapter describing one merge implementation that can own
      # and potentially execute merge work for one or more surface families.
      class Delegate
        attr_reader :name,
                    :priority,
                    :surface_kinds,
                    :languages,
                    :feature_profile,
                    :capabilities,
                    :metadata

        def initialize(
          name:,
          priority: 0,
          surface_kinds: nil,
          languages: nil,
          feature_profile: nil,
          capabilities: {},
          supports_surface: nil,
          discover_child_surfaces: nil,
          merge: nil,
          metadata: {}
        )
          @name = name.to_s
          @priority = Integer(priority)
          @surface_kinds = normalize_symbols(surface_kinds)
          @languages = normalize_symbols(languages)
          @feature_profile = feature_profile
          @capabilities = normalize_capabilities(capabilities)
          @supports_surface = supports_surface
          @discover_child_surfaces = discover_child_surfaces
          @merge = merge
          @metadata = metadata.dup.freeze
        end

        def supports?(surface)
          return false unless surface
          return false if surface_kinds.any? && !surface_kinds.include?(surface.surface_kind)

          surface_languages = [surface.effective_language, surface.declared_language].compact
          return false if languages.any? && (surface_languages & languages).empty?

          return true unless @supports_surface

          @supports_surface.call(surface)
        end

        def capability_supported?(capability, surface = nil)
          normalized_capability = capability.to_sym
          rule = capabilities[normalized_capability]

          if rule.nil?
            return !@merge.nil? if normalized_capability == :merge
            return !@discover_child_surfaces.nil? if normalized_capability == :discover_child_surfaces

            return false
          end

          return rule if [true, false].include?(rule)
          return true unless surface

          Array(rule).include?(surface.surface_kind)
        end

        def discover_child_surfaces(operation:, session:)
          return [] unless capability_supported?(:discover_child_surfaces, operation.surface)
          return [] unless @discover_child_surfaces

          Array(@discover_child_surfaces.call(operation: operation, session: session))
        end

        def merge(operation:, session:)
          raise NotImplementedError, "Delegate #{name.inspect} does not expose merge execution" unless @merge
          unless capability_supported?(
            :merge, operation.surface
          )
            raise NotImplementedError,
                  "Delegate #{name.inspect} does not support merge for #{operation.surface.surface_kind}"
          end

          @merge.call(operation: operation, session: session)
        end

        def to_h
          {
            name: name,
            priority: priority,
            surface_kinds: surface_kinds,
            languages: languages,
            feature_profile: feature_profile.respond_to?(:to_h) ? feature_profile.to_h : feature_profile,
            capabilities: capabilities.transform_values { |value| value.is_a?(Array) ? value.dup : value },
            metadata: metadata
          }
        end

        private

        def normalize_symbols(values)
          Array(values).filter_map do |value|
            next if value.nil?

            value.to_s.strip.downcase.tr('-', '_').to_sym
          end.freeze
        end

        def normalize_capabilities(values)
          values.each_with_object({}) do |(capability, surface_kinds), normalized|
            normalized[capability.to_sym] =
              case surface_kinds
              when true, false, nil
                surface_kinds
              else
                Array(surface_kinds).map { |surface_kind| surface_kind.to_s.strip.downcase.tr('-', '_').to_sym }.freeze
              end
          end.freeze
        end
      end
    end
  end
end
