# frozen_string_literal: true

RSpec.shared_examples('Ast::Merge::RetainedBlankGapCompliance') do
  def retained_blank_gap_source(*lines)
    comment_matrix_source(*lines)
  end

  it 'preserves destination blank gaps between retained matched owners' do
    template = retained_blank_gap_source(
      comment_matrix_line_builder.call('alpha', '1'),
      comment_matrix_line_builder.call('beta', '2')
    )
    destination = retained_blank_gap_source(
      comment_matrix_line_builder.call('alpha', '9'),
      '',
      comment_matrix_line_builder.call('beta', '8')
    )

    result = comment_matrix_merger_class.new(template, destination).merge

    expect(result).to(eq(destination))
  end

  it 'preserves destination blank gaps between retained matched owners under template preference' do
    template = retained_blank_gap_source(
      comment_matrix_line_builder.call('alpha', '1'),
      comment_matrix_line_builder.call('beta', '2')
    )
    destination = retained_blank_gap_source(
      comment_matrix_line_builder.call('alpha', '9'),
      '',
      comment_matrix_line_builder.call('beta', '8')
    )
    expected = retained_blank_gap_source(
      comment_matrix_line_builder.call('alpha', '1'),
      '',
      comment_matrix_line_builder.call('beta', '2')
    )

    result = comment_matrix_merger_class.new(template, destination, preference: :template).merge

    expect(result).to(eq(expected))
  end
end
