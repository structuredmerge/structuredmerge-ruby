# frozen_string_literal: true

RSpec.describe Ast::Merge::StructuralEdit::RemovePlanSupport do
  let(:node_class) { Struct.new(:label, :source_position, keyword_init: true) }
  let(:analysis_class) do
    Class.new do
      attr_reader :source

      def initialize(source:, comment_attachments: {}, layout_attachments: {})
        @source = source
        @comment_attachments = comment_attachments
        @layout_attachments = layout_attachments
      end

      def comment_attachment_for(owner)
        @comment_attachments.fetch(owner.object_id) do
          Ast::Merge::Comment::Attachment.new(owner: owner)
        end
      end

      def layout_attachment_for(owner)
        @layout_attachments.fetch(owner.object_id) do
          Ast::Merge::Layout::Attachment.new(owner: owner)
        end
      end
    end
  end

  describe '.build_remove_plan' do
    it 'builds a shared RemovePlan from a contiguous statement run plus explicit neighbors' do
      before_node = node_class.new(label: :before, source_position: { start_line: 1, end_line: 1 })
      removed_node = node_class.new(label: :removed, source_position: { start_line: 3, end_line: 4 })
      after_node = node_class.new(label: :after, source_position: { start_line: 6, end_line: 6 })
      promoted_region = instance_double(Ast::Merge::Comment::Region)
      analysis = analysis_class.new(
        source: "before\n\nremoved\nbody\n\nafter\n",
        comment_attachments: {
          removed_node.object_id => Ast::Merge::Comment::Attachment.new(
            owner: removed_node,
            leading_region: promoted_region
          )
        }
      )

      remove_plan = described_class.build_remove_plan(
        analysis: analysis,
        statements: Ast::Merge::Navigable::Statement.build_list([removed_node]),
        leading_statement: Ast::Merge::Navigable::Statement.build_list([before_node]).first,
        trailing_statement: Ast::Merge::Navigable::Statement.build_list([after_node]).first,
        source: :remove_plan_support_spec
      )

      expect(remove_plan).to be_a(Ast::Merge::StructuralEdit::RemovePlan)
      expect(remove_plan.remove_start_line).to eq(3)
      expect(remove_plan.remove_end_line).to eq(4)
      expect(remove_plan.leading_boundary.owner).to equal(before_node)
      expect(remove_plan.trailing_boundary.owner).to equal(after_node)
      expect(remove_plan.removed_attachments.map(&:owner)).to eq([removed_node])
      expect(remove_plan.metadata).to include(source: :remove_plan_support_spec)
    end

    it 'returns nil when the statement run has no usable line range' do
      analysis = analysis_class.new(source: "one\n")
      unpositioned = Struct.new(:label).new(:missing)

      remove_plan = described_class.build_remove_plan(
        analysis: analysis,
        statements: [unpositioned],
        source: :remove_plan_support_spec
      )

      expect(remove_plan).to be_nil
    end
  end
end
