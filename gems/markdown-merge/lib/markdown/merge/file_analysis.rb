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

      # @return [Symbol] The backend being used (:commonmarker, :markly)
      attr_reader :backend

      # @return [Hash] Parser-specific options
      attr_reader :parser_options

      # Initialize file analysis with tree_haver backend.
      #
      # @param source [String] Markdown source code to analyze
      # @param backend [Symbol] Backend to use (:commonmarker, :markly, :auto)
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

      private

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
      # For :auto, attempts commonmarker first, then markly.
      # tree_haver handles the actual availability checking.
      #
      # @param backend [Symbol] Requested backend
      # @return [Symbol] Resolved backend (:commonmarker or :markly)
      def resolve_backend(backend)
        return backend unless backend == :auto

        # Try commonmarker first, then markly
        if TreeHaver::BackendRegistry.available?(:commonmarker)
          :commonmarker
        elsif TreeHaver::BackendRegistry.available?(:markly)
          :markly
        else
          # Let tree_haver raise the appropriate error
          :commonmarker
        end
      end

      # Create a parser for the resolved backend.
      #
      # @return [Object] tree_haver parser instance
      def create_parser
        case @backend
        when :commonmarker
          create_commonmarker_parser
        when :markly
          create_markly_parser
        else
          raise ArgumentError, "Unknown backend: #{@backend}"
        end
      end

      # Create a Commonmarker parser via commonmarker-merge backend.
      #
      # @return [Commonmarker::Merge::Backend::Parser]
      def create_commonmarker_parser
        parser = Commonmarker::Merge::Backend::Parser.new
        # Default options enable table extension for GFM compatibility
        default_options = { extension: { table: true } }
        options = default_options.merge(@parser_options[:options] || {})
        parser.language = Commonmarker::Merge::Backend::Language.markdown(options: options)
        parser
      end

      # Create a Markly parser via markly-merge backend.
      #
      # @return [Markly::Merge::Backend::Parser]
      def create_markly_parser
        parser = Markly::Merge::Backend::Parser.new
        flags = @parser_options[:flags]
        extensions = @parser_options[:extensions] || [:table]
        parser.language = Markly::Merge::Backend::Language.markdown(
          flags: flags,
          extensions: extensions
        )
        parser
      end
    end
  end
end
