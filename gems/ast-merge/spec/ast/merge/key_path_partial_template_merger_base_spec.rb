# frozen_string_literal: true

require 'json'

RSpec.describe Ast::Merge::KeyPathPartialTemplateMergerBase do
  before do
    stub_const('KeyPathFakeEntry', Struct.new(:key_name, :kind, :children, keyword_init: true) do
      def mapping?
        kind == :mapping
      end

      def sequence?
        kind == :sequence
      end

      def scalar?
        kind == :scalar
      end
    end)
    stub_const('KeyPathFakeAnalysis', Struct.new(:valid?, :errors, :statements, keyword_init: true))
    stub_const('FakeSmartMerger', Class.new do
      attr_reader :merge_result

      def initialize(content)
        @content = content
        @merge_result = Struct.new(:content, :stats).new(content, { source: :fake_smart_merger })
      end

      def merge
        @content
      end
    end)
  end

  let(:merger_class) do
    Class.new(described_class) do
      attr_reader :smart_merger_calls

      def initialize(analyses:, parsed_values:, dumped_values:, **kwargs)
        @analyses = analyses
        @parsed_values = parsed_values
        @dumped_values = dumped_values
        @smart_merger_calls = []
        super(**kwargs)
      end

      def create_analysis(content)
        @analyses.fetch(content)
      end

      def child_entries_for(entry, _analysis)
        entry.children || []
      end

      def create_smart_merger(template_content, destination_content)
        @smart_merger_calls << { template_content: template_content, destination_content: destination_content }
        FakeSmartMerger.new('merged-document')
      end

      def parse_content_value(content)
        @parsed_values.fetch(content)
      end

      def dump_content_value(value)
        @dumped_values << value
        JSON.generate(value)
      end

      def deep_merge_content_value(base, overlay)
        return overlay unless base.is_a?(Hash) && overlay.is_a?(Hash)

        base.merge(overlay) do |_key, old_value, new_value|
          deep_merge_content_value(old_value, new_value)
        end
      end
    end
  end

  let(:target_entry) { KeyPathFakeEntry.new(key_name: 'target', kind: :sequence) }
  let(:root_entry) { KeyPathFakeEntry.new(key_name: 'root', kind: :mapping, children: [target_entry]) }
  let(:valid_analysis) { KeyPathFakeAnalysis.new(valid?: true, errors: [], statements: [root_entry]) }
  let(:parsed_values) { {} }
  let(:dumped_values) { [] }

  def build_merger(**overrides)
    merger_class.new(
      analyses: overrides.delete(:analyses) { { 'destination-doc' => valid_analysis } },
      parsed_values: overrides.delete(:parsed_values) { parsed_values },
      dumped_values: dumped_values,
      template: 'template-fragment',
      destination: 'destination-doc',
      key_path: %w[root target],
      **overrides
    )
  end

  describe '#merge' do
    it 'navigates the key path and delegates the full-document merge through the subclass smart merger' do
      parsed = { 'template-fragment' => ['from-template'] }
      merger = build_merger(parsed_values: parsed)

      result = merger.merge

      expect(result.key_path_found?).to be(true)
      expect(result.changed).to be(true)
      expect(result.content).to eq('merged-document')
      expect(result.stats).to eq({ source: :fake_smart_merger })
      expect(merger.smart_merger_calls).to eq([
                                                {
                                                  template_content: '{"root":{"target":["from-template"]}}',
                                                  destination_content: 'destination-doc'
                                                }
                                              ])
    end

    it 'returns the original destination when the target entry is scalar and destination preference wins' do
      scalar_target = KeyPathFakeEntry.new(key_name: 'target', kind: :scalar)
      scalar_root = KeyPathFakeEntry.new(key_name: 'root', kind: :mapping, children: [scalar_target])
      analysis = KeyPathFakeAnalysis.new(valid?: true, errors: [], statements: [scalar_root])
      merger = build_merger(analyses: { 'destination-doc' => analysis }, preference: :destination)

      result = merger.merge

      expect(result.key_path_found?).to be(true)
      expect(result.changed).to be(false)
      expect(result.content).to eq('destination-doc')
      expect(result.stats).to eq({ mode: :keep_destination })
      expect(merger.smart_merger_calls).to be_empty
    end

    it 'adds a missing key path through the shared structured-content helpers when configured' do
      merger = build_merger(
        analyses: { 'destination-doc' => KeyPathFakeAnalysis.new(valid?: true, errors: [], statements: []) },
        parsed_values: {
          'template-fragment' => 'value',
          'destination-doc' => { 'existing' => 'keep' }
        },
        key_path: %w[new nested],
        when_missing: :add
      )

      result = merger.merge

      expect(result.key_path_found?).to be(false)
      expect(result.changed).to be(true)
      expect(result.content).to eq('{"existing":"keep","new":{"nested":"value"}}')
      expect(dumped_values).to eq([
                                    { 'existing' => 'keep', 'new' => { 'nested' => 'value' } }
                                  ])
    end

    it 'returns a parse-failure result when the destination analysis is invalid' do
      invalid_analysis = KeyPathFakeAnalysis.new(valid?: false, errors: ['bad syntax'], statements: [])
      merger = build_merger(analyses: { 'destination-doc' => invalid_analysis })

      result = merger.merge

      expect(result.key_path_found?).to be(false)
      expect(result.changed).to be(false)
      expect(result.content).to eq('destination-doc')
      expect(result.message).to eq('Failed to parse destination: bad syntax')
    end
  end

  describe '#initialize' do
    it 'raises ArgumentError for an empty key path' do
      expect do
        build_merger(key_path: [])
      end.to raise_error(ArgumentError, /key_path cannot be empty/)
    end
  end
end
