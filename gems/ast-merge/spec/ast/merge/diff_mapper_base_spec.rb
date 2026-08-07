# frozen_string_literal: true

require 'ast/merge'

RSpec.describe Ast::Merge::DiffMapperBase do
  before do
    # Simple struct for mock analysis
    stub_const('MockAnalysis', Struct.new(:content, :lines, keyword_init: true))
  end

  # Concrete subclass for testing
  let(:test_mapper_class) do
    mock_analysis_class = MockAnalysis
    Class.new(described_class) do
      define_method(:create_analysis) do |content|
        # Simple mock analysis
        mock_analysis_class.new(content: content, lines: content.lines)
      end

      def map_hunk_to_paths(hunk, _original_analysis)
        # Simple implementation: map each changed line to a path
        hunk.lines.reject { |l| l.type == :context }.map do |line|
          Ast::Merge::DiffMapperBase::DiffMapping.new(
            path: ["line_#{line.old_line_num || line.new_line_num}"],
            operation: determine_operation_for_line(line),
            lines: [line],
            hunk: hunk
          )
        end
      end

      private

      def determine_operation_for_line(line)
        case line.type
        when :addition then :add
        when :removal then :remove
        else :modify
        end
      end
    end
  end

  let(:mapper) { test_mapper_class.new }

  describe '#parse_diff' do
    context 'with a simple unified diff' do
      let(:diff_text) do
        <<~DIFF
          --- a/config.yml
          +++ b/config.yml
          @@ -1,4 +1,5 @@
           key1: value1
          -key2: old_value
          +key2: new_value
          +key3: added_value
           key4: value4
        DIFF
      end

      it 'extracts file paths' do
        result = mapper.parse_diff(diff_text)

        expect(result.old_file).to eq('config.yml')
        expect(result.new_file).to eq('config.yml')
      end

      it 'parses hunks' do
        result = mapper.parse_diff(diff_text)

        expect(result.hunks.length).to eq(1)

        hunk = result.hunks.first
        expect(hunk.old_start).to eq(1)
        expect(hunk.old_count).to eq(4)
        expect(hunk.new_start).to eq(1)
        expect(hunk.new_count).to eq(5)
      end

      it 'categorizes lines correctly' do
        result = mapper.parse_diff(diff_text)
        hunk = result.hunks.first

        context_lines = hunk.lines.select { |l| l.type == :context }
        additions = hunk.lines.select { |l| l.type == :addition }
        removals = hunk.lines.select { |l| l.type == :removal }

        expect(context_lines.length).to eq(2)
        expect(additions.length).to eq(2)
        expect(removals.length).to eq(1)
      end

      it 'tracks line numbers correctly' do
        result = mapper.parse_diff(diff_text)
        hunk = result.hunks.first

        # First context line
        expect(hunk.lines[0].old_line_num).to eq(1)
        expect(hunk.lines[0].new_line_num).to eq(1)

        # Removal
        removal = hunk.lines.find { |l| l.type == :removal }
        expect(removal.old_line_num).to eq(2)
        expect(removal.new_line_num).to be_nil

        # Additions
        additions = hunk.lines.select { |l| l.type == :addition }
        expect(additions[0].old_line_num).to be_nil
        expect(additions[0].new_line_num).to eq(2)
      end
    end

    context 'with multiple hunks' do
      let(:diff_text) do
        <<~DIFF
          --- a/file.txt
          +++ b/file.txt
          @@ -1,3 +1,3 @@
           line1
          -old2
          +new2
           line3
          @@ -10,3 +10,4 @@
           line10
           line11
          +added12
           line12
        DIFF
      end

      it 'parses all hunks' do
        result = mapper.parse_diff(diff_text)

        expect(result.hunks.length).to eq(2)
        expect(result.hunks[0].old_start).to eq(1)
        expect(result.hunks[1].old_start).to eq(10)
      end
    end

    context 'with new file (no old content)' do
      let(:diff_text) do
        <<~DIFF
          --- /dev/null
          +++ b/new_file.yml
          @@ -0,0 +1,3 @@
          +key1: value1
          +key2: value2
          +key3: value3
        DIFF
      end

      it 'handles new file correctly' do
        result = mapper.parse_diff(diff_text)

        expect(result.old_file).to eq('/dev/null')
        expect(result.new_file).to eq('new_file.yml')

        hunk = result.hunks.first
        expect(hunk.old_start).to eq(0)
        expect(hunk.old_count).to eq(0)
        expect(hunk.new_start).to eq(1)
        expect(hunk.new_count).to eq(3)
        expect(hunk.lines.all? { |l| l.type == :addition }).to be(true)
      end
    end

    context 'with deleted file' do
      let(:diff_text) do
        <<~DIFF
          --- a/deleted.yml
          +++ /dev/null
          @@ -1,3 +0,0 @@
          -key1: value1
          -key2: value2
          -key3: value3
        DIFF
      end

      it 'handles deleted file correctly' do
        result = mapper.parse_diff(diff_text)

        expect(result.old_file).to eq('deleted.yml')
        expect(result.new_file).to eq('/dev/null')

        hunk = result.hunks.first
        expect(hunk.lines.all? { |l| l.type == :removal }).to be(true)
      end
    end
  end

  describe '#determine_operation' do
    let(:mapper) { test_mapper_class.new }

    it 'returns :add for addition-only hunks' do
      hunk = described_class::DiffHunk.new(
        old_start: 1,
        old_count: 0,
        new_start: 1,
        new_count: 2,
        lines: [
          described_class::DiffLine.new(type: :addition, content: 'new1'),
          described_class::DiffLine.new(type: :addition, content: 'new2')
        ],
        header: '@@ -1,0 +1,2 @@'
      )

      expect(mapper.determine_operation(hunk)).to eq(:add)
    end

    it 'returns :remove for removal-only hunks' do
      hunk = described_class::DiffHunk.new(
        old_start: 1,
        old_count: 2,
        new_start: 1,
        new_count: 0,
        lines: [
          described_class::DiffLine.new(type: :removal, content: 'old1'),
          described_class::DiffLine.new(type: :removal, content: 'old2')
        ],
        header: '@@ -1,2 +1,0 @@'
      )

      expect(mapper.determine_operation(hunk)).to eq(:remove)
    end

    it 'returns :modify for mixed hunks' do
      hunk = described_class::DiffHunk.new(
        old_start: 1,
        old_count: 1,
        new_start: 1,
        new_count: 1,
        lines: [
          described_class::DiffLine.new(type: :removal, content: 'old'),
          described_class::DiffLine.new(type: :addition, content: 'new')
        ],
        header: '@@ -1,1 +1,1 @@'
      )

      expect(mapper.determine_operation(hunk)).to eq(:modify)
    end
  end

  describe '#map' do
    let(:diff_text) do
      <<~DIFF
        --- a/config.yml
        +++ b/config.yml
        @@ -1,3 +1,4 @@
         key1: value1
        +key2: new_value
         key3: value3
      DIFF
    end

    let(:original_content) do
      <<~YAML
        key1: value1
        key3: value3
      YAML
    end

    it 'returns DiffMapping objects' do
      mappings = mapper.map(diff_text, original_content)

      expect(mappings).to all(be_a(described_class::DiffMapping))
    end

    it 'includes path information' do
      mappings = mapper.map(diff_text, original_content)

      expect(mappings.first.path).to be_an(Array)
      expect(mappings.first.operation).to eq(:add)
    end
  end

  describe 'abstract methods' do
    let(:base_mapper) { described_class.new }

    it 'raises NotImplementedError for #create_analysis' do
      expect { base_mapper.create_analysis('content') }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for #map_hunk_to_paths' do
      hunk = described_class::DiffHunk.new
      expect { base_mapper.map_hunk_to_paths(hunk, nil) }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for #build_path_for_node' do
      expect { base_mapper.send(:build_path_for_node, nil, nil) }.to raise_error(NotImplementedError)
    end
  end

  describe '#extract_file_path' do
    let(:mapper) { test_mapper_class.new }

    it 'removes a/ prefix' do
      expect(mapper.send(:extract_file_path, 'a/path/to/file.yml')).to eq('path/to/file.yml')
    end

    it 'removes b/ prefix' do
      expect(mapper.send(:extract_file_path, 'b/path/to/file.yml')).to eq('path/to/file.yml')
    end

    it 'removes timestamp suffix' do
      expect(mapper.send(:extract_file_path, "a/file.yml\t2024-01-01 12:00:00")).to eq('file.yml')
    end

    it 'handles /dev/null' do
      expect(mapper.send(:extract_file_path, '/dev/null')).to eq('/dev/null')
    end
  end
end
