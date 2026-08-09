# frozen_string_literal: true

module Ast
  module Merge
    module SourceRender
      # Exact whole-line range selected from one source revision.
      class SourceFragment
        attr_reader :revision, :start_line, :end_line, :metadata

        def initialize(revision:, start_line:, end_line:, metadata: {})
          @revision = revision.to_sym
          @start_line = Integer(start_line)
          @end_line = Integer(end_line)
          @metadata = metadata.to_h.freeze

          validate!
        end

        def kind
          :source
        end

        def line_range
          start_line..end_line
        end

        private

        def validate!
          unless REVISION_ROLES.include?(revision)
            raise InvalidPlanError, "Unknown source revision: #{revision.inspect}"
          end
          raise InvalidPlanError, 'start_line must be >= 1' if start_line < 1
          raise InvalidPlanError, 'end_line must be >= start_line' if end_line < start_line
        end
      end

      # Provider- or profile-generated source that does not exist in a revision.
      class SynthesizedFragment
        attr_reader :content, :reason, :producer, :metadata

        def initialize(content:, reason:, producer:, metadata: {})
          @content = content.to_s.freeze
          @reason = normalized_identifier(reason, :reason)
          @producer = normalized_identifier(producer, :producer)
          @metadata = metadata.to_h.freeze
        end

        def kind
          :synthesized
        end

        private

        def normalized_identifier(value, name)
          identifier = value.to_s.strip
          raise InvalidPlanError, "#{name} must not be empty" if identifier.empty?

          identifier.to_sym
        end
      end

      # Localized base/ours/theirs alternatives selected by a provider.
      class ConflictFragment
        DEFAULT_MARKER_SIZE = 7

        attr_reader :conflict_id, :base, :ours, :theirs, :labels, :marker_size, :metadata

        # rubocop:disable Metrics/ParameterLists -- three semantic sides are explicit contract roles
        def initialize(conflict_id:, base:, ours:, theirs:, labels: {}, marker_size: DEFAULT_MARKER_SIZE, metadata: {})
          @conflict_id = conflict_id.to_s.freeze
          @base = normalize_children(base)
          @ours = normalize_children(ours)
          @theirs = normalize_children(theirs)
          @labels = default_labels.merge(symbolize_keys(labels)).freeze
          @marker_size = Integer(marker_size)
          @metadata = metadata.to_h.freeze

          validate!
        end
        # rubocop:enable Metrics/ParameterLists

        def kind
          :conflict
        end

        def children_for(side)
          public_send(side)
        end

        private

        def normalize_children(children)
          Array(children).freeze
        end

        def default_labels
          { base: 'base', ours: 'ours', theirs: 'theirs' }
        end

        def symbolize_keys(hash)
          hash.to_h.transform_keys(&:to_sym)
        end

        def validate!
          raise InvalidPlanError, 'conflict_id must not be empty' if conflict_id.empty?
          raise InvalidPlanError, 'marker_size must be >= 1' if marker_size < 1

          invalid = [*base, *ours, *theirs].reject do |fragment|
            fragment.is_a?(SourceFragment) || fragment.is_a?(SynthesizedFragment)
          end
          return if invalid.empty?

          raise InvalidPlanError, 'Conflict sides may contain only source or synthesized fragments'
        end
      end
    end
  end
end
