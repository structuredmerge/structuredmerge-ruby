# frozen_string_literal: true

# The aggregate suite at the monorepo root loads every member from gems/*/lib. Member
# .simplecov files only cover lib/**, so without a root .simplecov SimpleCov tracks 0 files
# and every release changelog records "0.00% -- 0/0 lines in 0 files" (it did, 7.1.6-7.1.19).
RSpec.describe 'family root coverage tracking' do
  let(:root_simplecov) { File.expand_path('../../../../.simplecov', __dir__) }

  it 'tracks every member lib directory from the family root' do
    skip 'monorepo root .simplecov not present (standalone gem checkout)' unless File.file?(File.expand_path('../../../../.kettle-family.yml', __dir__))

    expect(File.file?(root_simplecov)).to be(true), 'add a root .simplecov that covers gems/*/lib/**/*.rb'
    expect(File.read(root_simplecov)).to include('gems/*/lib/**/*.rb')
  end
end
