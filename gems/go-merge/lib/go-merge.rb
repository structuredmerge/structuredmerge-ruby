# frozen_string_literal: true

require_relative 'go/merge'
require 'version_gem'
require_relative 'go/merge/version'

Go::Merge::Version.class_eval do
  extend VersionGem::Basic
end
