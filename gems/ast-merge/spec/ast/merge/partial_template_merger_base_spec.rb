# frozen_string_literal: true

RSpec.describe Ast::Merge::PartialTemplateMergerBase do
  before do
    stub_const('FakeNode', Struct.new(:text, :source_position, keyword_init: true))
    stub_const('FakeAnalysis', Class.new do
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
    end)
  end

  let(:merger_class) do
    Class.new(described_class) do
      def create_analysis(content)
        content
      end

      def create_smart_merger(template_content, destination_content)
        Struct.new(:merge_result).new(
          Struct.new(:content, :stats).new(template_content,
                                           { template: template_content, destination: destination_content })
        )
      end

      def find_section_end(_statements, injection_point)
        injection_point.anchor.index
      end

      def node_to_text(node, analysis = nil)
        pos = node.respond_to?(:source_position) ? node.source_position : nil
        if analysis&.respond_to?(:source) && pos
          analysis.source.lines[(pos[:start_line] - 1)..(pos[:end_line] - 1)].join
        else
          [node, analysis].compact.join('|')
        end
      end
    end
  end

  let(:merger) do
    merger_class.new(
      template: "template section\n",
      destination: "destination document\n",
      anchor: { type: :heading, text: /Section/ }
    )
  end

  describe '#build_merged_content' do
    it 'normalizes separators to a single blank line between before, section, and after content' do
      result = merger.send(
        :build_merged_content,
        "# Before\n\n\n",
        "## Section\nBody\n\n",
        "# After\n\n"
      )

      expect(result).to eq("# Before\n\n## Section\nBody\n\n# After\n")
    end

    it 'does not prepend a separator when only section content exists' do
      result = merger.send(:build_merged_content, '', "## Section\n", nil)

      expect(result).to eq("## Section\n")
    end

    it 'joins before and after with one blank line when the merged section is empty' do
      result = merger.send(:build_merged_content, "# Before\n", '', "# After\n")

      expect(result).to eq("# Before\n\n# After\n")
    end

    it 'returns an empty string when all content parts are blank' do
      result = merger.send(:build_merged_content, '', "\n", nil)

      expect(result).to eq('')
    end
  end

  describe 'source-backed structural recomposition' do
    it 'preserves exact surrounding destination whitespace when statement line ranges are available' do
      destination = <<~MD
        # Before


        ## Section
        Old body



        # After
      MD

      analysis = FakeAnalysis.new(source: destination)
      statements = Ast::Merge::Navigable::Statement.build_list([
                                                                 FakeNode.new(text: '# Before',
                                                                              source_position: {
                                                                                start_line: 1, end_line: 1
                                                                              }),
                                                                 FakeNode.new(text: '## Section',
                                                                              source_position: {
                                                                                start_line: 4, end_line: 5
                                                                              }),
                                                                 FakeNode.new(text: '# After',
                                                                              source_position: {
                                                                                start_line: 9, end_line: 9
                                                                              })
                                                               ])
      injection_point = Struct.new(:anchor).new(statements[1])
      source_preserving_merger = merger_class.new(
        template: "## Section\nNew body\n",
        destination: destination,
        anchor: { type: :heading, text: /Section/ },
        replace_mode: true
      )

      result = source_preserving_merger.send(:perform_section_merge, analysis, statements, injection_point)

      expect(result.content).to eq("# Before\n\n\n## Section\nNew body\n\n\n\n# After\n")
    end

    it 'builds a source-backed remove plan for the replaced section with preserved removed attachments' do
      destination = <<~MD
        # Before

        ## Section
        Old body

        # After
      MD

      removed_node = FakeNode.new(text: '## Section', source_position: { start_line: 3, end_line: 4 })
      before_node = FakeNode.new(text: '# Before', source_position: { start_line: 1, end_line: 1 })
      after_node = FakeNode.new(text: '# After', source_position: { start_line: 6, end_line: 6 })
      promoted_region = instance_double(Ast::Merge::Comment::Region)
      promoted_gap = instance_double(Ast::Merge::Layout::Gap)
      removed_attachment = Ast::Merge::Comment::Attachment.new(
        owner: removed_node,
        leading_region: promoted_region,
        leading_gap: promoted_gap
      )
      analysis = FakeAnalysis.new(
        source: destination,
        comment_attachments: { removed_node.object_id => removed_attachment }
      )
      statements = Ast::Merge::Navigable::Statement.build_list([
                                                                 before_node,
                                                                 removed_node,
                                                                 after_node
                                                               ])

      remove_plan = merger.send(
        :source_remove_plan_for,
        analysis: analysis,
        statements: statements,
        section_start_idx: 1,
        section_end_idx: 1
      )

      expect(remove_plan).to be_a(Ast::Merge::StructuralEdit::RemovePlan)
      expect(remove_plan.remove_start_line).to eq(3)
      expect(remove_plan.remove_end_line).to eq(4)
      expect(remove_plan.removed_attachments).to eq([removed_attachment])
      expect(remove_plan.rehome_plans.size).to eq(1)
      expect(remove_plan.rehome_plans.first.target_owner).to equal(before_node)
      expect(remove_plan.rehome_plans.first.comment_attachment.trailing_region).to equal(promoted_region)
      expect(remove_plan.rehome_plans.first.layout_attachment.trailing_gap).to equal(promoted_gap)
    end
  end
end
