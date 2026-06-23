# frozen_string_literal: true

require 'markly/merge'
require 'ast/merge/rspec/shared_examples'

RSpec.describe 'Markly reproducible merge' do
  let(:fixtures_path) { File.expand_path('fixtures/reproducible', __dir__) }
  let(:merger_class) { Markly::Merge::SmartMerger }
  let(:file_extension) { 'md' }

  describe 'basic merge scenarios (destination wins by default)' do
    context 'when a heading section is removed in destination' do
      it_behaves_like 'a reproducible merge', '01_heading_removed'
    end

    context 'when a heading section is added in destination' do
      it_behaves_like 'a reproducible merge', '02_heading_added'
    end

    context 'when content is changed in destination' do
      it_behaves_like 'a reproducible merge', '03_content_changed'
    end
  end

  it 'keeps template-only paragraphs and inner-merged code fences reproducible' do
    template = <<~MARKDOWN
      # Title

      ```ruby
      puts 'template'
      ```

      ## Details

      Template details.
    MARKDOWN
    destination = <<~MARKDOWN
      # Title

      ## Details

      Destination details.
    MARKDOWN

    first_merge = merger_class.new(template, destination, add_template_only_nodes: true).merge
    second_merge = merger_class.new(template, first_merge, add_template_only_nodes: true).merge

    expect(first_merge).to eq(<<~MARKDOWN)
      # Title

      ```ruby
      puts 'template'
      ```

      ## Details

      Destination details.

      Template details.
    MARKDOWN
    expect(second_merge).to eq(first_merge)
  end
end
