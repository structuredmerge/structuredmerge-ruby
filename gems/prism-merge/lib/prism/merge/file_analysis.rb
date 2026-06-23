# frozen_string_literal: true

module Prism
  module Merge
    # Simplified file analysis using Prism's native comment attachment.
    # This version leverages parse_result.attach_comments! to automatically
    # attach comments to nodes, eliminating the need for manual comment tracking
    # and the CommentNode class.
    #
    # Key improvements over V1:
    # - Uses Prism's native node.location.leading_comments and trailing_comments
    # - No manual comment tracking or CommentNode class
    # - Simpler freeze block extraction via comment scanning
    # - Better performance (one attach_comments! call vs multiple iterations)
    # - Enhanced freeze block validation (detects partial nodes and non-class/module contexts)
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      class NativeCommentAugmenter
        attr_reader :capability, :attachments_by_owner, :preamble_region, :postlude_region, :orphan_regions

        def initialize(analysis, owners: [], **details)
          @analysis = analysis
          @owners = Array(owners)
          @capability = Ast::Merge::Comment::Capability.native_full(
            source: :prism,
            style: :hash_comment,
            attachment_hints: true,
            comment_nodes: true,
            owner_count: @owners.size,
            comment_count: @analysis.tree.comments.size,
            **details
          )
          @attachments_by_owner = {}
          @preamble_region = nil
          @postlude_region = nil
          @orphan_regions = []
          build!
        end

        def attachment_for(owner)
          @attachments_by_owner[owner]
        end

        private

        def build!
          claimed = {}

          if @analysis.send(:comment_only_file?)
            entries = @analysis.send(:native_comment_entries_in_range, 1..@analysis.lines.length).select do |entry|
              entry[:full_line]
            end
            @preamble_region = @analysis.send(:build_comment_region, :preamble, entries) if entries.any?
            return
          end

          @owners.each do |owner|
            attachment = @analysis.comment_attachment_for(owner)
            @attachments_by_owner[owner] = attachment
            claim_entries!(claimed, @analysis.send(:owner_leading_comment_entries, owner))
            claim_entries!(claimed, @analysis.send(:owner_inline_comment_entries, owner))
            claim_entries!(claimed, @analysis.send(:owner_trailing_comment_entries, owner))
          end

          if @owners.empty?
            @preamble_region = @analysis.comment_region_for_range(1..@analysis.lines.length, kind: :preamble,
                                                                                             full_line_only: true)
            return
          end

          first_owner_start = @analysis.send(:owner_start_line, @owners.first)
          last_owner_end = @analysis.send(:owner_end_line, @owners.last)

          if first_owner_start && first_owner_start > 1
            first_owner_attachment = @attachments_by_owner[@owners.first]
            attached_leading_lines = first_owner_attachment&.leading_region&.nodes&.map do |node|
              node.line_number if node.respond_to?(:line_number)
            end&.compact || []

            preamble_entries = @analysis.send(:native_comment_entries_in_range,
                                              1..(first_owner_start - 1)).select do |entry|
              entry[:full_line] && !attached_leading_lines.include?(entry[:line])
            end
            if preamble_entries.any?
              @preamble_region = @analysis.send(:build_comment_region, :preamble, preamble_entries)
              claim_entries!(claimed, preamble_entries)
            end
          end

          if last_owner_end && last_owner_end < @analysis.lines.length
            postlude_entries = @analysis.send(:native_comment_entries_in_range,
                                              (last_owner_end + 1)..@analysis.lines.length).select do |entry|
              entry[:full_line]
            end
            if postlude_entries.any?
              @postlude_region = @analysis.send(:build_comment_region, :postlude, postlude_entries)
              claim_entries!(claimed, postlude_entries)
            end
          end

          infer_orphan_regions!(claimed)
        end

        def infer_orphan_regions!(claimed)
          remaining = @analysis.send(:native_comment_entries).select do |entry|
            entry[:full_line] && !claimed.key?(entry_key(entry))
          end
          return if remaining.empty?

          group_full_line_entries(remaining).each do |group|
            region = @analysis.send(:build_comment_region, :orphan, group)
            next unless region

            @orphan_regions << region
            attach_orphan_region_to_nearest_owner(region)
          end
        end

        def attach_orphan_region_to_nearest_owner(region)
          owner = @owners.reverse_each.find do |candidate|
            @analysis.send(:owner_end_line, candidate).to_i < region.location.start_line
          end
          return unless owner

          current = @attachments_by_owner[owner]
          @attachments_by_owner[owner] = Ast::Merge::Comment::Attachment.new(
            owner: current.owner,
            leading_region: current.leading_region,
            inline_region: current.inline_region,
            trailing_region: current.trailing_region,
            orphan_regions: current.orphan_regions + [region],
            leading_gap: current.leading_gap,
            trailing_gap: current.trailing_gap,
            metadata: current.metadata
          )
        end

        def group_full_line_entries(entries)
          entries.sort_by { |entry| entry[:line] }.each_with_object([]) do |entry, groups|
            current = groups.last
            if current && only_blank_lines_between?(current.last[:line], entry[:line])
              current << entry
            else
              groups << [entry]
            end
          end
        end

        def only_blank_lines_between?(from_line, to_line)
          return true if to_line <= from_line + 1

          ((from_line + 1)...to_line).all? { |line_number| @analysis.line_at(line_number).to_s.strip.empty? }
        end

        def claim_entries!(claimed, entries)
          Array(entries).each { |entry| claimed[entry_key(entry)] = true }
        end

        def entry_key(entry)
          [entry[:line], entry[:raw], entry[:attached_as]]
        end
      end

      # Default freeze token for identifying freeze blocks
      DEFAULT_FREEZE_TOKEN = 'prism-merge'

      # Canonical placeholder used in signatures to normalize the gemspec block variable.
      # When `Gem::Specification.new do |spec|` uses a different name from the template
      # (e.g. `|gem|`), assignment nodes such as `spec.name = "foo"` and `gem.name = "foo"`
      # would otherwise produce different signatures and never match.  We normalize both to
      # this placeholder so they match regardless of the variable name chosen by the author.
      GEMSPEC_VAR_PLACEHOLDER = :__gemspec_var__

      # @return [TreeHaver::Tree] The tree_haver parse tree (includes normalized comment objects)
      attr_reader :tree

      # @return [Prism::ParseResult] The underlying Prism parse result (via TreeHaver routing)
      attr_reader :parse_result

      # The block parameter name used in `Gem::Specification.new do |X|` (e.g. "spec",
      # "gem", "s").  nil for non-gemspec files.  Exposed so callers can override it for
      # nested body merges where the outer wrapper is not present in the body text.
      attr_reader :gemspec_block_var

      # Sets the gemspec block variable and clears any cached node signature data so
      # that subsequent calls to +nodes_with_comments+ use the updated placeholder.
      def gemspec_block_var=(var)
        return if @gemspec_block_var == var

        @gemspec_block_var = var
        @nodes_with_comments = nil # invalidate memoised cache
      end

      # Lines claimed by promoted BlockDirective nodes.
      # These lines appear in the source as comment-only directive markers (e.g.
      # `# token:freeze`) that Prism hoists onto the next code node's leading_comments.
      # The claimed_lines set is used by the emission pipeline to avoid re-emitting
      # those comment lines as leading_comments of adjacent code nodes.
      #
      # @return [Set<Integer>] 1-based line numbers claimed by BlockDirective promotions
      def claimed_lines
        @claimed_lines ||= Set.new
      end

      # Initialize file analysis with Prism's native comment handling
      #
      # @param source [String] Ruby source code to analyze
      # @param freeze_token [String] Token for freeze block markers (default: "prism-merge")
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param options [Hash] Additional options for forward compatibility
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil, source_label: nil,
                     **_options)
        @source = source
        @lines = source.lines
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @source_label = source_label
        # **options captured for forward compatibility
        # Route through the Prism backend that Prism::Merge registers with TreeHaver
        # during bootstrap rather than calling Prism.parse directly.
        # Store the full tree_haver result so downstream code can use @tree.comments
        # (normalized, deduplicated, with attachment hints) rather than accessing raw
        # Prism::Comment objects via @parse_result.comments or node.location.leading_comments.
        @tree = DebugLogger.time('FileAnalysis#parse') do
          TreeHaver.parser_for(:ruby).parse(source)
        end
        @parse_result = @tree.parse_result
        @gemspec_block_var = detect_gemspec_block_var

        # Use Prism's native comment attachment
        # On JRuby, the Comments class may not be loaded yet, so we need to require it
        attach_comments_safely!

        # Extract and validate structure
        @statements = extract_and_integrate_all_nodes

        DebugLogger.debug('FileAnalysis initialized', {
                            signature_generator: signature_generator ? 'custom' : 'default',
                            statements_count: @statements.size,
                            frozen_nodes_count: frozen_nodes.size
                          })
      end

      # Check if parse was successful
      # @return [Boolean]
      def valid?
        @parse_result.success?
      end

      # Get parse errors for compatibility with SmartMergerBase.
      # @return [Array<Prism::ParseError>] Array of parse errors
      def errors
        @parse_result.errors
      end

      # Get shared comment capability information for this analysis.
      #
      # @return [Ast::Merge::Comment::Capability]
      def comment_capability
        @comment_capability ||= Ast::Merge::Comment::Capability.native_full(
          source: :prism,
          style: :hash_comment,
          attachment_hints: true,
          comment_nodes: true,
          comment_count: comment_nodes.size
        )
      end

      # Describe how Prism merges own and emit comments.
      #
      # Prism exposes native owned comments and attachment hints, but merge output
      # still flows through ast-merge's synthetic ownership/emission layer.
      #
      # @return [Ast::Merge::Comment::SupportStyle]
      def comment_support_style
        @comment_support_style ||= shared_comment_support_style(
          source: :prism,
          style: :hash_comment,
          read_strategy: :native_read_portable_write
        )
      end

      def ruleset_owner_selector
        :prism_statement_sequence
      end

      def ruleset_render_family
        :prism_ruby_source
      end

      def ruleset_repair_policies
        [
          { kind: :comment_ownership_overlap, handling: :heal },
          { kind: :duplicate_template_leading_prefix, handling: :heal }
        ]
      end

      def ruleset_surfaces
        [
          { name: :ruby_doc_comment, selector: :native_attachment },
          { name: :yard_example_block, selector: :yard_example_tag }
        ]
      end

      def ruleset_delegation_policies
        [
          { surface_name: :ruby_doc_comment, strategy: :same_ruleset },
          { surface_name: :yard_example_block, strategy: :same_ruleset }
        ]
      end

      # Get all supported comments converted to shared/native Ruby comment nodes.
      #
      # @return [Array<Prism::Merge::Comment::Line>]
      def comment_nodes
        native_comment_entries.map { |entry| entry[:node] }
      end

      # Get a shared/native Ruby comment node at a specific line.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Prism::Merge::Comment::Line, nil]
      def comment_node_at(line_num)
        native_comment_entries.find { |entry| entry[:line] == line_num }&.dig(:node)
      end

      # Get comments in a line range converted to a shared comment region.
      #
      # @param range [Range] Range of 1-based line numbers
      # @param kind [Symbol] Region kind (:leading, :inline, :orphan, etc.)
      # @param full_line_only [Boolean] Whether to keep only full-line comments
      # @return [Ast::Merge::Comment::Region]
      def comment_region_for_range(range, kind:, full_line_only: false)
        entries = native_comment_entries_in_range(range)
        entries = entries.select { |entry| entry[:full_line] } if full_line_only
        build_comment_region(kind, entries, metadata: { range: range, full_line_only: full_line_only })
      end

      # Build a native shared comment attachment for an owner.
      #
      # @param owner [Object] Structural owner for the attachment
      # @param options [Hash] Additional metadata preserved on the attachment
      # @return [Ast::Merge::Comment::Attachment]
      def comment_attachment_for(owner, **options)
        leading_entries = owner_leading_comment_entries(owner)
        split_preamble = split_first_owner_preamble?(owner, leading_entries)
        _preamble_entries, leading_entries = split_first_owner_preamble_entries(leading_entries) if split_preamble

        leading_region = build_comment_region(
          :leading,
          leading_entries,
          metadata: split_preamble ? { floating: true } : {}
        )
        inline_region = build_comment_region(:inline, owner_inline_comment_entries(owner))
        trailing_region = build_comment_region(:trailing, owner_trailing_comment_entries(owner))
        layout_attachment = layout_attachment_for(owner, **options)

        Ast::Merge::Comment::Attachment.new(
          owner: owner,
          leading_region: leading_region,
          inline_region: inline_region,
          trailing_region: trailing_region,
          leading_gap: layout_attachment.leading_gap,
          trailing_gap: layout_attachment.trailing_gap,
          metadata: {
            source: :prism_native,
            line_num: owner_start_line(owner)
          }.merge(options)
        )
      end

      # Build a native shared comment augmenter for this analysis.
      #
      # @param owners [Array<#start_line,#end_line>, nil] Owners used for attachment exposure
      # @param options [Hash] Additional capability details
      # @return [NativeCommentAugmenter]
      def comment_augmenter(owners: nil, **options)
        NativeCommentAugmenter.new(self, owners: owners || comment_augmenter_default_owners, **options)
      end

      # Build a shared layout attachment for an owner using native Prism locations.
      #
      # @param owner [Object] Structural owner for the attachment
      # @param options [Hash] Additional metadata preserved on the attachment
      # @return [Ast::Merge::Layout::Attachment]
      def layout_attachment_for(owner, **options)
        owners = layout_augmenter_default_owners
        augmenter = if owners.any? { |candidate| candidate.equal?(owner) }
                      layout_augmenter(**options)
                    else
                      layout_augmenter(owners: [owner], **options)
                    end

        augmenter.attachment_for(owner) || Ast::Merge::Layout::Attachment.new(
          owner: owner,
          metadata: {
            source: :prism_native,
            line_num: owner_start_line(owner)
          }.merge(options)
        )
      end

      # Build a shared layout augmenter for this analysis using native Prism locations.
      #
      # @param owners [Array<Object>, nil] Owners used for gap inference
      # @param options [Hash] Additional metadata preserved on the augmenter
      # @return [Ast::Merge::Layout::Augmenter]
      def layout_augmenter(owners: nil, **options)
        if owners.nil? && options.empty?
          @layout_augmenter ||= build_layout_augmenter(layout_augmenter_default_owners)
        else
          build_layout_augmenter(owners || layout_augmenter_default_owners, **options)
        end
      end

      # Get nodes with their associated comments and metadata
      # Comments are now accessed via Prism's native node.location API
      # @return [Array<Hash>] Array of node info hashes
      def nodes_with_comments
        @nodes_with_comments ||= extract_nodes_with_comments
      end

      # Build a semantic sidecar that exposes Ruby doc-comment surfaces without
      # taking ownership of reconstruction away from Prism source spans.
      #
      # @return [Prism::Merge::RubyDocSurfaceAnalyzer]
      def ruby_doc_surface_analyzer
        @ruby_doc_surface_analyzer ||= RubyDocSurfaceAnalyzer.new(self)
      end

      # Override to detect Prism nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.respond_to?(:canonical_type) || value.is_a?(::Prism::Node) || super
      end

      # Determine if a node is frozen (has a freeze marker in its leading comments).
      #
      # For Ruby AST nodes, a freeze marker applies only to the node it directly
      # precedes in leading comments. If a freeze marker appears INSIDE a block
      # (nested in the body), it applies to that nested statement, NOT the outer
      # block. This is different from comment-only formats like Markdown where
      # checking content containment makes sense.
      #
      # Nested freeze markers inside the node's body are handled during recursive
      # body merging, where each nested statement gets its own freeze detection.
      #
      # @param node [Prism::Node, Ast::Merge::NodeTyping::FrozenWrapper] The node to check
      # @param claimed_lines [Set<Integer>] Line numbers already claimed by promoted BlockDirective nodes
      # @return [Boolean] true if the node has an unclaimed freeze marker in its leading comments
      def frozen_node?(node, claimed_lines: Set.new)
        # Already wrapped as frozen
        return true if node.is_a?(Ast::Merge::Freezable)

        return false unless @freeze_token

        # Get the actual node (in case it's a Wrapper)
        actual_node = node.respond_to?(:unwrap) ? node.unwrap : node

        freeze_pattern = /#{Regexp.escape(@freeze_token)}:freeze/i

        # BlockDirectiveDetector has already promoted balanced freeze/unfreeze pairs
        # to FreezeNode synthetic nodes. Any remaining freeze marker in leading
        # comments is unbalanced (node-level freeze marker), so use simple any? check.
        # Exclude markers at lines already claimed by promoted BlockDirective nodes
        # (those were hoisted onto this node by Prism's attach_comments!).
        if actual_node.respond_to?(:location) && actual_node.location.respond_to?(:leading_comments)
          return actual_node.location.leading_comments.any? do |c|
            c.slice.match?(freeze_pattern) && !claimed_lines.include?(c.location.start_line)
          end
        end

        false
      end

      # Check if a line falls within a frozen Prism-owned statement.
      #
      # Prism wrapped frozen nodes expose native locations with start/end lines,
      # but Prism::Location does not implement Range#cover?. Use explicit line
      # range checks rather than the FileAnalyzable default.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Boolean]
      def in_freeze_block?(line_num)
        !freeze_block_at(line_num).nil?
      end

      # Return the frozen Prism-owned statement covering the given line.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Ast::Merge::NodeTyping::FrozenWrapper, nil]
      def freeze_block_at(line_num)
        freeze_blocks.find do |block|
          start_line = owner_start_line(block)
          end_line = owner_end_line(block)

          start_line && end_line && (start_line..end_line).cover?(line_num)
        end
      end

      # Get nodes that are frozen (have a freeze marker).
      # Returns FrozenWrapper instances that include the Freezable behavior,
      # allowing them to satisfy both is_a?(Freezable) and is_a?(NodeTyping::Wrapper).
      #
      # @return [Array<Ast::Merge::NodeTyping::FrozenWrapper>] Wrapped frozen nodes
      def frozen_nodes
        # Return the underlying Prism nodes for tests and callers that expect
        # Prism node types. Statements may be wrapped in FrozenWrapper; unwrap
        # them here.
        statements.select { |node| node.is_a?(Ast::Merge::Freezable) }
                  .map { |node| node.respond_to?(:unwrap) ? node.unwrap : node }
      end

      class << self
        # Safely attach comments to nodes, handling JRuby compatibility issues.
        # On JRuby, the Prism::ParseResult::Comments class may not be autoloaded,
        # so we need to explicitly require it.
        #
        # This is a class method so it can be used anywhere in prism-merge code
        # that needs to attach comments to a parse result.
        #
        # @param parse_result [Prism::ParseResult] The parse result to attach comments to
        # @return [void]
        def attach_comments_safely!(parse_result)
          parse_result.attach_comments!
        # simplecov:disable defensive - JRuby compatibility for Comments class autoloading
        rescue NameError => e
          raise unless e.message.include?('Comments')

          # On JRuby, the Comments class needs to be explicitly required
          require 'prism/parse_result/comments'
          parse_result.attach_comments!

          # simplecov:enable
        end
      end

      private

      def comment_augmenter_default_owners
        @comment_augmenter_default_owners ||= statements.select do |stmt|
          owner_start_line(stmt) && owner_end_line(stmt)
        end
      end

      def layout_augmenter_default_owners
        @layout_augmenter_default_owners ||= statements.select do |stmt|
          owner_start_line(stmt) && owner_end_line(stmt)
        end
      end

      def build_layout_augmenter(owners, **options)
        Ast::Merge::Layout::Augmenter.new(
          lines: layout_lines,
          owners: owners,
          start_line_for: method(:owner_start_line),
          end_line_for: method(:owner_end_line),
          metadata: {
            source: :prism_native
          },
          **options
        )
      end

      def layout_lines
        @layout_lines ||= lines.map { |line| line.to_s.chomp }
      end

      def native_comment_entries
        @native_comment_entries ||= if comment_only_file?
                                      comment_entries_from_comment_only_statements
                                    else
                                      # Use the flat, deduplicated list from tree_haver rather than
                                      # re-collecting from node.location.leading_comments (which can
                                      # produce duplicates when a comment is attached to multiple nodes).
                                      # Two exclusions are required to match the scope of the old path:
                                      # 1. Lines claimed by promoted BlockDirective nodes (FreezeNode /
                                      #    NocovNode): those comments live inside synthetic nodes and must
                                      #    not appear as orphan preamble/postlude regions in the augmenter.
                                      # 2. Comments nested inside a top-level statement's body (e.g. coverage
                                      #    directives inside a `task :default do...end` block): those are
                                      #    handled during recursive body merging and must not appear at the
                                      #    file level either.
                                      @tree.comments
                                           .reject { |th_comment| claimed_lines.include?(th_comment.location.start_line) }
                                           .reject { |th_comment| nested_in_top_level_statement?(th_comment.location.start_line) }
                                           .map { |th_comment| native_comment_entry_from_tree(th_comment) }
                                    end
      end

      # Returns true if +line+ falls strictly inside the body of any top-level
      # statement (i.e. start_line < line <= end_line for a multi-line node).
      # Comments that are nested inside a statement body are handled when that
      # body is merged recursively; they must not also appear as file-level
      # orphan regions in NativeCommentAugmenter.
      def nested_in_top_level_statement?(line)
        statements.any? do |stmt|
          start = owner_start_line(stmt)
          stop = owner_end_line(stmt)
          next false unless start && stop && stop > start

          start < line && line <= stop
        end
      end

      def native_comment_entries_in_range(range)
        native_comment_entries.select { |entry| range.cover?(entry[:line]) }
      end

      def build_comment_region(kind, entries, metadata: {})
        return if entries.empty?

        Ast::Merge::Comment::Region.new(
          kind: kind,
          nodes: entries.map { |entry| entry[:node] },
          metadata: {
            source: :prism_native,
            entries: entries
          }.merge(metadata)
        )
      end

      def owner_start_line(owner)
        if owner.respond_to?(:location) && owner.location
          owner.location.start_line
        elsif owner.respond_to?(:start_line)
          owner.start_line
        elsif owner.respond_to?(:line_number)
          owner.line_number
        end
      end

      def owner_end_line(owner)
        if owner.respond_to?(:location) && owner.location
          owner.location.end_line
        elsif owner.respond_to?(:end_line)
          owner.end_line
        elsif owner.respond_to?(:line_number)
          owner.line_number
        end
      end

      def owner_leading_comment_entries(owner)
        native_comments_for(owner, :leading_comments).map do |comment|
          native_comment_entry(comment, attached_as: :leading)
        end
      end

      def split_first_owner_preamble?(owner, leading_entries)
        return false unless owner.equal?(Array(comment_augmenter_default_owners).first)
        return false unless owner_start_line(owner).to_i > 1

        preamble_entries, remaining_entries = split_first_owner_preamble_entries(leading_entries)
        preamble_entries.any? && remaining_entries.any?
      end

      def split_first_owner_preamble_entries(leading_entries)
        full_line_entries = Array(leading_entries).select { |entry| entry[:full_line] }
        groups = group_full_line_entries_for_attachment(full_line_entries)
        return [[], leading_entries] unless groups.length > 1
        return [[], leading_entries] unless groups.first.first[:line] == 1

        preamble_entries = groups.first
        remaining_lines = groups.drop(1).flatten.map { |entry| entry[:line] }
        remaining_entries = Array(leading_entries).reject do |entry|
          preamble_entries.include?(entry)
        end.sort_by { |entry| entry[:line] }
        return [[], leading_entries] if remaining_lines.empty? || remaining_entries.empty?

        [preamble_entries, remaining_entries]
      end

      def group_full_line_entries_for_attachment(entries)
        entries.sort_by { |entry| entry[:line] }.each_with_object([]) do |entry, groups|
          current = groups.last
          if current && contiguous_comment_lines_for_attachment?(current.last[:line], entry[:line])
            current << entry
          else
            groups << [entry]
          end
        end
      end

      def contiguous_comment_lines_for_attachment?(from_line, to_line)
        to_line == from_line + 1
      end

      def owner_inline_comment_entries(owner)
        owner_last_line = owner_end_line(owner)
        native_comments_for(owner, :trailing_comments).filter_map do |comment|
          entry = native_comment_entry(comment, attached_as: :trailing)
          entry if !entry[:full_line] && !(owner_last_line && entry[:line] > owner_last_line)
        end
      end

      def owner_trailing_comment_entries(owner)
        owner_last_line = owner_end_line(owner)
        native_comments_for(owner, :trailing_comments).filter_map do |comment|
          entry = native_comment_entry(comment, attached_as: :trailing)
          entry if entry[:full_line] && owner_last_line && entry[:line] > owner_last_line
        end
      end

      def native_comments_for(owner, kind)
        return [] unless owner.respond_to?(:location) && owner.location.respond_to?(kind)

        Array(owner.location.public_send(kind))
      end

      # Build a comment entry hash from a tree_haver comment (normalized, deduplicated).
      #
      # @param th_comment [TreeHaver::Backends::Prism::Comment] Normalized comment from @tree.comments
      # @return [Hash] Comment entry hash compatible with native_comment_entries consumers
      def native_comment_entry_from_tree(th_comment)
        line = th_comment.location.start_line
        raw = th_comment.text.chomp
        {
          line: line,
          text: raw.sub(/\A\s*#\s?/, ''),
          raw: raw,
          separator: inline_comment_separator_for(line, raw),
          # tree_haver classifies: :leading (full-line before code), :trailing (full-line
          # at end/before more comments), :inline (non-whitespace before #)
          full_line: th_comment.attachment_hint != :inline,
          attached_as: th_comment.attachment_hint,
          node: Prism::Merge::Comment::Line.new(
            text: raw,
            line_number: line,
            magic_comment_type: native_header_magic_comment_types[line]
          )
        }
      end

      # Build a comment entry hash from a raw Prism::Comment (used for per-owner
      # attachment queries via node.location.leading_comments / trailing_comments).
      #
      # @param comment [Prism::Comment] Raw Prism comment
      # @param attached_as [Symbol] :leading or :trailing (from Prism attachment context)
      # @return [Hash] Comment entry hash
      def native_comment_entry(comment, attached_as:)
        line = comment.location.start_line
        raw = comment.slice.chomp
        {
          line: line,
          text: comment.slice.sub(/\A\s*#\s?/, ''),
          raw: raw,
          separator: inline_comment_separator_for(line, raw),
          full_line: full_line_comment?(comment, attached_as: attached_as),
          attached_as: attached_as,
          node: Prism::Merge::Comment::Line.new(
            text: raw,
            line_number: line,
            magic_comment_type: native_header_magic_comment_types[line]
          )
        }
      end

      def comment_entries_from_comment_only_statements
        statements.filter_map do |stmt|
          case stmt
          when Prism::Merge::Comment::Block
            stmt.children.filter_map { |child| comment_entry_from_comment_ast_node(child) }
          when Prism::Merge::Comment::Line
            comment_entry_from_comment_ast_node(stmt)
          end
        end.flatten
      end

      def comment_entry_from_comment_ast_node(node)
        return unless node.is_a?(Prism::Merge::Comment::Line)

        {
          line: node.line_number,
          text: node.content,
          raw: node.text,
          full_line: true,
          attached_as: :comment_only,
          node: node
        }
      end

      def native_header_magic_comment_types
        @native_header_magic_comment_types ||= Prism::Merge::MagicCommentSupport.header_magic_comment_types_for_lines(@lines)
      end

      def full_line_comment?(comment, attached_as:)
        return true if attached_as == :leading

        line = @lines[comment.location.start_line - 1].to_s
        line.lstrip.start_with?('#')
      end

      def inline_comment_separator_for(line_number, raw_comment)
        return if raw_comment.to_s.empty?

        line_text = line_at(line_number).to_s.sub(/\r?\n\z/, '')
        prefix, separator, = line_text.rpartition(raw_comment)
        return unless separator == raw_comment

        prefix[/[ \t]+\z/]
      end

      def comment_only_file?
        statements.any? && statements.all? { |stmt| stmt.is_a?(Ast::Merge::AstNode) }
      end

      # Instance method wrapper for class method
      def attach_comments_safely!
        self.class.attach_comments_safely!(@parse_result)
      end

      # Extract all top-level AST nodes from the parsed source.
      #
      # Freeze semantics: a node is frozen if it has an *unbalanced* freeze marker
      # (`# token:freeze`) in its leading comments — one that is NOT followed by a
      # matching `# token:unfreeze` in the same leading comment block.  A balanced
      # freeze/unfreeze pair in leading comments is treated as a standalone freeze
      # block directive and does NOT cause the subsequent code node to be frozen.
      #
      # Frozen nodes are wrapped in FrozenWrapper to satisfy the Freezable API,
      # enabling them to be detected via is_a?(Freezable) and freeze_node?.
      #
      # Use `frozen_node?` to check if a specific node is frozen.
      #
      # @return [Array<Prism::Node, Ast::Merge::NodeTyping::FrozenWrapper>] Top-level statements
      def extract_and_integrate_all_nodes
        return [] unless valid?

        body = @parse_result.value.statements
        raw_nodes = if body.nil?
                      # simplecov:disable defensive
                      []
                    # simplecov:enable
                    elsif body.type.to_s == 'statements_node'
                      body.body.compact
                    else
                      # simplecov:disable defensive
                      [body].compact
                      # simplecov:enable
                    end

        return Comment::Parser.parse(@lines) if raw_nodes.empty? && @lines.any?

        # Detect block directive spans (freeze and nocov) from raw source lines.
        # Directives are promoted to FreezeNode / NocovNode synthetic nodes.
        # This runs AFTER Prism's attach_comments! to avoid being misled by Prism's
        # leading-comment attachment, which can hoist standalone freeze/unfreeze
        # instruction blocks onto the first code node.
        freeze_tok = @freeze_token.nil? || @freeze_token.empty? ? nil : @freeze_token
        detector = BlockDirectiveDetector.new(
          @lines,
          freeze_token: freeze_tok,
          nocov_token: BlockDirectiveDetector::NOCOV_TOKEN,
          source_label: @source_label
        )
        spans = detector.detect_spans
        promoted = detector.promote_spans_to_nodes(raw_nodes, spans, analysis: self)

        # Build the set of lines claimed by promoted BlockDirective nodes.
        # These lines were hoisted by Prism's attach_comments! onto subsequent
        # code nodes as leading_comments. Excluding them prevents false positives
        # in frozen_node? when the directive is a standalone comment block.
        # The claimed_lines are also exposed for use by the emission pipeline
        # to avoid duplicating those comment lines when emitting adjacent nodes.
        claimed_lines = Set.new
        promoted.each do |node|
          next unless node.is_a?(Ast::Merge::BlockDirective)

          (node.start_line..node.end_line).each { |l| claimed_lines.add(l) }
        end
        @claimed_lines = claimed_lines

        # Wrap any remaining frozen nodes (unbalanced freeze markers) in FrozenWrapper
        promoted.map do |node|
          if !node.is_a?(Ast::Merge::BlockDirective) && frozen_node?(node, claimed_lines: claimed_lines)
            Ast::Merge::NodeTyping::FrozenWrapper.new(node, :frozen)
          else
            node
          end
        end
      end

      # Extract nodes with their comments and metadata.
      #
      # Uses Prism's native comment attachment via node.location.
      #
      # @return [Array<Hash>] Array of node info hashes with keys:
      #   - :node [Prism::Node] The AST node
      #   - :index [Integer] Position in statements array
      #   - :leading_comments [Array<Prism::Comment>] Leading comments
      #   - :inline_comments [Array<Prism::Comment>] Trailing/inline comments
      #   - :signature [Array, nil] Structural signature for matching
      #   - :line_range [Range] Line range covered by the node
      # @api private
      def extract_nodes_with_comments
        return [] unless valid?

        statements.map.with_index do |stmt, idx|
          # Handle custom AST nodes (CommentBlock, CommentLine, EmptyLine)
          if stmt.is_a?(Ast::Merge::AstNode)
            {
              node: stmt,
              index: idx,
              leading_comments: [],
              inline_comments: [],
              signature: stmt.signature,
              line_range: stmt.location.start_line..stmt.location.end_line
            }
          else
            # Unwrap any FrozenWrapper to provide the underlying Prism node as
            # the primary :node value while still using the wrapper for comment
            # attachment (delegation via method_missing preserves location access).
            actual_node = stmt.respond_to?(:unwrap) ? stmt.unwrap : stmt

            {
              node: actual_node,
              index: idx,
              leading_comments: (stmt.location.respond_to?(:leading_comments) ? stmt.location.leading_comments : []),
              inline_comments: (stmt.location.respond_to?(:trailing_comments) ? stmt.location.trailing_comments : []),
              signature: generate_signature(actual_node),
              line_range: stmt.location.start_line..stmt.location.end_line
            }
          end
        end
      end

      # Generate default structural signature for a Prism node.
      #
      # Signatures are used to match nodes between template and destination files.
      # Nodes with identical signatures are considered "the same" for merge purposes.
      #
      # @param node [Prism::Node] Node to generate signature for
      # @return [Array] Signature array with format [:type, identifier, ...]
      #
      # @note Supported node types and their signature formats:
      #
      #   **Method/Class Definitions:**
      #   - `DefNode` → `[:def, name, [param_names]]`
      #   - `ClassNode` → `[:class, constant_path]`
      #   - `ModuleNode` → `[:module, constant_path]`
      #   - `SingletonClassNode` → `[:singleton_class, expression]`
      #
      #   **Constants:**
      #   - `ConstantWriteNode` → `[:const, name]`
      #   - `ConstantPathWriteNode` → `[:const, target]`
      #
      #   **Variable Assignments:**
      #   - `LocalVariableWriteNode` → `[:local_var, name]`
      #   - `InstanceVariableWriteNode` → `[:ivar, name]`
      #   - `ClassVariableWriteNode` → `[:cvar, name]`
      #   - `GlobalVariableWriteNode` → `[:gvar, name]`
      #   - `MultiWriteNode` → `[:multi_write, [target_names]]`
      #
      #   **Conditionals:**
      #   - `IfNode` → `[:if, condition_source]`
      #   - `UnlessNode` → `[:unless, condition_source]`
      #
      #   **Case Statements:**
      #   - `CaseNode` → `[:case, predicate]`
      #   - `CaseMatchNode` → `[:case_match, predicate]`
      #
      #   **Loops:**
      #   - `WhileNode` → `[:while, condition]`
      #   - `UntilNode` → `[:until, condition]`
      #   - `ForNode` → `[:for, index, collection]`
      #
      #   **Exception Handling:**
      #   - `BeginNode` → `[:begin, first_statement_preview]`
      #
      #   **Method Calls:**
      #   - `CallNode` (regular) → `[:call, method_name, first_arg]`
      #   - `CallNode` (assignment, e.g., `x.y = z`) → `[:call, :method=, receiver]`
      #   - `CallNode` (with block) → `[:call_with_block, method_name, first_arg_or_receiver]`
      #
      #   **Super Calls:**
      #   - `SuperNode` → `[:super, :with_block | :no_block]`
      #   - `ForwardingSuperNode` → `[:forwarding_super, :with_block | :no_block]`
      #
      #   **Lambdas:**
      #   - `LambdaNode` → `[:lambda, parameters_source]`
      #
      #   **Special Blocks:**
      #   - `PreExecutionNode` → `[:pre_execution, line_number]`
      #   - `PostExecutionNode` → `[:post_execution, line_number]`
      #
      #   **Other:**
      #   - `ParenthesesNode` → `[:parens, first_expression_preview]`
      #   - `EmbeddedStatementsNode` → `[:embedded, statements_source]`
      #   - Unknown nodes → `[:other, class_name, line_number]`
      #
      # @example Method definition signature
      #   # def greet(name, greeting: "Hello")
      #   compute_node_signature(def_node)
      #   # => [:def, :greet, [:name, :greeting]]
      #
      # @example Assignment method call signature
      #   # config.setting = "value"
      #   compute_node_signature(call_node)
      #   # => [:call, :setting=, "config"]
      #
      # @example Block method call signature
      #   # appraise "ruby-3.3" do ... end
      #   compute_node_signature(call_node)
      #   # => [:call_with_block, :appraise, "ruby-3.3"]
      #
      # @api private
      def compute_node_signature(node)
        # Handle our custom AST nodes (CommentBlock, CommentLine, EmptyLine, etc.)
        # These have their own signature method that returns the appropriate format
        return node.signature if node.is_a?(Ast::Merge::AstNode)

        # BlockDirective nodes (NocovNode, etc.) that are not FreezeNodeBase:
        # call their own #signature method.  NocovNode#signature delegates to the
        # inner content so a NocovNode in the template can match the same bare node
        # in the dest (and vice-versa), preventing duplication on each merge run.
        # FreezeNodeBase is handled earlier in generate_signature via freeze_signature.
        return node.signature if node.is_a?(Ast::Merge::BlockDirective) && !node.is_a?(Ast::Merge::FreezeNodeBase)

        # IMPORTANT: Do NOT call node.signature - Prism nodes have their own signature method
        # that returns [node_type_symbol, source_text] which is not what we want for matching.
        # We need our own signature format: [:type_symbol, identifier, params]
        #
        # Node types with nested content (from Prism) that we may encounter:
        # - BeginNode: statements, rescue_clause, else_clause, ensure_clause
        # - BlockNode: body (handled via parent CallNode)
        # - CallNode: block
        # - CaseMatchNode: else_clause, conditions, consequent
        # - CaseNode: else_clause, conditions, consequent
        # - ClassNode: body
        # - DefNode: body
        # - ElseNode: statements (handled via parent)
        # - EmbeddedStatementsNode: statements
        # - EnsureNode: statements (handled via parent BeginNode)
        # - ForNode: statements
        # - ForwardingSuperNode: block
        # - IfNode: statements, consequent
        # - InNode: statements (handled via parent CaseMatchNode)
        # - IndexAndWriteNode, IndexOperatorWriteNode, IndexOrWriteNode: block
        # - LambdaNode: body
        # - ModuleNode: body
        # - ParenthesesNode: body
        # - PostExecutionNode: statements (END { })
        # - PreExecutionNode: statements (BEGIN { })
        # - ProgramNode: statements (top-level)
        # - RescueNode: statements, consequent (handled via parent BeginNode)
        # - SingletonClassNode: body
        # - StatementsNode: body
        # - SuperNode: block
        # - UnlessNode: statements, else_clause, consequent
        # - UntilNode: statements
        # - WhenNode: statements, conditions (handled via parent CaseNode)
        # - WhileNode: statements

        case NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
        # === Method definitions ===
        when :def
          # Extract parameter names from ParametersNode
          params = if node.parameters
                     # Handle forwarding parameters (def foo(...)) specially
                     if node.parameters.is_a?(Prism::ForwardingParameterNode)
                       # simplecov:disable defensive - current Prism wraps ForwardingParameterNode in ParametersNode
                       [:forwarding]
                       # simplecov:enable
                     else
                       param_names = []
                       param_names.concat(node.parameters.requireds.map(&:name)) if node.parameters.requireds
                       param_names.concat(node.parameters.optionals.map(&:name)) if node.parameters.optionals
                       param_names << node.parameters.rest.name if node.parameters.rest&.respond_to?(:name)
                       param_names.concat(node.parameters.posts.map(&:name)) if node.parameters.posts
                       param_names.concat(node.parameters.keywords.map(&:name)) if node.parameters.keywords
                       # keyword_rest can be KeywordRestParameterNode (has name) or ForwardingParameterNode (no name)
                       if node.parameters.keyword_rest&.respond_to?(:name)
                         param_names << node.parameters.keyword_rest.name
                       elsif node.parameters.keyword_rest.is_a?(Prism::ForwardingParameterNode)
                         param_names << :forwarding
                       end
                       param_names << node.parameters.block.name if node.parameters.block
                       param_names
                     end
                   else
                     []
                   end
          [:def, node.name, params]

        # === Class/Module definitions ===
        when :class
          [:class, node.constant_path.slice]
        when :module
          [:module, node.constant_path.slice]
        when :singleton_class
          # class << self or class << expr
          expr = begin
            node.expression.slice
          rescue StandardError
            'self'
          end
          [:singleton_class, expr]

        # === Constants ===
        when :const
          if node.type.to_s == 'constant_write_node'
            [:const, node.name]
          else
            [:const, node.target.slice]
          end

        # === Variable assignments ===
        when :local_var
          [:local_var, node.name]
        when :ivar
          [:ivar, node.name]
        when :cvar
          [:cvar, node.name]
        when :gvar
          [:gvar, node.name]
        when :multi_write
          # Multiple assignment: a, b = 1, 2
          targets = node.lefts.map do |target|
            case target
            when Prism::LocalVariableTargetNode
              target.name
            when Prism::InstanceVariableTargetNode
              target.name
            when Prism::ClassVariableTargetNode
              target.name
            when Prism::GlobalVariableTargetNode
              target.name
            else
              target.slice
            end
          end
          [:multi_write, targets]

        # === Conditionals ===
        when :if, :unless
          # Conditionals match by their condition expression
          condition_source = node.predicate.slice
          [node.type.to_s == 'if_node' ? :if : :unless, condition_source]

        # === Case/Switch statements ===
        when :case
          # case expr; when ... end - match by the expression being switched on
          predicate = node.predicate&.slice || ''
          [:case, predicate]
        when :case_match
          # case expr; in ... end (pattern matching) - match by the expression
          predicate = node.predicate&.slice || ''
          [:case_match, predicate]

        # === Loops ===
        when :while
          [:while, node.predicate.slice]
        when :until
          [:until, node.predicate.slice]
        when :for
          # for i in collection - match by index and collection
          index = node.index.slice
          collection = node.collection.slice
          [:for, index, collection]

        # === Exception handling ===
        when :begin
          # begin/rescue/ensure blocks - unique by position within parent
          # Since these don't have a natural identifier, use first statement
          first_stmt = node.statements&.body&.first&.slice&.[](0, 30) || ''
          [:begin, first_stmt]

        # === Method calls ===
        when :call
          # Method calls match by name and context
          # For assignment methods (ending in =), match by receiver + method name only
          # For other calls, include first argument as identifier (e.g., appraise "name")
          method_name = node.name.to_s
          receiver = node.receiver&.slice

          if method_name.end_with?('=')
            # Assignment method: config.setting = "value"
            # Match by receiver and method name, NOT the value being assigned.
            #
            # Normalize the gemspec block variable (e.g. |gem| vs |spec|) so that
            # `gem.name = "foo"` and `spec.name = "foo"` produce the same signature.
            # Only applies when the receiver is a plain local variable (not a chained
            # call like `spec.metadata["key"]`) and it matches the detected block param.
            effective_receiver = if @gemspec_block_var &&
                                    receiver == @gemspec_block_var
                                   # Normalise the gemspec block variable so `gem.name =` and `spec.name =`
                                   # produce the same signature.  We rely on the slice comparison alone —
                                   # the guard intentionally does NOT require Prism::LocalVariableReadNode
                                   # because when body text is parsed standalone (no enclosing block), the
                                   # parameter name (`gem`, `spec`, …) is parsed as a zero-arg CallNode by
                                   # Prism, not as a LocalVariableReadNode.  The slice match is sufficient
                                   # because chained receivers (e.g. `spec.metadata`) produce longer slices
                                   # that will never equal the single-word block parameter name.
                                   GEMSPEC_VAR_PLACEHOLDER
                                 else
                                   receiver
                                 end
            if node.block
              # simplecov:disable defensive - Ruby syntax doesn't allow blocks with assignment methods
              [:call_with_block, node.name, effective_receiver]
              # simplecov:enable
            else
              [:call, node.name, effective_receiver]
            end
          else
            # Regular method call: appraise "unlocked" do ... end
            # Match by method name and first argument (which identifies the call)
            first_arg = extract_first_argument_value(node)
            if node.block
              [:call_with_block, node.name, first_arg]
            else
              [:call, node.name, first_arg]
            end
          end

        # === Super calls ===
        when :super
          [:super, node.block ? :with_block : :no_block]
        when :forwarding_super
          [:forwarding_super, node.block ? :with_block : :no_block]

        # === Operator-write calls (e.g. spec.rdoc_options += [...]) ===
        when :call_op_write
          receiver = node.receiver&.slice
          effective_receiver = if @gemspec_block_var && receiver == @gemspec_block_var
                                 GEMSPEC_VAR_PLACEHOLDER
                               else
                                 receiver
                               end
          [:call_op_write, node.write_name, effective_receiver]

        # === Lambdas ===
        when :lambda
          # Lambdas don't have names, but we can identify by parameter signature
          params = if node.parameters
                     node.parameters.slice
                   else
                     ''
                   end
          [:lambda, params]

        # === Special blocks ===
        when :pre_execution
          # BEGIN { } blocks
          [:pre_execution, node.location.start_line]
        when :post_execution
          # END { } blocks
          [:post_execution, node.location.start_line]

        # === Parenthesized expressions ===
        when :parens
          # Usually transparent, but if it appears at top level, identify by content
          first_expr = node.body&.body&.first&.slice&.[](0, 30) || ''
          [:parens, first_expr]

        # === Embedded statements (string interpolation) ===
        when :embedded
          [:embedded, node.statements&.slice || '']

        else
          # Fallback: use class name and line number
          # Nodes that reach here may not merge well across files
          [:other, node.class.name, node.location.start_line]
        end
      end

      # Extract the value of the first argument from a CallNode for signature matching.
      # Returns the unescaped string value for StringNode, or the slice for other node types.
      #
      # @param node [Prism::CallNode] The call node to extract argument from
      # @return [String, nil] The first argument value, or nil if no arguments
      def extract_first_argument_value(node)
        return unless node.arguments&.arguments&.any?

        first_arg = node.arguments.arguments.first
        case first_arg
        when Prism::StringNode
          first_arg.unescaped
        when Prism::SymbolNode
          first_arg.unescaped.to_sym
        else
          first_arg.slice
        end
      end

      # Detect the block parameter name used in `Gem::Specification.new do |X|`.
      #
      # Scans the top-level statements of the parsed source for a CallNode matching
      # `Gem::Specification.new do |X|` and returns the string name of `X` (e.g.
      # `"spec"`, `"gem"`, or `"s"`).  Returns `nil` when no such pattern is found.
      #
      # This value is used by `compute_node_signature` to normalise assignment
      # receivers so that `spec.name = "foo"` and `gem.name = "foo"` produce the
      # same signature regardless of which variable name the gemspec author chose.
      #
      # @return [String, nil]
      def detect_gemspec_block_var
        return unless valid?

        @parse_result.value.statements&.body&.each do |node|
          next unless node.is_a?(Prism::CallNode)
          next unless node.name == :new
          next unless node.receiver.is_a?(Prism::ConstantPathNode)
          next unless node.receiver.slice == 'Gem::Specification'
          next unless node.block.is_a?(Prism::BlockNode)

          bp = node.block.parameters
          next unless bp.is_a?(Prism::BlockParametersNode)

          param = bp.parameters&.requireds&.first
          next unless param.is_a?(Prism::RequiredParameterNode)

          return param.name.to_s
        end

        nil
      end
    end
  end
end
