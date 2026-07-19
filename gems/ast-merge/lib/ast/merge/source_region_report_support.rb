# frozen_string_literal: true

module Ast
  module Merge
    # Parser-neutral helpers for report-style source-region ownership views.
    #
    # Format gems still provide owner discovery and comment syntax. These helpers
    # turn those inputs into stable fixture/report data without each substrate
    # reimplementing attachment and blank-region ownership rules.
    module SourceRegionReportSupport
      private

      def source_comment_block_attachment_report(lines:, owners:, comment_line:, owner_address: nil,
                                                 owner_start_index: nil, owner_end_index: nil,
                                                 owner_declaration_start_index: nil)
        owner_address ||= ->(owner) { owner_address_for_report(owner) }
        owner_start_index ||= ->(owner) { owner_index_for_report(owner, :start_index) }
        owner_end_index ||= ->(owner) { owner_index_for_report(owner, :end_index) }
        owner_declaration_start_index ||= lambda do |owner|
          owner_index_for_report(owner, :declaration_start_index) || owner_start_index.call(owner)
        end

        comment_blocks = source_comment_blocks_for_report(lines, comment_line)
        {
          comments: comment_blocks.map do |block|
            source_comment_block_attachment(
              lines: lines,
              owners: owners,
              block: block,
              owner_address: owner_address,
              owner_end_index: owner_end_index,
              owner_declaration_start_index: owner_declaration_start_index
            )
          end
        }
      end

      def source_blank_line_ownership_regions(regions:, blank_content: nil, compact: nil)
        blank_content ||= ->(content) { content.to_s.lines.all? { |line| line.strip.empty? } }
        compact ||= ->(region) { region.reject { |_key, value| value.nil? } }

        regions.flat_map do |region|
          child_regions = region[:child_regions] ? source_blank_line_ownership_regions(regions: region[:child_regions],
                                                                                       blank_content: blank_content,
                                                                                       compact: compact) : []
          current = if region[:region_kind] == 'interstitial' && blank_content.call(region[:content])
                      [
                        compact.call(
                          region_id: region[:region_id],
                          position: region[:position],
                          previous_owner: region[:previous_owner],
                          next_owner: region[:next_owner],
                          span: region[:span],
                          ownership: 'declared_interstitial_region'
                        )
                      ]
                    else
                      []
                    end

          current + child_regions
        end
      end

      def source_comment_blocks_for_report(lines, comment_line)
        blocks = []
        index = 0
        while index < lines.length
          unless comment_line.call(lines[index])
            index += 1
            next
          end

          start_index = index
          index += 1 while index < lines.length && comment_line.call(lines[index])
          blocks << { start_index: start_index, end_index: index - 1 }
        end
        blocks
      end

      def source_comment_block_attachment(lines:, owners:, block:, owner_address:, owner_end_index:,
                                          owner_declaration_start_index:)
        previous_owner = owners.reverse.find { |owner| owner_end_index.call(owner) < block[:start_index] }
        next_owner = owners.find { |owner| owner_declaration_start_index.call(owner) > block[:end_index] }
        next_owner_index = next_owner && owner_declaration_start_index.call(next_owner)

        attachment = if next_owner_index && block[:end_index] + 1 == next_owner_index
                       'following_owner'
                     elsif previous_owner && next_owner_index && (block[:end_index] + 1...next_owner_index).any? do |idx|
                       lines[idx].to_s.strip.empty?
                     end
                       'preceding_owner'
                     elsif previous_owner && next_owner.nil?
                       'preceding_owner'
                     else
                       'standalone'
                     end

        source_report_compact_region(
          attachment: attachment,
          previous_owner: previous_owner && owner_address.call(previous_owner),
          next_owner: next_owner && owner_address.call(next_owner),
          span: source_report_line_span(block[:start_index], block[:end_index]),
          content: source_report_region_content(lines, block[:start_index], block[:end_index])
        )
      end

      def source_report_line_span(start_index, end_index)
        {
          start_line: start_index + 1,
          end_line: end_index + 1
        }
      end

      def source_report_region_content(lines, start_index, end_index)
        "#{lines[start_index..end_index].join("\n")}\n"
      end

      def source_report_compact_region(region)
        region.reject { |_key, value| value.nil? }
      end

      def owner_index_for_report(owner, key)
        if owner.respond_to?(:[])
          owner[key]
        elsif owner.respond_to?(key)
          owner.public_send(key)
        end
      end

      def owner_address_for_report(owner)
        if owner.respond_to?(:[])
          owner[:address]
        elsif owner.respond_to?(:address)
          owner.address
        end
      end
    end
  end
end
