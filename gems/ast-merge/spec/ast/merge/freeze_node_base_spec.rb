# frozen_string_literal: true

RSpec.describe Ast::Merge::FreezeNodeBase do
  describe 'MARKER_PATTERNS' do
    it 'is a hash' do
      expect(described_class::MARKER_PATTERNS).to be_a(Hash)
    end

    it 'includes :hash_comment pattern' do
      expect(described_class::MARKER_PATTERNS).to have_key(:hash_comment)
    end

    it 'includes :html_comment pattern' do
      expect(described_class::MARKER_PATTERNS).to have_key(:html_comment)
    end

    it 'includes :c_style_line pattern' do
      expect(described_class::MARKER_PATTERNS).to have_key(:c_style_line)
    end

    it 'includes :c_style_block pattern' do
      expect(described_class::MARKER_PATTERNS).to have_key(:c_style_block)
    end

    it 'has start and end patterns for each type' do
      described_class::MARKER_PATTERNS.each do |name, patterns|
        expect(patterns).to have_key(:start), "Pattern :#{name} missing :start"
        expect(patterns).to have_key(:end), "Pattern :#{name} missing :end"
        expect(patterns[:start]).to be_a(Regexp)
        expect(patterns[:end]).to be_a(Regexp)
      end
    end
  end

  describe 'DEFAULT_PATTERN' do
    it 'is :hash_comment' do
      expect(described_class::DEFAULT_PATTERN).to eq(:hash_comment)
    end
  end

  describe '.pattern_types' do
    it 'returns all registered pattern type names' do
      types = described_class.pattern_types
      expect(types).to include(:hash_comment, :html_comment, :c_style_line, :c_style_block)
    end
  end

  describe '.register_pattern' do
    after do
      # Clean up any custom patterns registered during tests
      described_class::MARKER_PATTERNS.delete(:test_pattern) if described_class::MARKER_PATTERNS.key?(:test_pattern)
    end

    it 'registers a new pattern' do
      described_class.register_pattern(
        :test_pattern,
        start: /^--\s*freeze/,
        end_pattern: /^--\s*unfreeze/
      )

      expect(described_class::MARKER_PATTERNS).to have_key(:test_pattern)
    end

    it 'raises ArgumentError for duplicate pattern name' do
      expect do
        described_class.register_pattern(
          :hash_comment,
          start: /test/,
          end_pattern: /test/
        )
      end.to raise_error(ArgumentError, /already registered/)
    end

    it 'raises ArgumentError if start is not a Regexp' do
      expect do
        described_class.register_pattern(
          :bad_pattern,
          start: 'not a regex',
          end_pattern: /test/
        )
      end.to raise_error(ArgumentError, /Start pattern must be a Regexp/)
    end

    it 'raises ArgumentError if end_pattern is not a Regexp' do
      expect do
        described_class.register_pattern(
          :bad_pattern,
          start: /test/,
          end_pattern: 'not a regex'
        )
      end.to raise_error(ArgumentError, /End pattern must be a Regexp/)
    end
  end

  describe '.start_pattern' do
    it 'returns start pattern for default pattern type' do
      pattern = described_class.start_pattern
      expect(pattern).to be_a(Regexp)
    end

    it 'returns start pattern for specified pattern type' do
      pattern = described_class.start_pattern(:html_comment)
      expect(pattern).to eq(described_class::MARKER_PATTERNS[:html_comment][:start])
    end

    it 'raises ArgumentError for unknown pattern type' do
      expect do
        described_class.start_pattern(:unknown)
      end.to raise_error(ArgumentError, /Unknown pattern type/)
    end
  end

  describe '.end_pattern' do
    it 'returns end pattern for default pattern type' do
      pattern = described_class.end_pattern
      expect(pattern).to be_a(Regexp)
    end

    it 'returns end pattern for specified pattern type' do
      pattern = described_class.end_pattern(:c_style_line)
      expect(pattern).to eq(described_class::MARKER_PATTERNS[:c_style_line][:end])
    end

    it 'raises ArgumentError for unknown pattern type' do
      expect do
        described_class.end_pattern(:unknown)
      end.to raise_error(ArgumentError, /Unknown pattern type/)
    end
  end

  describe '.freeze_start?' do
    context 'with hash_comment pattern (default)' do
      it 'returns true for matching freeze start marker' do
        expect(described_class.freeze_start?('# prism-merge:freeze')).to be(true)
      end

      it 'returns true for freeze marker with whitespace' do
        expect(described_class.freeze_start?('  # my-tool:freeze')).to be(true)
      end

      it 'returns true for freeze marker with suffix text' do
        expect(described_class.freeze_start?('# token:freeze reason here')).to be(true)
      end

      it 'returns false for non-matching line' do
        expect(described_class.freeze_start?('# regular comment')).to be(false)
      end

      it 'returns false for nil line' do
        expect(described_class.freeze_start?(nil)).to be(false)
      end

      it 'returns false for unfreeze marker' do
        expect(described_class.freeze_start?('# token:unfreeze')).to be(false)
      end
    end

    context 'with html_comment pattern' do
      it 'returns true for matching freeze start marker' do
        expect(described_class.freeze_start?('<!-- commonmarker-merge:freeze -->', :html_comment)).to be(true)
      end

      it 'returns true for marker with reason' do
        expect(described_class.freeze_start?('<!-- token:freeze reason here -->', :html_comment)).to be(true)
      end

      it 'returns false for unclosed HTML comment' do
        expect(described_class.freeze_start?('<!-- token:freeze', :html_comment)).to be(false)
      end

      it 'returns false for hash comment' do
        expect(described_class.freeze_start?('# token:freeze', :html_comment)).to be(false)
      end
    end

    context 'with c_style_line pattern' do
      it 'returns true for matching freeze start marker' do
        expect(described_class.freeze_start?('// json-merge:freeze', :c_style_line)).to be(true)
      end

      it 'returns true for marker with whitespace' do
        expect(described_class.freeze_start?('  // token:freeze', :c_style_line)).to be(true)
      end

      it 'returns false for hash comment' do
        expect(described_class.freeze_start?('# token:freeze', :c_style_line)).to be(false)
      end
    end

    context 'with c_style_block pattern' do
      it 'returns true for matching freeze start marker' do
        expect(described_class.freeze_start?('/* token:freeze */', :c_style_block)).to be(true)
      end

      it 'returns true for marker with reason' do
        expect(described_class.freeze_start?('/* token:freeze keep this */', :c_style_block)).to be(true)
      end

      it 'returns false for unclosed block comment' do
        expect(described_class.freeze_start?('/* token:freeze', :c_style_block)).to be(false)
      end
    end
  end

  describe '.freeze_end?' do
    context 'with hash_comment pattern (default)' do
      it 'returns true for matching unfreeze marker' do
        expect(described_class.freeze_end?('# prism-merge:unfreeze')).to be(true)
      end

      it 'returns true for unfreeze marker with whitespace' do
        expect(described_class.freeze_end?('  # my-tool:unfreeze')).to be(true)
      end

      it 'returns false for non-matching line' do
        expect(described_class.freeze_end?('# regular comment')).to be(false)
      end

      it 'returns false for nil line' do
        expect(described_class.freeze_end?(nil)).to be(false)
      end

      it 'returns false for freeze marker' do
        expect(described_class.freeze_end?('# token:freeze')).to be(false)
      end
    end

    context 'with html_comment pattern' do
      it 'returns true for matching unfreeze marker' do
        expect(described_class.freeze_end?('<!-- token:unfreeze -->', :html_comment)).to be(true)
      end

      it 'returns false for unclosed HTML comment' do
        expect(described_class.freeze_end?('<!-- token:unfreeze', :html_comment)).to be(false)
      end
    end

    context 'with c_style_line pattern' do
      it 'returns true for matching unfreeze marker' do
        expect(described_class.freeze_end?('// json-merge:unfreeze', :c_style_line)).to be(true)
      end
    end

    context 'with c_style_block pattern' do
      it 'returns true for matching unfreeze marker' do
        expect(described_class.freeze_end?('/* token:unfreeze */', :c_style_block)).to be(true)
      end
    end
  end

  describe 'Location struct' do
    it 'is defined' do
      expect(Ast::Merge::FreezeNodeBase::Location).to be_a(Class)
    end

    it 'has start_line and end_line attributes' do
      location = Ast::Merge::FreezeNodeBase::Location.new(1, 10)
      expect(location.start_line).to eq(1)
      expect(location.end_line).to eq(10)
    end

    describe '#cover?' do
      let(:location) { Ast::Merge::FreezeNodeBase::Location.new(5, 10) }

      it 'returns true for line at start' do
        expect(location.cover?(5)).to be(true)
      end

      it 'returns true for line in middle' do
        expect(location.cover?(7)).to be(true)
      end

      it 'returns true for line at end' do
        expect(location.cover?(10)).to be(true)
      end

      it 'returns false for line before range' do
        expect(location.cover?(4)).to be(false)
      end

      it 'returns false for line after range' do
        expect(location.cover?(11)).to be(false)
      end
    end
  end

  describe 'InvalidStructureError' do
    it 'is defined as an error class' do
      expect(Ast::Merge::FreezeNodeBase::InvalidStructureError).to be < StandardError
    end

    it 'can be raised with a message' do
      expect do
        raise Ast::Merge::FreezeNodeBase::InvalidStructureError, 'test error'
      end.to raise_error(Ast::Merge::FreezeNodeBase::InvalidStructureError, 'test error')
    end

    it 'accepts start_line and end_line keyword arguments' do
      error = Ast::Merge::FreezeNodeBase::InvalidStructureError.new(
        'test',
        start_line: 5,
        end_line: 10
      )
      expect(error.start_line).to eq(5)
      expect(error.end_line).to eq(10)
    end

    it 'accepts unclosed_nodes keyword argument' do
      error = Ast::Merge::FreezeNodeBase::InvalidStructureError.new(
        'test',
        unclosed_nodes: %i[node1 node2]
      )
      expect(error.unclosed_nodes).to eq(%i[node1 node2])
    end

    it 'defaults unclosed_nodes to empty array' do
      error = Ast::Merge::FreezeNodeBase::InvalidStructureError.new('test')
      expect(error.unclosed_nodes).to eq([])
    end
  end

  describe '#initialize' do
    it 'creates a freeze node with start_line and end_line' do
      node = described_class.new(start_line: 5, end_line: 10)

      expect(node.start_line).to eq(5)
      expect(node.end_line).to eq(10)
    end

    it 'accepts optional start_marker and end_marker' do
      node = described_class.new(
        start_line: 5,
        end_line: 10,
        start_marker: '# freeze',
        end_marker: '# unfreeze'
      )

      expect(node.start_marker).to eq('# freeze')
      expect(node.end_marker).to eq('# unfreeze')
    end

    it 'defaults pattern_type to DEFAULT_PATTERN' do
      node = described_class.new(start_line: 5, end_line: 10)
      expect(node.pattern_type).to eq(described_class::DEFAULT_PATTERN)
    end

    it 'accepts custom pattern_type' do
      node = described_class.new(start_line: 5, end_line: 10, pattern_type: :html_comment)
      expect(node.pattern_type).to eq(:html_comment)
    end

    context 'with lines parameter' do
      it 'stores lines directly' do
        lines = %W[line1\n line2\n line3\n]
        node = described_class.new(start_line: 1, end_line: 3, lines: lines)

        expect(node.lines).to eq(lines)
      end

      it 'derives content from lines' do
        lines = %w[line1 line2 line3]
        node = described_class.new(start_line: 1, end_line: 3, lines: lines)

        expect(node.content).to eq("line1\nline2\nline3")
      end
    end

    context 'with content parameter' do
      it 'stores content directly' do
        node = described_class.new(start_line: 1, end_line: 3, content: 'test content')

        expect(node.content).to eq('test content')
      end

      it 'derives lines from content' do
        node = described_class.new(start_line: 1, end_line: 3, content: "line1\nline2\nline3")

        expect(node.lines).to eq(%w[line1 line2 line3])
      end
    end

    context 'with analysis parameter' do
      let(:mock_analysis) do
        analysis = double('analysis')
        allow(analysis).to receive(:lines).and_return(%w[line0 line1 line2 line3 line4])
        analysis
      end

      it 'stores analysis reference' do
        node = described_class.new(start_line: 2, end_line: 4, analysis: mock_analysis)

        expect(node.analysis).to eq(mock_analysis)
      end

      it 'extracts lines from analysis' do
        node = described_class.new(start_line: 2, end_line: 4, analysis: mock_analysis)

        # Lines 2-4 (1-indexed) = indices 1-3 (0-indexed)
        expect(node.lines).to eq(%w[line1 line2 line3])
      end

      it 'derives content from extracted lines' do
        node = described_class.new(start_line: 2, end_line: 4, analysis: mock_analysis)

        expect(node.content).to eq("line1\nline2\nline3")
      end
    end

    context 'with nodes parameter' do
      it 'stores nodes array' do
        nodes = [double('node1'), double('node2')]
        node = described_class.new(start_line: 1, end_line: 5, nodes: nodes)

        expect(node.nodes).to eq(nodes)
      end

      it 'defaults nodes to empty array' do
        node = described_class.new(start_line: 1, end_line: 5)

        expect(node.nodes).to eq([])
      end
    end

    context 'with overlapping_nodes parameter' do
      it 'stores overlapping_nodes' do
        overlapping = [double('overlap1'), double('overlap2')]
        node = described_class.new(start_line: 1, end_line: 5, overlapping_nodes: overlapping)

        expect(node.overlapping_nodes).to eq(overlapping)
      end

      it 'defaults overlapping_nodes to nil' do
        node = described_class.new(start_line: 1, end_line: 5)

        expect(node.overlapping_nodes).to be_nil
      end
    end

    context 'with reason parameter' do
      it 'stores explicit reason' do
        node = described_class.new(start_line: 1, end_line: 5, reason: 'custom reason')

        expect(node.reason).to eq('custom reason')
      end

      it 'explicit reason takes precedence over marker extraction' do
        node = described_class.new(
          start_line: 1,
          end_line: 5,
          start_marker: '# token:freeze marker reason',
          reason: 'explicit reason'
        )

        expect(node.reason).to eq('explicit reason')
      end
    end

    context 'when determining priority of content sources' do
      let(:mock_analysis) do
        analysis = double('analysis')
        allow(analysis).to receive(:lines).and_return(%w[analysis_line])
        analysis
      end

      it 'prefers lines over analysis' do
        node = described_class.new(
          start_line: 1,
          end_line: 1,
          lines: %w[direct_line],
          analysis: mock_analysis
        )

        expect(node.lines).to eq(%w[direct_line])
      end

      it 'prefers content over lines for content attribute' do
        node = described_class.new(
          start_line: 1,
          end_line: 1,
          lines: %w[line_content],
          content: 'direct_content'
        )

        expect(node.content).to eq('direct_content')
      end
    end
  end

  describe '#location' do
    it 'returns a Location struct' do
      node = described_class.new(start_line: 5, end_line: 10)
      location = node.location

      expect(location).to be_a(Ast::Merge::FreezeNodeBase::Location)
      expect(location.start_line).to eq(5)
      expect(location.end_line).to eq(10)
    end

    it 'memoizes the location' do
      node = described_class.new(start_line: 5, end_line: 10)
      location = node.location
      expect(node.location).to equal(location)
    end
  end

  describe '#freeze_node?' do
    it 'returns true' do
      node = described_class.new(start_line: 1, end_line: 5)
      expect(node.freeze_node?).to be(true)
    end
  end

  describe '#slice' do
    it 'returns the content' do
      node = described_class.new(start_line: 1, end_line: 5)
      # Base class content is nil by default
      expect(node.slice).to be_nil
    end

    it 'returns content when set' do
      node = described_class.new(start_line: 1, end_line: 5)
      node.instance_variable_set(:@content, 'test content')
      expect(node.slice).to eq('test content')
    end
  end

  describe '#signature' do
    it 'returns an array with :FreezeNode and nil content when no content' do
      node = described_class.new(start_line: 1, end_line: 5)
      sig = node.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:FreezeNode)
      expect(sig.last).to be_nil
    end

    it 'returns an array with :FreezeNode and stripped content' do
      node = described_class.new(start_line: 1, end_line: 5)
      node.instance_variable_set(:@content, '  test content  ')
      sig = node.signature
      expect(sig).to eq([:FreezeNode, 'test content'])
    end
  end

  describe '#inspect' do
    it 'returns a readable representation' do
      node = described_class.new(start_line: 5, end_line: 10)

      inspect_result = node.inspect
      expect(inspect_result).to include('FreezeNode')
      expect(inspect_result).to include('5..10')
    end

    it 'includes the pattern type' do
      node = described_class.new(start_line: 5, end_line: 10, pattern_type: :html_comment)

      inspect_result = node.inspect
      expect(inspect_result).to include('html_comment')
    end
  end

  describe '#to_s' do
    it 'returns same as inspect' do
      node = described_class.new(start_line: 5, end_line: 10)
      expect(node.to_s).to eq(node.inspect)
    end
  end

  describe '#validate_line_order! (protected)' do
    # Test via a subclass that calls validate_line_order!
    let(:validating_class) do
      Class.new(described_class) do
        def initialize(start_line:, end_line:, pattern_type: Ast::Merge::FreezeNodeBase::DEFAULT_PATTERN)
          super
          validate_line_order!
        end
      end
    end

    it 'raises when end_line is before start_line' do
      expect do
        validating_class.new(start_line: 10, end_line: 5)
      end.to raise_error(Ast::Merge::FreezeNodeBase::InvalidStructureError, /end line.*before start line/i)
    end

    it 'does not raise for valid structure' do
      expect do
        validating_class.new(start_line: 5, end_line: 10)
      end.not_to raise_error
    end

    it 'does not raise when start equals end' do
      expect do
        validating_class.new(start_line: 5, end_line: 5)
      end.not_to raise_error
    end
  end

  describe 'line and content resolution edge cases' do
    describe 'when lines parameter is provided directly' do
      it 'uses provided lines without consulting analysis' do
        # This tests the early return in resolve_lines (line 376)
        node = described_class.new(
          start_line: 1,
          end_line: 3,
          lines: %w[explicit line1 line2]
        )
        expect(node.lines).to eq(%w[explicit line1 line2])
      end
    end

    describe 'when content parameter is provided directly' do
      it 'uses provided content without deriving from lines' do
        # This tests the early return in resolve_content (line 395)
        node = described_class.new(
          start_line: 1,
          end_line: 3,
          content: 'explicit content'
        )
        expect(node.content).to eq('explicit content')
      end

      it 'prioritizes content over lines for content value' do
        node = described_class.new(
          start_line: 1,
          end_line: 3,
          lines: %w[line1 line2],
          content: 'explicit content takes priority'
        )
        expect(node.content).to eq('explicit content takes priority')
      end
    end

    describe 'when analysis provides lines' do
      let(:mock_analysis) do
        analysis = double('Analysis')
        allow(analysis).to receive(:respond_to?).with(:lines).and_return(true)
        allow(analysis).to receive(:lines).and_return(%w[line0 line1 line2 line3 line4])
        analysis
      end

      it 'extracts lines from analysis using line numbers' do
        node = described_class.new(
          start_line: 2,
          end_line: 4,
          analysis: mock_analysis
        )
        # Lines 2-4 (1-indexed) = indices 1-3 (0-indexed)
        expect(node.lines).to eq(%w[line1 line2 line3])
      end
    end

    describe 'when analysis does not respond to lines' do
      let(:mock_analysis_without_lines) do
        analysis = double('Analysis')
        allow(analysis).to receive(:respond_to?).with(:lines).and_return(false)
        analysis
      end

      it 'falls back to splitting content' do
        node = described_class.new(
          start_line: 1,
          end_line: 2,
          analysis: mock_analysis_without_lines,
          content: "fallback\ncontent"
        )
        expect(node.lines).to eq(%w[fallback content])
      end
    end

    describe 'when neither lines nor analysis nor content provided' do
      it 'returns nil for lines' do
        node = described_class.new(start_line: 1, end_line: 3)
        expect(node.lines).to be_nil
      end

      it 'returns nil for content' do
        node = described_class.new(start_line: 1, end_line: 3)
        expect(node.content).to be_nil
      end
    end

    describe 'when lines are nil but content is provided' do
      it 'derives lines from content' do
        node = described_class.new(
          start_line: 1,
          end_line: 3,
          content: "line1\nline2\nline3"
        )
        expect(node.lines).to eq(%w[line1 line2 line3])
      end
    end
  end
end
