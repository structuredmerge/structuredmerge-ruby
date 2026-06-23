# frozen_string_literal: true

RSpec.describe Ast::Merge::Ruleset::SupportStyleResolver do
  describe '.call' do
    it 'builds a source-augmented portable-write support style' do
      support_style = described_class.call(
        read: :source_augmented_portable_write,
        source: :fixture_source,
        capability: :full,
        style: :hash_comment
      )

      expect(support_style).to be_source_augmented_portable_write
      expect(support_style.details).to include(
        source: :fixture_source,
        capability: :full,
        style: :hash_comment
      )
    end

    it 'builds a native-read portable-write support style' do
      support_style = described_class.call(
        read: :native_read_portable_write,
        source: :fixture_native,
        capability: :full,
        style: :hash_comment
      )

      expect(support_style).to be_native_read_portable_write
      expect(support_style.details).to include(
        source: :fixture_native,
        capability: :full,
        style: :hash_comment
      )
    end

    it 'builds a native-mutation support style' do
      support_style = described_class.call(
        read: :native_mutation,
        source: :fixture_native,
        capability: :full,
        style: :hash_comment
      )

      expect(support_style).to be_native_mutation
    end

    it 'rejects unknown read strategies' do
      expect do
        described_class.call(
          read: :mystery_strategy,
          source: :fixture_source,
          capability: :full,
          style: :hash_comment
        )
      end.to raise_error(ArgumentError, /Unknown ruleset read strategy/)
    end
  end
end
