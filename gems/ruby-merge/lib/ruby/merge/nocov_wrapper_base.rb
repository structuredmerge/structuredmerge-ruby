# frozen_string_literal: true

module Ruby
  module Merge
    # Shared Ruby wrapper for nodes carrying unbalanced or inline nocov markers.
    #
    # The wrapped parser node remains responsible for structural identity; this
    # wrapper only marks it as a Ruby coverage directive participant.
    class NocovWrapperBase
      include Ast::Merge::BlockDirective

      attr_reader :node, :merge_type

      def initialize(node, merge_type = :nocov)
        @node = node
        @merge_type = merge_type
      end

      def kind = :nocov
      def children = []
      def merge_policy = nil

      def start_line
        @node.location&.start_line
      end

      def end_line
        @node.location&.end_line
      end

      def unwrap = @node

      def location = @node.location

      def slice = @node.slice

      def nocov_wrapper? = true
      def nocov_node? = false
      def block_directive? = true

      def inspect
        "#<#{self.class} merge_type=#{@merge_type.inspect} node=#{@node.inspect}>"
      end
    end
  end
end
