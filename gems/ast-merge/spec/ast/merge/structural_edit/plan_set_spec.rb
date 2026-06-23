# frozen_string_literal: true

RSpec.describe Ast::Merge::StructuralEdit::PlanSet do
  let(:source) do
    <<~TEXT
      alpha
      beta
      gamma
      delta
      epsilon
    TEXT
  end

  describe '#merged_content' do
    it 'applies multiple non-overlapping splice plans against the same original source' do
      first = Ast::Merge::StructuralEdit::SplicePlan.new(
        source: source,
        replacement: "BETA\n",
        replace_start_line: 2,
        replace_end_line: 2
      )
      second = Ast::Merge::StructuralEdit::SplicePlan.new(
        source: source,
        replacement: "EPSILON\nZETA\n",
        replace_start_line: 5,
        replace_end_line: 5
      )

      plan_set = described_class.new(source: source, plans: [first, second])

      expect(plan_set.merged_content).to eq(
        <<~TEXT
          alpha
          BETA
          gamma
          delta
          EPSILON
          ZETA
        TEXT
      )
      expect(plan_set).to be_changed
    end

    it 'normalizes remove plans via #to_splice_plan' do
      remove = Ast::Merge::StructuralEdit::RemovePlan.new(
        source: source,
        remove_start_line: 2,
        remove_end_line: 3
      )
      replace = Ast::Merge::StructuralEdit::SplicePlan.new(
        source: source,
        replacement: "EPSILON\n",
        replace_start_line: 5,
        replace_end_line: 5
      )

      plan_set = described_class.new(source: source, plans: [remove, replace])

      expect(plan_set.merged_content).to eq(
        <<~TEXT
          alpha
          delta
          EPSILON
        TEXT
      )
    end

    it 'applies plans in descending line order so original-source coordinates stay valid' do
      late = Ast::Merge::StructuralEdit::SplicePlan.new(
        source: source,
        replacement: "delta\nDELTA-2\n",
        replace_start_line: 4,
        replace_end_line: 4
      )
      early = Ast::Merge::StructuralEdit::SplicePlan.new(
        source: source,
        replacement: "ALPHA\n",
        replace_start_line: 1,
        replace_end_line: 1
      )

      plan_set = described_class.new(source: source, plans: [early, late])

      expect(plan_set.merged_content).to eq(
        <<~TEXT
          ALPHA
          beta
          gamma
          delta
          DELTA-2
          epsilon
        TEXT
      )
    end
  end

  describe 'metadata aggregation' do
    it 'exposes promoted fragments from remove plans' do
      owner_before = Struct.new(:label).new(:before)
      owner_after = Struct.new(:label).new(:after)
      removed_owner = Struct.new(:label).new(:removed)
      region = instance_double(Ast::Merge::Comment::Region)
      gap = instance_double(Ast::Merge::Layout::Gap)

      remove = Ast::Merge::StructuralEdit::RemovePlan.new(
        source: source,
        remove_start_line: 2,
        remove_end_line: 2,
        leading_boundary: Ast::Merge::StructuralEdit::Boundary.new(edge: :leading, owner: owner_before),
        trailing_boundary: Ast::Merge::StructuralEdit::Boundary.new(edge: :trailing, owner: owner_after),
        removed_attachments: [
          Ast::Merge::Comment::Attachment.new(
            owner: removed_owner,
            leading_region: region,
            leading_gap: gap
          )
        ]
      )

      plan_set = described_class.new(source: source, plans: [remove])

      expect(plan_set.rehome_plans.length).to eq(1)
      expect(plan_set.promoted_comment_regions).to eq([region])
      expect(plan_set.promoted_layout_gaps).to eq([gap])
    end
  end

  describe 'validation' do
    it 'rejects plans with different source text' do
      first = Ast::Merge::StructuralEdit::SplicePlan.new(
        source: source,
        replacement: "BETA\n",
        replace_start_line: 2,
        replace_end_line: 2
      )
      second = Ast::Merge::StructuralEdit::SplicePlan.new(
        source: "other\nsource\n",
        replacement: "x\n",
        replace_start_line: 1,
        replace_end_line: 1
      )

      expect do
        described_class.new(source: source, plans: [first, second])
      end.to raise_error(ArgumentError, /must share the same source/)
    end

    it 'rejects overlapping plans' do
      first = Ast::Merge::StructuralEdit::SplicePlan.new(
        source: source,
        replacement: "BETA\n",
        replace_start_line: 2,
        replace_end_line: 3
      )
      second = Ast::Merge::StructuralEdit::SplicePlan.new(
        source: source,
        replacement: "GAMMA\n",
        replace_start_line: 3,
        replace_end_line: 4
      )

      expect do
        described_class.new(source: source, plans: [first, second])
      end.to raise_error(ArgumentError, /must not overlap/)
    end

    it 'rejects objects that are not splice-compatible' do
      expect do
        described_class.new(source: source, plans: [Object.new])
      end.to raise_error(ArgumentError, /SplicePlan instances or respond to #to_splice_plan/)
    end
  end

  describe Ast::Merge::StructuralEdit::SplicePlan do
    describe '#apply_to' do
      it 'applies the same line-range replacement to alternate source text' do
        original = "one\ntwo\nthree\n"
        plan = described_class.new(
          source: original,
          replacement: "TWO\n",
          replace_start_line: 2,
          replace_end_line: 2
        )

        expect(plan.apply_to("one\nsecond\nthree\n")).to eq("one\nTWO\nthree\n")
      end
    end
  end

  describe Ast::Merge::StructuralEdit::RemovePlan do
    describe '#to_splice_plan' do
      it 'exposes a splice-compatible representation with an empty replacement' do
        plan = described_class.new(
          source: "one\ntwo\nthree\n",
          remove_start_line: 2,
          remove_end_line: 2
        )

        splice_plan = plan.to_splice_plan
        expect(splice_plan).to be_a(Ast::Merge::StructuralEdit::SplicePlan)
        expect(splice_plan.replacement).to eq('')
        expect(plan.apply_to).to eq("one\nthree\n")
      end
    end
  end
end
