# frozen_string_literal: true

module Ast
  module Merge
    # Jaccard set-similarity utilities for fuzzy matching of text nodes.
    #
    # Provides token extraction and Jaccard index computation, reusable
    # across format-specific mergers (Markdown lists, TOML blocks, etc.).
    #
    # @example Computing similarity between two strings
    #   include Ast::Merge::JaccardSimilarity
    #
    #   a = extract_tokens("Commit changes to the branch")
    #   b = extract_tokens("Commit your changes")
    #   jaccard(a, b)  # => 0.667
    #
    # @example With custom stopwords
    #   tokens = extract_tokens("the quick brown fox", stopwords: %w[the].to_set)
    #   # => #<Set: {"quick", "brown", "fox"}>
    module JaccardSimilarity
      # Common English stopwords excluded from token matching.
      DEFAULT_STOPWORDS = %w[
        a
        an
        and
        are
        as
        at
        be
        but
        by
        for
        from
        has
        have
        in
        is
        it
        its
        of
        on
        or
        so
        that
        the
        their
        then
        there
        they
        this
        to
        up
        was
        will
        with
      ].to_set.freeze

      # Minimum word length for a token to be considered significant.
      DEFAULT_MIN_TOKEN_LENGTH = 3

      # Extract significant tokens from text for set-based comparison.
      #
      # Extracts words of at least `min_length` characters, lowercased,
      # with stopwords removed.
      #
      # @param text [String] The text to tokenize
      # @param stopwords [Set<String>] Words to exclude (default: DEFAULT_STOPWORDS)
      # @param min_length [Integer] Minimum token length (default: 3)
      # @return [Set<String>] Set of significant lowercase tokens
      def extract_tokens(text, stopwords: DEFAULT_STOPWORDS, min_length: DEFAULT_MIN_TOKEN_LENGTH)
        text.to_s
            .downcase
            .scan(/[[:alpha:]][[:alnum:]_-]{#{min_length - 1},}/)
            .reject { |t| stopwords.include?(t) }
            .to_set
      end

      # Compute Jaccard similarity index between two sets.
      #
      # J(A,B) = |A ∩ B| / |A ∪ B|
      #
      # Returns 0.0 if either set is empty.
      #
      # @param a [Set] First token set
      # @param b [Set] Second token set
      # @return [Float] Similarity score between 0.0 and 1.0
      def jaccard(a, b)
        return 0.0 if a.empty? || b.empty?

        (a & b).size.to_f / (a | b).size
      end

      module_function :extract_tokens, :jaccard
    end
  end
end
