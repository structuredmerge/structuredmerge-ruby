# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples/removal_mode_compliance'

class TestRemovalModeMerger
  REGISTERED_CASES = {}.freeze

  class << self
    def registered_cases
      REGISTERED_CASES
    end

    def clear_cases!
      registered_cases.clear
    end

    def register_case(example_case)
      options = normalized_options({ remove_template_missing_nodes: true }.merge(example_case.fetch(:options, {})))
      template = example_case.fetch(:template)
      destination = example_case.fetch(:destination)
      expected = example_case.fetch(:expected)

      registered_cases[[template, destination, options]] = expected
      registered_cases[[template, expected, options]] = expected
    end

    def normalized_options(options)
      options.sort_by { |key, _value| key.to_s }.to_h
    end
  end

  def initialize(template_content, destination_content, **options)
    @template_content = template_content
    @destination_content = destination_content
    @options = self.class.normalized_options(options)
  end

  def merge
    self.class.registered_cases.fetch([@template_content, @destination_content, @options])
  end
end

# -- shared example self-test
RSpec.describe 'RemovalModeCompliance shared examples' do
  it_behaves_like 'Ast::Merge::RemovalModeCompliance' do
    let(:merger_class) { TestRemovalModeMerger }

    let(:removal_mode_leading_comments_case) do
      {
        template: "keep\n",
        destination: "# docs\nremove\nkeep\n",
        expected: "# docs\nkeep\n"
      }
    end

    let(:removal_mode_inline_comments_case) do
      {
        template: "keep\n",
        destination: "remove # inline docs\nkeep\n",
        expected: "# inline docs\nkeep\n"
      }
    end

    let(:removal_mode_separator_blank_line_case) do
      {
        template: "keep\n",
        destination: "# docs\nremove # inline docs\n\n# separator note\n\nkeep\n",
        expected: "# docs\n# inline docs\n\n# separator note\n\nkeep\n"
      }
    end

    let(:removal_mode_recursive_case) do
      {
        template: "outer\n  keep\n",
        destination: "outer\n  # nested docs\n  remove\n  keep\n",
        expected: "outer\n  # nested docs\n  keep\n",
        options: { recursive: true }
      }
    end

    before do
      TestRemovalModeMerger.clear_cases!
      [
        removal_mode_leading_comments_case,
        removal_mode_inline_comments_case,
        removal_mode_separator_blank_line_case,
        removal_mode_recursive_case
      ].each do |example_case|
        TestRemovalModeMerger.register_case(example_case)
      end
    end
  end

  describe 'without optional cases' do
    it_behaves_like 'Ast::Merge::RemovalModeCompliance' do
      let(:merger_class) { TestRemovalModeMerger }

      let(:removal_mode_leading_comments_case) do
        {
          template: "keep\n",
          destination: "# docs\nremove\nkeep\n",
          expected: "# docs\nkeep\n"
        }
      end

      let(:removal_mode_separator_blank_line_case) do
        {
          template: "keep\n",
          destination: "# docs\nremove\n\nkeep\n",
          expected: "# docs\n\nkeep\n"
        }
      end

      let(:unsupported_removal_mode_case_reasons) do
        {
          removal_mode_inline_comments_case: 'inline comments are unsupported in this synthetic merger',
          removal_mode_recursive_case: 'recursive merge is unsupported in this synthetic merger'
        }
      end

      before do
        TestRemovalModeMerger.clear_cases!
        [
          removal_mode_leading_comments_case,
          removal_mode_separator_blank_line_case
        ].each do |example_case|
          TestRemovalModeMerger.register_case(example_case)
        end
      end
    end
  end
end
