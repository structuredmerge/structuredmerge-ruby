# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::SupportStyle do
  describe 'constructors' do
    it 'builds source-augmented portable-write styles' do
      support_style = described_class.source_augmented_portable_write(
        source: :fixture_source,
        capability: :full,
        style: :hash_comment
      )

      expect(support_style.style).to eq(:source_augmented_portable_write)
      expect(support_style).to be_source_augmented_portable_write
      expect(support_style).to be_portable_write
    end

    it 'builds native-read portable-write styles' do
      support_style = described_class.native_read_portable_write(
        source: :fixture_native,
        capability: :full,
        style: :hash_comment
      )

      expect(support_style.style).to eq(:native_read_portable_write)
      expect(support_style).to be_native_read_portable_write
      expect(support_style).to be_portable_write
    end
  end

  describe '#initialize' do
    it 'rejects old style names' do
      expect do
        described_class.new(
          style: :source_augmented_synthetic,
          details: { source: :fixture_source, capability: :full, style: :hash_comment }
        )
      end.to raise_error(ArgumentError, /Unknown comment support style/)
    end

    it 'accepts portable-write style names' do
      support_style = described_class.new(
        style: :source_augmented_portable_write,
        details: { source: :fixture_source, capability: :full, style: :hash_comment }
      )

      expect(support_style.style).to eq(:source_augmented_portable_write)
    end
  end
end
