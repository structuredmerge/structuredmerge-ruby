# frozen_string_literal: true

module Ast
  module Merge
    module StructuralEdit
      # Passive batch of non-overlapping structural edit plans against one source.
      #
      # `PlanSet` makes the existing line-based structural edit primitives usable
      # as a general-purpose replacement API for downstream callers that need to
      # apply more than one exact source-preserving edit without falling back to
      # ad hoc line-array surgery.
      #
      # Each plan must be splice-compatible, meaning it either is a
      # `SplicePlan` itself or responds to `#to_splice_plan` (for example
      # `RemovePlan`). All plans must reference the same original source and must
      # not overlap.
      class PlanSet
        attr_reader :source, :plans, :metadata

        def initialize(source:, plans:, metadata: {}, **options)
          @source = source.to_s
          @plans = Array(plans).compact.freeze
          @metadata = metadata.merge(options).freeze

          validate_plans!
        end

        # Return all plans normalized to {SplicePlan} instances.
        #
        # @return [Array<SplicePlan>]
        def splice_plans
          @splice_plans ||= plans.map { |plan| normalize_plan(plan) }.freeze
        end

        # Apply all splice plans and return merged source content.
        #
        # @return [String]
        def merged_content
          ordered_splice_plans.reduce(source) do |current_source, splice_plan|
            splice_plan.apply_to(current_source)
          end
        end

        def changed?
          merged_content != source
        end

        # Return all promoted rehome plans emitted by member plans.
        #
        # @return [Array<RehomePlan>]
        def rehome_plans
          plans.filter_map do |plan|
            next unless plan.respond_to?(:rehome_plans)

            Array(plan.rehome_plans)
          end.flatten.freeze
        end

        # Return all promoted comment regions across member plans.
        #
        # @return [Array<Comment::Region>]
        def promoted_comment_regions
          plans.filter_map do |plan|
            next unless plan.respond_to?(:promoted_comment_regions)

            Array(plan.promoted_comment_regions)
          end.flatten.freeze
        end

        # Return all promoted layout gaps across member plans.
        #
        # @return [Array<Layout::Gap>]
        def promoted_layout_gaps
          plans.filter_map do |plan|
            next unless plan.respond_to?(:promoted_layout_gaps)

            Array(plan.promoted_layout_gaps)
          end.flatten.freeze
        end

        # Return a concise debug representation of the plan set.
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} plans=#{plans.size} changed=#{changed?}>"
        end

        private

        def ordered_splice_plans
          @ordered_splice_plans ||= splice_plans
                                    .sort_by do |plan|
            [
              -plan.replace_start_line, -plan.replace_end_line
            ]
          end
                                                            .freeze
        end

        def normalize_plan(plan)
          candidate = plan.respond_to?(:to_splice_plan) ? plan.to_splice_plan : plan
          return candidate if candidate.is_a?(SplicePlan)

          raise ArgumentError, 'All plans must be SplicePlan instances or respond to #to_splice_plan'
        end

        def validate_plans!
          previous_range = nil

          splice_plans.sort_by { |plan| [plan.replace_start_line, plan.replace_end_line] }.each do |splice_plan|
            validate_plan_source!(splice_plan)

            current_range = splice_plan.line_range
            if previous_range && ranges_overlap?(previous_range, current_range)
              raise ArgumentError,
                    "Structural edit plans must not overlap: #{previous_range.begin}..#{previous_range.end} overlaps #{current_range.begin}..#{current_range.end}"
            end

            previous_range = current_range
          end
        end

        def validate_plan_source!(splice_plan)
          return if splice_plan.source == source

          raise ArgumentError, 'All plans in a PlanSet must share the same source'
        end

        def ranges_overlap?(left, right)
          left.begin <= right.end && right.begin <= left.end
        end
      end
    end
  end
end
