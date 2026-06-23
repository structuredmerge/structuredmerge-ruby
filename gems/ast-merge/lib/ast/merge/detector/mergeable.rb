# frozen_string_literal: true

module Ast
  module Merge
    module Detector
      ##
      # Mixin for adding region support to SmartMerger classes.
      #
      # This module provides functionality for detecting and handling regions
      # within documents that should be merged with different strategies.
      # Regions are portions of a document (like YAML frontmatter or fenced
      # code blocks) that may require specialized merging.
      #
      # @example Basic region configuration
      #   class SmartMerger
      #     include Detector::Mergeable
      #
      #     def initialize(template, dest, regions: [], region_placeholder: nil)
      #       @template_content = template
      #       @dest_content = dest
      #       setup_regions(regions: regions, region_placeholder: region_placeholder)
      #     end
      #   end
      #
      # @example With YAML frontmatter regions
      #   merger = SmartMerger.new(
      #     template,
      #     dest,
      #     regions: [
      #       {
      #         detector: Detector::YamlFrontmatter.new,
      #         merger_class: SomeYamlMerger,
      #         merger_options: { preserve_order: true }
      #       }
      #     ]
      #   )
      #
      # @example With nested regions (code blocks in markdown)
      #   merger = SmartMerger.new(
      #     template,
      #     dest,
      #     regions: [
      #       {
      #         detector: Detector::FencedCodeBlock.ruby,
      #         merger_class: Prism::Merge::SmartMerger,
      #         regions: [...]  # Nested regions!
      #       }
      #     ]
      #   )
      #
      # @see Base For implementing custom detectors
      # @see Region The data struct for detected regions
      #
      module Mergeable
        # Default placeholder prefix for extracted regions
        DEFAULT_PLACEHOLDER_PREFIX = '<<<AST_MERGE_REGION_'
        # Default placeholder suffix for extracted regions.
        DEFAULT_PLACEHOLDER_SUFFIX = '>>>'

        ##
        # Configuration for a single region type.
        #
        # @attr detector [Base] Detector instance for finding regions
        # @attr merger_class [Class, nil] Merger class for merging region content (nil to skip merging)
        # @attr merger_options [Hash] Options to pass to the region merger
        # @attr regions [Array<Hash>] Nested region configurations (recursive)
        #
        Config = Struct.new(:detector, :merger_class, :merger_options, :regions, keyword_init: true) do
          def initialize(detector:, merger_class: nil, merger_options: {}, regions: [])
            super(
              detector: detector,
              merger_class: merger_class,
              merger_options: merger_options || {},
              regions: regions || [],
            )
          end
        end

        ##
        # Extracted region with its content and placeholder.
        #
        # @attr region [Region] The detected region
        # @attr config [Config] The configuration that matched this region
        # @attr placeholder [String] The placeholder used in the document
        # @attr merged_content [String, nil] The merged content (set after merging)
        #
        ExtractedRegion = Struct.new(:region, :config, :placeholder, :merged_content, keyword_init: true)

        ##
        # Set up region handling for this merger instance.
        #
        # @param regions [Array<Hash>] Array of region configurations
        # @param region_placeholder [String, nil] Custom placeholder prefix (optional)
        # @raise [ArgumentError] if regions configuration is invalid
        #
        def setup_regions(regions:, region_placeholder: nil)
          @region_configs = build_region_configs(regions)
          @region_placeholder_prefix = region_placeholder || DEFAULT_PLACEHOLDER_PREFIX
          @extracted_template_regions = []
          @extracted_dest_regions = []
        end

        ##
        # Check if this merger has region configurations.
        #
        # @return [Boolean] true if regions are configured
        #
        def regions_configured?
          @region_configs && !@region_configs.empty?
        end

        ##
        # Extract regions from the template content, replacing with placeholders.
        #
        # @param content [String] Template content
        # @return [String] Content with regions replaced by placeholders
        # @raise [PlaceholderCollisionError] if content contains placeholder text
        #
        def extract_template_regions(content)
          return content unless regions_configured?

          extract_regions(content, @extracted_template_regions)
        end

        ##
        # Extract regions from the destination content, replacing with placeholders.
        #
        # @param content [String] Destination content
        # @return [String] Content with regions replaced by placeholders
        # @raise [PlaceholderCollisionError] if content contains placeholder text
        #
        def extract_dest_regions(content)
          return content unless regions_configured?

          extract_regions(content, @extracted_dest_regions)
        end

        ##
        # Merge extracted regions and substitute them back into the merged content.
        #
        # @param merged_content [String] The merged content with placeholders
        # @return [String] Content with placeholders replaced by merged regions
        #
        def substitute_merged_regions(merged_content)
          return merged_content unless regions_configured?

          result = merged_content

          # Process regions in reverse order of extraction to handle nested placeholders
          # We need to merge template and dest regions by their placeholder index
          merge_and_substitute_regions(result)
        end

        private

        ##
        # Build Config objects from configuration hashes.
        #
        # @param configs [Array<Hash>] Array of configuration hashes
        # @return [Array<Config>] Array of Config objects
        #
        def build_region_configs(configs)
          return [] if configs.nil? || configs.empty?

          configs.map do |config|
            case config
            when Config
              config
            when Hash
              Config.new(
                detector: config[:detector],
                merger_class: config[:merger_class],
                merger_options: config[:merger_options] || {},
                regions: config[:regions] || []
              )
            else
              raise ArgumentError, "Invalid region config: #{config.inspect}"
            end
          end
        end

        ##
        # Extract regions from content, replacing with placeholders.
        #
        # @param content [String] Content to process
        # @param storage [Array<ExtractedRegion>] Array to store extracted regions
        # @return [String] Content with placeholders
        #
        def extract_regions(content, storage)
          validate_no_placeholder_collision!(content)

          result = content
          region_index = storage.size

          @region_configs.each do |config|
            regions = config.detector.detect_all(result)

            # Process regions in reverse order to maintain correct positions
            regions.sort_by { |r| -r.start_line }.each do |region|
              placeholder = build_placeholder(region_index)
              region_index += 1

              extracted = ExtractedRegion.new(
                region: region,
                config: config,
                placeholder: placeholder,
                merged_content: nil
              )
              storage.unshift(extracted) # Add to front since we process in reverse

              # Replace the region with the placeholder
              result = replace_region_with_placeholder(result, region, placeholder)
            end
          end

          storage.sort_by! { |e| placeholder_index(e.placeholder) }
          result
        end

        ##
        # Validate that the content doesn't contain placeholder text.
        #
        # @param content [String] Content to validate
        # @raise [PlaceholderCollisionError] if placeholder is found
        #
        def validate_no_placeholder_collision!(content)
          return if content.nil? || content.empty?

          return unless content.include?(@region_placeholder_prefix)

          raise PlaceholderCollisionError, @region_placeholder_prefix
        end

        ##
        # Build a placeholder string for a given index.
        #
        # @param index [Integer] The region index
        # @return [String] The placeholder string
        #
        def build_placeholder(index)
          "#{@region_placeholder_prefix}#{index}#{DEFAULT_PLACEHOLDER_SUFFIX}"
        end

        ##
        # Extract the index from a placeholder string.
        #
        # @param placeholder [String] The placeholder string
        # @return [Integer] The extracted index
        #
        def placeholder_index(placeholder)
          placeholder.match(/#{Regexp.escape(@region_placeholder_prefix)}(\d+)/)[1].to_i
        end

        ##
        # Replace a region in content with a placeholder.
        #
        # @param content [String] The content
        # @param region [Region] The region to replace
        # @param placeholder [String] The placeholder to insert
        # @return [String] Content with region replaced
        #
        def replace_region_with_placeholder(content, region, placeholder)
          lines = content.lines
          # Region line numbers are 1-indexed
          start_idx = region.start_line - 1
          end_idx = region.end_line - 1

          # Replace the region lines with the placeholder
          before = lines[0...start_idx]
          after = lines[(end_idx + 1)..]

          # Preserve the newline style
          newline = content.include?("\r\n") ? "\r\n" : "\n"
          placeholder_line = "#{placeholder}#{newline}"

          (before + [placeholder_line] + (after || [])).join
        end

        ##
        # Merge and substitute regions back into the merged content.
        #
        # @param content [String] Merged content with placeholders
        # @return [String] Content with merged regions substituted
        #
        def merge_and_substitute_regions(content)
          result = content

          # Build a mapping of placeholder index to extracted regions from both sources
          template_by_idx = @extracted_template_regions.each_with_object({}) do |e, h|
            h[placeholder_index(e.placeholder)] = e
          end
          dest_by_idx = @extracted_dest_regions.each_with_object({}) do |e, h|
            h[placeholder_index(e.placeholder)] = e
          end

          # Find all placeholder indices in the merged content
          all_indices = (template_by_idx.keys + dest_by_idx.keys).uniq.sort

          all_indices.each do |idx|
            template_extracted = template_by_idx[idx]
            dest_extracted = dest_by_idx[idx]
            placeholder = build_placeholder(idx)

            merged_region_content = merge_region(template_extracted, dest_extracted)
            result = result.gsub(placeholder, merged_region_content) if merged_region_content
          end

          result
        end

        ##
        # Merge a region from template and destination.
        #
        # @param template_extracted [ExtractedRegion, nil] Template region
        # @param dest_extracted [ExtractedRegion, nil] Destination region
        # @return [String, nil] Merged region content, or nil if no content
        #
        def merge_region(template_extracted, dest_extracted)
          config = template_extracted&.config || dest_extracted&.config
          return unless config

          template_region = template_extracted&.region
          dest_region = dest_extracted&.region

          # Get the full text (including delimiters) for each region
          template_text = template_region&.full_text || ''
          dest_text = dest_region&.full_text || ''

          # If no merger class, prefer destination content (preserve customizations)
          unless config.merger_class
            return dest_text.empty? ? template_text : dest_text
          end

          # Extract just the content (without delimiters) for merging
          template_content = template_region&.content || ''
          dest_content = dest_region&.content || ''

          # Build merger options, including nested regions if configured
          merger_options = config.merger_options.dup
          merger_options[:regions] = config.regions unless config.regions.empty?

          # Create the merger and merge the region content
          merger = config.merger_class.new(template_content, dest_content, **merger_options)
          merged_content = merger.merge

          # Reconstruct with delimiters
          reconstruct_region_with_delimiters(template_region || dest_region, merged_content)
        end

        ##
        # Reconstruct a region with its delimiters around the merged content.
        #
        # @param region [Region] The original region (for delimiter info)
        # @param content [String] The merged content
        # @return [String] Full region text with delimiters
        #
        def reconstruct_region_with_delimiters(region, content)
          return content unless region&.delimiters

          opening, closing = region.delimiters

          # Ensure content ends with newline if it doesn't
          normalized_content = content.end_with?("\n") ? content : "#{content}\n"

          "#{opening}\n#{normalized_content}#{closing}\n"
        end
      end
    end
  end
end
