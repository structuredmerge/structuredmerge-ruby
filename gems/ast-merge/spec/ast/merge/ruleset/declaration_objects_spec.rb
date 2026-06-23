# frozen_string_literal: true

RSpec.describe 'Ast::Merge::Ruleset declaration objects' do
  describe Ast::Merge::Ruleset::RepairPolicy do
    it 'normalizes the declared handling through the shared healer vocabulary' do
      policy = described_class.new(kind: :comment_ownership_overlap, handling: 'warn')

      expect(policy.to_h).to eq(
        kind: :comment_ownership_overlap,
        handling: :warn,
        metadata: {}
      )
    end
  end

  describe Ast::Merge::Ruleset::LogicalOwnerPolicy do
    it 'stores preserve-if-referenced behavior as a shared runtime hook' do
      policy = described_class.new(kind: 'link_definition', action: 'preserve_if_referenced')

      expect(policy.to_h).to eq(
        kind: :link_definition,
        action: :preserve_if_referenced,
        metadata: {}
      )
      expect(policy.preserve?(referenced: true)).to be(true)
      expect(policy.preserve?(referenced: false)).to be(false)
    end

    it 'stores preserve-always behavior' do
      policy = described_class.new(kind: :anchor, action: :preserve_always)

      expect(policy.preserve?(referenced: true)).to be(true)
      expect(policy.preserve?(referenced: false)).to be(true)
    end
  end

  describe Ast::Merge::Ruleset::SurfaceDeclaration do
    it 'stores a declarative merge-surface selector' do
      declaration = described_class.new(name: 'fenced_code_block', selector: 'language_tag')

      expect(declaration.to_h).to eq(
        name: :fenced_code_block,
        selector: :language_tag,
        metadata: {}
      )
    end
  end

  describe Ast::Merge::Ruleset::DelegationPolicy do
    it 'stores a declarative delegation strategy' do
      policy = described_class.new(surface_name: 'fenced_code_block', strategy: 'by_language')

      expect(policy.to_h).to eq(
        surface_name: :fenced_code_block,
        strategy: :by_language,
        metadata: {}
      )
    end
  end
end
