# frozen_string_literal: true

RSpec.describe Ast::Merge::StructuralEdit::BoundarySupport do
  let(:node_class) { Struct.new(:label, :source_position, keyword_init: true) }
  let(:node_with_lines_class) { Struct.new(:label, :start_line, :end_line, keyword_init: true) }
  let(:analysis_class) do
    Class.new do
      attr_reader :comment_attachments, :layout_attachments

      def initialize(comment_attachments: {}, layout_attachments: {})
        @comment_attachments = comment_attachments
        @layout_attachments = layout_attachments
      end

      def comment_attachment_for(owner)
        comment_attachments.fetch(owner.object_id) do
          Ast::Merge::Comment::Attachment.new(owner: owner)
        end
      end

      def layout_attachment_for(owner)
        layout_attachments.fetch(owner.object_id) do
          Ast::Merge::Layout::Attachment.new(owner: owner)
        end
      end
    end
  end

  describe '.build_splice_boundary' do
    it 'unwraps Navigable::Statement owners and preserves shared attachments' do
      node = node_class.new(label: :section, source_position: { start_line: 3, end_line: 4 })
      statement = Ast::Merge::Navigable::Statement.build_list([node]).first
      comment_attachment = Ast::Merge::Comment::Attachment.new(owner: node)
      layout_attachment = Ast::Merge::Layout::Attachment.new(owner: node)
      analysis = analysis_class.new(
        comment_attachments: { node.object_id => comment_attachment },
        layout_attachments: { node.object_id => layout_attachment }
      )

      boundary = described_class.build_splice_boundary(
        analysis,
        statement,
        edge: :leading,
        source: :boundary_support_spec
      )

      expect(boundary).to be_a(Ast::Merge::StructuralEdit::Boundary)
      expect(boundary.owner).to equal(node)
      expect(boundary.comment_attachment).to equal(comment_attachment)
      expect(boundary.layout_attachment).to equal(layout_attachment)
      expect(boundary.metadata).to include(source: :boundary_support_spec)
    end

    it 'returns nil when no statement is provided' do
      expect(described_class.build_splice_boundary(analysis_class.new, nil, edge: :leading)).to be_nil
    end
  end

  describe '.removed_statement_attachments_for' do
    it 'returns only attachments that preserve fragments' do
      first = node_class.new(label: :first, source_position: { start_line: 1, end_line: 1 })
      second = node_class.new(label: :second, source_position: { start_line: 2, end_line: 2 })
      promoted_region = instance_double(Ast::Merge::Comment::Region)
      promoted_gap = instance_double(Ast::Merge::Layout::Gap)

      fragment_comment_attachment = Ast::Merge::Comment::Attachment.new(
        owner: first,
        leading_region: promoted_region
      )
      empty_comment_attachment = Ast::Merge::Comment::Attachment.new(owner: second)
      fragment_layout_attachment = Ast::Merge::Layout::Attachment.new(
        owner: second,
        leading_gap: promoted_gap
      )

      analysis = analysis_class.new(
        comment_attachments: {
          first.object_id => fragment_comment_attachment,
          second.object_id => empty_comment_attachment
        },
        layout_attachments: {
          second.object_id => fragment_layout_attachment
        }
      )

      attachments = described_class.removed_statement_attachments_for(analysis, [first, second])

      expect(attachments).to eq([fragment_comment_attachment, fragment_layout_attachment])
    end
  end

  describe '.statement_start_line / .statement_end_line' do
    it 'supports explicit line readers and source_position hashes' do
      with_lines = node_with_lines_class.new(label: :explicit, start_line: 7, end_line: 9)
      with_position = node_class.new(label: :positioned, source_position: { start_line: 11, end_line: 13 })
      wrapped_statement = Ast::Merge::Navigable::Statement.build_list([with_position]).first

      expect(described_class.statement_start_line(with_lines)).to eq(7)
      expect(described_class.statement_end_line(with_lines)).to eq(9)
      expect(described_class.statement_start_line(wrapped_statement)).to eq(11)
      expect(described_class.statement_end_line(wrapped_statement)).to eq(13)
    end
  end
end
