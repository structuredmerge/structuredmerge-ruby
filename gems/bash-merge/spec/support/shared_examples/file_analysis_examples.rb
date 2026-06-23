# frozen_string_literal: true

# Shared examples for FileAnalysis across different backends
#
# These examples test FileAnalysis behavior that should be consistent
# regardless of which tree-sitter backend is used (MRI, FFI, Rust, Java).

RSpec.shared_examples 'bash source parsing' do |expected_backend:|
  describe 'with valid bash source' do
    let(:simple_bash) do
      <<~BASH
        #!/bin/bash
        echo "hello"
      BASH
    end

    it 'accepts source code' do
      analysis = described_class.new(simple_bash)
      expect(analysis.source).to eq(simple_bash)
    end

    it 'is valid' do
      analysis = described_class.new(simple_bash)
      # Diagnostic info for CI debugging
      unless analysis.valid?
        warn '[DEBUG] Valid bash source analysis failed:'
        warn "  ast.nil?: #{analysis.ast.nil?}"
        warn "  errors: #{analysis.errors.inspect}"
        warn "  parser_path: #{analysis.instance_variable_get(:@parser_path).inspect}"
        warn "  TREE_SITTER_BASH_PATH: #{ENV['TREE_SITTER_BASH_PATH'].inspect}"
        warn "  TreeHaver.effective_backend: #{TreeHaver.effective_backend}"
        if analysis.ast&.root_node
          warn "  root_node.type: #{analysis.ast.root_node.type}"
          warn "  root_node.has_error?: #{analysis.ast.root_node.has_error?}"
        end
      end
      expect(analysis.valid?).to be true
    end

    it 'returns root_node' do
      analysis = described_class.new(simple_bash)
      # Diagnostic info for CI debugging
      if analysis.root_node.nil?
        warn '[DEBUG] root_node is nil:'
        warn "  valid?: #{analysis.valid?}"
        warn "  ast.nil?: #{analysis.ast.nil?}"
        warn "  errors: #{analysis.errors.inspect}"
      end
      expect(analysis.root_node).to be_a(Bash::Merge::NodeWrapper)
    end
  end
end

RSpec.shared_examples 'initialization options' do
  it 'accepts freeze_token option' do
    analysis = described_class.new("echo 'test'", freeze_token: 'custom-token')
    expect(analysis.freeze_token).to eq('custom-token')
  end

  it 'uses default freeze token' do
    analysis = described_class.new("echo 'test'")
    expect(analysis.freeze_token).to eq('bash-merge')
  end

  it 'accepts signature_generator option' do
    custom_gen = ->(node) { [:custom, node.class.name] }
    analysis = described_class.new("echo 'test'", signature_generator: custom_gen)
    expect(analysis).to be_a(described_class)
  end

  it 'accepts additional options for forward compatibility' do
    expect do
      described_class.new("echo 'test'", unknown_option: true, another: 'value')
    end.not_to raise_error
  end
end

RSpec.shared_examples 'invalid source handling' do
  it 'returns false with error when parser path is invalid' do
    analysis = described_class.new("echo 'test'", parser_path: '/nonexistent/path.so')
    expect(analysis.valid?).to be(false)
    expect(analysis.errors).not_to be_empty
  end
end

RSpec.shared_examples 'line access' do
  describe 'line methods' do
    it '#lines returns source split into lines' do
      source = "line1\nline2\nline3"
      analysis = described_class.new(source)
      expect(analysis.lines).to eq(%w[line1 line2 line3])
    end

    it '#line_at returns the line at the given 1-based index' do
      source = "line1\nline2\nline3"
      analysis = described_class.new(source)
      expect(analysis.line_at(2)).to eq('line2')
    end

    it '#line_at returns nil for out-of-bounds index' do
      analysis = described_class.new('line1')
      expect(analysis.line_at(5)).to be_nil
    end

    it '#normalized_line returns stripped line content' do
      source = '  indented  '
      analysis = described_class.new(source)
      expect(analysis.normalized_line(1)).to eq('indented')
    end
  end
end

RSpec.shared_examples 'freeze block detection' do
  describe 'freeze blocks' do
    it 'extracts freeze blocks from source' do
      source = <<~BASH
        #!/bin/bash
        # bash-merge:freeze
        SECRET="value"
        # bash-merge:unfreeze
        echo "hello"
      BASH

      analysis = described_class.new(source)
      expect(analysis.freeze_blocks.size).to eq(1)
    end

    it 'handles multiple freeze blocks' do
      source = <<~BASH
        #!/bin/bash
        # bash-merge:freeze
        SECRET1="value1"
        # bash-merge:unfreeze
        echo "between"
        # bash-merge:freeze
        SECRET2="value2"
        # bash-merge:unfreeze
      BASH

      analysis = described_class.new(source)
      expect(analysis.freeze_blocks.size).to eq(2)
    end

    it 'handles unmatched freeze markers' do
      source = <<~BASH
        #!/bin/bash
        # bash-merge:freeze
        SECRET="value"
        # No unfreeze marker
      BASH

      analysis = described_class.new(source)
      expect(analysis.freeze_blocks.size).to eq(0)
    end
  end
end

RSpec.shared_examples 'in_freeze_block? behavior' do
  describe '#in_freeze_block?' do
    it 'returns true for lines inside freeze blocks' do
      source = <<~BASH
        #!/bin/bash
        # bash-merge:freeze
        SECRET="value"
        # bash-merge:unfreeze
      BASH

      analysis = described_class.new(source)
      expect(analysis.in_freeze_block?(3)).to be(true)
    end

    it 'returns false for lines outside freeze blocks' do
      source = <<~BASH
        #!/bin/bash
        # bash-merge:freeze
        SECRET="value"
        # bash-merge:unfreeze
        echo "hello"
      BASH

      analysis = described_class.new(source)
      expect(analysis.in_freeze_block?(5)).to be(false)
    end

    it 'returns true for freeze marker lines' do
      source = <<~BASH
        #!/bin/bash
        # bash-merge:freeze
        SECRET="value"
        # bash-merge:unfreeze
      BASH

      analysis = described_class.new(source)
      expect(analysis.in_freeze_block?(2)).to be(true)
      expect(analysis.in_freeze_block?(4)).to be(true)
    end
  end
end

RSpec.shared_examples 'freeze_block_at' do
  describe '#freeze_block_at' do
    it 'returns the freeze block containing the line' do
      source = <<~BASH
        #!/bin/bash
        # bash-merge:freeze
        SECRET="value"
        # bash-merge:unfreeze
      BASH

      analysis = described_class.new(source)
      block = analysis.freeze_block_at(3)
      expect(block).to be_a(Bash::Merge::FreezeNode)
    end

    it 'returns nil for lines not in freeze blocks' do
      source = <<~BASH
        #!/bin/bash
        echo "hello"
      BASH

      analysis = described_class.new(source)
      expect(analysis.freeze_block_at(2)).to be_nil
    end
  end
end

RSpec.shared_examples 'comment tracker' do
  describe '#comment_tracker' do
    it 'returns a CommentTracker instance' do
      analysis = described_class.new('# comment')
      expect(analysis.comment_tracker).to be_a(Bash::Merge::CommentTracker)
    end
  end
end

RSpec.shared_examples 'shared comment capability' do
  describe 'shared comment capability' do
    let(:commented_source) do
      <<~BASH
        #!/usr/bin/env bash
        # preamble

        echo "hello" # inline hello
        # trailing
      BASH
    end

    it 'exposes shared comment capability and nodes' do
      analysis = described_class.new(commented_source)

      expect(analysis.comment_capability.source_augmented?).to be true
      expect(analysis.comment_support_style).to be_a(Ast::Merge::Comment::SupportStyle)
      expect(analysis.comment_support_style.source_augmented_portable_write?).to be true
      expect(analysis.comment_support_style.portable_write?).to be true
      expect(analysis.comment_support_style.details[:capability]).to eq(:source_augmented)
      expect(analysis.comment_support_style.details[:source]).to eq(:bash_source)
      expect(analysis.comment_support_style.details[:style]).to eq(:hash_comment)
      expect(analysis.comment_nodes.map(&:line_number)).to eq([2, 4, 5])
      expect(analysis.comment_node_at(4)&.text).to include('inline hello')
    end

    it 'builds attachments and document-boundary regions via augmenter' do
      analysis = described_class.new(commented_source)
      owner = analysis.top_level_statements.first

      attachment = analysis.comment_attachment_for(owner)
      expect(attachment.leading_region.nodes.map(&:line_number)).to eq([2])
      expect(attachment.inline_region.nodes.map(&:line_number)).to eq([4])
      expect(attachment.trailing_region.nodes.map(&:line_number)).to eq([5])

      augmenter = analysis.comment_augmenter(owners: analysis.statements)
      expect(augmenter.preamble_region).to be_nil
      expect(augmenter.postlude_region).to be_nil
    end
  end
end

RSpec.shared_examples 'conservative inline comment capability' do
  describe 'conservative inline comment capability' do
    it 'tracks inline comment attachments for simple command and assignment shapes' do
      source = <<~BASH
        echo "hello" # command docs
        APP_MODE="production" # assignment docs
      BASH

      analysis = described_class.new(source)
      command_owner = analysis.top_level_statements.find(&:command?)
      assignment_owner = analysis.top_level_statements.find(&:variable_assignment?)

      expect(analysis.comment_attachment_for(command_owner).inline_region.nodes.map(&:line_number)).to eq([1])
      expect(analysis.comment_attachment_for(assignment_owner).inline_region.nodes.map(&:line_number)).to eq([2])
      expect(analysis.comment_nodes.map(&:line_number)).to eq([1, 2])
    end

    it 'ignores quoted hash characters when building inline regions' do
      source = <<~BASH
        echo "# not a comment"
        APP_PATH="#/srv/app"
      BASH

      analysis = described_class.new(source)

      expect(analysis.comment_nodes).to be_empty
      expect(analysis.top_level_statements.all? do |statement|
        analysis.comment_attachment_for(statement).inline_region.nil?
      end).to be(true)
    end
  end
end

RSpec.shared_examples 'top level statements' do
  describe '#top_level_statements' do
    it 'returns top-level statements' do
      source = <<~BASH
        echo "one"
        echo "two"
        echo "three"
      BASH
      analysis = described_class.new(source)
      statements = analysis.top_level_statements
      expect(statements).to be_an(Array)
      expect(statements.size).to be >= 3
    end

    it 'excludes comments from statements' do
      source = <<~BASH
        # This is a comment
        echo "one"
      BASH
      analysis = described_class.new(source)
      statements = analysis.top_level_statements
      expect(statements.none? { |s| s.comment? }).to be true
    end

    it 'returns empty array when invalid' do
      analysis = described_class.new("echo 'hello'", parser_path: '/nonexistent/path.so')
      expect(analysis.top_level_statements).to eq([])
    end
  end
end

RSpec.shared_examples 'nodes and statements' do
  describe '#nodes and #statements' do
    it 'returns nodes including freeze blocks' do
      source = <<~BASH
        echo "before"
        # bash-merge:freeze
        SECRET="value"
        # bash-merge:unfreeze
        echo "after"
      BASH
      analysis = described_class.new(source)
      nodes = analysis.nodes
      freeze_nodes = nodes.select { |n| n.is_a?(Bash::Merge::FreezeNode) }
      expect(freeze_nodes.size).to eq(1)
    end

    it 'aliases statements to nodes' do
      analysis = described_class.new("echo 'hello'")
      expect(analysis.statements).to eq(analysis.nodes)
    end
  end
end

RSpec.shared_examples 'fallthrough_node? behavior' do
  describe '#fallthrough_node?' do
    it 'returns true for NodeWrapper instances' do
      analysis = described_class.new("echo 'hello'")
      node = analysis.nodes.first
      expect(analysis.fallthrough_node?(node)).to be true
    end

    it 'returns true for FreezeNode instances' do
      source = <<~BASH
        # bash-merge:freeze
        SECRET="value"
        # bash-merge:unfreeze
      BASH
      analysis = described_class.new(source)
      freeze_node = analysis.freeze_blocks.first
      expect(analysis.fallthrough_node?(freeze_node)).to be true
    end

    it 'returns false for other types' do
      analysis = described_class.new("echo 'hello'")
      expect(analysis.fallthrough_node?('not a node')).to be false
      expect(analysis.fallthrough_node?(nil)).to be false
      expect(analysis.fallthrough_node?(123)).to be false
    end
  end
end

RSpec.shared_examples 'parser path handling' do
  describe '.find_parser_path' do
    it 'returns a string path or nil' do
      path = described_class.find_parser_path
      expect(path.is_a?(String) || path.nil?).to be true
    end
  end

  describe 'error handling' do
    it 'handles missing grammar gracefully' do
      analysis = described_class.new("echo 'hello'", parser_path: '/nonexistent/path.so')
      expect(analysis.valid?).to be false
      expect(analysis.errors).not_to be_empty
    end
  end
end

RSpec.shared_examples 'shared layout compliance' do
  describe 'shared layout compliance' do
    let(:bash_with_layout_gaps) do
      <<~BASH

        alpha() {
          echo "alpha"
        }

        beta() {
          echo "beta"
        }

      BASH
    end

    let(:analysis) { described_class.new(bash_with_layout_gaps) }
    let(:first_owner) { analysis.top_level_statements.first }
    let(:second_owner) { analysis.top_level_statements[1] }
    let(:layout_augmenter) { analysis.layout_augmenter(owners: [first_owner, second_owner].compact) }
    let(:layout_attachment) { layout_augmenter.attachment_for(first_owner) }

    it 'finds stable top-level owners for layout inference' do
      expect(first_owner).not_to be_nil
      expect(second_owner).not_to be_nil
      expect(first_owner.function_definition?).to be true
      expect(second_owner.function_definition?).to be true
    end

    it_behaves_like 'Ast::Merge::Layout::Attachment' do
      let(:expected_attachment_owner) { first_owner }
      let(:expected_leading_gap_kind) { :preamble }
      let(:expected_trailing_gap_kind) { :interstitial }
      let(:expected_gap_ranges) { [1..1, 5..5] }
      let(:expected_leading_controls_output) { true }
      let(:expected_trailing_controls_output) { false }
    end

    it_behaves_like 'Ast::Merge::Layout::Augmenter' do
      let(:augmenter_owner) { first_owner }
      let(:expected_preamble_range) { 1..1 }
      let(:expected_postlude_range) { 9..9 }
      let(:expected_interstitial_ranges) { [5..5] }
      let(:expected_owner_leading_gap_kind) { :preamble }
      let(:expected_owner_trailing_gap_kind) { :interstitial }
    end

    it 'surfaces inferred layout gaps on comment attachments' do
      attachment = analysis.comment_attachment_for(first_owner)

      expect(attachment.leading_gap&.kind).to eq(:preamble)
      expect(attachment.trailing_gap&.kind).to eq(:interstitial)
    end
  end
end

RSpec.shared_examples 'freeze block integration' do
  describe 'integration with freeze blocks' do
    it 'excludes freeze block content from regular nodes' do
      source = <<~BASH
        echo "before"
        # bash-merge:freeze
        SECRET="value"
        # bash-merge:unfreeze
        echo "after"
      BASH
      analysis = described_class.new(source)

      regular_nodes = analysis.nodes.reject { |n| n.is_a?(Bash::Merge::FreezeNode) }
      var_nodes = regular_nodes.select { |n| n.respond_to?(:variable_assignment?) && n.variable_assignment? }
      expect(var_nodes.size).to eq(0)
    end

    it 'sorts nodes by start line' do
      source = <<~BASH
        echo "first"
        # bash-merge:freeze
        SECRET="value"
        # bash-merge:unfreeze
        echo "last"
      BASH
      analysis = described_class.new(source)
      nodes = analysis.nodes

      lines = nodes.map(&:start_line).compact
      expect(lines).to eq(lines.sort)
    end
  end
end

RSpec.shared_examples 'empty source handling' do
  describe 'with empty source' do
    it 'returns true for valid?' do
      analysis = described_class.new('')
      # Diagnostic info for CI debugging
      unless analysis.valid?
        warn '[DEBUG] Empty source analysis failed:'
        warn "  ast.nil?: #{analysis.ast.nil?}"
        warn "  errors: #{analysis.errors.inspect}"
        warn "  parser_path: #{analysis.instance_variable_get(:@parser_path).inspect}"
        warn "  TREE_SITTER_BASH_PATH: #{ENV['TREE_SITTER_BASH_PATH'].inspect}"
        warn "  TreeHaver.effective_backend: #{TreeHaver.effective_backend}"
        if analysis.ast&.root_node
          warn "  root_node.type: #{analysis.ast.root_node.type}"
          warn "  root_node.has_error?: #{analysis.ast.root_node.has_error?}"
        end
      end
      expect(analysis.valid?).to be true
    end
  end
end
