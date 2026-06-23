# frozen_string_literal: true

module Markdown
  module Merge
    # Rehydrates inline links and images to use link reference definitions.
    #
    # When markdown is processed through `to_commonmark`, reference-style links
    # `[text][label]` are converted to inline links `[text](url)`.
    # This class reverses that transformation by:
    # 1. Parsing link reference definitions from content using {LinkParser}
    # 2. Finding inline links/images using {LinkParser}'s PEG-based parsing
    # 3. Replacing inline URLs with reference labels where a definition exists
    #
    # Uses Parslet-based parsing for robust handling of:
    # - Emoji in labels (e.g., `[🖼️galtzo-discord]`)
    # - Nested brackets (for linked images like `[![alt][ref]](url)`)
    # - Multi-byte UTF-8 characters
    #
    # @example Standalone usage
    #   content = <<~MD
    #     Check out [Example](https://example.com) for more info.
    #
    #     [example]: https://example.com
    #   MD
    #   result = LinkReferenceRehydrator.rehydrate(content)
    #   # => "Check out [Example][example] for more info.\n\n[example]: https://example.com\n"
    #
    class LinkReferenceRehydrator
      # @return [String] The original content
      attr_reader :content

      # @return [DocumentProblems] Problems found during rehydration
      attr_reader :problems

      class << self
        # Rehydrate inline links/images to reference style (class method).
        #
        # @param content [String] Content to rehydrate
        # @return [String] Rehydrated content
        def rehydrate(content)
          new(content).rehydrate
        end
      end

      # Initialize a new rehydrator.
      #
      # @param content [String] Content to process
      def initialize(content)
        @content = content
        @problems = DocumentProblems.new
        @link_definitions = nil
        @duplicate_definitions = nil
        @url_to_label = nil
        @parser = LinkParser.new
        @rehydration_count = 0
      end

      # Get the map of URLs to their preferred label.
      #
      # @return [Hash<String, String>] URL => label mapping
      def link_definitions
        build_definition_maps unless @link_definitions
        @link_definitions
      end

      # Get duplicate definitions (multiple labels for same URL).
      #
      # @return [Hash<String, Array<String>>] URL => [labels] for duplicates only
      def duplicate_definitions
        build_definition_maps unless @duplicate_definitions
        @duplicate_definitions
      end

      # Rehydrate inline links and images to use reference definitions.
      #
      # Uses a tree-based approach to handle nested structures like linked images
      # `[![alt](img-url)](link-url)`. The parser builds a tree of link constructs,
      # and we process them in leaf-first (post-order) traversal to ensure
      # inner replacements are applied before outer ones.
      #
      # For linked images, this means:
      # 1. First, the inner image `![alt](img-url)` is replaced with `![alt][img-label]`
      # 2. Then, the outer link's text is updated to include the replaced image
      # 3. Finally, the outer link `[![alt][img-label]](link-url)` is replaced with `[![alt][img-label]][link-label]`
      #
      # This is done in a single pass by tracking replacement offsets.
      #
      # @return [String] Rehydrated content
      def rehydrate
        build_definition_maps unless @link_definitions
        record_duplicate_problems

        return content if @url_to_label.empty?

        # Use the new tree-based approach
        # 1. Find all link constructs with proper nesting detection
        tree = @parser.find_all_link_constructs(content)

        # 2. Collect all replacements using recursive tree processing
        # This properly handles nested structures by processing children first
        # and adjusting parent text to include child replacements
        replacements = collect_nested_replacements(tree, content)

        # 3. Apply replacements in reverse position order
        result = content.dup
        replacements.sort_by { |r| -r[:start_pos] }.each do |replacement|
          result = result[0...replacement[:start_pos]] +
                   replacement[:replacement] +
                   result[replacement[:end_pos]..]
        end

        result
      end

      # Check if rehydration made any changes.
      #
      # @return [Boolean] true if any links were rehydrated
      def changed?
        @rehydration_count.positive?
      end

      # Get count of links/images rehydrated.
      #
      # @return [Integer] Number of rehydrations performed
      attr_reader :rehydration_count

      private

      # Collect replacements from tree structure, processing children first.
      #
      # This method recursively processes the tree in post-order (children before parents).
      # When a child is replaced, the parent's text is updated to include the child's
      # replacement before the parent is processed.
      #
      # @param items [Array<Hash>] Tree items from find_all_link_constructs
      # @param text [String] The current text (used for extracting updated content)
      # @return [Array<Hash>] Replacements with :start_pos, :end_pos, :replacement
      def collect_nested_replacements(items, text)
        replacements = []

        items.each do |item|
          if item[:children]&.any?
            # Process children first and collect their replacements
            child_replacements = collect_nested_replacements(item[:children], text)

            # Try to process the parent with updated text content
            parent_replacement = process_parent_with_children(item, child_replacements)

            if parent_replacement
              # Parent was successfully processed - use ONLY the parent replacement
              # (it already includes the transformed child content)
              replacements << parent_replacement
            else
              # Parent couldn't be processed (no matching label, has title, etc.)
              # Include the child replacements instead
              replacements.concat(child_replacements)
            end
          else
            # Leaf node - process directly
            replacement = if item[:type] == :image
                            process_image(item)
                          else
                            process_link(item)
                          end
            replacements << replacement if replacement
          end
        end

        replacements
      end

      # Process a parent item that has children, accounting for child replacements.
      #
      # For a linked image like `[![alt](img-url)](link-url)`:
      # 1. The child image was already processed: `![alt](img-url)` → `![alt][img-label]`
      # 2. We need to build the new parent text: `[![alt][img-label]][link-label]`
      #
      # @param item [Hash] Parent item with :children
      # @param child_replacements [Array<Hash>] Replacements made by children
      # @return [Hash, nil] Replacement for the parent, or nil if not applicable
      def process_parent_with_children(item, child_replacements)
        # Get the label for the parent's URL
        label = @url_to_label[item[:url]]
        return unless label

        # Check if parent has a title (can't rehydrate if it does)
        if item[:title] && !item[:title].empty?
          @problems.add(
            :link_has_title,
            severity: :info,
            text: item[:text],
            url: item[:url],
            title: item[:title]
          )
          return
        end

        # Build the new link text by applying child replacements to the original text
        # Extract the original "text" part of the link (between [ and ])
        original_text = item[:text] || ''

        # Apply child replacements to build the new text content
        # Children positions are relative to the document, so we need to adjust
        new_text = original_text.dup

        # Sort child replacements by position (reverse order for safe replacement)
        sorted_children = child_replacements.sort_by { |r| -r[:start_pos] }

        sorted_children.each do |child_rep|
          # Calculate position relative to the link text start
          # The link text starts at item[:start_pos] + 1 (after the '[')
          text_start = item[:start_pos] + 1
          relative_start = child_rep[:start_pos] - text_start
          relative_end = child_rep[:end_pos] - text_start

          # Only apply if the child is within the text portion
          if relative_start >= 0 && relative_end <= new_text.length
            new_text = new_text[0...relative_start] + child_rep[:replacement] + new_text[relative_end..]
          end
        end

        @rehydration_count += 1
        {
          start_pos: item[:start_pos],
          end_pos: item[:end_pos],
          replacement: "[#{new_text}][#{label}]"
        }
      end

      def build_definition_maps
        @link_definitions = {}
        @duplicate_definitions = {}
        @url_to_label = {}
        url_to_all_labels = Hash.new { |h, k| h[k] = [] }

        definitions = @parser.parse_definitions(content)

        definitions.each do |defn|
          url_to_all_labels[defn[:url]] << defn[:label]
        end

        url_to_all_labels.each do |url, labels|
          sorted = labels.sort_by.with_index { |l, i| [l.length, i] }
          best_label = sorted.first

          @link_definitions[url] = best_label
          @url_to_label[url] = best_label

          @duplicate_definitions[url] = labels if labels.size > 1
        end
      end

      def record_duplicate_problems
        @duplicate_definitions.each do |url, labels|
          @problems.add(
            :duplicate_link_definition,
            severity: :warning,
            url: url,
            labels: labels,
            selected_label: @url_to_label[url]
          )
        end
      end

      def process_link(link)
        url = link[:url]
        title = link[:title]
        link_text = link[:text]

        if title && !title.empty?
          @problems.add(
            :link_has_title,
            severity: :info,
            text: link_text,
            url: url,
            title: title
          )
          return
        end

        label = @url_to_label[url]
        return unless label

        @rehydration_count += 1
        {
          start_pos: link[:start_pos],
          end_pos: link[:end_pos],
          replacement: "[#{link_text}][#{label}]"
        }
      end

      def process_image(image)
        url = image[:url]
        title = image[:title]
        alt_text = image[:alt]

        if title && !title.empty?
          @problems.add(
            :image_has_title,
            severity: :info,
            alt: alt_text,
            url: url,
            title: title
          )
          return
        end

        label = @url_to_label[url]
        return unless label

        @rehydration_count += 1
        {
          start_pos: image[:start_pos],
          end_pos: image[:end_pos],
          replacement: "![#{alt_text}][#{label}]"
        }
      end
    end
  end
end
