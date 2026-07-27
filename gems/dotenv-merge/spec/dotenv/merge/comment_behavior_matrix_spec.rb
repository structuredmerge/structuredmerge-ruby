# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples'

RSpec.describe Dotenv::Merge::SmartMerger, 'comment behavior matrix' do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  it_behaves_like 'Ast::Merge::CommentBehaviorMatrix' do
    hash_comment_line_based_comment_matrix_adapter(
      analysis_class: Dotenv::Merge::FileAnalysis,
      merger_class: Dotenv::Merge::SmartMerger,
      structural_owners_reader: ->(analysis) { analysis.structural_owners.grep(Dotenv::Merge::EnvLine) },
      owner_value_reader: ->(owner) { owner.value },
      line_builder: lambda do |name, value, inline: nil|
        line = "#{name}=#{value}"
        inline ? "#{line} # #{inline}" : line
      end,
      capabilities: {
        quoted_hash_inline_literals: 'intentional parser limit: quoted dotenv values with trailing comment-like text are treated as literal value content, so this is not a pending matrix gap',
        template_only_attached_comment_additions: 'intentional merge policy: template-only dotenv additions stay comment-free, so this matrix case is out of scope unless that product decision changes',
        template_only_floating_comment_additions: 'intentional merge policy: template-only dotenv additions stay comment-free, so this matrix case is out of scope unless that product decision changes',
        template_only_preamble_additions: 'intentional merge policy: template-only dotenv additions stay comment-free, so this matrix case is out of scope unless that product decision changes',
        template_only_trailing_comment_additions: 'intentional merge policy: template-only dotenv additions stay comment-free, so this matrix case is out of scope unless that product decision changes'
      },
      expected_literal_hash_value: 'literal # hash'
    )

    it_behaves_like 'Ast::Merge::RetainedBlankGapCompliance'
  end
end
