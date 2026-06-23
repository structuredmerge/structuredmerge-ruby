# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::RegionMergePolicy do
  def build_region(kind, *lines)
    Ast::Merge::Comment::Region.new(
      kind: kind,
      nodes: lines.map.with_index(1) { |text, index| Ast::Merge::Comment::Line.new(text: text, line_number: index) }
    )
  end

  describe '#text_submerge?' do
    it 'allows multiline leading regions with matching ownership kinds' do
      preferred = build_region(:leading, '# docs', '# more docs')
      other = build_region(:leading, '# docs changed', '# more docs')

      policy = described_class.new(preferred_region: preferred, other_region: other)

      expect(policy.text_submerge?).to be(true)
      expect(policy.strategy).to eq(:text_submerge)
    end

    it 'rejects inline regions even when they span multiple lines synthetically' do
      preferred = build_region(:inline, '# inline one', '# inline two')
      other = build_region(:inline, '# inline one changed', '# inline two')

      policy = described_class.new(preferred_region: preferred, other_region: other)

      expect(policy.text_submerge?).to be(false)
      expect(policy.preserve_preferred?).to be(true)
    end

    it 'rejects single-line comment regions' do
      preferred = build_region(:leading, '# docs')
      other = build_region(:leading, '# docs changed')

      policy = described_class.new(preferred_region: preferred, other_region: other)

      expect(policy.text_submerge?).to be(false)
    end

    it 'rejects mismatched ownership kinds' do
      preferred = build_region(:leading, '# docs', '# more docs')
      other = build_region(:trailing, '# docs', '# more docs')

      policy = described_class.new(preferred_region: preferred, other_region: other)

      expect(policy.text_submerge?).to be(false)
    end

    it 'short-circuits to preservation when either region has freeze markers' do
      preferred = build_region(:leading, '# ast-merge:freeze', '# docs')
      other = build_region(:leading, '# docs changed', '# more docs')

      policy = described_class.new(preferred_region: preferred, other_region: other, freeze_token: 'ast-merge')

      expect(policy.freeze_sensitive?).to be(true)
      expect(policy.text_submerge?).to be(false)
      expect(policy.strategy).to eq(:preserve_preferred)
    end

    it 'short-circuits to preservation when the attachment is freeze-sensitive' do
      preferred = build_region(:leading, '# docs', '# more docs')
      other = build_region(:leading, '# docs changed', '# more docs')
      attachment = Ast::Merge::Comment::Attachment.new(
        leading_region: Ast::Merge::Comment::Region.new(
          kind: :leading,
          nodes: [Ast::Merge::Comment::Line.new(text: '# ast-merge:freeze', line_number: 10)]
        )
      )

      policy = described_class.new(
        preferred_region: preferred,
        other_region: other,
        attachment: attachment,
        freeze_token: 'ast-merge'
      )

      expect(policy.freeze_sensitive?).to be(true)
      expect(policy.text_submerge?).to be(false)
    end
  end

  describe '#to_h' do
    it 'exposes the passive decision summary' do
      preferred = build_region(:orphan, '# docs', '# more docs')
      other = build_region(:orphan, '# docs changed', '# more docs')

      policy = described_class.new(preferred_region: preferred, other_region: other, source: :spec)

      expect(policy.to_h).to include(
        strategy: :text_submerge,
        text_submerge: true,
        preserve_preferred: false,
        preferred_kind: :orphan,
        other_kind: :orphan
      )
      expect(policy.to_h[:details][:source]).to eq(:spec)
    end
  end
end
