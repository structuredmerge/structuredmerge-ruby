# frozen_string_literal: true

require 'support/fictive_language_harness'
require 'ast/merge/rspec/shared_examples/comment_behavior_matrix'

RSpec.describe 'fictive language harness' do
  describe SpecSupport::FictiveLanguageHarness::FlatAnalysis do
    subject(:analysis) { described_class.new(source) }

    let(:source) do
      <<~SRC
        # Document header

        # Alpha docs

        alpha = 1
        beta = "two # literal" # beta docs
      SRC
    end

    it 'models a flat source-augmented portable-write analysis through shared hooks' do
      first_owner, second_owner = analysis.statements
      augmenter = analysis.comment_augmenter
      first_attachment = analysis.comment_attachment_for(first_owner)
      second_attachment = analysis.comment_attachment_for(second_owner)

      expect(analysis.comment_capability).to be_source_augmented
      expect(analysis.comment_support_style).to be_source_augmented_portable_write

      expect(first_owner.name).to eq('alpha')
      expect(second_owner.name).to eq('beta')

      expect(augmenter.preamble_region&.normalized_content).to eq('Document header')

      expect(first_attachment.leading_region).to be_floating
      expect(first_attachment.leading_region&.normalized_content).to eq('Alpha docs')
      expect(first_attachment.leading_region_layout_owned?).to be(true)
      expect(first_attachment.leading_gap).not_to be_nil

      expect(second_attachment.inline_region&.normalized_content).to eq('beta docs')
    end

    it_behaves_like 'Ast::Merge::CommentBehaviorMatrix' do
      let(:comment_matrix_analysis_class) { described_class }
      let(:comment_matrix_merger_class) { SpecSupport::FictiveLanguageHarness::FlatSmartMerger }
      let(:comment_matrix_source_builder) { ->(*lines) { "#{lines.join("\n")}\n" } }
      let(:comment_matrix_comment_line_builder) { ->(text, indent: '') { "#{indent}# #{text}" } }
      let(:comment_matrix_default_indent) { '' }
      let(:comment_matrix_line_builder) do
        lambda do |name, value, inline: nil|
          line = "#{name} = #{value}"
          inline ? "#{line} # #{inline}" : line
        end
      end
    end
  end

  describe SpecSupport::FictiveLanguageHarness::FlatSmartMerger do
    let(:line_builder) do
      lambda do |name, value, inline: nil|
        line = "#{name} = #{value}"
        inline ? "#{line} # #{inline}" : line
      end
    end

    it_behaves_like 'Ast::Merge::CommentBehaviorMatrix' do
      let(:comment_matrix_analysis_class) { SpecSupport::FictiveLanguageHarness::FlatAnalysis }
      let(:comment_matrix_merger_class) { described_class }
      let(:comment_matrix_source_builder) { ->(*lines) { "#{lines.join("\n")}\n" } }
      let(:comment_matrix_comment_line_builder) { ->(text, indent: '') { "#{indent}# #{text}" } }
      let(:comment_matrix_default_indent) { '' }
      let(:comment_matrix_line_builder) { line_builder }
    end

    it 'does not leave duplicate interstitial blank gaps when removing an owner' do
      template = <<~SRC
        alpha = 1

        beta = 2
      SRC
      destination = <<~SRC
        alpha = 1

        removed = 0

        beta = 2
      SRC

      result = described_class.new(
        template,
        destination,
        remove_template_missing_nodes: true
      ).merge

      expect(result.to_s).to eq(<<~SRC)
        alpha = 1

        beta = 2
      SRC
    end
  end

  describe SpecSupport::FictiveLanguageHarness::IndentedAnalysis do
    subject(:analysis) { described_class.new(source) }

    let(:source) do
      <<~SRC
        root = top
          # Child docs

          child = "value # literal" # child inline docs
      SRC
    end

    it 'preserves indentation-sensitive ownership while still using the shared comment stack' do
      root_owner, child_owner = analysis.statements
      child_attachment = analysis.comment_attachment_for(child_owner)

      expect(root_owner.indent).to eq(0)
      expect(child_owner.indent).to eq(2)

      expect(child_attachment.leading_region).to be_floating
      expect(child_attachment.leading_region&.text).to eq('  # Child docs')
      expect(child_attachment.leading_region_layout_owned?).to be(true)
      expect(child_attachment.inline_region&.normalized_content).to eq('child inline docs')
    end

    it_behaves_like 'Ast::Merge::CommentBehaviorMatrix' do
      let(:comment_matrix_analysis_class) { described_class }
      let(:comment_matrix_merger_class) { SpecSupport::FictiveLanguageHarness::IndentedSmartMerger }
      let(:comment_matrix_source_builder) { ->(*lines) { "#{lines.join("\n")}\n" } }
      let(:comment_matrix_comment_line_builder) { ->(text, indent: '') { "#{indent}# #{text}" } }
      let(:comment_matrix_default_indent) { '  ' }
      let(:comment_matrix_line_builder) do
        lambda do |name, value, inline: nil|
          line = "  #{name} = #{value}"
          inline ? "#{line} # #{inline}" : line
        end
      end
    end

    context 'with indentation-sensitive attached and floating neighbors' do
      let(:source) do
        <<~SRC
          parent = top
            # Attached child docs
            child = one

            # Floating sibling docs

            sibling = two # sibling inline docs
        SRC
      end

      it 'keeps indentation orthogonal to attached vs floating ownership' do
        _parent, child_owner, sibling_owner = analysis.statements
        child_attachment = analysis.comment_attachment_for(child_owner)
        sibling_attachment = analysis.comment_attachment_for(sibling_owner)

        expect(child_owner.indent).to eq(2)
        expect(sibling_owner.indent).to eq(2)

        expect(child_attachment.leading_region).not_to be_floating
        expect(child_attachment.leading_region&.text).to eq('  # Attached child docs')

        expect(sibling_attachment.leading_region).to be_floating
        expect(sibling_attachment.leading_region&.text).to eq('  # Floating sibling docs')
        expect(sibling_attachment.inline_region&.normalized_content).to eq('sibling inline docs')
      end
    end
  end

  describe SpecSupport::FictiveLanguageHarness::IndentedSmartMerger do
    let(:line_builder) do
      lambda do |name, value, inline: nil|
        line = "  #{name} = #{value}"
        inline ? "#{line} # #{inline}" : line
      end
    end

    it_behaves_like 'Ast::Merge::CommentBehaviorMatrix' do
      let(:comment_matrix_analysis_class) { SpecSupport::FictiveLanguageHarness::IndentedAnalysis }
      let(:comment_matrix_merger_class) { described_class }
      let(:comment_matrix_source_builder) { ->(*lines) { "#{lines.join("\n")}\n" } }
      let(:comment_matrix_comment_line_builder) { ->(text, indent: '') { "#{indent}# #{text}" } }
      let(:comment_matrix_default_indent) { '  ' }
      let(:comment_matrix_line_builder) { line_builder }
    end
  end
end
