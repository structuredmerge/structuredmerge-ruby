# frozen_string_literal: true

RSpec.describe Ast::Merge::Layout::Policy do
  it 'preserves exact whitespace by default' do
    policy = described_class.new

    expect(policy).to be_preserve_exact
    expect(policy.equivalent_blank_line?('', '  ')).to be(false)
    expect(policy.equivalent_blank_line?('', '')).to be(true)
  end

  it 'supports explicit whitespace-only blank-line equivalence' do
    policy = described_class.new(mode: :blank_line_equivalent)

    expect(policy).to be_blank_line_equivalent
    expect(policy.equivalent_blank_line?('', '  ')).to be(true)
    expect(policy.equivalent_blank_line?('', 'content')).to be(false)
  end

  it 'rejects unnamed layout policies' do
    expect do
      described_class.new(mode: :cleanup_whitespace)
    end.to raise_error(ArgumentError, /Unknown layout policy mode/)
  end
end
