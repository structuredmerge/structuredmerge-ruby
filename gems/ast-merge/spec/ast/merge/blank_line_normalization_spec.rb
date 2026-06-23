# frozen_string_literal: true

RSpec.describe 'Ast::Merge blank-line normalization' do
  it 'collapses repeated blank-line runs in plain content' do
    content = "before\n\n\n\nafter\n"

    expect(Ast::Merge.normalize_blank_line_runs(content)).to eq("before\n\nafter\n")
  end

  it 'honors the configured maximum retained blank lines' do
    content = "before\n\n\n\nafter\n"

    expect(Ast::Merge.normalize_blank_line_runs(content, max: 2)).to eq("before\n\n\nafter\n")
  end
end
