# frozen_string_literal: true

# For technical reasons, if we move to Zeitwerk, this cannot be require_relative.
#   See: https://github.com/fxn/zeitwerk#for_gem_extension
# Hook for other libraries to load this library (e.g. via bundler)
require 'bash/merge'
require 'version_gem'
require_relative 'bash/merge/version'

Bash::Merge::Version.class_eval do
  extend VersionGem::Basic
end
