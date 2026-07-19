# frozen_string_literal: true

RSpec.describe Ruby::Merge::NocovNodeBase do
  let(:analysis_class) do
    Struct.new(:lines) do
      def generate_signature(node)
        [:node, node]
      end
    end
  end

  it 'models balanced nocov blocks as Ruby block directives' do
    analysis = analysis_class.new(["# :nocov:\n", "def skipped\n", "end\n", "# :nocov:\n"])
    node = described_class.new(start_line: 1, end_line: 4, analysis: analysis, nodes: [:method])

    expect(node.kind).to eq(:nocov)
    expect(node.merge_policy).to be_nil
    expect(node.children).to eq([:method])
    expect(node.merge_type).to eq(:nocov_block)
    expect(node.signature).to eq([:node, :method])
    expect(node.slice).to eq("# :nocov:\ndef skipped\nend\n# :nocov:\n")
  end

  it 'uses normalized inner block content when multiple nodes are covered' do
    analysis = analysis_class.new(["# :nocov:\n", "def a\n", "end\n", "def b\n", "end\n", "# :nocov:\n"])
    node = described_class.new(start_line: 1, end_line: 6, analysis: analysis, nodes: %i[a b])

    expect(node.signature).to eq([:nocov_multi, "def a\nend\ndef b\nend"])
  end
end
