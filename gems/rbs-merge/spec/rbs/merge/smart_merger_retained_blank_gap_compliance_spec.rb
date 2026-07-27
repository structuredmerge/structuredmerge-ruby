# frozen_string_literal: true

require 'spec_helper'
require 'rbs/merge'
require 'ast/merge/rspec/shared_examples'

RSpec.describe Rbs::Merge::SmartMerger, :rbs_parsing do
  it_behaves_like 'Ast::Merge::RecursiveRetainedBlankGapCompliance' do
    let(:merger_class) { described_class }

    let(:recursive_retained_blank_gap_case) do
      {
        template: <<~RBS,
          class Example
            def alpha: () -> String
            def beta: () -> String
          end
        RBS
        destination: <<~RBS,
          class Example
            def alpha: () -> Symbol

            def beta: () -> Symbol
          end
        RBS
        expected: <<~RBS,
          class Example
            def alpha: () -> String

            def beta: () -> String
          end
        RBS
        options: { preference: :template }
      }
    end
  end
end
