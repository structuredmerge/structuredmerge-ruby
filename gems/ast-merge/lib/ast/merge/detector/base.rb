# frozen_string_literal: true

module Ast
  module Merge
    # Detector namespace for region detection and merging functionality.
    #
    # Regions are portions of a document that can be handled by a specialized
    # merger. For example, YAML frontmatter in a Markdown file, or Ruby code
    # blocks that should be merged with Prism.
    #
    # @example Detecting regions
    #   detector = Ast::Merge::Detector::FencedCodeBlock.ruby
    #   regions = detector.detect_all(markdown_content)
    #   regions.each do |region|
    #     puts "Found #{region.type} at lines #{region.start_line}-#{region.end_line}"
    #   end
    #
    # @see Detector::Region Data struct for detected regions
    # @see Detector::Base Base class for detectors
    # @see Detector::Mergeable Mixin for region-aware merging
    #
    module Detector
      # Represents a detected region within a document.
      #
      # Regions are portions of a document that can be handled by a specialized
      # merger. For example, YAML frontmatter in a Markdown file, or a Ruby code
      # block that should be merged using a Ruby-aware merger.
      #
      # @example Creating a region for YAML frontmatter
      #   Region.new(
      #     type: :yaml_frontmatter,
      #     content: "title: My Doc\nversion: 1.0\n",
      #     start_line: 1,
      #     end_line: 4,
      #     delimiters: ["---", "---"],
      #     metadata: { format: :yaml }
      #   )
      #
      # @api public
      Region = Struct.new(
        # @return [Symbol] The type of region (e.g., :yaml_frontmatter, :ruby_code_block)
        :type,

        # @return [String] The raw string content of this region (inner content, without delimiters)
        :content,

        # @return [Integer] 1-indexed start line in the original document
        :start_line,

        # @return [Integer] 1-indexed end line in the original document
        :end_line,

        # @return [Array<String>, nil] Delimiter strings to reconstruct the region
        :delimiters,

        # @return [Hash, nil] Optional metadata for detector-specific information
        :metadata,
        keyword_init: true
      ) do
        # Returns the line range covered by this region.
        # @return [Range]
        def line_range
          start_line..end_line
        end

        # Returns the number of lines this region spans.
        # @return [Integer]
        def line_count
          end_line - start_line + 1
        end

        # Reconstructs the full region text including delimiters.
        # @return [String]
        def full_text
          return content if delimiters.nil? || delimiters.empty?

          opening = delimiters[0] || ''
          closing = delimiters[1] || ''
          "#{opening}\n#{content}#{closing}"
        end

        # Checks if this region contains the given line number.
        # @param line [Integer] The line number to check (1-indexed)
        # @return [Boolean]
        def contains_line?(line)
          line_range.cover?(line)
        end

        # Checks if this region overlaps with another region.
        # @param other [Region] Another region
        # @return [Boolean]
        def overlaps?(other)
          line_range.cover?(other.start_line) ||
            line_range.cover?(other.end_line) ||
            other.line_range.cover?(start_line)
        end

        # @return [String]
        def to_s
          "Region<#{type}:#{start_line}-#{end_line}>"
        end

        # @return [String]
        def inspect
          truncated = if content && content.length > 30
                        "#{content[0, 30]}..."
                      else
                        content.inspect
                      end
          "#{self} #{truncated}"
        end
      end

      # Base class for region detection.
      #
      # Region detectors identify portions of a document that should be handled
      # by a specialized merger.
      #
      # Subclasses must implement:
      # - {#region_type} - Returns the type symbol for detected regions
      # - {#detect_all} - Finds all regions of this type in a document
      #
      # @example Implementing a custom detector
      #   class MyBlockDetector < Ast::Merge::Detector::Base
      #     def region_type
      #       :my_block
      #     end
      #
      #     def detect_all(source)
      #       # Return array of Region structs
      #       []
      #     end
      #   end
      #
      # @abstract Subclass and implement {#region_type} and {#detect_all}
      # @api public
      #
      class Base
        # Returns the type symbol for regions detected by this detector.
        # @return [Symbol]
        # @abstract
        def region_type
          raise NotImplementedError, "#{self.class}#region_type must be implemented"
        end

        # Detects all regions of this type in the given source.
        # @param _source [String] The full document content to scan
        # @return [Array<Region>] All detected regions, sorted by start_line
        # @abstract
        def detect_all(_source)
          raise NotImplementedError, "#{self.class}#detect_all must be implemented"
        end

        # Whether to strip delimiters from content before passing to merger.
        # @return [Boolean]
        def strip_delimiters?
          true
        end

        # A human-readable name for this detector.
        # @return [String]
        def name
          self.class.name || 'AnonymousDetector'
        end

        # @return [String]
        def inspect
          "#<#{name} region_type=#{region_type}>"
        end

        protected

        # Helper to build a Region struct.
        # @return [Region]
        def build_region(type:, content:, start_line:, end_line:, delimiters: nil, metadata: nil)
          Region.new(
            type: type,
            content: content,
            start_line: start_line,
            end_line: end_line,
            delimiters: delimiters,
            metadata: metadata || {}
          )
        end
      end

      autoload :FencedCodeBlock, 'ast/merge/detector/fenced_code_block'
      autoload :YamlFrontmatter, 'ast/merge/detector/yaml_frontmatter'
      autoload :TomlFrontmatter, 'ast/merge/detector/toml_frontmatter'
      autoload :Mergeable, 'ast/merge/detector/mergeable'
    end
  end
end
