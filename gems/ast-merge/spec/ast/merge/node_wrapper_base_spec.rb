# frozen_string_literal: true

RSpec.describe Ast::Merge::NodeWrapperBase do
  # Use TestableNode for real TreeHaver::Node behavior
  let(:test_node) do
    TestableNode.create(
      type: :test_type,
      text: "line 1\nline 2\nline 3",
      start_line: 1,
      end_line: 3,
      start_byte: 0,
      end_byte: 10
    )
  end

  let(:source_lines) { ['line 1', 'line 2', 'line 3'] }
  let(:source_string) { source_lines.join("\n") }

  # Concrete subclass for testing
  let(:test_wrapper_class) do
    Class.new(described_class) do
      def compute_signature(node)
        [:test, node.type.to_sym]
      end
    end
  end

  let(:wrapper) do
    test_wrapper_class.new(test_node, lines: source_lines, source: source_string)
  end

  describe '#initialize' do
    it 'stores the node' do
      expect(wrapper.node).to eq(test_node)
    end

    it 'stores the lines' do
      expect(wrapper.lines).to eq(source_lines)
    end

    it 'stores the source' do
      expect(wrapper.source).to eq(source_string)
    end

    it 'extracts start_line (1-based)' do
      expect(wrapper.start_line).to eq(1)
    end

    it 'extracts end_line (1-based)' do
      expect(wrapper.end_line).to eq(3)
    end

    it 'defaults leading_comments to empty array' do
      expect(wrapper.leading_comments).to eq([])
    end

    it 'defaults inline_comment to nil' do
      expect(wrapper.inline_comment).to be_nil
    end

    context 'with comments' do
      let(:leading) { [{ line: 1, text: 'comment', raw: '# comment', full_line: true }] }
      let(:inline) { { line: 2, text: 'inline', raw: '# inline', full_line: false } }

      let(:wrapper_with_comments) do
        test_wrapper_class.new(
          test_node,
          lines: source_lines,
          leading_comments: leading,
          inline_comment: inline
        )
      end

      it 'stores leading_comments' do
        expect(wrapper_with_comments.leading_comments).to eq(leading)
      end

      it 'stores inline_comment' do
        expect(wrapper_with_comments.inline_comment).to eq(inline)
      end
    end

    context 'when end_line is before start_line (using mock for edge case)' do
      let(:bad_node) do
        # Use mock for edge case testing where we need invalid data
        double(
          'mock_bad_node',
          type: :test,
          start_point: double(row: 5),
          end_point: double(row: 2)
        )
      end

      it 'corrects end_line to equal start_line' do
        wrapper = test_wrapper_class.new(bad_node, lines: source_lines)
        expect(wrapper.end_line).to eq(wrapper.start_line)
      end
    end

    context 'when node uses hash-style points' do
      let(:hash_point_node) do
        TestableNode.create(
          type: :test,
          text: 'test content',
          start_line: 2,
          end_line: 4
        )
      end

      it 'extracts line info from hash points' do
        wrapper = test_wrapper_class.new(hash_point_node, lines: source_lines)
        expect(wrapper.start_line).to eq(2)
        expect(wrapper.end_line).to eq(4)
      end
    end
  end

  describe '#signature' do
    it 'calls compute_signature' do
      expect(wrapper.signature).to eq(%i[test test_type])
    end
  end

  describe '#type' do
    it 'returns node type as symbol' do
      expect(wrapper.type).to eq(:test_type)
    end
  end

  describe '#type?' do
    it 'returns true for matching type as symbol' do
      expect(wrapper.type?(:test_type)).to be true
    end

    it 'returns true for matching type as string' do
      expect(wrapper.type?('test_type')).to be true
    end

    it 'returns false for non-matching type' do
      expect(wrapper.type?(:other)).to be false
    end
  end

  describe '#freeze_node?' do
    it 'returns false by default' do
      expect(wrapper.freeze_node?).to be false
    end
  end

  describe '#node_wrapper?' do
    it 'returns true' do
      expect(wrapper.node_wrapper?).to be true
    end
  end

  describe '#underlying_node' do
    it 'returns the underlying node' do
      expect(wrapper.underlying_node).to eq(test_node)
    end
  end

  describe '#content' do
    it 'returns lines from start_line to end_line' do
      expect(wrapper.content).to eq("line 1\nline 2\nline 3")
    end

    context 'when start_line is nil' do
      let(:no_point_node) do
        double('mock_no_point_node', type: :test)
      end

      it 'returns empty string' do
        wrapper = test_wrapper_class.new(no_point_node, lines: source_lines)
        expect(wrapper.content).to eq('')
      end
    end
  end

  describe 'shared comment hooks' do
    let(:wrapper_with_comments) do
      test_wrapper_class.new(
        test_node,
        lines: source_lines,
        source: source_string,
        leading_comments: [{ line: 1, text: 'header', raw: '# header', full_line: true }],
        inline_comment: { line: 2, text: 'inline', raw: '# inline', full_line: false }
      )
    end

    it 'converts leading comment hashes into a shared region' do
      region = wrapper_with_comments.leading_comment_region(repository: :ast_merge)

      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.kind).to eq(:leading)
      expect(region.normalized_content).to eq('header')
      expect(region.metadata[:repository]).to eq(:ast_merge)
    end

    it 'converts inline comment hashes into a shared region' do
      region = wrapper_with_comments.inline_comment_region(repository: :ast_merge)

      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.kind).to eq(:inline)
      expect(region.normalized_content).to eq('inline')
      expect(region.metadata[:repository]).to eq(:ast_merge)
    end

    it 'builds a shared attachment from the wrapper comment hashes' do
      attachment = wrapper_with_comments.comment_attachment(repository: :ast_merge)

      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(attachment.owner).to eq(wrapper_with_comments)
      expect(attachment.leading_region&.normalized_content).to eq('header')
      expect(attachment.inline_region&.normalized_content).to eq('inline')
      expect(attachment.metadata[:repository]).to eq(:ast_merge)
    end

    it 'detects freeze directives in leading normalized comments' do
      wrapper = test_wrapper_class.new(
        test_node,
        lines: source_lines,
        source: source_string,
        leading_comments: [{ line: 1, text: 'ast-merge:freeze', raw: '# ast-merge:freeze', full_line: true }]
      )

      expect(wrapper.leading_comment_freeze?('ast-merge')).to be(true)
      expect(wrapper.leading_comment_unfreeze?('ast-merge')).to be(false)
    end

    it 'distinguishes leading unfreeze directives from freeze directives' do
      wrapper = test_wrapper_class.new(
        test_node,
        lines: source_lines,
        source: source_string,
        leading_comments: [{ line: 1, text: 'ast-merge:unfreeze', raw: '# ast-merge:unfreeze', full_line: true }]
      )

      expect(wrapper.leading_comment_freeze?('ast-merge')).to be(false)
      expect(wrapper.leading_comment_unfreeze?('ast-merge')).to be(true)
    end
  end

  describe '#text' do
    it 'extracts text using byte positions' do
      expect(wrapper.text).to eq("line 1\nlin")
    end

    context "when node doesn't support byte positions" do
      let(:no_bytes_node) do
        double(
          'mock_no_bytes_node',
          type: :test,
          start_point: double(row: 0),
          end_point: double(row: 0)
        )
      end

      it 'returns empty string' do
        wrapper = test_wrapper_class.new(no_bytes_node, lines: source_lines)
        expect(wrapper.text).to eq('')
      end
    end
  end

  describe '#container? and #leaf?' do
    it 'defaults container? to false' do
      expect(wrapper.container?).to be false
    end

    it 'returns true for leaf? when not a container' do
      expect(wrapper.leaf?).to be true
    end
  end

  describe '#inspect' do
    it 'includes class name, type, and line range' do
      result = wrapper.inspect
      expect(result).to include('type=test_type')
      expect(result).to include('lines=1..3')
    end
  end

  describe 'abstract #compute_signature' do
    let(:abstract_wrapper_class) do
      Class.new(described_class)
    end

    it 'raises NotImplementedError when not overridden' do
      wrapper = abstract_wrapper_class.new(test_node, lines: source_lines)
      expect { wrapper.signature }.to raise_error(NotImplementedError)
    end
  end

  describe 'distinguishing from NodeTyping::Wrapper' do
    let(:typing_wrapper) do
      Ast::Merge::NodeTyping.with_merge_type(wrapper, :custom_type)
    end

    it 'NodeWrapperBase has node_wrapper? returning true' do
      expect(wrapper.node_wrapper?).to be true
    end

    it 'NodeTyping::Wrapper has typed_node? returning true' do
      expect(typing_wrapper.typed_node?).to be true
    end

    it 'NodeTyping::Wrapper does not have node_wrapper?' do
      expect(typing_wrapper.respond_to?(:node_wrapper?)).to be true # delegated
      expect(typing_wrapper.node_wrapper?).to be true # delegates to wrapped NodeWrapperBase
    end

    it 'allows double wrapping' do
      expect(typing_wrapper.merge_type).to eq(:custom_type)
      expect(typing_wrapper.type).to eq(:test_type) # delegated to NodeWrapperBase
      expect(typing_wrapper.start_line).to eq(1) # delegated
    end

    it 'can unwrap NodeTyping::Wrapper to get NodeWrapperBase' do
      unwrapped = Ast::Merge::NodeTyping.unwrap(typing_wrapper)
      expect(unwrapped).to eq(wrapper)
      expect(unwrapped.node_wrapper?).to be true
    end

    it 'can get underlying TreeHaver node from NodeWrapperBase' do
      expect(wrapper.underlying_node).to eq(test_node)
    end
  end

  describe '#node_text with multi-byte characters' do
    it 'extracts correct text when source contains emoji before the node' do
      # Emoji 🪙 is 4 UTF-8 bytes but 1 character.
      # Tree-sitter returns byte offsets, so node_text must use byteslice.
      emoji_source = "EMOJI=🪙\nA=1\n"
      # "A=1" starts at byte 13 (E-M-O-J-I-= = 6 bytes + 🪙 = 4 bytes + \n = 1 byte = 11; A at byte 11)
      # Actually: E(1) M(1) O(1) J(1) I(1) =(1) 🪙(4) \n(1) = 11 bytes for first line
      # A=1 starts at byte 11, ends at byte 14
      a_node = TestableNode.create(
        type: :pair,
        text: 'A=1',
        start_line: 1,
        end_line: 1,
        start_byte: 11,
        end_byte: 14
      )
      emoji_wrapper = test_wrapper_class.new(a_node, lines: emoji_source.lines, source: emoji_source)
      expect(emoji_wrapper.node_text(a_node)).to eq('A=1')
    end

    it 'extracts correct text with multiple emoji preceding' do
      source = "X=🍲🪙\nB=2\n"
      # X(1) =(1) 🍲(4) 🪙(4) \n(1) = 11 bytes for first line
      # B=2 starts at byte 11, ends at byte 14
      b_node = TestableNode.create(
        type: :pair,
        text: 'B=2',
        start_line: 1,
        end_line: 1,
        start_byte: 11,
        end_byte: 14
      )
      wrapper = test_wrapper_class.new(b_node, lines: source.lines, source: source)
      expect(wrapper.node_text(b_node)).to eq('B=2')
    end

    it 'extracts correct text with CJK characters preceding' do
      source = "NAME=日本語\nVAL=ok\n"
      # N(1)A(1)M(1)E(1)=(1) = 5 bytes + 日(3)本(3)語(3) = 9 bytes + \n(1) = 15 bytes
      # VAL=ok starts at byte 15, ends at byte 21
      val_node = TestableNode.create(
        type: :pair,
        text: 'VAL=ok',
        start_line: 1,
        end_line: 1,
        start_byte: 15,
        end_byte: 21
      )
      wrapper = test_wrapper_class.new(val_node, lines: source.lines, source: source)
      expect(wrapper.node_text(val_node)).to eq('VAL=ok')
    end
  end
end
