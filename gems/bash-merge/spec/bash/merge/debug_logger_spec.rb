# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

RSpec.describe Bash::Merge::DebugLogger do
  # Use the shared examples to validate base DebugLogger integration
  it_behaves_like 'Ast::Merge::DebugLogger' do
    let(:described_logger) { described_class }
    let(:env_var_name) { 'BASH_MERGE_DEBUG' }
    let(:log_prefix) { '[Bash::Merge]' }
  end

  describe 'Bash-specific functionality' do
    describe '.time' do
      it 'returns the block result' do
        result = described_class.time('test') { 42 }
        expect(result).to eq(42)
      end
    end

    describe '.log_node' do
      let(:source_lines) do
        [
          '# bash-merge:freeze',
          'SECRET_KEY="value"',
          'API_KEY="secret"',
          '# bash-merge:unfreeze',
          'OTHER_VAR="visible"'
        ]
      end

      context 'when debug is enabled' do
        before { stub_env('BASH_MERGE_DEBUG' => '1') }

        it 'logs FreezeNode with lines range' do
          freeze_node = Bash::Merge::FreezeNode.new(
            start_line: 1,
            end_line: 4,
            lines: source_lines
          )

          expect do
            described_class.log_node(freeze_node, label: 'TestFreeze')
          end.to output(/FreezeNode.*1\.\.4/).to_stderr
        end

        it 'logs unknown node types using extract_node_info' do
          unknown_node = Object.new

          expect do
            described_class.log_node(unknown_node, label: 'UnknownNode')
          end.to output(/UnknownNode/).to_stderr
        end
      end

      context 'when debug is disabled' do
        before { stub_env('BASH_MERGE_DEBUG' => nil) }

        it 'does not output anything' do
          freeze_node = Bash::Merge::FreezeNode.new(
            start_line: 1,
            end_line: 4,
            lines: source_lines
          )

          expect do
            described_class.log_node(freeze_node, label: 'Silent')
          end.not_to output.to_stderr
        end
      end
    end
  end
end
