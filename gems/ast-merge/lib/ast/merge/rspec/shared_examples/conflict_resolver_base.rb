# frozen_string_literal: true

# Shared examples for validating ConflictResolverBase integration
#
# Usage in your spec:
#   require "ast/merge/rspec/shared_examples/conflict_resolver_base"
#
#   RSpec.describe MyMerge::ConflictResolver do
#     it_behaves_like "Ast::Merge::ConflictResolverBase" do
#       let(:conflict_resolver_class) { MyMerge::ConflictResolver }
#       let(:strategy) { :node } # or :batch or :boundary
#       # Factory to create a conflict resolver instance
#       let(:build_conflict_resolver) do
#         ->(preference:, template_analysis:, dest_analysis:, **opts) {
#           conflict_resolver_class.new(
#             preference: preference,
#             template_analysis: template_analysis,
#             dest_analysis: dest_analysis,
#             **opts
#           )
#         }
#       end
#       # Factory to create mock analysis objects
#       let(:build_mock_analysis) { -> { double("Analysis") } }
#     end
#   end
#
# @note The extending class should inherit from or behave like Ast::Merge::ConflictResolverBase

RSpec.shared_examples('Ast::Merge::ConflictResolverBase') do
  # Required let blocks:
  # - conflict_resolver_class: The class under test
  # - strategy: The resolution strategy (:node, :batch, or :boundary)
  # - build_conflict_resolver: Lambda that creates a conflict resolver instance
  # - build_mock_analysis: Lambda that creates mock analysis objects

  describe 'decision constants' do
    it 'has DECISION_DESTINATION' do
      expect(conflict_resolver_class::DECISION_DESTINATION).to(eq(:destination))
    end

    it 'has DECISION_TEMPLATE' do
      expect(conflict_resolver_class::DECISION_TEMPLATE).to(eq(:template))
    end

    it 'has DECISION_ADDED' do
      expect(conflict_resolver_class::DECISION_ADDED).to(eq(:added))
    end

    it 'has DECISION_FROZEN' do
      expect(conflict_resolver_class::DECISION_FROZEN).to(eq(:frozen))
    end

    it 'has DECISION_IDENTICAL' do
      expect(conflict_resolver_class::DECISION_IDENTICAL).to(eq(:identical))
    end

    it 'has DECISION_KEPT_DEST' do
      expect(conflict_resolver_class::DECISION_KEPT_DEST).to(eq(:kept_destination))
    end

    it 'has DECISION_KEPT_TEMPLATE' do
      expect(conflict_resolver_class::DECISION_KEPT_TEMPLATE).to(eq(:kept_template))
    end

    it 'has DECISION_APPENDED' do
      expect(conflict_resolver_class::DECISION_APPENDED).to(eq(:appended))
    end

    it 'has DECISION_FREEZE_BLOCK' do
      expect(conflict_resolver_class::DECISION_FREEZE_BLOCK).to(eq(:freeze_block))
    end

    it 'has DECISION_RECURSIVE' do
      expect(conflict_resolver_class::DECISION_RECURSIVE).to(eq(:recursive))
    end

    it 'has DECISION_REPLACED' do
      expect(conflict_resolver_class::DECISION_REPLACED).to(eq(:replaced))
    end
  end

  describe 'initialization' do
    let(:template_analysis) { build_mock_analysis.call }
    let(:dest_analysis) { build_mock_analysis.call }

    context 'with :destination preference' do
      let(:resolver) do
        build_conflict_resolver.call(
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end

      it 'sets preference to :destination' do
        expect(resolver.preference).to(eq(:destination))
      end

      it 'sets strategy correctly' do
        expect(resolver.strategy).to(eq(strategy))
      end

      it 'stores template_analysis' do
        expect(resolver.template_analysis).to(eq(template_analysis))
      end

      it 'stores dest_analysis' do
        expect(resolver.dest_analysis).to(eq(dest_analysis))
      end
    end

    context 'with :template preference' do
      let(:resolver) do
        build_conflict_resolver.call(
          preference: :template,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end

      it 'sets preference to :template' do
        expect(resolver.preference).to(eq(:template))
      end
    end
  end

  describe 'attr_readers' do
    let(:template_analysis) { build_mock_analysis.call }
    let(:dest_analysis) { build_mock_analysis.call }
    let(:resolver) do
      build_conflict_resolver.call(
        preference: :destination,
        template_analysis: template_analysis,
        dest_analysis: dest_analysis
      )
    end

    it 'has #strategy reader' do
      expect(resolver).to(respond_to(:strategy))
    end

    it 'has #preference reader' do
      expect(resolver).to(respond_to(:preference))
    end

    it 'has #template_analysis reader' do
      expect(resolver).to(respond_to(:template_analysis))
    end

    it 'has #dest_analysis reader' do
      expect(resolver).to(respond_to(:dest_analysis))
    end

    it 'has #add_template_only_nodes reader' do
      expect(resolver).to(respond_to(:add_template_only_nodes))
    end

    it 'has #remove_template_missing_nodes reader' do
      expect(resolver).to(respond_to(:remove_template_missing_nodes))
    end

    it 'has #recursive reader' do
      expect(resolver).to(respond_to(:recursive))
    end

    it 'has #match_refiner reader' do
      expect(resolver).to(respond_to(:match_refiner))
    end
  end

  describe '#resolve' do
    let(:template_analysis) { build_mock_analysis.call }
    let(:dest_analysis) { build_mock_analysis.call }
    let(:resolver) do
      build_conflict_resolver.call(
        preference: :destination,
        template_analysis: template_analysis,
        dest_analysis: dest_analysis
      )
    end

    it 'responds to #resolve' do
      expect(resolver).to(respond_to(:resolve))
    end
  end

  describe '#freeze_node?' do
    let(:template_analysis) { build_mock_analysis.call }
    let(:dest_analysis) { build_mock_analysis.call }
    let(:resolver) do
      build_conflict_resolver.call(
        preference: :destination,
        template_analysis: template_analysis,
        dest_analysis: dest_analysis
      )
    end

    it 'returns false for nodes without freeze_node? method' do
      node = double('Node')
      expect(resolver.freeze_node?(node)).to(be(false))
    end

    it 'returns true for nodes that respond to freeze_node? and return true' do
      node = double('FreezeNode', freeze_node?: true)
      expect(resolver.freeze_node?(node)).to(be(true))
    end

    it 'returns false for nodes that respond to freeze_node? and return false' do
      node = double('RegularNode', freeze_node?: false)
      expect(resolver.freeze_node?(node)).to(be(false))
    end
  end

  describe 'per-node-type preferences' do
    let(:template_analysis) { build_mock_analysis.call }
    let(:dest_analysis) { build_mock_analysis.call }

    context 'with hash preferences' do
      let(:resolver) do
        build_conflict_resolver.call(
          preference: { default: :destination, special: :template },
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end
      let(:typed_template_node) { Ast::Merge::NodeTyping.with_merge_type(Object.new, :special) }
      let(:typed_dest_node) { Ast::Merge::NodeTyping.with_merge_type(Object.new, :special) }
      let(:untyped_node) { Object.new }

      it 'reports per-type preference enabled' do
        expect(resolver.per_type_preference?).to(be(true))
      end

      it 'returns default preference for untyped nodes' do
        expect(resolver.preference_for_node(untyped_node)).to(eq(:destination))
      end

      it 'returns per-type preference for typed nodes' do
        expect(resolver.preference_for_node(typed_template_node)).to(eq(:template))
      end

      it 'prefers typed template nodes when configured' do
        resolution = resolver.send(:preference_resolution, template_node: typed_template_node, dest_node: untyped_node)
        expect(resolution[:source]).to(eq(:template))
        expect(resolution[:decision]).to(eq(conflict_resolver_class::DECISION_TEMPLATE))
      end

      it 'prefers typed destination nodes when configured' do
        resolver_with_dest = build_conflict_resolver.call(
          preference: { default: :template, special: :destination },
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        resolution = resolver_with_dest.send(:preference_resolution, template_node: untyped_node,
                                                                     dest_node: typed_dest_node)
        expect(resolution[:source]).to(eq(:destination))
        expect(resolution[:decision]).to(eq(conflict_resolver_class::DECISION_DESTINATION))
      end
    end

    context 'with scalar preference' do
      let(:resolver) do
        build_conflict_resolver.call(
          preference: :template,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end

      it 'reports per-type preference disabled' do
        expect(resolver.per_type_preference?).to(be(false))
      end
    end
  end
end

RSpec.shared_examples('Ast::Merge::ConflictResolverBase validation') do
  # Tests for invalid initialization arguments
  # These test the base class validation directly

  let(:template_analysis) { build_mock_analysis.call }
  let(:dest_analysis) { build_mock_analysis.call }

  describe 'argument validation' do
    it 'raises ArgumentError for invalid strategy' do
      expect do
        Ast::Merge::ConflictResolverBase.new(
          strategy: :invalid,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end.to(raise_error(ArgumentError, /Invalid strategy/))
    end

    it 'raises ArgumentError for invalid preference' do
      expect do
        Ast::Merge::ConflictResolverBase.new(
          strategy: :node,
          preference: :invalid,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end.to(raise_error(ArgumentError, /Invalid preference/))
    end

    it 'accepts :node strategy' do
      expect do
        Ast::Merge::ConflictResolverBase.new(
          strategy: :node,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end.not_to(raise_error)
    end

    it 'accepts :batch strategy' do
      expect do
        Ast::Merge::ConflictResolverBase.new(
          strategy: :batch,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end.not_to(raise_error)
    end

    it 'accepts :boundary strategy' do
      expect do
        Ast::Merge::ConflictResolverBase.new(
          strategy: :boundary,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end.not_to(raise_error)
    end

    it 'accepts :destination preference' do
      expect do
        Ast::Merge::ConflictResolverBase.new(
          strategy: :node,
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end.not_to(raise_error)
    end

    it 'accepts :template preference' do
      expect do
        Ast::Merge::ConflictResolverBase.new(
          strategy: :node,
          preference: :template,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end.not_to(raise_error)
    end
  end
end

RSpec.shared_examples('Ast::Merge::ConflictResolverBase node strategy') do
  # Additional examples specific to :node strategy resolvers
  # Use when strategy is :node

  let(:template_analysis) { build_mock_analysis.call }
  let(:dest_analysis) { build_mock_analysis.call }
  let(:resolver) do
    build_conflict_resolver.call(
      preference: :destination,
      template_analysis: template_analysis,
      dest_analysis: dest_analysis
    )
  end

  describe 'node strategy' do
    it 'has :node strategy' do
      expect(resolver.strategy).to(eq(:node))
    end

    it 'delegates resolve to resolve_node_pair' do
      expect(resolver).to(respond_to(:resolve))
    end
  end
end

RSpec.shared_examples('Ast::Merge::ConflictResolverBase batch strategy') do
  # Additional examples specific to :batch strategy resolvers
  # Use when strategy is :batch

  let(:template_analysis) { build_mock_analysis.call }
  let(:dest_analysis) { build_mock_analysis.call }
  let(:resolver) do
    build_conflict_resolver.call(
      preference: :destination,
      template_analysis: template_analysis,
      dest_analysis: dest_analysis
    )
  end

  describe 'batch strategy' do
    it 'has :batch strategy' do
      expect(resolver.strategy).to(eq(:batch))
    end

    it 'delegates resolve to resolve_batch' do
      expect(resolver).to(respond_to(:resolve))
    end
  end

  describe '#add_template_only_nodes' do
    context 'with default value' do
      it 'defaults to false' do
        expect(resolver.add_template_only_nodes).to(be(false))
      end
    end

    context 'with add_template_only_nodes: true' do
      let(:resolver_with_add) do
        build_conflict_resolver.call(
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: true
        )
      end

      it 'returns true when set' do
        expect(resolver_with_add.add_template_only_nodes).to(be(true))
      end
    end
  end
end

RSpec.shared_examples('Ast::Merge::ConflictResolverBase boundary strategy') do
  # Additional examples specific to :boundary strategy resolvers
  # Use when strategy is :boundary
  #
  # Boundary strategy is used for ASTs where content is processed
  # in sections/ranges rather than individual nodes or all at once.
  # This is typical for languages like Ruby where file alignment
  # identifies boundaries (sections with differences) between
  # template and destination files.

  let(:template_analysis) { build_mock_analysis.call }
  let(:dest_analysis) { build_mock_analysis.call }
  let(:resolver) do
    build_conflict_resolver.call(
      preference: :destination,
      template_analysis: template_analysis,
      dest_analysis: dest_analysis
    )
  end

  describe 'boundary strategy' do
    it 'has :boundary strategy' do
      expect(resolver.strategy).to(eq(:boundary))
    end

    it 'delegates resolve to resolve_boundary' do
      expect(resolver).to(respond_to(:resolve))
    end
  end

  describe '#add_template_only_nodes' do
    context 'with default value' do
      it 'defaults to false' do
        expect(resolver.add_template_only_nodes).to(be(false))
      end
    end

    context 'with add_template_only_nodes: true' do
      let(:resolver_with_add) do
        build_conflict_resolver.call(
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: true
        )
      end

      it 'returns true when set' do
        expect(resolver_with_add.add_template_only_nodes).to(be(true))
      end
    end
  end
end
