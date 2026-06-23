# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples'

RSpec.describe Ast::Merge::ConflictResolverBase do
  # Dogfood: Test the base class with the shared examples
  it_behaves_like 'Ast::Merge::ConflictResolverBase' do
    let(:conflict_resolver_class) { described_class }
    let(:strategy) { :node } # Test with :node strategy
    let(:build_conflict_resolver) do
      lambda { |preference:, template_analysis:, dest_analysis:, **opts|
        # Use an anonymous subclass that provides minimal implementations
        klass = Class.new(described_class) do
          def resolve_node_pair(template_node, dest_node, template_index:, dest_index:)
            # Minimal implementation for testing
            {
              source: @preference,
              decision: @preference == :destination ? DECISION_DESTINATION : DECISION_TEMPLATE,
              template_node: template_node,
              dest_node: dest_node
            }
          end
        end

        klass.new(
          strategy: :node,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          **opts
        )
      }
    end
    let(:build_mock_analysis) { -> { double('Analysis') } }
  end

  it_behaves_like 'Ast::Merge::ConflictResolverBase validation' do
    let(:build_mock_analysis) { -> { double('Analysis') } }
  end

  # Test strategy-specific shared examples
  it_behaves_like 'Ast::Merge::ConflictResolverBase node strategy' do
    let(:conflict_resolver_class) { described_class }
    let(:build_conflict_resolver) do
      lambda { |preference:, template_analysis:, dest_analysis:, **opts|
        klass = Class.new(described_class) do
          def resolve_node_pair(_template_node, _dest_node, template_index:, dest_index:)
            { source: @preference, decision: :test }
          end
        end
        klass.new(
          strategy: :node,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          **opts
        )
      }
    end
    let(:build_mock_analysis) { -> { double('Analysis') } }
  end

  it_behaves_like 'Ast::Merge::ConflictResolverBase batch strategy' do
    let(:conflict_resolver_class) { described_class }
    let(:build_conflict_resolver) do
      lambda { |preference:, template_analysis:, dest_analysis:, **opts|
        klass = Class.new(described_class) do
          def resolve_batch(_result)
            { decision: :batch_test }
          end
        end
        klass.new(
          strategy: :batch,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          **opts
        )
      }
    end
    let(:build_mock_analysis) { -> { double('Analysis') } }
  end

  it_behaves_like 'Ast::Merge::ConflictResolverBase boundary strategy' do
    let(:conflict_resolver_class) { described_class }
    let(:build_conflict_resolver) do
      lambda { |preference:, template_analysis:, dest_analysis:, **opts|
        klass = Class.new(described_class) do
          def resolve_boundary(_boundary, _result)
            { decision: :boundary_test }
          end
        end
        klass.new(
          strategy: :boundary,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          **opts
        )
      }
    end
    let(:build_mock_analysis) { -> { double('Analysis') } }
  end

  describe 'direct base class behavior' do
    let(:template_analysis) { double('TemplateAnalysis') }
    let(:dest_analysis) { double('DestAnalysis') }

    describe '#resolve with :node strategy' do
      it 'raises NotImplementedError when resolve_node_pair not implemented' do
        resolver = described_class.new(
          strategy: :node,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        expect do
          resolver.resolve('template_node', 'dest_node', template_index: 0, dest_index: 0)
        end.to raise_error(NotImplementedError, /resolve_node_pair/)
      end
    end

    describe '#resolve with :batch strategy' do
      it 'raises NotImplementedError when resolve_batch not implemented' do
        resolver = described_class.new(
          strategy: :batch,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        expect do
          resolver.resolve('result')
        end.to raise_error(NotImplementedError, /resolve_batch/)
      end
    end

    describe '#resolve with :boundary strategy' do
      it 'raises NotImplementedError when resolve_boundary not implemented' do
        resolver = described_class.new(
          strategy: :boundary,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        expect do
          resolver.resolve('boundary', 'result')
        end.to raise_error(NotImplementedError, /resolve_boundary/)
      end
    end

    describe '#build_signature_map' do
      it 'builds a map from nodes to signatures' do
        resolver = described_class.new(
          strategy: :batch,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        node1 = double('Node1')
        node2 = double('Node2')
        node3 = double('Node3')
        nodes = [node1, node2, node3]

        allow(template_analysis).to receive(:generate_signature).with(node1).and_return(%i[sig a])
        allow(template_analysis).to receive(:generate_signature).with(node2).and_return(%i[sig b])
        allow(template_analysis).to receive(:generate_signature).with(node3).and_return(%i[sig a]) # duplicate

        map = resolver.send(:build_signature_map, nodes, template_analysis)

        expect(map[%i[sig a]].size).to eq(2)
        expect(map[%i[sig b]].size).to eq(1)
        expect(map[%i[sig a]][0][:node]).to eq(node1)
        expect(map[%i[sig a]][0][:index]).to eq(0)
        expect(map[%i[sig a]][1][:node]).to eq(node3)
        expect(map[%i[sig a]][1][:index]).to eq(2)
      end

      it 'skips nodes with nil signatures' do
        resolver = described_class.new(
          strategy: :batch,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        node1 = double('Node1')
        node2 = double('Node2')
        nodes = [node1, node2]

        allow(template_analysis).to receive(:generate_signature).with(node1).and_return(nil)
        allow(template_analysis).to receive(:generate_signature).with(node2).and_return(%i[sig b])

        map = resolver.send(:build_signature_map, nodes, template_analysis)

        expect(map.keys).to eq([%i[sig b]])
      end
    end

    describe '#build_signature_map_from_infos' do
      it 'builds a map from node_info hashes' do
        resolver = described_class.new(
          strategy: :boundary,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        node_infos = [
          { signature: %i[sig a], index: 0, node: double('Node1') },
          { signature: %i[sig b], index: 1, node: double('Node2') },
          { signature: %i[sig a], index: 2, node: double('Node3') }
        ]

        map = resolver.send(:build_signature_map_from_infos, node_infos)

        expect(map[%i[sig a]].size).to eq(2)
        expect(map[%i[sig b]].size).to eq(1)
        expect(map[%i[sig a]][0][:index]).to eq(0)
        expect(map[%i[sig a]][1][:index]).to eq(2)
      end

      it 'skips node_infos with nil signatures' do
        resolver = described_class.new(
          strategy: :boundary,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        node_infos = [
          { signature: nil, index: 0, node: double('Node1') },
          { signature: %i[sig b], index: 1, node: double('Node2') }
        ]

        map = resolver.send(:build_signature_map_from_infos, node_infos)

        expect(map.keys).to eq([%i[sig b]])
      end
    end

    describe 'unresolved path helpers' do
      let(:resolver) do
        described_class.new(
          strategy: :batch,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end

      let(:unresolved_helper_host) { resolver }
      let(:unresolved_case_id_parts) { ['json', :pair_value, 'name'] }
      let(:expected_unresolved_case_id) { 'json-pair_value-name-12' }

      it_behaves_like 'Ast::Merge::UnresolvedHelperContract'
    end

    describe '#ranges_overlap?' do
      let(:resolver) do
        described_class.new(
          strategy: :boundary,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end

      it 'returns true for overlapping ranges' do
        expect(resolver.send(:ranges_overlap?, 1..5, 3..7)).to be true
        expect(resolver.send(:ranges_overlap?, 3..7, 1..5)).to be true
      end

      it 'returns true for adjacent ranges that share an endpoint' do
        expect(resolver.send(:ranges_overlap?, 1..5, 5..10)).to be true
      end

      it 'returns false for non-overlapping ranges' do
        expect(resolver.send(:ranges_overlap?, 1..5, 7..10)).to be false
        expect(resolver.send(:ranges_overlap?, 7..10, 1..5)).to be false
      end

      it 'returns true for contained ranges' do
        expect(resolver.send(:ranges_overlap?, 1..10, 3..5)).to be true
        expect(resolver.send(:ranges_overlap?, 3..5, 1..10)).to be true
      end
    end

    describe 'resolution helpers' do
      let(:resolver) do
        described_class.new(
          strategy: :node,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end

      describe '#frozen_resolution' do
        it 'creates a frozen resolution hash' do
          template_node = double('TemplateNode')
          dest_node = double('DestNode')

          result = resolver.send(
            :frozen_resolution,
            source: :destination,
            template_node: template_node,
            dest_node: dest_node,
            reason: 'user requested freeze'
          )

          expect(result[:source]).to eq(:destination)
          expect(result[:decision]).to eq(:frozen)
          expect(result[:template_node]).to eq(template_node)
          expect(result[:dest_node]).to eq(dest_node)
          expect(result[:reason]).to eq('user requested freeze')
        end
      end

      describe '#identical_resolution' do
        it 'creates an identical resolution hash' do
          template_node = double('TemplateNode')
          dest_node = double('DestNode')

          result = resolver.send(
            :identical_resolution,
            template_node: template_node,
            dest_node: dest_node
          )

          expect(result[:source]).to eq(:destination)
          expect(result[:decision]).to eq(:identical)
          expect(result[:template_node]).to eq(template_node)
          expect(result[:dest_node]).to eq(dest_node)
        end
      end

      describe '#preference_resolution' do
        context 'with :destination preference' do
          it 'returns destination resolution' do
            template_node = double('TemplateNode')
            dest_node = double('DestNode')

            result = resolver.send(
              :preference_resolution,
              template_node: template_node,
              dest_node: dest_node
            )

            expect(result[:source]).to eq(:destination)
            expect(result[:decision]).to eq(:destination)
          end
        end

        context 'with :template preference' do
          let(:resolver) do
            described_class.new(
              strategy: :node,
              preference: :template,
              template_analysis: template_analysis,
              dest_analysis: dest_analysis
            )
          end

          it 'returns template resolution' do
            template_node = double('TemplateNode')
            dest_node = double('DestNode')

            result = resolver.send(
              :preference_resolution,
              template_node: template_node,
              dest_node: dest_node
            )

            expect(result[:source]).to eq(:template)
            expect(result[:decision]).to eq(:template)
          end
        end
      end
    end

    describe '#resolve with unknown strategy (covers else branch at line 150)' do
      it 'returns nil for unknown strategy' do
        # Force an unknown strategy by setting instance variable directly
        resolver = described_class.new(
          strategy: :node,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
        resolver.instance_variable_set(:@strategy, :unknown)

        # Should fall through the case statement and return nil
        result = resolver.resolve('arg1', 'arg2')
        expect(result).to be_nil
      end
    end

    describe '#preference_for_node' do
      context 'with Symbol preference' do
        let(:resolver) do
          described_class.new(
            strategy: :node,
            preference: :destination,
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
        end

        it 'returns the preference for any node' do
          node = double('Node')
          expect(resolver.preference_for_node(node)).to eq(:destination)
        end

        it 'returns the preference when node is nil' do
          expect(resolver.preference_for_node(nil)).to eq(:destination)
        end
      end

      context 'with Hash preference' do
        let(:resolver) do
          described_class.new(
            strategy: :node,
            preference: { default: :destination, lint_gem: :template, test_type: :template },
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
        end

        it 'returns default preference when node is nil' do
          expect(resolver.preference_for_node(nil)).to eq(:destination)
        end

        it 'returns default preference for non-typed node' do
          node = double('Node')
          expect(resolver.preference_for_node(node)).to eq(:destination)
        end

        it 'returns type-specific preference for typed node' do
          node = double('Node')
          typed_node = Ast::Merge::NodeTyping.with_merge_type(node, :lint_gem)
          expect(resolver.preference_for_node(typed_node)).to eq(:template)
        end

        it 'returns default for typed node with unknown merge_type' do
          node = double('Node')
          typed_node = Ast::Merge::NodeTyping.with_merge_type(node, :unknown_type)
          expect(resolver.preference_for_node(typed_node)).to eq(:destination)
        end
      end
    end

    describe '#default_preference' do
      context 'with Symbol preference' do
        it 'returns the symbol preference' do
          resolver = described_class.new(
            strategy: :node,
            preference: :template,
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
          expect(resolver.default_preference).to eq(:template)
        end
      end

      context 'with Hash preference' do
        it 'returns :default value from hash' do
          resolver = described_class.new(
            strategy: :node,
            preference: { default: :template, other: :destination },
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
          expect(resolver.default_preference).to eq(:template)
        end

        it 'returns :destination when :default key is missing' do
          resolver = described_class.new(
            strategy: :node,
            preference: { lint_gem: :template },
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
          expect(resolver.default_preference).to eq(:destination)
        end
      end
    end

    describe '#per_type_preference?' do
      it 'returns true for Hash preference' do
        resolver = described_class.new(
          strategy: :node,
          preference: { default: :destination },
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
        expect(resolver.per_type_preference?).to be true
      end

      it 'returns false for Symbol preference' do
        resolver = described_class.new(
          strategy: :node,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
        expect(resolver.per_type_preference?).to be false
      end
    end

    describe '#preference_resolution with typed nodes' do
      context 'with Hash preference' do
        let(:resolver) do
          described_class.new(
            strategy: :node,
            preference: { default: :destination, special_type: :template },
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
        end

        it "uses template_node's merge_type when template is typed" do
          template = Ast::Merge::NodeTyping.with_merge_type(double('T'), :special_type)
          dest = double('DestNode')

          result = resolver.send(:preference_resolution, template_node: template, dest_node: dest)

          expect(result[:source]).to eq(:template)
          expect(result[:decision]).to eq(:template)
        end

        it "uses dest_node's merge_type when only dest is typed" do
          template = double('TemplateNode')
          dest = Ast::Merge::NodeTyping.with_merge_type(double('D'), :special_type)

          result = resolver.send(:preference_resolution, template_node: template, dest_node: dest)

          expect(result[:source]).to eq(:template)
          expect(result[:decision]).to eq(:template)
        end

        it 'uses default preference when neither node is typed' do
          template = double('TemplateNode')
          dest = double('DestNode')

          result = resolver.send(:preference_resolution, template_node: template, dest_node: dest)

          expect(result[:source]).to eq(:destination)
          expect(result[:decision]).to eq(:destination)
        end

        it 'template_node takes precedence over dest_node' do
          template = Ast::Merge::NodeTyping.with_merge_type(double('T'), :special_type)
          dest = Ast::Merge::NodeTyping.with_merge_type(double('D'), :other_type)

          result = resolver.send(:preference_resolution, template_node: template, dest_node: dest)

          # special_type => :template
          expect(result[:source]).to eq(:template)
        end
      end
    end

    describe 'Hash preference validation' do
      it 'accepts valid Hash preference' do
        expect do
          described_class.new(
            strategy: :node,
            preference: { default: :destination, custom: :template },
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
        end.not_to raise_error
      end

      it 'raises ArgumentError for non-Symbol keys' do
        expect do
          described_class.new(
            strategy: :node,
            preference: { 'string_key' => :destination },
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
        end.to raise_error(ArgumentError, /keys must be Symbols/)
      end

      it 'raises ArgumentError for invalid values' do
        expect do
          described_class.new(
            strategy: :node,
            preference: { default: :invalid_value },
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
        end.to raise_error(ArgumentError, /values must be :destination or :template/)
      end

      it 'raises ArgumentError for invalid preference type' do
        expect do
          described_class.new(
            strategy: :node,
            preference: :invalid_symbol,
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          )
        end.to raise_error(ArgumentError, /Invalid preference/)
      end
    end
  end
end
