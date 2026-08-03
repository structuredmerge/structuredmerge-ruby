# frozen_string_literal: true

require_relative 'markly/merge'
require 'version_gem'
require_relative 'markly/merge/version'

Markly::Merge::Version.class_eval do
  extend VersionGem::Basic
end
