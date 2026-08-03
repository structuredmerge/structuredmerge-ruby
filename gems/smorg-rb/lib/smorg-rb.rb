# frozen_string_literal: true

require_relative 'smorg/rb'
require 'version_gem'
require_relative 'smorg/rb/version'

Smorg::RB::Version.class_eval do
  extend VersionGem::Basic
end
