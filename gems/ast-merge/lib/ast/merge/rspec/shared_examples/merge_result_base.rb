# frozen_string_literal: true

# Shared examples for validating MergeResultBase integration
#
# Usage in your spec:
#   require "ast/merge/rspec/shared_examples/merge_result_base"
#
#   RSpec.describe MyMerge::MergeResult do
#     it_behaves_like "Ast::Merge::MergeResultBase" do
#       let(:merge_result_class) { MyMerge::MergeResult }
#       # Factory to create a merge result instance
#       let(:build_merge_result) { -> { merge_result_class.new } }
#     end
#   end
#
# @note The extending class should inherit from or behave like Ast::Merge::MergeResultBase

RSpec.shared_examples('Ast::Merge::MergeResultBase') do
  # Required let blocks:
  # - merge_result_class: The class under test
  # - build_merge_result: Lambda that creates a merge result instance

  describe 'decision constants' do
    it 'has DECISION_KEPT_TEMPLATE' do
      expect(merge_result_class::DECISION_KEPT_TEMPLATE).to(eq(:kept_template))
    end

    it 'has DECISION_KEPT_DEST' do
      expect(merge_result_class::DECISION_KEPT_DEST).to(eq(:kept_destination))
    end

    it 'has DECISION_MERGED' do
      expect(merge_result_class::DECISION_MERGED).to(eq(:merged))
    end

    it 'has DECISION_ADDED' do
      expect(merge_result_class::DECISION_ADDED).to(eq(:added))
    end

    it 'has DECISION_FREEZE_BLOCK' do
      expect(merge_result_class::DECISION_FREEZE_BLOCK).to(eq(:freeze_block))
    end

    it 'has DECISION_REPLACED' do
      expect(merge_result_class::DECISION_REPLACED).to(eq(:replaced))
    end

    it 'has DECISION_APPENDED' do
      expect(merge_result_class::DECISION_APPENDED).to(eq(:appended))
    end
  end

  describe 'instance methods' do
    let(:result) { build_merge_result.call }

    describe '#lines' do
      it 'returns an Array' do
        expect(result.lines).to(be_an(Array))
      end

      it 'is initially empty' do
        expect(result.lines).to(be_empty)
      end
    end

    describe '#decisions' do
      it 'returns an Array' do
        expect(result.decisions).to(be_an(Array))
      end

      it 'is initially empty' do
        expect(result.decisions).to(be_empty)
      end
    end

    describe '#empty?' do
      it 'returns true when no lines' do
        expect(result.empty?).to(be(true))
      end
    end

    describe '#line_count' do
      it 'returns 0 for empty result' do
        expect(result.line_count).to(eq(0))
      end
    end

    describe '#decision_summary' do
      it 'returns a Hash' do
        expect(result.decision_summary).to(be_a(Hash))
      end

      it 'returns empty hash for empty result' do
        expect(result.decision_summary).to(eq({}))
      end
    end

    describe '#inspect' do
      it 'returns a string representation' do
        expect(result.inspect).to(be_a(String))
        expect(result.inspect).to(include('lines='))
        expect(result.inspect).to(include('decisions='))
      end
    end
  end
end
