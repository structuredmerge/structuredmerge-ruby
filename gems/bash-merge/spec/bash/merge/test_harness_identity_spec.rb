# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bash::Merge::TestHarnessIdentity do
  def command_for(source)
    Bash::Merge::FileAnalysis.new(source).nodes.find(&:command?)
  end

  it 'identifies literal titles and optional literal prerequisites without using the body' do
    simple = command_for("test_expect_success 'keeps both edits' 'echo base'\n")
    qualified = command_for("test_expect_success PERL 'keeps both edits' 'echo base'\n")

    expect(described_class.for(simple)).to eq([:test_expect_success, "'keeps both edits'"])
    expect(described_class.for(qualified)).to eq(
      [:test_expect_success, 'PERL', "'keeps both edits'"]
    )
  end

  it 'rejects dynamic titles and arbitrary commands' do
    dynamic = command_for("test_expect_success \"uses $mode\" 'echo base'\n")
    arbitrary = command_for("printf '%s' 'keeps both edits'\n")

    expect(described_class.for(dynamic)).to be_nil
    expect(described_class.for(arbitrary)).to be_nil
  end
end
