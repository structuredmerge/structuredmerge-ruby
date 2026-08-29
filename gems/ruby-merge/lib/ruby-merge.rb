# frozen_string_literal: true

require_relative 'ruby/merge'
require 'version_gem'
require_relative "ruby/merge/version"

Ruby::Merge::Version.class_eval do
  extend VersionGem::Basic
end
