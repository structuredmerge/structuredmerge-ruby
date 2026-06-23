# frozen_string_literal: true

RSpec.describe Ast::Merge::MatchRefinerBase do
  describe 'MatchResult struct' do
    let(:result) do
      described_class::MatchResult.new(
        template_node: :template,
        dest_node: :dest,
        score: 0.85,
        metadata: { reason: 'test' }
      )
    end

    describe '#high_confidence?' do
      it 'returns true when score >= threshold' do
        expect(result.high_confidence?(threshold: 0.8)).to be true
      end

      it 'returns false when score < threshold' do
        expect(result.high_confidence?(threshold: 0.9)).to be false
      end

      it 'uses 0.8 as default threshold' do
        expect(result.high_confidence?).to be true
      end
    end

    describe '#<=>' do
      let(:lower_result) do
        described_class::MatchResult.new(
          template_node: :t2,
          dest_node: :d2,
          score: 0.5,
          metadata: {}
        )
      end

      it 'compares by score' do
        expect(result <=> lower_result).to eq(1)
        expect(lower_result <=> result).to eq(-1)
      end

      it 'allows sorting' do
        results = [lower_result, result]
        expect(results.sort).to eq([lower_result, result])
      end
    end
  end

  describe '#initialize' do
    context 'with default options' do
      subject(:refiner) { described_class.new }

      it 'sets default threshold' do
        expect(refiner.threshold).to eq(0.5)
      end

      it 'sets empty node_types' do
        expect(refiner.node_types).to eq([])
      end
    end

    context 'with custom options' do
      subject(:refiner) { described_class.new(threshold: 0.7, node_types: %i[table list]) }

      it 'sets custom threshold' do
        expect(refiner.threshold).to eq(0.7)
      end

      it 'sets custom node_types' do
        expect(refiner.node_types).to eq(%i[table list])
      end
    end

    context 'with threshold bounds' do
      it 'clamps threshold to minimum 0.0' do
        refiner = described_class.new(threshold: -0.5)
        expect(refiner.threshold).to eq(0.0)
      end

      it 'clamps threshold to maximum 1.0' do
        refiner = described_class.new(threshold: 1.5)
        expect(refiner.threshold).to eq(1.0)
      end
    end
  end

  describe '#call' do
    subject(:refiner) { described_class.new }

    it 'raises NotImplementedError' do
      expect { refiner.call([], [], {}) }.to raise_error(
        NotImplementedError,
        /must be implemented/
      )
    end
  end

  describe '#handles_type?' do
    context 'with empty node_types (handles all)' do
      subject(:refiner) { described_class.new(node_types: []) }

      it 'returns true for any type' do
        expect(refiner.handles_type?(:table)).to be true
        expect(refiner.handles_type?(:list)).to be true
        expect(refiner.handles_type?(:paragraph)).to be true
      end
    end

    context 'with specific node_types' do
      subject(:refiner) { described_class.new(node_types: %i[table list]) }

      it 'returns true for matching types' do
        expect(refiner.handles_type?(:table)).to be true
        expect(refiner.handles_type?(:list)).to be true
      end

      it 'returns false for non-matching types' do
        expect(refiner.handles_type?(:paragraph)).to be false
        expect(refiner.handles_type?(:heading)).to be false
      end
    end
  end

  describe 'subclass implementation' do
    subject(:refiner) { custom_refiner_class.new(threshold: 0.5) }

    let(:custom_refiner_class) do
      Class.new(described_class) do
        def call(template_nodes, dest_nodes, _context = {})
          greedy_match(template_nodes, dest_nodes) do |t, d|
            t == d ? 1.0 : 0.0
          end
        end
      end
    end

    describe '#call with matching nodes' do
      it 'returns match results for identical nodes' do
        template = %i[a b c]
        dest = %i[a b d]

        results = refiner.call(template, dest)

        expect(results.size).to eq(2)
        expect(results.map(&:template_node)).to contain_exactly(:a, :b)
        expect(results.map(&:dest_node)).to contain_exactly(:a, :b)
        expect(results.map(&:score)).to all(eq(1.0))
      end

      it 'returns empty array when no matches' do
        template = %i[x y]
        dest = %i[a b]

        results = refiner.call(template, dest)

        expect(results).to be_empty
      end
    end
  end

  describe 'protected helper methods' do
    subject(:refiner) { test_refiner_class.new }

    let(:test_refiner_class) do
      Class.new(described_class) do
        # Expose protected methods for testing
        public :filter_by_type, :node_type, :match_result, :find_best_match, :greedy_match
      end
    end

    describe '#filter_by_type' do
      let(:nodes) do
        [
          Struct.new(:type).new(:table),
          Struct.new(:type).new(:list),
          Struct.new(:type).new(:table),
          Struct.new(:type).new(:paragraph)
        ]
      end

      it 'filters nodes by type' do
        tables = refiner.filter_by_type(nodes, :table)
        expect(tables.size).to eq(2)
        expect(tables.map(&:type)).to all(eq(:table))
      end

      it 'returns empty array when no matches' do
        headings = refiner.filter_by_type(nodes, :heading)
        expect(headings).to be_empty
      end
    end

    describe '#node_type' do
      it 'returns type from node with #type method' do
        node = Struct.new(:type).new(:table)
        expect(refiner.node_type(node)).to eq(:table)
      end

      it 'returns class-based type for objects without #type' do
        node = Object.new
        expect(refiner.node_type(node)).to eq(:Object)
      end
    end

    describe '#match_result' do
      it 'creates a MatchResult struct' do
        result = refiner.match_result(:t, :d, 0.9, { key: 'value' })

        expect(result).to be_a(described_class::MatchResult)
        expect(result.template_node).to eq(:t)
        expect(result.dest_node).to eq(:d)
        expect(result.score).to eq(0.9)
        expect(result.metadata).to eq({ key: 'value' })
      end
    end

    describe '#find_best_match' do
      let(:template_node) { :template }
      let(:dest_nodes) { %i[d1 d2 d3] }

      it 'finds the best matching node above threshold' do
        result = refiner.find_best_match(template_node, dest_nodes) do |_t, d|
          case d
          when :d1 then 0.6
          when :d2 then 0.9
          when :d3 then 0.7
          end
        end

        expect(result.dest_node).to eq(:d2)
        expect(result.score).to eq(0.9)
      end

      it 'returns nil when no match above threshold' do
        result = refiner.find_best_match(template_node, dest_nodes) do |_t, _d|
          0.3 # Below default threshold of 0.5
        end

        expect(result).to be_nil
      end

      it 'skips nodes in used_dest_nodes set' do
        used = Set.new([:d2])

        result = refiner.find_best_match(template_node, dest_nodes, used_dest_nodes: used) do |_t, d|
          case d
          when :d1 then 0.6
          when :d2 then 0.9 # Would be best but is used
          when :d3 then 0.7
          end
        end

        expect(result.dest_node).to eq(:d3)
      end
    end

    describe '#greedy_match' do
      let(:template_nodes) { %i[t1 t2 t3] }
      let(:dest_nodes) { %i[d1 d2 d3] }

      it 'greedily matches nodes by best score' do
        scores = {
          %i[t1 d1] => 0.8,
          %i[t1 d2] => 0.6,
          %i[t2 d1] => 0.9, # Best overall, t2->d1
          %i[t2 d2] => 0.7,
          %i[t3 d3] => 0.75
        }

        results = refiner.greedy_match(template_nodes, dest_nodes) do |t, d|
          scores[[t, d]] || 0.0
        end

        # t2->d1 (0.9), t1->d2 (0.6), t3->d3 (0.75)
        expect(results.size).to eq(3)

        # Best match t2->d1 should be included
        t2_match = results.find { |r| r.template_node == :t2 }
        expect(t2_match.dest_node).to eq(:d1)
        expect(t2_match.score).to eq(0.9)

        # Since d1 is taken, t1 gets d2
        t1_match = results.find { |r| r.template_node == :t1 }
        expect(t1_match.dest_node).to eq(:d2)
      end

      it 'respects threshold' do
        results = refiner.greedy_match(template_nodes, dest_nodes) do |_t, _d|
          0.3 # Below threshold
        end

        expect(results).to be_empty
      end

      it 'ensures each node is matched at most once' do
        # All template nodes want d1
        results = refiner.greedy_match(template_nodes, dest_nodes) do |_t, d|
          d == :d1 ? 0.9 : 0.6
        end

        dest_nodes_matched = results.map(&:dest_node)
        expect(dest_nodes_matched.uniq.size).to eq(dest_nodes_matched.size)

        template_nodes_matched = results.map(&:template_node)
        expect(template_nodes_matched.uniq.size).to eq(template_nodes_matched.size)
      end
    end
  end

  describe 'using lambda as refiner' do
    it 'lambdas can be used instead of subclass' do
      lambda_refiner = lambda do |template, dest, _ctx|
        matches = []
        template.each do |t|
          dest.each do |d|
            next unless t == d

            matches << Ast::Merge::MatchRefinerBase::MatchResult.new(
              template_node: t,
              dest_node: d,
              score: 1.0,
              metadata: {}
            )
          end
        end
        matches
      end

      results = lambda_refiner.call(%i[a b], %i[a c], {})

      expect(results.size).to eq(1)
      expect(results.first.template_node).to eq(:a)
    end
  end

  describe '#node_type' do
    let(:refiner) { described_class.new }

    context 'when node responds to :type' do
      let(:node_with_type) do
        double('TypedNode', type: :block_quote)
      end

      it 'returns the type' do
        result = refiner.send(:node_type, node_with_type)
        expect(result).to eq(:block_quote)
      end
    end

    context 'when node does not respond to :type but has class' do
      let(:plain_object) { Object.new }

      it 'returns class name as symbol' do
        result = refiner.send(:node_type, plain_object)
        expect(result).to eq(:Object)
      end
    end

    context 'with namespaced class' do
      let(:namespaced_node) do
        # Create a class with a namespaced name
        node_class = Class.new do
          class << self
            def name
              'Ast::Merge::TestNode'
            end
          end
        end
        node_class.new
      end

      it 'returns just the last part of the class name' do
        result = refiner.send(:node_type, namespaced_node)
        expect(result).to eq(:TestNode)
      end
    end
  end
end
