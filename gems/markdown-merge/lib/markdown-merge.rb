# frozen_string_literal: true

require_relative 'markdown/merge'
require 'version_gem'
require_relative 'markdown/merge/version'

Markdown::Merge::Version.class_eval do
  extend VersionGem::Basic
end
