# frozen_string_literal: true

require 'ast/merge'
require 'version_gem'
require_relative 'ast/merge/version'

Ast::Merge::Version.class_eval do
  extend VersionGem::Basic
end
