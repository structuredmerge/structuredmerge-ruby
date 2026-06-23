# frozen_string_literal: true

module Prism
  module Merge
    # Surgically removes bundle-gem scaffold boilerplate from Rakefiles.
    #
    # Each ChunkSpec describes an anchor (exact require/task call) and optional
    # satellite nodes (matched fuzzily via Jaccard similarity). The remover
    # finds all matching nodes in the top-level statements and removes them
    # by line range, leaving user-added content intact.
    #
    # @example
    #   specs = [ScaffoldChunkRemover::RSPEC_SPEC, ScaffoldChunkRemover::RUBOCOP_SPEC]
    #   clean = ScaffoldChunkRemover.remove(source, specs)
    class ScaffoldChunkRemover
      ChunkSpec = Struct.new(
        :anchor_type,        # :require_call or :task_call
        :anchor_value,       # String — exact require path OR task name pattern
        :satellite_patterns, # Array<String> — token patterns for satellite nodes
        :jaccard_threshold,  # Float — min Jaccard score for satellite matching
        :max_lookahead,      # Integer — nodes to scan after anchor
        :max_lookbehind,     # Integer — nodes to scan before anchor
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

      class << self
        def remove(source, specs = ALL_SPECS)
          new(source, specs).call
        end
      end

      def initialize(source, specs = ALL_SPECS)
        @source = source
        @specs = specs
      end

      def call
        return @source if @source.empty?

        parse_result = TreeHaver.parser_for(:ruby).parse(@source).parse_result
        statements = parse_result.value.statements&.body&.compact || []
        return @source if statements.empty?

        lines_to_remove = Set.new

        @specs.each do |spec|
          anchor_idx = find_anchor(statements, spec)
          next unless anchor_idx

          nodes_to_remove = [statements[anchor_idx]]

          if spec.satellite_patterns.any?
            start_idx = [0, anchor_idx - spec.max_lookbehind].max
            end_idx = [statements.size - 1, anchor_idx + spec.max_lookahead].min

            spec.satellite_patterns.each do |pattern|
              p_tokens = jaccard_tokens(pattern)
              (start_idx..end_idx).each do |i|
                next if i == anchor_idx

                candidate = statements[i]
                c_tokens = jaccard_tokens(candidate.slice.to_s)
                score = jaccard(p_tokens, c_tokens)
                nodes_to_remove << candidate if score >= spec.jaccard_threshold
              end
            end
          end

          nodes_to_remove.each do |node|
            (node.location.start_line..node.location.end_line).each { |ln| lines_to_remove << ln }
          end
        end

        return @source if lines_to_remove.empty?

        lines = @source.lines

        # Remove up to 1 trailing blank line per contiguous removed block
        trailing = Set.new
        lines_to_remove.to_a.sort.each do |ln|
          next if lines_to_remove.include?(ln + 1)

          next_line = lines[ln] # 0-indexed: lines[ln] is line number ln+1
          trailing << (ln + 1) if next_line && next_line.strip.empty?
        end
        lines_to_remove.merge(trailing)

        lines.reject.with_index { |_, i| lines_to_remove.include?(i + 1) }.join
      end

      private

      def find_anchor(statements, spec)
        statements.each_with_index do |node, idx|
          next unless NodeTypeNormalizer.canonical_type(node.type.to_s, :prism) == :call

          matched = case spec.anchor_type
                    when :require_call then require_anchor_match?(node, spec.anchor_value)
                    when :task_call then task_anchor_match?(node, spec.anchor_value, spec.jaccard_threshold)
                    else false
                    end

          return idx if matched
        end
        nil
      end

      def require_anchor_match?(node, anchor_value)
        return false unless node.name.to_s == 'require'

        first_arg = node.arguments&.arguments&.first
        return false unless first_arg
        return false unless NodeTypeNormalizer.canonical_type(first_arg.type.to_s, :prism) == :string

        first_arg.unescaped == anchor_value
      end

      def task_anchor_match?(node, anchor_value, threshold)
        return false unless node.name.to_s == 'task'

        node_tokens = jaccard_tokens(node.slice.to_s)
        pattern_tokens = jaccard_tokens("task #{anchor_value}")
        jaccard(pattern_tokens, node_tokens) >= threshold
      end

      def jaccard_tokens(text)
        text.scan(/[A-Za-z0-9_]+/).to_set
      end

      def jaccard(a_set, b_set)
        return 0.0 if (a_set | b_set).empty?

        (a_set & b_set).size.to_f / (a_set | b_set).size
      end
    end
  end
end
