# frozen_string_literal: true

require_relative 'json/merge'
require 'version_gem'
require_relative 'json/merge/version'

Json::Merge::Version.class_eval do
  extend VersionGem::Basic
end
