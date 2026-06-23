# frozen_string_literal: true

RSpec.describe Ast::Merge::Healer do
  describe '.normalize_mode' do
    it 'accepts supported modes' do
      expect(described_class.normalize_mode(:heal)).to eq(:heal)
      expect(described_class.normalize_mode('warn')).to eq(:warn)
      expect(described_class.normalize_mode('error')).to eq(:error)
      expect(described_class.normalize_mode(:skip)).to eq(:skip)
    end

    it 'rejects unknown modes' do
      expect do
        described_class.normalize_mode(:mystery)
      end.to raise_error(ArgumentError, /Unknown corruption handling mode/)
    end
  end

  describe '.handle' do
    let(:prefix) { '[fixture]' }

    it 'returns true for heal' do
      expect(
        described_class.handle(mode: :heal, prefix: prefix, kind: :duplicate_block, message: 'healed', warner: lambda { |*|
        })
      ).to be(true)
    end

    it 'warns and returns false for warn' do
      warned = []

      result = described_class.handle(
        mode: :warn,
        prefix: prefix,
        kind: :duplicate_block,
        message: 'warning only',
        warner: ->(msg) { warned << msg }
      )

      expect(result).to be(false)
      expect(warned).to eq(['[fixture] Suspected corruption (duplicate_block): warning only'])
    end

    it 'raises the provided error class for error' do
      custom_error = Class.new(StandardError)

      expect do
        described_class.handle(
          mode: :error,
          prefix: prefix,
          kind: :duplicate_block,
          message: 'boom',
          error_class: custom_error,
          warner: ->(*) {}
        )
      end.to raise_error(custom_error, /\[fixture\] Suspected corruption \(duplicate_block\): boom/)
    end

    it 'returns false for skip' do
      expect(
        described_class.handle(mode: :skip, prefix: prefix, kind: :duplicate_block, message: 'ignored', warner: lambda { |*|
        })
      ).to be(false)
    end
  end

  describe '.filter_items' do
    let(:prefix) { '[fixture]' }
    let(:items) { %w[a keep b] }

    it 'filters matching items for heal' do
      filtered = described_class.filter_items(
        items,
        mode: :heal,
        prefix: prefix,
        kind: :duplicate_block,
        message: 'healed'
      ) { |item| item != 'keep' }

      expect(filtered).to eq(['keep'])
    end

    it 'returns original items for skip' do
      filtered = described_class.filter_items(
        items,
        mode: :skip,
        prefix: prefix,
        kind: :duplicate_block,
        message: 'ignored'
      ) { |item| item != 'keep' }

      expect(filtered).to eq(items)
    end

    it 'warns and returns original items for warn' do
      warned = []

      filtered = described_class.filter_items(
        items,
        mode: :warn,
        prefix: prefix,
        kind: :duplicate_block,
        message: 'warning only',
        warner: ->(msg) { warned << msg }
      ) { |item| item != 'keep' }

      expect(filtered).to eq(items)
      expect(warned).to eq(['[fixture] Suspected corruption (duplicate_block): warning only'])
    end

    it 'raises for error' do
      custom_error = Class.new(StandardError)

      expect do
        described_class.filter_items(
          items,
          mode: :error,
          prefix: prefix,
          kind: :duplicate_block,
          message: 'boom',
          error_class: custom_error,
          warner: ->(*) {}
        ) { |item| item != 'keep' }
      end.to raise_error(custom_error, /\[fixture\] Suspected corruption \(duplicate_block\): boom/)
    end

    it 'calls on_filter for removed items' do
      removed = []

      filtered = described_class.filter_items(
        items,
        mode: :heal,
        prefix: prefix,
        kind: :duplicate_block,
        message: 'healed',
        on_filter: ->(item) { removed << item }
      ) { |item| item != 'keep' }

      expect(filtered).to eq(['keep'])
      expect(removed).to eq(%w[a b])
    end

    it 'leaves clean inputs unchanged under every handling mode' do
      described_class::HANDLINGS.each do |mode|
        filtered = described_class.filter_items(
          items,
          mode: mode,
          prefix: prefix,
          kind: :duplicate_block,
          message: 'clean input',
          warner: ->(*) {}
        ) { |_item| false }

        expect(filtered).to equal(items)
      end
    end

    it 'diverges only at suspected corruption matches' do
      healed = described_class.filter_items(
        items,
        mode: :heal,
        prefix: prefix,
        kind: :duplicate_block,
        message: 'policy divergence'
      ) { |item| item != 'keep' }
      skipped = described_class.filter_items(
        items,
        mode: :skip,
        prefix: prefix,
        kind: :duplicate_block,
        message: 'policy divergence'
      ) { |item| item != 'keep' }

      expect(healed).to eq(['keep'])
      expect(skipped).to equal(items)
    end
  end
end
