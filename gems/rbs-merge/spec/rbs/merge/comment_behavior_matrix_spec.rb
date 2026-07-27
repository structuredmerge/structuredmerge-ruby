# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples'

RSpec.describe Rbs::Merge::SmartMerger, 'comment behavior matrix' do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  it_behaves_like 'Ast::Merge::CommentBehaviorMatrix' do
    hash_comment_line_based_comment_matrix_adapter(
      analysis_class: Rbs::Merge::FileAnalysis,
      merger_class: Rbs::Merge::SmartMerger,
      structural_owners_reader: ->(analysis) { analysis.statements.grep(Rbs::Merge::NodeWrapper) },
      owner_value_reader: ->(owner) { owner.text[/\Atype\s+[a-z_]\w*\s+=\s+(.+)\z/, 1] },
      line_builder: lambda do |name, value, inline: nil|
        "type #{name} = #{value}"
      end,
      capabilities: {
        inline_comments: 'intentional syntax limit: RBS has no inline comment form for these declarations, so this is not a pending matrix gap',
        quoted_hash_inline_literals: 'intentional syntax limit: quoted hash-inline comment scenarios do not exist in RBS syntax, so this is not a pending matrix gap'
      }
    )

    it_behaves_like 'Ast::Merge::RetainedBlankGapCompliance'
  end
end
