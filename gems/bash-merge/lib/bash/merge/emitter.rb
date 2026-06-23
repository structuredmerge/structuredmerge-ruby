# frozen_string_literal: true

module Bash
  module Merge
    # Custom Bash emitter that preserves comments and formatting.
    # This class provides utilities for emitting Bash while maintaining
    # the original structure, comments, and style choices.
    #
    # Inherits common emitter functionality from Ast::Merge::EmitterBase.
    #
    # @example Basic usage
    #   emitter = Emitter.new
    #   emitter.emit_comment("This is a comment")
    #   emitter.emit_line("echo 'hello'")
    class Emitter < Ast::Merge::EmitterBase
      include Ast::Merge::EmitterLineMetadataSupport

      # Initialize subclass-specific state
      def initialize_subclass_state(**_options)
        initialize_line_metadata_state
      end

      # Clear subclass-specific state
      def clear_subclass_state
        clear_line_metadata_state
      end

      def emit_blank_line
        append_line('')
      end

      # Emit a tracked comment from CommentTracker
      # @param comment [Hash] Comment with :text, :indent
      def emit_tracked_comment(comment)
        indent = ' ' * (comment[:indent] || 0)
        append_line("#{indent}# #{comment[:text]}")
      end

      # Emit a comment line
      #
      # @param text [String] Comment text (without #)
      # @param inline [Boolean] Whether this is an inline comment
      def emit_comment(text, inline: false)
        if inline
          # Inline comments are appended to the last line
          return if @lines.empty?

          @lines[-1] = "#{@lines[-1]} # #{text}"
        else
          append_line("#{current_indent}# #{text}")
        end
      end

      # Emit a shebang line
      #
      # @param interpreter [String] Interpreter path (e.g., "/bin/bash")
      def emit_shebang(interpreter = '/bin/bash', metadata: nil)
        append_line("#!#{interpreter}", metadata)
      end

      # Emit a variable assignment
      #
      # @param name [String] Variable name
      # @param value [String] Variable value
      # @param export [Boolean] Whether to export the variable
      # @param inline_comment [String, nil] Optional inline comment
      def emit_variable_assignment(name, value, export: false, inline_comment: nil, metadata: nil)
        prefix = export ? 'export ' : ''
        line = "#{current_indent}#{prefix}#{name}=#{value}"
        line += " # #{inline_comment}" if inline_comment
        append_line(line, metadata)
      end

      # Emit a function definition start
      #
      # @param name [String] Function name
      def emit_function_start(name, metadata: nil)
        append_line("#{current_indent}#{name}() {", metadata)
        indent
      end

      # Emit a function definition end
      def emit_function_end
        dedent
        append_line("#{current_indent}}")
      end

      # Emit an if statement start
      #
      # @param condition [String] Condition expression
      def emit_if_start(condition, metadata: nil)
        append_line("#{current_indent}if #{condition}; then", metadata)
        indent
      end

      # Emit an elif clause
      #
      # @param condition [String] Condition expression
      def emit_elif(condition, metadata: nil)
        dedent
        append_line("#{current_indent}elif #{condition}; then", metadata)
        indent
      end

      # Emit an else clause
      def emit_else
        dedent
        append_line("#{current_indent}else")
        indent
      end

      # Emit an if statement end
      def emit_fi
        dedent
        append_line("#{current_indent}fi")
      end

      # Emit a for loop start
      #
      # @param var [String] Loop variable name
      # @param items [String] Items to iterate over
      def emit_for_start(var, items, metadata: nil)
        append_line("#{current_indent}for #{var} in #{items}; do", metadata)
        indent
      end

      # Emit a for/while loop end
      def emit_done
        dedent
        append_line("#{current_indent}done")
      end

      # Emit a while loop start
      #
      # @param condition [String] Condition expression
      def emit_while_start(condition, metadata: nil)
        append_line("#{current_indent}while #{condition}; do", metadata)
        indent
      end

      # Emit a case statement start
      #
      # @param expression [String] Expression to match
      def emit_case_start(expression, metadata: nil)
        append_line("#{current_indent}case #{expression} in", metadata)
        indent
      end

      # Emit a case pattern
      #
      # @param pattern [String] Pattern to match
      def emit_case_pattern(pattern, metadata: nil)
        append_line("#{current_indent}#{pattern})", metadata)
        indent
      end

      # Emit a case pattern terminator
      def emit_case_pattern_end
        dedent
        append_line("#{current_indent};;")
      end

      # Emit a case statement end
      def emit_esac
        dedent
        append_line("#{current_indent}esac")
      end

      # Emit a raw line of code
      #
      # @param line [String] Line to emit
      def emit_line(line, metadata: nil)
        append_line("#{current_indent}#{line}", metadata)
      end

      def emit_raw_lines(raw_lines, metadata: nil)
        raw_lines.each_with_index do |line, idx|
          append_line(line.chomp, expanded_line_metadata(metadata, idx))
        end
      end

      # Get the output as a Bash string
      #
      # @return [String]
      def to_bash
        to_s
      end
    end
  end
end
