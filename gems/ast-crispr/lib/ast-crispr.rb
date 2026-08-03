# frozen_string_literal: true

require 'ast/crispr'
require 'version_gem'
require_relative 'ast/crispr/version'

Ast::Crispr::Version.class_eval do
  extend VersionGem::Basic
end
