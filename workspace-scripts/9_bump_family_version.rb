#!/usr/bin/env ruby
# frozen_string_literal: true

exec(File.expand_path("archive/bump_family_version.rb", __dir__), *ARGV)
