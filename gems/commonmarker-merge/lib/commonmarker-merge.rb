# frozen_string_literal: true

require_relative 'commonmarker/merge'
require 'version_gem'
require_relative 'commonmarker/merge/version'

Commonmarker::Merge::Version.class_eval do
  extend VersionGem::Basic
end
