# frozen_string_literal: true

module Bash
  module Merge
    # Extracts bounded AST identities for Git-style shell test harness calls.
    class TestHarnessIdentity
      class << self
        def for(wrapper)
          return unless wrapper.command? && wrapper.command_name == 'test_expect_success'

          identity = literal_identity(wrapper)
          [:test_expect_success, *identity] if identity
        end

        private

        def literal_identity(wrapper)
          arguments = command_argument_nodes(wrapper.node)
          return [source_for(wrapper, arguments.first)] if simple_literal_title?(arguments)
          return unless qualified_literal_title?(arguments)

          arguments.first(2).map { |argument| source_for(wrapper, argument) }
        end

        def command_argument_nodes(node)
          children = node.children.select(&:named?)
          command_index = children.index { |child| %w[word command_name].include?(child.type.to_s) }
          return [] unless command_index

          arguments = children.drop(command_index + 1)
          arguments.any? { |child| child.type.to_s.include?('redirect') } ? [] : arguments
        end

        def simple_literal_title?(arguments)
          arguments.length == 2 && literal_title?(arguments.first)
        end

        def qualified_literal_title?(arguments)
          arguments.length == 3 &&
            literal_prerequisite?(arguments[0]) &&
            literal_title?(arguments[1])
        end

        def literal_prerequisite?(argument)
          argument.type.to_s == 'word' && argument.children.none?(&:named?)
        end

        def literal_title?(argument)
          return true if argument.type.to_s == 'raw_string'
          return false unless argument.type.to_s == 'string'

          argument.children.select(&:named?).all? { |child| child.type.to_s == 'string_content' }
        end

        def source_for(wrapper, node)
          start_offset = node.start_byte - wrapper.start_byte
          end_offset = node.end_byte - wrapper.start_byte
          wrapper.source_text.byteslice(start_offset...end_offset).to_s
        end
      end
    end
  end
end
