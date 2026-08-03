# frozen_string_literal: true

require 'binary/merge'
require 'version_gem'
require_relative 'binary/merge/version'

Binary::Merge::Version.class_eval do
  extend VersionGem::Basic
end
