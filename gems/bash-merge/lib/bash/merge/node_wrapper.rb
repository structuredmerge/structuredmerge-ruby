# frozen_string_literal: true

module Bash
  module Merge
    # Wraps TreeHaver nodes with comment associations, line information, and signatures.
    # This provides a unified interface for working with Bash AST nodes during merging.
    #
    # Inherits common functionality from Ast::Merge::NodeWrapperBase:
    # - Source context (lines, source, comments)
    # - Line info extraction
    # - Basic methods: #type, #type?, #text, #content, #signature
    #
    # @example Basic usage
    #   parser = TreeHaver::Parser.new
    #   parser.language = TreeHaver::Language.bash
    #   tree = parser.parse(source)
    #   wrapper = NodeWrapper.new(tree.root_node, lines: source.lines, source: source)
    #   wrapper.signature # => [:program, ...]
    #
    # @see Ast::Merge::NodeWrapperBase
    class NodeWrapper < Ast::Merge::NodeWrapperBase
      attr_reader :node

      # Check if this is a function definition
      # @return [Boolean]
      def function_definition?
        @node.type.to_s == 'function_definition'
      end

      # Check if this is a variable assignment
      # @return [Boolean]
      def variable_assignment?
        @node.type.to_s == 'variable_assignment'
      end

      # Check if this is an if statement
      # @return [Boolean]
      def if_statement?
        @node.type.to_s == 'if_statement'
      end

      # Check if this is a for loop
      # @return [Boolean]
      def for_statement?
        %w[for_statement c_style_for_statement].include?(@node.type.to_s)
      end

      # Check if this is a while loop
      # @return [Boolean]
      def while_statement?
        @node.type.to_s == 'while_statement'
      end

      # Check if this is a case statement
      # @return [Boolean]
      def case_statement?
        @node.type.to_s == 'case_statement'
      end

      # Check if this is a command
      # @return [Boolean]
      def command?
        @node.type.to_s == 'command'
      end

      # Check if this is a pipeline
      # @return [Boolean]
      def pipeline?
        @node.type.to_s == 'pipeline'
      end

      # Check if this is a comment
      # @return [Boolean]
      def comment?
        @node.type.to_s == 'comment'
      end

      # Get the function name if this is a function definition
      # @return [String, nil]
      def function_name
        return unless function_definition?

        # In bash tree-sitter, function name is in a 'name' or 'word' child
        name_node = find_child_by_type('word') || find_child_by_field('name')
        node_text(name_node) if name_node
      end

      # Get the variable name if this is a variable assignment
      # @return [String, nil]
      def variable_name
        return unless variable_assignment?

        # In bash tree-sitter, variable name is a child of type 'variable_name'
        name_node = find_child_by_type('variable_name')
        node_text(name_node) if name_node
      end

      # Get the command name if this is a command
      # @return [String, nil]
      def command_name
        return unless command?

        # First child that is a word or simple_expansion
        @node.each do |child|
          next if %w[comment file_redirect heredoc_redirect].include?(child.type.to_s)

          return node_text(child) if %w[word command_name].include?(child.type.to_s)
        end
        nil
      end

      def start_byte = node.start_byte
      def end_byte = node.end_byte
      def source_text = @source.byteslice(start_byte...end_byte).to_s

      def semantic_tree
        semantic_node(node)
      end

      def heredoc?
        descendant_type?(node, %w[heredoc_redirect heredoc_body])
      end

      # Find a child by field name
      # @param field_name [String] Field name to look for
      # @return [TreeSitter::Node, nil]
      def find_child_by_field(field_name)
        return unless @node.respond_to?(:child_by_field_name)

        @node.child_by_field_name(field_name)
      end

      # Find a child by type
      # @param type_name [String] Type name to look for
      # @return [TreeSitter::Node, nil]
      def find_child_by_type(type_name)
        return unless @node.respond_to?(:each)

        @node.each do |child|
          return child if child.type.to_s == type_name
        end
        nil
      end

      protected

      # Override wrap_child to use Bash::Merge::NodeWrapper
      def wrap_child(child)
        NodeWrapper.new(child, lines: @lines, source: @source)
      end

      def compute_signature(node)
        node_type = node.type.to_s

        case node_type
        when 'program'
          # Root node - signature based on direct children structure
          child_types = []
          node.each { |child| child_types << child.type.to_s unless child.type.to_s == 'comment' }
          [:program, child_types.length]
        when 'function_definition'
          # Functions are identified by their name
          name = function_name
          [:function_definition, name]
        when 'variable_assignment'
          # Variable assignments are identified by variable name
          name = variable_name
          [:variable_assignment, name]
        when 'command'
          # Commands identified by their command name and arguments.
          # Arguments are included so that `PATH_add exe` and `PATH_add bin`
          # get distinct signatures, while `echo "hello"` repeated twice gets
          # the same signature — the resolver handles positional matching for
          # nodes with identical signatures.
          name = command_name
          args = extract_command_arguments(node)
          [:command, name, args, extract_command_signature_context(node)]
        when 'if_statement'
          # If statements identified by their condition pattern
          condition = extract_condition_pattern(node)
          [:if_statement, condition]
        when 'for_statement', 'c_style_for_statement'
          # For loops identified by their loop variable
          var = extract_loop_variable(node)
          [:for_statement, var]
        when 'while_statement'
          # While loops identified by condition
          condition = extract_condition_pattern(node)
          [:while_statement, condition]
        when 'case_statement'
          # Case statements identified by the expression being matched
          expr = extract_case_expression(node)
          [:case_statement, expr]
        when 'pipeline'
          # Pipelines identified by command names in order
          commands = extract_pipeline_commands(node)
          [:pipeline, commands]
        when 'comment'
          # Comments identified by their content
          [:comment, node_text(node).strip]
        else
          # Generic fallback - type and first few chars of content
          content_preview = node_text(node).slice(0, 50).strip
          [node_type.to_sym, content_preview]
        end
      end

      private

      def semantic_node(value)
        children = value.children
        return [value.type.to_s, @source.byteslice(value.start_byte...value.end_byte).to_s] if children.empty?

        [value.type.to_s, children.select(&:named?).map { |child| semantic_node(child) }]
      end

      def descendant_type?(value, types)
        return true if types.include?(value.type.to_s)

        value.children.any? { |child| descendant_type?(child, types) }
      end

      def extract_command_signature_context(node)
        # Extract additional context like redirections
        redirections = []
        node.each do |child|
          redirections << child.type.to_s if child.type.to_s.include?('redirect')
        end
        redirections.empty? ? nil : redirections.sort
      end

      # Extract argument words from a command node.
      # Returns the argument text values (everything after the command name).
      #
      # @param node [Object] A tree-sitter command node
      # @return [Array<String>, nil] Argument values, or nil if none
      def extract_command_arguments(node)
        args = []
        found_command_name = false
        node.each do |child|
          type_s = child.type.to_s
          # Skip comments and redirections
          next if %w[comment file_redirect heredoc_redirect].include?(type_s)

          if !found_command_name && %w[word command_name].include?(type_s)
            # First word/command_name is the command itself, skip it
            found_command_name = true
            next
          end

          # Everything after the command name is an argument
          args << node_text(child) if found_command_name
        end
        args.empty? ? nil : args
      end

      def extract_condition_pattern(node)
        # Try to extract the test/condition from if/while statements
        # Look for test_command, compound_statement, etc.
        node.each do |child|
          return node_text(child).slice(0, 100).strip if %w[test_command bracket_command].include?(child.type.to_s)
        end
        nil
      end

      def extract_loop_variable(node)
        # Extract the loop variable from for statements
        var_node = node.each.find { |child| child.type.to_s == 'variable_name' }
        node_text(var_node) if var_node
      end

      def extract_case_expression(node)
        # Extract the expression being matched in a case statement
        node.each do |child|
          return node_text(child).slice(0, 50).strip if %w[word variable_name].include?(child.type.to_s)
        end
        nil
      end

      def extract_pipeline_commands(node)
        # Extract command names from a pipeline
        commands = []
        node.each do |child|
          next unless child.type.to_s == 'command'

          wrapper = NodeWrapper.new(child, lines: @lines, source: @source)
          cmd_name = wrapper.command_name
          commands << cmd_name if cmd_name
        end
        commands
      end
    end
  end
end
