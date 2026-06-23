# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples/reproducible_partial_merge'

class TestPartialTemplateMerger
  Result = Struct.new(:content, :changed, :has_section, :message, keyword_init: true) do
    def section_found?
      has_section
    end
  end

  def initialize(template:, destination:, open_token: '[[TARGET]]', close_token: '[[/TARGET]]')
    @template = template
    @destination = destination
    @open_token = open_token
    @close_token = close_token
  end

  def merge
    pattern = /(#{Regexp.escape(@open_token)})(.*?)(#{Regexp.escape(@close_token)})/m
    match = @destination.match(pattern)

    unless match
      return Result.new(content: @destination, changed: false, has_section: false,
                        message: 'Section not found')
    end

    merged_content = @destination.sub(pattern, "\\1#{@template}\\3")

    Result.new(
      content: merged_content,
      changed: merged_content != @destination,
      has_section: true,
      message: merged_content == @destination ? 'Section unchanged' : 'Section merged successfully'
    )
  end
end

# -- shared example self-test
RSpec.describe 'reproducible partial merge shared examples' do
  it_behaves_like 'a reproducible partial merge' do
    let(:partial_merger_class) { TestPartialTemplateMerger }
    let(:template_content) { 'new content' }
    let(:destination_content) { "before\n[[TARGET]]old content[[/TARGET]]\nafter\n" }
    let(:expected_merged_content) { "before\n[[TARGET]]new content[[/TARGET]]\nafter\n" }
  end
end
