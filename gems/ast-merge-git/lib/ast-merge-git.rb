# frozen_string_literal: true

require 'ast/merge/git'
require 'version_gem'
require_relative 'ast/merge/git/version'

Ast::Merge::Git::Version.class_eval do
  extend VersionGem::Basic
end
