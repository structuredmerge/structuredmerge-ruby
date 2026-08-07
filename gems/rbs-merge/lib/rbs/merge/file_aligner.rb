# frozen_string_literal: true

module Rbs
  module Merge
    # Aligns declarations between template and destination files by matching signatures.
    # Produces alignment information used by SmartMerger to combine files.
    #
    # @example Basic usage
    #   aligner = FileAligner.new(template_analysis, dest_analysis)
    #   alignment = aligner.align
    #   alignment.each do |entry|
    #     case entry[:type]
    #     when :match
    #       # Both files have this declaration
    #     when :template_only
    #       # Only in template
    #     when :dest_only
    #       # Only in destination
    #     end
    #   end
    class FileAligner < ::Ast::Merge::FileAlignerBase
      # @return [FileAnalysis] Template file analysis
      attr_reader :template_analysis

      # @return [FileAnalysis] Destination file analysis
      attr_reader :dest_analysis

      # Initialize a file aligner
      #
      # @param template_analysis [FileAnalysis] Analysis of the template file
      # @param dest_analysis [FileAnalysis] Analysis of the destination file

      private

      def template_entry_key
        :template_decl
      end

      def dest_entry_key
        :dest_decl
      end

      def add_signature_aliases(map, statement, idx, analysis)
        return unless statement.is_a?(FreezeNode) && statement.nodes.any?

        statement.nodes.each do |contained_node|
          contained_sig = analysis.generate_signature(contained_node)
          map[contained_sig] << idx if contained_sig
        end
      end

      # Override: 4-tuple key for matches — preserves destination-relative order
      def match_sort_key(entry)
        [0, entry[:dest_index], 0, entry[:template_index] || 0]
      end

      # Override: dest-only entries — freeze blocks sort separately
      def dest_only_sort_key(entry)
        if entry[:dest_decl].is_a?(FreezeNode)
          [1, entry[:dest_index], 0, 0]
        else
          [0, entry[:dest_index], 1, 0]
        end
      end

      # Override: template-only items at the end, by template index
      def template_only_sort_key(entry, _dest_size)
        [2, entry[:template_index], 0, 0]
      end
    end
  end
end
