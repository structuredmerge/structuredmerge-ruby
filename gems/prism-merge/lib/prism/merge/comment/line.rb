# frozen_string_literal: true

module Prism
  module Merge
    module Comment
      # Ruby-specific comment line with magic comment detection.
      #
      # Extends the generic `Ast::Merge::Comment::Line` with Ruby-specific
      # features like detection of magic comments (frozen_string_literal,
      # encoding, etc.).
      #
      # @example
      #   line = Line.new(text: "# frozen_string_literal: true", line_number: 1)
      #   line.magic_comment? #=> true
      #   line.magic_comment_type #=> :frozen_string_literal
      #
      class Line < Ast::Merge::Comment::Line
        MAGIC_COMMENT_PATTERNS = Ruby::Merge::MagicCommentSupport::MAGIC_COMMENT_PATTERNS

        class << self
          def magic_comment_type_for(text)
            Prism::Merge::MagicCommentSupport.magic_comment_type_for_text(text)
          end

          # Build a Line from a +TreeHaver::Backends::Prism::Comment+ instance.
          #
          # @param th_comment [TreeHaver::Backends::Prism::Comment]
          # @param magic_comment_types [Hash{Integer => Symbol}] optional pre-computed
          #   map of line_number => magic_comment_type (avoids duplicate lookups)
          # @return [Prism::Merge::Comment::Line]
          def from_tree_haver(th_comment, magic_comment_types = {})
            line_number = th_comment.location.start_line
            new(
              text: th_comment.text,
              line_number: line_number,
              magic_comment_type: magic_comment_types[line_number]
            )
          end
        end

        # Initialize a new Ruby comment Line.
        #
        # Always uses hash_comment style for Ruby.
        #
        # @param text [String] The full comment text including `#`
        # @param line_number [Integer] The 1-based line number
        def initialize(text:, line_number:, magic_comment_type: nil)
          @magic_comment_type = magic_comment_type
          super(text: text, line_number: line_number, style: :hash_comment)
        end

        # Check if this is a Ruby magic comment.
        #
        # Magic comments are special comments that affect Ruby's behavior:
        # - `# frozen_string_literal: true/false`
        # - `# encoding: UTF-8`
        # - `# coding: UTF-8`
        # - `# warn_indent: true/false`
        # - `# shareable_constant_value: literal/...`
        #
        # == CLASSIFICATION ONLY, NOT PRAGMA RESOLUTION
        #
        # This attribute feeds comment classification and node signatures. It does
        # not decide whether a pragma survives a merge or where it is placed - that
        # is {Prism::Merge::PragmaMerger}, wired in from
        # {Prism::Merge::SmartMerger#apply_pragma_header}. PragmaMerger reads
        # Prism's native ParseResult#magic_comments directly and does not consult
        # this attribute.
        #
        # Do not build pragma retention or placement on top of this. Note also that
        # `magic_comment_type` is populated only for comments in the header prefix,
        # so it is not a reliable test for "is this text a pragma" elsewhere in a
        # file.
        #
        # @return [Boolean] true if this is a magic comment
        def magic_comment?
          !@magic_comment_type.nil?
        end

        # Get the type of magic comment.
        #
        # @return [Symbol, nil] The magic comment type, or nil if not a magic comment
        attr_reader :magic_comment_type

        # Get the value of a magic comment.
        #
        # @return [String, nil] The magic comment value, or nil if not a magic comment
        def magic_comment_value
          return unless magic_comment?

          stripped = content.strip
          stripped.split(':', 2).last&.strip
        end

        # Generate signature for matching.
        #
        # For magic comments, uses the magic comment TYPE as the signature
        # so that `# frozen_string_literal: true` matches `# frozen_string_literal: false`.
        # This allows preference to be applied when both template and dest have
        # the same type of magic comment with different values.
        #
        # For non-magic comments, uses the parent implementation (normalized content).
        #
        # @return [Array] Signature for matching
        def signature
          if magic_comment?
            [:magic_comment, magic_comment_type]
          else
            super
          end
        end

        # @return [String] Human-readable representation
        def inspect
          magic = magic_comment? ? " magic=#{magic_comment_type}" : ''
          "#<Prism::Merge::Comment::Line line=#{line_number}#{magic} #{text.inspect}>"
        end
      end
    end
  end
end
