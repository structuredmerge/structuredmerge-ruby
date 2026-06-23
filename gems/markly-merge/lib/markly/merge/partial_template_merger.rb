# frozen_string_literal: true

module Markly
  module Merge
    # Thin Markly-specific wrapper for Markdown::Merge::PartialTemplateMerger.
    #
    # Forces the :markly backend and the markly-merge default freeze token while
    # inheriting all comment-handling and merge behavior from markdown-merge.
    class PartialTemplateMerger < Markdown::Merge::PartialTemplateMerger
      Result = Markdown::Merge::PartialTemplateMerger::Result

      Markdown::Merge::WrapperSupport.configure_partial_template_merger_subclass!(
        self,
        default_backend: :markly,
        file_analysis_class: -> { FileAnalysis },
        smart_merger_class: -> { SmartMerger }
      )
    end
  end
end
