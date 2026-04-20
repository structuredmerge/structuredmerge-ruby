# frozen_string_literal: true

require_relative "lib/tree_haver/version"

Gem::Specification.new do |spec|
  spec.name = "tree_haver"
  spec.version = TreeHaver::VERSION
  spec.authors = ["Structured Merge Contributors"]
  spec.email = ["opensource@structuredmerge.dev"]

  spec.summary = "Structured Merge parser abstraction and process analysis for Ruby"
  spec.description = "Backend registry, parser request/result contracts, and tree-sitter language-pack integration for Structured Merge."
  spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
  spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  root = __dir__
  spec.files = Dir.chdir(root) do
    Dir.glob("lib/**/*", File::FNM_DOTMATCH).reject { |path| File.directory?(path) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "citrus", "~> 3.0"
  spec.add_dependency "parslet", "~> 2.0"
  spec.add_dependency "tree_sitter_language_pack", "~> 1.6"
end
