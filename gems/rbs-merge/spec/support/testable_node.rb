# frozen_string_literal: true

module Rbs
  module Merge
    module SpecSupport
      class TestableNode
        attr_reader :type, :text, :start_line, :end_line

        def self.create(type:, text:, start_line:, end_line: nil)
          new(type: type, text: text, start_line: start_line, end_line: end_line)
        end

        def initialize(type:, text:, start_line:, end_line:)
          @type = type.to_s
          @text = text.to_s
          @start_line = start_line
          @end_line = end_line || start_line + @text.count("\n")
        end
      end
    end
  end
end

TestableNode = Rbs::Merge::SpecSupport::TestableNode unless defined?(TestableNode)
