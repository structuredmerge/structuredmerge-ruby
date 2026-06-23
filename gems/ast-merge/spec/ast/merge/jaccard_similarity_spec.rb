# frozen_string_literal: true

RSpec.describe Ast::Merge::JaccardSimilarity do
  include described_class

  describe '.extract_tokens' do
    it 'extracts lowercase words of 3+ characters' do
      tokens = extract_tokens('Create a feature branch')
      expect(tokens).to include('create', 'feature', 'branch')
    end

    it 'excludes stopwords by default' do
      tokens = extract_tokens('Create a feature branch and push to the repo')
      expect(tokens).not_to include('and', 'the')
    end

    it 'returns a Set' do
      tokens = extract_tokens('hello world again hello')
      expect(tokens).to be_a(Set)
    end

    it 'deduplicates tokens' do
      tokens = extract_tokens('hello hello hello')
      expect(tokens.size).to eq(1)
    end

    it 'handles empty string' do
      tokens = extract_tokens('')
      expect(tokens).to be_empty
    end

    it 'handles nil input' do
      tokens = extract_tokens(nil)
      expect(tokens).to be_empty
    end

    it 'accepts custom stopwords' do
      custom = %w[create].to_set
      tokens = extract_tokens('Create a feature branch', stopwords: custom)
      expect(tokens).not_to include('create')
      expect(tokens).to include('feature', 'branch')
    end

    it 'accepts custom minimum token length' do
      tokens = extract_tokens('go to the big house', min_length: 2)
      expect(tokens).to include('go', 'big')
    end

    it 'handles multi-byte characters' do
      tokens = extract_tokens('🪙 Token::Resolver provides parsing')
      expect(tokens).to include('token', 'resolver', 'provides', 'parsing')
    end
  end

  describe '.jaccard' do
    it 'returns 1.0 for identical sets' do
      a = Set['alpha', 'beta']
      expect(jaccard(a, a)).to eq(1.0)
    end

    it 'returns 0.0 for disjoint sets' do
      a = Set['alpha', 'beta']
      b = Set['gamma', 'delta']
      expect(jaccard(a, b)).to eq(0.0)
    end

    it 'returns correct score for overlapping sets' do
      a = Set['commit', 'changes']
      b = Set['commit', 'your', 'changes']
      # intersection: {commit, changes} = 2
      # union: {commit, changes, your} = 3
      expect(jaccard(a, b)).to be_within(0.001).of(2.0 / 3)
    end

    it 'returns 0.0 when first set is empty' do
      expect(jaccard(Set.new, Set['alpha'])).to eq(0.0)
    end

    it 'returns 0.0 when second set is empty' do
      expect(jaccard(Set['alpha'], Set.new)).to eq(0.0)
    end

    it 'returns 0.0 when both sets are empty' do
      expect(jaccard(Set.new, Set.new)).to eq(0.0)
    end

    it 'is symmetric' do
      a = Set['alpha', 'beta', 'gamma']
      b = Set['beta', 'gamma', 'delta']
      expect(jaccard(a, b)).to eq(jaccard(b, a))
    end
  end
end
