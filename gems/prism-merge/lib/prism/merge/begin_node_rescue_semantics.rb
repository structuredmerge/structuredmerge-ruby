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
        ruby_rescue_semantics.merge_ordered_clause_types(primary_types, secondary_types)
      end

      def canonicalize_rescue_clause_order(clause_types)
        ruby_rescue_semantics.canonicalize_rescue_clause_order(clause_types)
      end

      def canonicalize_begin_clause_kind_order(clause_types)
        ruby_rescue_semantics.canonicalize_begin_clause_kind_order(clause_types)
      end

      private

      def ruby_rescue_semantics
        @ruby_rescue_semantics ||= Ruby::Merge::RescueSemantics.new(
          source_defined_exception_definitions: source_defined_exception_definitions
        )
      end

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

        parse_result = TreeHaver.with_backend(Prism::Merge::BACKEND_REFERENCE.id) do
          TreeHaver.parser_for(:ruby, backend_type: :prism).parse(source).parse_result
        end
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

        parse_result = TreeHaver.with_backend(Prism::Merge::BACKEND_REFERENCE.id) do
          TreeHaver.parser_for(:ruby, backend_type: :prism).parse(source).parse_result
        end
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
        before = source.byteslice(0, start_offset) || +''
        after = source.byteslice(end_offset, source.bytesize - end_offset) || +''
        "#{before}#{replacement}#{after}"
      end

      def rescue_clause_type?(clause_type)
        ruby_rescue_semantics.rescue_clause_type?(clause_type)
      end

      def broad_rescue_clause_type?(clause_type)
        ruby_rescue_semantics.broad_rescue_clause_type?(clause_type)
      end

      def clause_kind_sort_key(clause_type)
        ruby_rescue_semantics.clause_kind_sort_key(clause_type)
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

      def source_defined_exception_definitions
        @source_defined_exception_definitions ||= begin
          definitions = []
          [template_analysis, dest_analysis].compact.each do |analysis|
            next unless analysis.respond_to?(:parse_result) && analysis.parse_result&.respond_to?(:value)

            collect_source_defined_exception_definitions(analysis.parse_result.value, nil, definitions)
          end
          definitions
        end
      end

      def source_defined_exception_hierarchy
        ruby_rescue_semantics.source_defined_exception_hierarchy
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
        ruby_rescue_semantics.resolve_exception_constant(exception_name)
      end

      def rescue_clause_exception_names(clause_type)
        ruby_rescue_semantics.rescue_clause_exception_names(clause_type)
      end

      def rescue_clause_exception_constants(clause_type)
        ruby_rescue_semantics.rescue_clause_exception_constants(clause_type)
      end

      def exception_constant_covers?(covering_constant, covered_constant)
        ruby_rescue_semantics.exception_constant_covers?(covering_constant, covered_constant)
      end

      def source_defined_exception_covers?(covering_name, covered_name)
        ruby_rescue_semantics.source_defined_exception_covers?(covering_name, covered_name)
      end

      def exception_name_covers?(covering_name, covered_name)
        ruby_rescue_semantics.exception_name_covers?(covering_name, covered_name)
      end

      def rescue_clause_covers?(covering_clause_type, covered_clause_type)
        ruby_rescue_semantics.rescue_clause_covers?(covering_clause_type, covered_clause_type)
      end

      def broader_rescue_clause_type_than?(left_clause_type, right_clause_type)
        ruby_rescue_semantics.broader_rescue_clause_type_than?(left_clause_type, right_clause_type)
      end
    end
  end
end
