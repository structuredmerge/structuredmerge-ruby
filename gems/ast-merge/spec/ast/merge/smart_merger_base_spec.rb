# frozen_string_literal: true

RSpec.describe Ast::Merge::SmartMergerBase do
  # Create a minimal concrete implementation for testing
  let(:mock_analysis_class) do
    Class.new do
      attr_reader :content, :statements, :source_lines

      def initialize(content, **options)
        @content = content
        @freeze_token = options[:freeze_token]
        @signature_generator = options[:signature_generator]
        @source_lines = content.lines
        @statements = parse_statements
      end

      def valid?
        true
      end

      def source_range(start_line, end_line)
        @source_lines[(start_line - 1)..(end_line - 1)].join
      end

      private

      def parse_statements
        @source_lines.map.with_index do |line, idx|
          MockNode.new(line.strip, idx + 1)
        end.reject { |n| n.content.empty? }
      end
    end
  end

  let(:mock_result_class) do
    Class.new do
      attr_accessor :content, :lines

      def initialize(**_options)
        @lines = []
        @content = ''
      end

      def to_s
        @content
      end

      def decision_summary
        { lines: @lines.size }
      end
    end
  end

  let(:concrete_merger_class) do
    analysis = mock_analysis_class
    result = mock_result_class

    Class.new(described_class) do
      define_method(:analysis_class) { analysis }
      define_method(:result_class) { result }
      define_method(:default_freeze_token) { 'test-merge' }

      private

      define_method(:perform_merge) do
        # Simple merge: combine both analyses
        @result.lines = @dest_analysis.statements.map(&:to_s)
        @result.content = @result.lines.join("\n")
        @result
      end
    end
  end

  # Define MockNode using stub_const to avoid leaky constant declaration
  let(:mock_node_class) do
    Struct.new(:content, :line, keyword_init: false) do
      def to_s
        content
      end
    end
  end

  before do
    stub_const('MockNode', mock_node_class)
  end

  describe '#initialize' do
    let(:template) { "line one\nline two" }
    let(:dest) { "line one\nline three" }

    it 'creates a merger with default options' do
      merger = concrete_merger_class.new(template, dest)

      expect(merger.preference).to eq(:destination)
      expect(merger.add_template_only_nodes).to be false
      expect(merger.freeze_token).to eq('test-merge')
    end

    it 'accepts custom preference' do
      merger = concrete_merger_class.new(template, dest, preference: :template)
      expect(merger.preference).to eq(:template)
    end

    it 'accepts custom add_template_only_nodes' do
      merger = concrete_merger_class.new(template, dest, add_template_only_nodes: true)
      expect(merger.add_template_only_nodes).to be true
    end

    it 'accepts custom freeze_token' do
      merger = concrete_merger_class.new(template, dest, freeze_token: 'custom-freeze')
      expect(merger.freeze_token).to eq('custom-freeze')
    end

    it 'accepts signature_generator' do
      generator = ->(node) { [:custom, node.to_s] }
      merger = concrete_merger_class.new(template, dest, signature_generator: generator)
      expect(merger.signature_generator).to eq(generator)
    end

    it 'accepts match_refiner' do
      refiner = double('refiner')
      merger = concrete_merger_class.new(template, dest, match_refiner: refiner)
      expect(merger.match_refiner).to eq(refiner)
    end

    it 'creates template_analysis' do
      merger = concrete_merger_class.new(template, dest)
      expect(merger.template_analysis).not_to be_nil
      expect(merger.template_analysis.content).to eq(template)
    end

    it 'creates dest_analysis' do
      merger = concrete_merger_class.new(template, dest)
      expect(merger.dest_analysis).not_to be_nil
      expect(merger.dest_analysis.content).to eq(dest)
    end
  end

  describe '#merge' do
    let(:template) { 'template line' }
    let(:dest) { 'dest line' }

    it 'returns merged content as a string' do
      merger = concrete_merger_class.new(template, dest)
      result = merger.merge

      expect(result).to be_a(String)
      expect(result).to eq('dest line')
    end
  end

  describe '#merge_result' do
    let(:template) { 'line one' }
    let(:dest) { 'line two' }

    it 'returns the result object' do
      merger = concrete_merger_class.new(template, dest)
      result = merger.merge_result

      expect(result).to respond_to(:to_s)
    end

    it 'memoizes the result' do
      merger = concrete_merger_class.new(template, dest)
      result1 = merger.merge_result
      result2 = merger.merge_result

      expect(result1).to be(result2)
    end
  end

  describe '#merge_with_debug' do
    let(:template) { 'line one' }
    let(:dest) { 'line two' }

    it 'returns a hash with content and statistics' do
      merger = concrete_merger_class.new(template, dest)
      result = merger.merge_with_debug

      expect(result).to be_a(Hash)
      expect(result).to have_key(:content)
      expect(result).to have_key(:statistics)
      expect(result[:content]).to be_a(String)
    end
  end

  describe '#stats' do
    let(:template) { 'line one' }
    let(:dest) { 'line two' }

    it 'returns merge statistics' do
      merger = concrete_merger_class.new(template, dest)
      stats = merger.stats

      expect(stats).to be_a(Hash)
    end
  end

  describe 'unresolved helper surface' do
    let(:template) { 'line one' }
    let(:dest) { 'line two' }
    let(:merger) { concrete_merger_class.new(template, dest) }
    let(:unresolved_helper_host) { merger }
    let(:unresolved_case_id_parts) { %w[bash variable_assignment MY_VAR] }
    let(:expected_unresolved_case_id) { 'bash-variable_assignment-MY_VAR-12' }

    it_behaves_like 'Ast::Merge::UnresolvedHelperContract'
  end

  describe 'with regions' do
    let(:yaml_detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    let(:template) do
      <<~MD
        ---
        title: Template
        ---
        Body content
      MD
    end

    let(:dest) do
      <<~MD
        ---
        title: Destination
        author: Jane
        ---
        Body content modified
      MD
    end

    it 'accepts regions configuration' do
      merger = concrete_merger_class.new(
        template,
        dest,
        regions: [{ detector: yaml_detector }]
      )

      expect(merger.regions_configured?).to be true
    end

    it 'accepts custom region_placeholder' do
      merger = concrete_merger_class.new(
        template,
        dest,
        regions: [{ detector: yaml_detector }],
        region_placeholder: '###CUSTOM_'
      )

      expect(merger.instance_variable_get(:@region_placeholder_prefix)).to eq('###CUSTOM_')
    end
  end

  describe 'abstract methods' do
    let(:abstract_class) do
      Class.new(described_class)
    end

    it 'raises NotImplementedError for analysis_class' do
      # Need to bypass initialize to test the abstract method directly
      instance = abstract_class.allocate

      expect { instance.send(:analysis_class) }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for perform_merge' do
      instance = abstract_class.allocate

      expect { instance.send(:perform_merge) }.to raise_error(NotImplementedError)
    end
  end

  describe 'default implementations' do
    let(:instance) { concrete_merger_class.new('t', 'd') }

    it 'default_freeze_token can be overridden' do
      expect(instance.send(:default_freeze_token)).to eq('test-merge')
    end

    it 'resolver_class returns nil by default' do
      # Test on base class
      base_instance = described_class.allocate
      expect(base_instance.send(:resolver_class)).to be_nil
    end

    it 'aligner_class returns nil by default' do
      base_instance = described_class.allocate
      expect(base_instance.send(:aligner_class)).to be_nil
    end

    it 'build_analysis_options returns empty hash by default' do
      base_instance = described_class.allocate
      expect(base_instance.send(:build_analysis_options)).to eq({})
    end

    it 'build_resolver_options returns empty hash by default' do
      base_instance = described_class.allocate
      expect(base_instance.send(:build_resolver_options)).to eq({})
    end
  end

  describe 'parse error handling' do
    let(:failing_analysis_class) do
      Class.new do
        def initialize(_content, **_options)
          raise StandardError, 'Parse failed'
        end
      end
    end

    let(:failing_merger_class) do
      analysis = failing_analysis_class

      Class.new(described_class) do
        define_method(:analysis_class) { analysis }
        define_method(:default_freeze_token) { 'test' }
      end
    end

    it 'raises TemplateParseError for template parse failures' do
      expect do
        failing_merger_class.new('bad template', 'good dest')
      end.to raise_error(Ast::Merge::TemplateParseError)
    end
  end

  describe 'inheritance' do
    it 'includes RegionMergeable' do
      expect(described_class.ancestors).to include(Ast::Merge::Detector::Mergeable)
    end
  end

  describe '#merge_with_debug return structure' do
    it 'returns hash with content and statistics' do
      merger = concrete_merger_class.new('template', 'dest')
      result = merger.merge_with_debug

      expect(result).to have_key(:content)
      expect(result).to have_key(:statistics)
      expect(result.keys).to eq(%i[content statistics])
    end
  end

  describe 'region substitution in merge_result' do
    let(:yaml_detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    let(:template_with_yaml) do
      <<~MD
        ---
        title: Template Title
        ---
        Body content
      MD
    end

    let(:dest_with_yaml) do
      <<~MD
        ---
        title: Dest Title
        author: Jane
        ---
        Body content
      MD
    end

    it 'substitutes regions when regions_configured?' do
      merger = concrete_merger_class.new(
        template_with_yaml,
        dest_with_yaml,
        regions: [{ detector: yaml_detector }]
      )

      result = merger.merge
      expect(result).to include('title: Dest Title')
    end
  end

  describe 'update_result_content' do
    it 'updates content via content=' do
      merger = concrete_merger_class.new('t', 'd')
      result = merger.merge_result

      merger.send(:update_result_content, result, 'new content')
      expect(result.to_s).to eq('new content')
    end
  end

  describe 'parse error handling with context' do
    context 'when analysis raises an error' do
      let(:error_analysis_class) do
        Class.new do
          def initialize(_content, **_options)
            raise 'Parse failed'
          end
        end
      end

      let(:error_merger_class) do
        analysis = error_analysis_class

        Class.new(described_class) do
          define_method(:analysis_class) { analysis }
          define_method(:default_freeze_token) { 'test' }
        end
      end

      it 'raises TemplateParseError' do
        expect do
          error_merger_class.new('bad template', 'good dest')
        end.to raise_error(Ast::Merge::TemplateParseError)
      end
    end
  end

  describe 'build_result edge cases' do
    context 'when result_class has zero-arity initializer' do
      let(:zero_arity_result) do
        Class.new do
          attr_accessor :content

          def initialize
            @content = 'zero arity'
          end

          def to_s
            @content
          end

          def decision_summary
            {}
          end
        end
      end

      let(:zero_arity_merger_class) do
        analysis = mock_analysis_class
        result = zero_arity_result

        Class.new(described_class) do
          define_method(:analysis_class) { analysis }
          define_method(:result_class) { result }
          define_method(:default_freeze_token) { 'test' }

          private

          define_method(:perform_merge) do
            @result.content = 'merged'
            @result
          end
        end
      end

      it 'creates result with no arguments' do
        merger = zero_arity_merger_class.new('t', 'd')
        result = merger.merge_result
        expect(result).not_to be_nil
      end
    end
  end

  describe 'with aligner_class' do
    let(:mock_aligner_class) do
      Class.new do
        def initialize(template_analysis, dest_analysis, **_options)
          @template_analysis = template_analysis
          @dest_analysis = dest_analysis
        end

        def align
          []
        end
      end
    end

    let(:merger_with_aligner_class) do
      analysis = mock_analysis_class
      result = mock_result_class
      aligner = mock_aligner_class

      Class.new(described_class) do
        define_method(:analysis_class) { analysis }
        define_method(:result_class) { result }
        define_method(:aligner_class) { aligner }
        define_method(:default_freeze_token) { 'test' }

        private

        define_method(:perform_merge) do
          @result.content = 'merged with aligner'
          @result
        end
      end
    end

    it 'builds aligner when aligner_class is defined' do
      merger = merger_with_aligner_class.new('t', 'd')
      expect(merger.aligner).not_to be_nil
    end
  end
end
