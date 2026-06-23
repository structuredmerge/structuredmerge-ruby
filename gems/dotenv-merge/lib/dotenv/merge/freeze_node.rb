# frozen_string_literal: true

module Dotenv
  module Merge
    # Represents a freeze block in a dotenv file.
    # Freeze blocks protect sections from being overwritten during merge.
    #
    # @example Freeze block in dotenv file
    #   # dotenv-merge:freeze Custom API settings
    #   API_KEY=my_custom_key
    #   API_SECRET=my_custom_secret
    #   # dotenv-merge:unfreeze
    #
    # @see Ast::Merge::FreezeNodeBase
    class FreezeNode < Ast::Merge::FreezeNodeBase
      # Make InvalidStructureError available as Dotenv::Merge::FreezeNode::InvalidStructureError
      InvalidStructureError = Ast::Merge::FreezeNodeBase::InvalidStructureError

      # Make Location available as Dotenv::Merge::FreezeNode::Location
      Location = Ast::Merge::FreezeNodeBase::Location

      # Initialize a new FreezeNode for dotenv
      #
      # @param start_line [Integer] Starting line number (1-indexed)
      # @param end_line [Integer] Ending line number (1-indexed)
      # @param analysis [FileAnalysis] The file analysis
      # @param reason [String, nil] Optional reason from freeze marker
      def initialize(start_line:, end_line:, analysis:, reason: nil)
        super(
          start_line: start_line,
          end_line: end_line,
          analysis: analysis,
          reason: reason
        )
      end

      # Get the content of this freeze block
      # @return [String] The content lines joined
      def content
        @lines&.map { |l| l.respond_to?(:raw) ? l.raw : l.to_s }&.join("\n")
      end

      # Get a signature for this freeze block
      # @return [Array] Signature based on normalized content
      def signature
        [:FreezeNode, content.gsub(/\s+/, ' ').strip]
      end

      # Get environment variable lines within the freeze block
      # @return [Array<EnvLine>] Assignment lines only
      def env_lines
        @lines&.select { |l| l.respond_to?(:assignment?) && l.assignment? } || []
      end

      # String representation for debugging
      # @return [String]
      def inspect
        "#<#{self.class.name} lines=#{@start_line}..#{@end_line} env_vars=#{env_lines.size}>"
      end
    end
  end
end
