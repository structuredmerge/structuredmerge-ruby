# frozen_string_literal: true

module Ast
  module Merge
    module RSpec
      module ConformanceFixtures
        module_function

        def normalize_conformance_fixture_support(value = nil, default_status: nil, **keywords)
          value = keywords unless keywords.empty?

          case value
          when nil, false
            nil
          when true
            { status: (default_status || 'pending').to_s }
          when String, Symbol
            { status: (default_status || value).to_s }
          when Hash
            support = value[:support] || value['support'] || value
            return nil if support == false

            status = support[:status] || support['status'] || support[:state] || support['state']
            status ||= 'unsupported' if support[:unsupported] || support['unsupported']
            status ||= 'pending' if support[:pending] || support['pending']
            status ||= default_status
            return nil unless %w[pending unsupported skipped].include?(status.to_s)

            metadata = { status: status.to_s }
            reason = support[:reason] || support['reason'] ||
                     support[:message] || support['message'] ||
                     support[:unsupported_reason] || support['unsupported_reason'] ||
                     support[:pending_reason] || support['pending_reason']
            metadata[:reason] = reason if reason
            metadata[:category] = support[:category] || support['category'] if support[:category] || support['category']
            metadata
          else
            nil
          end
        end

        def support_for_conformance_fixture(role, pending_roles: nil, unsupported_roles: nil, fixture: nil)
          role_support(pending_roles, role, default_status: 'pending') ||
            role_support(unsupported_roles, role, default_status: 'unsupported') ||
            normalize_conformance_fixture_support(fixture)
        end

        def apply_conformance_fixture_support!(support)
          metadata = normalize_conformance_fixture_support(support)
          return unless metadata

          message = metadata[:reason] || "conformance fixture marked #{metadata[:status]}"
          metadata[:status] == 'pending' ? pending(message) : skip(message)
        end

        def role_support(roles, role, default_status:)
          value =
            if roles.is_a?(Array)
              roles.map(&:to_s).include?(role.to_s) ? true : nil
            elsif roles
              roles[role.to_sym] || roles[role.to_s]
            end
          normalize_conformance_fixture_support(value, default_status: default_status)
        end
        private_class_method :role_support
      end
    end
  end
end
