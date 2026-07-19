# frozen_string_literal: true

module Rbs
  module Merge
    # Resolves conflicts between template and destination declarations.
    # Determines which version to use when both files have declarations
    # with matching signatures but different content.
    #
    # @example Basic usage
    #   resolver = ConflictResolver.new(
    #     preference: :destination,
    #     template_analysis: template_analysis,
    #     dest_analysis: dest_analysis
    #   )
    #   winner = resolver.resolve(template_decl, dest_decl)
    class ConflictResolver < ::Ast::Merge::ConflictResolverBase
      include ::Ast::Merge::CommentLayoutEmissionSupport

      # Initialize a conflict resolver
      #
      # @param preference [Symbol, Hash] Which version wins on conflict (:template or :destination)
      #   or per-node-type Hash when used with node_typing
      # @param template_analysis [FileAnalysis] Analysis of the template file
      # @param dest_analysis [FileAnalysis] Analysis of the destination file
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type preferences
      # @param options [Hash] Additional options for forward compatibility
      def initialize(preference:, template_analysis:, dest_analysis:, node_typing: nil, **options)
        super(
          strategy: :node,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          **options
        )
        @node_typing = node_typing
      end

      # Resolve a conflict between template and destination declarations
      #
      # @param template_decl [Object] Template declaration
      # @param dest_decl [Object] Destination declaration
      # @param template_index [Integer] Index in template statements
      # @param dest_index [Integer] Index in destination statements
      # @return [Hash] Resolution result with :source and :declaration keys
      def resolve(template_decl, dest_decl, template_index:, dest_index:)
        # Freeze blocks always win (they represent protected content)
        # Template freeze blocks take precedence - frozen content from template is preserved
        if freeze_node?(template_decl)
          return { source: :template, declaration: template_decl, decision: DECISION_FREEZE_BLOCK }
        end

        # Destination freeze blocks also win (though less common)
        if freeze_node?(dest_decl)
          return { source: :destination, declaration: dest_decl, decision: DECISION_FREEZE_BLOCK }
        end

        # Check if declarations are identical
        if declarations_identical?(template_decl, dest_decl)
          # Prefer destination to minimize diffs
          return { source: :destination, declaration: dest_decl, decision: DECISION_DESTINATION }
        end

        # Check if we should recursively merge (for container types)
        if can_recursive_merge?(template_decl, dest_decl)
          return {
            source: :recursive,
            template_declaration: template_decl,
            dest_declaration: dest_decl,
            decision: DECISION_RECURSIVE
          }
        end

        # Apply preference (supports per-node-type preferences with node_typing)
        case resolve_preference(template_decl, dest_decl)
        when :template
          { source: :template, declaration: template_decl, decision: DECISION_TEMPLATE }
        else # :destination (validated in initialize)
          { source: :destination, declaration: dest_decl, decision: DECISION_DESTINATION }
        end
      end

      # Check if two declarations are identical
      # @param decl1 [Object] First declaration
      # @param decl2 [Object] Second declaration
      # @return [Boolean]
      def declarations_identical?(decl1, decl2)
        # Compare text content for backend-agnostic comparison
        text1 = extract_declaration_text(decl1, @template_analysis)
        text2 = extract_declaration_text(decl2, @dest_analysis)

        # Normalize whitespace for comparison
        normalize_text(text1) == normalize_text(text2) &&
          leading_gap_line_count_for(decl1, @template_analysis) == leading_gap_line_count_for(decl2, @dest_analysis)
      end

      # Check if declarations can be recursively merged
      # @param template_decl [Object] Template declaration
      # @param dest_decl [Object] Destination declaration
      # @return [Boolean]
      def can_recursive_merge?(template_decl, dest_decl)
        # Only container types can be recursively merged
        # Container types are: class, module, interface

        template_type = canonical_type(template_decl)
        dest_type = canonical_type(dest_decl)

        # Both must be the same container type
        return false unless template_type == dest_type
        return false unless NodeTypeNormalizer.container_type?(template_type)

        # At least one side must have members so recursive merging can preserve
        # destination-only or template-only nested members inside the matched shell.
        has_members?(template_decl) || has_members?(dest_decl)
      end

      private

      # Resolve preference for a matched declaration pair.
      #
      # @param template_decl [Object] Template declaration
      # @param dest_decl [Object] Destination declaration
      # @return [Symbol] :template or :destination
      def resolve_preference(template_decl, dest_decl)
        return @preference unless @preference.is_a?(Hash)

        typed_template = apply_node_typing(template_decl)
        typed_dest = apply_node_typing(dest_decl)

        if Ast::Merge::NodeTyping.typed_node?(typed_template)
          merge_type = Ast::Merge::NodeTyping.merge_type_for(typed_template)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        if Ast::Merge::NodeTyping.typed_node?(typed_dest)
          merge_type = Ast::Merge::NodeTyping.merge_type_for(typed_dest)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        default_preference
      end

      # Apply node typing to a declaration if configured.
      #
      # @param decl [Object] Declaration
      # @return [Object] Possibly typed declaration
      def apply_node_typing(decl)
        return decl unless @node_typing
        return decl unless decl

        Ast::Merge::NodeTyping.process(decl, @node_typing)
      end

      # Extract text content from a declaration
      # @param decl [Object] Declaration
      # @param analysis [FileAnalysis] Analysis for line extraction
      # @return [String]
      def extract_declaration_text(decl, analysis)
        start_line = get_decl_start_line(decl)
        end_line = get_decl_end_line(decl)
        return '' unless start_line && end_line

        lines = []

        leading_region = leading_region_for(decl, analysis)
        if region_present?(leading_region)
          region_start = region_start_line(leading_region)
          if region_start && region_start < start_line
            lines.concat((region_start...start_line).filter_map { |ln| analysis.line_at(ln) })
          end
        elsif native_comment_fallback_applicable?(decl, analysis)
          comment_start = decl.comment.location&.start_line
          if comment_start && comment_start < start_line
            lines.concat((comment_start...start_line).filter_map { |ln| analysis.line_at(ln) })
          end
        end

        lines.concat((start_line..end_line).map { |ln| analysis.line_at(ln) })
        lines.join("\n")
      end

      def native_comment_fallback_applicable?(decl, _analysis)
        decl.respond_to?(:comment) && decl.comment
      end

      def leading_gap_line_count_for(decl, analysis)
        leading_region = leading_region_for(decl, analysis)
        return 0 unless region_present?(leading_region)

        region_start = region_start_line(leading_region)
        start_line = get_decl_start_line(decl)
        return 0 unless region_start && start_line && region_start < start_line

        blank_line_count_before(region_start, analysis)
      end
      # Get start line for a declaration (works with both backends)
      def get_decl_start_line(decl)
        if decl.respond_to?(:start_line)
          decl.start_line
        elsif decl.respond_to?(:location) && decl.location
          decl.location.start_line
        elsif decl.respond_to?(:start_point) && decl.start_point
          decl.start_point.row + 1
        end
      end

      # Get end line for a declaration (works with both backends)
      def get_decl_end_line(decl)
        if decl.respond_to?(:end_line)
          decl.end_line
        elsif decl.respond_to?(:location) && decl.location
          decl.location.end_line
        elsif decl.respond_to?(:end_point) && decl.end_point
          decl.end_point.row + 1
        end
      end

      # Normalize text for comparison (remove trailing whitespace, normalize line endings)
      def normalize_text(text)
        text.to_s.lines.map(&:rstrip).join("\n").strip
      end

      # Get canonical type for a declaration (works with both backends)
      # @param decl [Object] Declaration (NodeWrapper, TreeHaver::Node, or RBS::AST::*)
      # @return [Symbol]
      def canonical_type(decl)
        if decl.is_a?(NodeWrapper)
          decl.canonical_type
        elsif decl.respond_to?(:type) && decl.type.respond_to?(:to_sym)
          # TreeHaver::Node - get type and normalize
          NodeTypeNormalizer.canonical_type(decl.type, :tree_sitter)
        elsif decl.respond_to?(:class) && decl.class.name.to_s.include?('RBS::AST')
          # RBS gem node - map class name to canonical type
          NodeTypeNormalizer.canonical_type(decl.class.name, :rbs)
        else
          :unknown
        end
      end

      # Check if declaration has members (works with both backends)
      # @param decl [Object] Declaration
      # @return [Boolean]
      def has_members?(decl)
        if decl.is_a?(NodeWrapper)
          decl.members.any?
        elsif decl.respond_to?(:members)
          # RBS gem nodes have members method
          decl.members.any?
        elsif decl.respond_to?(:each)
          # TreeHaver::Node - check for members container child
          decl.each do |child|
            child_type = child.respond_to?(:type) ? child.type.to_s : ''
            return true if %w[members interface_members].include?(child_type)
          end
          false
        else
          false
        end
      end
    end
  end
end
