# frozen_string_literal: true

require 'ast/crispr/markdown/markly'
require 'version_gem'
require_relative 'ast/crispr/markdown/markly/version'

Ast::Crispr::Markdown::Markly::Version.class_eval do
  extend VersionGem::Basic
end
