# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bash::Merge::Emitter do
  let(:emitter) { described_class.new }

  describe '#initialize' do
    it 'starts with empty lines' do
      expect(emitter.lines).to be_empty
    end

    it 'starts at indent level 0' do
      expect(emitter.indent_level).to eq(0)
    end

    it 'accepts custom indent size' do
      custom_emitter = described_class.new(indent_size: 4)
      expect(custom_emitter.indent_size).to eq(4)
    end
  end

  describe '#emit_comment' do
    it 'emits a full-line comment' do
      emitter.emit_comment('This is a comment')
      expect(emitter.lines).to include('# This is a comment')
    end

    it 'emits an inline comment' do
      emitter.emit_line("echo 'hello'")
      emitter.emit_comment('inline', inline: true)
      expect(emitter.lines.last).to eq("echo 'hello' # inline")
    end

    it 'does nothing for inline comment when lines is empty' do
      emitter.emit_comment('inline', inline: true)
      expect(emitter.lines).to be_empty
    end
  end

  describe '#emit_leading_comments' do
    it 'emits leading comments preserving indentation' do
      comments = [
        { text: 'First comment', indent: 0 },
        { text: 'Indented comment', indent: 2 }
      ]
      emitter.emit_leading_comments(comments)
      expect(emitter.lines[0]).to eq('# First comment')
      expect(emitter.lines[1]).to eq('  # Indented comment')
    end

    it 'handles missing indent' do
      comments = [{ text: 'No indent specified' }]
      emitter.emit_leading_comments(comments)
      expect(emitter.lines[0]).to eq('# No indent specified')
    end
  end

  describe '#emit_blank_line' do
    it 'emits an empty line' do
      emitter.emit_blank_line
      expect(emitter.lines).to eq([''])
    end
  end

  describe '#emit_shebang' do
    it 'emits a shebang line' do
      emitter.emit_shebang('/bin/bash')
      expect(emitter.lines.first).to eq('#!/bin/bash')
    end

    it 'uses /bin/bash by default' do
      emitter.emit_shebang
      expect(emitter.lines.first).to eq('#!/bin/bash')
    end

    it 'accepts custom interpreter' do
      emitter.emit_shebang('/usr/bin/env bash')
      expect(emitter.lines.first).to eq('#!/usr/bin/env bash')
    end
  end

  describe '#emit_variable_assignment' do
    it 'emits a simple variable assignment' do
      emitter.emit_variable_assignment('FOO', '"bar"')
      expect(emitter.lines).to include('FOO="bar"')
    end

    it 'emits an exported variable' do
      emitter.emit_variable_assignment('FOO', '"bar"', export: true)
      expect(emitter.lines).to include('export FOO="bar"')
    end

    it 'includes inline comment when provided' do
      emitter.emit_variable_assignment('FOO', '"bar"', inline_comment: 'my var')
      expect(emitter.lines.last).to include('# my var')
    end
  end

  describe '#emit_function_start / #emit_function_end' do
    it 'emits a function definition' do
      emitter.emit_function_start('my_func')
      emitter.emit_line('echo "inside"')
      emitter.emit_function_end

      result = emitter.to_bash
      expect(result).to include('my_func() {')
      expect(result).to include('}')
    end

    it 'indents function body' do
      emitter.emit_function_start('my_func')
      emitter.emit_line('echo "inside"')
      emitter.emit_function_end

      expect(emitter.lines[1]).to match(/^\s+echo/)
    end
  end

  describe '#emit_if_start / #emit_elif / #emit_else / #emit_fi' do
    it 'emits an if statement' do
      emitter.emit_if_start('[ "$x" -eq 1 ]')
      emitter.emit_line('echo "yes"')
      emitter.emit_fi

      result = emitter.to_bash
      expect(result).to include('if [ "$x" -eq 1 ]; then')
      expect(result).to include('fi')
    end

    it 'emits an elif clause' do
      emitter.emit_if_start('[ "$x" -eq 1 ]')
      emitter.emit_line('echo "one"')
      emitter.emit_elif('[ "$x" -eq 2 ]')
      emitter.emit_line('echo "two"')
      emitter.emit_fi

      result = emitter.to_bash
      expect(result).to include('elif [ "$x" -eq 2 ]; then')
    end

    it 'emits an else clause' do
      emitter.emit_if_start('[ "$x" -eq 1 ]')
      emitter.emit_line('echo "yes"')
      emitter.emit_else
      emitter.emit_line('echo "no"')
      emitter.emit_fi

      result = emitter.to_bash
      expect(result).to include('else')
    end

    it 'handles complex if-elif-else chains' do
      emitter.emit_if_start('[ "$x" -eq 1 ]')
      emitter.emit_line('echo "one"')
      emitter.emit_elif('[ "$x" -eq 2 ]')
      emitter.emit_line('echo "two"')
      emitter.emit_else
      emitter.emit_line('echo "other"')
      emitter.emit_fi

      result = emitter.to_bash
      expect(result).to include('if')
      expect(result).to include('elif')
      expect(result).to include('else')
      expect(result).to include('fi')
    end
  end

  describe '#emit_for_start / #emit_done' do
    it 'emits a for loop' do
      emitter.emit_for_start('i', '1 2 3')
      emitter.emit_line('echo "$i"')
      emitter.emit_done

      result = emitter.to_bash
      expect(result).to include('for i in 1 2 3; do')
      expect(result).to include('done')
    end
  end

  describe '#emit_while_start / #emit_done' do
    it 'emits a while loop' do
      emitter.emit_while_start('true')
      emitter.emit_line('sleep 1')
      emitter.emit_done

      result = emitter.to_bash
      expect(result).to include('while true; do')
      expect(result).to include('done')
    end

    it 'indents while body' do
      emitter.emit_while_start('[ "$x" -lt 10 ]')
      emitter.emit_line('x=$((x + 1))')
      emitter.emit_done

      expect(emitter.lines[1]).to match(/^\s+x=/)
    end
  end

  describe '#emit_case_start / #emit_case_pattern / #emit_case_pattern_end / #emit_esac' do
    it 'emits a case statement' do
      emitter.emit_case_start('"$1"')
      emitter.emit_case_pattern('start')
      emitter.emit_line('echo "starting"')
      emitter.emit_case_pattern_end
      emitter.emit_case_pattern('stop')
      emitter.emit_line('echo "stopping"')
      emitter.emit_case_pattern_end
      emitter.emit_esac

      result = emitter.to_bash
      expect(result).to include('case "$1" in')
      expect(result).to include('start)')
      expect(result).to include(';;')
      expect(result).to include('stop)')
      expect(result).to include('esac')
    end
  end

  describe '#emit_raw_lines' do
    it 'emits lines as-is' do
      emitter.emit_raw_lines(%W[line1\n line2\n])
      expect(emitter.lines).to eq(%w[line1 line2])
    end

    it 'handles lines without newlines' do
      emitter.emit_raw_lines(%w[line1 line2])
      expect(emitter.lines).to eq(%w[line1 line2])
    end
  end

  describe '#to_bash' do
    it 'joins lines with newlines' do
      emitter.emit_shebang
      emitter.emit_line('echo "hello"')

      result = emitter.to_bash
      expect(result).to eq("#!/bin/bash\necho \"hello\"\n")
    end

    it 'ensures trailing newline' do
      emitter.emit_line("echo 'test'")
      expect(emitter.to_bash).to end_with("\n")
    end

    it 'handles empty output' do
      # Empty content should still work
      result = emitter.to_bash
      expect(result).to eq('')
    end
  end

  describe '#clear' do
    it 'resets the emitter' do
      emitter.emit_line('test')
      emitter.clear

      expect(emitter.lines).to be_empty
      expect(emitter.indent_level).to eq(0)
    end

    it 'resets indent level even when deeply nested' do
      emitter.emit_function_start('func')
      emitter.emit_if_start('true')
      emitter.emit_for_start('i', '1 2')
      expect(emitter.indent_level).to eq(3)

      emitter.clear
      expect(emitter.indent_level).to eq(0)
    end
  end

  describe 'indentation behavior' do
    it 'does not go below 0 indent level with emit_fi' do
      emitter.emit_fi # Try to decrease from 0
      expect(emitter.indent_level).to eq(0)
    end

    it 'does not go below 0 indent level with emit_function_end' do
      emitter.emit_function_end
      expect(emitter.indent_level).to eq(0)
      expect(emitter.lines.last).to eq('}')
    end

    it 'does not go below 0 indent level with emit_elif' do
      emitter.emit_elif('[ "$x" -eq 2 ]')
      expect(emitter.indent_level).to eq(1)
      expect(emitter.lines.last).to eq('elif [ "$x" -eq 2 ]; then')
    end

    it 'does not go below 0 indent level with emit_else' do
      emitter.emit_else
      expect(emitter.indent_level).to eq(1)
      expect(emitter.lines.last).to eq('else')
    end

    it 'does not go below 0 indent level with emit_done' do
      emitter.emit_done
      expect(emitter.indent_level).to eq(0)
      expect(emitter.lines.last).to eq('done')
    end

    it 'does not go below 0 indent level with emit_case_pattern_end' do
      emitter.emit_case_pattern_end
      expect(emitter.indent_level).to eq(0)
      expect(emitter.lines.last).to eq(';;')
    end

    it 'does not go below 0 indent level with emit_esac' do
      emitter.emit_esac
      expect(emitter.indent_level).to eq(0)
      expect(emitter.lines.last).to eq('esac')
    end

    it 'uses correct indent for nested structures' do
      emitter.emit_function_start('outer')
      emitter.emit_if_start('true')
      emitter.emit_line("echo 'nested'")

      # The nested echo should have 4 spaces (2 levels × 2 spaces)
      nested_line = emitter.lines.find { |l| l.include?('nested') }
      expect(nested_line).to start_with('    ')
    end

    it 'respects custom indent size' do
      custom = described_class.new(indent_size: 4)
      custom.emit_function_start('func')
      custom.emit_line("echo 'test'")

      nested_line = custom.lines.find { |l| l.include?('test') }
      expect(nested_line).to start_with('    ') # 4 spaces
    end
  end
end
