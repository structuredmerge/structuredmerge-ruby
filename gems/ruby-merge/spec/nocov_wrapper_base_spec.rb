# frozen_string_literal: true

RSpec.describe Ruby::Merge::NocovWrapperBase do
  let(:location) { Struct.new(:start_line, :end_line).new(2, 4) }
  let(:node) do
    Struct.new(:location, :slice).new(location, "def skipped\nend\n")
  end

  it 'marks wrapped Ruby nodes as nocov block directive participants' do
    wrapper = described_class.new(node)

    expect(wrapper.kind).to eq(:nocov)
    expect(wrapper.children).to eq([])
    expect(wrapper.merge_policy).to be_nil
    expect(wrapper.start_line).to eq(2)
    expect(wrapper.end_line).to eq(4)
    expect(wrapper.unwrap).to equal(node)
    expect(wrapper.location).to equal(location)
    expect(wrapper.slice).to eq("def skipped\nend\n")
    expect(wrapper.nocov_wrapper?).to be(true)
    expect(wrapper.nocov_node?).to be(false)
  end
end
