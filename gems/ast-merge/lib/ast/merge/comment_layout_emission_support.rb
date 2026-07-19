# frozen_string_literal: true

module Ast
  module Merge
    # Shared helpers for merge emitters that reconstruct source regions around
    # structural owners while preserving comment and blank-line ownership.
    #
    # Format-specific gems still decide which comments are syntax comments and
    # which owners participate in a merge.  This module centralizes the
    # language-neutral mechanics for querying attachments and calculating the
    # source span that should be emitted for an owner.
    module CommentLayoutEmissionSupport
      include LineRangeSupport

      private

      def leading_region_for(owner, analysis, owners: nil)
        return unless owner && analysis&.respond_to?(:comment_attachment_for)

        attachment = if owners.nil?
                       analysis.comment_attachment_for(owner)
                     else
                       analysis.comment_attachment_for(owner, owners: owners)
                     end
        attachment.leading_region if attachment.respond_to?(:leading_region)
      end

      def trailing_region_for(owner, analysis, owners: nil)
        return unless owner && analysis&.respond_to?(:comment_attachment_for)

        attachment = if owners.nil?
                       analysis.comment_attachment_for(owner)
                     else
                       analysis.comment_attachment_for(owner, owners: owners)
                     end
        attachment.trailing_region if attachment.respond_to?(:trailing_region)
      end

      def region_present?(region)
        return false unless region
        return !region.empty? if region.respond_to?(:empty?)
        return region.nodes.any? if region.respond_to?(:nodes)

        true
      end

      def region_start_line(region)
        return region.start_line if region.respond_to?(:start_line) && region.start_line
        return unless region.respond_to?(:nodes)

        region.nodes.filter_map { |node| node.respond_to?(:line_number) ? node.line_number : nil }.min
      end

      def region_end_line(region)
        return region.end_line if region.respond_to?(:end_line) && region.end_line
        return unless region.respond_to?(:nodes)

        region.nodes.filter_map { |node| node.respond_to?(:line_number) ? node.line_number : nil }.max
      end

      def preceding_blank_line_start(region_start, analysis)
        line_num = region_start
        while line_num && line_num > 1
          previous_line = source_line_at(analysis, line_num - 1)
          break unless previous_line && previous_line.strip.empty?

          line_num -= 1
        end

        line_num
      end

      def blank_line_count_before(line_num, analysis)
        count = 0
        current = line_num.to_i - 1

        while current >= 1
          previous_line = source_line_at(analysis, current)
          break unless previous_line && previous_line.strip.empty?

          count += 1
          current -= 1
        end

        count
      end

      def leading_segment_start_for_output(output_owner:, output_analysis:, source_region_start:, source_analysis:,
                                           source_region: nil, owners: nil)
        source_region_start - desired_blank_line_count_before_leading_region(
          output_owner: output_owner,
          output_analysis: output_analysis,
          source_region_start: source_region_start,
          source_region: source_region,
          source_analysis: source_analysis,
          owners: owners
        )
      end

      def desired_blank_line_count_before_leading_region(output_owner:, output_analysis:, source_region_start:,
                                                         source_analysis:, source_region: nil, owners: nil)
        target_region = leading_region_for(output_owner, output_analysis, owners: owners)
        target_region_start = region_start_line(target_region)
        output_start_line = owner_start_line(output_owner)

        if target_region_start && output_start_line && target_region_start < output_start_line
          blank_line_count_before(target_region_start, output_analysis)
        elsif source_region && previous_owner_trailing_region_matches?(output_owner, output_analysis, source_region,
                                                                       owners: owners)
          0
        else
          blank_line_count_before(source_region_start, source_analysis)
        end
      end

      def previous_owner_trailing_region_matches?(owner, analysis, source_region, owners: nil)
        previous_owner = previous_owner_for(owner, analysis, owners: owners)
        return false unless previous_owner

        previous_trailing_region = trailing_region_for(previous_owner, analysis, owners: owners)
        regions_equivalent?(previous_trailing_region, source_region)
      end

      def previous_owner_for(owner, analysis, owners: nil)
        owner_list = Array(owners || analysis&.statements).select do |entry|
          owner_start_line(entry)
        end
        index = owner_list.index(owner)
        return unless index && index.positive?

        owner_list[index - 1]
      end

      def regions_equivalent?(left, right)
        return false unless left && right

        left.respond_to?(:normalized_content) &&
          right.respond_to?(:normalized_content) &&
          left.normalized_content == right.normalized_content
      end

      def root_boundary_lines_for(kind, analysis, owners: nil, augmenter_cache: nil, fallback_to_owner_bounds: false)
        boundary_owners = owners || analysis.statements
        comment_only_lines = comment_only_root_boundary_lines_for(kind, analysis, owners: boundary_owners)
        return comment_only_lines if comment_only_lines.any?
        return [] unless analysis&.respond_to?(:comment_augmenter)

        region = root_boundary_region(kind, analysis, owners: boundary_owners, augmenter_cache: augmenter_cache)
        unless region_present?(region)
          return [] unless fallback_to_owner_bounds

          return owner_bound_root_boundary_lines_for(kind, analysis, owners: boundary_owners)
        end

        start_line, end_line = root_boundary_range(kind, analysis, region, owners: boundary_owners)
        return [] unless start_line && end_line
        return [] if start_line > end_line

        (start_line..end_line).filter_map { |line_number| source_line_at(analysis, line_number) }
      end

      def comment_only_root_boundary_lines_for(kind, analysis, owners: nil)
        return [] unless kind == :preamble
        return [] unless Array(owners || analysis.statements).empty?
        return [] unless analysis.respond_to?(:lines) && analysis.lines.any?

        (1..analysis.lines.length).filter_map { |line_number| source_line_at(analysis, line_number) }
      end

      def owner_bound_root_boundary_lines_for(kind, analysis, owners: nil)
        owner_list = Array(owners || analysis.statements).select do |owner|
          owner_start_line(owner) && owner_end_line(owner)
        end
        return [] if owner_list.empty?

        case kind
        when :preamble
          first_line = owner_list.filter_map { |owner| root_boundary_owner_start_line_for(owner, analysis) }.min
          return [] unless first_line && first_line > 1

          (1...first_line).filter_map { |line_number| source_line_at(analysis, line_number) }
        when :postlude
          last_line = owner_list.filter_map { |owner| owner_end_line(owner) }.max
          return [] unless last_line && analysis.respond_to?(:lines)
          return [] if last_line >= analysis.lines.length

          ((last_line + 1)..analysis.lines.length).filter_map { |line_number| source_line_at(analysis, line_number) }
        else
          []
        end
      end

      def root_boundary_region(kind, analysis, owners: nil, augmenter_cache: nil)
        augmenter = root_comment_augmenter_for(analysis, owners: owners, augmenter_cache: augmenter_cache)
        return unless augmenter

        kind == :preamble ? augmenter.preamble_region : augmenter.postlude_region
      end

      def root_comment_augmenter_for(analysis, owners: nil, augmenter_cache: nil)
        cache = augmenter_cache || (@root_comment_augmenters ||= {})
        key = [analysis.object_id, Array(owners || analysis.statements).map(&:object_id)]
        cache[key] ||= analysis.comment_augmenter(owners: owners || analysis.statements)
      end

      def root_boundary_range(kind, analysis, region, owners: nil)
        owner_list = Array(owners || analysis.statements).select do |owner|
          owner_start_line(owner) && owner_end_line(owner)
        end

        case kind
        when :preamble
          end_line = if owner_list.any?
                       owner_list.filter_map { |owner| root_boundary_owner_start_line_for(owner, analysis) }.min.to_i - 1
                     else
                       analysis.lines.length
                     end
          [1, end_line]
        when :postlude
          start_line = if owner_list.any?
                         owner_list.filter_map { |owner| owner_end_line(owner) }.max.to_i + 1
                       else
                         region.start_line || 1
                       end
          [start_line, analysis.lines.length]
        end
      end

      def first_owner_for(analysis, owners: nil)
        Array(owners || analysis&.statements)
          .select { |owner| owner_start_line(owner) }
          .min_by { |owner| owner_start_line(owner) }
      end

      def owner_start_line(owner)
        object_start_line(owner)
      end

      def owner_end_line(owner)
        object_end_line(owner)
      end

      def root_boundary_owner_start_line_for(owner, _analysis)
        owner_start_line(owner)
      end
    end
  end
end
