# frozen_string_literal: true

require 'ast/merge/text'

RSpec.describe Ast::Merge::Text::FileAnalysis do
  describe '#initialize' do
    it 'parses source into line statements' do
      source = "Hello world\nGoodbye world"
      analysis = described_class.new(source)

      expect(analysis.statements.size).to eq(2)
      expect(analysis.statements[0]).to be_a(Ast::Merge::Text::LineNode)
      expect(analysis.statements[1]).to be_a(Ast::Merge::Text::LineNode)
    end

    it 'handles empty source' do
      analysis = described_class.new('')

      expect(analysis.statements).to be_empty
    end

    it 'handles single line without newline' do
      analysis = described_class.new('Hello world')

      expect(analysis.statements.size).to eq(1)
      expect(analysis.statements[0].content).to eq('Hello world')
    end

    it 'handles trailing newline correctly' do
      analysis = described_class.new("Hello world\n")

      expect(analysis.statements.size).to eq(1)
      expect(analysis.statements[0].content).to eq('Hello world')
    end

    it 'preserves empty lines in the middle' do
      source = "Line one\n\nLine three"
      analysis = described_class.new(source)

      expect(analysis.statements.size).to eq(3)
      expect(analysis.statements[0].content).to eq('Line one')
      expect(analysis.statements[1].content).to eq('')
      expect(analysis.statements[2].content).to eq('Line three')
    end
  end

  describe 'freeze blocks' do
    it 'parses freeze blocks with default token' do
      source = <<~TEXT
        Line one
        # text-merge:freeze
        Frozen content
        # text-merge:unfreeze
        Line four
      TEXT
      analysis = described_class.new(source)

      expect(analysis.statements.size).to eq(3)
      expect(analysis.statements[0]).to be_a(Ast::Merge::Text::LineNode)
      expect(analysis.statements[0].content).to eq('Line one')
      expect(analysis.statements[1]).to be_a(Ast::Merge::FreezeNodeBase)
      expect(analysis.statements[2]).to be_a(Ast::Merge::Text::LineNode)
      expect(analysis.statements[2].content).to eq('Line four')
    end

    it 'parses freeze blocks with custom token' do
      source = <<~TEXT
        Line one
        # custom:freeze
        Frozen content
        # custom:unfreeze
        Line four
      TEXT
      analysis = described_class.new(source, freeze_token: 'custom')

      expect(analysis.statements.size).to eq(3)
      expect(analysis.statements[1]).to be_a(Ast::Merge::FreezeNodeBase)
    end

    it 'raises error for unclosed freeze block' do
      source = <<~TEXT
        Line one
        # text-merge:freeze
        Frozen content
      TEXT

      expect { described_class.new(source) }.to raise_error(
        Ast::Merge::FreezeNodeBase::InvalidStructureError,
        /Unclosed freeze block/
      )
    end

    it 'extracts freeze reason when provided' do
      source = <<~TEXT
        # text-merge:freeze Custom reason here
        Frozen content
        # text-merge:unfreeze
      TEXT
      analysis = described_class.new(source)

      expect(analysis.statements.size).to eq(1)
      expect(analysis.statements[0]).to be_a(Ast::Merge::FreezeNodeBase)
      expect(analysis.statements[0].reason).to eq('Custom reason here')
    end
  end

  describe '#compute_node_signature' do
    it 'returns signature for LineNode' do
      source = 'Hello world'
      analysis = described_class.new(source)
      line_node = analysis.statements[0]

      expect(analysis.compute_node_signature(line_node)).to eq([:line, 'Hello world'])
    end

    it 'returns signature for FreezeNodeBase' do
      source = <<~TEXT
        # text-merge:freeze
        Frozen
        # text-merge:unfreeze
      TEXT
      analysis = described_class.new(source)
      freeze_node = analysis.statements[0]

      expect(analysis.compute_node_signature(freeze_node)).to eq([:freeze_block, 1, 3])
    end

    it 'returns nil for unknown node types' do
      analysis = described_class.new('Hello')

      expect(analysis.compute_node_signature('not a node')).to be_nil
    end
  end

  describe 'shared layout compliance' do
    subject(:analysis) { described_class.new(layout_source) }

    let(:layout_source) do
      <<~TEXT

        alpha

        beta

      TEXT
    end

    let(:first_owner) { analysis.statements.reject(&:blank?).first }
    let(:second_owner) { analysis.statements.reject(&:blank?)[1] }
    let(:layout_augmenter) { analysis.layout_augmenter(owners: [first_owner, second_owner].compact) }
    let(:layout_attachment) { layout_augmenter.attachment_for(first_owner) }

    it 'finds stable non-blank line owners for layout inference' do
      expect(first_owner).not_to be_nil
      expect(second_owner).not_to be_nil
      expect(first_owner.content).to eq('alpha')
      expect(second_owner.content).to eq('beta')
      expect(first_owner.start_line).to eq(2)
      expect(second_owner.start_line).to eq(4)
    end

    it_behaves_like 'Ast::Merge::Layout::Attachment' do
      let(:expected_attachment_owner) { first_owner }
      let(:expected_leading_gap_kind) { :preamble }
      let(:expected_trailing_gap_kind) { :interstitial }
      let(:expected_gap_ranges) { [1..1, 3..3] }
      let(:expected_leading_controls_output) { true }
      let(:expected_trailing_controls_output) { false }
    end

    it_behaves_like 'Ast::Merge::Layout::Augmenter' do
      let(:augmenter_owner) { first_owner }
      let(:expected_preamble_range) { 1..1 }
      let(:expected_postlude_range) { 5..5 }
      let(:expected_interstitial_ranges) { [3..3] }
      let(:expected_owner_leading_gap_kind) { :preamble }
      let(:expected_owner_trailing_gap_kind) { :interstitial }
    end
  end

  describe '#fallthrough_node?' do
    it 'returns true for LineNode' do
      source = 'Hello world'
      analysis = described_class.new(source)
      line_node = analysis.statements[0]

      expect(analysis.fallthrough_node?(line_node)).to be true
    end

    it 'returns true for FreezeNodeBase' do
      source = <<~TEXT
        # text-merge:freeze
        Frozen
        # text-merge:unfreeze
      TEXT
      analysis = described_class.new(source)
      freeze_node = analysis.statements[0]

      expect(analysis.fallthrough_node?(freeze_node)).to be true
    end

    it 'returns false for other types' do
      analysis = described_class.new('Hello')

      expect(analysis.fallthrough_node?('not a node')).to be false
    end
  end

  describe '#freeze_marker? edge cases' do
    it 'returns false for invalid marker type' do
      analysis = described_class.new('test')
      # Test with an unrecognized type symbol
      result = analysis.send(:freeze_marker?, '# text-merge:freeze', :invalid_type)
      expect(result).to be false
    end

    it 'returns false when line does not match freeze pattern' do
      analysis = described_class.new('test')
      result = analysis.send(:freeze_marker?, 'regular line', :freeze)
      expect(result).to be false
    end

    it 'detects explicit unfreeze directives through normalized comment parsing' do
      analysis = described_class.new('test')

      expect(analysis.send(:freeze_marker?, '# text-merge:unfreeze', :unfreeze)).to be(true)
      expect(analysis.send(:freeze_marker?, '# text-merge:unfreeze', :freeze)).to be(false)
    end

    it 'does not treat inline token text in non-comment lines as freeze directives' do
      analysis = described_class.new('test')

      expect(analysis.send(:freeze_marker?, 'value text-merge:freeze', :freeze)).to be(false)
    end
  end

  describe 'orphan unfreeze marker' do
    it 'ignores unfreeze marker without matching freeze marker' do
      source = <<~TEXT
        Line before
        # text-merge:unfreeze
        Line after
      TEXT
      analysis = described_class.new(source)

      # The unfreeze line should be skipped (not create a freeze block or line node)
      # and we should just get the regular lines
      statements = analysis.statements
      line_contents = statements.map { |s| s.respond_to?(:content) ? s.content : s.to_s }

      expect(statements.size).to eq(2)
      expect(line_contents).to contain_exactly('Line before', 'Line after')
    end
  end

  describe '#extract_freeze_reason edge cases' do
    it 'returns nil when no reason is provided' do
      source = <<~TEXT
        # text-merge:freeze
        Content
        # text-merge:unfreeze
      TEXT
      analysis = described_class.new(source)
      freeze_node = analysis.statements[0]

      expect(freeze_node.reason).to be_nil
    end

    it 'extracts reason when provided after freeze' do
      source = <<~TEXT
        # text-merge:freeze Keep this content
        Content
        # text-merge:unfreeze
      TEXT
      analysis = described_class.new(source)
      freeze_node = analysis.statements[0]

      expect(freeze_node.reason).to eq('Keep this content')
    end
  end
end
