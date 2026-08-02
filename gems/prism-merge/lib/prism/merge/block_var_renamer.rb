# frozen_string_literal: true

module Prism
  module Merge
    # AST-directed renaming of a block parameter and its receiver references.
    class BlockVarRenamer
      class << self
        def normalize(source, binding:, canonical_name:)
          return source unless binding

          rename(
            source,
            old_var: binding.name,
            new_var: canonical_name,
            parameter_offset: binding.parameter.location.start_offset,
            scope_range: binding.scope_range
          )
        end

        def rename(source, old_var:, new_var:, parameter_offset: nil, scope_range: nil)
          return source if old_var == new_var || source.empty?

          parse_result = TreeHaver.with_backend(Prism::Merge::BACKEND_REFERENCE.id) do
            TreeHaver.parser_for(:ruby, backend_type: :prism).parse(source).parse_result
          end
          return source unless parse_result.success?

          offsets = ReceiverCollector.collect(parse_result.value, old_var, scope_range: scope_range)
          offsets << parameter_offset if parameter_offset
          apply_replacements(source, offsets.uniq.sort, old_var, new_var)
        end

        private

        def apply_replacements(source, offsets, old_var, new_var)
          offsets.reverse_each.reduce(source.dup) do |updated, offset|
            "#{updated.byteslice(0, offset)}#{new_var}#{updated.byteslice(offset + old_var.bytesize, updated.bytesize)}"
          end
        end
      end

      class ReceiverCollector < ::Prism::Visitor
        def self.collect(program_node, target_var, scope_range: nil)
          offsets = Set.new
          visitor = new(target_var, offsets, scope_range: scope_range)
          visitor.visit(program_node)
          offsets
        end

        def initialize(target_var, offsets, scope_range: nil)
          super()
          @target_var = target_var
          @offsets = offsets
          @scope_range = scope_range
        end

        def visit_call_node(node)
          record_root_receiver(node.receiver) if node.receiver
          super
        end

        def visit_call_operator_write_node(node)
          record_root_receiver(node.receiver) if node.receiver
          super
        end

        def visit_call_and_write_node(node)
          record_root_receiver(node.receiver) if node.receiver
          super
        end

        def visit_call_or_write_node(node)
          record_root_receiver(node.receiver) if node.receiver
          super
        end

        def visit_block_node(node)
          return if shadowing_target_parameter?(node)

          super
        end

        private

        def record_root_receiver(receiver)
          root = receiver
          root = root.receiver while root.type == :call_node && root.receiver
          return unless root.slice == @target_var
          return if @scope_range && !@scope_range.cover?(root.location.start_offset)

          @offsets << root.location.start_offset
        end

        # A nested block may legitimately reuse the same local name. Those calls
        # belong to the nested binding, not the selected outer binding.
        def shadowing_target_parameter?(node)
          return false unless @scope_range
          return false unless @scope_range.cover?(node.location.start_offset)
          return false if node.location.start_offset == @scope_range.begin

          required = node.parameters&.parameters&.requireds&.first
          required&.name&.to_s == @target_var
        end
      end
    end
  end
end
