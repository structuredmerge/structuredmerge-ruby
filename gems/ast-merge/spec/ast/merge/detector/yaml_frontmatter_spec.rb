# frozen_string_literal: true

RSpec.describe Ast::Merge::Detector::YamlFrontmatter do
  let(:detector) { described_class.new }

  describe '#region_type' do
    it 'returns :yaml_frontmatter' do
      expect(detector.region_type).to eq(:yaml_frontmatter)
    end
  end

  describe '#detect_all' do
    context 'with valid YAML frontmatter' do
      let(:source) do
        <<~MD
          ---
          title: My Document
          author: Jane Doe
          date: 2024-01-15
          ---

          # Content starts here

          Some body text.
        MD
      end

      it 'detects the frontmatter' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end

      it 'returns a Region object' do
        regions = detector.detect_all(source)
        expect(regions.first).to be_a(Ast::Merge::Detector::Region)
      end

      it 'captures content without delimiters' do
        regions = detector.detect_all(source)
        expect(regions.first.content).to eq("title: My Document\nauthor: Jane Doe\ndate: 2024-01-15\n")
      end

      it 'sets correct start line' do
        regions = detector.detect_all(source)
        expect(regions.first.start_line).to eq(1)
      end

      it 'sets correct end line' do
        regions = detector.detect_all(source)
        # Line 1: ---, Line 2-4: content, Line 5: ---
        expect(regions.first.end_line).to eq(5)
      end

      it 'captures delimiters' do
        regions = detector.detect_all(source)
        expect(regions.first.delimiters).to eq(['---', '---'])
      end

      it 'sets yaml format in metadata' do
        regions = detector.detect_all(source)
        expect(regions.first.metadata[:format]).to eq(:yaml)
      end
    end

    context 'with minimal frontmatter' do
      let(:source) do
        <<~MD
          ---
          title: Short
          ---
          Content
        MD
      end

      it 'detects single-line content' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.content).to eq("title: Short\n")
      end
    end

    context 'with empty frontmatter' do
      let(:source) do
        <<~MD
          ---
          ---
          Content
        MD
      end

      it 'detects empty frontmatter' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.content).to eq('')
      end
    end

    context 'with UTF-8 BOM' do
      let(:source) do
        "\xEF\xBB\xBF---\ntitle: With BOM\n---\nContent"
      end

      it 'detects frontmatter after BOM' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.content).to eq("title: With BOM\n")
      end
    end

    context 'with trailing whitespace on delimiters' do
      let(:source) do
        "---   \ntitle: Test\n---\t\nContent"
      end

      it 'handles whitespace after delimiters' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end
    end

    context 'with CRLF line endings' do
      let(:source) do
        "---\r\ntitle: Windows\r\n---\r\nContent"
      end

      it 'handles Windows line endings' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.content).to eq("title: Windows\r\n")
      end
    end

    context 'when frontmatter is not at the start' do
      let(:source) do
        <<~MD
          Some text first

          ---
          title: Not frontmatter
          ---
        MD
      end

      it 'does not detect non-frontmatter YAML blocks' do
        regions = detector.detect_all(source)
        expect(regions).to eq([])
      end
    end

    context 'with missing closing delimiter' do
      let(:source) do
        <<~MD
          ---
          title: No closing
          Some text
        MD
      end

      it 'does not detect unclosed frontmatter' do
        regions = detector.detect_all(source)
        expect(regions).to eq([])
      end
    end

    context 'with empty or nil source' do
      it 'returns empty array for nil' do
        expect(detector.detect_all(nil)).to eq([])
      end

      it 'returns empty array for empty string' do
        expect(detector.detect_all('')).to eq([])
      end
    end

    context 'with document starting with non-frontmatter' do
      let(:source) do
        <<~MD
          # Header first

          ---
          title: This is a HR not frontmatter
          ---
        MD
      end

      it 'does not detect as frontmatter' do
        regions = detector.detect_all(source)
        expect(regions).to eq([])
      end
    end

    context 'with complex YAML content' do
      let(:source) do
        <<~MD
          ---
          title: "Complex: Values"
          tags:
            - ruby
            - markdown
          nested:
            key: value
            other: |
              multiline
              content
          ---
          Body
        MD
      end

      it 'captures all YAML content' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.content).to include('nested:')
        expect(regions.first.content).to include('multiline')
      end
    end
  end

  describe 'line calculation edge cases' do
    context "when content is not empty and doesn't end with newline" do
      let(:source) do
        "---\ntitle: test\n---\nBody"
      end

      it 'correctly calculates end_line for non-empty content' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.content).to eq("title: test\n")
        # Line 1: ---, Line 2: title: test, Line 3: ---
        expect(regions.first.start_line).to eq(1)
        expect(regions.first.end_line).to eq(3)
      end
    end

    context 'when full match does not end with newline' do
      let(:source) do
        "---\ntitle: test\n---"
      end

      it 'correctly handles match without trailing newline' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.end_line).to eq(3)
      end
    end

    context 'when content has multiple lines without trailing newline' do
      let(:source) do
        "---\nline1: a\nline2: b\n---\nBody"
      end

      it 'correctly calculates end_line for multi-line content' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.start_line).to eq(1)
        # Line 1: ---, Line 2: line1, Line 3: line2, Line 4: ---
        expect(regions.first.end_line).to eq(4)
      end
    end
  end
end
