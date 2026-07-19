# frozen_string_literal: true

require_relative 'unresolved_support'

module Ast
  module Merge
    # Abstract base class for SmartMerger implementations across all *-merge gems.
    #
    # SmartMergerBase provides the standard interface and common functionality
    # for intelligent file merging. Subclasses implement format-specific parsing,
    # analysis, and merge logic while inheriting the common API.
    #
    # ## Standard Options
    #
    # All SmartMerger implementations support these common options:
    #
    # - `preference` - `:destination` (default) or `:template`, or Hash for per-type
    # - `add_template_only_nodes` - `false` (default) or `true`
    # - `signature_generator` - Custom signature proc or `nil`
    # - `freeze_token` - Token for freeze block markers
    # - `match_refiner` - Fuzzy match refiner or `nil`
    # - `regions` - Region configurations for nested merging
    # - `region_placeholder` - Custom placeholder for regions
    # - `node_typing` - Hash mapping node types to callables for per-type preferences
    #
    # ## Implementing a SmartMerger
    #
    # Subclasses must implement:
    # - `analysis_class` - Returns the FileAnalysis class for this format
    # - `perform_merge` - Performs the format-specific merge logic
    #
    # Subclasses may override:
    # - `default_freeze_token` - Format-specific default freeze token
    # - `resolver_class` - Returns the ConflictResolver class (if different)
    # - `result_class` - Returns the MergeResult class (if different)
    # - `aligner_class` - Returns the FileAligner class (if used)
    # - `parse_content` - Custom parsing logic
    # - `build_analysis_options` - Additional analysis options
    # - `build_resolver_options` - Additional resolver options
    #
    # ## FileAnalysis Error Handling Pattern
    #
    # All FileAnalysis classes must follow this consistent error handling pattern:
    #
    # 1. **Catch backend errors internally** - Handle `TreeHaver::NotAvailable` and
    #    similar backend errors inside the FileAnalysis class, storing them in `@errors`
    #    and setting `@ast = nil`. Do NOT re-raise these errors.
    #
    # 2. **Collect parse errors without raising** - When the parser detects syntax errors
    #    (e.g., `has_error?` returns true), collect them in `@errors` but do NOT raise.
    #
    # 3. **Implement `valid?`** - Return `false` when there are errors or no AST:
    #    ```ruby
    #    def valid?
    #      @errors.empty? && !@ast.nil?
    #    end
    #    ```
    #
    # 4. **SmartMergerBase handles the rest** - After FileAnalysis creation,
    #    `parse_and_analyze` checks `valid?` and raises the appropriate parse error
    #    (TemplateParseError or DestinationParseError) if the analysis is invalid.
    #
    # This pattern ensures:
    # - Consistent error handling across all *-merge gems
    # - TreeHaver::NotAvailable (which inherits from Exception) is handled safely
    # - Parse errors are properly wrapped in format-specific error classes
    # - No need to rescue Exception in SmartMergerBase
    #
    # @example FileAnalysis error handling
    #   def parse_content
    #     parser = TreeHaver.parser_for(:myformat, backend_type: :tree_sitter)
    #     @ast = parser.parse(@source)
    #
    #     if @ast&.root_node&.has_error?
    #       collect_parse_errors(@ast.root_node)
    #       # Do NOT raise here - SmartMergerBase will check valid?
    #     end
    #   rescue TreeHaver::NotAvailable => e
    #     @errors << e.message
    #     @ast = nil
    #     # Do NOT re-raise - SmartMergerBase will check valid?
    #   rescue StandardError => e
    #     @errors << e
    #     @ast = nil
    #     # Do NOT re-raise - SmartMergerBase will check valid?
    #   end
    #
    # @example Implementing a custom SmartMerger
    #   class MyFormat::SmartMerger < Ast::Merge::SmartMergerBase
    #     def analysis_class
    #       MyFormat::FileAnalysis
    #     end
    #
    #     def default_freeze_token
    #       "myformat-merge"
    #     end
    #
    #     private
    #
    #     def perform_merge
    #       alignment = @aligner.align
    #       process_alignment(alignment)
    #       @result
    #     end
    #   end
    #
    # @abstract Subclass and implement {#analysis_class} and {#perform_merge}
    # @api public
    class SmartMergerBase
      include Detector::Mergeable
      include UnresolvedSupport

      # @return [String] Template source content
      attr_reader :template_content

      # @return [String] Destination source content
      attr_reader :dest_content

      # @return [Object] Analysis of the template file
      attr_reader :template_analysis

      # @return [Object] Analysis of the destination file
      attr_reader :dest_analysis

      # @return [Object, nil] Aligner for finding matches (if applicable)
      attr_reader :aligner

      # @return [Object] Resolver for handling conflicts
      attr_reader :resolver

      # @return [Object] Result object tracking merged content
      attr_reader :result

      # @return [Symbol, Hash] Preference for signature matches
      attr_reader :preference

      # @return [Boolean] Whether to add template-only nodes
      attr_reader :add_template_only_nodes

      # @return [String] Token for freeze block markers
      attr_reader :freeze_token

      # @return [Proc, nil] Custom signature generator
      attr_reader :signature_generator

      # @return [Object, nil] Match refiner for fuzzy matching
      attr_reader :match_refiner

      # @return [Hash{Symbol,String => #call}, nil] Node typing configuration
      attr_reader :node_typing

      # @return [Symbol] How matching differences should be surfaced
      attr_reader :resolution_mode
      # @return [Ast::Merge::UnresolvedPolicy] Caller-facing unresolved review policy.
      attr_reader :unresolved_policy

      # Creates a new SmartMerger for intelligent file merging.
      #
      # @param template_content [String] Template source content
      # @param dest_content [String] Destination source content
      #
      # @param signature_generator [Proc, nil] Optional proc to generate custom signatures.
      #   The proc receives a node and should return one of:
      #   - An array representing the node's signature
      #   - `nil` to indicate the node should have no signature
      #   - The original node to fall through to default signature computation
      #
      # @param preference [Symbol, Hash] Controls which version to use
      #   when nodes have matching signatures but different content:
      #   - `:destination` (default) - Use destination version (preserves customizations)
      #   - `:template` - Use template version (applies updates)
      #   - Hash for per-type preferences: `{ default: :destination, special: :template }`
      #
      # @param add_template_only_nodes [Boolean] Controls whether to add nodes that only
      #   exist in template:
      #   - `false` (default) - Skip template-only nodes
      #   - `true` - Add template-only nodes to result
      #
      # @param freeze_token [String, nil] Token to use for freeze block markers.
      #   Default varies by format (e.g., "prism-merge", "markly-merge")
      #
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching.
      #   Default: nil (fuzzy matching disabled)
      #
      # @param regions [Array<Hash>, nil] Region configurations for nested merging.
      #   Each hash should contain:
      #   - `:detector` - RegionDetectorBase instance
      #   - `:merger_class` - SmartMerger class for the region (optional)
      #   - `:merger_options` - Options for the region merger (optional)
      #   - `:regions` - Nested region configs (optional, for recursive regions)
      #
      # @param region_placeholder [String, nil] Custom placeholder prefix for regions.
      #   Default: "<<<AST_MERGE_REGION_"
      #
      # @param format_options [Hash] Format-specific parser options passed to FileAnalysis.
      #   These are merged with freeze_token and signature_generator in build_full_analysis_options.
      #   Examples:
      #   - Markly: `flags: Markly::FOOTNOTES, extensions: [:table, :strikethrough]`
      #   - Commonmarker: `options: { parse: { smart: true } }`
      #   - Prism: (no additional parser options needed)
      #
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences. Maps node type names to callables that
      #   can wrap nodes with custom merge_types for use with Hash-based preference.
      #   @example
      #     node_typing = {
      #       CallNode: ->(node) {
      #         NodeTyping.with_merge_type(node, :special) if special_node?(node)
      #       }
      #     }
      #
      # @raise [Ast::Merge::TemplateParseError] If template has syntax errors
      # @raise [Ast::Merge::DestinationParseError] If destination has syntax errors
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        freeze_token: nil,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        node_typing: nil,
        resolution_mode: :eager,
        unresolved_policy: nil,
        template_path: nil,
        dest_path: nil,
        **format_options
      )
        @template_content = template_content
        @dest_content = dest_content
        @signature_generator = signature_generator
        @preference = preference
        @add_template_only_nodes = add_template_only_nodes
        @freeze_token = freeze_token || default_freeze_token
        @match_refiner = match_refiner
        @node_typing = node_typing
        @resolution_mode = resolution_mode
        @unresolved_policy = Ast::Merge::UnresolvedPolicy.coerce(unresolved_policy)
        @template_path = template_path
        @dest_path = dest_path
        @format_options = format_options

        # Validate node_typing if provided
        NodeTyping.validate!(node_typing) if node_typing
        validate_resolution_mode!(resolution_mode)

        # Set up region support
        setup_regions(regions: regions || [], region_placeholder: region_placeholder)

        # Extract regions before parsing (if configured)
        template_for_parsing = extract_template_regions(@template_content)
        dest_for_parsing = extract_dest_regions(@dest_content)

        # Parse and analyze both files
        @template_analysis = parse_and_analyze(template_for_parsing, :template)
        @dest_analysis = parse_and_analyze(dest_for_parsing, :destination)

        # Set up aligner (if applicable)
        @aligner = build_aligner if respond_to?(:aligner_class, true) && aligner_class

        # Set up resolver
        @resolver = build_resolver

        # Set up result
        @result = build_result
      end

      # Perform the merge operation and return the merged content as a string.
      #
      # @return [String] The merged content
      def merge
        merge_result.to_s
      end

      # Perform the merge operation and return the full result object.
      #
      # This method is memoized - subsequent calls return the cached result.
      #
      # @return [Object] The merge result (format-specific MergeResult subclass)
      def merge_result
        return @merge_result if @merge_result

        @merge_result = DebugLogger.time("#{self.class.name}#merge") do
          result = perform_merge

          # Substitute merged regions back into the result if configured
          if regions_configured? && (merged_content = result.to_s)
            final_content = substitute_merged_regions(merged_content)
            update_result_content(result, final_content)
          end

          result
        end
      end

      # Perform the merge and return detailed debug information.
      #
      # @return [Hash] Hash containing:
      #   - `:content` [String] - Final merged content
      #   - `:statistics` [Hash] - Merge decision counts
      def merge_with_debug
        content = merge

        {
          content: content,
          statistics: @result.decision_summary
        }
      end

      # Get merge statistics.
      #
      # @return [Hash] Statistics about the merge
      def stats
        merge_result # Ensure merge has run
        @result.decision_summary
      end

      protected

      # Returns the FileAnalysis class for this format.
      #
      # @return [Class] The analysis class
      # @abstract Subclasses must implement this method
      def analysis_class
        raise NotImplementedError, "#{self.class}#analysis_class must be implemented"
      end

      # Returns the default freeze token for this format.
      #
      # @return [String] The default freeze token (e.g., "prism-merge")
      def default_freeze_token
        'ast-merge'
      end

      # Returns the ConflictResolver class for this format.
      #
      # Override if your format uses a custom resolver.
      #
      # @return [Class, nil] The resolver class, or nil to skip resolver creation
      def resolver_class
        nil
      end

      # Returns the MergeResult class for this format.
      #
      # Override if your format uses a custom result class.
      #
      # @return [Class, nil] The result class, or nil to skip result creation
      def result_class
        nil
      end

      # Returns the FileAligner class for this format.
      #
      # Override if your format uses an aligner.
      #
      # @return [Class, nil] The aligner class, or nil if not used
      def aligner_class
        nil
      end

      # Performs the format-specific merge logic.
      #
      # This method should use @template_analysis, @dest_analysis, @resolver, etc.
      # to perform the merge and populate @result.
      #
      # @return [Object] The merge result (typically @result)
      # @abstract Subclasses must implement this method
      def perform_merge
        raise NotImplementedError, "#{self.class}#perform_merge must be implemented"
      end

      # Build additional options for FileAnalysis.
      #
      # Override to add format-specific options.
      #
      # @return [Hash] Additional options for the analysis class
      def build_analysis_options
        {}
      end

      # Build additional options for ConflictResolver.
      #
      # Override to add format-specific options.
      #
      # @return [Hash] Additional options for the resolver class
      def build_resolver_options
        {}
      end

      # Update the result content after region substitution.
      #
      # Override if your result class needs special handling.
      #
      # @param result [Object] The merge result
      # @param content [String] The final content with regions substituted
      def update_result_content(result, content)
        result.content = content
      end

      private

      def validate_resolution_mode!(resolution_mode)
        return if MergerConfig::VALID_RESOLUTION_MODES.include?(resolution_mode)

        raise ArgumentError,
              "Invalid resolution_mode: #{resolution_mode.inspect}. " \
                "Must be one of: #{MergerConfig::VALID_RESOLUTION_MODES.map(&:inspect).join(', ')}"
      end

      # Parse and analyze content, raising appropriate errors.
      #
      # Error handling:
      # - All FileAnalysis classes handle TreeHaver::NotAvailable internally,
      #   storing the error and setting valid? to false
      # - The validity check catches silent failures (grammar not available, parse errors)
      # - StandardError from FileAnalysis initialization is wrapped in parse error
      #
      # @param content [String] Content to parse
      # @param source [Symbol] :template or :destination
      # @return [Object] The analysis result
      def parse_and_analyze(content, source)
        options = build_full_analysis_options
        # Always label with dest_path — unbalanced directives corrupt the
        # destination regardless of which side introduced them.
        options[:source_label] = @dest_path if @dest_path

        analysis = DebugLogger.time("#{self.class.name}#analyze_#{source}") do
          analysis_class.new(content, **options)
        end

        # Check if the analysis is valid - if not, raise a parse error
        # This catches cases where parsing fails silently (e.g., grammar not available)
        if analysis.respond_to?(:valid?) && !analysis.valid?
          error_class = source == :template ? template_parse_error_class : destination_parse_error_class
          errors = analysis.respond_to?(:errors) ? analysis.errors : []
          raise error_class.new(errors: errors, content: content)
        end

        analysis
      rescue StandardError => e
        # Don't re-wrap our own parse errors
        raise if e.is_a?(template_parse_error_class) || e.is_a?(destination_parse_error_class)

        # Wrap the error in our parse error class
        error_class = source == :template ? template_parse_error_class : destination_parse_error_class
        raise error_class.new(errors: [e], content: content)
      end

      # Returns the TemplateParseError class for this merger.
      # Override in subclasses to use format-specific error classes.
      #
      # @return [Class] The template parse error class
      def template_parse_error_class
        TemplateParseError
      end

      # Returns the DestinationParseError class for this merger.
      # Override in subclasses to use format-specific error classes.
      #
      # @return [Class] The destination parse error class
      def destination_parse_error_class
        DestinationParseError
      end

      # Build the complete options hash for FileAnalysis.
      #
      # Override this method to completely control what options are passed.
      # By default, includes freeze_token, signature_generator, and format_options.
      #
      # @return [Hash] Options for the analysis class
      def build_full_analysis_options
        {
          freeze_token: @freeze_token,
          signature_generator: @signature_generator
        }.merge(build_analysis_options).merge(@format_options)
      end

      # Build the aligner instance.
      #
      # Override if your aligner has a different constructor signature.
      #
      # @return [Object] The aligner instance
      def build_aligner
        aligner_class.new(@template_analysis, @dest_analysis, match_refiner: @match_refiner)
      end

      # Build the resolver instance.
      #
      # Override if your resolver has a different constructor signature.
      #
      # @return [Object, nil] The resolver instance
      def build_resolver
        return unless resolver_class

        options = {
          preference: @preference,
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
          add_template_only_nodes: @add_template_only_nodes,
          match_refiner: @match_refiner
        }.merge(build_resolver_options)

        resolver_class.new(**options)
      end

      # Build the result instance.
      #
      # Override if your result class has a different constructor signature.
      #
      # @return [Object, nil] The result instance
      def build_result
        return unless result_class

        if result_class.instance_method(:initialize).arity == 0
          result_class.new
        else
          result_class.new(
            template_analysis: @template_analysis,
            dest_analysis: @dest_analysis
          )
        end
      end
    end
  end
end
