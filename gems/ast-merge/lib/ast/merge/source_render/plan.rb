# frozen_string_literal: true

module Ast
  module Merge
    module SourceRender
      # Passive ordered render plan produced by a family provider.
      class Plan
        attr_reader :sources, :fragments, :metadata

        def initialize(sources:, fragments:, metadata: {})
          @sources = normalize_sources(sources)
          @fragments = Array(fragments).freeze
          @metadata = metadata.to_h.freeze

          validate!
        end

        def source_lines(revision)
          sources.fetch(revision.to_sym).lines
        end

        def source_content(fragment)
          source_lines(fragment.revision)[(fragment.start_line - 1)..(fragment.end_line - 1)].join
        end

        private

        def normalize_sources(values)
          values.to_h.each_with_object({}) do |(revision, source), normalized|
            role = revision.to_sym
            raise InvalidPlanError, "Unknown source revision: #{role.inspect}" unless REVISION_ROLES.include?(role)

            normalized[role] = source.to_s.freeze
          end.freeze
        end

        def validate!
          validate_fragment_types!
          validate_source_ranges!
          validate_line_boundaries!
        end

        def validate_fragment_types!
          invalid = fragments.reject do |fragment|
            SourceRender::FRAGMENT_KINDS.include?(fragment.kind) if fragment.respond_to?(:kind)
          end
          raise InvalidPlanError, 'Plan contains an unsupported fragment' unless invalid.empty?
        end

        def validate_source_ranges!
          each_source_fragment do |fragment|
            lines = source_lines(fragment.revision)
            if fragment.end_line > lines.length
              raise InvalidPlanError,
                    "#{fragment.revision} line #{fragment.end_line} exceeds source line count #{lines.length}"
            end
          end
        end

        def each_source_fragment(&block)
          fragments.each do |fragment|
            if fragment.is_a?(SourceFragment)
              block.call(fragment)
            elsif fragment.is_a?(ConflictFragment)
              %i[base ours theirs].each do |side|
                fragment.children_for(side).grep(SourceFragment, &block)
              end
            end
          end
        end

        def validate_line_boundaries!
          validate_top_level_line_boundaries!
          validate_conflict_line_boundaries!
        end

        def validate_top_level_line_boundaries!
          fragments[0...-1].each do |fragment|
            next if fragment.is_a?(ConflictFragment)
            next if fragment_content(fragment).end_with?("\n")

            raise InvalidPlanError, 'Every non-final fragment must end at a line boundary'
          end
        end

        def validate_conflict_line_boundaries!
          fragments.grep(ConflictFragment).each do |conflict|
            %i[base ours theirs].each do |side|
              conflict.children_for(side).each { |fragment| validate_conflict_child_boundary!(fragment) }
            end
          end
        end

        def validate_conflict_child_boundary!(fragment)
          content = fragment_content(fragment)
          return if content.empty? || content.end_with?("\n")

          raise InvalidPlanError, 'Every conflict-side fragment must end at a line boundary'
        end

        def fragment_content(fragment)
          return source_content(fragment) if fragment.is_a?(SourceFragment)
          return fragment.content if fragment.is_a?(SynthesizedFragment)

          ''
        end
      end
    end
  end
end
