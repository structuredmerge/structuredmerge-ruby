# frozen_string_literal: true

RSpec.describe Ast::Merge::SectionTyping do
  describe Ast::Merge::SectionTyping::TypedSection do
    describe '#initialize' do
      subject(:section) do
        described_class.new(
          type: :appraise_block,
          name: 'coverage',
          node: double('Node'),
          metadata: { has_gems: true }
        )
      end

      it 'sets type' do
        expect(section.type).to eq(:appraise_block)
      end

      it 'sets name' do
        expect(section.name).to eq('coverage')
      end

      it 'sets node' do
        expect(section.node).to be_a(RSpec::Mocks::Double)
      end

      it 'sets metadata' do
        expect(section.metadata).to eq({ has_gems: true })
      end
    end

    describe '#normalized_name' do
      it 'handles strings' do
        section = described_class.new(type: :test, name: '  Coverage  ', node: nil, metadata: nil)
        expect(section.normalized_name).to eq('coverage')
      end

      it 'handles symbols' do
        section = described_class.new(type: :test, name: :coverage, node: nil, metadata: nil)
        expect(section.normalized_name).to eq('coverage')
      end

      it 'handles nil' do
        section = described_class.new(type: :test, name: nil, node: nil, metadata: nil)
        expect(section.normalized_name).to eq('')
      end
    end

    describe '#unclassified?' do
      it 'returns true for :unclassified type' do
        section = described_class.new(type: :unclassified, name: :unclassified, node: nil, metadata: nil)
        expect(section.unclassified?).to be true
      end

      it 'returns true for :preamble type' do
        section = described_class.new(type: :preamble, name: :preamble, node: nil, metadata: nil)
        expect(section.unclassified?).to be true
      end

      it 'returns false for other types' do
        section = described_class.new(type: :appraise_block, name: 'test', node: nil, metadata: nil)
        expect(section.unclassified?).to be false
      end
    end
  end

  describe Ast::Merge::SectionTyping::Classifier do
    let(:concrete_classifier_class) do
      Class.new(described_class) do
        def classify(node)
          return unless node.respond_to?(:name) && node.name == :special

          Ast::Merge::SectionTyping::TypedSection.new(
            type: :special_block,
            name: node.id,
            node: node,
            metadata: nil
          )
        end
      end
    end

    let(:classifier) { concrete_classifier_class.new }

    describe '#classify' do
      context 'with base class' do
        it 'raises NotImplementedError' do
          base = described_class.new
          expect { base.classify(double) }.to raise_error(NotImplementedError, /must be implemented/)
        end
      end

      context 'with concrete subclass' do
        it 'returns TypedSection for matching nodes' do
          node = double('Node', name: :special, id: 'test_block')
          result = classifier.classify(node)
          expect(result).to be_a(Ast::Merge::SectionTyping::TypedSection)
          expect(result.name).to eq('test_block')
        end

        it 'returns nil for non-matching nodes' do
          node = double('Node', name: :other)
          expect(classifier.classify(node)).to be_nil
        end
      end
    end

    describe '#classifies?' do
      it 'returns true when classify returns a section' do
        node = double('Node', name: :special, id: 'test')
        expect(classifier.classifies?(node)).to be true
      end

      it 'returns false when classify returns nil' do
        node = double('Node', name: :other)
        expect(classifier.classifies?(node)).to be false
      end
    end

    describe '#classify_all' do
      it 'classifies matching nodes' do
        nodes = [
          double('Node1', name: :special, id: 'block1'),
          double('Node2', name: :special, id: 'block2')
        ]

        sections = classifier.classify_all(nodes)
        expect(sections.length).to eq(2)
        expect(sections.map(&:name)).to eq(%w[block1 block2])
      end

      it 'groups unclassified nodes into unclassified sections' do
        nodes = [
          double('Node1', name: :other),
          double('Node2', name: :other),
          double('Node3', name: :special, id: 'block1')
        ]

        sections = classifier.classify_all(nodes)
        expect(sections.length).to eq(2)
        expect(sections.first.unclassified?).to be true
        expect(sections.first.metadata[:node_count]).to eq(2)
        expect(sections.last.name).to eq('block1')
      end

      it 'handles trailing unclassified nodes' do
        nodes = [
          double('Node1', name: :special, id: 'block1'),
          double('Node2', name: :other)
        ]

        sections = classifier.classify_all(nodes)
        expect(sections.length).to eq(2)
        expect(sections.first.name).to eq('block1')
        expect(sections.last.unclassified?).to be true
      end

      it 'handles all unclassified nodes' do
        nodes = [
          double('Node1', name: :other),
          double('Node2', name: :other)
        ]

        sections = classifier.classify_all(nodes)
        expect(sections.length).to eq(1)
        expect(sections.first.unclassified?).to be true
        expect(sections.first.metadata[:node_count]).to eq(2)
      end

      it 'handles empty input' do
        sections = classifier.classify_all([])
        expect(sections).to eq([])
      end

      it 'unwraps single unclassified node' do
        node = double('Node', name: :other)
        sections = classifier.classify_all([node])
        expect(sections.first.node).to eq(node) # single node, not array
      end
    end
  end

  describe Ast::Merge::SectionTyping::CallableClassifier do
    describe '#initialize' do
      it 'stores the callable' do
        callable = ->(_node) { nil }
        classifier = described_class.new(callable)
        expect(classifier.callable).to eq(callable)
      end
    end

    describe '#classify' do
      it 'delegates to the callable' do
        callable = lambda { |node|
          next nil unless node[:type] == :block

          Ast::Merge::SectionTyping::TypedSection.new(
            type: :block,
            name: node[:name],
            node: node,
            metadata: nil
          )
        }
        classifier = described_class.new(callable)

        result = classifier.classify({ type: :block, name: 'test' })
        expect(result.name).to eq('test')
      end

      it 'returns nil when callable returns nil' do
        callable = ->(_node) { nil }
        classifier = described_class.new(callable)
        expect(classifier.classify({})).to be_nil
      end

      it 'converts Hash return to TypedSection' do
        callable = lambda { |node|
          { type: :block, name: node[:name], node: node, metadata: nil }
        }
        classifier = described_class.new(callable)

        result = classifier.classify({ name: 'converted' })
        expect(result).to be_a(Ast::Merge::SectionTyping::TypedSection)
        expect(result.name).to eq('converted')
      end
    end
  end

  describe Ast::Merge::SectionTyping::CompositeClassifier do # - Using numbered classifiers is clearer here for composite pattern testing
    let(:classifier1) do
      Ast::Merge::SectionTyping::CallableClassifier.new(lambda { |node|
        next nil unless node[:type] == :type_a

        { type: :type_a, name: node[:name], node: node, metadata: nil }
      })
    end

    let(:classifier2) do
      Ast::Merge::SectionTyping::CallableClassifier.new(lambda { |node|
        next nil unless node[:type] == :type_b

        { type: :type_b, name: node[:name], node: node, metadata: nil }
      })
    end

    let(:composite) { described_class.new(classifier1, classifier2) }

    describe '#initialize' do
      it 'stores classifiers' do
        expect(composite.classifiers).to eq([classifier1, classifier2])
      end

      it 'flattens nested arrays' do
        nested = described_class.new([classifier1], [classifier2])
        expect(nested.classifiers).to eq([classifier1, classifier2])
      end
    end

    describe '#classify' do
      it 'returns result from first matching classifier' do
        node = { type: :type_a, name: 'first' }
        result = composite.classify(node)
        expect(result.type).to eq(:type_a)
      end

      it 'tries subsequent classifiers' do
        node = { type: :type_b, name: 'second' }
        result = composite.classify(node)
        expect(result.type).to eq(:type_b)
      end

      it 'returns nil when no classifier matches' do
        node = { type: :unknown, name: 'none' }
        expect(composite.classify(node)).to be_nil
      end
    end
  end

  describe '.merge_sections' do
    let(:template_sections) do
      [
        Ast::Merge::SectionTyping::TypedSection.new(type: :block, name: 'coverage', node: double('T1'), metadata: nil),
        Ast::Merge::SectionTyping::TypedSection.new(type: :block, name: 'style', node: double('T2'), metadata: nil),
        Ast::Merge::SectionTyping::TypedSection.new(type: :block, name: 'template_only', node: double('T3'),
                                                    metadata: nil)
      ]
    end

    let(:dest_sections) do
      [
        Ast::Merge::SectionTyping::TypedSection.new(type: :block, name: 'coverage', node: double('D1'), metadata: nil),
        Ast::Merge::SectionTyping::TypedSection.new(type: :block, name: 'style', node: double('D2'), metadata: nil),
        Ast::Merge::SectionTyping::TypedSection.new(type: :block, name: 'dest_only', node: double('D3'), metadata: nil)
      ]
    end

    context 'with :destination preference' do
      it 'uses destination sections for matches' do
        merged = described_class.merge_sections(template_sections, dest_sections, preference: :destination)
        coverage = merged.find { |s| s.name == 'coverage' }
        expect(coverage.node).to eq(dest_sections[0].node)
      end

      it 'includes destination-only sections' do
        merged = described_class.merge_sections(template_sections, dest_sections, preference: :destination)
        dest_only = merged.find { |s| s.name == 'dest_only' }
        expect(dest_only).not_to be_nil
      end

      it 'excludes template-only sections by default' do
        merged = described_class.merge_sections(template_sections, dest_sections, preference: :destination)
        template_only = merged.find { |s| s.name == 'template_only' }
        expect(template_only).to be_nil
      end
    end

    context 'with :template preference' do
      it 'uses template sections for matches' do
        merged = described_class.merge_sections(template_sections, dest_sections, preference: :template)
        coverage = merged.find { |s| s.name == 'coverage' }
        expect(coverage.node).to eq(template_sections[0].node)
      end
    end

    context 'with add_template_only: true' do
      it 'includes template-only sections' do
        merged = described_class.merge_sections(template_sections, dest_sections, preference: :destination,
                                                                                  add_template_only: true)
        template_only = merged.find { |s| s.name == 'template_only' }
        expect(template_only).not_to be_nil
      end
    end

    context 'with per-section preferences' do
      it 'applies different preferences per section' do
        pref = { :default => :destination, 'style' => :template }
        merged = described_class.merge_sections(template_sections, dest_sections, preference: pref)

        coverage = merged.find { |s| s.name == 'coverage' }
        style = merged.find { |s| s.name == 'style' }

        expect(coverage.node).to eq(dest_sections[0].node) # destination
        expect(style.node).to eq(template_sections[1].node) # template
      end
    end

    context 'with unclassified sections' do
      it 'skips unclassified template sections by default' do
        template_with_unclassified = [
          Ast::Merge::SectionTyping::TypedSection.new(type: :unclassified, name: :unclassified, node: double('U'),
                                                      metadata: nil),
          *template_sections
        ]

        merged = described_class.merge_sections(template_with_unclassified, dest_sections, preference: :destination)
        unclassified = merged.find { |s| s.unclassified? }
        expect(unclassified).to be_nil
      end

      it 'includes unclassified template sections when add_template_only is true' do
        template_with_unclassified = [
          Ast::Merge::SectionTyping::TypedSection.new(type: :unclassified, name: :unclassified, node: double('U'),
                                                      metadata: nil),
          *template_sections
        ]

        merged = described_class.merge_sections(template_with_unclassified, dest_sections, preference: :destination,
                                                                                           add_template_only: true)
        unclassified = merged.find { |s| s.unclassified? }
        expect(unclassified).not_to be_nil
      end
    end
  end

  describe '.preference_for' do
    it 'returns symbol preference directly' do
      expect(described_class.preference_for('any', :template)).to eq(:template)
    end

    it 'returns exact match from hash with string key' do
      pref = { 'coverage' => :template, :default => :destination }
      expect(described_class.preference_for('coverage', pref)).to eq(:template)
    end

    it 'returns exact match from hash with symbol key' do
      pref = { coverage: :template, default: :destination }
      expect(described_class.preference_for('coverage', pref)).to eq(:template)
    end

    it 'normalizes uppercase keys to match lowercase names' do
      pref = { 'COVERAGE' => :template, :default => :destination }
      expect(described_class.preference_for('coverage', pref)).to eq(:template)
    end

    it 'normalizes keys with whitespace' do
      pref = { '  coverage  ' => :template, :default => :destination }
      expect(described_class.preference_for('coverage', pref)).to eq(:template)
    end

    it 'normalizes section name with whitespace to match key' do
      pref = { 'coverage' => :template, :default => :destination }
      expect(described_class.preference_for('  coverage  ', pref)).to eq(:template)
    end

    it 'returns default when no match' do
      pref = { 'other' => :template, :default => :destination }
      expect(described_class.preference_for('coverage', pref)).to eq(:destination)
    end

    it 'defaults to :destination when no default specified' do
      pref = { 'other' => :template }
      expect(described_class.preference_for('coverage', pref)).to eq(:destination)
    end
  end
end
