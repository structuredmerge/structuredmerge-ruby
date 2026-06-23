# frozen_string_literal: true

module Markly
  module Merge
    # File analysis for Markdown files using Markly.
    #
    # This is a thin wrapper around Markdown::Merge::FileAnalysis that:
    # - Forces the :markly backend
    # - Sets the default freeze token to "markly-merge"
    # - Exposes markly-specific options (flags, extensions)
    #
    # @example Basic usage
    #   analysis = FileAnalysis.new(markdown_source)
    #   analysis.statements.each do |node|
    #     puts "#{node.merge_type}: #{node.type}"
    #   end
    #
    # @example With custom freeze token
    #   analysis = FileAnalysis.new(source, freeze_token: "my-merge")
    #
    # @see Markdown::Merge::FileAnalysis Underlying implementation
    class FileAnalysis < Markdown::Merge::FileAnalysis
      # Default freeze token for markly-merge
      # @return [String]
      DEFAULT_FREEZE_TOKEN = 'markly-merge'

      Markdown::Merge::WrapperSupport.configure_file_analysis_subclass!(
        self,
        default_backend: :markly,
        default_parser_options: lambda do
          {
            flags: ::Markly::DEFAULT,
            extensions: [:table]
          }
        end
      )
    end
  end
end
