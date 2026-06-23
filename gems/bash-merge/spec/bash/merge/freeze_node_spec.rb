# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

RSpec.describe Bash::Merge::FreezeNode do
  # Use shared examples to validate base FreezeNodeBase integration
  it_behaves_like 'Ast::Merge::FreezeNodeBase' do
    let(:freeze_node_class) { described_class }
    let(:default_pattern_type) { :hash_comment }
    let(:build_freeze_node) do
      lambda { |start_line:, end_line:, **opts|
        # Build enough lines to cover the requested range
        lines = opts.delete(:lines) || begin
          result = []
          (1..end_line).each do |i|
            result << if i == start_line
                        '# bash-merge:freeze'
                      elsif i == end_line
                        '# bash-merge:unfreeze'
                      else
                        "VAR_#{i}=\"value_#{i}\""
                      end
          end
          result
        end
        freeze_node_class.new(
          start_line: start_line,
          end_line: end_line,
          lines: lines,
          pattern_type: opts[:pattern_type] || :hash_comment,
          **opts.except(:pattern_type)
        )
      }
    end
  end

  # Bash-specific tests
  let(:lines) do
    [
      '#!/bin/bash',
      '# bash-merge:freeze',
      'SECRET="my-secret"',
      '# bash-merge:unfreeze',
      'echo "hello"'
    ]
  end

  describe '#initialize' do
    it 'creates a freeze node from start and end lines' do
      freeze_node = described_class.new(
        start_line: 2,
        end_line: 4,
        lines: lines
      )

      expect(freeze_node.start_line).to eq(2)
      expect(freeze_node.end_line).to eq(4)
    end

    it 'extracts lines within the freeze block' do
      freeze_node = described_class.new(
        start_line: 2,
        end_line: 4,
        lines: lines
      )

      expect(freeze_node.lines.size).to eq(3)
      expect(freeze_node.lines).to include('SECRET="my-secret"')
    end

    it 'raises error for invalid structure' do
      expect do
        described_class.new(
          start_line: 5,
          end_line: 2,
          lines: lines
        )
      end.to raise_error(Bash::Merge::FreezeNode::InvalidStructureError)
    end
  end

  describe '#signature' do
    it 'generates consistent signatures for same content' do
      node1 = described_class.new(start_line: 2, end_line: 4, lines: lines)
      node2 = described_class.new(start_line: 2, end_line: 4, lines: lines)

      expect(node1.signature).to eq(node2.signature)
    end

    it 'handles lines with varying whitespace' do
      lines_with_spaces = [
        '#!/bin/bash',
        '# bash-merge:freeze',
        '  SECRET="my-secret"  ',
        '# bash-merge:unfreeze',
        'echo "hello"'
      ]
      node = described_class.new(start_line: 2, end_line: 4, lines: lines_with_spaces)
      expect(node.signature.first).to eq(:FreezeNode)
      expect(node.signature.last).to include('SECRET="my-secret"')
    end

    it 'handles lines containing empty strings after strip' do
      lines_with_empty = [
        '#!/bin/bash',
        '# bash-merge:freeze',
        '   ',
        'SECRET="my-secret"',
        '# bash-merge:unfreeze'
      ]
      node = described_class.new(start_line: 2, end_line: 5, lines: lines_with_empty)
      expect(node.signature.first).to eq(:FreezeNode)
      # The empty line should be excluded from the normalized content
      expect(node.signature.last).not_to include("\n\n")
    end

    it 'handles lines with nil values intermixed' do
      # This exercises the l&.strip safe navigation when l is nil
      lines_with_nil = [
        '# bash-merge:freeze',
        nil,
        'SECRET="value"',
        '# bash-merge:unfreeze'
      ]
      node = described_class.new(start_line: 1, end_line: 4, lines: lines_with_nil)
      expect(node.signature.first).to eq(:FreezeNode)
      # nil lines should be filtered out by compact
      expect(node.signature.last).to include('SECRET')
    end
  end

  describe '#location' do
    it 'returns a Location struct' do
      freeze_node = described_class.new(
        start_line: 2,
        end_line: 4,
        lines: lines
      )

      expect(freeze_node.location).to respond_to(:start_line)
      expect(freeze_node.location).to respond_to(:end_line)
      expect(freeze_node.location).to respond_to(:cover?)
    end

    it 'covers lines within the block' do
      freeze_node = described_class.new(
        start_line: 2,
        end_line: 4,
        lines: lines
      )

      expect(freeze_node.location.cover?(2)).to be(true)
      expect(freeze_node.location.cover?(3)).to be(true)
      expect(freeze_node.location.cover?(4)).to be(true)
      expect(freeze_node.location.cover?(1)).to be(false)
      expect(freeze_node.location.cover?(5)).to be(false)
    end
  end

  describe 'bash-specific methods' do
    let(:freeze_node) do
      described_class.new(
        start_line: 2,
        end_line: 4,
        lines: lines
      )
    end

    it '#function_definition? returns false' do
      expect(freeze_node.function_definition?).to be(false)
    end

    it '#variable_assignment? returns false' do
      expect(freeze_node.variable_assignment?).to be(false)
    end

    it '#command? returns false' do
      expect(freeze_node.command?).to be(false)
    end

    it '#inspect returns a useful string' do
      result = freeze_node.inspect
      expect(result).to include('FreezeNode')
      expect(result).to include('2..4')
    end

    it '#inspect shows content_length when slice has content' do
      result = freeze_node.inspect
      # The slice should have content, so content_length should be > 0
      expect(result).to match(/content_length=\d+/)
      # Verify it's not showing 0 (the else branch of || 0)
      expect(result).not_to include('content_length=0')
    end

    it '#slice returns content with non-zero length' do
      # Explicitly test that slice returns content (covers the else branch of || 0)
      slice_content = freeze_node.slice
      expect(slice_content).not_to be_nil
      expect(slice_content.length).to be > 0
    end
  end

  describe 'validation edge cases' do
    it 'raises error for empty freeze block' do
      empty_lines = [nil, nil, nil]
      expect do
        described_class.new(
          start_line: 1,
          end_line: 3,
          lines: empty_lines
        )
      end.to raise_error(Bash::Merge::FreezeNode::InvalidStructureError, /empty/i)
    end

    it 'raises error for reversed line order' do
      expect do
        described_class.new(
          start_line: 5,
          end_line: 1,
          lines: lines
        )
      end.to raise_error(Bash::Merge::FreezeNode::InvalidStructureError)
    end
  end
end
