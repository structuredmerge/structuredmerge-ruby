# frozen_string_literal: true

module Ast
  module Merge
    # Text-based AST module for ast-merge.
    #
    # Provides a simple line/word based AST that can be used with any text file.
    # This serves as both:
    # 1. A reference implementation for *-merge gems
    # 2. A testing tool for validating merge behavior
    #
    # @example Basic usage
    #   require "ast/merge/text"
    #
    #   template = "Line one\nLine two\nLine three"
    #   dest = "Line one modified\nLine two\nCustom line"
    #
    #   merger = Ast::Merge::Text::SmartMerger.new(template, dest)
    #   result = merger.merge
    module Text
      # Default freeze token for text files
      DEFAULT_FREEZE_TOKEN = 'text-merge'

      autoload :WordNode, 'ast/merge/text/word_node'
      autoload :LineNode, 'ast/merge/text/line_node'
      autoload :FileAnalysis, 'ast/merge/text/file_analysis'
      autoload :MergeResult, 'ast/merge/text/merge_result'
      autoload :ConflictResolver, 'ast/merge/text/conflict_resolver'
      autoload :SmartMerger, 'ast/merge/text/smart_merger'
      autoload :Section, 'ast/merge/text/section'
      autoload :SectionSplitter, 'ast/merge/text/section_splitter'
      autoload :LineSectionSplitter, 'ast/merge/text/section_splitter'
    end
  end
end
