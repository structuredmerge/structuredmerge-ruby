# frozen_string_literal: true

require 'spec_helper'

# SmartMerger specs with explicit backend testing
#
# This spec file tests SmartMerger behavior across all available tree-sitter backends:
# - :mri (via ruby_tree_sitter gem, tagged :mri_backend)
# - :ffi (via FFI bindings, tagged :ffi_backend)
# - :rust (via tree_stump gem, tagged :rust_backend)
# - :java (via jtreesitter, tagged :java_backend)

RSpec.describe Bash::Merge::SmartMerger do
  # ============================================================
  # :auto backend tests (uses whatever is available)
  # ============================================================

  context 'with :auto backend', :bash_grammar do
    it_behaves_like 'basic initialization'
    it_behaves_like 'configuration options'
    it_behaves_like 'instance methods'
    it_behaves_like 'accessors'
    it_behaves_like 'basic merge operation'
    it_behaves_like 'template preference'
    it_behaves_like 'merge_with_debug'
    it_behaves_like 'validation'
    it_behaves_like 'add template-only nodes'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'function merging'
    it_behaves_like 'duplicate command signatures'
    it_behaves_like 'complex scripts'
    it_behaves_like 'document boundary comments'
    it_behaves_like 'matched leading comments'
    it_behaves_like 'removed node leading comments'
    it_behaves_like 'conservative inline comments'
    it_behaves_like 'removed node inline comments'
    it_behaves_like 'multi-byte character (emoji) handling'
    it_behaves_like 'floating comment gap transitions'
  end

  describe 'duplicate template preamble healing', :bash_grammar, :mri_backend do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    let(:template_content) do
      <<~BASH
        # Shared header

        alpha=1
      BASH
    end

    let(:destination_content) do
      <<~BASH
        # Shared header
        # Shared header
        # Destination header
        alpha=9
      BASH
    end

    it 'collapses the duplicated template prefix in heal mode' do
      merged = described_class.new(
        template_content,
        destination_content,
        add_template_only_nodes: true
      ).merge

      expect(merged.lines.grep("# Shared header\n").size).to eq(0)
      expect(merged.lines.grep("# Destination header\n").size).to eq(1)
      expect(merged).to include('alpha=9')
    end

    it 'preserves the duplicated prefix in skip mode' do
      merged = described_class.new(
        template_content,
        destination_content,
        add_template_only_nodes: true,
        corruption_handling: :skip
      ).merge

      expect(merged.lines.grep("# Shared header\n").size).to eq(2)
      expect(merged.lines.grep("# Destination header\n").size).to eq(1)
    end

    it 'warns and preserves the duplicated prefix in warn mode' do
      allow(Bash::Merge::DebugLogger).to receive(:debug_warning)

      merged = described_class.new(
        template_content,
        destination_content,
        add_template_only_nodes: true,
        corruption_handling: :warn
      ).merge

      expect(Bash::Merge::DebugLogger).to have_received(:debug_warning).with(
        /Suspected corruption \(duplicate_template_preamble_prefix\)/,
        hash_including(template_comment_lines: 2, merged_comment_lines: 3, destination_specific_comment_lines: 1)
      )
      expect(merged.lines.grep("# Shared header\n").size).to eq(2)
    end

    it 'raises in error mode' do
      expect do
        described_class.new(
          template_content,
          destination_content,
          add_template_only_nodes: true,
          corruption_handling: :error
        ).merge
      end.to raise_error(Bash::Merge::CorruptionDetectedError, /duplicate_template_preamble_prefix/)
    end

    it 'keeps destination-owned first-owner docs singular when template models them as a preamble' do
      template = <<~BASH
        # Template header

        alpha=1
      BASH
      destination = <<~BASH
        # Destination header
        alpha=9
      BASH

      merged = described_class.new(
        template,
        destination,
        add_template_only_nodes: true
      ).merge

      expect(merged.lines.grep("# Template header\n").size).to eq(0)
      expect(merged.lines.grep("# Destination header\n").size).to eq(1)
      expect(merged).to include('alpha=9')
    end

    it 'deduplicates equivalent preamble docs when only blank-line ownership differs' do
      template = <<~BASH
        # Shared header

        alpha=1
      BASH
      destination = <<~BASH
        # Shared header
        alpha=9
      BASH

      merged = described_class.new(
        template,
        destination,
        preference: :template,
        add_template_only_nodes: true
      ).merge

      expect(merged.lines.grep("# Shared header\n").size).to eq(1)
      expect(merged).to include('alpha=1')
      expect(merged).not_to include('alpha=9')
    end
  end

  # ============================================================
  # Backend-aware tests - MRI/ruby_tree_sitter
  # ============================================================

  context 'with MRI backend', :bash_grammar, :mri_backend do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    it_behaves_like 'basic initialization'
    it_behaves_like 'configuration options'
    it_behaves_like 'instance methods'
    it_behaves_like 'accessors'
    it_behaves_like 'basic merge operation'
    it_behaves_like 'template preference'
    it_behaves_like 'merge_with_debug'
    it_behaves_like 'validation'
    it_behaves_like 'add template-only nodes'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'function merging'
    it_behaves_like 'duplicate command signatures'
    it_behaves_like 'complex scripts'
    it_behaves_like 'document boundary comments'
    it_behaves_like 'matched leading comments'
    it_behaves_like 'removed node leading comments'
    it_behaves_like 'conservative inline comments'
    it_behaves_like 'removed node inline comments'
    it_behaves_like 'multi-byte character (emoji) handling'
    it_behaves_like 'floating comment gap transitions'
  end

  # ============================================================
  # Backend-aware tests - FFI
  # ============================================================

  context 'with FFI backend', :bash_grammar, :ffi_backend do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    it_behaves_like 'basic initialization'
    it_behaves_like 'configuration options'
    it_behaves_like 'instance methods'
    it_behaves_like 'accessors'
    it_behaves_like 'basic merge operation'
    it_behaves_like 'template preference'
    it_behaves_like 'merge_with_debug'
    it_behaves_like 'validation'
    it_behaves_like 'add template-only nodes'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'function merging'
    it_behaves_like 'duplicate command signatures'
    it_behaves_like 'complex scripts'
    it_behaves_like 'document boundary comments'
    it_behaves_like 'matched leading comments'
    it_behaves_like 'removed node leading comments'
    it_behaves_like 'conservative inline comments'
    it_behaves_like 'removed node inline comments'
    it_behaves_like 'multi-byte character (emoji) handling'
    it_behaves_like 'floating comment gap transitions'
  end

  # ============================================================
  # Backend-aware tests - Rust/tree_stump
  # ============================================================

  context 'with Rust backend', :bash_grammar, :rust_backend do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    it_behaves_like 'basic initialization'
    it_behaves_like 'configuration options'
    it_behaves_like 'instance methods'
    it_behaves_like 'accessors'
    it_behaves_like 'basic merge operation'
    it_behaves_like 'template preference'
    it_behaves_like 'merge_with_debug'
    it_behaves_like 'validation'
    it_behaves_like 'add template-only nodes'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'function merging'
    it_behaves_like 'duplicate command signatures'
    it_behaves_like 'complex scripts'
    it_behaves_like 'document boundary comments'
    it_behaves_like 'matched leading comments'
    it_behaves_like 'removed node leading comments'
    it_behaves_like 'conservative inline comments'
    it_behaves_like 'removed node inline comments'
    it_behaves_like 'multi-byte character (emoji) handling'
    it_behaves_like 'floating comment gap transitions'
  end

  describe 'unresolved runtime flow', :bash_grammar, :mri_backend do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    let(:template_content) do
      <<~BASH
        #!/bin/bash
        MY_VAR="template_value"
      BASH
    end

    let(:destination_content) do
      <<~BASH
        #!/bin/bash
        MY_VAR="dest_value"
      BASH
    end

    let(:unresolved_runtime_merger) do
      described_class.new(
        template_content,
        destination_content,
        resolution_mode: :unresolved
      )
    end
    let(:expected_unresolved_surface_path) { 'document[0] > variable_assignment["MY_VAR"]' }
    let(:expected_unresolved_output_fragment) { 'MY_VAR="dest_value"' }
    let(:build_fresh_unresolved_merge_result) do
      lambda do
        described_class.new(
          template_content,
          destination_content,
          resolution_mode: :unresolved
        ).merge_result
      end
    end
    let(:expected_replayed_output_fragment) { 'MY_VAR="template_value"' }

    it_behaves_like 'Ast::Merge::UnresolvedRuntimeContract'
    it_behaves_like 'Ast::Merge::UnresolvedRuntimeDebugContract'
    it_behaves_like 'Ast::Merge::UnresolvedReviewStateTransportContract'
  end

  # ============================================================
  # Backend-aware tests - Java/jtreesitter
  # ============================================================

  context 'with Java backend', :bash_grammar, :java_backend do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    it_behaves_like 'basic initialization'
    it_behaves_like 'configuration options'
    it_behaves_like 'instance methods'
    it_behaves_like 'accessors'
    it_behaves_like 'basic merge operation'
    it_behaves_like 'template preference'
    it_behaves_like 'merge_with_debug'
    it_behaves_like 'validation'
    it_behaves_like 'add template-only nodes'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'function merging'
    it_behaves_like 'duplicate command signatures'
    it_behaves_like 'complex scripts'
    it_behaves_like 'document boundary comments'
    it_behaves_like 'matched leading comments'
    it_behaves_like 'removed node leading comments'
    it_behaves_like 'conservative inline comments'
    it_behaves_like 'removed node inline comments'
    it_behaves_like 'multi-byte character (emoji) handling'
    it_behaves_like 'floating comment gap transitions'
  end
end
