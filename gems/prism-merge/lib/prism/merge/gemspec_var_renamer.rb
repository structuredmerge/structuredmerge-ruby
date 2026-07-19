# frozen_string_literal: true

module Prism
  module Merge
    # AST-directed renaming of the gemspec block variable in Ruby source text.
    #
    # When a legacy gemspec uses +Gem::Specification.new do |gem|+ but the template
    # uses +do |spec|+, signature normalisation (via +GEMSPEC_VAR_PLACEHOLDER+) lets
    # the merge engine match corresponding attributes.  However, *destination-only*
    # nodes that survive the inner merge still carry the original receiver name in
    # their source text (e.g. +gem.add_dependency+), producing a broken gemspec that
    # mixes +spec.foo+ and +gem.bar+.
    #
    # This utility rewrites those receivers using only AST-derived byte offsets —
    # no regular expressions, no string scanning.
    #
    # @example
    #   source = <<~RUBY
    #     gem.name = "mylib"
    #     gem.metadata["key"] = "value"
    #     gem.add_dependency("foo", "~> 1.0")
    #   RUBY
    #
    #   Prism::Merge::GemspecVarRenamer.rename(source, old_var: "gem", new_var: "spec")
    #   # =>  "spec.name = \"mylib\"\n..."
    #
    class GemspecVarRenamer
      class << self
        # Rename all occurrences of +old_var+ used as a method-call receiver to
        # +new_var+ in the given Ruby source text.
        #
        # The method parses +source+ with Prism, walks every +CallNode+ to find
        # root receivers whose slice equals +old_var+, records their unique byte
        # offsets, and applies positional replacements in reverse order so earlier
        # offsets remain valid.
        #
        # @param source  [String] Ruby source text (typically the body of a gemspec block)
        # @param old_var [String] The receiver name to replace (e.g. +"gem"+)
        # @param new_var [String] The replacement receiver name (e.g. +"spec"+)
        # @return [String] Rewritten source text with receivers renamed
        def rename(source, old_var:, new_var:)
          return source if old_var == new_var
          return source if source.empty?

          parse_result = TreeHaver.with_backend(Prism::Merge::BACKEND_REFERENCE.id) do
            TreeHaver.parser_for(:ruby, backend_type: :prism).parse(source).parse_result
          end
          offsets = collect_receiver_offsets(parse_result.value, old_var)
          return source if offsets.empty?

          apply_replacements(source, offsets, old_var, new_var)
        end

        # Collect unique byte offsets of root receivers matching +old_var+.
        #
        # For chained calls like +gem.metadata["key"]+, the AST contains nested
        # CallNodes.  We walk to the innermost (root) receiver so that each
        # physical occurrence of the variable name is recorded exactly once.
        #
        # @param program_node [Prism::ProgramNode] The parsed AST root
        # @param old_var      [String] The variable name to look for
        # @return [Array<Integer>] Sorted, deduplicated byte offsets (ascending)
        def collect_receiver_offsets(program_node, old_var)
          offsets = Set.new
          visitor = ReceiverCollector.new(old_var, offsets)
          visitor.visit(program_node)
          offsets.to_a.sort
        end

        # Apply byte-offset replacements in reverse order so that earlier offsets
        # are not invalidated by length changes from prior replacements.
        #
        # @param source  [String]         Original source text
        # @param offsets [Array<Integer>]  Byte offsets (ascending) of receivers to replace
        # @param old_var [String]          Original variable name
        # @param new_var [String]          Replacement variable name
        # @return [String] Transformed source text
        def apply_replacements(source, offsets, old_var, new_var)
          result = source.dup
          old_len = old_var.bytesize
          offsets.reverse_each do |offset|
            result.byteslice(offset, old_len)
            result = "#{result.byteslice(0,
                                         offset)}#{new_var}#{result.byteslice(offset + old_len,
                                                                              result.bytesize - offset - old_len)}"
          end
          result
        end

        private :collect_receiver_offsets, :apply_replacements
      end

      # @api private
      # Prism::Visitor subclass that walks CallNodes to find root receivers
      # matching a target variable name.  Also handles compound write nodes
      # (+CallOperatorWriteNode+, +CallAndWriteNode+, +CallOrWriteNode+) whose
      # receiver is the gemspec variable (e.g. +gem.files +=+).
      class ReceiverCollector < ::Prism::Visitor
        # @param target_var [String] The variable name to match against receiver slices
        # @param offsets    [Set<Integer>] Accumulator for unique byte offsets
        def initialize(target_var, offsets)
          super()
          @target_var = target_var
          @offsets = offsets
        end

        # Visit a CallNode — if it has a receiver, walk to the root (innermost)
        # receiver and record its offset when its slice matches the target.
        #
        # @param node [Prism::CallNode]
        def visit_call_node(node)
          record_root_receiver(node.receiver) if node.receiver
          super(node)
        end

        # Visit a CallOperatorWriteNode (e.g. +gem.files +=+).
        #
        # @param node [Prism::CallOperatorWriteNode]
        def visit_call_operator_write_node(node)
          record_root_receiver(node.receiver) if node.receiver
          super(node)
        end

        # Visit a CallAndWriteNode (e.g. +gem.files &&=+).
        #
        # @param node [Prism::CallAndWriteNode]
        def visit_call_and_write_node(node)
          record_root_receiver(node.receiver) if node.receiver
          super(node)
        end

        # Visit a CallOrWriteNode (e.g. +gem.files ||=+).
        #
        # @param node [Prism::CallOrWriteNode]
        def visit_call_or_write_node(node)
          record_root_receiver(node.receiver) if node.receiver
          super(node)
        end

        private

        # Walk a receiver chain to its root and record the offset if it matches.
        #
        # @param receiver [Prism::Node] The receiver node to walk
        def record_root_receiver(receiver)
          root = receiver
          root = root.receiver while root.type.to_s == 'call_node' && root.receiver
          @offsets << root.location.start_offset if root.slice == @target_var
        end
      end
    end
  end
end
