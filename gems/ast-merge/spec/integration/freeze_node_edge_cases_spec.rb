# frozen_string_literal: true

# Branch coverage integration specs for ast-merge
# These tests target specific uncovered branches identified in coverage analysis

RSpec.describe 'Ast::Merge Branch Coverage' do
  describe 'FreezeNodeBase.pattern_for' do
    describe 'with different pattern types and tokens' do
      it 'builds hash_comment pattern with token' do
        # This covers the :hash_comment when branch (line 161)
        pattern = Ast::Merge::FreezeNodeBase.pattern_for(:hash_comment, 'my-merge')
        expect(pattern).to be_a(Regexp)
        freeze_example = '# my-merge:freeze'
        unfreeze_example = '# my-merge:unfreeze some reason'
        expect(freeze_example).to match(pattern)
        expect(unfreeze_example).to match(pattern)
        # Capture groups should work
        match = '# my-merge:freeze reason text'.match(pattern)
        freeze_text = match[1]
        reason_text = match[2]
        expect(freeze_text).to eq('freeze')
        expect(reason_text).to eq('reason text')
      end

      it 'builds html_comment pattern with token' do
        pattern = Ast::Merge::FreezeNodeBase.pattern_for(:html_comment, 'my-merge')
        expect(pattern).to be_a(Regexp)
        freeze_example = '<!-- my-merge:freeze -->'
        unfreeze_example = '<!-- my-merge:unfreeze reason here -->'
        expect(freeze_example).to match(pattern)
        expect(unfreeze_example).to match(pattern)
      end

      it 'builds c_style_line pattern with token' do
        pattern = Ast::Merge::FreezeNodeBase.pattern_for(:c_style_line, 'my-merge')
        expect(pattern).to be_a(Regexp)
        freeze_example = '// my-merge:freeze'
        unfreeze_example = '// my-merge:unfreeze some reason'
        expect(freeze_example).to match(pattern)
        expect(unfreeze_example).to match(pattern)
      end

      it 'builds c_style_block pattern with token' do
        pattern = Ast::Merge::FreezeNodeBase.pattern_for(:c_style_block, 'my-merge')
        expect(pattern).to be_a(Regexp)
        freeze_example = '/* my-merge:freeze */'
        unfreeze_example = '/* my-merge:unfreeze reason */'
        expect(freeze_example).to match(pattern)
        expect(unfreeze_example).to match(pattern)
      end

      it 'raises ArgumentError for unknown pattern type' do
        expect do
          Ast::Merge::FreezeNodeBase.pattern_for(:unknown_pattern)
        end.to raise_error(ArgumentError, /unknown pattern type/i)
      end

      it 'raises ArgumentError for custom type with token' do
        # Register a custom pattern temporarily
        custom_name = :"custom_test_#{rand(10_000)}"
        Ast::Merge::FreezeNodeBase.register_pattern(
          custom_name,
          start: /^--\s*freeze-begin/i,
          end_pattern: /^--\s*freeze-end/i
        )

        # Should raise when trying to build token-specific pattern for custom type
        expect do
          Ast::Merge::FreezeNodeBase.pattern_for(custom_name, 'my-token')
        end.to raise_error(ArgumentError, /cannot build token-specific pattern/i)
      ensure
        # Clean up by removing the custom pattern
        Ast::Merge::FreezeNodeBase::MARKER_PATTERNS.delete(custom_name)
      end
    end
  end

  describe 'DebugLogger edge cases' do
    let(:test_logger) do
      Module.new do
        extend Ast::Merge::DebugLogger

        self.env_var_name = 'TEST_BRANCH_DEBUG'
        self.log_prefix = '[TestBranch]'
      end
    end

    describe '#time when Benchmark is not available' do
      it 'still returns the block result' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        stub_const('Ast::Merge::DebugLogger::BENCHMARK_AVAILABLE', false)

        result = test_logger.time('operation') { 42 }
        expect(result).to eq(42)
      end
    end

    describe '#extract_node_info edge cases' do
      it 'handles node with location having start_line and end_line' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        location = double('Location', start_line: 5, end_line: 10)
        node = double('Node', location: location)
        test_class = Class.new do
          class << self
            def name
              'TestNode'
            end
          end
        end
        allow(node).to receive(:class).and_return(test_class)

        info = test_logger.extract_node_info(node)
        expect(info[:lines]).to eq('5..10')
      end

      it 'handles node with location having only line' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        location = double('Location', line: 7)
        allow(location).to receive(:respond_to?).and_return(false)
        allow(location).to receive(:respond_to?).with(:start_line).and_return(false)
        allow(location).to receive(:respond_to?).with(:end_line).and_return(false)
        allow(location).to receive(:respond_to?).with(:line).and_return(true)
        node = double('Node', location: location)
        allow(node).to receive(:respond_to?).with(:location).and_return(true)
        test_class = Class.new do
          class << self
            def name
              'TestNode'
            end
          end
        end
        allow(node).to receive(:class).and_return(test_class)

        info = test_logger.extract_node_info(node)
        # When start_line/end_line not present and line is, extract_lines returns nil
        # because the implementation checks start_line/end_line first
        expect(info[:lines]).to be_nil
      end

      it 'handles node without location but with start_line/end_line' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        node = double('Node', start_line: 5, end_line: 10)
        allow(node).to receive(:respond_to?).with(:location).and_return(false)
        allow(node).to receive(:respond_to?).with(:start_line).and_return(true)
        allow(node).to receive(:respond_to?).with(:end_line).and_return(true)
        test_class = Class.new do
          class << self
            def name
              'TestNode'
            end
          end
        end
        allow(node).to receive(:class).and_return(test_class)

        info = test_logger.extract_node_info(node)
        expect(info[:lines]).to eq('5..10')
      end

      it 'handles node without location' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        node = double('Node')
        allow(node).to receive(:respond_to?).with(:location).and_return(false)
        allow(node).to receive(:respond_to?).with(:start_line).and_return(false)
        allow(node).to receive(:respond_to?).with(:end_line).and_return(false)
        test_class = Class.new do
          class << self
            def name
              'TestNode'
            end
          end
        end
        allow(node).to receive(:class).and_return(test_class)

        info = test_logger.extract_node_info(node)
        expect(info[:lines]).to be_nil
      end
    end

    describe '#safe_type_name edge cases' do
      it 'handles anonymous class node' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        anon_class = Class.new
        node = anon_class.new

        result = test_logger.safe_type_name(node)
        expect(result).to be_a(String)
      end

      it 'handles node class with nil name' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        node = double('Node')
        klass = double('Class')
        allow(node).to receive(:class).and_return(klass)
        allow(klass).to receive(:respond_to?).with(:name).and_return(true)
        allow(klass).to receive_messages(name: nil, to_s: 'AnonymousClass')

        result = test_logger.safe_type_name(node)
        expect(result).to eq('AnonymousClass')
      end
    end

    describe '#extract_lines edge cases' do
      it 'handles node with only start_line (no end_line)' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        location = double('Location', start_line: 5)
        allow(location).to receive(:respond_to?).with(:start_line).and_return(true)
        allow(location).to receive(:respond_to?).with(:end_line).and_return(false)
        node = double('Node', location: location)
        allow(node).to receive(:respond_to?).with(:location).and_return(true)

        result = test_logger.extract_lines(node)
        expect(result).to eq('5')
      end

      it 'handles node with line instead of start_line' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        location = double('Location')
        allow(location).to receive(:respond_to?).with(:start_line).and_return(false)
        allow(location).to receive(:respond_to?).with(:end_line).and_return(false)
        node = double('Node', location: location)
        allow(node).to receive(:respond_to?).with(:location).and_return(true)

        result = test_logger.extract_lines(node)
        # Returns nil when location doesn't have start_line
        expect(result).to be_nil
      end

      it 'handles node with start_line and end_line directly' do
        stub_env('TEST_BRANCH_DEBUG' => '1')
        node = double('Node', start_line: 3, end_line: 7)
        allow(node).to receive(:respond_to?).with(:location).and_return(false)
        allow(node).to receive(:respond_to?).with(:start_line).and_return(true)
        allow(node).to receive(:respond_to?).with(:end_line).and_return(true)

        result = test_logger.extract_lines(node)
        expect(result).to eq('3..7')
      end
    end
  end

  describe 'FileAnalysisBase edge cases' do
    # Create a minimal test implementation
    let(:test_analysis_class) do
      Class.new do
        include Ast::Merge::FileAnalyzable

        def initialize(source, freeze_token: 'test-merge', signature_generator: nil)
          @source = source
          @lines = source.lines.map(&:chomp)
          @freeze_token = freeze_token
          @signature_generator = signature_generator
          @statements = []
        end

        def compute_node_signature(node)
          case node
          when Ast::Merge::FreezeNodeBase
            node.signature # Use the FreezeNodeBase's signature method
          else
            [:default, node.hash]
          end
        end
      end
    end

    describe '#generate_signature with custom generator' do
      it 'returns custom generator result when it returns an Array' do
        custom_gen = ->(_node) { [:custom, 'signature'] }
        analysis = test_analysis_class.new('content', signature_generator: custom_gen)

        result = analysis.generate_signature(double('Node'))
        expect(result).to eq([:custom, 'signature'])
      end

      it 'returns nil when custom generator returns nil' do
        custom_gen = ->(_node) { nil }
        analysis = test_analysis_class.new('content', signature_generator: custom_gen)

        result = analysis.generate_signature(double('Node'))
        expect(result).to be_nil
      end

      it 'falls through to default computation when generator returns a FreezeNode' do
        freeze_node = Ast::Merge::FreezeNodeBase.new(
          start_line: 1,
          end_line: 3,
          content: 'frozen content'
        )
        custom_gen = ->(_node) { freeze_node }
        analysis = test_analysis_class.new('content', signature_generator: custom_gen)

        result = analysis.generate_signature(double('OriginalNode'))
        # Should compute signature for the freeze_node using its signature method
        expect(result).to eq(freeze_node.signature)
      end
    end

    describe '#signature_at edge cases' do
      it 'returns nil for negative index' do
        analysis = test_analysis_class.new('content')

        result = analysis.signature_at(-1)
        expect(result).to be_nil
      end

      it 'returns nil for index beyond statements length' do
        analysis = test_analysis_class.new('content')

        result = analysis.signature_at(100)
        expect(result).to be_nil
      end
    end

    describe '#line_at edge cases' do
      it 'returns nil for line 0' do
        analysis = test_analysis_class.new("line1\nline2")

        result = analysis.line_at(0)
        expect(result).to be_nil
      end

      it 'returns nil for negative line number' do
        analysis = test_analysis_class.new("line1\nline2")

        result = analysis.line_at(-1)
        expect(result).to be_nil
      end

      it 'returns line content for valid line number' do
        analysis = test_analysis_class.new("line1\nline2\nline3")

        expect(analysis.line_at(1)).to eq('line1')
        expect(analysis.line_at(2)).to eq('line2')
        expect(analysis.line_at(3)).to eq('line3')
      end
    end

    describe '#signature_at with valid index' do
      it 'returns signature for valid index' do
        analysis = test_analysis_class.new('content')
        analysis.instance_variable_set(:@statements, [double('Node', hash: 12_345)])

        result = analysis.signature_at(0)
        expect(result).to eq([:default, 12_345])
      end
    end

    describe '#generate_signature with non-fallthrough result' do
      it 'passes through arbitrary values from custom generator' do
        # Test when custom generator returns something that is not Array, nil, or a fallthrough node
        # Non-fallthrough values are passed through as-is, allowing custom signature types
        custom_gen = ->(_node) { 'string result' }
        analysis = test_analysis_class.new('content', signature_generator: custom_gen)

        node = double('Node', hash: 99_999)
        result = analysis.generate_signature(node)
        # Should pass through the string result directly
        expect(result).to eq('string result')
      end
    end

    describe '#fallthrough_node?' do
      it 'returns true for FreezeNodeBase instances' do
        analysis = test_analysis_class.new('content')
        freeze_node = Ast::Merge::FreezeNodeBase.new(start_line: 1, end_line: 3)

        expect(analysis.fallthrough_node?(freeze_node)).to be true
      end

      it 'returns false for non-FreezeNodeBase instances' do
        analysis = test_analysis_class.new('content')

        expect(analysis.fallthrough_node?('string')).to be false
        expect(analysis.fallthrough_node?(123)).to be false
        expect(analysis.fallthrough_node?(double('Node'))).to be false
      end
    end

    describe '#normalized_line' do
      it 'strips whitespace from line content' do
        analysis = test_analysis_class.new("  line1  \n  line2  ")

        expect(analysis.normalized_line(1)).to eq('line1')
        expect(analysis.normalized_line(2)).to eq('line2')
      end

      it 'returns nil for invalid line number' do
        analysis = test_analysis_class.new('line1')

        expect(analysis.normalized_line(0)).to be_nil
        expect(analysis.normalized_line(-1)).to be_nil
      end
    end

    describe '#freeze_blocks (line 68)' do
      it 'returns empty array when no freeze nodes in statements' do
        analysis = test_analysis_class.new('content')
        analysis.instance_variable_set(:@statements, [double('RegularNode')])

        expect(analysis.freeze_blocks).to eq([])
      end

      it 'returns freeze nodes from statements' do
        freeze_node = Ast::Merge::FreezeNodeBase.new(start_line: 1, end_line: 3, content: 'frozen')
        analysis = test_analysis_class.new('content')
        analysis.instance_variable_set(:@statements, [double('Node'), freeze_node, double('Node2')])

        expect(analysis.freeze_blocks).to eq([freeze_node])
      end
    end

    describe '#in_freeze_block? (line 76)' do
      it 'returns false when line is not in any freeze block' do
        freeze_node = Ast::Merge::FreezeNodeBase.new(start_line: 5, end_line: 10, content: 'frozen')
        analysis = test_analysis_class.new('content')
        analysis.instance_variable_set(:@statements, [freeze_node])

        expect(analysis.in_freeze_block?(1)).to be false
        expect(analysis.in_freeze_block?(15)).to be false
      end

      it 'returns true when line is inside a freeze block' do
        freeze_node = Ast::Merge::FreezeNodeBase.new(start_line: 5, end_line: 10, content: 'frozen')
        analysis = test_analysis_class.new('content')
        analysis.instance_variable_set(:@statements, [freeze_node])

        expect(analysis.in_freeze_block?(5)).to be true
        expect(analysis.in_freeze_block?(7)).to be true
        expect(analysis.in_freeze_block?(10)).to be true
      end
    end

    describe '#freeze_block_at (line 84)' do
      it 'returns nil when line is not in any freeze block' do
        freeze_node = Ast::Merge::FreezeNodeBase.new(start_line: 5, end_line: 10, content: 'frozen')
        analysis = test_analysis_class.new('content')
        analysis.instance_variable_set(:@statements, [freeze_node])

        expect(analysis.freeze_block_at(1)).to be_nil
        expect(analysis.freeze_block_at(15)).to be_nil
      end

      it 'returns the freeze block containing the line' do
        freeze_node = Ast::Merge::FreezeNodeBase.new(start_line: 5, end_line: 10, content: 'frozen')
        analysis = test_analysis_class.new('content')
        analysis.instance_variable_set(:@statements, [freeze_node])

        expect(analysis.freeze_block_at(7)).to eq(freeze_node)
      end
    end

    describe '#compute_node_signature (line 168)' do
      it 'raises NotImplementedError when not implemented' do
        # Create a class that includes FileAnalyzable but doesn't implement compute_node_signature
        bare_class = Class.new do
          include Ast::Merge::FileAnalyzable

          # NOTE: source, lines, freeze_token, signature_generator are provided by FileAnalyzable
          attr_reader :statements

          def initialize
            @statements = []
          end
        end

        analysis = bare_class.new
        expect { analysis.compute_node_signature(double('Node')) }
          .to raise_error(NotImplementedError, /must implement #compute_node_signature/)
      end
    end
  end

  describe 'MergeResult edge cases' do
    describe 'initialization and basic operations' do
      let(:result) { Ast::Merge::MergeResultBase.new }

      it 'starts with empty lines' do
        expect(result.lines).to be_empty
        expect(result.empty?).to be true
      end

      it 'tracks line count' do
        expect(result.line_count).to eq(0)
      end

      it 'provides decision_summary' do
        summary = result.decision_summary
        expect(summary).to be_a(Hash)
      end

      it 'provides inspect output' do
        output = result.inspect
        expect(output).to include('MergeResult')
        expect(output).to include('lines=0')
      end

      it 'can check content?' do
        expect(result.content?).to be false
      end

      it 'returns content as array' do
        expect(result.content).to eq([])
      end

      it 'returns to_s' do
        expect(result.to_s).to eq('')
      end
    end

    describe 'with initialization parameters' do
      it 'accepts template_analysis' do
        analysis = double('Analysis')
        result = Ast::Merge::MergeResultBase.new(template_analysis: analysis)
        expect(result.template_analysis).to eq(analysis)
      end

      it 'accepts dest_analysis' do
        analysis = double('Analysis')
        result = Ast::Merge::MergeResultBase.new(dest_analysis: analysis)
        expect(result.dest_analysis).to eq(analysis)
      end

      it 'accepts conflicts array' do
        conflicts = [{ type: :conflict }]
        result = Ast::Merge::MergeResultBase.new(conflicts: conflicts)
        expect(result.conflicts).to eq(conflicts)
      end

      it 'accepts frozen_blocks array' do
        blocks = [:block1]
        result = Ast::Merge::MergeResultBase.new(frozen_blocks: blocks)
        expect(result.frozen_blocks).to eq(blocks)
      end

      it 'accepts stats hash' do
        stats = { merged: 5 }
        result = Ast::Merge::MergeResultBase.new(stats: stats)
        expect(result.stats).to eq(stats)
      end
    end
  end

  describe 'FreezeNode#reason edge cases' do
    # Tests for uncovered branches in reason method (lines 301-315)

    it 'returns explicit reason when provided at initialization' do
      # Covers line 301 - return @explicit_reason if @explicit_reason
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        reason: 'explicit reason provided'
      )
      expect(freeze_node.reason).to eq('explicit reason provided')
    end

    it 'returns nil when start_marker is not set' do
      # Covers line 303 - return nil unless @start_marker
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content'
      )
      expect(freeze_node.reason).to be_nil
    end

    it 'returns nil when token cannot be extracted from marker' do
      # Covers line 308 - return nil unless token
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: 'invalid marker without token'
      )
      expect(freeze_node.reason).to be_nil
    end

    it 'returns nil when pattern does not match marker' do
      # Covers line 312 - return nil unless match
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: '# some-token:freeze',
        pattern_type: :c_style_line # Wrong pattern type for hash comment
      )
      expect(freeze_node.reason).to be_nil
    end

    it 'returns nil when reason text is empty after strip' do
      # Covers line 315 - reason_text&.empty? ? nil : reason_text
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: '# test-token:freeze   ', # Only whitespace after marker
        pattern_type: :hash_comment
      )
      expect(freeze_node.reason).to be_nil
    end

    it 'extracts reason from marker when present' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: '# test-token:freeze keep this section',
        pattern_type: :hash_comment
      )
      expect(freeze_node.reason).to eq('keep this section')
    end

    it 'returns nil for html_comment pattern when no reason provided (match[2] nil)' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: '<!-- test-token:freeze -->',
        pattern_type: :html_comment
      )
      expect(freeze_node.reason).to be_nil
    end

    it 'extracts reason from html_comment marker when present' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: '<!-- test-token:freeze keep this section -->',
        pattern_type: :html_comment
      )
      expect(freeze_node.reason).to eq('keep this section')
    end

    it 'extracts reason from c_style_line marker when present' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: '// test-token:freeze keep this',
        pattern_type: :c_style_line
      )
      expect(freeze_node.reason).to eq('keep this')
    end

    it 'returns nil for c_style_line with no reason' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: '// test-token:freeze',
        pattern_type: :c_style_line
      )
      expect(freeze_node.reason).to be_nil
    end

    it 'extracts reason from c_style_block when present' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: '/* test-token:freeze keep this */',
        pattern_type: :c_style_block
      )
      expect(freeze_node.reason).to eq('keep this')
    end

    it 'returns nil for c_style_block with no reason' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content',
        start_marker: '/* test-token:freeze */',
        pattern_type: :c_style_block
      )
      expect(freeze_node.reason).to be_nil
    end
  end

  describe 'FreezeNode#extract_token_from_marker edge cases' do
    it 'returns nil for invalid marker format' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'content',
        start_marker: 'not a valid marker'
      )
      # The private method returns nil, which causes reason to return nil
      expect(freeze_node.reason).to be_nil
    end
  end

  describe 'DebugLogger module method edge cases' do
    describe '#env_var_name from instance context' do
      # Tests for uncovered branches in env_var_name/log_prefix methods (lines 131-152)

      let(:custom_logger_class) do
        Class.new do
          include Ast::Merge::DebugLogger

          class << self
            attr_accessor :env_var_name, :log_prefix
          end

          self.env_var_name = 'CUSTOM_DEBUG'
          self.log_prefix = '[Custom]'
        end
      end

      it 'uses class env_var_name when class responds to it' do
        instance = custom_logger_class.new
        expect(instance.env_var_name).to eq('CUSTOM_DEBUG')
      end

      it 'uses class log_prefix when class responds to it' do
        instance = custom_logger_class.new
        expect(instance.log_prefix).to eq('[Custom]')
      end

      it "falls back to base when class doesn't respond" do
        basic_class = Class.new do
          include Ast::Merge::DebugLogger
        end
        instance = basic_class.new
        expect(instance.env_var_name).to eq('AST_MERGE_DEBUG')
        expect(instance.log_prefix).to eq('[Ast::Merge]')
      end
    end

    describe 'module extending with custom config' do
      let(:extended_module) do
        Module.new do
          extend Ast::Merge::DebugLogger

          self.env_var_name = 'EXTENDED_DEBUG'
          self.log_prefix = '[Extended]'
        end
      end

      it 'uses own env_var_name' do
        expect(extended_module.env_var_name).to eq('EXTENDED_DEBUG')
      end

      it 'uses own log_prefix' do
        expect(extended_module.log_prefix).to eq('[Extended]')
      end
    end
  end

  describe 'FreezeNode.freeze_start? and freeze_end? edge cases' do
    it 'returns false for nil line in freeze_start?' do
      result = Ast::Merge::FreezeNodeBase.freeze_start?(nil)
      expect(result).to be false
    end

    it 'returns false for nil line in freeze_end?' do
      result = Ast::Merge::FreezeNodeBase.freeze_end?(nil)
      expect(result).to be false
    end
  end

  describe 'FreezeNode::InvalidStructureError' do
    it 'stores unclosed_nodes' do
      error = Ast::Merge::FreezeNodeBase::InvalidStructureError.new(
        'Unclosed freeze block',
        start_line: 5,
        end_line: 10,
        unclosed_nodes: %i[node1 node2]
      )
      expect(error.unclosed_nodes).to eq(%i[node1 node2])
      expect(error.start_line).to eq(5)
      expect(error.end_line).to eq(10)
    end
  end

  describe 'FreezeNode::Location' do
    it 'checks if line is covered' do
      location = Ast::Merge::FreezeNodeBase::Location.new(5, 10)
      expect(location.cover?(7)).to be true
      expect(location.cover?(4)).to be false
      expect(location.cover?(11)).to be false
      expect(location.cover?(5)).to be true
      expect(location.cover?(10)).to be true
    end
  end

  describe 'FreezeNode resolve_lines edge cases (line 376)' do
    # Tests for uncovered else branch when analysis.lines returns nil

    it 'falls back to content when analysis.lines returns nil' do
      # Create analysis that responds to lines but returns nil
      analysis_with_nil_lines = double('Analysis')
      allow(analysis_with_nil_lines).to receive(:respond_to?).with(:lines).and_return(true)
      allow(analysis_with_nil_lines).to receive(:lines).and_return(nil)

      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 2,
        analysis: analysis_with_nil_lines,
        content: "line1\nline2"
      )

      # Should fall through to content.split since all_lines is nil
      expect(freeze_node.lines).to eq(%w[line1 line2])
    end
  end

  describe 'FreezeNode extract_token_from_marker edge cases (line 395)' do
    # Tests for uncovered then branch when @start_marker is nil

    it 'returns nil reason when start_marker is nil (via extract_token_from_marker)' do
      # This specifically tests line 395: return nil unless @start_marker
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'content'
        # start_marker is not provided, so it's nil
      )

      # Calling reason will internally call extract_token_from_marker
      # which should hit the `return nil unless @start_marker` branch
      expect(freeze_node.reason).to be_nil
    end
  end
end
