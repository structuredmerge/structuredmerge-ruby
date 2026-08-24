# frozen_string_literal: true

module Ruby
  module Merge
    # Parser-neutral naming policy for a block-local receiver.
    module BlockBindingSupport
      module_function

      def effective_receiver(receiver, block_var, placeholder: :__block_binding__)
        block_var && receiver == block_var ? placeholder : receiver
      end

      def preferred_block_var(template_var, destination_var)
        template_var if template_var && destination_var && template_var != destination_var
      end

      def merged_block_var(var, preferred_var)
        preferred_var || var
      end
    end
  end
end
