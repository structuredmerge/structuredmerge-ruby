# frozen_string_literal: true

module Toml
  module Merge
    # Analyzes TOML file structure, extracting statements for merging.
    # This is the main analysis class that prepares TOML content for merging.
    #
    # @example Basic usage
    #   analysis = FileAnalysis.new(toml_source)
    #   analysis.valid? # => true
    #   analysis.statements # => [NodeWrapper, ...]
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      class CommentAugmenter
        OwnerRange = Struct.new(:start_line, :end_line)

        attr_reader :capability, :attachments_by_owner, :preamble_region, :postlude_region, :orphan_regions

        def initialize(analysis, owners: [], **details)
          @analysis = analysis
          @owners = Array(owners)
          @delegate = Ast::Merge::Comment::Augmenter.new(
            lines: analysis.lines,
            comments: analysis.send(:tracked_comment_entries),
            owners: analysis.send(:augmenter_delegate_owners, @owners),
            style: :hash_comment,
            **details
          )
          @capability = analysis.send(:build_comment_capability, owner_count: @owners.size, **details)
          @attachments_by_owner = @owners.each_with_object({}) do |owner, result|
            result[owner] = analysis.comment_attachment_for(owner)
          end
          @preamble_region = @delegate.preamble_region
          @postlude_region = @delegate.postlude_region
          @orphan_regions = @delegate.orphan_regions
        end

        def attachment_for(owner)
          @attachments_by_owner[owner] || @delegate.attachment_for(owner)
        end
      end

      # @return [TreeHaver::Tree, nil] Parsed AST
      attr_reader :ast

      # @return [Array] Parse errors if any
      attr_reader :errors

      # @return [Symbol] The backend used for parsing (:tree_sitter or :citrus)
      attr_reader :backend

      class << self
        # Find the parser library path using TreeHaver::GrammarFinder
        #
        # @return [String, nil] Path to the parser library or nil if not found
        def find_parser_path
          TreeHaver::GrammarFinder.new(:toml).find_library_path
        end
      end

      # Initialize file analysis
      #
      # @param source [String] TOML source code to analyze
      # @param source [String] TOML source code to analyze
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param parser_path [String, nil] Path to tree-sitter-toml parser library
      # @param options [Hash] Additional options (forward compatibility - freeze_token, node_typing, etc.)
      #
      # @note To force a specific backend, use TreeHaver.with_backend or TREE_HAVER_BACKEND env var.
      #   TreeHaver handles backend selection, auto-detection, and fallback.
      def initialize(source, signature_generator: nil, parser_path: nil, **_options)
        @source = source
        @lines = source.lines.map(&:chomp)
        @signature_generator = signature_generator
        @parser_path = parser_path
        @errors = []
        @backend = :tree_sitter # Default, will be updated during parsing
        # **options captures any additional parameters (e.g., freeze_token, node_typing) for forward compatibility

        # Parse the TOML
        DebugLogger.time('FileAnalysis#parse_toml') { parse_toml }

        @statements = integrate_nodes

        DebugLogger.debug('FileAnalysis initialized', {
                            signature_generator: signature_generator ? 'custom' : 'default',
                            statements_count: @statements.size,
                            valid: valid?
                          })
      end

      # Check if parse was successful
      # @return [Boolean]
      def valid?
        @errors.empty? && !@ast.nil?
      end

      # Get shared comment capability information for this analysis.
      #
      # @return [Ast::Merge::Comment::Capability]
      def comment_capability
        @comment_capability ||= build_comment_capability(owner_count: 0)
      end

      # Describe how TOML merges currently own and emit comments.
      #
      # Native backends expose comment nodes, but TOML still emits comments
      # through its synthetic merge layer. Source-only backends use the same
      # synthetic ownership model with a source-augmented read path.
      #
      # @return [Ast::Merge::Comment::SupportStyle]
      def comment_support_style
        @comment_support_style ||= shared_comment_support_style(
          source: native_comment_backend? ? @backend : :toml_source,
          style: :hash_comment,
          read_strategy: native_comment_backend? ? :native_read_portable_write : :source_augmented_portable_write
        )
      end

      # Get all comments converted to shared Ast::Merge comment nodes.
      #
      # @return [Array<Ast::Merge::Comment::Line>]
      def comment_nodes
        comment_tracker.comment_nodes
      end

      # Get a shared Ast::Merge comment node at a specific line.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Ast::Merge::Comment::Line, nil]
      def comment_node_at(line_num)
        comment_tracker.comment_node_at(line_num)
      end

      # Get comments in a line range converted to a shared comment region.
      #
      # @param range [Range] Range of 1-based line numbers
      # @param kind [Symbol] Region kind (:leading, :inline, :orphan, etc.)
      # @param full_line_only [Boolean] Whether to keep only full-line comments
      # @return [Ast::Merge::Comment::Region]
      def comment_region_for_range(range, kind:, full_line_only: false)
        comment_tracker.comment_region_for_range(range, kind: kind, full_line_only: full_line_only)
      end

      # Build a shared comment attachment for an owner.
      #
      # @param owner [Object] Structural owner for the attachment
      # @param line_num [Integer, nil] Optional line number override
      # @param options [Hash] Additional attachment metadata
      # @return [Ast::Merge::Comment::Attachment]
      def comment_attachment_for(owner, line_num: nil, **options)
        shared_comment_attachment_for(
          owner,
          tracker_attachment: comment_tracker.comment_attachment_for(owner, line_num: line_num, **options),
          line_num: line_num,
          **options
        )
      end

      # @return [Symbol]
      def comment_attachment_strategy
        :normalize_tracked_layout_merge
      end

      def ruleset_owner_selector
        :line_bound_statements
      end

      def ruleset_render_family
        :toml_pairs_and_tables
      end

      def comment_augmenter(owners: nil, **options)
        CommentAugmenter.new(self, owners: owners || comment_augmenter_default_owners, **options)
      end

      # Override to detect tree-sitter nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.is_a?(NodeWrapper) || super
      end

      # Get the root node of the parse tree
      # @return [NodeWrapper, nil]
      def root_node
        return unless valid?

        root = @ast.root_node
        wrap_node(root, document_root: root)
      end

      # Get a hash mapping signatures to nodes
      # @return [Hash<Array, NodeWrapper>]
      def signature_map
        @signature_map ||= build_signature_map
      end

      # Get all top-level tables (sections) in the TOML document
      # Uses NodeTypeNormalizer for backend-agnostic type checking.
      # Passes document_root to enable Citrus backend normalization (pairs as siblings).
      # @return [Array<NodeWrapper>]
      def tables
        return [] unless valid?

        result = []
        root = @ast.root_node
        root.each do |child|
          wrapper = wrap_node(child, document_root: root)
          next unless wrapper
          next unless wrapper.table? || wrapper.array_of_tables?

          result << wrapper
        end
        result
      end

      # Get all top-level key-value pairs (not in tables)
      #
      # For tree-sitter backend: pairs are nested under tables, so root-level
      # pairs are direct children of the document.
      #
      # For Citrus backend: ALL pairs are siblings at document level (flat structure).
      # We must filter to only include pairs that appear BEFORE the first table header.
      #
      # @return [Array<NodeWrapper>]
      def root_pairs
        return [] unless valid?

        result = []
        root = @ast.root_node

        # Find the line number of the first table (if any)
        first_table_line = nil
        root.each do |child|
          wrapper = wrap_node(child, document_root: root)
          next unless wrapper

          next unless wrapper.table? || wrapper.array_of_tables?

          child_line = wrapper.start_line
          first_table_line = child_line if child_line && (first_table_line.nil? || child_line < first_table_line)
        end

        root.each do |child|
          wrapper = wrap_node(child, document_root: root)
          next unless wrapper&.pair?

          # For Citrus backend, only include pairs before the first table
          if first_table_line
            child_line = wrapper.start_line
            next if child_line && child_line >= first_table_line
          end

          result << wrapper
        end
        result
      end

      private

      def parse_toml
        # TreeHaver handles everything:
        # - Backend selection (via TREE_HAVER_BACKEND env or TreeHaver.backend)
        # - Registered tree-sitter grammar lookup / provisioning
        # - Registered Citrus or Parslet TOML backends from Toml::Merge
        parser_options = {}
        parser_options[:library_path] = @parser_path if @parser_path

        parser = TreeHaver.parser_for(:toml, **parser_options)

        # For NodeTypeNormalizer, we care about the backend type:
        # - All native backends (mri, rust, ffi, java) produce tree-sitter AST format
        # - Citrus produces Citrus::Match-based nodes
        # - Parslet produces Hash/Array/Slice-based nodes
        backend_sym = parser.backend
        @backend = case backend_sym
                   when :citrus then :citrus
                   when :parslet then :parslet
                   else :tree_sitter # mri, rust, ffi, java all use tree-sitter format
                   end

        @ast = parser.parse(@source)

        # Check for parse errors in the tree
        if @ast&.root_node&.has_error?
          collect_parse_errors(@ast.root_node)
          # Don't raise here - let SmartMergerBase detect via valid? check
          # This is consistent with how other FileAnalysis classes handle parse errors
        end
      rescue TreeHaver::Error => e
        # TreeHaver::Error inherits from Exception, not StandardError.
        # This also catches TreeHaver::NotAvailable (subclass of Error).
        # Catch parse errors from Citrus backend and other TreeHaver errors.
        @errors << e.message
        @ast = nil
      rescue StandardError => e
        @errors << e unless @errors.include?(e)
        @ast = nil
      end

      def collect_parse_errors(node)
        # Collect ERROR and MISSING nodes from the tree
        if node.type.to_s == 'ERROR' || node.missing?
          @errors << {
            type: node.type.to_s,
            start_point: node.start_point,
            end_point: node.end_point,
            text: node.to_s
          }
        end

        node.each { |child| collect_parse_errors(child) }
      end

      def integrate_nodes
        return [] unless valid?

        (root_pairs + tables)
          .select { |node| node.start_line && node.end_line }
          .sort_by { |node| node.start_line || 0 }
      end

      def compute_node_signature(node)
        return unless node.is_a?(NodeWrapper)

        node.signature
      end

      def build_comment_capability(owner_count:, **details)
        capability_details = {
          source: native_comment_backend? ? @backend : :toml_source,
          style: :hash_comment,
          attachment_hints: true,
          comment_nodes: true,
          owner_count: owner_count,
          comment_count: tracked_comment_entries.size
        }.merge(details)

        if native_comment_backend?
          Ast::Merge::Comment::Capability.native_partial(**capability_details)
        else
          Ast::Merge::Comment::Capability.source_augmented(**capability_details)
        end
      end

      def augmenter_delegate_owners(owners)
        Array(owners).filter_map { |owner| comment_owner_range_for_augmenter(owner) }
      end

      def wrap_node(node, document_root: nil)
        return unless node

        NodeWrapper.new(
          node,
          lines: @lines,
          source: @source,
          backend: @backend,
          document_root: document_root || @ast&.root_node,
          comment_tracker: comment_tracker,
          comment_entries: tracked_comment_entries
        )
      end

      def comment_tracker
        @comment_tracker ||= CommentTracker.new(@lines, tracked_comment_entries, backend: @backend)
      end

      def tracked_comment_entries
        @tracked_comment_entries ||= begin
          entries = native_comment_backend? ? native_comment_entries : scanned_comment_entries
          entries.sort_by { |entry| [entry[:line], entry[:column] || 0] }
        end
      end

      def native_comment_backend?
        @backend != :parslet
      end

      def comment_owner_range_for_augmenter(owner)
        start_line = owner.respond_to?(:start_line) ? owner.start_line : nil
        return unless start_line

        end_line = comment_owner_end_line_for_augmenter(owner) || start_line
        CommentAugmenter::OwnerRange.new(start_line, [end_line, start_line].max)
      end

      def comment_owner_end_line_for_augmenter(owner)
        return owner.start_line if owner.respond_to?(:table?) && owner.table? && owner.pairs.empty?
        return owner.start_line if owner.respond_to?(:array_of_tables?) && owner.array_of_tables? && owner.pairs.empty?

        if owner.respond_to?(:table?) && owner.table? || owner.respond_to?(:array_of_tables?) && owner.array_of_tables?
          child_end_line = owner.pairs.map(&:end_line).compact.max
          return child_end_line if child_end_line
        end

        owner.respond_to?(:end_line) ? owner.end_line : nil
      end

      def native_comment_entries
        entries = []
        collect_native_comment_entries(@ast&.root_node, entries)
        entries.uniq { |entry| [entry[:line], entry[:column], entry[:raw]] }
      end

      def collect_native_comment_entries(node, entries)
        return unless node

        if NodeTypeNormalizer.canonical_type(node.type, @backend) == :comment
          entry = build_native_comment_entry(node)
          entries << entry if entry
        end

        return unless node.respond_to?(:each)

        node.each { |child| collect_native_comment_entries(child, entries) }
      end

      def build_native_comment_entry(node)
        line = node_start_line(node)
        return unless line

        raw = node_text(node).to_s.sub(/\n\z/, '')
        return unless raw.lstrip.start_with?('#')

        raw_line = line_at(line).to_s
        column = raw_line.index(raw) || node_start_column(node) || 0
        prefix = raw_line[0...column].to_s

        build_comment_entry(line: line, column: column, prefix: prefix, raw: raw, source: :native)
      end

      def scanned_comment_entries
        state = nil

        lines.each_with_index.filter_map do |line, index|
          column, state = scan_line_for_comment(line.to_s, state)
          next unless column

          raw_line = line.to_s
          raw = raw_line.byteslice(column..) || ''
          prefix = raw_line.byteslice(0, column).to_s
          build_comment_entry(line: index + 1, column: column, prefix: prefix, raw: raw, source: :scanner)
        end
      end

      def scan_line_for_comment(line, state)
        index = 0

        while index < line.bytesize
          if state == :multiline_basic
            closing = find_multiline_basic_end(line, index)
            return [nil, state] unless closing

            index = closing + 3
            state = nil
            next
          elsif state == :multiline_literal
            closing = line.index("'''", index)
            return [nil, state] unless closing

            index = closing + 3
            state = nil
            next
          end

          if line.byteslice(index, 3) == '"""'
            state = :multiline_basic
            index += 3
          elsif line.byteslice(index, 3) == "'''"
            state = :multiline_literal
            index += 3
          else
            char = line.getbyte(index)

            case char
            when 34 # "
              index = advance_basic_string(line, index + 1)
            when 39 # '
              closing = line.index("'", index + 1)
              return [nil, state] unless closing

              index = closing + 1
            when 35 # #
              return [index, state]
            else
              index += 1
            end
          end
        end

        [nil, state]
      end

      def advance_basic_string(line, index)
        while index < line.bytesize
          char = line.getbyte(index)
          if char == 92 # \\
            index += 2
          elsif char == 34 # "
            return index + 1
          else
            index += 1
          end
        end

        line.bytesize
      end

      def find_multiline_basic_end(line, index)
        position = index

        while (position = line.index('"""', position))
          return position unless escaped_in_basic_string?(line, position)

          position += 3
        end

        nil
      end

      def escaped_in_basic_string?(line, index)
        backslashes = 0
        cursor = index - 1

        while cursor >= 0 && line.getbyte(cursor) == 92
          backslashes += 1
          cursor -= 1
        end

        backslashes.odd?
      end

      def build_comment_entry(line:, column:, prefix:, raw:, source:)
        cleaned_raw = raw.sub(/\n\z/, '')
        return if cleaned_raw.empty?

        {
          line: line,
          column: column,
          indent: prefix[/\A[ \t]*/].to_s.length,
          text: cleaned_raw.sub(/\A\s*#\s?/, ''),
          full_line: prefix.strip.empty?,
          raw: cleaned_raw,
          source: source
        }
      end

      def node_start_line(node)
        extract_point_row(node.respond_to?(:start_point) ? node.start_point : nil)&.+(1)
      end

      def node_end_line(node)
        extract_point_row(node.respond_to?(:end_point) ? node.end_point : nil)&.+(1)
      end

      def node_start_column(node)
        extract_point_column(node.respond_to?(:start_point) ? node.start_point : nil)
      end

      def extract_point_row(point)
        return point.row if point.respond_to?(:row)
        return point[:row] if point.is_a?(Hash)

        nil
      end

      def extract_point_column(point)
        return point.column if point.respond_to?(:column)
        return point[:column] if point.is_a?(Hash)

        nil
      end

      def node_text(node)
        return '' unless node.respond_to?(:start_byte) && node.respond_to?(:end_byte)

        length = node.end_byte - node.start_byte
        return @source[node.start_byte, length].to_s if @backend == :citrus

        text = @source.byteslice(node.start_byte, length)
        return text if text&.valid_encoding?

        text = @source[node.start_byte, length]
        return text if text&.valid_encoding?

        text.to_s.scrub
      end

      def build_signature_map
        map = {}
        statements.each do |node|
          sig = generate_signature(node)
          map[sig] = node if sig
        end
        map
      end
    end
  end
end
