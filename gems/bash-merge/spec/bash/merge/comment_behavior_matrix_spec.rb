# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

RSpec.describe Bash::Merge::SmartMerger, 'comment behavior matrix', :bash_grammar do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  it_behaves_like 'Ast::Merge::CommentBehaviorMatrix' do
    hash_comment_line_based_comment_matrix_adapter(
      analysis_class: Bash::Merge::FileAnalysis,
      merger_class: Bash::Merge::SmartMerger,
      capabilities: {},
      structural_owners_reader: ->(analysis) { analysis.top_level_statements.select(&:variable_assignment?) },
      owner_value_reader: ->(owner) { owner.text[/\A[a-zA-Z_][a-zA-Z0-9_]*=(.+)\z/, 1] },
      line_builder: lambda do |name, value, inline: nil|
        line = "#{name}=#{value}"
        inline ? "#{line} # #{inline}" : line
      end
    )

    it_behaves_like 'Ast::Merge::RetainedBlankGapCompliance'
  end
end
