# frozen_string_literal: true

module Json
  module Merge
    # Computes base-aware JSON-family semantic decisions without rendering.
    # rubocop:disable Metrics/ClassLength -- recursive decisions and classifications form one algorithm
    class ThreeWayDecision
      State = Data.define(:present, :value) do
        def self.present(value)
          new(present: true, value: value)
        end

        def self.missing
          @missing ||= new(present: false, value: nil)
        end

        def to_h
          present ? { present: true, value: value } : { present: false }
        end
      end

      Result = Data.define(:state, :conflicts, :changes) do
        def present?
          state.present
        end

        def value
          state.value
        end

        def conflicted?
          !conflicts.empty?
        end
      end

      def call(base:, ours:, theirs:)
        merge_states(
          State.present(base),
          State.present(ours),
          State.present(theirs),
          path: ''
        )
      end

      private

      def merge_states(base, ours, theirs, path:)
        return success(ours) if ours == theirs
        return success(theirs, change: classify(path, base, ours, theirs)) if base == ours
        return success(ours, change: classify(path, base, ours, theirs)) if base == theirs
        return merge_added_objects(ours, theirs, path: path) if added_object_states?(base, ours, theirs)
        return merge_objects(base, ours, theirs, path: path) if object_states?(base, ours, theirs)

        conflict(base, ours, theirs, path: path)
      end

      def merge_objects(base, ours, theirs, path:)
        aggregate = { value: {}, conflicts: [], changes: [] }
        states = [base, ours, theirs]
        ordered_keys(base.value, ours.value, theirs.value).each do |key|
          merge_object_key(aggregate, key, states, path: path)
        end

        Result.new(
          state: State.present(aggregate[:value]),
          conflicts: aggregate[:conflicts].freeze,
          changes: aggregate[:changes].freeze
        )
      end

      def merge_added_objects(ours, theirs, path:)
        merge_objects(State.present({}), ours, theirs, path: path)
      end

      def merge_object_key(aggregate, key, states, path:)
        child_states = states.map { |state| state_for(state.value, key) }
        child = merge_states(*child_states, path: child_path(path, key))
        aggregate[:value][key] = child.value if child.present?
        aggregate[:conflicts].concat(child.conflicts)
        aggregate[:changes].concat(child.changes)
      end

      def success(state, change: nil)
        Result.new(
          state: state,
          conflicts: [].freeze,
          changes: change ? [change].freeze : [].freeze
        )
      end

      def conflict(base, ours, theirs, path:)
        classification = classify(path, base, ours, theirs)
        selected = ours.present ? ours : theirs
        Result.new(
          state: selected,
          conflicts: [conflict_payload(base, ours, theirs, path, classification)].freeze,
          changes: [classification].freeze
        )
      end

      def conflict_payload(base, ours, theirs, path, classification)
        {
          conflict_id: conflict_id(path),
          category: conflict_category(ours, theirs),
          path: path,
          base: base.to_h,
          ours: ours.to_h,
          theirs: theirs.to_h,
          change_classification: classification
        }.freeze
      end

      def classify(path, base, ours, theirs)
        {
          path: path,
          ours: change_state(base, ours),
          theirs: change_state(base, theirs)
        }.freeze
      end

      def change_state(base, side)
        return :unchanged if base == side
        return :added unless base.present
        return :deleted unless side.present

        :edited
      end

      def conflict_category(ours, theirs)
        ours.present && theirs.present ? :edit_edit : :delete_edit
      end

      def object_states?(*states)
        states.all? { |state| state.present && state.value.is_a?(Hash) }
      end

      def added_object_states?(base, ours, theirs)
        !base.present &&
          ours.present && ours.value.is_a?(Hash) &&
          theirs.present && theirs.value.is_a?(Hash)
      end

      def state_for(object, key)
        object.key?(key) ? State.present(object.fetch(key)) : State.missing
      end

      def ordered_keys(*objects)
        objects.each_with_object([]) do |object, keys|
          object.each_key { |key| keys << key unless keys.include?(key) }
        end
      end

      def child_path(path, key)
        "#{path}/#{escape_path_segment(key)}"
      end

      def escape_path_segment(key)
        key.to_s.gsub('~', '~0').gsub('/', '~1')
      end

      def conflict_id(path)
        suffix = path.delete_prefix('/').gsub(/[^a-zA-Z0-9_-]+/, '-')
        "json-conflict-#{suffix.empty? ? 'root' : suffix}"
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
