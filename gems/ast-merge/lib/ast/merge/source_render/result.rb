# frozen_string_literal: true

module Ast
  module Merge
    module SourceRender
      # Immutable output and provenance from a render plan.
      class Result
        attr_reader :content, :line_records, :synthesized_fragments, :conflicts, :verification_input

        def initialize(content:, line_records:, synthesized_fragments:, conflicts:, verification_input:)
          @content = content.freeze
          @line_records = line_records.freeze
          @synthesized_fragments = synthesized_fragments.freeze
          @conflicts = conflicts.freeze
          @verification_input = verification_input.freeze
          freeze
        end

        def conflicted?
          !conflicts.empty?
        end

        def to_h
          {
            content: content,
            line_records: line_records,
            synthesized_fragments: synthesized_fragments,
            conflicts: conflicts,
            verification_input: verification_input
          }
        end
      end
    end
  end
end
