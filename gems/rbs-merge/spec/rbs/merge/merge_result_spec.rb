# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

# MergeResult specs - works with any RBS parser backend
# Tagged with :rbs_parsing since FileAnalysis supports both RBS gem and tree-sitter-rbs
RSpec.describe Rbs::Merge::MergeResult, :rbs_parsing do
  let(:template_source) do
    <<~RBS
      class Foo
        def bar: (String) -> Integer
      end

      type my_type = String
    RBS
  end

  let(:dest_source) do
    <<~RBS
      class Foo
        def bar: (Integer) -> String
      end

      type my_type = Integer
    RBS
  end

  let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
  let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }
  let(:result) { described_class.new(template_analysis, dest_analysis) }

  shared_examples 'extract_lines with leading comments' do
    let(:source_with_comments) do
      <<~RBS
        # This is a comment for the class
        class CommentedClass
          def bar: () -> void
        end
      RBS
    end
    let(:analysis_with_comments) { Rbs::Merge::FileAnalysis.new(source_with_comments) }
    let(:result_with_comments) { described_class.new(analysis_with_comments, analysis_with_comments) }

    it 'includes leading comments when extracting lines' do
      result_with_comments.add_from_template(0)
      output = result_with_comments.to_s
      expect(output).to include('# This is a comment for the class')
      expect(output).to include('class CommentedClass')
    end
  end

  shared_examples 'comment source fallback extraction' do
    let(:template_without_comments) do
      <<~RBS
        class CommentedClass
          def bar: () -> void
        end
      RBS
    end
    let(:destination_with_comments) do
      <<~RBS
        # Keep destination docs
        class CommentedClass
          def bar: () -> void
        end
      RBS
    end
    let(:template_without_comments_analysis) { Rbs::Merge::FileAnalysis.new(template_without_comments) }
    let(:destination_with_comments_analysis) { Rbs::Merge::FileAnalysis.new(destination_with_comments) }
    let(:result_with_comment_fallback) do
      described_class.new(template_without_comments_analysis, destination_with_comments_analysis)
    end

    it 'uses the comment source statement when the preferred statement lacks leading comments' do
      result_with_comment_fallback.add_from_template(
        0,
        comment_source_statement: destination_with_comments_analysis.statements.first,
        comment_source_analysis: destination_with_comments_analysis
      )

      expect(result_with_comment_fallback.to_s).to eq(<<~RBS)
        # Keep destination docs
        class CommentedClass
          def bar: () -> void
        end
      RBS
    end
  end

  shared_examples 'freeze block emission parity' do
    let(:dest_with_freeze) do
      <<~RBS
        # rbs-merge:freeze
        type frozen = String
        # rbs-merge:unfreeze
      RBS
    end
    let(:dest_analysis_frozen) { Rbs::Merge::FileAnalysis.new(dest_with_freeze) }
    let(:result_frozen) { described_class.new(template_analysis, dest_analysis_frozen) }

    it 'emits the exact freeze block lines and records a freeze decision' do
      freeze_node = dest_analysis_frozen.freeze_blocks.first

      result_frozen.add_freeze_block(freeze_node)

      expect(result_frozen.to_s).to eq(<<~RBS)
        # rbs-merge:freeze
        type frozen = String
        # rbs-merge:unfreeze
      RBS
      expect(result_frozen.decisions.first[:decision]).to eq(described_class::DECISION_FREEZE_BLOCK)
      expect(result_frozen.decisions.first[:source]).to eq(:destination)
    end
  end

  shared_examples 'custom freeze block emission parity' do
    let(:dest_with_custom_token_freeze) do
      <<~RBS
        # custom-token:freeze
        type frozen = String
        # custom-token:unfreeze
      RBS
    end
    let(:dest_analysis_custom_token_frozen) do
      Rbs::Merge::FileAnalysis.new(dest_with_custom_token_freeze, freeze_token: 'custom-token')
    end
    let(:result_custom_token_frozen) { described_class.new(template_analysis, dest_analysis_custom_token_frozen) }

    it 'emits the exact custom-token freeze block lines and records a freeze decision' do
      freeze_node = dest_analysis_custom_token_frozen.freeze_blocks.first

      result_custom_token_frozen.add_freeze_block(freeze_node)

      expect(result_custom_token_frozen.to_s).to eq(<<~RBS)
        # custom-token:freeze
        type frozen = String
        # custom-token:unfreeze
      RBS
      expect(result_custom_token_frozen.decisions.first[:decision]).to eq(described_class::DECISION_FREEZE_BLOCK)
      expect(result_custom_token_frozen.decisions.first[:source]).to eq(:destination)
    end
  end

  shared_examples 'freeze block leading docs emission parity' do
    let(:dest_with_documented_freeze) do
      <<~RBS
        # keep freeze docs
        # rbs-merge:freeze
        type frozen = String
        # rbs-merge:unfreeze
      RBS
    end
    let(:dest_analysis_documented_frozen) { Rbs::Merge::FileAnalysis.new(dest_with_documented_freeze) }
    let(:result_documented_frozen) { described_class.new(template_analysis, dest_analysis_documented_frozen) }

    it 'emits leading docs that belong to the freeze block' do
      freeze_node = dest_analysis_documented_frozen.freeze_blocks.first

      result_documented_frozen.add_freeze_block(freeze_node)

      expect(result_documented_frozen.to_s).to eq(<<~RBS)
        # keep freeze docs
        # rbs-merge:freeze
        type frozen = String
        # rbs-merge:unfreeze
      RBS
    end
  end

  shared_examples 'reason-bearing freeze block leading docs emission parity' do
    let(:dest_with_documented_reason_bearing_freeze) do
      <<~RBS
        # keep freeze docs
        # rbs-merge:freeze keep local customization
        type frozen = String
        # rbs-merge:unfreeze resume normal merge
      RBS
    end
    let(:dest_analysis_documented_reason_bearing_frozen) do
      Rbs::Merge::FileAnalysis.new(dest_with_documented_reason_bearing_freeze)
    end
    let(:result_documented_reason_bearing_frozen) do
      described_class.new(template_analysis, dest_analysis_documented_reason_bearing_frozen)
    end

    it 'emits leading docs that belong to the reason-bearing freeze block' do
      freeze_node = dest_analysis_documented_reason_bearing_frozen.freeze_blocks.first

      result_documented_reason_bearing_frozen.add_freeze_block(freeze_node)

      expect(result_documented_reason_bearing_frozen.to_s).to eq(<<~RBS)
        # keep freeze docs
        # rbs-merge:freeze keep local customization
        type frozen = String
        # rbs-merge:unfreeze resume normal merge
      RBS
    end
  end

  shared_examples 'custom freeze block leading docs emission parity' do
    let(:dest_with_documented_custom_token_freeze) do
      <<~RBS
        # keep custom freeze docs
        # custom-token:freeze
        type frozen = String
        # custom-token:unfreeze
      RBS
    end
    let(:dest_analysis_documented_custom_token_frozen) do
      Rbs::Merge::FileAnalysis.new(dest_with_documented_custom_token_freeze, freeze_token: 'custom-token')
    end
    let(:result_documented_custom_token_frozen) do
      described_class.new(template_analysis, dest_analysis_documented_custom_token_frozen)
    end

    it 'emits leading docs that belong to the custom-token freeze block' do
      freeze_node = dest_analysis_documented_custom_token_frozen.freeze_blocks.first

      result_documented_custom_token_frozen.add_freeze_block(freeze_node)

      expect(result_documented_custom_token_frozen.to_s).to eq(<<~RBS)
        # keep custom freeze docs
        # custom-token:freeze
        type frozen = String
        # custom-token:unfreeze
      RBS
    end
  end

  shared_examples 'reason-bearing custom freeze block leading docs emission parity' do
    let(:dest_with_documented_reason_bearing_custom_token_freeze) do
      <<~RBS
        # keep custom freeze docs
        # custom-token:freeze keep local customization
        type frozen = String
        # custom-token:unfreeze resume normal merge
      RBS
    end
    let(:dest_analysis_documented_reason_bearing_custom_token_frozen) do
      Rbs::Merge::FileAnalysis.new(dest_with_documented_reason_bearing_custom_token_freeze,
                                   freeze_token: 'custom-token')
    end
    let(:result_documented_reason_bearing_custom_token_frozen) do
      described_class.new(template_analysis, dest_analysis_documented_reason_bearing_custom_token_frozen)
    end

    it 'emits leading docs that belong to the reason-bearing custom-token freeze block' do
      freeze_node = dest_analysis_documented_reason_bearing_custom_token_frozen.freeze_blocks.first

      result_documented_reason_bearing_custom_token_frozen.add_freeze_block(freeze_node)

      expect(result_documented_reason_bearing_custom_token_frozen.to_s).to eq(<<~RBS)
        # keep custom freeze docs
        # custom-token:freeze keep local customization
        type frozen = String
        # custom-token:unfreeze resume normal merge
      RBS
    end
  end

  # Use shared examples - rbs-merge's MergeResult requires analysis args
  it_behaves_like 'Ast::Merge::MergeResultBase' do
    let(:merge_result_class) { described_class }
    let(:build_merge_result) { -> { described_class.new(template_analysis, dest_analysis) } }
  end

  describe '#initialize' do
    it 'initializes with empty content and decisions' do
      expect(result.content).to be_empty
      expect(result.decisions).to be_empty
    end

    it 'stores template and dest analysis' do
      expect(result.template_analysis).to eq(template_analysis)
      expect(result.dest_analysis).to eq(dest_analysis)
    end
  end

  describe '#add_from_template' do
    it 'adds content from template' do
      result.add_from_template(0)
      expect(result.to_s).to include('class Foo')
      expect(result.to_s).to include('(String) -> Integer')
    end

    it 'records decision' do
      result.add_from_template(0, decision: described_class::DECISION_ADDED)
      expect(result.decisions.first[:decision]).to eq(described_class::DECISION_ADDED)
      expect(result.decisions.first[:source]).to eq(:template)
    end

    it 'handles nil statement gracefully' do
      result.add_from_template(999)
      expect(result.content).to be_empty
    end
  end

  describe '#add_from_destination' do
    it 'adds content from destination' do
      result.add_from_destination(0)
      expect(result.to_s).to include('class Foo')
      expect(result.to_s).to include('(Integer) -> String')
    end

    it 'records decision' do
      result.add_from_destination(0)
      expect(result.decisions.first[:decision]).to eq(described_class::DECISION_DESTINATION)
      expect(result.decisions.first[:source]).to eq(:destination)
    end

    it 'handles nil statement gracefully' do
      result.add_from_destination(999)
      expect(result.content).to be_empty
    end
  end

  describe '#add_freeze_block' do
    let(:dest_with_freeze) do
      <<~RBS
        # rbs-merge:freeze
        type frozen = String
        # rbs-merge:unfreeze
      RBS
    end
    let(:dest_analysis_frozen) { Rbs::Merge::FileAnalysis.new(dest_with_freeze) }
    let(:result_frozen) { described_class.new(template_analysis, dest_analysis_frozen) }

    it 'adds freeze block content' do
      freeze_node = dest_analysis_frozen.freeze_blocks.first
      result_frozen.add_freeze_block(freeze_node)
      expect(result_frozen.to_s).to include('rbs-merge:freeze')
      expect(result_frozen.to_s).to include('type frozen')
      expect(result_frozen.to_s).to include('rbs-merge:unfreeze')
    end

    it 'records freeze block decision' do
      freeze_node = dest_analysis_frozen.freeze_blocks.first
      result_frozen.add_freeze_block(freeze_node)
      expect(result_frozen.decisions.first[:decision]).to eq(described_class::DECISION_FREEZE_BLOCK)
    end
  end

  describe '#add_recursive_merge' do
    it 'adds merged content' do
      merged = "class Merged\n  def foo: () -> void\nend\n"
      result.add_recursive_merge(merged, template_index: 0, dest_index: 0)
      expect(result.to_s).to include('class Merged')
      expect(result.to_s).to include('def foo')
    end

    it 'records recursive decision' do
      merged = "class Merged\nend\n"
      result.add_recursive_merge(merged, template_index: 0, dest_index: 0)
      expect(result.decisions.first[:decision]).to eq(described_class::DECISION_RECURSIVE)
      expect(result.decisions.first[:source]).to eq(:merged)
    end
  end

  describe '#add_raw' do
    it 'adds raw lines' do
      result.add_raw(['# Custom content', 'type raw = String'], decision: :custom)
      expect(result.to_s).to include('# Custom content')
      expect(result.to_s).to include('type raw = String')
    end

    it 'records raw decision' do
      result.add_raw(['# line'], decision: :custom)
      expect(result.decisions.first[:decision]).to eq(:custom)
      expect(result.decisions.first[:source]).to eq(:raw)
    end
  end

  describe '#to_s' do
    it 'returns empty string for empty result' do
      expect(result.to_s).to eq('')
    end

    it 'joins content with newlines' do
      result.add_from_template(1) # type my_type = String
      output = result.to_s
      expect(output).to end_with("\n")
    end
  end

  describe '#empty?' do
    it 'returns true when no content' do
      expect(result.empty?).to be true
    end

    it 'returns false when content exists' do
      result.add_from_template(0)
      expect(result.empty?).to be false
    end
  end

  describe '#summary' do
    it 'returns summary hash' do
      result.add_from_template(0, decision: described_class::DECISION_TEMPLATE)
      result.add_from_destination(1, decision: described_class::DECISION_DESTINATION)

      summary = result.summary
      expect(summary[:total_decisions]).to eq(2)
      expect(summary[:by_decision]).to include(described_class::DECISION_TEMPLATE => 1)
      expect(summary[:by_decision]).to include(described_class::DECISION_DESTINATION => 1)
    end
  end

  describe 'decision constants' do
    it 'defines DECISION_FREEZE_BLOCK' do
      expect(described_class::DECISION_FREEZE_BLOCK).to eq(:freeze_block)
    end

    it 'defines DECISION_TEMPLATE' do
      expect(described_class::DECISION_TEMPLATE).to eq(:template)
    end

    it 'defines DECISION_DESTINATION' do
      expect(described_class::DECISION_DESTINATION).to eq(:destination)
    end

    it 'defines DECISION_ADDED' do
      expect(described_class::DECISION_ADDED).to eq(:added)
    end

    it 'defines DECISION_RECURSIVE' do
      expect(described_class::DECISION_RECURSIVE).to eq(:recursive)
    end
  end

  describe 'extract_lines with comments', :rbs_backend do
    around do |example|
      TreeHaver.with_backend(:rbs) do
        example.run
      end
    end

    it_behaves_like 'extract_lines with leading comments'
    it_behaves_like 'comment source fallback extraction'
    it_behaves_like 'freeze block emission parity'
    it_behaves_like 'freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing freeze block leading docs emission parity'
    it_behaves_like 'custom freeze block emission parity'
    it_behaves_like 'custom freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing custom freeze block leading docs emission parity'
  end

  describe 'extract_lines with comments', :mri_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    it_behaves_like 'extract_lines with leading comments'
    it_behaves_like 'comment source fallback extraction'
    it_behaves_like 'freeze block emission parity'
    it_behaves_like 'freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing freeze block leading docs emission parity'
    it_behaves_like 'custom freeze block emission parity'
    it_behaves_like 'custom freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing custom freeze block leading docs emission parity'
  end

  describe 'extract_lines with comments', :java_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    it_behaves_like 'extract_lines with leading comments'
    it_behaves_like 'comment source fallback extraction'
    it_behaves_like 'freeze block emission parity'
    it_behaves_like 'freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing freeze block leading docs emission parity'
    it_behaves_like 'custom freeze block emission parity'
    it_behaves_like 'custom freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing custom freeze block leading docs emission parity'
  end

  describe 'extract_lines with comments', :rbs_grammar, :rust_backend do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    it_behaves_like 'extract_lines with leading comments'
    it_behaves_like 'comment source fallback extraction'
    it_behaves_like 'freeze block emission parity'
    it_behaves_like 'freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing freeze block leading docs emission parity'
    it_behaves_like 'custom freeze block emission parity'
    it_behaves_like 'custom freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing custom freeze block leading docs emission parity'
  end

  describe 'extract_lines with comments', :ffi_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    it_behaves_like 'extract_lines with leading comments'
    it_behaves_like 'comment source fallback extraction'
    it_behaves_like 'freeze block emission parity'
    it_behaves_like 'freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing freeze block leading docs emission parity'
    it_behaves_like 'custom freeze block emission parity'
    it_behaves_like 'custom freeze block leading docs emission parity'
    it_behaves_like 'reason-bearing custom freeze block leading docs emission parity'
  end

  describe '#add_recursive_merge edge cases' do
    it 'removes trailing empty line when content ends with newline' do
      # Content ending with newline will have empty last element after split
      merged = "class Foo\nend\n"
      result.add_recursive_merge(merged, template_index: 0, dest_index: 0)
      # The trailing empty element should be removed
      expect(result.content.last).not_to eq('')
    end

    it 'handles content without trailing newline' do
      merged = "class Foo\nend"
      result.add_recursive_merge(merged, template_index: 0, dest_index: 0)
      expect(result.content).to eq(['class Foo', 'end'])
    end
  end

  describe '#to_s edge cases' do
    it "adds trailing newline if content doesn't end with one" do
      result.add_raw(['class Foo', 'end'], decision: :custom)
      output = result.to_s
      expect(output).to end_with("\n")
    end

    it "doesn't double newline if content already ends with newline" do
      # This is an edge case - normally lines don't include newlines
      # but testing the unless branch
      result.add_raw(['class Foo', 'end'], decision: :custom)
      output = result.to_s
      expect(output).not_to end_with("\n\n")
    end
  end

  describe 'extract_lines with FreezeNode' do
    let(:dest_with_freeze) do
      <<~RBS
        # rbs-merge:freeze
        type frozen = String
        # rbs-merge:unfreeze
      RBS
    end
    let(:dest_analysis_frozen) { Rbs::Merge::FileAnalysis.new(dest_with_freeze) }
    let(:result_frozen) { described_class.new(template_analysis, dest_analysis_frozen) }

    it 'extracts lines using start_line and end_line for FreezeNode' do
      freeze_node = dest_analysis_frozen.freeze_blocks.first
      result_frozen.add_freeze_block(freeze_node)
      output = result_frozen.to_s
      # 3 lines of content + trailing newline = 3 lines when split by newline
      expect(output.lines.count).to eq(3)
    end
  end

  describe 'extract_lines without comments' do
    let(:source_no_comments) do
      <<~RBS
        class NoComment
          def bar: () -> void
        end
      RBS
    end
    let(:analysis_no_comments) { Rbs::Merge::FileAnalysis.new(source_no_comments) }
    let(:result_no_comments) { described_class.new(analysis_no_comments, analysis_no_comments) }

    it 'extracts lines using declaration location when no comment' do
      result_no_comments.add_from_template(0)
      output = result_no_comments.to_s
      expect(output).to include('class NoComment')
      expect(output).not_to include('#')
    end
  end
end
