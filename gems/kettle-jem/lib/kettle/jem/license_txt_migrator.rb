# frozen_string_literal: true

module Kettle
  module Jem
    # Recognizes MIT license text and extracts copyright lines from its preamble.
    class LicenseTxtMigrator
      MIT_PHRASES = [
        "permission is hereby granted",
        "without restriction"
      ].freeze

      def initialize(content)
        @content = content.to_s
        @analysis = Ast::Merge::Text::FileAnalysis.new(@content)
      end

      def mit_license?
        text = @analysis.searchable_text.downcase
        MIT_PHRASES.all? { |phrase| text.include?(phrase) }
      end

      def copyright_lines
        lines = @analysis.statements.select { |node| node.is_a?(Ast::Merge::Text::LineNode) }
        boundary = lines.index do |node|
          @analysis.searchable_text(nodes: [node]).downcase.include?("permission is hereby granted")
        end
        lines.first(boundary || lines.length)
          .select { |node| node.content.match?(/copyright/i) }
          .map(&:content)
      end
    end
  end
end
