# frozen_string_literal: true

require_relative 'typescript/merge'
require 'version_gem'
require_relative 'typescript/merge/version'

TypeScript::Merge::Version.class_eval do
  extend VersionGem::Basic
end
