# frozen_string_literal: true

module Ast
  module Merge
    module Text
      # Abstract base class for text-based section splitters.
      #
      # A SectionSplitter takes text content (typically from a leaf node in an AST)
      # and divides it into logical sections that can be matched, compared, and
      # merged independently. This is useful for:
      #
      # - Markdown documents split by headings
      # - Plain text files with comment-delimited sections
      # - Configuration files with section markers
      # - Any text where structure is defined by patterns, not AST
      #
      # **Important**: This is for TEXT-BASED splitting of content that doesn't
      # have a structured AST. For AST-level node classification (like identifying
      # `appraise` blocks in Ruby), use `Ast::Merge::SectionTyping` instead.
      #
      # ## How Section Splitting Works
      #
      # 1. **Split**: Parse text content into sections with unique names
      # 2. **Match**: Compare sections between template and destination by name
      # 3. **Merge**: Apply merge rules per-section (template wins, dest wins, merge)
      # 4. **Join**: Reconstruct the text from merged sections
      #
      # ## Implementing a SectionSplitter
      #
      # Subclasses must implement:
      # - `split(content)` - Parse content into an array of Section objects
      # - `join(sections)` - Reconstruct content from sections
      #
      # Subclasses may override:
      # - `section_signature(section)` - Custom matching logic beyond name
      # - `merge_sections(template_section, dest_section)` - Custom section merge
      # - `normalize_name(name)` - Custom name normalization for matching
      #
      # @example Implementing a Markdown heading splitter
      #   class HeadingSplitter < SectionSplitter
      #     def initialize(split_level: 2)
      #       @split_level = split_level
      #     end
      #
      #     def split(content)
      #       # Parse and split on headings at @split_level
      #     end
      #
      #     def join(sections)
      #       sections.map(&:full_text).join
      #     end
      #   end
      #
      # @example Using a splitter for section-based merging
      #   splitter = HeadingSplitter.new(split_level: 2)
      #   template_sections = splitter.split(template_content)
      #   dest_sections = splitter.split(dest_content)
      #
      #   merged = splitter.merge_documents(
      #     template_sections,
      #     dest_sections,
      #     preference: {
      #       default: :destination,
      #       "Installation" => :template
      #     }
      #   )
      #
      #   result = splitter.join(merged)
      #
      # @abstract Subclass and implement {#split} and {#join}
      # @api public
      class SectionSplitter
        # Default preference when none specified
        DEFAULT_PREFERENCE = :destination

        # @return [Hash] Options passed to the splitter
        attr_reader :options

        # Initialize the splitter with options.
        #
        # @param options [Hash] Splitter-specific options
        def initialize(**options)
          @options = options
        end

        # Split text content into sections.
        #
        # @param content [String] The text content to split
        # @return [Array<Section>] Array of sections in document order
        # @abstract Subclasses must implement this method
        def split(content)
          raise NotImplementedError, "#{self.class}#split must be implemented"
        end

        # Reconstruct text content from sections.
        #
        # @param sections [Array<Section>] Sections to join
        # @return [String] Reconstructed text content
        # @abstract Subclasses must implement this method
        def join(sections)
          raise NotImplementedError, "#{self.class}#join must be implemented"
        end

        # Merge two text documents using section-based semantics.
        #
        # This is the main entry point for section-based merging. It:
        # 1. Splits both documents into sections
        # 2. Matches sections by name
        # 3. Merges each section according to preferences
        # 4. Joins the result back into text
        #
        # @param template_content [String] Template text content
        # @param dest_content [String] Destination text content
        # @param preference [Symbol, Hash] Merge preference
        #   - `:template` - Template wins for all sections
        #   - `:destination` - Destination wins for all sections
        #   - Hash - Per-section preferences: `{ default: :dest, "Section Name" => :template }`
        # @param add_template_only [Boolean] Whether to add sections only in template
        # @return [String] Merged text content
        def merge(template_content, dest_content, preference: DEFAULT_PREFERENCE, add_template_only: false)
          template_sections = split(template_content)
          dest_sections = split(dest_content)

          merged_sections = merge_section_lists(
            template_sections,
            dest_sections,
            preference: preference,
            add_template_only: add_template_only
          )

          join(merged_sections)
        end

        # Merge two lists of sections.
        #
        # @param template_sections [Array<Section>] Sections from template
        # @param dest_sections [Array<Section>] Sections from destination
        # @param preference [Symbol, Hash] Merge preference
        # @param add_template_only [Boolean] Whether to add template-only sections
        # @return [Array<Section>] Merged sections
        def merge_section_lists(template_sections, dest_sections, preference: DEFAULT_PREFERENCE,
                                add_template_only: false)
          # Build lookup by normalized name
          dest_by_name = dest_sections.each_with_object({}) do |section, hash|
            key = normalize_name(section.name)
            hash[key] = section
          end

          merged = []
          seen_names = Set.new

          # Process template sections in order
          template_sections.each do |template_section|
            key = normalize_name(template_section.name)
            seen_names << key

            dest_section = dest_by_name[key]

            if dest_section
              # Section exists in both - merge according to preference
              section_pref = preference_for_section(template_section.name, preference)
              merged << merge_sections(template_section, dest_section, section_pref)
            elsif add_template_only
              # Template-only section - add if configured
              merged << template_section
            end
            # Otherwise skip template-only sections
          end

          # Append destination-only sections (preserve destination content)
          dest_sections.each do |dest_section|
            key = normalize_name(dest_section.name)
            next if seen_names.include?(key)

            merged << dest_section
          end

          merged
        end

        # Merge a single pair of matching sections.
        #
        # The default implementation simply chooses one section based on preference.
        # Subclasses can override for more sophisticated merging (e.g., line-level
        # merging within sections).
        #
        # @param template_section [Section] Section from template
        # @param dest_section [Section] Section from destination
        # @param preference [Symbol] :template or :destination
        # @return [Section] Merged section
        def merge_sections(template_section, dest_section, preference)
          case preference
          when :template
            template_section
          when :destination
            dest_section
          when :merge
            # Subclasses can implement actual content merging
            merge_section_content(template_section, dest_section)
          else
            dest_section
          end
        end

        # Merge content within a section (for :merge preference).
        #
        # Default implementation prefers destination. Subclasses should override
        # for format-specific content merging.
        #
        # @param template_section [Section] Section from template
        # @param dest_section [Section] Section from destination
        # @return [Section] Section with merged content
        def merge_section_content(template_section, dest_section)
          # Default: use template header, dest body
          Section.new(
            name: dest_section.name,
            header: template_section.header || dest_section.header,
            body: dest_section.body,
            start_line: dest_section.start_line,
            end_line: dest_section.end_line,
            metadata: dest_section.metadata&.merge(template_section.metadata || {})
          )
        end

        # Get the preference for a specific section.
        #
        # @param section_name [String, Symbol] The section name
        # @param preference [Symbol, Hash] Overall preference configuration
        # @return [Symbol] :template or :destination
        def preference_for_section(section_name, preference)
          return preference unless preference.is_a?(Hash)

          # Try exact match first
          return preference[section_name] if preference.key?(section_name)

          # Try normalized name
          normalized = normalize_name(section_name)
          preference.each do |key, value|
            return value if normalize_name(key) == normalized
          end

          # Fall back to default
          preference.fetch(:default, DEFAULT_PREFERENCE)
        end

        # Normalize a section name for matching.
        #
        # Default implementation strips whitespace, downcases, normalizes spaces.
        # Subclasses can override for format-specific normalization.
        #
        # @param name [String, Symbol, nil] The section name
        # @return [String] Normalized name
        def normalize_name(name)
          return '' if name.nil?
          return name.to_s if name.is_a?(Symbol)

          name.to_s.strip.downcase.gsub(/\s+/, ' ')
        end

        # Generate a signature for section matching.
        #
        # Default uses normalized name. Subclasses can override for more
        # sophisticated matching (e.g., including metadata).
        #
        # @param section [Section] The section
        # @return [Array, String] Signature for matching
        def section_signature(section)
          normalize_name(section.name)
        end

        class << self
          # Validate a splitter configuration.
          #
          # @param config [Hash, nil] Configuration to validate
          # @raise [ArgumentError] If configuration is invalid
          # @return [void]
          def validate!(config)
            return if config.nil?

            return if config.is_a?(Hash)

            raise ArgumentError, "splitter config must be a Hash, got #{config.class}"
          end
        end
      end

      # Line-pattern section splitter for text content.
      #
      # Splits text content into sections based on a line pattern (regex).
      # Useful for documents with consistent structural markers like headings.
      #
      # @example Split Markdown on level-2 headings
      #   splitter = LineSectionSplitter.new(pattern: /^## (.+)$/)
      #   sections = splitter.split(markdown_content)
      #
      # @example Split on comment markers
      #   splitter = LineSectionSplitter.new(pattern: /^# === (.+) ===\s*$/)
      #   sections = splitter.split(config_file)
      #
      class LineSectionSplitter < SectionSplitter
        # @return [Regexp] Pattern to match section headers
        attr_reader :pattern

        # @return [Integer] Capture group index for section name (1-based)
        attr_reader :name_capture

        # Initialize a line-based splitter.
        #
        # @param pattern [Regexp] Pattern to match section header lines
        # @param name_capture [Integer] Capture group for section name (default: 1)
        # @param options [Hash] Additional options
        def initialize(pattern:, name_capture: 1, **options)
          super(**options)
          @pattern = pattern
          @name_capture = name_capture
        end

        # Split content on lines matching the pattern.
        #
        # @param content [String] Text content
        # @return [Array<Section>] Sections
        def split(content)
          lines = content.lines
          sections = []
          current_section = nil
          preamble_lines = []

          lines.each_with_index do |line, index|
            line_num = index + 1

            if (match = line.match(pattern))
              # Start new section
              if current_section
                sections << finalize_section(current_section)
              elsif preamble_lines.any?
                sections << Section.new(
                  name: :preamble,
                  header: nil,
                  body: preamble_lines.join,
                  start_line: 1,
                  end_line: line_num - 1,
                  metadata: { type: :preamble }
                )
              end

              section_name = match[name_capture] || match[0]
              current_section = {
                name: section_name.strip,
                header: line,
                body_lines: [],
                start_line: line_num
              }
            elsif current_section
              current_section[:body_lines] << line
            else
              preamble_lines << line
            end
          end

          # Finalize last section
          if current_section
            current_section[:end_line] = lines.length
            sections << finalize_section(current_section)
          elsif preamble_lines.any? && sections.empty?
            # Entire document is preamble (no sections found)
            sections << Section.new(
              name: :preamble,
              header: nil,
              body: preamble_lines.join,
              start_line: 1,
              end_line: lines.length,
              metadata: { type: :preamble }
            )
          end

          sections
        end

        # Join sections back into text content.
        #
        # @param sections [Array<Section>] Sections to join
        # @return [String] Reconstructed content
        def join(sections)
          sections.map(&:full_text).join
        end

        private

        def finalize_section(section_data)
          Section.new(
            name: section_data[:name],
            header: section_data[:header],
            body: section_data[:body_lines].join,
            start_line: section_data[:start_line],
            end_line: section_data[:end_line] || section_data[:start_line] + section_data[:body_lines].length,
            metadata: nil
          )
        end
      end
    end
  end
end
