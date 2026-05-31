# frozen_string_literal: true

require "digest"

module Ast
  module Merge
    # Base class for tracking merge results in AST merge libraries.
    # Provides shared decision constants and base functionality for
    # file-type-specific implementations.
    #
    # @example Basic usage in a subclass
    #   class MyMergeResult < Ast::Merge::MergeResultBase
    #     def add_node(node, decision:, source:)
    #       # File-type-specific node handling
    #     end
    #   end
    class MergeResultBase
      # Decision constants for tracking merge choices

      # Line was kept from template (no conflict or template preferred).
      # Used when template content is included without modification.
      DECISION_KEPT_TEMPLATE = :kept_template

      # Line was kept from destination (no conflict or destination preferred).
      # Used when destination content is included without modification.
      DECISION_KEPT_DEST = :kept_destination

      # Line was merged from both sources.
      # Used when content was combined from template and destination.
      DECISION_MERGED = :merged

      # Line was added from template (template-only content).
      # Used for content that exists only in template and is added to result.
      DECISION_ADDED = :added

      # Line from destination freeze block (always preserved).
      # Used for content within freeze markers that must be kept
      # from destination regardless of template content.
      DECISION_FREEZE_BLOCK = :freeze_block

      # Line replaced matching content (signature match with preference applied).
      # Used when template and destination have nodes with same signature but
      # different content, and one version replaced the other based on preference.
      DECISION_REPLACED = :replaced

      # Line was appended from destination (destination-only content).
      # Used for content that exists only in destination and is added to result.
      DECISION_APPENDED = :appended

      # Line was emitted with a provisional winner while review remains required.
      DECISION_UNRESOLVED = :unresolved

      # @return [Array<String>] Lines in the result (canonical storage for line-by-line merging)
      attr_reader :lines

      # @return [Array<Hash>] Decisions made during merge
      attr_reader :decisions

      # @return [Object, nil] Analysis of the template file
      attr_reader :template_analysis

      # @return [Object, nil] Analysis of the destination file
      attr_reader :dest_analysis

      # @return [Array<Hash>] Conflicts detected during merge
      attr_reader :conflicts

      # @return [Array] Frozen blocks preserved during merge
      attr_reader :frozen_blocks

      # @return [Hash] Statistics about the merge
      attr_reader :stats

      # @return [Array<Ast::Merge::Runtime::ResolutionCase, Hash>] Reviewable unresolved cases
      attr_reader :unresolved_cases

      # Initialize a new merge result.
      #
      # This unified constructor accepts all parameters that any *-merge gem might need.
      # Subclasses should call super with the parameters they use.
      #
      # @param template_analysis [Object, nil] Analysis of the template file
      # @param dest_analysis [Object, nil] Analysis of the destination file
      # @param conflicts [Array<Hash>] Conflicts detected during merge
      # @param frozen_blocks [Array] Frozen blocks preserved during merge
      # @param stats [Hash] Statistics about the merge
      # @param options [Hash] Additional options for forward compatibility
      def initialize(
        template_analysis: nil,
        dest_analysis: nil,
        conflicts: [],
        frozen_blocks: [],
        stats: {},
        unresolved_cases: [],
        **options
      )
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
        @lines = []
        @decisions = []
        @conflicts = conflicts
        @frozen_blocks = frozen_blocks
        @stats = stats
        @unresolved_cases = unresolved_cases
        # **options captured for forward compatibility - subclasses may use additional options
      end

      # Get content - returns @lines array for most gems.
      # Subclasses may override for different content models (e.g., string).
      #
      # @return [Array<String>] The merged content as array of lines
      def content
        @lines
      end

      # Set content from a string (splits on newlines).
      # Used when region substitution replaces the merged content.
      #
      # @param value [String] The new content
      def content=(value)
        @lines = value.to_s.split("\n", -1)
      end

      # Get content as a string.
      # This is the canonical method for converting the merge result to a string.
      # Ensures a trailing newline for non-empty content, matching standard file
      # conventions and the pattern used by EmitterBase#to_s, Psych::Merge::MergeResult#to_yaml,
      # and Bash::Merge::MergeResult#to_bash.
      #
      # @return [String] Content as string joined with newlines
      def to_s
        content = @lines.join("\n")
        content += "\n" unless content.empty? || content.end_with?("\n")
        content
      end

      # Check if content has been built (has any lines).
      #
      # @return [Boolean]
      def content?
        !@lines.empty?
      end

      # Check if the result is empty
      # @return [Boolean]
      def empty?
        @lines.empty?
      end

      # Get the number of lines
      # @return [Integer]
      def line_count
        @lines.length
      end

      # Remove blank lines from the end of the current result.
      #
      # Layout-aware merge adapters use this when they later discover that a
      # removed owner controlled a leading blank-line gap already emitted as
      # part of the preceding output.
      #
      # @param max [Integer, nil] Maximum number of blank lines to remove
      # @return [Integer] Number of lines removed
      def remove_trailing_blank_lines(max: nil)
        removed = 0

        while @lines.any? && @lines.last.to_s.strip.empty?
          break if max && removed >= max

          @lines.pop
          @line_metadata.pop if instance_variable_defined?(:@line_metadata) && @line_metadata.respond_to?(:pop)
          removed += 1
        end

        removed
      end

      # Normalize repeated blank-line runs in the current result.
      #
      # This is a safety repair for line-oriented semantic merges after
      # ownership-aware layout handling has run. It prevents removed/skipped
      # owners from leaving impossible interstitial blank runs in generated
      # output.
      #
      # @param max [Integer] Maximum number of consecutive blank lines to retain
      # @return [Integer] Number of blank lines removed
      def normalize_blank_line_runs!(max: 1)
        max = Integer(max)
        raise ArgumentError, "max must be >= 0" if max.negative?

        normalized_lines = []
        normalized_metadata = [] if instance_variable_defined?(:@line_metadata) && @line_metadata.respond_to?(:each)
        blank_count = 0
        removed = 0

        @lines.each_with_index do |line, index|
          if line.to_s.strip.empty?
            blank_count += 1
            if blank_count > max
              removed += 1
              next
            end
          else
            blank_count = 0
          end

          normalized_lines << line
          normalized_metadata << @line_metadata[index] if normalized_metadata
        end

        @lines = normalized_lines
        @line_metadata = normalized_metadata if normalized_metadata
        removed
      end

      def unresolved?
        @unresolved_cases.any?
      end

      alias_method :review_required?, :unresolved?

      def add_unresolved_case(resolution_case)
        @unresolved_cases << resolution_case
        resolution_case
      end

      def record_unresolved_choice(
        template_text:,
        destination_text:,
        provisional_winner:,
        case_id:,
        surface_path: nil,
        reason: :conflict,
        metadata: {},
        conflict_fields: {}
      )
        return if template_text == destination_text

        conflict = {
          case_id: case_id,
          reason: reason,
          template: template_text,
          destination: destination_text,
          provisional_winner: provisional_winner,
        }.merge(compact_hash(conflict_fields))
        @conflicts << conflict

        resolution_case = Ast::Merge::Runtime::ResolutionCase.new(
          case_id: case_id,
          reason: reason,
          candidates: {
            template: template_text,
            destination: destination_text,
          },
          provisional_winner: provisional_winner,
          surface_path: surface_path,
          metadata: compact_hash(metadata),
        )
        add_unresolved_case(resolution_case)
      end

      def unresolved_case(case_id)
        @unresolved_cases.find { |resolution_case| resolution_case.case_id == case_id.to_s }
      end

      def apply_unresolved_resolutions!(resolutions)
        normalized = normalize_unresolved_resolutions(resolutions)
        remaining_cases = []

        @unresolved_cases.each do |resolution_case|
          selection = normalized[resolution_case.case_id]
          if selection.nil?
            remaining_cases << resolution_case
            next
          end

          apply_unresolved_resolution!(resolution_case, selection)
          @conflicts.reject! { |conflict| conflict[:case_id].to_s == resolution_case.case_id }
        end

        @unresolved_cases = remaining_cases
        self
      end

      def to_unresolved_review_state(selections: {}, metadata: {})
        normalized_selections = normalize_unresolved_resolutions(selections)
        Ast::Merge::UnresolvedReviewState.new(
          cases: unresolved_cases,
          selections: normalized_selections,
          metadata: review_state_metadata(metadata, normalized_selections),
        )
      end

      def apply_unresolved_review_state!(review_state)
        state = Ast::Merge::UnresolvedReviewState.coerce(review_state)
        validate_review_state_compatibility!(state)
        apply_unresolved_resolutions!(state.selections)
      end

      # Get summary of decisions made
      # @return [Hash<Symbol, Integer>]
      def decision_summary
        summary = Hash.new(0)
        @decisions.each { |d| summary[d[:decision]] += 1 }
        summary
      end

      # String representation
      # @return [String]
      def inspect
        "#<#{self.class.name} lines=#{line_count} decisions=#{@decisions.length}>"
      end

      protected

      # Track a decision
      # @param decision [Symbol] The decision made
      # @param source [Symbol] The source (:template, :destination, :merged)
      # @param line [Integer, nil] The line number
      def track_decision(decision, source, line: nil)
        @decisions << {
          decision: decision,
          source: source,
          line: line,
          timestamp: Time.now,
        }
      end

      def compact_hash(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key] = value unless value.nil?
        end
      end

      def normalize_unresolved_resolutions(resolutions)
        resolutions.to_h.each_with_object({}) do |(case_id, selection), hash|
          hash[case_id.to_s] = selection&.to_sym
        end
      end

      def validate_review_state_compatibility!(state)
        validate_review_state_replay_context!(state)

        persisted_cases = state.cases.each_with_object({}) do |resolution_case, hash|
          hash[resolution_case.case_id] = resolution_case
        end
        selection_identities = persisted_selection_identities(state.metadata)

        state.selections.each_key do |case_id|
          current_case = unresolved_case(case_id)
          raise ArgumentError, "cannot apply review state: case #{case_id} is not present in the current unresolved result" unless current_case

          validate_review_state_selection_identity!(case_id, current_case, selection_identities[case_id])

          persisted_case = persisted_cases[case_id]
          next unless persisted_case

          validate_review_state_case_identity!(case_id, current_case, persisted_case)
        end
      end

      def validate_review_state_selection_identity!(case_id, current_case, expected_identity)
        return unless expected_identity

        current_identity = review_identity_for_case(current_case)
        return if current_identity.nil? || expected_identity == current_identity

        raise ArgumentError,
          "cannot apply review state: case #{case_id} no longer matches the current unresolved surface"
      end

      def validate_review_state_case_identity!(case_id, current_case, persisted_case)
        persisted_identity = review_identity_for_case(persisted_case)
        return unless persisted_identity

        current_identity = review_identity_for_case(current_case)
        return if current_identity.nil? || persisted_identity == current_identity

        raise ArgumentError,
          "cannot apply review state: case #{case_id} no longer matches the current unresolved surface"
      end

      def persisted_selection_identities(metadata)
        review_state = metadata.fetch(:review_state, metadata.fetch("review_state", {})).to_h
        review_state.fetch(:selection_identities, review_state.fetch("selection_identities", {})).to_h
          .transform_keys(&:to_s)
      end

      def persisted_review_state_replay_context(metadata)
        review_state = metadata.fetch(:review_state, metadata.fetch("review_state", {})).to_h
        review_state.fetch(:replay_context, review_state.fetch("replay_context", {})).to_h
      end

      def review_identity_for_case(resolution_case)
        return unless resolution_case

        resolution_case.metadata[:review_identity] || resolution_case.metadata["review_identity"]
      end

      def review_state_metadata(metadata, normalized_selections)
        metadata_hash = metadata.to_h
        selection_identities = selection_review_identities(normalized_selections)
        review_state = metadata_hash.fetch(:review_state, metadata_hash.fetch("review_state", {})).to_h
        replay_context = review_state_replay_context
        return metadata_hash if selection_identities.empty? && replay_context.empty?

        merged_review_state = review_state.dup
        merged_review_state[:selection_identities] = selection_identities unless selection_identities.empty?
        merged_review_state[:replay_context] = review_state.fetch(:replay_context, review_state.fetch("replay_context", {})).to_h
          .merge(replay_context) unless replay_context.empty?

        metadata_hash.merge(
          review_state: merged_review_state,
        )
      end

      def selection_review_identities(normalized_selections)
        normalized_selections.each_with_object({}) do |(case_id, _selection), identities|
          current_case = unresolved_case(case_id)
          identity = review_identity_for_case(current_case)
          identities[case_id.to_s] = identity if identity
        end
      end

      def review_state_replay_context
        compact_hash(
          merge_result_class: self.class.name,
          template_input_fingerprint: analysis_input_fingerprint(@template_analysis),
          destination_input_fingerprint: analysis_input_fingerprint(@dest_analysis),
        )
      end

      def validate_review_state_replay_context!(state)
        persisted_context = persisted_review_state_replay_context(state.metadata)
        return if persisted_context.empty?

        current_context = review_state_replay_context

        compare_review_state_replay_context!(
          persisted_context: persisted_context,
          current_context: current_context,
          key: :merge_result_class,
          mismatch_message: "cannot apply review state exported from #{persisted_context[:merge_result_class] || persisted_context["merge_result_class"]} to #{self.class.name}",
        )
        compare_review_state_replay_context!(
          persisted_context: persisted_context,
          current_context: current_context,
          key: :template_input_fingerprint,
          mismatch_message: "cannot apply review state: template input fingerprint no longer matches",
        )
        compare_review_state_replay_context!(
          persisted_context: persisted_context,
          current_context: current_context,
          key: :destination_input_fingerprint,
          mismatch_message: "cannot apply review state: destination input fingerprint no longer matches",
        )
      end

      def compare_review_state_replay_context!(persisted_context:, current_context:, key:, mismatch_message:)
        expected = persisted_context[key] || persisted_context[key.to_s]
        return unless expected

        actual = current_context[key] || current_context[key.to_s]
        return if actual.nil? || actual == expected

        raise ArgumentError, mismatch_message
      end

      def analysis_input_fingerprint(analysis)
        source = analysis_source(analysis)
        return if source.nil?

        Digest::SHA256.hexdigest(source)
      end

      def analysis_source(analysis)
        return if analysis.nil?
        return analysis.source.to_s if analysis.respond_to?(:source)
        return analysis.instance_variable_get(:@source).to_s if analysis.instance_variable_defined?(:@source)
        return analysis.lines.join("\n") if analysis.respond_to?(:lines)

        nil
      end

      def apply_unresolved_resolution!(resolution_case, selection)
        selected_candidate = resolution_case.candidate_for(selection)
        return if selection.to_sym == resolution_case.provisional_winner

        apply_non_provisional_unresolved_resolution!(
          resolution_case,
          selection: selection.to_sym,
          selected_candidate: selected_candidate,
        )
      end

      def apply_non_provisional_unresolved_resolution!(resolution_case, selection:, selected_candidate:)
        line = resolution_case.metadata[:line]
        unless line && line >= 1 && line <= @lines.length
          raise ArgumentError,
            "cannot apply non-provisional resolution for case #{resolution_case.case_id} without line metadata"
        end

        @lines[line - 1] = selected_candidate
        apply_resolution_decision!(line: line, selection: selection)
      end

      def apply_resolution_decision!(line:, selection:)
        unresolved_decision = @decisions.reverse.find do |decision|
          decision[:decision] == DECISION_UNRESOLVED && decision[:line] == line
        end
        return unless unresolved_decision

        unresolved_decision[:decision] =
          case selection
          when :template then DECISION_KEPT_TEMPLATE
          when :destination then DECISION_KEPT_DEST
          else unresolved_decision[:decision]
          end
      end
    end
  end
end
