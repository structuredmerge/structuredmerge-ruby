# frozen_string_literal: true

module Ast
  module Merge
    module Runtime
      # Value object describing one owned merge surface.
      class Surface
        attr_reader :surface_kind,
                    :declared_language,
                    :effective_language,
                    :address,
                    :parent_address,
                    :span,
                    :reconstruction_strategy,
                    :metadata

        def initialize(
          surface_kind:,
          address:, declared_language: nil,
          effective_language: nil,
          parent_address: nil,
          span: nil,
          reconstruction_strategy: nil,
          metadata: {}
        )
          @surface_kind = surface_kind&.to_sym
          @declared_language = normalize_language(declared_language)
          @effective_language = normalize_language(effective_language)
          @address = address.to_s
          @parent_address = parent_address&.to_s
          @span = span
          @reconstruction_strategy = reconstruction_strategy&.to_sym
          @metadata = metadata.dup.freeze
        end

        def embedded?
          !parent_address.nil?
        end

        def root?
          !embedded?
        end

        def to_h
          {
            surface_kind: surface_kind,
            declared_language: declared_language,
            effective_language: effective_language,
            address: address,
            parent_address: parent_address,
            span: span,
            reconstruction_strategy: reconstruction_strategy,
            metadata: metadata,
            embedded: embedded?
          }.compact
        end

        private

        def normalize_language(language)
          return if language.nil?

          language.to_s.strip.downcase.tr('-', '_').to_sym
        end
      end
    end
  end
end
