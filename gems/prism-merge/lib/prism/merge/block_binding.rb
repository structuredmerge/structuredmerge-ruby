# frozen_string_literal: true

module Prism
  module Merge
    # Finds a simple block parameter on a structurally identified call.
    class BlockBinding
      attr_reader :call, :parameter

      def initialize(call:, parameter:)
        @call = call
        @parameter = parameter
      end

      def name
        parameter.name.to_s
      end

      def scope_range
        call.block.location.start_offset...call.block.location.end_offset
      end

      def self.find(source, &matcher)
        parse_result = TreeHaver.with_backend(Prism::Merge::BACKEND_REFERENCE.id) do
          TreeHaver.parser_for(:ruby, backend_type: :prism).parse(source).parse_result
        end
        return unless parse_result.success?

        call = parse_result.value.breadth_first_search_all { |node| node.is_a?(::Prism::CallNode) }.find(&matcher)
        parameter = call&.block&.parameters&.parameters&.requireds&.first
        new(call: call, parameter: parameter) if parameter
      end
    end
  end
end
