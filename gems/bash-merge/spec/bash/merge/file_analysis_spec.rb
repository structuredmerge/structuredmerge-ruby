# frozen_string_literal: true

require 'spec_helper'

# FileAnalysis specs with explicit backend testing
#
# This spec file tests FileAnalysis behavior across all available tree-sitter backends:
# - :mri (via ruby_tree_sitter gem, tagged :mri_backend)
# - :ffi (via FFI bindings, tagged :ffi_backend)
# - :rust (via tree_stump gem, tagged :rust_backend)
# - :java (via jtreesitter, tagged :java_backend)

RSpec.describe Bash::Merge::FileAnalysis do
  describe 'FileAnalyzable contract', :bash_grammar do
    it_behaves_like 'Ast::Merge::FileAnalyzable' do
      let(:file_analysis_class) { described_class }
      let(:freeze_node_class) { Bash::Merge::FreezeNode }
      let(:sample_source) { "VAR=value\n# comment\n" }
      let(:sample_source_with_freeze) do
        <<~BASH
          VAR=value
          # bash-merge:freeze
          LOCKED=value
          # bash-merge:unfreeze
          OTHER=value
        BASH
      end
      let(:build_file_analysis) do
        ->(source, **opts) { described_class.new(source, **opts) }
      end

      let(:analysis_expected_feature_profile) do
        {
          owner_selector: :line_bound_statements,
          match_key: :signature,
          read_strategy: :source_augmented_portable_write,
          attachment_strategy: :augmenter_preferred_tracker_layout,
          comment_style: :hash_comment,
          render_family: :bash_script_statements,
          capabilities: { layout_aware: true, logical_owner: false },
          logical_owners: {},
          repair_policies: [],
          surfaces: [],
          delegation_policies: []
        }
      end
    end
  end

  # ============================================================
  # :auto backend tests (uses whatever is available)
  # ============================================================

  context 'with :auto backend', :bash_grammar do
    it_behaves_like 'bash source parsing', expected_backend: :auto
    it_behaves_like 'initialization options'
    it_behaves_like 'line access'
    it_behaves_like 'freeze block detection'
    it_behaves_like 'in_freeze_block? behavior'
    it_behaves_like 'freeze_block_at'
    it_behaves_like 'comment tracker'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'conservative inline comment capability'
    it_behaves_like 'top level statements'
    it_behaves_like 'nodes and statements'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'shared layout compliance'
    it_behaves_like 'parser path handling'
    it_behaves_like 'freeze block integration'
    it_behaves_like 'empty source handling'
  end

  context 'with :auto backend - invalid source', :bash_grammar do
    it_behaves_like 'invalid source handling'
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

    it_behaves_like 'bash source parsing', expected_backend: :mri
    it_behaves_like 'initialization options'
    it_behaves_like 'line access'
    it_behaves_like 'freeze block detection'
    it_behaves_like 'in_freeze_block? behavior'
    it_behaves_like 'freeze_block_at'
    it_behaves_like 'comment tracker'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'conservative inline comment capability'
    it_behaves_like 'top level statements'
    it_behaves_like 'nodes and statements'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'shared layout compliance'
    it_behaves_like 'parser path handling'
    it_behaves_like 'freeze block integration'
    it_behaves_like 'empty source handling'
    it_behaves_like 'invalid source handling'
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

    it_behaves_like 'bash source parsing', expected_backend: :ffi
    it_behaves_like 'initialization options'
    it_behaves_like 'line access'
    it_behaves_like 'freeze block detection'
    it_behaves_like 'in_freeze_block? behavior'
    it_behaves_like 'freeze_block_at'
    it_behaves_like 'comment tracker'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'conservative inline comment capability'
    it_behaves_like 'top level statements'
    it_behaves_like 'nodes and statements'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'shared layout compliance'
    it_behaves_like 'parser path handling'
    it_behaves_like 'freeze block integration'
    it_behaves_like 'empty source handling'
    it_behaves_like 'invalid source handling'
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

    it_behaves_like 'bash source parsing', expected_backend: :rust
    it_behaves_like 'initialization options'
    it_behaves_like 'line access'
    it_behaves_like 'freeze block detection'
    it_behaves_like 'in_freeze_block? behavior'
    it_behaves_like 'freeze_block_at'
    it_behaves_like 'comment tracker'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'conservative inline comment capability'
    it_behaves_like 'top level statements'
    it_behaves_like 'nodes and statements'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'shared layout compliance'
    it_behaves_like 'parser path handling'
    it_behaves_like 'freeze block integration'
    it_behaves_like 'empty source handling'
    it_behaves_like 'invalid source handling'
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

    it_behaves_like 'bash source parsing', expected_backend: :java
    it_behaves_like 'initialization options'
    it_behaves_like 'line access'
    it_behaves_like 'freeze block detection'
    it_behaves_like 'in_freeze_block? behavior'
    it_behaves_like 'freeze_block_at'
    it_behaves_like 'comment tracker'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'conservative inline comment capability'
    it_behaves_like 'top level statements'
    it_behaves_like 'nodes and statements'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'shared layout compliance'
    it_behaves_like 'parser path handling'
    it_behaves_like 'freeze block integration'
    it_behaves_like 'empty source handling'
    it_behaves_like 'invalid source handling'
  end
end
