# frozen_string_literal: true

RSpec.describe 'Ast::Crispr provider architecture' do
  let(:repo_root) { Pathname(__dir__).join('..', '..', '..').expand_path }
  let(:provider_lib_files) { repo_root.join('gems').glob('ast-crispr-*/lib/**/*.rb') }

  let(:forbidden_patterns) do
    {
      /(?<![:\w])Prism\.parse\b/ => 'delegate Ruby/Prism analysis to prism-merge',
      /(?<![:\w])Markly\.parse\b/ => 'delegate Markdown/Markly analysis to markly-merge',
      /(?<![:\w])Commonmarker\.parse\b/ => 'delegate Markdown/CommonMarker analysis to commonmarker-merge',
      /Kramdown::Document\.new\b/ => 'delegate Markdown/Kramdown analysis to kramdown-merge',
      /(?<![:\w])JSON\.parse\b/ => 'delegate JSON analysis to json-merge',
      /(?<![:\w])YAML\.(safe_load|load|parse)\b/ => 'delegate YAML analysis to yaml-merge or psych-merge',
      /\bTomlRB\b/ => 'delegate TOML analysis to toml-merge or a TOML provider merge gem',
      /\bTOML::Parslet\b/ => 'delegate TOML analysis to toml-merge or parslet-toml-merge',
      /TreeHaver\.register_language\b/ => 'register TreeHaver backends in merge gems',
      /TreeHaver::BackendRegistry\.register\b/ => 'register TreeHaver backends in merge gems',
      /TreeHaver\.parser_for\b/ => 'delegate parsing and analysis to merge gems'
    }
  end

  it 'keeps provider gems above merge-gem analysis instead of parser APIs' do
    violations = provider_lib_files.flat_map do |path|
      content = path.read
      relative_path = path.relative_path_from(repo_root)

      forbidden_patterns.filter_map do |pattern, guidance|
        next unless content.match?(pattern)

        "#{relative_path}: matches #{pattern.inspect}; #{guidance}"
      end
    end

    expect(violations).to be_empty, violations.join("\n")
  end
end
