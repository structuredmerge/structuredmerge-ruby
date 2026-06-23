# frozen_string_literal: true

RSpec.describe Ast::Merge::StructuralEdit::RemovePlan do
  let(:survivor_before) { Struct.new(:label).new(:before) }
  let(:survivor_after) { Struct.new(:label).new(:after) }
  let(:removed_owner) { Struct.new(:label).new(:removed) }
  let(:leading_boundary) { Ast::Merge::StructuralEdit::Boundary.new(edge: :leading, owner: survivor_before) }
  let(:trailing_boundary) { Ast::Merge::StructuralEdit::Boundary.new(edge: :trailing, owner: survivor_after) }

  describe 'source-preserving removal' do
    let(:source) do
      <<~TEXT
        # Before

        ## Section
        Old body

        ## After
      TEXT
    end

    it 'removes the requested line range while preserving untouched source exactly' do
      plan = described_class.new(
        source: source,
        remove_start_line: 3,
        remove_end_line: 5,
        leading_boundary: leading_boundary,
        trailing_boundary: trailing_boundary
      )

      expect(plan.before_content).to eq("# Before\n\n")
      expect(plan.removed_content).to eq("## Section\nOld body\n\n")
      expect(plan.after_content).to eq("## After\n")
      expect(plan.merged_content).to eq("# Before\n\n\n## After\n")
      expect(plan.changed?).to be true
    end
  end

  describe 'rehome planning' do
    let(:leading_region) { instance_double(Ast::Merge::Comment::Region) }
    let(:inline_region) { instance_double(Ast::Merge::Comment::Region) }
    let(:orphan_region) { instance_double(Ast::Merge::Comment::Region) }
    let(:trailing_region) { instance_double(Ast::Merge::Comment::Region) }
    let(:leading_gap) { instance_double(Ast::Merge::Layout::Gap) }
    let(:trailing_gap) { instance_double(Ast::Merge::Layout::Gap) }
    let(:removed_attachment) do
      Ast::Merge::Comment::Attachment.new(
        owner: removed_owner,
        leading_region: leading_region,
        inline_region: inline_region,
        trailing_region: trailing_region,
        orphan_regions: [orphan_region],
        leading_gap: leading_gap,
        trailing_gap: trailing_gap
      )
    end

    it 'derives retained and removed owners and splits promoted fragments by surviving boundary side' do
      plan = described_class.new(
        source: "before\nremove\nafter\n",
        remove_start_line: 2,
        remove_end_line: 2,
        leading_boundary: leading_boundary,
        trailing_boundary: trailing_boundary,
        removed_attachments: [removed_attachment]
      )

      expect(plan.retained_owners).to eq([survivor_before, survivor_after])
      expect(plan.removed_owners).to eq([removed_owner])
      expect(plan.promoted_comment_regions).to eq([leading_region, inline_region, orphan_region, trailing_region])
      expect(plan.promoted_layout_gaps).to eq([leading_gap, trailing_gap])
      expect(plan.rehome_plans.size).to eq(3)

      leading_plan = plan.rehome_plans[0]
      ambiguous_plan = plan.rehome_plans[1]
      trailing_plan = plan.rehome_plans[2]

      expect(leading_plan.target_owner).to equal(survivor_before)
      expect(leading_plan.comment_attachment.trailing_region).to equal(leading_region)
      expect(leading_plan.layout_attachment.trailing_gap).to equal(leading_gap)

      expect(ambiguous_plan.target_owner).to equal(survivor_before)
      expect(ambiguous_plan.comment_attachment.trailing_region).to equal(inline_region)
      expect(ambiguous_plan.comment_attachment.orphan_regions).to eq([orphan_region])

      expect(trailing_plan.target_owner).to equal(survivor_after)
      expect(trailing_plan.comment_attachment.leading_region).to equal(trailing_region)
      expect(trailing_plan.layout_attachment.leading_gap).to equal(trailing_gap)
    end

    it 'falls back to the surviving trailing boundary when no leading boundary exists' do
      plan = described_class.new(
        source: "before\nremove\nafter\n",
        remove_start_line: 2,
        remove_end_line: 2,
        trailing_boundary: trailing_boundary,
        removed_attachments: [
          Ast::Merge::Comment::Attachment.new(
            owner: removed_owner,
            leading_region: leading_region,
            leading_gap: leading_gap
          )
        ]
      )

      expect(plan.rehome_plans.size).to eq(1)
      expect(plan.rehome_plans.first.target_owner).to equal(survivor_after)
      expect(plan.rehome_plans.first.comment_attachment.leading_region).to equal(leading_region)
      expect(plan.rehome_plans.first.layout_attachment.leading_gap).to equal(leading_gap)
    end

    it 'ignores empty removed attachments and produces no rehome plans when nothing survives' do
      plan = described_class.new(
        source: "before\nremove\nafter\n",
        remove_start_line: 2,
        remove_end_line: 2,
        leading_boundary: leading_boundary,
        removed_attachments: [Ast::Merge::Comment::Attachment.new(owner: removed_owner)]
      )

      expect(plan.rehome_plans).to eq([])
      expect(plan.promoted_comment_regions).to eq([])
      expect(plan.promoted_layout_gaps).to eq([])
    end
  end

  describe Ast::Merge::StructuralEdit::RehomePlan do
    let(:source_owner) { Struct.new(:label).new(:removed) }
    let(:target_owner) { Struct.new(:label).new(:survivor) }
    let(:region) { instance_double(Ast::Merge::Comment::Region) }
    let(:gap) { instance_double(Ast::Merge::Layout::Gap) }

    it 'retargets promoted fragments onto the trailing side of a leading boundary owner' do
      boundary = Ast::Merge::StructuralEdit::Boundary.new(edge: :leading, owner: target_owner)

      plan = described_class.new(
        source_owner: source_owner,
        target_boundary: boundary,
        comment_regions: [region],
        layout_gaps: [gap]
      )

      expect(plan).to be_leading
      expect(plan.target_owner).to equal(target_owner)
      expect(plan.comment_attachment.trailing_region).to equal(region)
      expect(plan.layout_attachment.trailing_gap).to equal(gap)
    end

    it 'retargets promoted fragments onto the leading side of a trailing boundary owner' do
      boundary = Ast::Merge::StructuralEdit::Boundary.new(edge: :trailing, owner: target_owner)

      plan = described_class.new(
        source_owner: source_owner,
        target_boundary: boundary,
        comment_regions: [region],
        layout_gaps: [gap]
      )

      expect(plan).to be_trailing
      expect(plan.comment_attachment.leading_region).to equal(region)
      expect(plan.layout_attachment.leading_gap).to equal(gap)
    end
  end
end
