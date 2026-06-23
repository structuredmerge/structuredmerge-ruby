# frozen_string_literal: true

module Markly
  module Merge
    # Orchestrates the smart merge process for Markdown files using Markly.
    #
    # This is a thin wrapper around Markdown::Merge::SmartMerger that:
    # - Forces the :markly backend
    # - Sets markly-specific defaults (freeze token, inner_merge_code_blocks)
    # - Exposes markly-specific options (flags, extensions)
    #
    # @example Basic merge (destination customizations preserved)
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #   if result.success?
    #     File.write("output.md", result.content)
    #   end
    #
    # @example Template updates win
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    # @example Custom signature matching
    #   sig_gen = ->(node) {
    #     canonical_type = Ast::Merge::NodeTyping.merge_type_for(node) || node.type
    #     if canonical_type == :heading
    #       [:heading, node.header_level]  # Match by level only, not content
    #     else
    #       node  # Fall through to default
    #     end
    #   }
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_generator: sig_gen
    #   )
    #
    # @example Disable inner-merge for code blocks
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     inner_merge_code_blocks: false
    #   )
    #
    # @see Markdown::Merge::SmartMerger Underlying implementation
    class SmartMerger < Markdown::Merge::SmartMerger
      Markdown::Merge::WrapperSupport.configure_smart_merger_subclass!(
        self,
        default_backend: :markly,
        default_freeze_token: -> { DEFAULT_FREEZE_TOKEN },
        default_inner_merge_code_blocks: -> { DEFAULT_INNER_MERGE_CODE_BLOCKS },
        default_parser_options: lambda do
          {
            flags: ::Markly::DEFAULT,
            extensions: [:table]
          }
        end,
        file_analysis_class: -> { FileAnalysis },
        template_parse_error_class: -> { TemplateParseError },
        destination_parse_error_class: -> { DestinationParseError }
      )
    end
  end
end
