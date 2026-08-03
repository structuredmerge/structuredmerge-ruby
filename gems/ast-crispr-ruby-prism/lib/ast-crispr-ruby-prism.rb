# frozen_string_literal: true

require 'ast/crispr/ruby/prism'
require 'version_gem'
require_relative 'ast/crispr/ruby/prism/version'

Ast::Crispr::Ruby::Prism::Version.class_eval do
  extend VersionGem::Basic
end
