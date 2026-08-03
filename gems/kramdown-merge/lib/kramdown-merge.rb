# frozen_string_literal: true

require_relative 'kramdown/merge'
require 'version_gem'
require_relative 'kramdown/merge/version'

Kramdown::Merge::Version.class_eval do
  extend VersionGem::Basic
end
