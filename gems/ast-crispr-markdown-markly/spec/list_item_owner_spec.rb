# frozen_string_literal: true

RSpec.describe Ast::Crispr::Markdown::Markly do
  it 'exposes Markdown list items as CRISPR structural owners' do
    source = <<~MARKDOWN
      # Title

      ## Changed

      - First item
        continuation
    MARKDOWN

    context = described_class.document_context(content: source, source_label: 'CHANGELOG.transfer.md')
    owners = context.structural_owners(owner_scope: :list_items)

    expect(owners.size).to eq(1)
    expect(owners.first.source).to include("- First item\n  continuation")
    expect(owners.first.location.start_line).to eq(5)
  end

  it 'selects Markdown list item matches through the Markly selector' do
    source = <<~MARKDOWN
      # Title

      - Selected item
    MARKDOWN
    context = described_class.document_context(content: source, source_label: 'README.md')
    selector = described_class::Selectors.list_item(text: 'Selected')

    matches = selector.locate_matches(context)

    expect(matches.map(&:line_range)).to eq([3..3])
  end
end
