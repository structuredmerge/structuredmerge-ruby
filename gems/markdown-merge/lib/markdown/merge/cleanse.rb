# frozen_string_literal: true

module Markdown
  module Merge
    # Namespace for document cleansing/repair utilities.
    #
    # The Cleanse module contains parsers and fixers for repairing malformed
    # Markdown documents, particularly those affected by previous bugs in
    # ast-merge or other merge tools.
    #
    # @example Fix condensed link reference definitions
    #   content = File.read("README.md")
    #   parser = Markdown::Merge::Cleanse::CondensedLinkRefs.new(content)
    #   if parser.condensed?
    #     File.write("README.md", parser.expand)
    #   end
    #
    # @example Fix code fence spacing issues
    #   content = File.read("README.md")
    #   parser = Markdown::Merge::Cleanse::CodeFenceSpacing.new(content)
    #   if parser.malformed?
    #     File.write("README.md", parser.fix)
    #   end
    #
    # @example Fix block element spacing issues
    #   content = File.read("README.md")
    #   parser = Markdown::Merge::Cleanse::BlockSpacing.new(content)
    #   if parser.malformed?
    #     File.write("README.md", parser.fix)
    #   end
    #
    # @see Cleanse::CondensedLinkRefs For fixing condensed link reference definitions
    # @see Cleanse::CodeFenceSpacing For fixing code fence spacing issues
    # @see Cleanse::BlockSpacing For fixing missing blank lines between block elements
    # @api public
    module Cleanse
      autoload :BlockSpacing, 'markdown/merge/cleanse/block_spacing'
      autoload :CodeFenceSpacing, 'markdown/merge/cleanse/code_fence_spacing'
      autoload :CondensedLinkRefs, 'markdown/merge/cleanse/condensed_link_refs'
      autoload :ListMarkerDuplication, 'markdown/merge/cleanse/list_marker_duplication'
      autoload :TemplatingCorruption, 'markdown/merge/cleanse/templating_corruption'
    end
  end
end
