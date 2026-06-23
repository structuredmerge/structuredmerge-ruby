# frozen_string_literal: true

require 'parslet'

module Markdown
  module Merge
    # Parslet-based parser for markdown link structures.
    #
    # This parser extracts:
    # - Link reference definitions: `[label]: url` or `[label]: url "title"`
    # - Inline links: `[text](url)` or `[text](url "title")`
    # - Inline images: `![alt](url)` or `![alt](url "title")`
    # - Linked images: `[![alt](img-url)](link-url)` (nested structures)
    #
    # Handles complex cases like:
    # - Emoji in labels (e.g., `[🖼️galtzo-discord]`)
    # - Nested brackets (for linked images like `[![alt][ref]](url)`)
    # - Multi-byte UTF-8 characters
    #
    # @example Parse link definitions
    #   parser = LinkParser.new
    #   defs = parser.parse_definitions("[example]: https://example.com\n[🎨logo]: https://logo.png")
    #   # => [{ label: "example", url: "https://example.com" }, { label: "🎨logo", url: "https://logo.png" }]
    #
    # @example Find inline links with nested structure detection
    #   parser = LinkParser.new
    #   items = parser.find_all_link_constructs("Click [![Logo](img.png)](link.com) here")
    #   # Returns a tree structure with :children for nested items
    #
    class LinkParser
      # Grammar for link reference definitions
      class DefinitionGrammar < Parslet::Parser
        rule(:space) { match('[ \t]') }
        rule(:spaces) { space.repeat(1) }
        rule(:spaces?) { space.repeat }

        # Bracket content: handles nested brackets recursively
        rule(:bracket_content) do
          (
            str('[') >> bracket_content.maybe >> str(']') |
            str(']').absent? >> any
          ).repeat
        end

        rule(:label) { str('[') >> bracket_content.as(:label) >> str(']') }

        rule(:url_char) { match('[^\s>]') }
        rule(:bare_url) { url_char.repeat(1) }
        rule(:angled_url_char) { match('[^>]') }
        rule(:angled_url) { str('<') >> angled_url_char.repeat(1) >> str('>') }
        rule(:url) { (angled_url | bare_url).as(:url) }

        rule(:title_content_double) { (str('"').absent? >> any).repeat }
        rule(:title_content_single) { (str("'").absent? >> any).repeat }
        rule(:title_content_paren) { (str(')').absent? >> any).repeat }

        rule(:title_double) { str('"') >> title_content_double.as(:title) >> str('"') }
        rule(:title_single) { str("'") >> title_content_single.as(:title) >> str("'") }
        rule(:title_paren) { str('(') >> title_content_paren.as(:title) >> str(')') }
        rule(:title) { title_double | title_single | title_paren }

        rule(:definition) do
          spaces? >> label >> str(':') >> spaces? >> url >> (spaces >> title).maybe >> spaces?
        end

        root(:definition)
      end

      # Grammar for inline links: [text](url) or [text](url "title")
      class InlineLinkGrammar < Parslet::Parser
        rule(:space) { match('[ \t]') }
        rule(:spaces) { space.repeat(1) }

        # Bracket content with recursive nesting
        rule(:bracket_content) do
          (
            str('[') >> bracket_content.maybe >> str(']') |
            str(']').absent? >> any
          ).repeat
        end

        rule(:link_text) { str('[') >> bracket_content.as(:text) >> str(']') }

        # URL content - handles balanced parens inside URLs
        rule(:paren_content) do
          (
            str('(') >> paren_content.maybe >> str(')') |
            match('[^()\s"\']')
          ).repeat
        end

        rule(:url) { paren_content.as(:url) }

        rule(:title_content_double) { (str('"').absent? >> any).repeat }
        rule(:title_content_single) { (str("'").absent? >> any).repeat }
        rule(:title_double) { str('"') >> title_content_double.as(:title) >> str('"') }
        rule(:title_single) { str("'") >> title_content_single.as(:title) >> str("'") }
        rule(:title) { title_double | title_single }

        rule(:url_part) { str('(') >> url >> (spaces >> title).maybe >> str(')') }

        rule(:inline_link) { link_text >> url_part }

        root(:inline_link)
      end

      # Grammar for inline images: ![alt](url) or ![alt](url "title")
      class InlineImageGrammar < Parslet::Parser
        rule(:space) { match('[ \t]') }
        rule(:spaces) { space.repeat(1) }

        rule(:bracket_content) do
          (
            str('[') >> bracket_content.maybe >> str(']') |
            str(']').absent? >> any
          ).repeat
        end

        rule(:alt_text) { str('![') >> bracket_content.as(:alt) >> str(']') }

        rule(:paren_content) do
          (
            str('(') >> paren_content.maybe >> str(')') |
            match('[^()\s"\']')
          ).repeat
        end

        rule(:url) { paren_content.as(:url) }

        rule(:title_content_double) { (str('"').absent? >> any).repeat }
        rule(:title_content_single) { (str("'").absent? >> any).repeat }
        rule(:title_double) { str('"') >> title_content_double.as(:title) >> str('"') }
        rule(:title_single) { str("'") >> title_content_single.as(:title) >> str("'") }
        rule(:title) { title_double | title_single }

        rule(:url_part) { str('(') >> url >> (spaces >> title).maybe >> str(')') }

        rule(:inline_image) { alt_text >> url_part }

        root(:inline_image)
      end

      def initialize
        @definition_grammar = DefinitionGrammar.new
        @link_grammar = InlineLinkGrammar.new
        @image_grammar = InlineImageGrammar.new
      end

      # Parse link reference definitions from content.
      #
      # @param content [String] Markdown content
      # @return [Array<Hash>] Array of { label:, url:, title: (optional) }
      def parse_definitions(content)
        definitions = []

        content.each_line do |line|
          result = parse_definition_line(line.chomp)
          definitions << result if result
        end

        definitions
      end

      # Parse a single line as a link reference definition.
      #
      # @param line [String] A single line
      # @return [Hash, nil] { label:, url:, title: } or nil
      def parse_definition_line(line)
        result = @definition_grammar.parse(line)

        url = result[:url].to_s
        # Strip angle brackets if present
        url = url[1..-2] if url.start_with?('<') && url.end_with?('>')

        definition = {
          label: result[:label].to_s,
          url: url
        }
        definition[:title] = result[:title].to_s if result[:title]
        definition
      rescue Parslet::ParseFailed
        nil
      end

      # Find all inline links in content with positions.
      #
      # @param content [String] Markdown content
      # @return [Array<Hash>] Array of { text:, url:, title:, start_pos:, end_pos: }
      def find_inline_links(content)
        find_constructs(content, :link)
      end

      # Find all inline images in content with positions.
      #
      # @param content [String] Markdown content
      # @return [Array<Hash>] Array of { alt:, url:, title:, start_pos:, end_pos: }
      def find_inline_images(content)
        find_constructs(content, :image)
      end

      # Build URL to label mapping from definitions.
      #
      # @param definitions [Array<Hash>] From parse_definitions
      # @return [Hash<String, String>] URL => best label
      def build_url_to_label_map(definitions)
        url_to_labels = Hash.new { |h, k| h[k] = [] }

        definitions.each do |defn|
          url_to_labels[defn[:url]] << defn[:label]
        end

        url_to_labels.transform_values do |labels|
          labels.min_by { |l| [l.length, l] }
        end
      end

      # Find all link constructs (links and images) with proper nesting structure.
      #
      # This method returns a flat list of items where linked images are represented
      # as a single item with :children containing the nested image. This allows
      # for proper replacement from leaves to root.
      #
      # @param content [String] Markdown content
      # @return [Array<Hash>] Array of link/image constructs with :children for nested items
      def find_all_link_constructs(content)
        # Find all images and links
        images = find_inline_images(content)
        links = find_inline_links(content)

        # Build a tree structure where images inside links are children
        build_link_tree(links, images)
      end

      # Build a tree structure from links and images, detecting nesting.
      #
      # @param links [Array<Hash>] Links with :start_pos and :end_pos
      # @param images [Array<Hash>] Images with :start_pos and :end_pos
      # @return [Array<Hash>] Links/images with :children for nested items
      def build_link_tree(links, images)
        # Combine all items
        all_items = links.map { |l| l.merge(type: :link) } +
                    images.map { |i| i.merge(type: :image) }

        # Sort by start position
        sorted = all_items.sort_by { |item| item[:start_pos] }

        result = []
        skip_until = -1

        sorted.each do |item|
          # Skip items that are children of a previous item
          next if item[:start_pos] < skip_until

          # Find any items nested inside this one
          children = sorted.select do |other|
            other[:start_pos] > item[:start_pos] &&
              other[:end_pos] <= item[:end_pos] &&
              other != item
          end

          if children.any?
            item = item.merge(children: children)
            # Mark children to be skipped
            skip_until = item[:end_pos]
          end

          result << item
        end

        result
      end

      # Flatten a tree of link constructs to leaf-first order for processing.
      #
      # This is useful for replacement operations where we want to process
      # innermost items first (depth-first, post-order traversal).
      #
      # @param items [Array<Hash>] Items from find_all_link_constructs
      # @return [Array<Hash>] Items in leaf-first order (children before parents)
      def flatten_leaf_first(items)
        result = []

        items.each do |item|
          if item[:children]
            # First add children (recursively), then the parent
            result.concat(flatten_leaf_first(item[:children]))
          end
          # Add the item without children key for cleaner processing
          result << item.except(:children)
        end

        result
      end

      private

      def find_constructs(content, type)
        results = []
        pos = 0
        grammar = type == :image ? @image_grammar : @link_grammar
        start_marker = type == :image ? '![' : '['

        while pos < content.length
          idx = content.index(start_marker, pos)
          break unless idx

          # For links, skip if preceded by ! (that's an image)
          if type == :link && idx > 0 && content[idx - 1] == '!'
            pos = idx + 1
            next
          end

          result = try_parse_construct_at(content, idx, grammar, type)

          if result
            results << result
            pos = result[:end_pos]
          else
            pos = idx + 1
          end
        end

        results
      end

      def try_parse_construct_at(content, start_idx, grammar, type)
        remaining = content[start_idx..]

        # Find the closing ) by tracking balanced brackets/parens
        bracket_end = find_bracket_end(remaining, type == :image ? 1 : 0)
        return unless bracket_end

        # Check for ( after ]
        return if bracket_end + 1 >= remaining.length
        return unless remaining[bracket_end + 1] == '('

        paren_end = find_paren_end(remaining, bracket_end + 1)
        return unless paren_end

        # Extract the substring and try to parse it
        substring = remaining[0..paren_end]

        begin
          result = grammar.parse(substring)

          parsed = if type == :image
                     {
                       alt: result[:alt].to_s,
                       url: result[:url].to_s,
                       start_pos: start_idx,
                       end_pos: start_idx + substring.length,
                       original: substring
                     }
                   else
                     {
                       text: result[:text].to_s,
                       url: result[:url].to_s,
                       start_pos: start_idx,
                       end_pos: start_idx + substring.length,
                       original: substring
                     }
                   end

          parsed[:title] = result[:title].to_s if result[:title]
          parsed
        rescue Parslet::ParseFailed
          nil
        end
      end

      def find_bracket_end(text, start_offset)
        depth = 0
        pos = start_offset

        while pos < text.length
          case text[pos]
          when '['
            depth += 1
          when ']'
            depth -= 1
            return pos if depth == 0
          end
          pos += 1
        end

        nil
      end

      def find_paren_end(text, start_offset)
        depth = 0
        pos = start_offset
        in_quotes = false
        quote_char = nil

        while pos < text.length
          char = text[pos]

          if !in_quotes && ['"', "'"].include?(char)
            in_quotes = true
            quote_char = char
          elsif in_quotes && char == quote_char
            in_quotes = false
            quote_char = nil
          elsif !in_quotes
            case char
            when '('
              depth += 1
            when ')'
              depth -= 1
              return pos if depth == 0
            end
          end

          pos += 1
        end

        nil
      end
    end
  end
end
