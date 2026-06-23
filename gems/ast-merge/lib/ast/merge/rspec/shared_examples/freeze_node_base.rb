# frozen_string_literal: true

# Shared examples for validating FreezeNodeBase integration
#
# Usage in your spec:
#   require "ast/merge/rspec/shared_examples/freeze_node_base"
#
#   RSpec.describe MyMerge::FreezeNode do
#     it_behaves_like "Ast::Merge::FreezeNodeBase" do
#       let(:freeze_node_class) { MyMerge::FreezeNode }
#       let(:default_pattern_type) { :hash_comment }
#       # Factory to create a freeze node instance
#       let(:build_freeze_node) do
#         ->(start_line:, end_line:, **opts) {
#           freeze_node_class.new(start_line: start_line, end_line: end_line, **opts)
#         }
#       end
#     end
#   end
#
# @note The extending class should inherit from or behave like Ast::Merge::FreezeNodeBase

RSpec.shared_examples('Ast::Merge::FreezeNodeBase') do
  # Required let blocks:
  # - freeze_node_class: The class under test (e.g., MyMerge::FreezeNode)
  # - default_pattern_type: The default pattern type (:hash_comment, etc.)
  # - build_freeze_node: Lambda that creates a freeze node instance

  describe 'class methods' do
    describe '.pattern_for' do
      it 'returns a hash with :start and :end keys' do
        pattern = freeze_node_class.pattern_for(:hash_comment)
        expect(pattern).to(be_a(Hash))
        expect(pattern).to(have_key(:start))
        expect(pattern).to(have_key(:end))
      end

      it 'returns Regexp patterns' do
        pattern = freeze_node_class.pattern_for(:hash_comment)
        expect(pattern[:start]).to(be_a(Regexp))
        expect(pattern[:end]).to(be_a(Regexp))
      end

      it 'raises ArgumentError for unknown pattern type' do
        expect { freeze_node_class.pattern_for(:unknown_pattern) }
          .to(raise_error(ArgumentError, /unknown pattern type/i))
      end
    end

    describe '.start_pattern' do
      it 'returns a Regexp' do
        expect(freeze_node_class.start_pattern).to(be_a(Regexp))
      end

      it 'accepts pattern_type argument' do
        expect(freeze_node_class.start_pattern(:hash_comment)).to(be_a(Regexp))
      end
    end

    describe '.end_pattern' do
      it 'returns a Regexp' do
        expect(freeze_node_class.end_pattern).to(be_a(Regexp))
      end

      it 'accepts pattern_type argument' do
        expect(freeze_node_class.end_pattern(:hash_comment)).to(be_a(Regexp))
      end
    end

    describe '.freeze_start?' do
      it 'returns true for valid freeze start markers' do
        expect(freeze_node_class.freeze_start?('# token:freeze')).to(be(true))
        expect(freeze_node_class.freeze_start?('  # my-merge:freeze')).to(be(true))
      end

      it 'returns false for invalid markers' do
        expect(freeze_node_class.freeze_start?('not a marker')).to(be(false))
        expect(freeze_node_class.freeze_start?('# unfreeze')).to(be(false))
      end

      it 'returns false for nil' do
        expect(freeze_node_class.freeze_start?(nil)).to(be(false))
      end
    end

    describe '.freeze_end?' do
      it 'returns true for valid freeze end markers' do
        expect(freeze_node_class.freeze_end?('# token:unfreeze')).to(be(true))
        expect(freeze_node_class.freeze_end?('  # my-merge:unfreeze')).to(be(true))
      end

      it 'returns false for invalid markers' do
        expect(freeze_node_class.freeze_end?('not a marker')).to(be(false))
        expect(freeze_node_class.freeze_end?('# freeze')).to(be(false))
      end

      it 'returns false for nil' do
        expect(freeze_node_class.freeze_end?(nil)).to(be(false))
      end
    end

    describe '.pattern_types' do
      it 'returns an array of symbols' do
        types = freeze_node_class.pattern_types
        expect(types).to(be_an(Array))
        expect(types).to(all(be_a(Symbol)))
      end

      it 'includes :hash_comment' do
        expect(freeze_node_class.pattern_types).to(include(:hash_comment))
      end
    end
  end

  describe 'instance methods' do
    let(:freeze_node) { build_freeze_node.call(start_line: 5, end_line: 10) }

    describe '#start_line' do
      it 'returns the start line number' do
        expect(freeze_node.start_line).to(eq(5))
      end
    end

    describe '#end_line' do
      it 'returns the end line number' do
        expect(freeze_node.end_line).to(eq(10))
      end
    end

    describe '#location' do
      it 'returns a location object' do
        expect(freeze_node.location).to(respond_to(:start_line))
        expect(freeze_node.location).to(respond_to(:end_line))
      end

      it 'has correct line numbers' do
        expect(freeze_node.location.start_line).to(eq(5))
        expect(freeze_node.location.end_line).to(eq(10))
      end
    end

    describe '#freeze_node?' do
      it 'returns true' do
        expect(freeze_node.freeze_node?).to(be(true))
      end
    end

    describe '#signature' do
      it 'returns an Array' do
        expect(freeze_node.signature).to(be_an(Array))
      end

      it 'starts with :FreezeNode' do
        expect(freeze_node.signature.first).to(eq(:FreezeNode))
      end
    end

    describe '#inspect' do
      it 'returns a string representation' do
        expect(freeze_node.inspect).to(be_a(String))
        expect(freeze_node.inspect).to(include('5'))
        expect(freeze_node.inspect).to(include('10'))
      end
    end

    describe '#pattern_type' do
      it 'returns the pattern type' do
        expect(freeze_node.pattern_type).to(be_a(Symbol))
      end
    end
  end

  describe 'InvalidStructureError' do
    it 'is defined' do
      expect(freeze_node_class::InvalidStructureError).to(be_a(Class))
    end

    it 'is a StandardError' do
      expect(freeze_node_class::InvalidStructureError.ancestors).to(include(StandardError))
    end

    it 'accepts start_line, end_line, and unclosed_nodes' do
      error = freeze_node_class::InvalidStructureError.new(
        'test error',
        start_line: 1,
        end_line: 10,
        unclosed_nodes: []
      )
      expect(error.start_line).to(eq(1))
      expect(error.end_line).to(eq(10))
      expect(error.unclosed_nodes).to(eq([]))
    end
  end

  describe 'Location struct' do
    let(:location) { freeze_node_class::Location.new(5, 10) }

    it 'has start_line' do
      expect(location.start_line).to(eq(5))
    end

    it 'has end_line' do
      expect(location.end_line).to(eq(10))
    end

    it 'responds to cover?' do
      expect(location).to(respond_to(:cover?))
    end

    it '#cover? returns true for lines within range' do
      expect(location.cover?(7)).to(be(true))
    end

    it '#cover? returns false for lines outside range' do
      expect(location.cover?(3)).to(be(false))
      expect(location.cover?(15)).to(be(false))
    end
  end
end
