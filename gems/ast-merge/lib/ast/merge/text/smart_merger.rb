# frozen_string_literal: true

module Ast
  module Merge
    module Text
      # Smart merger for text-based files.
      #
      # Provides intelligent merging of two text files using a simple line-based AST
      # where lines are top-level nodes and words are nested nodes.
      #
      # @example Basic merge (destination customizations preserved)
      #   merger = SmartMerger.new(template_content, dest_content)
      #   result = merger.merge
      #   puts result  # Merged content
      #
      # @example Template wins merge
      #   merger = SmartMerger.new(
      #     template_content,
      #     dest_content,
      #     preference: :template,
      #     add_template_only_nodes: true
      #   )
      #   result = merger.merge
      #   # Template-only lines are emitted in template order relative to
      #   # their matched anchors.
      #
      # @example With freeze blocks
      #   template = <<~TEXT
      #     Line one
      #     Line two
      #   TEXT
      #
      #   dest = <<~TEXT
      #     Line one modified
      #     # text-merge:freeze
      #     Custom content
      #     # text-merge:unfreeze
      #   TEXT
      #
      #   merger = SmartMerger.new(template, dest)
      #   result = merger.merge
      #   # => "Line one modified\n# text-merge:freeze\nCustom content\n# text-merge:unfreeze"
      #
      # @example With regions (embedded code blocks)
      #   merger = SmartMerger.new(
      #     template_content,
      #     dest_content,
      #     regions: [
      #       { detector: FencedCodeBlockDetector.ruby, merger_class: SomeRubyMerger }
      #     ]
      #   )
      class SmartMerger < SmartMergerBase
        # Default freeze token for text merging
        DEFAULT_FREEZE_TOKEN = 'text-merge'

        # Initialize a new SmartMerger
        #
        # @param template_content [String] Template text content
        # @param dest_content [String] Destination text content
        # @param preference [Symbol] :destination or :template
        # @param add_template_only_nodes [Boolean] Whether to add template-only lines
        # @param freeze_token [String] Token for freeze block markers
        # @param signature_generator [Proc, nil] Custom signature generator
        # @param resolution_mode [Symbol] :eager (default) or :unresolved
        # @param regions [Array<Hash>, nil] Region configurations for nested merging
        # @param region_placeholder [String, nil] Custom placeholder for regions
        def initialize(
          template_content,
          dest_content,
          preference: :destination,
          add_template_only_nodes: false,
          freeze_token: DEFAULT_FREEZE_TOKEN,
          signature_generator: nil,
          resolution_mode: :eager,
          unresolved_policy: nil,
          regions: nil,
          region_placeholder: nil
        )
          super(
            template_content,
            dest_content,
            signature_generator: signature_generator,
            preference: preference,
            add_template_only_nodes: add_template_only_nodes,
            freeze_token: freeze_token,
            resolution_mode: resolution_mode,
            unresolved_policy: unresolved_policy,
            regions: regions,
            region_placeholder: region_placeholder,
          )
        end

        # Get merge statistics
        #
        # @return [Hash] Statistics about the merge
        def stats
          merge_result # Ensure merge has run
          {
            template_lines: @template_analysis.statements.count { |s| s.is_a?(LineNode) },
            dest_lines: @dest_analysis.statements.count { |s| s.is_a?(LineNode) },
            result_lines: @result.lines.size,
            decisions: @result.decision_summary
          }
        end

        protected

        # @return [Class] The analysis class for text files
        def analysis_class
          FileAnalysis
        end

        # @return [String] The default freeze token
        def default_freeze_token
          DEFAULT_FREEZE_TOKEN
        end

        # @return [Class] The resolver class for text files
        def resolver_class
          ConflictResolver
        end

        # @return [Class] The result class for text files
        def result_class
          MergeResult
        end

        # Perform the text-specific merge
        #
        # @return [MergeResult] The merge result
        def perform_merge
          @resolver.resolve(@result)
          @result
        end

        # Build the resolver with positional arguments (Text::ConflictResolver signature)
        def build_resolver
          ConflictResolver.new(
            @template_analysis,
            @dest_analysis,
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            resolution_mode: @resolution_mode,
            unresolved_policy: @unresolved_policy
          )
        end
      end
    end
  end
end
