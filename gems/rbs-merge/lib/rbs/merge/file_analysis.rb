# frozen_string_literal: true

module Rbs
  module Merge
    # File analysis for RBS type signature files.
    # Supports multiple backends: RBS gem (MRI only) and tree-sitter-rbs (cross-platform).
    #
    # This class provides the foundation for intelligent merging by:
    # - Parsing RBS files using TreeHaver's backend system
    # - Extracting top-level declarations (classes, modules, interfaces, type aliases, constants)
    # - Detecting freeze blocks marked with comment directives
    # - Generating signatures for matching declarations between files
    #
    # @example Basic usage (auto-selects backend)
    #   analysis = FileAnalysis.new(rbs_source)
    #   analysis.statements.each do |stmt|
    #     puts stmt.canonical_type
    #   end
    #
    # @example With custom freeze token
    #   analysis = FileAnalysis.new(source, freeze_token: "my-merge")
    #   # Looks for: # my-merge:freeze / # my-merge:unfreeze
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      # Default freeze token for identifying freeze blocks
      # @return [String]
      DEFAULT_FREEZE_TOKEN = 'rbs-merge'

      # @return [TreeHaver::Tree, nil] Parsed AST (for tree-sitter backend)
      attr_reader :ast

      # @return [Array] Parse errors if any
      attr_reader :errors

      # @return [Symbol] The backend used for parsing (:rbs or :tree_sitter)
      attr_reader :backend

      # @return [Array] RBS directives (for RBS gem backend only)
      attr_reader :directives

      # @return [Array] Raw declarations from parser
      attr_reader :declarations

      # @return [CommentTracker] Comment tracker for this file
      attr_reader :comment_tracker

      # Initialize file analysis
      #
      # @param source [String] RBS source code to analyze
      # @param freeze_token [String] Token for freeze block markers (default: "rbs-merge")
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param options [Hash] Additional options
      #
      # @note Backend selection is handled by TreeHaver. To force a specific backend:
      #   - Use TreeHaver.with_backend(:mri) { ... } for tree-sitter via MRI
      #   - Use TreeHaver.with_backend(:rbs) { ... } for RBS gem (MRI only)
      #   - Set TREE_HAVER_BACKEND=rbs or TREE_HAVER_BACKEND=mri env var
      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil, **_options)
        @source = source
        @lines = source.split("\n", -1)
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @errors = []
        @backend = nil # Will be set during parsing
        @directives = []
        @declarations = []
        @ast = nil
        @comment_tracker = CommentTracker.new(@lines, freeze_token: freeze_token)

        # Parse the RBS source
        DebugLogger.time('FileAnalysis#parse') { parse_rbs }

        # Extract and integrate all nodes including freeze blocks
        @statements = integrate_nodes

        DebugLogger.debug('FileAnalysis initialized', {
                            signature_generator: signature_generator ? 'custom' : 'default',
                            backend: @backend,
                            declarations_count: @declarations.size,
                            statements_count: @statements.size,
                            freeze_blocks: freeze_blocks.size,
                            valid: valid?
                          })
      end

      # Check if parse was successful
      # @return [Boolean]
      def valid?
        return false unless @errors.empty?

        !@ast.nil? || @declarations.any?
      end

      # Get shared comment capability information for this analysis.
      #
      # @return [Object]
      def comment_capability
        @comment_capability ||= comment_tracker.augment(owners: []).capability
      end

      # Describe how RBS merges currently own and emit comments.
      #
      # RBS comment tracking is source-augmented and emitted through the shared
      # synthetic merge layer rather than via editable parser-native comment AST.
      #
      # @return [Ast::Merge::Comment::SupportStyle]
      def comment_support_style
        @comment_support_style ||= shared_comment_support_style(
          source: :rbs_source,
          style: :hash_comment,
          read_strategy: :source_augmented_portable_write
        )
      end

      # Get all tracked comments converted to shared comment nodes.
      #
      # @return [Array]
      def comment_nodes
        comment_tracker.comment_nodes
      end

      # Get a shared comment node at a specific line.
      #
      # @param line_num [Integer] 1-based line number
      # @return [Object, nil]
      def comment_node_at(line_num)
        comment_tracker.comment_node_at(line_num)
      end

      # Get comments in a line range converted to a shared comment region.
      #
      # @param range [Range] Range of 1-based line numbers
      # @param kind [Symbol] Region kind
      # @param full_line_only [Boolean] Whether to keep only full-line comments
      # @return [Object]
      def comment_region_for_range(range, kind:, full_line_only: false)
        comment_tracker.comment_region_for_range(
          range,
          kind: kind,
          full_line_only: full_line_only
        )
      end

      # Build a passive shared comment attachment for an owner.
      #
      # @param owner [Object] Structural owner for the attachment
      # @param options [Hash] Additional metadata / lookup overrides
      # @return [Object]
      def comment_attachment_for(owner, **options)
        augmented_attachment = comment_augmenter(**options).attachment_for(owner)

        shared_comment_attachment_for(
          owner,
          tracker_attachment: augmented_attachment || comment_tracker.comment_attachment_for(owner, **options),
          **options
        )
      end

      # @return [Symbol]
      def comment_attachment_strategy
        :normalize_tracked_layout_merge
      end

      def ruleset_owner_selector
        :rbs_declarations
      end

      def ruleset_render_family
        :rbs_declarations
      end

      # Build a passive shared comment augmenter for this analysis.
      #
      # @param owners [Array<#start_line,#end_line>, nil] Owners used for attachment inference
      # @param options [Hash] Additional augmenter options
      # @return [Object]
      def comment_augmenter(owners: nil, **options)
        comment_tracker.augment(
          owners: owners || comment_augmenter_default_owners,
          **options
        )
      end

      # Get all statements (declarations outside freeze blocks + FreezeNodes)
      # @return [Array<NodeWrapper, FreezeNode>]
      attr_reader :statements

      # Get the root node of the parse tree
      # @return [NodeWrapper, nil]
      def root_node
        return unless valid?

        if @backend == :rbs
          # For RBS gem, create a synthetic document wrapper
          nil # RBS gem doesn't have a single root node
        else
          root = @ast.root_node
          NodeWrapper.new(
            root,
            lines: @lines,
            source: @source,
            backend: @backend
          )
        end
      end

      # Compute default signature for a node
      # @param node [Object] The declaration, NodeWrapper, or FreezeNode
      # @return [Array, nil] Signature array
      def compute_node_signature(node)
        return if node.nil?

        case node
        when FreezeNode
          node.signature
        when NodeWrapper
          node.signature
        else
          # Raw declarations/members from the RBS gem frequently respond to #type
          # as part of their own AST API, so backend selection must stay authoritative
          # here. Otherwise frozen contained RBS declarations are misrouted through the
          # tree-sitter signature path and become unmatchable.
          if @backend == :tree_sitter && node.respond_to?(:type)
            compute_tree_sitter_signature(node)
          else
            compute_rbs_gem_signature(node)
          end
        end
      end

      # Compute signature for a tree-sitter node
      # @param node [Object] TreeHaver::Node
      # @return [Array, nil] Signature array
      def compute_tree_sitter_signature(node)
        node_type = node.respond_to?(:type) ? node.type.to_s : nil
        return unless node_type

        canonical = NodeTypeNormalizer.canonical_type(node_type, :tree_sitter)
        name = extract_tree_sitter_node_name(node)

        case canonical
        when :class
          [:class, name || 'anonymous']
        when :module
          [:module, name || 'anonymous']
        when :interface
          [:interface, name || 'anonymous']
        when :type_alias
          [:type_alias, name || 'anonymous']
        when :constant
          [:constant, name || 'anonymous']
        when :global
          [:global, name || 'anonymous']
        when :class_alias
          [:class_alias, name || 'anonymous']
        when :module_alias
          [:module_alias, name || 'anonymous']
        when :method
          [:method, name || 'anonymous']
        else
          [canonical, name || node_type]
        end
      end

      # Extract name from a tree-sitter node
      # @param node [Object] TreeHaver::Node
      # @return [String, nil]
      def extract_tree_sitter_node_name(node)
        return unless node.respond_to?(:each)

        name_node_types = %w[
          class_name
          module_name
          interface_name
          const_name
          global_name
          alias_name
          method_name
        ]

        node.each do |child|
          child_type = child.respond_to?(:type) ? child.type.to_s : ''
          next unless name_node_types.include?(child_type)

          # Name nodes often have a constant or identifier child
          if child.respond_to?(:each)
            child.each do |inner|
              inner_type = inner.respond_to?(:type) ? inner.type.to_s : ''
              if %w[constant identifier].include?(inner_type)
                return inner.respond_to?(:text) ? inner.text : nil
              end
            end
          end
          # If no inner constant/identifier, try the name node itself
          return child.respond_to?(:text) ? child.text : nil
        end

        nil
      end

      # Override to detect RBS nodes for signature generator fallthrough
      # @param value [Object] The value to check
      # @return [Boolean] true if this is a fallthrough node
      def fallthrough_node?(value)
        return true if value.is_a?(NodeWrapper)
        return true if value.is_a?(FreezeNode)

        # Check for RBS gem AST types (when rbs gem is loaded)
        if @backend == :rbs && defined?(::RBS::AST)
          return true if value.is_a?(::RBS::AST::Declarations::Base)
          return true if value.is_a?(::RBS::AST::Members::Base)
        end

        super
      end

      private

      def parse_rbs
        # Use TreeHaver to get the appropriate parser
        # TreeHaver handles backend selection automatically for the current
        # sibling-development environment and respects explicit backend overrides.
        parser = TreeHaver.parser_for(:rbs)
        result = parser.parse(@source)

        # Determine which backend was used based on the result type
        if result.is_a?(Backends::RbsBackend::Tree)
          process_rbs_gem_result(result)
        else
          process_tree_sitter_result(result)
        end
      rescue TreeHaver::NotAvailable => e
        @errors << "No RBS parser available: #{e.message}"
        @ast = nil
      rescue TreeHaver::Error => e
        @errors << e.message
        @ast = nil
      rescue StandardError => e
        @errors << e.message
        @ast = nil
      end

      # Process result from RBS gem backend
      def process_rbs_gem_result(result)
        @backend = :rbs
        @ast = result
        @declarations = result.declarations
        @directives = result.directives

        return unless result.has_errors?

        result.errors.each { |e| @errors << e.message }
      end

      # Process result from tree-sitter backend
      def process_tree_sitter_result(result)
        @backend = :tree_sitter
        @ast = result

        # Check for parse errors in the tree
        collect_parse_errors(@ast.root_node) if @ast&.root_node&.has_error?
        validate_tree_sitter_document

        # Extract declarations from AST
        extract_tree_sitter_declarations
      end

      def validate_tree_sitter_document
        return unless @ast&.root_node

        @ast.root_node.each do |child|
          child_type = child.type.to_s
          next if %w[comment decl use_directive].include?(child_type)

          canonical = NodeTypeNormalizer.canonical_type(child_type, :tree_sitter)
          next if NodeTypeNormalizer.declaration_type?(canonical)

          @errors << {
            type: child_type,
            start_point: child.start_point,
            end_point: child.end_point,
            message: 'RBS merge requires document syntax; inline RBS syntax is unsupported'
          }
        end
      end

      def collect_parse_errors(node)
        if node.type.to_s == 'ERROR' || node.missing?
          @errors << {
            type: node.type.to_s,
            start_point: node.start_point,
            end_point: node.end_point
          }
        end

        node.each { |child| collect_parse_errors(child) }
      end

      def extract_tree_sitter_declarations
        return unless @ast&.root_node

        @declarations = []
        root = @ast.root_node

        # tree-sitter-rbs structure: program -> decl -> *_decl (class_decl, etc.)
        # We want to collect the actual declaration nodes (class_decl, module_decl, etc.)
        # not the wrapper `decl` nodes
        root.each do |child|
          child_type = child.type.to_s

          # Skip non-declaration nodes
          next if %w[comment].include?(child_type)

          if child_type == 'decl'
            # The `decl` node wraps the actual declaration
            # Extract the inner declaration (class_decl, module_decl, etc.)
            child.each do |inner|
              inner_type = inner.type.to_s
              # Skip keywords and punctuation
              next if %w[end class module interface type def].include?(inner_type)

              canonical = NodeTypeNormalizer.canonical_type(inner.type, :tree_sitter)
              if %i[class module interface type_alias constant global class_alias module_alias].include?(canonical)
                @declarations << inner
                break # Only one actual declaration per `decl` wrapper
              end
            end
          else
            # Direct declaration (shouldn't happen based on grammar, but handle it)
            canonical = NodeTypeNormalizer.canonical_type(child.type, :tree_sitter)
            if %i[class module interface type_alias constant global class_alias module_alias].include?(canonical)
              @declarations << child
            end
          end
        end
      end

      def integrate_nodes
        return [] unless valid?

        # Find freeze markers and build freeze blocks
        freeze_markers = find_freeze_markers
        freeze_block_nodes = freeze_markers.empty? ? [] : build_freeze_blocks(freeze_markers)

        # Wrap declarations in NodeWrapper
        wrapped_declarations = wrap_declarations

        # If no freeze blocks, return all declarations
        return wrapped_declarations if freeze_block_nodes.empty?

        # Integrate declarations with freeze blocks
        integrate_nodes_with_freeze_blocks(wrapped_declarations, freeze_block_nodes)
      end

      def wrap_declarations
        @declarations.map do |decl|
          NodeWrapper.new(
            decl,
            lines: @lines,
            source: @source,
            backend: @backend
          )
        end
      end

      # Find all freeze markers in the source
      # @return [Array<Hash>] Array of marker info hashes
      def find_freeze_markers
        markers = []
        pattern = Ast::Merge::FreezeNodeBase.pattern_for(:hash_comment, @freeze_token)

        @lines.each_with_index do |line, idx|
          line_num = idx + 1
          next unless (match = line.match(pattern))

          marker_type = match[1]&.downcase
          if marker_type == 'freeze'
            markers << { type: :start, line: line_num, text: line }
          elsif marker_type == 'unfreeze'
            markers << { type: :end, line: line_num, text: line }
          end
        end

        markers
      end

      # Build freeze blocks from paired markers
      # @param markers [Array<Hash>] Freeze markers
      # @return [Array<FreezeNode>] Freeze block nodes
      def build_freeze_blocks(markers)
        blocks = []
        stack = []

        markers.each do |marker|
          case marker[:type]
          when :start
            stack.push(marker)
          when :end
            if stack.any?
              start_marker = stack.pop
              contained_nodes = find_contained_nodes(start_marker[:line], marker[:line])
              overlapping_nodes = find_overlapping_nodes(start_marker[:line], marker[:line])

              blocks << FreezeNode.new(
                start_line: start_marker[:line],
                end_line: marker[:line],
                analysis: self,
                nodes: contained_nodes,
                overlapping_nodes: overlapping_nodes,
                start_marker: start_marker[:text],
                end_marker: marker[:text]
              )
            else
              DebugLogger.warning("Unmatched freeze end marker at line #{marker[:line]}")
            end
          end
        end

        stack.each do |unmatched|
          DebugLogger.warning("Unmatched freeze start marker at line #{unmatched[:line]}")
        end

        blocks
      end

      # Find declarations fully contained within a range
      def find_contained_nodes(start_line, end_line)
        @declarations.select do |decl|
          decl_start = node_start_line(decl)
          decl_end = node_end_line(decl)
          decl_start && decl_end && decl_start >= start_line && decl_end <= end_line
        end
      end

      # Find declarations that overlap with a range
      def find_overlapping_nodes(start_line, end_line)
        @declarations.select do |decl|
          decl_start = node_start_line(decl)
          decl_end = node_end_line(decl)
          next false unless decl_start && decl_end

          !(decl_end < start_line || decl_start > end_line)
        end
      end

      # Get start line for a node (handles both backends)
      def node_start_line(node)
        # Prefer direct start_line method (TreeHaver::Node has this)
        if node.respond_to?(:start_line)
          node.start_line
        elsif node.respond_to?(:location) && node.location
          node.location.start_line
        elsif node.respond_to?(:start_point)
          pos = node.start_point
          if pos.respond_to?(:row)
            pos.row + 1
          elsif pos.is_a?(Hash)
            pos[:row] + 1
          end
        end
      end

      # Get end line for a node (handles both backends)
      def node_end_line(node)
        # Prefer direct end_line method (TreeHaver::Node has this)
        if node.respond_to?(:end_line)
          node.end_line
        elsif node.respond_to?(:location) && node.location
          node.location.end_line
        elsif node.respond_to?(:end_point)
          pos = node.end_point
          if pos.respond_to?(:row)
            pos.row + 1
          elsif pos.is_a?(Hash)
            pos[:row] + 1
          end
        end
      end

      # Integrate declarations with freeze blocks, avoiding duplicates
      def integrate_nodes_with_freeze_blocks(declarations, freeze_blocks)
        frozen_decl_lines = freeze_blocks.flat_map do |fb|
          fb.nodes.map { |n| node_start_line(n) }
        end.compact.to_set

        # Filter out frozen declarations
        result = declarations.reject do |wrapper|
          frozen_decl_lines.include?(wrapper.start_line)
        end

        result.concat(freeze_blocks)

        # Sort by start line
        result.sort_by { |node| node.start_line || 0 }
      end

      # Compute signature for an RBS gem node
      def compute_rbs_gem_signature(node)
        return unless @backend == :rbs && defined?(::RBS::AST)

        case node
        when ::RBS::AST::Declarations::Class
          [:class, node.name.to_s]
        when ::RBS::AST::Declarations::Module
          [:module, node.name.to_s]
        when ::RBS::AST::Declarations::Interface
          [:interface, node.name.to_s]
        when ::RBS::AST::Declarations::TypeAlias
          [:type_alias, node.name.to_s]
        when ::RBS::AST::Declarations::Constant
          [:constant, node.name.to_s]
        when ::RBS::AST::Declarations::Global
          [:global, node.name.to_s]
        when ::RBS::AST::Declarations::ClassAlias
          [:class_alias, node.new_name.to_s]
        when ::RBS::AST::Declarations::ModuleAlias
          [:module_alias, node.new_name.to_s]
        when ::RBS::AST::Members::MethodDefinition
          [:method, node.name.to_s, node.kind]
        when ::RBS::AST::Members::Alias
          [:alias, node.new_name.to_s, node.old_name.to_s]
        when ::RBS::AST::Members::AttrReader
          [:attr_reader, node.name.to_s]
        when ::RBS::AST::Members::AttrWriter
          [:attr_writer, node.name.to_s]
        when ::RBS::AST::Members::AttrAccessor
          [:attr_accessor, node.name.to_s]
        when ::RBS::AST::Members::Include
          [:include, node.name.to_s]
        when ::RBS::AST::Members::Extend
          [:extend, node.name.to_s]
        when ::RBS::AST::Members::Prepend
          [:prepend, node.name.to_s]
        when ::RBS::AST::Members::InstanceVariable
          [:ivar, node.name.to_s]
        when ::RBS::AST::Members::ClassInstanceVariable
          [:civar, node.name.to_s]
        when ::RBS::AST::Members::ClassVariable
          [:cvar, node.name.to_s]
        else
          [:unknown, node.class.name, node.location&.start_line]
        end
      end
    end
  end
end
