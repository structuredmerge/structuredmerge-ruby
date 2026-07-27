# frozen_string_literal: true

require 'prism/merge'
require 'ast/merge/rspec/shared_examples'

RSpec.describe 'Prism reproducible merge' do
  let(:fixtures_path) { File.expand_path('fixtures/reproducible', __dir__) }
  let(:merger_class) { Prism::Merge::SmartMerger }
  let(:file_extension) { 'rb' }

  describe Prism::Merge::RecursiveMergePolicy do
    let(:merger) { instance_double(Prism::Merge::SmartMerger) }
    let(:policy) { described_class.new(merger: merger) }

    it 'treats nil block bodies as non-mergeable instead of failing' do
      result = Prism.parse("RSpec.describe Foo do\nend\n")
      body = result.value.statements.body.first.block.body

      expect(body).to be_nil
      expect(policy.body_has_mergeable_statements?(body)).to be(false)
    end
  end

  describe 'basic merge scenarios (destination wins by default)' do
    context 'when a method is removed in destination' do
      it_behaves_like 'a reproducible merge', '01_method_removed'
    end

    context 'when a method is added in destination' do
      it_behaves_like 'a reproducible merge', '02_method_added'
    end

    context 'when an implementation is changed in destination' do
      it_behaves_like 'a reproducible merge', '03_implementation_changed'
    end
  end

  describe 'gemspec merge with trailing comment block (regression)' do
    context 'when template has trailing comments after last matched node that also appear as leading comments of a dest-only node' do
      it_behaves_like 'a reproducible merge', '05_gemspec_orphan_duplication', {
        preference: :template,
        add_template_only_nodes: true
      }
    end
  end

  describe 'gemspec merge with freeze blocks (regression)' do
    let(:fixture_dir) { File.join(fixtures_path, '04_gemspec_duplication') }
    let(:template_fixture) { File.read(File.join(fixture_dir, 'template.rb')) }
    let(:dest_fixture) { File.read(File.join(fixture_dir, 'destination.rb')) }

    it 'does not duplicate freeze blocks when template and dest have identical freeze block' do
      merger = Prism::Merge::SmartMerger.new(
        template_fixture,
        dest_fixture,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: 'kettle-dev'
      )
      merged = merger.merge

      freeze_count = merged.scan(/#\s*kettle-dev:freeze/i).length
      expect(freeze_count).to eq(2), "Expected 2 freeze blocks, got #{freeze_count}"
      expect(merged).to include('NOTE: This gem has "runtime" dependencies')
    end
  end

  describe 'Ruby merge with template leading comments on matched destination nodes' do
    context 'when destination kept the matched call and template added an adjacent comment' do
      it_behaves_like 'a reproducible merge', '06_matched_destination_template_leading_comment', {
        preference: :template,
        add_template_only_nodes: true
      }
    end
  end
end
