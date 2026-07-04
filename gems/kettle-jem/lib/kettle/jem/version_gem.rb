# frozen_string_literal: true

require "version_gem"
require_relative "version"

Kettle::Jem::Version.class_eval do
  extend VersionGem::Basic
end
