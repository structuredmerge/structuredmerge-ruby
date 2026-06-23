# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

# FreezeNode specs - works with any RBS parser backend
# Tagged with :rbs_parsing since FileAnalysis supports both RBS gem and tree-sitter-rbs
RSpec.describe Rbs::Merge::FreezeNode, :rbs_parsing do
  shared_examples 'freeze block parity' do
    it 'detects a single freeze block with stable line bounds' do
      expect(analysis.freeze_blocks.size).to eq(1)

      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.start_line).to eq(4)
      expect(freeze_node.end_line).to eq(6)
    end

    it 'keeps contained declarations merge-addressable across backends' do
      freeze_node = analysis.freeze_blocks.first
      contained_node = freeze_node.nodes.first
      contained_start_line = if contained_node.respond_to?(:start_line)
                               contained_node.start_line
                             else
                               contained_node.location&.start_line
                             end
      contained_end_line = if contained_node.respond_to?(:end_line)
                             contained_node.end_line
                           else
                             contained_node.location&.end_line
                           end

      expect(freeze_node.nodes.size).to eq(1)
      expect(contained_start_line).to eq(5)
      expect(contained_end_line).to eq(5)
    end

    it 'preserves freeze block content, signature, location, and reason' do
      freeze_node = analysis.freeze_blocks.first
      location = freeze_node.location
      signature = freeze_node.signature

      expect(freeze_node.content).to include('rbs-merge:freeze')
      expect(freeze_node.content).to include('type custom')
      expect(freeze_node.content).to include('rbs-merge:unfreeze')

      expect(signature.first).to eq(:FreezeNode)
      expect(signature.last).to be_a(String)
      expect(signature.last).to include('type custom')

      expect(location).to be_a(described_class::Location)
      expect(location.start_line).to eq(4)
      expect(location.end_line).to eq(6)
      expect(location.cover?(4)).to be(true)
      expect(location.cover?(5)).to be(true)
      expect(location.cover?(6)).to be(true)
      expect(location.cover?(3)).to be(false)
      expect(location.cover?(7)).to be(false)

      expect(freeze_node.reason).to eq('Custom reason')
    end
  end

  shared_examples 'freeze block parity without reason' do
    let(:source) do
      <<~RBS
        # rbs-merge:freeze
        type custom = String
        # rbs-merge:unfreeze
      RBS
    end

    it 'returns nil when no reason is provided' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.reason).to be_nil
    end
  end

  shared_examples 'custom freeze token parity' do
    let(:source) do
      <<~RBS
        class Before
        end

        # custom-token:freeze Custom reason
        type custom = String
        # custom-token:unfreeze

        class After
        end
      RBS
    end

    let(:analysis) { Rbs::Merge::FileAnalysis.new(source, freeze_token: 'custom-token') }

    it 'preserves custom-token freeze block content, location, contained declaration lines, and reason' do
      freeze_node = analysis.freeze_blocks.first
      contained_node = freeze_node.nodes.first
      contained_start_line = contained_node.respond_to?(:start_line) ? contained_node.start_line : contained_node.location&.start_line
      contained_end_line = contained_node.respond_to?(:end_line) ? contained_node.end_line : contained_node.location&.end_line

      expect(freeze_node.content).to include('custom-token:freeze')
      expect(freeze_node.content).to include('type custom')
      expect(freeze_node.content).to include('custom-token:unfreeze')

      expect(freeze_node.location.start_line).to eq(4)
      expect(freeze_node.location.end_line).to eq(6)
      expect(contained_start_line).to eq(5)
      expect(contained_end_line).to eq(5)
      expect(freeze_node.reason).to eq('Custom reason')
    end
  end

  # Use shared examples to validate base FreezeNodeBase integration
  it_behaves_like 'Ast::Merge::FreezeNodeBase' do
    let(:freeze_node_class) { described_class }
    let(:default_pattern_type) { :hash_comment }
    let(:build_freeze_node) do
      # RBS FreezeNode requires an analysis object
      source = <<~RBS
        # rbs-merge:freeze
        type example = String
        # rbs-merge:unfreeze
      RBS
      analysis = Rbs::Merge::FileAnalysis.new(source)
      lambda { |start_line:, end_line:, **opts|
        # For the shared examples, we create a simple freeze node
        # using the analysis from the source above
        described_class.new(
          start_line: start_line,
          end_line: end_line,
          analysis: analysis,
          **opts
        )
      }
    end
  end

  # RBS-specific tests below
  let(:source) do
    <<~RBS
      class Before
      end

      # rbs-merge:freeze Custom reason
      type custom = String
      # rbs-merge:unfreeze

      class After
      end
    RBS
  end
  let(:analysis) { Rbs::Merge::FileAnalysis.new(source) }

  describe 'inheritance' do
    it 'inherits from Ast::Merge::FreezeNodeBase' do
      expect(described_class.superclass).to eq(Ast::Merge::FreezeNodeBase)
    end

    it 'has InvalidStructureError' do
      expect(described_class::InvalidStructureError).to eq(Ast::Merge::FreezeNodeBase::InvalidStructureError)
    end

    it 'has Location' do
      expect(described_class::Location).to eq(Ast::Merge::FreezeNodeBase::Location)
    end
  end

  describe 'freeze block detection' do
    it 'detects freeze blocks in analysis' do
      expect(analysis.freeze_blocks.size).to eq(1)
    end

    it 'has correct line numbers' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.start_line).to eq(4)
      expect(freeze_node.end_line).to eq(6)
    end
  end

  describe '#nodes' do
    it 'contains declarations within the freeze block' do
      freeze_node = analysis.freeze_blocks.first
      contained_node = freeze_node.nodes.first
      contained_start_line = if contained_node.respond_to?(:start_line)
                               contained_node.start_line
                             else
                               contained_node.location&.start_line
                             end
      contained_end_line = if contained_node.respond_to?(:end_line)
                             contained_node.end_line
                           else
                             contained_node.location&.end_line
                           end

      expect(freeze_node.nodes.size).to eq(1)
      expect(contained_start_line).to eq(5)
      expect(contained_end_line).to eq(5)
    end
  end

  describe '#content' do
    it 'returns the content of the freeze block' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.content).to include('rbs-merge:freeze')
      expect(freeze_node.content).to include('type custom')
      expect(freeze_node.content).to include('rbs-merge:unfreeze')
    end
  end

  describe '#signature' do
    it 'returns a FreezeNode signature with normalized content' do
      freeze_node = analysis.freeze_blocks.first
      sig = freeze_node.signature
      expect(sig.first).to eq(:FreezeNode)
      expect(sig.last).to be_a(String)
      expect(sig.last).to include('type custom')
    end
  end

  describe '#location' do
    it 'returns a Location struct' do
      freeze_node = analysis.freeze_blocks.first
      location = freeze_node.location
      expect(location).to be_a(described_class::Location)
      expect(location.start_line).to eq(4)
      expect(location.end_line).to eq(6)
    end

    it 'supports cover? method' do
      freeze_node = analysis.freeze_blocks.first
      location = freeze_node.location
      expect(location.cover?(4)).to be true
      expect(location.cover?(5)).to be true
      expect(location.cover?(6)).to be true
      expect(location.cover?(3)).to be false
      expect(location.cover?(7)).to be false
    end
  end

  describe '#reason' do
    it 'extracts reason from freeze marker' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.reason).to eq('Custom reason')
    end

    context 'without reason' do
      let(:source) do
        <<~RBS
          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze
        RBS
      end

      it 'returns nil when no reason provided' do
        freeze_node = analysis.freeze_blocks.first
        expect(freeze_node.reason).to be_nil
      end
    end
  end

  describe 'explicit backend freeze parity', :rbs_backend do
    around do |example|
      TreeHaver.with_backend(:rbs) do
        example.run
      end
    end

    it_behaves_like 'freeze block parity'
    it_behaves_like 'freeze block parity without reason'
    it_behaves_like 'custom freeze token parity'
  end

  describe 'explicit backend freeze parity', :mri_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    it_behaves_like 'freeze block parity'
    it_behaves_like 'freeze block parity without reason'
    it_behaves_like 'custom freeze token parity'
  end

  describe 'explicit backend freeze parity', :java_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    it_behaves_like 'freeze block parity'
    it_behaves_like 'freeze block parity without reason'
    it_behaves_like 'custom freeze token parity'
  end

  describe 'explicit backend freeze parity', :rbs_grammar, :rust_backend do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    it_behaves_like 'freeze block parity'
    it_behaves_like 'freeze block parity without reason'
    it_behaves_like 'custom freeze token parity'
  end

  describe 'explicit backend freeze parity', :ffi_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    it_behaves_like 'freeze block parity'
    it_behaves_like 'freeze block parity without reason'
    it_behaves_like 'custom freeze token parity'
  end

  describe '#inspect' do
    it 'returns a descriptive string' do
      freeze_node = analysis.freeze_blocks.first
      expect(freeze_node.inspect).to match(/Rbs::Merge::FreezeNode/)
      expect(freeze_node.inspect).to match(/lines=4\.\.6/)
      expect(freeze_node.inspect).to match(/nodes=1/)
    end
  end

  describe 'validation' do
    context 'with partial overlap' do
      let(:invalid_source) do
        <<~RBS
          # rbs-merge:freeze
          class Foo
            def bar: () -> void
          # rbs-merge:unfreeze
          end
        RBS
      end

      it 'raises InvalidStructureError' do
        expect { Rbs::Merge::FileAnalysis.new(invalid_source) }
          .to raise_error(described_class::InvalidStructureError)
      end

      it 'includes node names in error message' do
        expect { Rbs::Merge::FileAnalysis.new(invalid_source) }
          .to raise_error(described_class::InvalidStructureError, /Foo.*lines/)
      end
    end

    context 'with partial overlap and node without name method' do
      # Test the else branch in validate_structure! (line 103)
      # where node.respond_to?(:name) is false
      it "uses class name when node doesn't respond to :name" do
        # Create a freeze node with a mock node that doesn't have :name
        source = <<~RBS
          class Foo
          end
        RBS
        analysis = Rbs::Merge::FileAnalysis.new(source)

        # Create a testable node without :name that partially overlaps
        # Freeze block: lines 2-4, Node: lines 1-3 (partial overlap)
        nameless_node = TestableNode.create(
          type: :class_decl,
          text: "class Foo\nend\n",
          start_line: 1,
          end_line: 3
        )

        # Validation happens during initialize, so the error is raised there
        # Freeze block lines 2-4, node lines 1-3 creates partial overlap:
        # - NOT fully_contained (node starts before freeze block)
        # - NOT encompasses (node doesn't end after freeze block)
        # - NOT fully_outside (overlaps at lines 2-3)
        expect do
          described_class.new(
            start_line: 2,
            end_line: 4,
            analysis: analysis,
            nodes: [],
            overlapping_nodes: [nameless_node]
          )
        end.to raise_error(described_class::InvalidStructureError, /TestableNode/)
      end
    end

    context 'with fully contained declaration' do
      let(:valid_source) do
        <<~RBS
          # rbs-merge:freeze
          class Foo
            def bar: () -> void
          end
          # rbs-merge:unfreeze
        RBS
      end

      it 'does not raise' do
        expect { Rbs::Merge::FileAnalysis.new(valid_source) }.not_to raise_error
      end
    end

    context 'with freeze block inside class' do
      let(:nested_source) do
        <<~RBS
          class Foo
            # rbs-merge:freeze
            def custom: () -> void
            # rbs-merge:unfreeze
          end
        RBS
      end

      # This is actually valid - the class encompasses the freeze block
      it 'allows freeze blocks inside container declarations' do
        expect { Rbs::Merge::FileAnalysis.new(nested_source) }.not_to raise_error
      end
    end
  end
end
