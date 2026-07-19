# frozen_string_literal: true

require 'digest'

module Markdown
  module Merge
    # File analysis for Markdown files using tree_haver backends.
    #
    # Extends FileAnalysisBase with backend-agnostic parsing via tree_haver.
    # Supports both Commonmarker and Markly backends through tree_haver's
    # unified API.
    #
    # Parses Markdown source code and extracts:
    # - Top-level block elements (headings, paragraphs, lists, code blocks, etc.)
    # - Freeze blocks marked with HTML comments
    # - Structural signatures for matching elements between files
    #
    # All nodes are wrapped with canonical types via NodeTypeNormalizer,
    # enabling portable merge rules across backends.
    #
    # Freeze blocks are marked with HTML comments:
    #   <!-- markdown-merge:freeze -->
    #   ... content to preserve ...
    #   <!-- markdown-merge:unfreeze -->
    #
    # @example Basic usage with auto backend
    #   analysis = FileAnalysis.new(markdown_source)
    #   analysis.statements.each do |node|
    #     puts "#{node.merge_type}: #{node.type}"
    #   end
    #
    # @example With specific backend
    #   analysis = FileAnalysis.new(markdown_source, backend: :markly)
    #
    # @example With custom freeze token
    #   analysis = FileAnalysis.new(source, freeze_token: "my-merge")
    #   # Looks for: <!-- my-merge:freeze --> / <!-- my-merge:unfreeze -->
    #
    # @see FileAnalysisBase Base class
    # @see NodeTypeNormalizer Type normalization
    class FileAnalysis < FileAnalysisBase
      # Default freeze token for identifying freeze blocks
      # @return [String]
      DEFAULT_FREEZE_TOKEN = 'markdown-merge'

      class << self
        def default_backend
          :auto
        end

        def default_freeze_token
          self::DEFAULT_FREEZE_TOKEN
        end

        def default_parser_options
          {}
        end

        def default_freeze_node_class
          Markdown::Merge::FreezeNode
        end
      end

      # @return [Symbol] The backend being used (:commonmarker, :markly, :kramdown)
      attr_reader :backend

      # @return [Hash] Parser-specific options
      attr_reader :parser_options

      Location = Struct.new(:start_line, :end_line, keyword_init: true)
      HeadingSectionOwner = Struct.new(:location, :heading_text, :heading_source, :level, :base, keyword_init: true)
      LinkDefinitionOwner = Struct.new(:location, :label, :url, :title, :source, keyword_init: true)
      HtmlCommentOwner = Struct.new(:location, :text, :source, keyword_init: true)
      InlineReferenceOwner = Struct.new(
        :location,
        :line,
        :start_column,
        :end_column,
        :source,
        :reference_kind,
        :label,
        :labels,
        keyword_init: true
      )
      TableRowOwner = Struct.new(:location, :source, :text, keyword_init: true)

      # Initialize file analysis with tree_haver backend.
      #
      # @param source [String] Markdown source code to analyze
      # @param backend [Symbol] Backend to use (:commonmarker, :markly, :kramdown, :auto)
      # @param freeze_token [String] Token for freeze block markers
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param parser_options [Hash] Backend-specific parser options
      #   For commonmarker: { options: {} }
      #   For markly: { flags: Markly::DEFAULT, extensions: [:table] }
      def initialize(
        source,
        backend: self.class.default_backend,
        freeze_token: self.class.default_freeze_token,
        signature_generator: nil,
        **parser_options
      )
        @requested_backend = backend
        @parser_options = self.class.default_parser_options.merge(parser_options)

        # Resolve and initialize the backend
        @backend = resolve_backend(backend)
        @parser = create_parser

        super(source, freeze_token: freeze_token, signature_generator: signature_generator)
      end

      # Parse the source document using tree_haver backend.
      #
      # Error handling follows the same pattern as other *-merge gems:
      # - TreeHaver::Error (which inherits from Exception, not StandardError) is caught
      # - TreeHaver::NotAvailable is a subclass of TreeHaver::Error, so it's also caught
      # - When an error occurs, the error is stored in @errors and nil is returned
      # - SmartMergerBase#parse_and_analyze checks valid? and raises the appropriate parse error
      #
      # @param source [String] Markdown source to parse
      # @return [Object, nil] Root document node from tree_haver, or nil on error
      def parse_document(source)
        tree = @parser.parse(source)
        tree.root_node
      rescue TreeHaver::Error => e
        # TreeHaver::Error inherits from Exception, not StandardError.
        # This also catches TreeHaver::NotAvailable (subclass of Error).
        @errors << e.message
        nil
      end

      # Get the next sibling of a node.
      #
      # Handles differences between backends:
      # - Commonmarker: node.next_sibling
      # - Markly: node.next
      #
      # @param node [Object] Current node
      # @return [Object, nil] Next sibling or nil
      def next_sibling(node)
        # tree_haver normalizes this, but handle both patterns for safety
        if node.respond_to?(:next_sibling)
          node.next_sibling
        elsif node.respond_to?(:next)
          node.next
        end
      end

      # Returns the FreezeNode class to use.
      #
      # @return [Class] Markdown::Merge::FreezeNode
      def freeze_node_class
        self.class.default_freeze_node_class
      end

      # Check if value is a tree_haver node.
      #
      # @param value [Object] Value to check
      # @return [Boolean] true if this is a parser node
      def parser_node?(value)
        # Check for tree_haver node or wrapped node
        return true if value.respond_to?(:type) && value.respond_to?(:source_position)
        return true if Ast::Merge::NodeTyping.typed_node?(value)

        false
      end

      # Override to detect tree_haver nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        Ast::Merge::NodeTyping.typed_node?(value) ||
          value.is_a?(Ast::Merge::FreezeNodeBase) ||
          parser_node?(value) ||
          super
      end

      # Compute signature for a tree_haver node.
      #
      # Uses canonical types from NodeTypeNormalizer for portable signatures.
      #
      # @param node [Object] The node (may be wrapped)
      # @return [Array, nil] Signature array
      def compute_parser_signature(node)
        # Get canonical type from wrapper or normalize raw type
        canonical_type = if Ast::Merge::NodeTyping.typed_node?(node)
                           Ast::Merge::NodeTyping.merge_type_for(node)
                         else
                           NodeTypeNormalizer.canonical_type(node.type, @backend)
                         end

        # Unwrap to access underlying node methods
        raw_node = Ast::Merge::NodeTyping.unwrap(node)

        case canonical_type
        when :heading
          level = raw_node.header_level
          # H1 is the document title — treat as a singleton (see FileAnalysisBase for rationale)
          return [:heading, 1] if level == 1

          [:heading, level, extract_text_content(raw_node)]
        when :paragraph
          # Content-based: Match paragraphs by content hash (first 32 chars of digest)
          text = extract_text_content(raw_node)
          [:paragraph, Digest::SHA256.hexdigest(text)[0, 32]]
        when :code_block
          # Content-based: Match code blocks by fence info and content hash
          content = safe_string_content(raw_node)
          fence_info = raw_node.respond_to?(:fence_info) ? raw_node.fence_info : nil
          [:code_block, fence_info, Digest::SHA256.hexdigest(content)[0, 16]]
        when :list
          # Structure-based: Match lists by type and item count (content may differ)
          list_type = raw_node.respond_to?(:list_type) ? raw_node.list_type : nil
          [:list, list_type, count_children(raw_node)]
        when :block_quote
          # Content-based: Match block quotes by content hash
          text = extract_text_content(raw_node)
          [:block_quote, Digest::SHA256.hexdigest(text)[0, 16]]
        when :thematic_break
          # Structure-based: All thematic breaks are equivalent
          [:thematic_break]
        when :html_block
          # Content-based: Match HTML blocks by content hash
          content = safe_string_content(raw_node)
          [:html_block, Digest::SHA256.hexdigest(content)[0, 16]]
        when :table
          # Content-based: Match tables by structure and header content
          header_content = extract_table_header_content(raw_node)
          [:table, count_children(raw_node), Digest::SHA256.hexdigest(header_content)[0, 16]]
        when :footnote_definition
          # Name/label-based: Match footnotes by name or label
          label = raw_node.respond_to?(:name) ? raw_node.name : safe_string_content(raw_node)
          [:footnote_definition, label]
        when :custom_block
          # Content-based: Match custom blocks by content hash
          text = extract_text_content(raw_node)
          [:custom_block, Digest::SHA256.hexdigest(text)[0, 16]]
        else
          # Unknown type - use canonical type and position
          pos = raw_node.source_position
          [:unknown, canonical_type, pos&.dig(:start_line)]
        end
      end

      # Extract all text content from a node and its children.
      #
      # Override for tree_haver nodes which don't have a `walk` method.
      # Uses recursive traversal via `children` instead.
      #
      # @param node [Object] The node
      # @return [String] Concatenated text content
      def extract_text_content(node)
        text_parts = []
        collect_text_recursive(node, text_parts)
        text_parts.join
      end

      # Safely get string content from a node.
      #
      # Override for tree_haver nodes which use `text` instead of `string_content`.
      #
      # @param node [Object] The node
      # @return [String] String content or empty string
      def safe_string_content(node)
        if node.respond_to?(:string_content)
          node.string_content.to_s
        elsif node.respond_to?(:text)
          node.text.to_s
        else
          extract_text_content(node)
        end
      rescue TypeError, NoMethodError
        extract_text_content(node)
      end

      # Collect top-level nodes from document, wrapping with canonical types.
      #
      # @return [Array<Object>] Wrapped nodes
      def collect_top_level_nodes
        nodes = []
        child = @document.first_child
        while child
          # Wrap each node with its canonical type
          wrapped = NodeTypeNormalizer.wrap(child, @backend)
          nodes << wrapped
          child = next_sibling(child)
        end
        nodes
      end

      def heading_section_owners
        headings = Array(statements).filter_map do |statement|
          next unless heading_statement?(statement)

          build_heading_owner(statement)
        end

        headings.each_with_index.map do |owner, index|
          branch_end_line = branch_end_line(headings, index)
          HeadingSectionOwner.new(
            location: Location.new(start_line: owner.location.start_line, end_line: branch_end_line),
            heading_text: owner.heading_text,
            heading_source: owner.heading_source,
            level: owner.level,
            base: owner.base
          )
        end
      end

      def link_definition_owners
        Array(statements).filter_map do |statement|
          next unless statement.respond_to?(:merge_type) && statement.merge_type == :link_definition

          position = statement.source_position
          next unless position

          LinkDefinitionOwner.new(
            location: Location.new(start_line: position[:start_line], end_line: position[:end_line]),
            label: statement.label,
            url: statement.url,
            title: statement.title,
            source: if statement.respond_to?(:content)
                      statement.content
                    else
                      source_range(position[:start_line], position[:end_line]).chomp
                    end
          )
        end
      end

      def html_comment_owners
        comment_tracker.comment_nodes.map do |comment|
          HtmlCommentOwner.new(
            location: Location.new(start_line: comment.location.start_line, end_line: comment.location.end_line),
            text: comment.content,
            source: comment.text
          )
        end
      end

      def inline_reference_owners
        source.to_s.lines.each_with_index.flat_map do |line, index|
          inline_references_for_line(line.chomp, index + 1)
        end
      end

      def table_row_owners
        ast_table_lines = {}
        ast_rows = Array(statements).flat_map do |statement|
          node = unwrap_markdown_statement(statement)
          next [] unless node.respond_to?(:type) && node.type.to_s == 'table'

          table_position = node.source_position
          if table_position
            (table_position[:start_line]..table_position[:end_line]).each do |line|
              ast_table_lines[line] = true
            end
          end
          Array(node.children).filter_map do |child|
            next unless child.respond_to?(:type) && child.type.to_s == 'table_row'

            position = child.source_position
            next unless position

            TableRowOwner.new(
              location: Location.new(start_line: position[:start_line], end_line: position[:end_line]),
              source: source_range(position[:start_line], position[:end_line]),
              text: extract_text_content(child)
            )
          end
        end
        ast_lines = ast_rows.map { |owner| owner.location.start_line }.to_h { |line| [line, true] }
        loose_rows = source.to_s.lines.each_with_index.filter_map do |line, index|
          line_number = index + 1
          next if ast_lines[line_number]
          next if ast_table_lines[line_number]
          next unless loose_table_row_line?(line)

          TableRowOwner.new(
            location: Location.new(start_line: line_number, end_line: line_number),
            source: line,
            text: line
          )
        end
        ast_rows + loose_rows
      end

      private

      def loose_table_row_line?(line)
        stripped = line.to_s.lstrip
        return false unless stripped.start_with?('|')

        stripped.include?(' |') || stripped.include?('| ')
      end

      def heading_statement?(statement)
        merge_type = if statement.respond_to?(:merge_type)
                       statement.merge_type
                     else
                       unwrap_markdown_statement(statement)&.type
                     end

        %w[heading header].include?(merge_type.to_s)
      end

      def build_heading_owner(statement)
        node = unwrap_markdown_statement(statement)
        position = node&.source_position
        return unless node && position

        heading_source = source_range(position[:start_line], position[:end_line]).sub(/\n\z/, '')
        heading_text = node.to_plaintext.to_s.sub(/\n+\z/, '')
        HeadingSectionOwner.new(
          location: Location.new(start_line: position[:start_line], end_line: position[:end_line]),
          heading_text: heading_text,
          heading_source: heading_source,
          level: node.header_level,
          base: normalize_heading_base(heading_text)
        )
      rescue StandardError
        nil
      end

      def branch_end_line(headings, index)
        current = headings[index]
        cursor = index + 1
        while cursor < headings.length
          return headings[cursor].location.start_line - 1 if headings[cursor].level <= current.level

          cursor += 1
        end

        source.to_s.lines.length
      end

      def unwrap_markdown_statement(statement)
        Ast::Merge::NodeTyping.unwrap(statement)
      rescue StandardError
        statement
      end

      def normalize_heading_base(text)
        text.to_s.sub(/\A(?:\d\uFE0F?\u20E3|[^[:alnum:][:space:]])+[ \t]*/u, '').strip.downcase
      end

      def inline_references_for_line(line, line_number)
        owners = []
        index = 0
        while index < line.length
          image = inline_image_reference_at(line, index, line_number)
          if image
            owners << image
            index = image.end_column
            next
          end

          link = inline_link_reference_at(line, index, line_number)
          if link
            owners << link
            index = link.end_column
            next
          end

          index += 1
        end
        owners
      end

      def inline_image_reference_at(line, index, line_number)
        return unless line[index] == '!' && line[index + 1] == '['

        alt_end = closing_bracket_index(line, index + 1)
        return unless alt_end && line[alt_end + 1] == '['

        label_end = closing_bracket_index(line, alt_end + 1)
        return unless label_end

        label = line[(alt_end + 2)...label_end]
        inline_reference_owner(
          line: line,
          line_number: line_number,
          start_column: index,
          end_column: label_end + 1,
          reference_kind: :image_reference,
          label: label,
          labels: [label]
        )
      end

      def inline_link_reference_at(line, index, line_number)
        return unless line[index] == '['

        text_end = closing_bracket_index(line, index)
        return unless text_end && line[text_end + 1] == '['

        label_end = closing_bracket_index(line, text_end + 1)
        return unless label_end

        text = line[(index + 1)...text_end]
        label = line[(text_end + 2)...label_end]
        image_owner = inline_image_reference_at(text, 0, line_number)
        labels = [label]
        labels.unshift(image_owner.label) if image_owner && image_owner.source == text
        inline_reference_owner(
          line: line,
          line_number: line_number,
          start_column: index,
          end_column: label_end + 1,
          reference_kind: labels.length > 1 ? :linked_image_reference : :link_reference,
          label: label,
          labels: labels
        )
      end

      def inline_reference_owner(line:, line_number:, start_column:, end_column:, reference_kind:, label:, labels:)
        InlineReferenceOwner.new(
          location: Location.new(start_line: line_number, end_line: line_number),
          line: line_number,
          start_column: start_column,
          end_column: end_column,
          source: line[start_column...end_column],
          reference_kind: reference_kind,
          label: label,
          labels: labels.compact.uniq
        )
      end

      def closing_bracket_index(text, opening_index)
        depth = 0
        index = opening_index
        while index < text.length
          case text[index]
          when '['
            depth += 1
          when ']'
            depth -= 1
            return index if depth.zero?
          end
          index += 1
        end
        nil
      end

      # Recursively collect text content from a node and its descendants.
      #
      # Uses NodeTypeNormalizer to map backend-specific types to canonical types,
      # enabling portable type checking across different markdown parsers.
      #
      # NOTE: We use `type` here instead of `merge_type` because this method operates
      # on child nodes (text, code), not top-level statements.
      # Only top-level statements are wrapped by NodeTypeNormalizer with `merge_type`.
      # However, we use NodeTypeNormalizer.canonical_type to normalize the raw type.
      #
      # @param node [Object] The node to traverse
      # @param text_parts [Array<String>] Array to accumulate text into
      # @return [void]
      def collect_text_recursive(node, text_parts)
        # Normalize the type using NodeTypeNormalizer for backend portability
        canonical_type = NodeTypeNormalizer.canonical_type(node.type, @backend)

        # Collect text from text and code nodes
        if %i[text code].include?(canonical_type)
          content = if node.respond_to?(:string_content)
                      node.string_content.to_s
                    elsif node.respond_to?(:text)
                      node.text.to_s
                    else
                      ''
                    end
          text_parts << content unless content.empty?
        end

        # Recurse into children
        node.children.each do |child|
          collect_text_recursive(child, text_parts)
        end
      end

      # Resolve the backend to use.
      #
      # For :auto, use the same backend selection as the Markdown substrate facade.
      # tree_haver handles the final availability checking.
      #
      # @param backend [Symbol] Requested backend
      # @return [Symbol] Resolved backend
      def resolve_backend(backend)
        return Markdown::Merge.resolve_backend(nil).to_sym if backend.to_s.empty? || backend == :auto

        backend.to_sym
      end

      # Create a parser for the resolved backend.
      #
      # @return [Object] tree_haver parser instance
      def create_parser
        unless Markdown::Merge::BACKEND_REFERENCES.key?(@backend.to_s)
          raise ArgumentError, "Unknown backend: #{@backend}"
        end

        parser = TreeHaver.with_backend(@backend) { TreeHaver.parser_for(:markdown) }

        case @backend
        when :commonmarker
          parser.language = commonmarker_language
        when :markly
          parser.language = markly_language
        when :kramdown
          parser.language = kramdown_language
        else
          return parser
        end

        parser
      end

      # Create a Commonmarker language config for the TreeHaver parser.
      #
      # @return [Commonmarker::Merge::Backend::Language]
      def commonmarker_language
        # Default options enable table extension for GFM compatibility
        default_options = { extension: { table: true } }
        options = default_options.merge(@parser_options[:options] || {})
        Commonmarker::Merge::Backend::Language.markdown(options: options)
      end

      # Create a Markly language config for the TreeHaver parser.
      #
      # @return [Markly::Merge::Backend::Language]
      def markly_language
        flags = @parser_options[:flags]
        extensions = @parser_options[:extensions] || [:table]
        Markly::Merge::Backend::Language.markdown(
          flags: flags,
          extensions: extensions
        )
      end

      # Create a Kramdown language config for the TreeHaver parser.
      #
      # @return [Kramdown::Merge::Backend::Language]
      def kramdown_language
        Kramdown::Merge::Backend::Language.markdown(options: @parser_options[:options] || {})
      end
    end
  end
end
