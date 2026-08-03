# frozen_string_literal: true

require_relative 'rust/merge'
require 'version_gem'
require_relative 'rust/merge/version'

Rust::Merge::Version.class_eval do
  extend VersionGem::Basic
end
