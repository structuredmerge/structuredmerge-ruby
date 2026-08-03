# frozen_string_literal: true

require_relative 'zip/merge'
require 'version_gem'
require_relative 'zip/merge/version'

Zip::Merge::Version.class_eval do
  extend VersionGem::Basic
end
