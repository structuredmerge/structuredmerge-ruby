# frozen_string_literal: true

RSpec.describe Ast::Merge::StructuralEdit::SplicePlan do
  let(:source) do
    <<~TEXT
      # Before

      ## Section
      Old body


      # After
    TEXT
  end

  describe '#merged_content' do
    it 'preserves untouched source outside the replaced line range exactly' do
      plan = described_class.new(
        source: source,
        replacement: "## Section\nNew body\n",
        replace_start_line: 3,
        replace_end_line: 4
      )

      expect(plan.before_content).to eq("# Before\n\n")
      expect(plan.removed_content).to eq("## Section\nOld body\n")
      expect(plan.after_content).to eq("\n\n# After\n")
      expect(plan.merged_content).to eq("# Before\n\n## Section\nNew body\n\n\n# After\n")
    end

    it 'reports unchanged when the replacement matches the removed content' do
      plan = described_class.new(
        source: source,
        replacement: "## Section\nOld body\n",
        replace_start_line: 3,
        replace_end_line: 4
      )

      expect(plan.changed?).to be false
    end

    it 'preserves a trailing blank-line separator owned by the removed range when following content starts immediately' do
      source = <<~TEXT
        ## Section
        Old body

        ## After
      TEXT

      plan = described_class.new(
        source: source,
        replacement: "## Section\nNew body\n",
        replace_start_line: 1,
        replace_end_line: 3
      )

      expect(plan.merged_content).to eq("## Section\nNew body\n\n## After\n")
    end

    it 'can disable preserved trailing blank-line separators for exact range deletion callers' do
      source = <<~TEXT
        ## Section
        Old body

        ## After
      TEXT

      plan = described_class.new(
        source: source,
        replacement: "## Section\nNew body\n",
        replace_start_line: 1,
        replace_end_line: 3,
        preserve_removed_trailing_blank_lines: false
      )

      expect(plan.merged_content).to eq("## Section\nNew body\n## After\n")
    end

    # The junction invariant: a splice must not emit a blank-line run longer than
    # any single contributor already had. Deletion is what exposes it -- the
    # separator that preceded the removed range and the separator that followed
    # it become adjacent once the range's own text is gone.
    it 'does not stack the junction blanks when an empty replacement removes a range' do
      source = <<~TEXT
        ## Section
        Old body

        ## After
      TEXT

      plan = described_class.new(
        source: source,
        replacement: '',
        replace_start_line: 1,
        replace_end_line: 3
      )

      expect(plan.merged_content).to eq("## After\n")
    end

    it 'caps a junction where both sides of the removed range had a blank' do
      source = "# Before\n\n## Section\nOld body\n\n# After\n"

      plan = described_class.new(
        source: source,
        replacement: '',
        replace_start_line: 3,
        replace_end_line: 5
      )

      # One blank survives, matching the source's own section separator; two
      # would be a separator the source never had.
      expect(plan.merged_content).to eq("# Before\n\n# After\n")
    end

    it 'keeps a longer junction blank run that the source already had on one side' do
      source = "# Before\n\n\n## Section\nOld body\n\n# After\n"

      plan = described_class.new(
        source: source,
        replacement: '',
        replace_start_line: 4,
        replace_end_line: 6
      )

      # The cap is the longest contributing run, not a flat single blank.
      expect(plan.merged_content).to eq("# Before\n\n\n# After\n")
    end

    # The range's trailing blank belongs to the removed owner. With nothing
    # spliced in to separate, re-emitting it invents a blank the source never had
    # -- a leading one when the range starts the file.
    it 'does not invent a leading blank when removing a range at the start of the file' do
      source = "## Section\nOld body\n\n## After\n"

      plan = described_class.new(
        source: source,
        replacement: '',
        replace_start_line: 1,
        replace_end_line: 3
      )

      expect(plan.merged_content).to eq("## After\n")
    end
  end

  describe 'validation' do
    it 'rejects a replace range that extends beyond the source' do
      expect do
        described_class.new(
          source: source,
          replacement: 'x',
          replace_start_line: 3,
          replace_end_line: 99
        )
      end.to raise_error(ArgumentError, /exceeds source line count/)
    end
  end

  describe Ast::Merge::StructuralEdit::Boundary do
    it 'exposes layout gaps and comment regions from passive attachments' do
      owner = Struct.new(:label).new(:survivor)
      gap = instance_double(Ast::Merge::Layout::Gap)
      region = instance_double(Ast::Merge::Comment::Region)
      layout_attachment = instance_double(Ast::Merge::Layout::Attachment, gaps: [gap])
      comment_attachment = instance_double(Ast::Merge::Comment::Attachment, regions: [region])

      boundary = described_class.new(
        edge: :leading,
        owner: owner,
        layout_attachment: layout_attachment,
        comment_attachment: comment_attachment
      )

      expect(boundary).to be_leading
      expect(boundary.gaps).to eq([gap])
      expect(boundary.regions).to eq([region])
    end
  end
end
