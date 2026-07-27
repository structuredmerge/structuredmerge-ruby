# frozen_string_literal: true

module Yaml
  module Merge
    module DebugLogger
      module_function

      def debug(_message, _details = nil); end

      def time(_label)
        yield
      end
    end
  end
end
