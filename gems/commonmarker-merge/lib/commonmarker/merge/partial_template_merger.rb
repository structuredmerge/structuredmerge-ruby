# frozen_string_literal: true

module Commonmarker
  module Merge
    # Thin Commonmarker-specific wrapper for Markdown::Merge::PartialTemplateMerger.
    #
    # Forces the :commonmarker backend while inheriting comment-handling and
    # merge behavior from markdown-merge.
    class PartialTemplateMerger < Markdown::Merge::PartialTemplateMerger
      Result = Markdown::Merge::PartialTemplateMerger::Result

      Markdown::Merge::WrapperSupport.configure_partial_template_merger_subclass!(
        self,
        default_backend: :commonmarker,
        file_analysis_class: -> { FileAnalysis },
        smart_merger_class: -> { SmartMerger }
      )
    end
  end
end
