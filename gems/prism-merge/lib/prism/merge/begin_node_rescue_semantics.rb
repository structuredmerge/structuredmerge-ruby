# frozen_string_literal: true

module Prism
  module Merge
    class BeginNodeRescueSemantics
      attr_reader :template_analysis, :dest_analysis

      def initialize(template_analysis:, dest_analysis:)
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
      end

      def normalized_clause_body_and_header_source(template_clause_node:, dest_clause_node:, clause_body:,
                                                   preferred_source:)
        unless template_clause_node.type.to_s == 'rescue_node' && dest_clause_node.type.to_s == 'rescue_node'
          return { header_source: preferred_source,
                   clause_body: clause_body }
        end

        template_reference = rescue_node_reference_name(template_clause_node)
        dest_reference = rescue_node_reference_name(dest_clause_node)
        return { header_source: preferred_source, clause_body: clause_body } if template_reference == dest_reference

        merged_references = local_variable_read_names_in_source(clause_body)
        needs_template_reference = template_reference && merged_references.include?(template_reference)
        needs_dest_reference = dest_reference && merged_references.include?(dest_reference)

        header_source = if needs_dest_reference && !needs_template_reference
                          :destination
                        elsif needs_template_reference && !needs_dest_reference
                          :template
                        else
                          preferred_source
                        end

        chosen_reference = header_source == :template ? template_reference : dest_reference
        alternate_reference = header_source == :template ? dest_reference : template_reference
        normalized_body = if chosen_reference && alternate_reference && merged_references.include?(alternate_reference)
                            rewrite_local_reference_in_source(clause_body, from: alternate_reference,
                                                                           to: chosen_reference)
                          else
                            clause_body
                          end

        { header_source: header_source, clause_body: normalized_body }
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

      private

      def rescue_node_reference_name(rescue_node)
        return unless rescue_node.type.to_s == 'rescue_node'

        reference = rescue_node.reference if rescue_node.respond_to?(:reference)
        return unless reference

        return reference.slice if reference.respond_to?(:slice)
        return reference.name.to_s if reference.respond_to?(:name)

        reference.to_s
      end

      def local_variable_read_names_in(node, names = [])
        return names unless node

        if node.type.to_s == 'local_variable_read_node'
          names << node.name.to_s
        elsif node.type.to_s == 'call_node' && node.respond_to?(:variable_call?) && node.variable_call?
          names << node.name.to_s
        end
        if node.respond_to?(:compact_child_nodes)
          node.compact_child_nodes.each do |child|
            local_variable_read_names_in(child, names)
          end
        end
        names
      end

      def local_variable_read_names_in_source(source)
        return [] if source.to_s.strip.empty?

        parse_result = TreeHaver.parser_for(:ruby).parse(source).parse_result
        return [] unless parse_result.success?

        local_variable_read_names_in(parse_result.value).uniq
      end

      def local_reference_node_named?(node, name)
        return false unless node && name

        if node.type.to_s == 'local_variable_read_node'
          node.name.to_s == name
        elsif node.type.to_s == 'call_node' && node.respond_to?(:variable_call?) && node.variable_call?
          node.name.to_s == name
        else
          false
        end
      end

      def local_reference_offsets_in(node, name, offsets = [])
        return offsets unless node

        if local_reference_node_named?(node, name) && node.respond_to?(:location) && node.location
          offsets << [node.location.start_offset, node.location.length]
        end

        if node.respond_to?(:compact_child_nodes)
          node.compact_child_nodes.each do |child|
            local_reference_offsets_in(child, name, offsets)
          end
        end
        offsets
      end

      def rewrite_local_reference_in_source(source, from:, to:)
        return source if from.nil? || to.nil? || from == to || source.to_s.empty?

        parse_result = TreeHaver.parser_for(:ruby).parse(source).parse_result
        return source unless parse_result.success?

        offsets = local_reference_offsets_in(parse_result.value, from)
        return source if offsets.empty?

        rewritten = source.dup
        offsets.sort_by(&:first).reverse_each do |start_offset, length|
          rewritten = replace_byte_range(rewritten, start_offset, start_offset + length, to)
        end
        rewritten
      end

      def replace_byte_range(source, start_offset, end_offset, replacement)
        before = source.byteslice(0, start_offset) || +""
        after = source.byteslice(end_offset, source.bytesize - end_offset) || +""
        "#{before}#{replacement}#{after}"
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
          definitions = []
          [template_analysis, dest_analysis].compact.each do |analysis|
            next unless analysis.respond_to?(:parse_result) && analysis.parse_result&.respond_to?(:value)

            collect_source_defined_exception_definitions(analysis.parse_result.value, nil, definitions)
          end

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

      def collect_source_defined_exception_definitions(node, namespace, definitions)
        return unless node

        case node
        when Prism::ProgramNode
          collect_source_defined_exception_definitions(node.statements, namespace, definitions)
        when Prism::StatementsNode
          node.body.each { |child| collect_source_defined_exception_definitions(child, namespace, definitions) }
        when Prism::ModuleNode
          module_name = qualify_source_constant_name(node.constant_path.slice, namespace)
          collect_source_defined_exception_definitions(node.body, module_name, definitions)
        when Prism::ClassNode
          class_name = qualify_source_constant_name(node.constant_path.slice, namespace)
          definitions << {
            name: class_name,
            namespace: namespace,
            superclass: node.superclass&.slice
          }
          collect_source_defined_exception_definitions(node.body, class_name, definitions)
        else
          if node.respond_to?(:compact_child_nodes)
            node.compact_child_nodes.each do |child|
              collect_source_defined_exception_definitions(child, namespace, definitions)
            end
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
