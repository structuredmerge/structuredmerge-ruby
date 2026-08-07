# frozen_string_literal: true

require 'spec_helper'
require 'toml/merge'
require 'ast/merge/rspec'
require 'ast/merge/rspec/shared_examples'

RSpec.describe Toml::Merge::SmartMerger, :toml_parsing do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  it_behaves_like 'Ast::Merge::RetainedBlankGapCompliance' do
    hash_comment_line_based_comment_matrix_adapter(
      analysis_class: Toml::Merge::FileAnalysis,
      merger_class: described_class,
      structural_owners_reader: lambda(&:statements),
      owner_value_reader: lambda(&:value),
      line_builder: lambda do |name, value, inline: nil|
        line = "#{name} = \"#{value}\""
        inline ? "#{line} # #{inline}" : line
      end
    )
  end

  it 'preserves destination blank gaps between retained matched keys inside a table under template preference' do
    template = <<~TOML
      [app]
      alpha = "1"
      beta = "2"
    TOML
    destination = <<~TOML
      [app]
      alpha = "9"

      beta = "8"
    TOML
    expected = <<~TOML
      [app]
      alpha = "1"

      beta = "2"
    TOML

    expect(described_class.new(template, destination, preference: :template).merge).to eq(expected)
  end
end
