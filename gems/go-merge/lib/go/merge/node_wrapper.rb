# frozen_string_literal: true

module Go
  module Merge
    # Structural identity and source-range adapter for a top-level Go AST node.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength -- Go declaration forms share one structural identity boundary
    class NodeWrapper
      DECLARATION_TYPES = %w[
        const_declaration
        function_declaration
        import_declaration
        method_declaration
        package_clause
        type_declaration
        var_declaration
      ].freeze
      GROUP_SPEC_TYPES = %w[const_spec import_spec type_spec var_spec].freeze

      attr_reader :node, :source, :leading_comments, :trailing_comments

      def initialize(node, source:, leading_comments: [])
        @node = node
        @source = source
        @leading_comments = leading_comments.freeze
        @trailing_comments = []
      end

      def signature
        case node.type
        when 'package_clause'
          [:package, required_descendant_text(node, 'package_identifier')]
        when 'import_declaration'
          import_signature
        when 'function_declaration'
          [:function, required_direct_child_text(node, 'identifier')]
        when 'method_declaration'
          [:method, receiver_type_name, required_direct_child_text(node, 'field_identifier')]
        when 'type_declaration'
          declaration_signature(:type, 'type_spec', 'type_identifier')
        when 'const_declaration'
          declaration_signature(:const, 'const_spec', 'identifier')
        when 'var_declaration'
          declaration_signature(:var, 'var_spec', 'identifier')
        else
          raise ArgumentError, "Unsupported top-level Go node #{node.type.inspect}"
        end.freeze
      end

      def grouped?
        case node.type
        when 'import_declaration'
          !find_descendant(node, ['import_spec_list']).nil?
        when 'type_declaration', 'const_declaration'
          node.children.any? { |child| child.type == '(' }
        when 'var_declaration'
          !find_descendant(node, ['var_spec_list']).nil?
        else
          false
        end
      end

      def start_byte
        leading_comments.first&.start_byte || node.start_byte
      end

      def attach_trailing_comment!(comment)
        trailing_comments << comment
      end

      def end_byte = trailing_comments.last&.end_byte || node.end_byte
      def start_line = line_for_byte(start_byte)
      def end_line = line_for_byte(end_byte.zero? ? 0 : end_byte - 1)
      def source_text = source.byteslice(start_byte...end_byte).to_s

      def semantic_tree
        semantic_node(node)
      end

      private

      def import_signature
        specs = descendants(node, 'import_spec')
        values = specs.map do |spec|
          literal = required_descendant(spec, 'interpreted_string_literal', 'raw_string_literal')
          alias_node = spec.children.find do |child|
            %w[package_identifier dot blank_identifier].include?(child.type)
          end
          [alias_node ? text(alias_node) : nil, import_path(literal)]
        end
        return [:import_group, values.sort_by { |value| value.map(&:to_s) }.freeze] if grouped?

        [:import, values.fetch(0)]
      end

      def import_path(literal)
        content = literal.children.find do |child|
          %w[interpreted_string_literal_content raw_string_literal_content].include?(child.type)
        end
        return text(content) if content

        literal_text = text(literal)
        literal_text.byteslice(1...-1).to_s
      end

      def receiver_type_name
        receiver = node.children.find { |child| child.type == 'parameter_list' }
        parameter = required_descendant(receiver, 'parameter_declaration')
        required_descendant_text(parameter, 'type_identifier')
      end

      def declaration_signature(kind, spec_type, identifier_type)
        specs = descendants(node, spec_type)
        member_names = specs.map do |spec|
          spec.children.select { |child| child.type == identifier_type }.map { |child| text(child) }
        end
        raise ArgumentError, "#{node.type} has no declared name" if member_names.flatten.empty?
        return [:"#{kind}_group", member_names.map(&:freeze).freeze] if grouped?

        names = member_names.flatten
        [kind, names.length == 1 ? names.first : names.freeze]
      end

      def required_direct_child_text(parent, type)
        child = parent.children.find { |candidate| candidate.type == type }
        raise ArgumentError, "#{parent.type} has no #{type}" unless child

        text(child)
      end

      def required_descendant_text(parent, *types)
        text(required_descendant(parent, *types))
      end

      def required_descendant(parent, *types)
        found = find_descendant(parent, types)
        raise ArgumentError, "#{parent.type} has no #{types.join(' or ')}" unless found

        found
      end

      def find_descendant(parent, types)
        return parent if types.include?(parent.type)

        parent.children.each do |child|
          found = find_descendant(child, types)
          return found if found
        end
        nil
      end

      def descendants(parent, type, found = [])
        found << parent if parent.type == type
        parent.children.each { |child| descendants(child, type, found) }
        found
      end

      def semantic_node(value)
        children = value.children
        return [value.type, text(value)] if children.empty?

        [value.type, children.select(&:named?).map { |child| semantic_node(child) }]
      end

      def text(value)
        source.byteslice(value.start_byte...value.end_byte).to_s
      end

      def line_for_byte(byte)
        source.byteslice(0...byte).to_s.count("\n") + 1
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength
  end
end
