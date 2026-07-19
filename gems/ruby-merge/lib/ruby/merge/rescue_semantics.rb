# frozen_string_literal: true

module Ruby
  module Merge
    class RescueSemantics
      def initialize(source_defined_exception_definitions: [])
        @source_defined_exception_definitions = source_defined_exception_definitions
      end

      def merge_ordered_clause_types(primary_types, secondary_types)
        ordered = primary_types.dup

        secondary_types.each_with_index do |clause_type, secondary_index|
          next if ordered.include?(clause_type)

          previous_shared = secondary_types[0...secondary_index].reverse.find { |type| ordered.include?(type) }
          next_shared = secondary_types[(secondary_index + 1)..]&.find { |type| ordered.include?(type) }

          if previous_shared
            insert_at = ordered.index(previous_shared) + 1
            ordered.insert(insert_at, clause_type)
          elsif next_shared
            insert_at = ordered.index(next_shared)
            ordered.insert(insert_at, clause_type)
          else
            ordered << clause_type
          end
        end

        ordered
      end

      def canonicalize_rescue_clause_order(clause_types)
        rescue_clause_types = clause_types.select { |clause_type| rescue_clause_type?(clause_type) }
        return clause_types if rescue_clause_types.length < 2

        ordered_rescue_types = rescue_clause_types.dup

        if rescue_clause_types.any? { |clause_type| broad_rescue_clause_type?(clause_type) } &&
           rescue_clause_types.any? { |clause_type| !broad_rescue_clause_type?(clause_type) }
          specific_rescue_types = ordered_rescue_types.reject { |clause_type| broad_rescue_clause_type?(clause_type) }
          broad_rescue_types = ordered_rescue_types.select { |clause_type| broad_rescue_clause_type?(clause_type) }
          ordered_rescue_types = specific_rescue_types + broad_rescue_types
        end

        loop do
          swapped = false

          (0...(ordered_rescue_types.length - 1)).each do |index|
            left_clause_type = ordered_rescue_types[index]
            right_clause_type = ordered_rescue_types[index + 1]
            next unless broader_rescue_clause_type_than?(left_clause_type, right_clause_type)

            ordered_rescue_types[index] = right_clause_type
            ordered_rescue_types[index + 1] = left_clause_type
            swapped = true
          end

          break unless swapped
        end

        clause_types.map do |clause_type|
          rescue_clause_type?(clause_type) ? ordered_rescue_types.shift : clause_type
        end
      end

      def canonicalize_begin_clause_kind_order(clause_types)
        clause_types.each_with_index
                    .sort_by { |(clause_type, index)| [clause_kind_sort_key(clause_type), index] }
                    .map(&:first)
      end

      def rescue_clause_signature(exception_names)
        normalized_exceptions = Array(exception_names).filter_map { |exception| normalize_exception_name(exception) }
        if normalized_exceptions.empty? || normalized_exceptions == ['StandardError']
          [:standard_error]
        else
          normalized_exceptions.sort
        end
      end

      def rescue_clause_type?(clause_type)
        clause_type.is_a?(Array) && clause_type.first == :rescue_clause
      end

      def broad_rescue_clause_type?(clause_type)
        rescue_clause_type?(clause_type) && clause_type[1] == [:standard_error]
      end

      def clause_kind_sort_key(clause_type)
        return 0 if rescue_clause_type?(clause_type)
        return 1 if clause_type == :else_clause
        return 2 if clause_type == :ensure_clause

        3
      end

      def normalize_exception_name(exception_name)
        return 'StandardError' if exception_name == :standard_error

        name = exception_name.to_s.sub(/\A::/, '')
        name.empty? ? nil : name
      end

      def qualify_source_constant_name(constant_name, namespace = nil)
        normalized_name = normalize_exception_name(constant_name)
        return if normalized_name.nil?
        return normalized_name if constant_name.to_s.start_with?('::') || namespace.nil? || namespace.empty?

        "#{namespace}::#{normalized_name}"
      end

      def source_defined_exception_hierarchy
        @source_defined_exception_hierarchy ||= begin
          definitions = @source_defined_exception_definitions
          defined_names = definitions.map { |definition| definition[:name] }.compact.to_set

          definitions.each_with_object({}) do |definition, hierarchy|
            next unless definition[:name] && definition[:superclass]

            superclass_name = if definition[:superclass].to_s.start_with?('::')
                                normalize_exception_name(definition[:superclass])
                              else
                                candidate_name = qualify_source_constant_name(definition[:superclass],
                                                                              definition[:namespace])
                                defined_names.include?(candidate_name) ? candidate_name : normalize_exception_name(definition[:superclass])
                              end

            hierarchy[definition[:name]] ||= superclass_name if superclass_name
          end
        end
      end

      def resolve_exception_constant(exception_name)
        return ::StandardError if exception_name == :standard_error
        return unless exception_name.is_a?(String) && !exception_name.empty?

        exception_name.split('::').reject(&:empty?).inject(Object) { |scope, const_name| scope.const_get(const_name) }
      rescue NameError
        nil
      end

      def rescue_clause_exception_names(clause_type)
        return [] unless rescue_clause_type?(clause_type)

        Array(clause_type[1]).filter_map { |exception_name| normalize_exception_name(exception_name) }
      end

      def rescue_clause_exception_constants(clause_type)
        rescue_clause_exception_names(clause_type).filter_map do |exception_name|
          resolve_exception_constant(exception_name)
        end
      end

      def exception_constant_covers?(covering_constant, covered_constant)
        return true if covering_constant == covered_constant

        covered_constant < covering_constant
      rescue StandardError
        false
      end

      def source_defined_exception_covers?(covering_name, covered_name)
        normalized_covering = normalize_exception_name(covering_name)
        current_name = normalize_exception_name(covered_name)
        return false if normalized_covering.nil? || current_name.nil?
        return true if normalized_covering == current_name

        while (current_name = source_defined_exception_hierarchy[current_name])
          return true if current_name == normalized_covering
        end

        false
      end

      def exception_name_covers?(covering_name, covered_name)
        covering_constant = resolve_exception_constant(covering_name)
        covered_constant = resolve_exception_constant(covered_name)

        if covering_constant && covered_constant
          exception_constant_covers?(covering_constant, covered_constant)
        else
          source_defined_exception_covers?(covering_name, covered_name)
        end
      end

      def rescue_clause_covers?(covering_clause_type, covered_clause_type)
        return false unless rescue_clause_type?(covering_clause_type) && rescue_clause_type?(covered_clause_type)

        covering_names = rescue_clause_exception_names(covering_clause_type)
        covered_names = rescue_clause_exception_names(covered_clause_type)
        return false if covering_names.empty? || covered_names.empty?

        covered_names.all? do |covered_name|
          covering_names.any? do |covering_name|
            exception_name_covers?(covering_name, covered_name)
          end
        end
      end

      def broader_rescue_clause_type_than?(left_clause_type, right_clause_type)
        return false unless rescue_clause_type?(left_clause_type) && rescue_clause_type?(right_clause_type)

        rescue_clause_covers?(left_clause_type, right_clause_type) &&
          !rescue_clause_covers?(right_clause_type, left_clause_type)
      end
    end
  end
end
