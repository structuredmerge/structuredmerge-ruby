# frozen_string_literal: true

module Ast
  module Merge
    module Detector
      # Detects fenced code blocks with a specific language identifier.
      #
      # This detector finds Markdown-style fenced code blocks (using ``` or ~~~)
      # that have a specific language identifier. It can be configured for any
      # language: ruby, json, yaml, mermaid, etc.
      #
      # ## When to Use This Detector
      #
      # **Use FencedCodeBlock when:**
      # - Working with raw Markdown text without parsing to AST
      # - Quick extraction from strings without parser dependencies
      # - Custom text processing requiring line-level precision
      # - Operating on source text directly (e.g., linters, formatters)
      #
      # **Do NOT use FencedCodeBlock when:**
      # - Working with parsed Markdown AST (use native code block nodes instead)
      # - Integrating with markdown-merge's CodeBlockMerger (it uses native nodes)
      # - Using tree_haver's unified Markdown backend API
      #
      # @example Detecting Ruby code blocks
      #   detector = FencedCodeBlock.new("ruby", aliases: ["rb"])
      #   regions = detector.detect_all(markdown_source)
      #
      # @example Using factory methods
      #   detector = FencedCodeBlock.ruby
      #   detector = FencedCodeBlock.yaml
      #   detector = FencedCodeBlock.json
      #
      # @api public
      #
      class FencedCodeBlock < Base
        # @return [String] The primary language identifier
        attr_reader :language

        # @return [Array<String>] Alternative language identifiers
        attr_reader :aliases

        # Creates a new detector for the specified language.
        #
        # @param language [String, Symbol] The language identifier (e.g., "ruby", "json")
        # @param aliases [Array<String, Symbol>] Alternative identifiers (e.g., ["rb"] for ruby)
        def initialize(language, aliases: [])
          super()
          @language = language.to_s.downcase
          @aliases = aliases.map { |a| a.to_s.downcase }
          @all_identifiers = [@language] + @aliases
        end

        # @return [Symbol] The region type (e.g., :ruby_code_block)
        def region_type
          :"#{@language}_code_block"
        end

        # Check if a language identifier matches this detector.
        #
        # @param lang [String] The language identifier to check
        # @return [Boolean] true if the language matches
        def matches_language?(lang)
          @all_identifiers.include?(lang.to_s.downcase)
        end

        # Detects all fenced code blocks with the configured language.
        #
        # @param source [String] The full document content
        # @return [Array<Region>] All detected code blocks, sorted by start_line
        def detect_all(source)
          return [] if source.nil? || source.empty?

          regions = []
          lines = source.lines
          in_block = false
          start_line = nil
          content_lines = []
          current_language = nil
          fence_char = nil
          fence_length = nil
          indent = ''

          lines.each_with_index do |line, idx|
            line_num = idx + 1

            if !in_block
              # Match opening fence: ```lang or ~~~lang (optionally indented)
              match = line.match(/^(\s*)(`{3,}|~{3,})(\w*)\s*$/)
              if match
                indent = match[1] || ''
                fence = match[2]
                lang = match[3].downcase

                if @all_identifiers.include?(lang)
                  in_block = true
                  start_line = line_num
                  content_lines = []
                  current_language = lang
                  fence_char = fence[0]
                  fence_length = fence.length
                end
              end
            elsif line.match?(/^#{Regexp.escape(indent)}#{Regexp.escape(fence_char)}{#{fence_length},}\s*$/)
              # Match closing fence (must use same char, same indent, and at least same length)
              opening_fence = "#{fence_char * fence_length}#{current_language}"
              closing_fence = fence_char * fence_length

              regions << build_region(
                type: region_type,
                content: content_lines.join,
                start_line: start_line,
                end_line: line_num,
                delimiters: [opening_fence, closing_fence],
                metadata: { language: current_language, indent: indent.empty? ? nil : indent }
              )
              in_block = false
              start_line = nil
              content_lines = []
              current_language = nil
              fence_char = nil
              fence_length = nil
              indent = ''
            else
              # Accumulate content lines (strip the indent if present)
              content_lines << if indent.empty?
                                 line
                               else
                                 # Strip the common indent from content lines
                                 line.sub(/^#{Regexp.escape(indent)}/, '')
                               end
            end
          end

          # NOTE: Unclosed blocks are ignored (no region created)
          regions
        end

        # @return [String] A description of this detector
        def inspect
          aliases_str = @aliases.empty? ? '' : " aliases=#{@aliases.inspect}"
          "#<#{self.class.name} language=#{@language}#{aliases_str}>"
        end

        class << self
          # Creates a detector for Ruby code blocks.
          # @return [FencedCodeBlock]
          def ruby
            new('ruby', aliases: ['rb'])
          end

          # Creates a detector for JSON code blocks.
          # @return [FencedCodeBlock]
          def json
            new('json')
          end

          # Creates a detector for YAML code blocks.
          # @return [FencedCodeBlock]
          def yaml
            new('yaml', aliases: ['yml'])
          end

          # Creates a detector for TOML code blocks.
          # @return [FencedCodeBlock]
          def toml
            new('toml')
          end

          # Creates a detector for Mermaid diagram blocks.
          # @return [FencedCodeBlock]
          def mermaid
            new('mermaid')
          end

          # Creates a detector for JavaScript code blocks.
          # @return [FencedCodeBlock]
          def javascript
            new('javascript', aliases: ['js'])
          end

          # Creates a detector for TypeScript code blocks.
          # @return [FencedCodeBlock]
          def typescript
            new('typescript', aliases: ['ts'])
          end

          # Creates a detector for Python code blocks.
          # @return [FencedCodeBlock]
          def python
            new('python', aliases: ['py'])
          end

          # Creates a detector for Bash/Shell code blocks.
          # @return [FencedCodeBlock]
          def bash
            new('bash', aliases: %w[sh shell zsh])
          end

          # Creates a detector for SQL code blocks.
          # @return [FencedCodeBlock]
          def sql
            new('sql')
          end

          # Creates a detector for HTML code blocks.
          # @return [FencedCodeBlock]
          def html
            new('html')
          end

          # Creates a detector for CSS code blocks.
          # @return [FencedCodeBlock]
          def css
            new('css')
          end

          # Creates a detector for Markdown code blocks (nested markdown).
          # @return [FencedCodeBlock]
          def markdown
            new('markdown', aliases: ['md'])
          end
        end
      end
    end
  end
end
