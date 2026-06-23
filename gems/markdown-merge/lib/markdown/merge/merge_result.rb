# frozen_string_literal: true

require 'digest'

module Markdown
  module Merge
    # Represents the result of a Markdown merge operation.
    #
    # Inherits from Ast::Merge::MergeResultBase to provide consistent result
    # handling across all merge gems. Contains the merged content along
    # with metadata about conflicts, frozen sections, and changes made.
    #
    # @example Successful merge
    #   result = SmartMerger.merge(source_a, source_b)
    #   if result.success?
    #     File.write("merged.md", result.content)
    #   end
    #
    # @example Handling conflicts
    #   result = SmartMerger.merge(source_a, source_b)
    #   if result.conflicts?
    #     result.conflicts.each do |conflict|
    #       puts "Conflict at: #{conflict[:location]}"
    #     end
    #   end
    #
    # @example Checking for document problems
    #   result = SmartMerger.merge(source_a, source_b, normalize_whitespace: true)
    #   result.problems.by_category(:excessive_whitespace).each do |problem|
    #     puts "Whitespace issue at line #{problem.details[:line]}"
    #   end
    #
    # @see Ast::Merge::MergeResultBase Base class
    # @see DocumentProblems For problem tracking
    class MergeResult < Ast::Merge::MergeResultBase
      # @return [DocumentProblems] Problems found during merge
      attr_reader :problems

      # Initialize a new MergeResult
      #
      # @param content [String, nil] Merged content (nil if merge failed)
      # @param conflicts [Array<Hash>] Conflict descriptions
      # @param frozen_blocks [Array<Hash>] Preserved frozen block info
      # @param stats [Hash] Merge statistics
      # @param problems [DocumentProblems, nil] Document problems found
      # @param options [Hash] Additional options for forward compatibility
      def initialize(content:, raw_content: nil, conflicts: [], frozen_blocks: [], stats: {}, problems: nil, **options)
        super(
          conflicts: conflicts,
          frozen_blocks: frozen_blocks,
          stats: default_stats.merge(stats),
          **options
        )
        @content_raw = content
        @raw_content = raw_content || content
        @problems = problems || DocumentProblems.new
      end

      # Get the merged content as a string.
      # Overrides base class to return string content directly.
      #
      # @return [String, nil] The merged Markdown content
      def content
        @content_raw
      end

      # Check if content has been set (not nil).
      # Overrides base class for string-based content.
      #
      # @return [Boolean]
      def content?
        !@content_raw.nil?
      end

      # Get content as a string (alias for content in this class).
      #
      # @return [String, nil] The merged content
      def content_string
        @content_raw
      end

      # Check if merge was successful (no unresolved conflicts)
      #
      # @return [Boolean] True if merge succeeded
      def success?
        conflicts.empty? && content?
      end

      # Check if there are unresolved conflicts
      #
      # @return [Boolean] True if conflicts exist
      def conflicts?
        !conflicts.empty?
      end

      # Check if any frozen blocks were preserved
      #
      # @return [Boolean] True if frozen blocks were preserved
      def has_frozen_blocks?
        !frozen_blocks.empty?
      end

      # Get count of nodes added during merge
      #
      # @return [Integer] Number of nodes added
      def nodes_added
        stats[:nodes_added] || 0
      end

      # Get count of nodes removed during merge
      #
      # @return [Integer] Number of nodes removed
      def nodes_removed
        stats[:nodes_removed] || 0
      end

      # Get count of nodes modified during merge
      #
      # @return [Integer] Number of nodes modified
      def nodes_modified
        stats[:nodes_modified] || 0
      end

      # Get merge duration in milliseconds
      #
      # @return [Float, nil] Merge time in milliseconds
      def merge_time_ms
        stats[:merge_time_ms]
      end

      # Get count of frozen blocks preserved
      #
      # @return [Integer] Number of frozen blocks
      def frozen_count
        frozen_blocks.size
      end

      # String representation for debugging
      #
      # @return [String] Debug representation
      def inspect
        status = success? ? 'success' : 'failed'
        "#<#{self.class.name} #{status} conflicts=#{conflicts.size} frozen=#{frozen_blocks.size} " \
          "added=#{nodes_added} removed=#{nodes_removed} modified=#{nodes_modified}>"
      end

      # Convert to string (returns merged content)
      #
      # @return [String] The merged content or empty string
      def to_s
        content || ''
      end

      def to_unresolved_review_state(selections: {}, metadata: {})
        normalized_selections = normalize_unresolved_resolutions(selections)
        Ast::Merge::UnresolvedReviewState.new(
          cases: serializable_unresolved_cases,
          selections: delegated_applied_selections.merge(normalized_selections),
          metadata: review_state_metadata(metadata, normalized_selections)
        )
      end

      def apply_unresolved_resolutions!(resolutions)
        normalized = normalize_unresolved_resolutions(resolutions)
        handled_case_ids = apply_grouped_delegated_resolutions!(normalized)
        remaining = normalized.reject { |case_id, _| handled_case_ids.include?(case_id) }
        apply_output_range_resolutions_descending!(remaining)
        fallback = remaining.reject { |case_id, _| handled_case_ids.include?(case_id) }
        super(fallback)
      end

      protected

      def apply_non_provisional_unresolved_resolution!(resolution_case, selection:, selected_candidate:)
        raw_output_range = resolution_case.metadata[:output_range]
        if raw_output_range && @content_raw != @raw_content
          raise ArgumentError,
                "cannot apply non-provisional resolution for case #{resolution_case.case_id} after post-processing transformed markdown output"
        end

        output_range = normalize_output_range(raw_output_range)
        return super unless output_range

        selected_candidate = resolution_case.metadata.dig(:output_candidate_by_selection,
                                                          selection.to_sym) || selected_candidate
        start_offset, end_offset = output_range
        prefix = @content_raw.byteslice(0, start_offset).to_s
        suffix = @content_raw.byteslice(end_offset..).to_s
        @content_raw = "#{prefix}#{selected_candidate}#{suffix}"
        @raw_content = @content_raw
      end

      private

      SERIALIZATION_OMIT = Object.new.freeze

      def apply_grouped_delegated_resolutions!(normalized_resolutions)
        handled_case_ids = []
        delegated_groups = @unresolved_cases
                           .group_by { |resolution_case| resolution_case.metadata[:delegated_apply_group] }
                           .reject { |group_id, _| group_id.nil? }

        delegated_groups.each_value do |cases|
          selected_cases = cases.select { |resolution_case| normalized_resolutions.key?(resolution_case.case_id) }
          next if selected_cases.empty?

          apply_grouped_delegated_block!(cases, selected_cases, normalized_resolutions)
          handled_case_ids.concat(selected_cases.map(&:case_id))
        end

        handled_case_ids
      end

      def apply_grouped_delegated_block!(cases, selected_cases, normalized_resolutions)
        raw_output_range = cases.map { |resolution_case| resolution_case.metadata[:output_range] }.compact.uniq.fetch(0)
        if @content_raw != @raw_content
          raise ArgumentError,
                "cannot apply non-provisional resolution for delegated block #{cases.first.metadata[:delegated_apply_group]} after post-processing transformed markdown output"
        end

        output_range = normalize_output_range(raw_output_range)
        renderer = cases.map do |resolution_case|
          resolution_case.metadata[:delegated_apply_renderer]
        end.compact.uniq.fetch(0)
        prior_selections = cases.map do |resolution_case|
          resolution_case.metadata[:delegated_applied_selections]
        end.compact.reduce({}) do |memo, selections|
          memo.merge(selections.transform_keys(&:to_s))
        end
        prior_root_selections = cases.map do |resolution_case|
          resolution_case.metadata[:delegated_root_applied_selections]
        end.compact.reduce({}) do |memo, selections|
          memo.merge(selections.transform_keys(&:to_s))
        end
        prior_root_identities = cases.map do |resolution_case|
          resolution_case.metadata[:delegated_root_case_identities]
        end.compact.reduce({}) do |memo, identities|
          memo.merge(identities.transform_keys(&:to_s))
        end
        delegated_selections = selected_cases.each_with_object(prior_selections) do |resolution_case, hash|
          hash[resolution_case.metadata[:delegated_case_id]] = normalized_resolutions.fetch(resolution_case.case_id)
        end
        delegated_root_selections = selected_cases.each_with_object(prior_root_selections) do |resolution_case, hash|
          hash[resolution_case.case_id] = normalized_resolutions.fetch(resolution_case.case_id)
        end
        delegated_root_identities = selected_cases.each_with_object(prior_root_identities) do |resolution_case, hash|
          hash[resolution_case.case_id] = review_identity_for_case(resolution_case)
        end
        delegated_result = renderer.call(delegated_selections)
        updated_output_range = replace_output_range!(output_range, delegated_result.fetch(:content))
        previous_case_ids = cases.map(&:case_id)
        @unresolved_cases.reject! { |resolution_case| previous_case_ids.include?(resolution_case.case_id) }
        @conflicts.reject! { |conflict| previous_case_ids.include?(conflict[:case_id].to_s) }
        remapped_cases = remap_delegated_cases_after_apply(
          delegated_result[:unresolved_cases],
          template_case: cases.first,
          output_range: updated_output_range,
          renderer: renderer,
          applied_selections: delegated_selections,
          root_applied_selections: delegated_root_selections,
          root_case_identities: delegated_root_identities
        )
        remapped_cases.each { |resolution_case| add_unresolved_case(resolution_case) }
        @conflicts.concat(remapped_cases.map { |resolution_case| conflict_for_resolution_case(resolution_case) })
      end

      def apply_output_range_resolutions_descending!(normalized_resolutions)
        selected_cases = @unresolved_cases.select do |resolution_case|
          normalized_resolutions.key?(resolution_case.case_id) && normalize_output_range(resolution_case.metadata[:output_range])
        end
        selected_cases
          .sort_by { |resolution_case| -normalize_output_range(resolution_case.metadata[:output_range]).first }
          .each do |resolution_case|
            selection = normalized_resolutions.fetch(resolution_case.case_id)
            apply_unresolved_resolution!(resolution_case, selection)
            normalized_resolutions.delete(resolution_case.case_id)
            @conflicts.reject! { |conflict| conflict[:case_id].to_s == resolution_case.case_id }
          end
        selected_case_ids = selected_cases.map(&:case_id)
        @unresolved_cases.reject! { |resolution_case| selected_case_ids.include?(resolution_case.case_id) }
      end

      def normalize_output_range(value)
        range = Array(value)
        return unless range.length == 2

        start_offset = range[0].to_i
        end_offset = range[1].to_i
        return unless start_offset >= 0 && end_offset >= start_offset && @raw_content
        return unless end_offset <= @raw_content.bytesize

        [start_offset, end_offset]
      end

      def replace_output_range!(output_range, replacement)
        start_offset, end_offset = output_range
        prefix = @content_raw.byteslice(0, start_offset).to_s
        suffix = @content_raw.byteslice(end_offset..).to_s
        @content_raw = "#{prefix}#{replacement}#{suffix}"
        @raw_content = @content_raw
        [start_offset, start_offset + replacement.to_s.bytesize]
      end

      def remap_delegated_cases_after_apply(unresolved_cases, template_case:, output_range:, renderer:,
                                            applied_selections:, root_applied_selections:, root_case_identities:)
        operation_id = template_case.metadata[:delegated_runtime_operation_id]
        surface_prefix = template_case.metadata[:delegated_runtime_surface_path]
        delegated_group = template_case.metadata[:delegated_apply_group]

        Array(unresolved_cases).map do |resolution_case|
          suffix = delegated_surface_suffix_for(resolution_case.surface_path)
          Ast::Merge::Runtime::ResolutionCase.new(
            case_id: "#{operation_id}-#{resolution_case.case_id}",
            reason: resolution_case.reason,
            candidates: resolution_case.candidates,
            provisional_winner: resolution_case.provisional_winner,
            surface_path: [surface_prefix, suffix].compact.join(' > '),
            operation_id: operation_id,
            metadata: resolution_case.metadata.merge(
              delegated_case_id: resolution_case.case_id,
              output_range: output_range,
              delegated_apply_group: delegated_group,
              delegated_apply_renderer: renderer,
              delegated_applied_selections: applied_selections,
              delegated_root_applied_selections: root_applied_selections,
              delegated_root_case_identities: root_case_identities,
              delegated_runtime_operation_id: operation_id,
              delegated_runtime_surface_path: surface_prefix
            )
          )
        end
      end

      def delegated_surface_suffix_for(surface_path)
        path = surface_path.to_s
        return if path.empty? || path == 'document[0]'

        path.sub(/\Adocument\[0\]\s*>\s*/, '')
      end

      def conflict_for_resolution_case(resolution_case)
        {
          case_id: resolution_case.case_id,
          reason: resolution_case.reason,
          template: resolution_case.candidates[:template],
          destination: resolution_case.candidates[:destination],
          provisional_winner: resolution_case.provisional_winner,
          surface_path: resolution_case.surface_path
        }
      end

      def serializable_unresolved_cases
        @unresolved_cases.map do |resolution_case|
          Ast::Merge::Runtime::ResolutionCase.new(
            case_id: resolution_case.case_id,
            reason: resolution_case.reason,
            candidates: resolution_case.candidates,
            provisional_winner: resolution_case.provisional_winner,
            surface_path: resolution_case.surface_path,
            operation_id: resolution_case.operation_id,
            metadata: sanitize_review_state_metadata(
              resolution_case.metadata.merge(review_identity: review_identity_for_case(resolution_case))
            )
          )
        end
      end

      def delegated_applied_selections
        @unresolved_cases.each_with_object({}) do |resolution_case, selections|
          selections.merge!(resolution_case.metadata[:delegated_root_applied_selections].to_h)
        end
      end

      def review_state_metadata(metadata, normalized_selections)
        metadata_hash = super(metadata, normalized_selections)
        markdown_review_state = metadata_hash.fetch(:markdown_review_state,
                                                    metadata_hash.fetch('markdown_review_state', {})).to_h
        metadata_hash.merge(
          markdown_review_state: markdown_review_state.merge(
            selection_identities: selection_review_identities(normalized_selections)
          )
        )
      end

      def selection_review_identities(normalized_selections)
        delegated_identities = @unresolved_cases.each_with_object({}) do |resolution_case, identities|
          identities.merge!(resolution_case.metadata[:delegated_root_case_identities].to_h)
        end

        normalized_selections.each_with_object(delegated_identities) do |(case_id, _selection), identities|
          current_case = unresolved_case(case_id)
          identities[case_id.to_s] = review_identity_for_case(current_case) if current_case
        end
      end

      def persisted_selection_identities(metadata)
        markdown_review_state = metadata.fetch(:markdown_review_state, metadata.fetch('markdown_review_state', {})).to_h
        markdown_review_state.fetch(:selection_identities, markdown_review_state.fetch('selection_identities', {})).to_h
                             .transform_keys(&:to_s)
      end

      def review_identity_for_case(resolution_case)
        persisted_review_identity = case_metadata_value(resolution_case, :review_identity)
        return persisted_review_identity if persisted_review_identity

        Digest::SHA256.hexdigest(
          [
            resolution_case.surface_path,
            resolution_case.reason,
            resolution_case.provisional_winner,
            case_metadata_value(resolution_case, :match_kind),
            resolution_case.candidates[:template],
            resolution_case.candidates[:destination]
          ].map(&:to_s).join("\u001f")
        )
      end

      def sanitize_review_state_metadata(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), hash|
            sanitized = sanitize_review_state_metadata(entry)
            next if sanitized.equal?(SERIALIZATION_OMIT)

            hash[key] = sanitized
          end
        when Array
          value.filter_map do |entry|
            sanitized = sanitize_review_state_metadata(entry)
            sanitized unless sanitized.equal?(SERIALIZATION_OMIT)
          end
        else
          return SERIALIZATION_OMIT if value.respond_to?(:call)

          value
        end
      end

      def validate_review_state_compatibility!(state)
        super

        persisted_cases = state.cases.each_with_object({}) do |resolution_case, hash|
          hash[resolution_case.case_id] = resolution_case
        end

        state.selections.each_key do |case_id|
          current_case = unresolved_case(case_id)
          persisted_case = persisted_cases[case_id]
          if persisted_case && !case_metadata_value(persisted_case, :review_identity) &&
             (persisted_case.surface_path != current_case.surface_path ||
             case_metadata_value(persisted_case, :match_kind) != case_metadata_value(current_case, :match_kind))
            raise ArgumentError,
                  "cannot apply markdown review state: case #{case_id} no longer matches the current unresolved markdown surface"
          end

          next unless current_case&.metadata&.[](:output_range)
          next if @content_raw == @raw_content

          raise ArgumentError,
                "cannot apply markdown review state for case #{case_id} after post-processing transformed markdown output"
        end
      end

      def case_metadata_value(resolution_case, key)
        return unless resolution_case

        resolution_case.metadata[key] || resolution_case.metadata[key.to_s]
      end

      # Default statistics structure
      #
      # @return [Hash] Default stats hash
      def default_stats
        {
          nodes_added: 0,
          nodes_removed: 0,
          nodes_modified: 0,
          merge_time_ms: 0
        }
      end
    end
  end
end
