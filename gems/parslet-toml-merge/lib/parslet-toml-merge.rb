# frozen_string_literal: true

require_relative 'parslet/toml/merge'
require 'version_gem'
require_relative 'parslet/toml/merge/version'

Parslet::Toml::Merge::Version.class_eval do
  extend VersionGem::Basic
end
