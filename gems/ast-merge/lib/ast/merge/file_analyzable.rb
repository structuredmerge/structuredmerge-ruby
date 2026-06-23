# frozen_string_literal: true

module Ast
  module Merge
    # Mixin module for file analysis classes across all *-merge gems.
    #
    # This module provides common functionality for analyzing source files,
    # including freeze block detection, line access, and signature generation.
    # Include this module in your FileAnalysis class and implement the required
    # abstract methods.
    #
    # @example Including in a FileAnalysis class
    #   class FileAnalysis
    #     include Ast::Merge::FileAnalyzable
    #
    #     def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil)
    #       @source = source
    #       @lines = source.split("\n", -1)
    #       @freeze_token = freeze_token
    #       @signature_generator = signature_generator
    #       @statements = parse_and_extract_statements
    #     end
    #
    #     # Required: implement this method for parser-specific signature logic
    #     def compute_node_signature(node)
    #       # Return signature array or nil
    #     end
    #
    #     # Required: implement if using generate_signature with custom node type detection
    #     def fallthrough_node?(node)
    #       node.is_a?(MyParser::Node) || node.is_a?(FreezeNodeBase)
    #     end
    #   end
    #
    # @abstract Include this module and implement {#compute_node_signature} and optionally {#fallthrough_node?}
    module FileAnalyzable
      # Common attributes shared by all FileAnalysis classes.
      # These attr_reader declarations provide consistent interface across all merge gems.
      # Including classes should set these instance variables in their initialize method.
      #
      # @!attribute [r] source
      #   @return [String] Original source content
      # @!attribute [r] lines
      #   @return [Array<String>] Lines of source code (may be specialized in subclasses)
      # @!attribute [r] freeze_token
      #   @return [String] Token used to mark freeze blocks (e.g., "prism-merge", "psych-merge")
      # @!attribute [r] signature_generator
      #   @return [Proc, nil] Custom signature generator, or nil to use default
      class << self
        # Install the shared attr_reader interface on including analyses.
        #
        # @param base [Class] analysis class receiving the shared readers
        # @return [void]
        def included(base)
          base.class_eval do
            attr_reader(:source, :lines, :freeze_token, :signature_generator)
          end
        end
      end

      # Get all top-level statements (nodes and freeze blocks).
      # Override this method in including classes to return the appropriate collection.
      # The default implementation returns @statements if set, otherwise an empty array.
      #
      # @return [Array] All top-level statements
      def statements
        @statements ||= []
      end

      # Get all freeze blocks/nodes from statements.
      # Includes both traditional FreezeNodeBase blocks and Freezable-wrapped nodes.
      #
      # @return [Array<Freezable>] All freeze nodes
      def freeze_blocks
        statements.select { |node| node.is_a?(Freezable) }
      end

      # Check if a line is within a freeze block.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Boolean] true if line is inside a freeze block
      def in_freeze_block?(line_num)
        freeze_blocks.any? { |fb| fb.location.cover?(line_num) }
      end

      # Get the freeze block containing the given line, if any.
      #
      # @param line_num [Integer] 1-based line number
      # @return [FreezeNodeBase, nil] Freeze block node or nil
      def freeze_block_at(line_num)
        freeze_blocks.find { |fb| fb.location.cover?(line_num) }
      end

      # Get structural signature for a statement at given index.
      #
      # @param index [Integer] Statement index (0-based)
      # @return [Array, nil] Signature array or nil if index out of bounds
      def signature_at(index)
        return if index < 0 || index >= statements.length

        generate_signature(statements[index])
      end

      # Get a specific line (1-indexed).
      #
      # @param line_num [Integer] Line number (1-indexed)
      # @return [String, nil] The line content or nil if out of bounds
      def line_at(line_num)
        return if line_num < 1

        lines[line_num - 1]
      end

      # Get a normalized line (whitespace-trimmed, for comparison).
      #
      # @param line_num [Integer] Line number (1-indexed)
      # @return [String, nil] Normalized line content or nil if out of bounds
      def normalized_line(line_num)
        line = line_at(line_num)
        line&.strip
      end

      # Describe the level of comment support available from this analysis.
      #
      # Analyses with native or augmented comment support should override this.
      # The default implementation advertises no comment support while still
      # providing the shared hook surface used by merge gems.
      #
      # @return [Comment::Capability]
      def comment_capability
        Comment::Capability.none(source: :file_analyzable_default)
      end

      # Return all shared comment nodes known to this analysis.
      #
      # @return [Array<Ast::Merge::Comment::Line>]
      def comment_nodes
        []
      end

      # Describe how the merge pipeline will own and emit comments for this
      # analysis.
      #
      # Analyses with comment support should override this to advertise their
      # intended read/write model independently from raw parser capability.
      #
      # @return [Comment::SupportStyle]
      def comment_support_style
        capability = comment_capability
        details = {
          source: :file_analyzable_default,
          capability: capability.level
        }

        if capability.none?
          Comment::SupportStyle.unavailable(**details)
        elsif capability.source_augmented?
          Ruleset::SupportStyleResolver.call(
            read: :source_augmented_portable_write,
            source: details[:source],
            capability: details[:capability],
            style: details[:style]
          )
        else
          Ruleset::SupportStyleResolver.call(
            read: :native_read_portable_write,
            source: details[:source],
            capability: details[:capability],
            style: details[:style]
          )
        end
      end

      # Build a shared support-style declaration for analyses that already know
      # their read/write model.
      #
      # @param source [Symbol] support-style source identifier
      # @param style [Symbol] comment syntax family
      # @param read_strategy [Symbol] support-style read/write strategy
      # @param capability [Symbol] advertised capability level
      # @return [Comment::SupportStyle]
      def shared_comment_support_style(source:, style:, read_strategy:, capability: comment_capability.level)
        details = {
          source: source,
          capability: capability,
          style: style
        }

        Ruleset::SupportStyleResolver.call(read: read_strategy, **details)
      rescue ArgumentError => e
        raise unless e.message.start_with?('Unknown ruleset read strategy:')

        raise ArgumentError, "Unknown comment support read strategy: #{read_strategy.inspect}"
      end

      # Describe the current analysis using spec-aligned merge feature terms.
      #
      # Analyses can override the individual `ruleset_*` hooks below to make this
      # surface more specific without replacing the whole profile object.
      #
      # @return [Ruleset::FeatureProfile]
      def feature_profile
        Ruleset::FeatureProfile.new(
          owner_selector: ruleset_owner_selector,
          match_key: ruleset_match_key,
          read_strategy: ruleset_read_strategy,
          attachment_strategy: ruleset_attachment_strategy,
          comment_style: ruleset_comment_style,
          render_family: ruleset_render_family,
          comment_capability: comment_capability,
          support_style: comment_support_style,
          capabilities: ruleset_capabilities,
          logical_owners: ruleset_logical_owners,
          repair_policies: ruleset_repair_policies,
          surfaces: ruleset_surfaces,
          delegation_policies: ruleset_delegation_policies,
          metadata: { source: :file_analyzable_default }
        )
      end

      def ruleset_owner_selector
        :shared_default
      end

      def ruleset_match_key
        :signature
      end

      def ruleset_read_strategy
        support_style = comment_support_style
        return unless support_style.respond_to?(:available?) && support_style.available?

        support_style.style
      end

      def ruleset_attachment_strategy
        comment_attachment_strategy
      end

      def ruleset_comment_style
        comment_support_style.details[:style] || comment_capability.details[:style]
      end

      def ruleset_render_family
        nil
      end

      def ruleset_capabilities
        {
          layout_aware: true,
          logical_owner: ruleset_logical_owners.any?
        }
      end

      def ruleset_logical_owners
        {}
      end

      def ruleset_repair_policies
        []
      end

      def ruleset_surfaces
        []
      end

      def ruleset_delegation_policies
        []
      end

      # Return the shared comment node at a specific line.
      #
      # @param _line_num [Integer] 1-based line number
      # @return [Ast::Merge::Comment::Line, nil]
      def comment_node_at(_line_num)
        nil
      end

      # Return a shared comment region spanning a requested line range.
      #
      # Analyses with comment support should override this to return attached or
      # tracked comment content. The default implementation returns an empty
      # region of the requested kind so callers can rely on the hook surface.
      #
      # @param range [Range] 1-based line range
      # @param kind [Symbol] region ownership kind
      # @param options [Hash] region metadata
      # @return [Comment::Region]
      def comment_region_for_range(range, kind:, **options)
        Comment::Region.new(
          kind: kind,
          nodes: [],
          metadata: {
            source: :file_analyzable_default,
            range: range
          }.merge(options)
        )
      end

      # Return a passive shared attachment for a structural owner.
      #
      # Analyses with comment ownership data should override this to return
      # meaningful leading/inline/trailing regions. The default implementation
      # returns an empty attachment so callers can migrate incrementally.
      #
      # @param owner [Object] structural owner
      # @param options [Hash] attachment metadata
      # @return [Comment::Attachment]
      def comment_attachment_for(owner, **options)
        layout_attachment = layout_owner_supported?(owner) ? layout_attachment_for(owner, **options) : nil

        Comment::Attachment.new(
          owner: owner,
          leading_gap: layout_attachment&.leading_gap,
          trailing_gap: layout_attachment&.trailing_gap,
          metadata: {
            source: :file_analyzable_default
          }.merge(options)
        )
      end

      # Describe the shared attachment strategy used by this analysis.
      #
      # Analyses that rely on one of the common tracked/augmented attachment
      # shapes can override this and delegate `comment_attachment_for` through
      # {#shared_comment_attachment_for} instead of open-coding the merge path.
      #
      # @return [Symbol]
      def comment_attachment_strategy
        :layout_only
      end

      # Build a comment attachment through one of the shared runtime strategies.
      #
      # This surfaces the current repeated runtime seam explicitly so
      # format-specific analyses can declare which ownership path they use while
      # still preserving any custom tracker attachment selection they need.
      #
      # @param owner [Object] structural owner
      # @param tracker_attachment [Comment::Attachment, nil] tracker-built or custom base attachment
      # @param strategy [Symbol] attachment strategy override
      # @param options [Hash] attachment metadata
      # @return [Comment::Attachment]
      def shared_comment_attachment_for(owner, tracker_attachment: nil, strategy: comment_attachment_strategy,
                                        **options)
        case strategy
        when :layout_only
          merge_comment_attachment_with_layout(owner, nil, **options)
        when :tracker_layout_merge
          merge_comment_attachment_with_layout(owner, tracker_attachment, **options)
        when :augmenter_preferred_tracker_layout
          merge_augmented_comment_attachment_with_layout(owner, tracker_attachment: tracker_attachment, **options)
        when :normalize_tracked_layout_merge
          normalize_tracked_comment_attachment_with_layout(owner, tracker_attachment: tracker_attachment, **options)
        else
          raise ArgumentError, "Unknown comment attachment strategy: #{strategy.inspect}"
        end
      end

      # Merge a format-specific comment attachment with shared inferred layout gaps.
      #
      # This lets analyses keep custom comment-region logic while still exposing
      # the shared gap ownership model through the returned comment attachment.
      #
      # @param owner [Object] structural owner
      # @param comment_attachment [Comment::Attachment, nil] existing comment attachment
      # @param options [Hash] attachment metadata
      # @return [Comment::Attachment]
      def merge_comment_attachment_with_layout(owner, comment_attachment, **options)
        layout_attachment = layout_owner_supported?(owner) ? layout_attachment_for(owner, **options) : nil

        Comment::Attachment.new(
          owner: comment_attachment&.owner || owner,
          leading_region: comment_attachment&.leading_region,
          inline_region: comment_attachment&.inline_region,
          trailing_region: comment_attachment&.trailing_region,
          orphan_regions: comment_attachment&.orphan_regions || [],
          leading_gap: layout_attachment&.leading_gap,
          trailing_gap: layout_attachment&.trailing_gap,
          metadata: (comment_attachment&.metadata || {}).merge(options)
        )
      end

      # Prefer an augmenter-built attachment when available, then merge the
      # result with shared layout ownership data.
      #
      # This lets analyses use richer augmenter ownership (for example floating
      # leading regions) while preserving tracker-based fallback behavior.
      #
      # @param owner [Object] structural owner
      # @param tracker_attachment [Comment::Attachment, nil] tracker-built fallback
      # @param options [Hash] attachment metadata
      # @return [Comment::Attachment]
      def merge_augmented_comment_attachment_with_layout(owner, tracker_attachment:, **options)
        augmenter_attachment = comment_augmenter(owners: [owner]).attachment_for(owner)

        merge_comment_attachment_with_layout(
          owner,
          augmenter_attachment || tracker_attachment,
          **options
        )
      end

      # Merge a tracker-built attachment with shared layout ownership and then
      # normalize any layout-owned leading region metadata.
      #
      # @param owner [Object] structural owner
      # @param tracker_attachment [Comment::Attachment, nil] tracker-built attachment
      # @param options [Hash] attachment metadata
      # @return [Comment::Attachment]
      def normalize_tracked_comment_attachment_with_layout(owner, tracker_attachment:, **options)
        normalize_layout_owned_comment_attachment(
          merge_comment_attachment_with_layout(
            owner,
            tracker_attachment,
            **options
          )
        )
      end

      # Mark a leading region as floating when shared layout already proves it is
      # gap-owned, without changing the underlying region content.
      #
      # Some format analyzers still build attachments from tracker-level comment
      # regions that do not set `floating: true` even though the shared layout
      # augmenter has already established a leading gap. This helper preserves the
      # attachment shape while normalizing that metadata in one place.
      #
      # @param attachment [Comment::Attachment, nil]
      # @return [Comment::Attachment, nil]
      def normalize_layout_owned_comment_attachment(attachment)
        return attachment unless attachment&.leading_region
        return attachment if attachment.leading_region.floating?
        return attachment unless attachment.leading_gap

        Comment::Attachment.new(
          owner: attachment.owner,
          leading_region: Comment::Region.new(
            kind: attachment.leading_region.kind,
            nodes: attachment.leading_region.nodes,
            metadata: attachment.leading_region.metadata.merge(floating: true)
          ),
          inline_region: attachment.inline_region,
          trailing_region: attachment.trailing_region,
          orphan_regions: attachment.orphan_regions,
          leading_gap: attachment.leading_gap,
          trailing_gap: attachment.trailing_gap,
          metadata: attachment.metadata
        )
      end

      # Build a passive shared comment augmenter for the current analysis.
      #
      # Format-specific analyses should override this when they can provide
      # native or tracked comment data. The default implementation preserves the
      # shared augmenter interface while reporting the analysis capability.
      #
      # @param owners [Array<#start_line,#end_line>, nil] owners for attachment inference
      # @param options [Hash] augmenter metadata
      # @return [Comment::Augmenter]
      def comment_augmenter(owners: nil, **options)
        Comment::Augmenter.new(
          lines: lines,
          comments: [],
          owners: owners || comment_augmenter_default_owners,
          capability: comment_capability,
          **options
        )
      end

      # Return a passive shared layout attachment for a structural owner.
      #
      # Analyses with explicit blank-line ownership data should override this to
      # return meaningful leading/trailing gap attachments. The default
      # implementation returns an empty attachment so callers can migrate
      # incrementally.
      #
      # @param owner [Object] structural owner
      # @param options [Hash] attachment metadata
      # @return [Layout::Attachment]
      def layout_attachment_for(owner, **options)
        owners = layout_augmenter_default_owners
        augmenter = if owners.any? { |candidate| candidate.equal?(owner) }
                      layout_augmenter(**options)
                    else
                      layout_augmenter(owners: [owner], **options)
                    end

        inferred_attachment = augmenter.attachment_for(owner)

        Layout::Attachment.new(
          owner: owner,
          leading_gap: inferred_attachment&.leading_gap,
          trailing_gap: inferred_attachment&.trailing_gap,
          metadata: {
            source: :file_analyzable_default
          }.merge(options)
        )
      end

      # Build a passive shared layout augmenter for the current analysis.
      #
      # Format-specific analyses should override this when they can provide a
      # stronger ownership model for blank-line gaps. The default implementation
      # preserves the shared hook surface while inferring only directly adjacent
      # blank-line runs from source lines and owner ranges.
      #
      # @param owners [Array<#start_line,#end_line>, nil] owners for gap inference
      # @param options [Hash] augmenter metadata
      # @return [Layout::Augmenter]
      def layout_augmenter(owners: nil, **options)
        Layout::Augmenter.new(
          lines: lines,
          owners: owners || layout_augmenter_default_owners,
          **options
        )
      end

      def layout_owner_supported?(owner)
        owner&.respond_to?(:start_line) &&
          owner.respond_to?(:end_line) &&
          !owner.start_line.nil? &&
          !owner.end_line.nil?
      end

      # Check whether an owner's leading normalized comment attachment contains a freeze directive.
      #
      # @param owner [Object] structural owner
      # @param freeze_token [String, nil] token to detect (defaults to this analysis token)
      # @param options [Hash] attachment metadata
      # @return [Boolean]
      def owner_leading_comment_freeze?(owner, freeze_token: self.freeze_token, **options)
        attachment = comment_attachment_for(owner, **options)
        attachment.respond_to?(:leading_freeze?) && attachment.leading_freeze?(freeze_token)
      end

      # Check whether an owner's leading normalized comment attachment contains an unfreeze directive.
      #
      # @param owner [Object] structural owner
      # @param freeze_token [String, nil] token to detect (defaults to this analysis token)
      # @param options [Hash] attachment metadata
      # @return [Boolean]
      def owner_leading_comment_unfreeze?(owner, freeze_token: self.freeze_token, **options)
        attachment = comment_attachment_for(owner, **options)
        attachment.respond_to?(:leading_unfreeze?) && attachment.leading_unfreeze?(freeze_token)
      end

      # Generate signature for a node.
      #
      # Signatures are used to match nodes between template and destination files.
      # Two nodes with the same signature are considered "the same" for merge purposes,
      # allowing the merger to decide which version to keep based on preference settings.
      #
      # ## Signature Generation Flow
      #
      # 1. **FreezeNodeBase** (explicit freeze blocks like `# token:freeze ... # token:unfreeze`):
      #    Uses content-based signature via `freeze_signature`. This ensures explicit freeze
      #    blocks match between files based on their actual content.
      #
      # 2. **FrozenWrapper** (AST nodes with freeze markers in leading comments):
      #    The wrapper is **unwrapped first** to get the underlying AST node. The signature
      #    is then generated from the underlying node, NOT the wrapper. This is critical
      #    because the freeze marker only affects merge *preference* (destination wins),
      #    not *matching*. Two nodes should match by their structural identity even if
      #    their content differs slightly.
      #
      # 3. **Custom signature_generator**: If provided, receives the unwrapped node and can:
      #    - Return an Array signature (e.g., `[:gem, "foo"]`) - used directly
      #    - Return `nil` - node gets no signature, won't be matched
      #    - Return the node (fallthrough) - default signature computation is used
      #
      # 4. **Default computation**: Falls through to `compute_node_signature` for
      #    parser-specific default signature generation.
      #
      # ## Why FrozenWrapper Must Be Unwrapped
      #
      # Consider a gemspec with a frozen `gem_version` variable:
      #
      #   Template:                         Destination:
      #   # kettle-dev:freeze               # kettle-dev:freeze
      #   # Comment                         # Comment
      #   # kettle-dev:unfreeze             # More comments
      #   gem_version = "1.0"               # kettle-dev:unfreeze
      #                                     gem_version = "1.0"
      #
      # Both have a `gem_version` assignment with a freeze marker in leading comments.
      # The assignments are wrapped in FrozenWrapper, but their CONTENT differs
      # (template has fewer comments in the freeze block).
      #
      # If we generated signatures from the wrapper (which delegates `slice` to the
      # full node content), they would NOT match and both would be output - duplicating
      # the freeze block!
      #
      # By unwrapping first, we generate signatures from the underlying
      # `LocalVariableWriteNode`, which matches by variable name (`gem_version`),
      # ensuring only ONE version is output (the destination version, since it's frozen).
      #
      # @param node [Object] Node to generate signature for (may be wrapped)
      # @return [Array, nil] Signature array or nil
      #
      # @example Custom generator with fallthrough
      #   signature_generator = ->(node) {
      #     case node
      #     when MyParser::SpecialNode
      #       [:special, node.name]
      #     else
      #       node  # Return original node for default signature computation
      #     end
      #   }
      #
      # @see FreezeNodeBase#freeze_signature
      # @see NodeTyping::FrozenWrapper
      # @see Freezable
      def generate_signature(node)
        # ==========================================================================
        # CASE 1: FreezeNodeBase (explicit freeze blocks)
        # ==========================================================================
        # FreezeNodeBase represents an explicit freeze block delimited by markers:
        #   # token:freeze
        #   ... content ...
        #   # token:unfreeze
        #
        # These are standalone structural elements (not attached to AST nodes).
        # They use content-based signatures so identical freeze blocks match.
        # This is different from FrozenWrapper which wraps AST nodes.
        return node.freeze_signature if node.is_a?(FreezeNodeBase)

        # ==========================================================================
        # CASE 2: Unwrap FrozenWrapper (and other wrappers)
        # ==========================================================================
        # FrozenWrapper wraps AST nodes that have freeze markers in their leading
        # comments. The wrapper marks the node as "frozen" (prefer destination),
        # but for MATCHING purposes, we need the underlying node's identity.
        #
        # Example: A `gem_version = ...` assignment wrapped in FrozenWrapper should
        # match another `gem_version = ...` assignment by variable name, not by
        # the full content of the assignment (which may differ).
        #
        # CRITICAL: We must unwrap BEFORE calling the signature_generator so it
        # receives the actual AST node type (e.g., Prism::LocalVariableWriteNode)
        # rather than the wrapper (FrozenWrapper). Otherwise, type-based signature
        # generators (like kettle-jem's gemspec generator) won't recognize the node
        # and will fall through to default handling incorrectly.
        actual_node = node.respond_to?(:unwrap) ? node.unwrap : node

        result = if signature_generator
                   # ==========================================================================
                   # CASE 3: Custom signature generator
                   # ==========================================================================
                   # Pass the UNWRAPPED node to the custom generator. This ensures:
                   # - Type checks work (e.g., `node.is_a?(Prism::CallNode)`)
                   # - The generator sees the real AST structure
                   # - Frozen nodes match by their underlying identity
                   #
                   # NOTE: For TreeHaver-based backends, the node already has a unified API
                   # with #text, #type, #source_position methods. For other backends, they
                   # must conform to the same API (either via TreeHaver or equivalent adapter).
                   custom_result = signature_generator.call(actual_node)
                   case custom_result
                   when Array, nil
                     # Generator returned a final signature or nil - use as-is
                     custom_result
                   else
                     # Generator returned a node (fallthrough) - compute default signature.
                     #
                     # Two conditions indicate the generator is deferring to default handling:
                     # 1. Identity equality: the generator returned the exact same object it
                     #    received (classic "I don't handle this type" passthrough pattern).
                     # 2. Known node type: the result is a recognised wrapper/node class.
                     #
                     # If neither applies, treat the return value as a final custom signature
                     # (e.g. a String, Symbol, or other non-node key).
                     if custom_result.equal?(actual_node) || fallthrough_node?(custom_result)
                       # Special case: if fallthrough result is Freezable, use freeze_signature
                       # This handles cases where the generator wraps a node in Freezable
                       if custom_result.is_a?(Freezable)
                         custom_result.freeze_signature
                       else
                         # Unwrap any wrapper and compute default signature
                         unwrapped = custom_result.respond_to?(:unwrap) ? custom_result.unwrap : custom_result
                         compute_node_signature(unwrapped)
                       end
                     else
                       # Non-node return value - pass through (allows arbitrary signature types)
                       custom_result
                     end
                   end
                 else
                   # ==========================================================================
                   # CASE 4: No custom generator - use default computation
                   # ==========================================================================
                   # Pass the UNWRAPPED node to compute_node_signature. This is critical
                   # because compute_node_signature uses type checking (e.g., case statements
                   # matching Prism::DefNode, Prism::CallNode, etc.). If we pass a
                   # FrozenWrapper, it won't match any of those types and will fall through
                   # to a generic handler, producing incorrect signatures.
                   #
                   # For FrozenWrapper nodes, the underlying AST node determines the signature
                   # (e.g., method name for DefNode, gem name for CallNode). The wrapper only
                   # affects merge preference (destination wins), not matching.
                   compute_node_signature(actual_node)
                 end

        if result
          DebugLogger.debug('Generated signature', {
                              node_type: node.class.name.split('::').last,
                              signature: result,
                              generator: signature_generator ? 'custom' : 'default'
                            })
        end

        result
      end

      # Check if a value represents a fallthrough node that should be used for
      # default signature computation.
      #
      # When a signature_generator returns a non-Array/nil value, we check if it's
      # a "fallthrough" node that should be passed to compute_node_signature.
      # This includes:
      # - AstNode instances (custom AST nodes like Comment::Line)
      # - Freezable nodes (frozen wrappers)
      # - FreezeNodeBase instances
      # - NodeTyping::Wrapper instances (unwrapped to get the underlying node)
      #
      # Override this method to add custom node type detection for your parser.
      #
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        value.is_a?(AstNode) ||
          value.is_a?(Freezable) ||
          value.is_a?(FreezeNodeBase) ||
          value.is_a?(NodeTyping::Wrapper) ||
          value.is_a?(BlockDirective)
      end

      # Compute default signature for a node.
      # This method must be implemented by including classes.
      #
      # @param node [Object] The node to compute signature for
      # @return [Array, nil] Signature array or nil
      # @abstract
      def compute_node_signature(node)
        raise NotImplementedError, "#{self.class} must implement #compute_node_signature"
      end

      private

      def comment_augmenter_default_owners
        statements.select { |statement| statement.respond_to?(:start_line) && statement.respond_to?(:end_line) }
      end

      def layout_augmenter_default_owners
        statements.select { |statement| statement.respond_to?(:start_line) && statement.respond_to?(:end_line) }
      end
    end
  end
end
