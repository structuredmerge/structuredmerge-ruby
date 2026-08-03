# frozen_string_literal: true

require_relative 'prism/merge'
require 'version_gem'
require_relative 'prism/merge/version'

Prism::Merge::Version.class_eval do
  extend VersionGem::Basic
end
