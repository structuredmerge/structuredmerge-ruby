# frozen_string_literal: true

require_relative 'block_binding_support'

module Ruby
  module Merge
    module GemspecSupport
      GEMSPEC_VAR_PLACEHOLDER = :__gemspec_var__

      module_function

      def effective_receiver(receiver, gemspec_block_var)
        BlockBindingSupport.effective_receiver(receiver, gemspec_block_var, placeholder: GEMSPEC_VAR_PLACEHOLDER)
      end

      def preferred_block_var(template_var, dest_var)
        BlockBindingSupport.preferred_block_var(template_var, dest_var)
      end

      def merged_block_var(var, preferred_var)
        BlockBindingSupport.merged_block_var(var, preferred_var)
      end

      def opening_line_with_preferred_block_var(opening_line, dest_var:, preferred_var:, node_preference:)
        return opening_line unless preferred_var && dest_var && dest_var != preferred_var
        return opening_line unless node_preference == :destination

        opening_line.sub("|#{dest_var}|", "|#{preferred_var}|")
      end
    end
  end
end
