# frozen_string_literal: true

module Ast
  module Merge
    # Shared handling contract for suspected corruption / healing sites.
    module Healer
      HANDLINGS = %i[heal warn error skip].freeze

      module_function

      def normalize_mode(value)
        normalized = value.to_sym
        return normalized if HANDLINGS.include?(normalized)

        raise ArgumentError, "Unknown corruption handling mode: #{value.inspect}"
      end

      def handle(mode:, kind:, message:, prefix:, error_class: CorruptionDetectedError, warner: nil)
        normalized = normalize_mode(mode)
        formatted = format_message(prefix: prefix, kind: kind, message: message)

        case normalized
        when :heal
          true
        when :warn
          (warner || Kernel.method(:warn)).call(formatted)
          false
        when :error
          raise error_class, formatted
        when :skip
          false
        else
          raise ArgumentError, "Unknown corruption handling mode: #{normalized.inspect}"
        end
      end

      def format_message(prefix:, kind:, message:)
        "#{prefix} Suspected corruption (#{kind}): #{message}"
      end

      def filter_items(items, mode:, kind:, message:, prefix:, error_class: CorruptionDetectedError, warner: nil,
                       on_filter: nil)
        matches = Array(items).map { |item| [item, yield(item)] }
        return items unless matches.any? { |_, matched| matched }
        return items unless handle(
          mode: mode,
          kind: kind,
          message: message,
          prefix: prefix,
          error_class: error_class,
          warner: warner
        )

        matches.each_with_object([]) do |(item, matched), filtered|
          if matched
            on_filter&.call(item)
          else
            filtered << item
          end
        end
      end
    end
  end
end
