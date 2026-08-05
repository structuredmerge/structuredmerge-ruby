# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'TreeHaver backend contracts' do
  cases = [
    ['bash-merge', Bash::Merge, :available_bash_backends, :bash, "echo hello\n"],
    ['commonmarker-merge', Commonmarker::Merge, :available_markdown_backends, :markdown, "# Title\n"],
    ['go-merge', Go::Merge, :available_go_backends, :go, "package main\n"],
    ['json-merge', Json::Merge, :available_json_backends, :json, "{\"a\":1}\n"],
    ['kramdown-merge', Kramdown::Merge, :available_markdown_backends, :markdown, "# Title\n"],
    ['markly-merge', Markly::Merge, :available_markdown_backends, :markdown, "# Title\n"],
    ['prism-merge', Prism::Merge, :available_ruby_backends, :ruby, "def a; end\n"],
    ['psych-merge', Psych::Merge, :available_yaml_backends, :yaml, "a: 1\n"],
    ['rbs-merge', Rbs::Merge, :available_rbs_backends, :rbs, "class A\nend\n"],
    ['ruby-merge', Ruby::Merge, :available_ruby_backends, :ruby, "def a; end\n"],
    ['rust-merge', Rust::Merge, :available_rust_backends, :rust, "fn main() {}\n"],
    ['toml-merge', Toml::Merge, :available_toml_backends, :toml, "a = 1\n"],
    ['typescript-merge', TypeScript::Merge, :available_type_script_backends, :typescript, "const a = 1;\n"],
    ['yaml-merge', Yaml::Merge, :available_yaml_backends, :yaml, "a: 1\n"]
  ]

  cases.each do |gem_name, merge_module, backend_method, language, source|
    describe gem_name do
      merge_module.public_send(:register_backend!) if merge_module.respond_to?(:register_backend!)

      merge_module.public_send(backend_method).each do |backend_ref|
        include_examples(
          'Ast::Merge::TreeHaverBackendContract',
          language: language,
          backend_id: backend_ref.id,
          source: source
        )
      end
    end
  end
end
