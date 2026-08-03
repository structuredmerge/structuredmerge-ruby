# frozen_string_literal: true

require_relative 'plain/merge'
require 'version_gem'
require_relative 'plain/merge/version'

Plain::Merge::Version.class_eval do
  extend VersionGem::Basic
end
