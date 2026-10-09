# frozen_string_literal: true

require 'spec_helper'

# Style/WordArray offers %w[\n \n] for the newline arrays asserted below, but %w
# does not interpret escapes: that is a two-character literal backslash-n, not a
# newline byte. The chunks under test are real "\n" strings, so the double-quoted
# form is correct throughout this file and the cop's suggestion would silently
# weaken every one of these assertions.
# rubocop:disable Style/WordArray
RSpec.describe Ast::Merge::StructuralEdit::BlankLineSupport do
  describe '.trailing_blank_line_chunks' do
    it 'returns the trailing blank lines in source order, newlines intact' do
      expect(described_class.trailing_blank_line_chunks("body\n\n\n")).to eq(["\n", "\n"])
    end

    it 'returns nothing when the text ends in content' do
      expect(described_class.trailing_blank_line_chunks("body\n")).to eq([])
    end

    it 'treats whitespace-only lines as blank' do
      expect(described_class.trailing_blank_line_chunks("body\n   \n")).to eq(["   \n"])
    end

    it 'returns nothing for empty text' do
      expect(described_class.trailing_blank_line_chunks('')).to eq([])
    end
  end

  describe '.leading_blank_line_chunks' do
    it 'returns the leading blank lines in source order' do
      expect(described_class.leading_blank_line_chunks("\n\nbody\n")).to eq(["\n", "\n"])
    end

    it 'returns nothing when the text opens with content' do
      expect(described_class.leading_blank_line_chunks("body\n\n")).to eq([])
    end
  end

  describe '.missing_trailing_blank_line_chunks' do
    it 'returns the separator the replacement would otherwise lose' do
      chunks = described_class.missing_trailing_blank_line_chunks(
        removed_content: "## Section\nBody\n\n",
        replacement: "## Section\nNew body\n",
        after_content: "## After\n"
      )

      expect(chunks).to eq(["\n"])
    end

    it 'returns nothing when the replacement already ends in enough blanks' do
      chunks = described_class.missing_trailing_blank_line_chunks(
        removed_content: "## Section\nBody\n\n",
        replacement: "## Section\nNew body\n\n",
        after_content: "## After\n"
      )

      expect(chunks).to eq([])
    end

    it 'returns nothing when the tail already opens with a blank' do
      chunks = described_class.missing_trailing_blank_line_chunks(
        removed_content: "## Section\nBody\n\n",
        replacement: "## Section\nNew body\n",
        after_content: "\n## After\n"
      )

      expect(chunks).to eq([])
    end

    it 'returns nothing when the removed range had no trailing blank' do
      chunks = described_class.missing_trailing_blank_line_chunks(
        removed_content: "## Section\nBody\n",
        replacement: "## Section\nNew body\n",
        after_content: "## After\n"
      )

      expect(chunks).to eq([])
    end
  end

  # The junction invariant: splicing must not emit a blank run longer than any
  # single contributor already had. Deletion is what exposes it, because the
  # separators on both sides of the removed range become adjacent once the
  # range's own text is gone.
  describe '.cap_junction_blank_runs' do
    it 'joins untouched when the tail is empty' do
      expect(
        described_class.cap_junction_blank_runs(
          head: "a\n\n", tail: '', preserved_count: 0, before_content: '', replacement: ''
        )
      ).to eq("a\n\n")
    end

    it 'joins untouched when the head ends in content' do
      expect(
        described_class.cap_junction_blank_runs(
          head: "a\n", tail: "\nb\n", preserved_count: 0, before_content: '', replacement: 'a'
        )
      ).to eq("a\n\nb\n")
    end

    it 'caps a stacked single-blank junction down to the longest contributor' do
      result = described_class.cap_junction_blank_runs(
        head: "# Before\n\n", tail: "\n## After\n", preserved_count: 0,
        before_content: "# Before\n\n", replacement: ''
      )

      expect(result).to eq("# Before\n\n## After\n")
    end

    it 'keeps a junction run no longer than the contributors already had' do
      result = described_class.cap_junction_blank_runs(
        head: "# Before\n\n\n", tail: "# After\n", preserved_count: 0,
        before_content: "# Before\n\n\n", replacement: ''
      )

      expect(result).to eq("# Before\n\n\n# After\n")
    end

    it 'leaves the junction alone when nothing is in excess' do
      result = described_class.cap_junction_blank_runs(
        head: "# Before\n\n", tail: "# After\n", preserved_count: 1,
        before_content: "# Before\n", replacement: ''
      )

      expect(result).to eq("# Before\n\n# After\n")
    end

    # A whole-file head of blanks: only one blank is in excess, so exactly one is
    # dropped and the surviving blank comes from the head rather than the tail.
    it 'never removes more blank lines than the junction run exceeds the cap' do
      result = described_class.cap_junction_blank_runs(
        head: "\n", tail: "\n# After\n", preserved_count: 0,
        before_content: '', replacement: ''
      )

      expect(result).to eq("\n# After\n")
    end

    it 'counts preserved blanks as a contributor to the allowed run' do
      result = described_class.cap_junction_blank_runs(
        head: "## Section\nNew body\n\n", tail: "\n## After\n", preserved_count: 1,
        before_content: '', replacement: "## Section\nNew body\n"
      )

      expect(result).to eq("## Section\nNew body\n\n## After\n")
    end
  end
end
# rubocop:enable Style/WordArray
