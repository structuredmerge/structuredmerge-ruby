# frozen_string_literal: true

module Commonmarker
  module Merge
    # File analysis for Markdown files using CommonMarker.
    #
    # This is a thin wrapper around Markdown::Merge::FileAnalysis that:
    # - Forces the :commonmarker backend
    # - Sets the default freeze token to "commonmarker-merge"
    # - Exposes commonmarker-specific options
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
      # Default freeze token for commonmarker-merge
      # @return [String]
      DEFAULT_FREEZE_TOKEN = 'commonmarker-merge'

      Markdown::Merge::WrapperSupport.configure_file_analysis_subclass!(
        self,
        default_backend: :commonmarker
      )
    end
  end
end
