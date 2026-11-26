# frozen_string_literal: true

require 'yaml'

# The aggregate suite at the monorepo root loads every member from gems/*/lib. Member
# .simplecov files only cover lib/**, so without a root .simplecov SimpleCov tracks 0 files
# and every release changelog records "0.00% -- 0/0 lines in 0 files" (it did, 7.1.6-7.1.19).
RSpec.describe 'family root coverage tracking' do
  let(:family_root) { File.expand_path('../../../..', __dir__) }
  let(:root_simplecov) { File.join(family_root, '.simplecov') }

  it 'tracks every member lib directory from the family root' do
    family_config = File.join(family_root, '.kettle-family.yml')
    skip 'not a monorepo family checkout' unless File.file?(family_config)

    expect(File.file?(root_simplecov)).to be(true), 'add a root .simplecov that covers gems/*/lib/**/*.rb'
    expect(File.read(root_simplecov)).to include('gems/*/lib/**/*.rb')
  end

  it 'defines the enforced family coverage floor where CI and the release changelog both read it' do
    family_config = File.join(family_root, '.kettle-family.yml')
    skip 'not a monorepo family checkout' unless File.file?(family_config)

    workflow = File.join(family_root, '.github', 'workflows', 'coverage.yml')
    expect(File.file?(workflow)).to be(true), 'add .github/workflows/coverage.yml with the K_SOUP_COV_MIN_* floor'
    env = YAML.safe_load_file(workflow, permitted_classes: [], aliases: false).fetch('env')

    expect(env.fetch('K_SOUP_COV_MIN_HARD')).to eq('true')
    expect(env.fetch('K_SOUP_COV_MIN_LINE').to_f).to be > 0
    expect(env.fetch('K_SOUP_COV_MIN_BRANCH').to_f).to be > 0
  end
end
