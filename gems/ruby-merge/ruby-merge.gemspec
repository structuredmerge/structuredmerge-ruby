# frozen_string_literal: true

require_relative "lib/ruby/merge/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-merge"
  spec.version = Ruby::Merge::VERSION
  spec.authors = ["Structured Merge Contributors"]
  spec.email = ["opensource@structuredmerge.dev"]
  spec.summary = "Structured Merge Ruby substrate analysis for Ruby"
  spec.description = "Tree-sitter-backed Ruby family substrate for Structured Merge."
  spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
  spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
  spec.required_ruby_version = ">= 4.0.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  root = __dir__
  spec.files = Dir.chdir(root) { Dir.glob("lib/**/*", File::FNM_DOTMATCH).reject { |path| File.directory?(path) } }
  spec.require_paths = ["lib"]
  spec.add_dependency "ast-merge", "= #{Ruby::Merge::VERSION}"
  spec.add_dependency "tree_haver", "= #{Ruby::Merge::VERSION}"
end
