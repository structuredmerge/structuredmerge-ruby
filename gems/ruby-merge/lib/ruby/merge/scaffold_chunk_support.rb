# frozen_string_literal: true

module Ruby
  module Merge
    # Shared chunk anchors used when preserving project-specific Rake sections.
    module ScaffoldChunkSupport
      ChunkSpec = Struct.new(
        :anchor_type,
        :anchor_value,
        :satellite_patterns,
        :jaccard_threshold,
        :max_lookahead,
        :max_lookbehind,
        keyword_init: true
      )

      BUNDLER_GEM_TASKS_SPEC = ChunkSpec.new(
        anchor_type: :require_call,
        anchor_value: 'bundler/gem_tasks',
        satellite_patterns: [],
        jaccard_threshold: 0.35,
        max_lookahead: 0,
        max_lookbehind: 0
      )

      RSPEC_SPEC = ChunkSpec.new(
        anchor_type: :require_call,
        anchor_value: 'rspec/core/rake_task',
        satellite_patterns: ['RSpec::Core::RakeTask.new'],
        jaccard_threshold: 0.35,
        max_lookahead: 5,
        max_lookbehind: 2
      )

      RUBOCOP_SPEC = ChunkSpec.new(
        anchor_type: :require_call,
        anchor_value: 'rubocop/rake_task',
        satellite_patterns: ['RuboCop::RakeTask.new'],
        jaccard_threshold: 0.35,
        max_lookahead: 5,
        max_lookbehind: 2
      )

      DEFAULT_TASK_SPEC = ChunkSpec.new(
        anchor_type: :task_call,
        anchor_value: 'default',
        satellite_patterns: [],
        jaccard_threshold: 0.35,
        max_lookahead: 0,
        max_lookbehind: 0
      )

      ALL_SPECS = [BUNDLER_GEM_TASKS_SPEC, RSPEC_SPEC, RUBOCOP_SPEC, DEFAULT_TASK_SPEC].freeze

      module_function

      def jaccard_tokens(text)
        text.scan(/[A-Za-z0-9_]+/).to_set
      end

      def jaccard(a_set, b_set)
        union = a_set | b_set
        return 0.0 if union.empty?

        (a_set & b_set).size.to_f / union.size
      end

      def task_anchor_match?(source, anchor_value, threshold)
        node_tokens = jaccard_tokens(source.to_s)
        pattern_tokens = jaccard_tokens("task #{anchor_value}")
        jaccard(pattern_tokens, node_tokens) >= threshold
      end
    end
  end
end
