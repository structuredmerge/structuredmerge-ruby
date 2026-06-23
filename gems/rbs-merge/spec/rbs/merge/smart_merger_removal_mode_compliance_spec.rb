# frozen_string_literal: true

require 'spec_helper'
require 'rbs/merge'
require 'ast/merge/rspec/shared_examples'

RSpec.describe Rbs::Merge::SmartMerger, :rbs_parsing do
  it_behaves_like 'Ast::Merge::RemovalModeCompliance' do
    let(:merger_class) { described_class }

    let(:removal_mode_leading_comments_case) do
      {
        template: <<~RBS,
          class Keep
          end
        RBS
        destination: <<~RBS,
          class Keep
          end

          # keep removed declaration docs
          class Legacy
          end
        RBS
        expected: <<~RBS
          class Keep
          end

          # keep removed declaration docs
        RBS
      }
    end

    let(:removal_mode_separator_blank_line_case) do
      {
        template: <<~RBS,
          class Keep
          end

          class Tail
          end
        RBS
        destination: <<~RBS,
          class Keep
          end

          # keep removed declaration docs
          class Legacy
          end

          # keep tail docs
          class Tail
          end
        RBS
        expected: <<~RBS
          class Keep
          end

          # keep removed declaration docs

          # keep tail docs
          class Tail
          end
        RBS
      }
    end

    let(:removal_mode_recursive_case) do
      {
        template: <<~RBS,
          class Example
            def shared: () -> String
          end
        RBS
        destination: <<~RBS,
          class Example
            # keep helper docs
            def helper: () -> Symbol

            def shared: () -> Integer
          end
        RBS
        expected: "class Example\n  # keep helper docs\n  def shared: () -> String\nend\n",
        options: { preference: :template }
      }
    end

    let(:unsupported_removal_mode_case_reasons) do
      {
        removal_mode_inline_comments_case: 'RBS declarations do not expose general inline-comment promotion semantics'
      }
    end
  end
end
