# frozen_string_literal: true

module Rbs
  module Merge
    # Produces the stable, location-free projection used for native RBS
    # semantic verification and provider contract extension evidence.
    module NativeProjection
      module_function

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength -- native RBS values require recursive type dispatch
      def call(value)
        case value
        when Array
          value.map { |item| call(item) }
        when Hash
          value.map { |key, item| [call(key), call(item)] }
        when String, Symbol, Numeric, true, false, nil
          value
        else
          attributes = value.instance_variables.reject { |name| %i[@location @comment].include?(name) }
          [
            value.class.name,
            attributes.map { |name| [name, call(value.instance_variable_get(name))] }
          ]
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength
    end
  end
end
