# frozen_string_literal: true

RSpec.describe Ast::Merge::MatchScoreBase do
  describe '#initialize' do
    let(:node_a) { double('node_a') }
    let(:node_b) { double('node_b') }
    let(:algorithm) { ->(_a, _b) { 0.75 } }

    it 'stores node_a' do
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)
      expect(scorer.node_a).to eq(node_a)
    end

    it 'stores node_b' do
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)
      expect(scorer.node_b).to eq(node_b)
    end

    it 'stores algorithm' do
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)
      expect(scorer.algorithm).to eq(algorithm)
    end

    it 'uses default threshold' do
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)
      expect(scorer.threshold).to eq(0.5)
    end

    it 'accepts custom threshold' do
      scorer = described_class.new(node_a, node_b, algorithm: algorithm, threshold: 0.8)
      expect(scorer.threshold).to eq(0.8)
    end

    it "raises ArgumentError if algorithm doesn't respond to :call" do
      expect do
        described_class.new(node_a, node_b, algorithm: 'not callable')
      end.to raise_error(ArgumentError, 'algorithm must respond to :call')
    end

    context 'with callable object' do
      let(:callable_class) do
        Class.new do
          def call(_a, _b)
            0.9
          end
        end
      end

      it 'accepts any object responding to :call' do
        scorer = described_class.new(node_a, node_b, algorithm: callable_class.new)
        expect(scorer.score).to eq(0.9)
      end
    end
  end

  describe '#score' do
    let(:node_a) { double('node_a', value: 10) }
    let(:node_b) { double('node_b', value: 10) }

    it 'computes score using algorithm' do
      algorithm = ->(a, b) { a.value == b.value ? 1.0 : 0.0 }
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)
      expect(scorer.score).to eq(1.0)
    end

    it 'caches the score' do
      call_count = 0
      algorithm = lambda { |_a, _b|
        call_count += 1
        0.5
      }
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)

      scorer.score
      scorer.score
      scorer.score

      expect(call_count).to eq(1)
    end

    it 'clamps scores above 1.0' do
      algorithm = ->(_a, _b) { 1.5 }
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)
      expect(scorer.score).to eq(1.0)
    end

    it 'clamps scores below 0.0' do
      algorithm = ->(_a, _b) { -0.5 }
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)
      expect(scorer.score).to eq(0.0)
    end
  end

  describe '#match?' do
    let(:node_a) { double('node_a') }
    let(:node_b) { double('node_b') }

    context 'with default threshold (0.5)' do
      it 'returns true when score >= 0.5' do
        algorithm = ->(_a, _b) { 0.5 }
        scorer = described_class.new(node_a, node_b, algorithm: algorithm)
        expect(scorer.match?).to be true
      end

      it 'returns false when score < 0.5' do
        algorithm = ->(_a, _b) { 0.49 }
        scorer = described_class.new(node_a, node_b, algorithm: algorithm)
        expect(scorer.match?).to be false
      end
    end

    context 'with custom threshold' do
      it 'respects custom threshold' do
        algorithm = ->(_a, _b) { 0.7 }
        scorer = described_class.new(node_a, node_b, algorithm: algorithm, threshold: 0.8)
        expect(scorer.match?).to be false
      end
    end
  end

  describe '#<=>' do
    let(:node_a) { double('node_a') }
    let(:node_b) { double('node_b') }

    it 'compares scorers by score' do
      scorer_low = described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.3 })
      scorer_high = described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.9 })

      expect(scorer_low <=> scorer_high).to eq(-1)
      expect(scorer_high <=> scorer_low).to eq(1)
    end

    it 'returns 0 for equal scores' do
      scorer1 = described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.5 })
      scorer2 = described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.5 })

      expect(scorer1 <=> scorer2).to eq(0)
    end

    it 'allows sorting' do
      scorers = [
        described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.5 }),
        described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.9 }),
        described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.1 })
      ]

      sorted = scorers.sort
      expect(sorted.map(&:score)).to eq([0.1, 0.5, 0.9])
    end
  end

  describe 'Comparable interface' do
    let(:node_a) { double('node_a') }
    let(:node_b) { double('node_b') }
    let(:node_c) { double('node_c') }

    let(:scorer_low) { described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.3 }) }
    let(:scorer_mid) { described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.5 }) }
    let(:scorer_high) { described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.9 }) }
    let(:scorer_mid_dup) { described_class.new(node_a, node_c, algorithm: ->(_a, _b) { 0.5 }) }

    describe '#<' do
      it 'returns true when score is less' do
        expect(scorer_low < scorer_mid).to be true
      end

      it 'returns false when score is greater' do
        expect(scorer_high < scorer_mid).to be false
      end

      it 'returns false when score is equal' do
        expect(scorer_mid < scorer_mid_dup).to be false
      end
    end

    describe '#<=' do
      it 'returns true when score is less' do
        expect(scorer_low <= scorer_mid).to be true
      end

      it 'returns true when score is equal' do
        expect(scorer_mid <= scorer_mid_dup).to be true
      end

      it 'returns false when score is greater' do
        expect(scorer_high <= scorer_mid).to be false
      end
    end

    describe '#>' do
      it 'returns true when score is greater' do
        expect(scorer_high > scorer_mid).to be true
      end

      it 'returns false when score is less' do
        expect(scorer_low > scorer_mid).to be false
      end

      it 'returns false when score is equal' do
        expect(scorer_mid > scorer_mid_dup).to be false
      end
    end

    describe '#>=' do
      it 'returns true when score is greater' do
        expect(scorer_high >= scorer_mid).to be true
      end

      it 'returns true when score is equal' do
        expect(scorer_mid >= scorer_mid_dup).to be true
      end

      it 'returns false when score is less' do
        expect(scorer_low >= scorer_mid).to be false
      end
    end

    describe '#between?' do
      it 'returns true when score is between bounds' do
        expect(scorer_mid.between?(scorer_low, scorer_high)).to be true
      end

      it 'returns true when score equals lower bound' do
        expect(scorer_mid.between?(scorer_mid_dup, scorer_high)).to be true
      end

      it 'returns true when score equals upper bound' do
        expect(scorer_mid.between?(scorer_low, scorer_mid_dup)).to be true
      end

      it 'returns false when score is below lower bound' do
        expect(scorer_low.between?(scorer_mid, scorer_high)).to be false
      end

      it 'returns false when score is above upper bound' do
        expect(scorer_high.between?(scorer_low, scorer_mid)).to be false
      end
    end

    describe '#clamp' do
      it 'returns self when within range' do
        result = scorer_mid.clamp(scorer_low, scorer_high)
        expect(result).to eq(scorer_mid)
      end

      it 'returns lower bound when below range' do
        result = scorer_low.clamp(scorer_mid, scorer_high)
        expect(result).to eq(scorer_mid)
      end

      it 'returns upper bound when above range' do
        result = scorer_high.clamp(scorer_low, scorer_mid)
        expect(result).to eq(scorer_mid)
      end
    end
  end

  describe '#hash' do
    # Use simple structs instead of doubles for stable hash/equality behavior
    let(:node_class) { Struct.new(:id) }
    let(:node_a) { node_class.new(:a) }
    let(:node_b) { node_class.new(:b) }
    let(:node_c) { node_class.new(:c) }
    let(:algorithm) { ->(_a, _b) { 0.5 } }

    it 'returns an Integer' do
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)
      expect(scorer.hash).to be_a(Integer)
    end

    it 'returns same hash for equivalent scorers' do
      # Create equivalent nodes (same struct values)
      node_a1 = node_class.new(:a)
      node_b1 = node_class.new(:b)
      node_a2 = node_class.new(:a)
      node_b2 = node_class.new(:b)

      scorer1 = described_class.new(node_a1, node_b1, algorithm: algorithm)
      scorer2 = described_class.new(node_a2, node_b2, algorithm: algorithm)

      expect(scorer1.hash).to eq(scorer2.hash)
    end

    it 'returns different hash for different node_a' do
      scorer1 = described_class.new(node_a, node_b, algorithm: algorithm)
      scorer2 = described_class.new(node_c, node_b, algorithm: algorithm)

      expect(scorer1.hash).not_to eq(scorer2.hash)
    end

    it 'returns different hash for different node_b' do
      scorer1 = described_class.new(node_a, node_b, algorithm: algorithm)
      scorer2 = described_class.new(node_a, node_c, algorithm: algorithm)

      expect(scorer1.hash).not_to eq(scorer2.hash)
    end

    it 'returns different hash for different scores' do
      scorer1 = described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.5 })
      scorer2 = described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.9 })

      expect(scorer1.hash).not_to eq(scorer2.hash)
    end

    it 'allows scorers to be used as Hash keys' do
      # Create equivalent nodes
      node_a1 = node_class.new(:a)
      node_b1 = node_class.new(:b)
      node_a2 = node_class.new(:a)
      node_b2 = node_class.new(:b)

      scorer1 = described_class.new(node_a1, node_b1, algorithm: algorithm)
      scorer2 = described_class.new(node_a2, node_b2, algorithm: algorithm)

      hash = { scorer1 => 'value1' }
      expect(hash[scorer2]).to eq('value1')
    end
  end

  describe '#eql?' do
    let(:node_class) { Struct.new(:id) }
    let(:node_a) { node_class.new(:a) }
    let(:node_b) { node_class.new(:b) }
    let(:node_c) { node_class.new(:c) }
    let(:algorithm) { ->(_a, _b) { 0.5 } }

    it 'returns true for equivalent scorers' do
      node_a1 = node_class.new(:a)
      node_b1 = node_class.new(:b)
      node_a2 = node_class.new(:a)
      node_b2 = node_class.new(:b)

      scorer1 = described_class.new(node_a1, node_b1, algorithm: algorithm)
      scorer2 = described_class.new(node_a2, node_b2, algorithm: algorithm)

      expect(scorer1.eql?(scorer2)).to be true
    end

    it 'returns false for different node_a' do
      scorer1 = described_class.new(node_a, node_b, algorithm: algorithm)
      scorer2 = described_class.new(node_c, node_b, algorithm: algorithm)

      expect(scorer1.eql?(scorer2)).to be false
    end

    it 'returns false for different node_b' do
      scorer1 = described_class.new(node_a, node_b, algorithm: algorithm)
      scorer2 = described_class.new(node_a, node_c, algorithm: algorithm)

      expect(scorer1.eql?(scorer2)).to be false
    end

    it 'returns false for different scores' do
      scorer1 = described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.5 })
      scorer2 = described_class.new(node_a, node_b, algorithm: ->(_a, _b) { 0.9 })

      expect(scorer1.eql?(scorer2)).to be false
    end

    it 'returns false for non-MatchScoreBase objects' do
      scorer = described_class.new(node_a, node_b, algorithm: algorithm)

      expect(scorer.eql?('not a scorer')).to be false
      expect(scorer.eql?(nil)).to be false
      expect(scorer.eql?(0.5)).to be false
    end
  end

  describe 'Hash and Set compatibility' do
    let(:node_class) { Struct.new(:id) }
    let(:algorithm) { ->(_a, _b) { 0.5 } }

    it 'works correctly in a Set' do
      node_a1 = node_class.new(:a)
      node_b1 = node_class.new(:b)
      node_a2 = node_class.new(:a)
      node_b2 = node_class.new(:b)
      node_c = node_class.new(:c)

      scorer1 = described_class.new(node_a1, node_b1, algorithm: algorithm)
      scorer2 = described_class.new(node_a2, node_b2, algorithm: algorithm) # equivalent to scorer1
      scorer3 = described_class.new(node_a1, node_c, algorithm: algorithm) # different

      set = Set.new([scorer1, scorer2, scorer3])
      expect(set.size).to eq(2) # scorer1 and scorer2 are equivalent
    end

    it 'works correctly with Hash#key?' do
      node_a1 = node_class.new(:a)
      node_b1 = node_class.new(:b)
      node_a2 = node_class.new(:a)
      node_b2 = node_class.new(:b)

      scorer1 = described_class.new(node_a1, node_b1, algorithm: algorithm)
      scorer2 = described_class.new(node_a2, node_b2, algorithm: algorithm)

      hash = { scorer1 => 'value' }
      expect(hash.key?(scorer2)).to be true
    end

    it 'works correctly with Array#uniq' do
      node_a1 = node_class.new(:a)
      node_b1 = node_class.new(:b)
      node_a2 = node_class.new(:a)
      node_b2 = node_class.new(:b)
      node_c = node_class.new(:c)

      scorer1 = described_class.new(node_a1, node_b1, algorithm: algorithm)
      scorer2 = described_class.new(node_a2, node_b2, algorithm: algorithm)
      scorer3 = described_class.new(node_a1, node_c, algorithm: algorithm)

      array = [scorer1, scorer2, scorer3]
      expect(array.uniq.size).to eq(2)
    end
  end

  describe 'algorithm examples' do
    context 'with type-based matching' do
      let(:algorithm) do
        ->(a, b) { a[:type] == b[:type] ? 1.0 : 0.0 }
      end

      it 'scores matching types as 1.0' do
        node_a = { type: :heading }
        node_b = { type: :heading }
        scorer = described_class.new(node_a, node_b, algorithm: algorithm)
        expect(scorer.score).to eq(1.0)
      end

      it 'scores non-matching types as 0.0' do
        node_a = { type: :heading }
        node_b = { type: :paragraph }
        scorer = described_class.new(node_a, node_b, algorithm: algorithm)
        expect(scorer.score).to eq(0.0)
      end
    end

    context 'with content similarity' do
      let(:algorithm) do
        lambda { |a, b|
          common = (a[:words] & b[:words]).size
          total = (a[:words] | b[:words]).size
          total > 0 ? common.to_f / total : 0.0
        }
      end

      it 'scores identical content as 1.0' do
        words = %w[hello world]
        node_a = { words: words }
        node_b = { words: words }
        scorer = described_class.new(node_a, node_b, algorithm: algorithm)
        expect(scorer.score).to eq(1.0)
      end

      it 'scores partial overlap appropriately' do
        node_a = { words: %w[hello world foo] }
        node_b = { words: %w[hello world bar] }
        scorer = described_class.new(node_a, node_b, algorithm: algorithm)
        # 2 common (hello, world) / 4 total (hello, world, foo, bar) = 0.5
        expect(scorer.score).to eq(0.5)
      end

      it 'scores no overlap as 0.0' do
        node_a = { words: %w[foo bar] }
        node_b = { words: %w[baz qux] }
        scorer = described_class.new(node_a, node_b, algorithm: algorithm)
        expect(scorer.score).to eq(0.0)
      end
    end
  end
end
