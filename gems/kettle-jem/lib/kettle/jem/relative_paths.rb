# frozen_string_literal: true

require "pathname"

module Kettle
  module Jem
    # Relativizes a path under a root directory using filesystem identity rather
    # than lexical string comparison.
    #
    # Pathname#relative_path_from is purely lexical, so when the path and the root
    # are two valid spellings of the same directory it walks up past the root and
    # returns a parent-directory escape instead of raising. On hosts where /home
    # is a symlink to /var/home (Fedora Silverblue/Aurora), Dir.mktmpdir and
    # TMPDIR report "/home/..." while `git rev-parse --show-toplevel` reports
    # "/var/home/...". The escape then reaches `git add --`, which fails with
    # "is outside repository at".
    #
    # Both sides are canonicalized before relativizing. File.realpath is safe
    # here, unlike in Kettle::Paths where the result must preserve the caller's
    # spelling because callers stat those paths and spawn processes from that
    # working directory: these values feed only `git add`, and git itself reports
    # the realpath spelling, so the canonical form is the one git expects.
    module RelativePaths
      class << self
        # Returns the path of +path+ relative to +root+, or nil when root is not
        # an ancestor. Never returns an escaping "../../.." path.
        #
        # Falls back to lexical comparison when either side does not exist yet,
        # because generated and planned paths have no filesystem identity.
        #
        # @param path [String, Pathname, nil]
        # @param root [String, Pathname, nil]
        # @return [String, nil]
        def relative_path_under(path, root)
          return nil if blank?(path) || blank?(root)

          absolute = File.expand_path(path.to_s)
          boundary = File.expand_path(root.to_s)
          relative = relativize(absolute, boundary)
          relative.start_with?("..") ? nil : relative
        rescue ArgumentError
          nil
        end

        private

        def relativize(absolute, boundary)
          if File.exist?(absolute) && File.exist?(boundary)
            Pathname(File.realpath(absolute)).relative_path_from(Pathname(File.realpath(boundary))).to_s
          else
            Pathname(absolute).relative_path_from(Pathname(boundary)).to_s
          end
        end

        def blank?(value)
          value.nil? || value.to_s.strip.empty?
        end
      end
    end
  end
end
