# frozen_string_literal: true

module Ast
  module Merge
    module Layout
      # Passive representation of a contiguous blank-line run.
      #
      # A gap may be adjacent to both a preceding and a following owner. Both
      # owners can reference the same shared gap object, but only one side is the
      # active controller for output at any moment.
      class Gap
        # Supported gap kinds.
        #
        # @return [Array<Symbol>]
        KINDS = %i[preamble interstitial postlude].freeze
        # Supported owner-reference sides.
        #
        # @return [Array<Symbol>]
        SIDES = %i[before after].freeze

        attr_reader :kind, :start_line, :end_line, :lines, :before_owner, :after_owner, :controller_side, :metadata

        def initialize(kind:, start_line:, end_line:, lines:, before_owner: nil, after_owner: nil,
                       controller_side: nil, metadata: {}, **options)
          @kind = normalize_kind(kind)
          @start_line = Integer(start_line)
          @end_line = Integer(end_line)
          @lines = Array(lines).freeze
          @before_owner = before_owner
          @after_owner = after_owner
          @controller_side = normalize_controller_side(controller_side || default_controller_side)
          @metadata = metadata.merge(options).freeze

          validate_range!
          validate_adjacency!
          validate_controller_side!
        end

        def preamble?
          kind == :preamble
        end

        def interstitial?
          kind == :interstitial
        end

        def postlude?
          kind == :postlude
        end

        # Return the number of source lines spanned by the gap.
        #
        # @return [Integer]
        def line_count
          end_line - start_line + 1
        end

        # Return the number of blank lines contained in the gap.
        #
        # @return [Integer]
        def blank_line_count
          lines.count { |line| line.to_s.strip.empty? }
        end

        # Return the owner currently controlling output for this gap.
        #
        # @return [Object, nil]
        def controller
          owner_for(controller_side)
        end

        # Return the opposite controller side, if any.
        #
        # @return [Symbol, nil]
        def fallback_side
          return unless controller_side

          controller_side == :before ? :after : :before
        end

        # Return the owner on the fallback controller side.
        #
        # @return [Object, nil]
        def fallback_controller
          owner_for(fallback_side)
        end

        # Resolve an owner by side.
        #
        # @param side [Symbol, String, nil]
        # @return [Object, nil]
        def owner_for(side)
          case normalize_controller_side(side)
          when :before then before_owner
          when :after then after_owner
          end
        end

        def leading_for?(owner)
          after_owner.equal?(owner)
        end

        def trailing_for?(owner)
          before_owner.equal?(owner)
        end

        def adjacent_side_for(owner)
          return :before if trailing_for?(owner)
          return :after if leading_for?(owner)

          nil
        end

        def role_for(owner)
          case adjacent_side_for(owner)
          when :before then :trailing
          when :after then :leading
          end
        end

        def owned_by?(owner)
          leading_for?(owner) || trailing_for?(owner)
        end

        # Return the owner that should control output after owner removal/retention filtering.
        #
        # @param retained_owners [Array<Object>, nil] explicitly retained owners
        # @param removed_owners [Array<Object>, nil] explicitly removed owners
        # @return [Object, nil]
        def effective_controller(retained_owners: nil, removed_owners: nil)
          effective_side = effective_controller_side(retained_owners: retained_owners, removed_owners: removed_owners)
          effective_side ? owner_for(effective_side) : nil
        end

        # Return the side that should control output after owner filtering.
        #
        # @param retained_owners [Array<Object>, nil] explicitly retained owners
        # @param removed_owners [Array<Object>, nil] explicitly removed owners
        # @return [Symbol, nil]
        def effective_controller_side(retained_owners: nil, removed_owners: nil)
          return controller_side if owner_available?(controller, retained_owners: retained_owners,
                                                                 removed_owners: removed_owners)
          return fallback_side if owner_available?(fallback_controller, retained_owners: retained_owners,
                                                                        removed_owners: removed_owners)

          nil
        end

        def controls_output_for?(owner, retained_owners: nil, removed_owners: nil)
          effective_controller(retained_owners: retained_owners, removed_owners: removed_owners).equal?(owner)
        end

        # Return a concise debug representation of the gap.
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} kind=#{kind} lines=#{start_line}..#{end_line} controller_side=#{controller_side.inspect}>"
        end

        private

        def default_controller_side
          case kind
          when :preamble
            :after
          when :postlude
            :before
          else
            if after_owner
              :after
            else
              (before_owner ? :before : nil)
            end
          end
        end

        def normalize_kind(kind)
          normalized = kind&.to_sym
          return normalized if KINDS.include?(normalized)

          raise ArgumentError,
                "Unknown layout gap kind: #{kind.inspect}. Expected one of: #{KINDS.join(', ')}"
        end

        def normalize_controller_side(side)
          return if side.nil?

          normalized = side.to_sym
          return normalized if SIDES.include?(normalized)

          raise ArgumentError,
                "Unknown controller side: #{side.inspect}. Expected one of: #{SIDES.join(', ')}"
        end

        def validate_range!
          raise ArgumentError, 'end_line must be >= start_line' if end_line < start_line
          return if lines.empty? || lines.size == line_count

          raise ArgumentError,
                "lines length (#{lines.size}) must match line range size (#{line_count})"
        end

        def validate_adjacency!
          case kind
          when :preamble
            raise ArgumentError, 'preamble gaps cannot have a before_owner' if before_owner
            raise ArgumentError, 'preamble gaps require an after_owner' unless after_owner
          when :postlude
            raise ArgumentError, 'postlude gaps require a before_owner' unless before_owner
            raise ArgumentError, 'postlude gaps cannot have an after_owner' if after_owner
          when :interstitial
            unless before_owner || after_owner
              raise ArgumentError,
                    'interstitial gaps require at least one adjacent owner'
            end
          end
        end

        def validate_controller_side!
          return if controller_side.nil? && before_owner.nil? && after_owner.nil?
          return if owner_for(controller_side)

          raise ArgumentError,
                "controller_side #{controller_side.inspect} must reference an adjacent owner"
        end

        def owner_available?(owner, retained_owners:, removed_owners:)
          return false if owner.nil?

          if retained_owners
            Array(retained_owners).any? { |candidate| candidate.equal?(owner) }
          elsif removed_owners
            Array(removed_owners).none? { |candidate| candidate.equal?(owner) }
          else
            true
          end
        end
      end
    end
  end
end
