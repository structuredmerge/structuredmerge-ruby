# frozen_string_literal: true

require_relative 'citrus/toml/merge'
require 'version_gem'
require_relative 'citrus/toml/merge/version'

Citrus::Toml::Merge::Version.class_eval do
  extend VersionGem::Basic
end
