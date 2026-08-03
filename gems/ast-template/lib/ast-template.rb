# frozen_string_literal: true

require 'ast/template'
require 'version_gem'
require_relative 'ast/template/version'

Ast::Template::Version.class_eval do
  extend VersionGem::Basic
end
