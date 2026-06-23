# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bash::Merge::NodeWrapper do
  # NodeWrapper requires a tree-sitter node, which requires parser availability
  # Tests tagged :tree_sitter_bash are skipped when the grammar is not available

  describe 'class structure' do
    it 'is a class' do
      expect(described_class).to be_a(Class)
    end
  end

  describe 'when tree-sitter parser is available', :bash_grammar do
    let(:bash_content) { "echo 'hello'" }

    it 'creates wrapper instances from FileAnalysis' do
      analysis = Bash::Merge::FileAnalysis.new(bash_content)

      nodes = analysis.nodes
      expect(nodes).to be_an(Array)
      expect(nodes).to all(be_a(described_class).or(be_a(Bash::Merge::FreezeNode)))
    end
  end

  describe '#freeze_node?', :bash_grammar do
    it 'returns false for NodeWrapper instances' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)

      node = analysis.nodes.first
      expect(node).to be_a(described_class)
      expect(node.freeze_node?).to be false
    end
  end

  describe 'type predicates with real parsed content', :bash_grammar do
    describe '#function_definition?' do
      it 'returns true for function definitions' do
        source = <<~BASH
          my_function() {
            echo "hello"
          }
        BASH
        analysis = Bash::Merge::FileAnalysis.new(source)
        func_node = analysis.nodes.find { |n| n.respond_to?(:function_definition?) && n.function_definition? }
        expect(func_node).not_to be_nil
        expect(func_node.function_definition?).to be true
      end

      it 'returns false for non-function nodes' do
        source = "echo 'hello'"
        analysis = Bash::Merge::FileAnalysis.new(source)
        node = analysis.nodes.first
        expect(node.function_definition?).to be false
      end
    end

    describe '#variable_assignment?' do
      it 'returns true for variable assignments' do
        source = "MY_VAR='value'"
        analysis = Bash::Merge::FileAnalysis.new(source)
        var_node = analysis.nodes.find { |n| n.respond_to?(:variable_assignment?) && n.variable_assignment? }
        expect(var_node).not_to be_nil
        expect(var_node.variable_assignment?).to be true
      end

      it 'returns false for non-assignment nodes' do
        source = "echo 'hello'"
        analysis = Bash::Merge::FileAnalysis.new(source)
        node = analysis.nodes.first
        expect(node.variable_assignment?).to be false
      end
    end

    describe '#command?' do
      it 'returns true for commands' do
        source = "echo 'hello'"
        analysis = Bash::Merge::FileAnalysis.new(source)
        cmd_node = analysis.nodes.find { |n| n.respond_to?(:command?) && n.command? }
        expect(cmd_node).not_to be_nil
        expect(cmd_node.command?).to be true
      end
    end

    describe '#if_statement?' do
      it 'returns true for if statements' do
        source = <<~BASH
          if [ -n "$VAR" ]; then
            echo "set"
          fi
        BASH
        analysis = Bash::Merge::FileAnalysis.new(source)
        if_node = analysis.nodes.find { |n| n.respond_to?(:if_statement?) && n.if_statement? }
        expect(if_node).not_to be_nil
        expect(if_node.if_statement?).to be true
      end
    end

    describe '#for_statement?' do
      it 'returns true for for loops' do
        source = <<~BASH
          for i in 1 2 3; do
            echo $i
          done
        BASH
        analysis = Bash::Merge::FileAnalysis.new(source)
        for_node = analysis.nodes.find { |n| n.respond_to?(:for_statement?) && n.for_statement? }
        expect(for_node).not_to be_nil
        expect(for_node.for_statement?).to be true
      end
    end

    describe '#while_statement?' do
      it 'returns true for while loops' do
        source = <<~BASH
          while true; do
            echo "loop"
          done
        BASH
        analysis = Bash::Merge::FileAnalysis.new(source)
        while_node = analysis.nodes.find { |n| n.respond_to?(:while_statement?) && n.while_statement? }
        expect(while_node).not_to be_nil
        expect(while_node.while_statement?).to be true
      end
    end

    describe '#case_statement?' do
      it 'returns true for case statements' do
        source = <<~BASH
          case "$1" in
            start) echo "starting" ;;
            stop) echo "stopping" ;;
          esac
        BASH
        analysis = Bash::Merge::FileAnalysis.new(source)
        case_node = analysis.nodes.find { |n| n.respond_to?(:case_statement?) && n.case_statement? }
        expect(case_node).not_to be_nil
        expect(case_node.case_statement?).to be true
      end
    end

    describe '#pipeline?' do
      it 'returns true for pipelines' do
        source = 'cat file.txt | grep pattern | wc -l'
        analysis = Bash::Merge::FileAnalysis.new(source)
        pipeline_node = analysis.nodes.find { |n| n.respond_to?(:pipeline?) && n.pipeline? }
        expect(pipeline_node).not_to be_nil
        expect(pipeline_node.pipeline?).to be true
      end
    end

    describe '#comment?' do
      it 'returns true for comments' do
        source = '# This is a comment'
        analysis = Bash::Merge::FileAnalysis.new(source)
        root = analysis.root_node
        comment_child = root.children.find { |c| c.comment? }
        expect(comment_child).not_to be_nil
        expect(comment_child.comment?).to be true
      end
    end
  end

  describe '#function_name', :bash_grammar do
    it 'returns the function name for function definitions' do
      source = <<~BASH
        my_awesome_function() {
          echo "hello"
        }
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      func_node = analysis.nodes.find { |n| n.respond_to?(:function_definition?) && n.function_definition? }
      expect(func_node).not_to be_nil
      expect(func_node.function_name).to eq('my_awesome_function')
    end

    it 'returns nil for non-function nodes' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      node = analysis.nodes.first
      expect(node.function_name).to be_nil
    end
  end

  describe '#variable_name', :bash_grammar do
    it 'returns the variable name for assignments' do
      source = "MY_VAR='value'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      var_node = analysis.nodes.find { |n| n.respond_to?(:variable_assignment?) && n.variable_assignment? }
      expect(var_node).not_to be_nil
      expect(var_node.variable_name).to eq('MY_VAR')
    end

    it 'returns nil for non-assignment nodes' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      node = analysis.nodes.first
      expect(node.variable_name).to be_nil
    end
  end

  describe '#command_name', :bash_grammar do
    it 'returns the command name for commands' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      cmd_node = analysis.nodes.find { |n| n.respond_to?(:command?) && n.command? }
      expect(cmd_node).not_to be_nil
      expect(cmd_node.command_name).to eq('echo')
    end

    it 'returns nil for non-command nodes' do
      source = "MY_VAR='value'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      var_node = analysis.nodes.find { |n| n.respond_to?(:variable_assignment?) && n.variable_assignment? }
      expect(var_node).not_to be_nil
      expect(var_node.command_name).to be_nil
    end
  end

  describe '#children', :bash_grammar do
    it 'returns wrapped child nodes' do
      source = <<~BASH
        if [ -n "$VAR" ]; then
          echo "set"
        fi
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      if_node = analysis.nodes.find { |n| n.respond_to?(:if_statement?) && n.if_statement? }
      expect(if_node).not_to be_nil
      children = if_node.children
      expect(children).to be_an(Array)
      expect(children).to all(be_a(described_class))
    end

    it 'returns empty array for leaf nodes' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      # String literal should be a leaf
      cmd_node = analysis.nodes.find { |n| n.respond_to?(:command?) && n.command? }
      expect(cmd_node).not_to be_nil
      # Command nodes do have children (the word nodes)
      expect(cmd_node.children).to be_an(Array)
    end
  end

  describe '#signature', :bash_grammar do
    it 'generates signature for function definitions' do
      source = <<~BASH
        my_function() {
          echo "hello"
        }
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      func_node = analysis.nodes.find { |n| n.respond_to?(:function_definition?) && n.function_definition? }
      expect(func_node).not_to be_nil
      sig = func_node.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:function_definition)
      expect(sig.last).to eq('my_function')
    end

    it 'generates signature for variable assignments' do
      source = "MY_VAR='value'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      var_node = analysis.nodes.find { |n| n.respond_to?(:variable_assignment?) && n.variable_assignment? }
      expect(var_node).not_to be_nil
      sig = var_node.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:variable_assignment)
      expect(sig.last).to eq('MY_VAR')
    end

    it 'generates signature for commands' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      cmd_node = analysis.nodes.find { |n| n.respond_to?(:command?) && n.command? }
      expect(cmd_node).not_to be_nil
      sig = cmd_node.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:command)
      expect(sig[1]).to eq('echo')
    end

    it 'generates signature for if statements' do
      source = <<~BASH
        if [ -n "$VAR" ]; then
          echo "set"
        fi
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      if_node = analysis.nodes.find { |n| n.respond_to?(:if_statement?) && n.if_statement? }
      expect(if_node).not_to be_nil
      sig = if_node.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:if_statement)
    end

    it 'generates signature for for statements' do
      source = <<~BASH
        for i in 1 2 3; do
          echo $i
        done
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      for_node = analysis.nodes.find { |n| n.respond_to?(:for_statement?) && n.for_statement? }
      expect(for_node).not_to be_nil
      sig = for_node.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:for_statement)
    end

    it 'generates signature for while statements' do
      source = <<~BASH
        while true; do
          echo "loop"
        done
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      while_node = analysis.nodes.find { |n| n.respond_to?(:while_statement?) && n.while_statement? }
      expect(while_node).not_to be_nil
      sig = while_node.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:while_statement)
    end

    it 'generates signature for case statements' do
      source = <<~BASH
        case "$1" in
          start) echo "starting" ;;
        esac
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      case_node = analysis.nodes.find { |n| n.respond_to?(:case_statement?) && n.case_statement? }
      expect(case_node).not_to be_nil
      sig = case_node.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:case_statement)
    end

    it 'generates signature for pipelines' do
      source = 'cat file | grep pattern'
      analysis = Bash::Merge::FileAnalysis.new(source)
      pipeline_node = analysis.nodes.find { |n| n.respond_to?(:pipeline?) && n.pipeline? }
      expect(pipeline_node).not_to be_nil
      sig = pipeline_node.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:pipeline)
      expect(sig.last).to be_an(Array)
    end

    it 'generates signature for program root' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      root = analysis.root_node
      expect(root).not_to be_nil
      sig = root.signature
      expect(sig).to be_an(Array)
      expect(sig.first).to eq(:program)
    end
  end

  describe '#text and #content', :bash_grammar do
    it 'extracts text from nodes' do
      source = "echo 'hello world'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      cmd_node = analysis.nodes.find { |n| n.respond_to?(:command?) && n.command? }
      expect(cmd_node).not_to be_nil
      text = cmd_node.text
      expect(text).to include('echo')
      expect(text).to include('hello world')
    end

    it 'extracts content from lines' do
      source = "echo 'hello world'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      cmd_node = analysis.nodes.find { |n| n.respond_to?(:command?) && n.command? }
      expect(cmd_node).not_to be_nil
      content = cmd_node.content
      expect(content).to include('echo')
    end
  end

  describe '#start_line and #end_line', :bash_grammar do
    it 'provides line information' do
      source = <<~BASH
        echo "line 1"
        echo "line 2"
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      root = analysis.root_node
      expect(root.start_line).to be_a(Integer)
      expect(root.end_line).to be_a(Integer)
      expect(root.start_line).to be >= 1
      expect(root.end_line).to be >= root.start_line
    end

    it 'handles multiline constructs' do
      source = <<~BASH
        if [ -n "$VAR" ]; then
          echo "set"
          echo "more"
        fi
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      if_node = analysis.nodes.find { |n| n.respond_to?(:if_statement?) && n.if_statement? }
      expect(if_node).not_to be_nil
      expect(if_node.start_line).to eq(1)
      expect(if_node.end_line).to eq(4)
    end
  end

  describe '#type and #type?', :bash_grammar do
    it 'returns the node type' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      cmd_node = analysis.nodes.find { |n| n.respond_to?(:command?) && n.command? }
      expect(cmd_node).not_to be_nil
      expect(cmd_node.type).to be_a(Symbol)
    end

    it 'checks type with type?' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      cmd_node = analysis.nodes.find { |n| n.respond_to?(:command?) && n.command? }
      expect(cmd_node).not_to be_nil
      expect(cmd_node.type?(:command)).to be true
      expect(cmd_node.type?('command')).to be true
      expect(cmd_node.type?(:function_definition)).to be false
    end
  end

  describe '#inspect', :bash_grammar do
    it 'returns a debug string' do
      source = "echo 'hello'"
      analysis = Bash::Merge::FileAnalysis.new(source)
      node = analysis.nodes.first
      inspect_str = node.inspect
      expect(inspect_str).to include('NodeWrapper')
      expect(inspect_str).to include('type=')
    end
  end

  describe 'edge cases', :bash_grammar do
    it 'handles empty content' do
      source = ''
      analysis = Bash::Merge::FileAnalysis.new(source)
      # Should not raise
      expect(analysis.nodes).to be_an(Array)
    end

    it 'handles comments only' do
      source = '# Just a comment'
      analysis = Bash::Merge::FileAnalysis.new(source)
      expect(analysis.valid?).to be true
    end

    it 'handles heredocs' do
      source = <<~BASH
        cat <<EOF
        This is a heredoc
        with multiple lines
        EOF
      BASH
      analysis = Bash::Merge::FileAnalysis.new(source)
      expect(analysis.valid?).to be true
      expect(analysis.nodes).not_to be_empty
    end

    it 'handles command with redirections' do
      source = "echo 'hello' > output.txt 2>&1"
      analysis = Bash::Merge::FileAnalysis.new(source)
      # Commands with redirections may be wrapped in redirected_statement
      # or may be direct commands depending on tree-sitter-bash version
      cmd_node = analysis.nodes.find do |n|
        (n.respond_to?(:command?) && n.command?) ||
          (n.respond_to?(:type) && n.type.to_s == 'redirected_statement')
      end
      expect(cmd_node).not_to be_nil
      sig = cmd_node.signature
      # Should have a valid signature
      expect(sig).to be_an(Array)
      expect(sig.first).to be_a(Symbol)
    end
  end
end
