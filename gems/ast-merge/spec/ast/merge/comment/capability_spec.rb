# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::Capability do
  describe 'level constructors' do
    it 'builds a native_full capability' do
      capability = described_class.native_full

      expect(capability.level).to eq(:native_full)
      expect(capability).to be_native_full
      expect(capability).to be_native
      expect(capability).to be_available
      expect(capability).to have_attributes(attachment_hints?: true, comment_nodes?: true)
    end

    it 'builds a native_partial capability' do
      capability = described_class.native_partial(comment_nodes: true)

      expect(capability.level).to eq(:native_partial)
      expect(capability).to be_native_partial
      expect(capability).to be_native
      expect(capability).to be_available
      expect(capability).to have_attributes(attachment_hints?: false, comment_nodes?: true)
    end

    it 'builds a native_comment_nodes_only capability' do
      capability = described_class.native_comment_nodes_only

      expect(capability.level).to eq(:native_comment_nodes_only)
      expect(capability).to be_native_comment_nodes_only
      expect(capability).to be_native
      expect(capability).to be_available
      expect(capability).to have_attributes(attachment_hints?: false, comment_nodes?: true)
    end

    it 'builds a source_augmented capability' do
      capability = described_class.source_augmented

      expect(capability.level).to eq(:source_augmented)
      expect(capability).to be_source_augmented
      expect(capability).to be_augmented
      expect(capability).to be_available
      expect(capability).not_to be_native
      expect(capability).to have_attributes(attachment_hints?: false, comment_nodes?: false)
    end

    it 'builds a none capability' do
      capability = described_class.none

      expect(capability.level).to eq(:none)
      expect(capability).to be_none
      expect(capability).not_to be_available
      expect(capability).not_to be_native
      expect(capability).not_to be_augmented
    end
  end

  describe '#initialize' do
    it 'accepts string levels' do
      capability = described_class.new(level: 'native_partial')

      expect(capability.level).to eq(:native_partial)
    end

    it 'stores additional details' do
      capability = described_class.new(
        level: :source_augmented,
        source: :comment_tracker,
        attachment_hints: true,
        parser: :psych
      )

      expect(capability.details).to eq(
        source: :comment_tracker,
        attachment_hints: true,
        parser: :psych
      )
      expect(capability.attachment_hints?).to be(true)
    end

    it 'raises for unknown levels' do
      expect do
        described_class.new(level: :mystery_mode)
      end.to raise_error(ArgumentError, /Unknown comment capability level/)
    end
  end

  describe '#to_h' do
    it 'returns a normalized hash view' do
      capability = described_class.native_partial(comment_nodes: true, parser: :psych)

      expect(capability.to_h).to eq(
        level: :native_partial,
        details: { comment_nodes: true, parser: :psych },
        native: true,
        augmented: false,
        available: true,
        attachment_hints: false,
        comment_nodes: true
      )
    end
  end

  describe '#inspect' do
    it 'includes the level for debugging' do
      capability = described_class.source_augmented(source: :line_scan)

      expect(capability.inspect).to include('source_augmented')
      expect(capability.inspect).to include('line_scan')
    end
  end
end
