# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Normalized parsed merge-ruleset configuration.
      class Config
        attr_reader :format,
                    :owners,
                    :match,
                    :read,
                    :attach,
                    :comment_style,
                    :render,
                    :capabilities,
                    :logical_owners,
                    :repair_policies,
                    :surfaces,
                    :delegation_policies,
                    :directives,
                    :source,
                    :path

        class << self
          def load(path)
            raise ArgumentError, "Ruleset file not found: #{path}" unless File.exist?(path)

            parse(File.read(path, encoding: 'UTF-8'), path: path)
          end

          def parse(source, path: nil)
            new(**Parser.parse(source, path: path))
          end
        end

        def initialize(
          source:,
          format:, owners:, match:, read:, attach:, path: nil,
          comment_style: nil,
          render: nil,
          capabilities: {},
          logical_owners: {},
          repair_policies: {},
          surfaces: [],
          delegation_policies: [],
          directives: []
        )
          @source = source.to_s
          @path = path
          @format = format
          @owners = owners
          @match = match
          @read = read
          @attach = attach
          @comment_style = comment_style
          @render = render
          @capabilities = capabilities.dup
          @logical_owners = logical_owners.dup
          @repair_policies = normalize_repair_policies(repair_policies)
          @surfaces = normalize_surfaces(surfaces)
          @delegation_policies = normalize_delegation_policies(delegation_policies)
          @directives = directives.dup
        end

        def to_h
          {
            format: format,
            owners: owners,
            match: match,
            read: read,
            attach: attach,
            comment_style: comment_style,
            render: render,
            capabilities: capabilities.dup,
            logical_owners: logical_owners.dup,
            repair_policies: repair_policies.map(&:to_h),
            surfaces: surfaces.map(&:to_h),
            delegation_policies: delegation_policies.map(&:to_h)
          }.compact
        end

        def attachment_strategy
          attach
        end

        def runtime_declaration(source: :ruleset_config, capability: :full)
          RuntimeTranslator.declaration(self, source: source, capability: capability)
        end

        def feature_profile(source: :ruleset_config, capability: :full)
          RuntimeTranslator.feature_profile(self, source: source, capability: capability)
        end

        def support_style(source:, capability: :full)
          RuntimeTranslator.support_style(self, source: source, capability: capability)
        end

        private

        def normalize_repair_policies(values)
          case values
          when Hash
            values.map { |kind, handling| RepairPolicy.new(kind: kind, handling: handling) }.freeze
          else
            Array(values).map do |value|
              value.is_a?(RepairPolicy) ? value : RepairPolicy.new(**value)
            end.freeze
          end
        end

        def normalize_surfaces(values)
          Array(values).map do |value|
            value.is_a?(SurfaceDeclaration) ? value : SurfaceDeclaration.new(**value)
          end.freeze
        end

        def normalize_delegation_policies(values)
          Array(values).map do |value|
            value.is_a?(DelegationPolicy) ? value : DelegationPolicy.new(**value)
          end.freeze
        end
      end
    end
  end
end
