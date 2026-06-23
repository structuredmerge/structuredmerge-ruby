# frozen_string_literal: true

module Markdown
  module Merge
    # Container for document issues found during processing.
    #
    # Collects problems discovered during merge operations, link reference
    # rehydration, whitespace normalization, and other document transformations.
    # Problems are categorized and have severity levels for filtering and reporting.
    #
    # @example Basic usage
    #   problems = DocumentProblems.new
    #   problems.add(:duplicate_link_definition, label: "example", url: "https://example.com")
    #   problems.add(:excessive_whitespace, line: 42, count: 5, severity: :warning)
    #   problems.empty? # => false
    #   problems.count # => 2
    #
    # @example Filtering by category
    #   problems.by_category(:duplicate_link_definition)
    #   # => [{ category: :duplicate_link_definition, label: "example", ... }]
    #
    # @example Filtering by severity
    #   problems.by_severity(:error)
    #   problems.warnings
    #   problems.errors
    #
    class DocumentProblems
      # Problem entry struct
      Problem = Struct.new(:category, :severity, :details, keyword_init: true) do
        def to_h
          { category: category, severity: severity, **details }
        end

        def warning?
          severity == :warning
        end

        def error?
          severity == :error
        end

        def info?
          severity == :info
        end
      end

      # Valid severity levels
      SEVERITIES = %i[info warning error].freeze

      # Valid problem categories
      CATEGORIES = %i[
        duplicate_link_definition
        excessive_whitespace
        link_has_title
        image_has_title
        link_ref_spacing
      ].freeze

      # @return [Array<Problem>] All collected problems
      attr_reader :problems

      def initialize
        @problems = []
      end

      # Add a problem to the collection.
      #
      # @param category [Symbol] Problem category (see CATEGORIES)
      # @param severity [Symbol] Severity level (:info, :warning, :error), default :warning
      # @param details [Hash] Additional details about the problem
      # @return [Problem] The added problem
      def add(category, severity: :warning, **details)
        validate_category!(category)
        validate_severity!(severity)

        problem = Problem.new(category: category, severity: severity, details: details)
        @problems << problem
        problem
      end

      # Get all problems as an array of hashes.
      #
      # @return [Array<Hash>] All problems
      def all
        @problems.map(&:to_h)
      end

      # Get problems by category.
      #
      # @param category [Symbol] Category to filter by
      # @return [Array<Problem>] Problems in that category
      def by_category(category)
        @problems.select { |p| p.category == category }
      end

      # Get problems by severity.
      #
      # @param severity [Symbol] Severity to filter by
      # @return [Array<Problem>] Problems with that severity
      def by_severity(severity)
        @problems.select { |p| p.severity == severity }
      end

      # Get all info-level problems.
      #
      # @return [Array<Problem>] Info problems
      def infos
        by_severity(:info)
      end

      # Get all warning-level problems.
      #
      # @return [Array<Problem>] Warning problems
      def warnings
        by_severity(:warning)
      end

      # Get all error-level problems.
      #
      # @return [Array<Problem>] Error problems
      def errors
        by_severity(:error)
      end

      # Check if there are any problems.
      #
      # @return [Boolean] true if no problems
      def empty?
        @problems.empty?
      end

      # Get the count of problems.
      #
      # @param category [Symbol, nil] Optional category filter
      # @param severity [Symbol, nil] Optional severity filter
      # @return [Integer] Problem count
      def count(category: nil, severity: nil)
        filtered = @problems
        filtered = filtered.select { |p| p.category == category } if category
        filtered = filtered.select { |p| p.severity == severity } if severity
        filtered.size
      end

      # Merge another DocumentProblems into this one.
      #
      # @param other [DocumentProblems] Problems to merge
      # @return [self]
      def merge!(other)
        @problems.concat(other.problems)
        self
      end

      # Clear all problems.
      #
      # @return [self]
      def clear
        @problems.clear
        self
      end

      # Get a summary of problems by category.
      #
      # @return [Hash<Symbol, Integer>] Counts by category
      def summary_by_category
        @problems.group_by(&:category).transform_values(&:size)
      end

      # Get a summary of problems by severity.
      #
      # @return [Hash<Symbol, Integer>] Counts by severity
      def summary_by_severity
        @problems.group_by(&:severity).transform_values(&:size)
      end

      private

      def validate_category!(category)
        return if CATEGORIES.include?(category)

        raise ArgumentError, "Invalid category: #{category}. Valid: #{CATEGORIES.join(', ')}"
      end

      def validate_severity!(severity)
        return if SEVERITIES.include?(severity)

        raise ArgumentError, "Invalid severity: #{severity}. Valid: #{SEVERITIES.join(', ')}"
      end
    end
  end
end
