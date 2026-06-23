# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

# ConflictResolver specs - works with any RBS parser backend
# Tagged with :rbs_parsing since FileAnalysis supports both RBS gem and tree-sitter-rbs
RSpec.describe Rbs::Merge::ConflictResolver, :rbs_parsing do
  shared_examples 'comment-aware declaration identity' do
    let(:documented_source) do
      <<~RBS
        # shared docs
        class Foo
          def bar: () -> void
        end
      RBS
    end
    let(:different_docs_source) do
      <<~RBS
        # different docs
        class Foo
          def bar: () -> void
        end
      RBS
    end
    let(:documented_analysis) { Rbs::Merge::FileAnalysis.new(documented_source) }
    let(:different_docs_analysis) { Rbs::Merge::FileAnalysis.new(different_docs_source) }

    it 'treats identical documented declarations as identical' do
      resolver = described_class.new(
        preference: :destination,
        template_analysis: documented_analysis,
        dest_analysis: documented_analysis
      )

      decl1 = documented_analysis.declarations.first
      decl2 = documented_analysis.declarations.first

      expect(resolver.declarations_identical?(decl1, decl2)).to be true
    end

    it 'treats differing declaration-leading docs as a meaningful difference' do
      resolver = described_class.new(
        preference: :destination,
        template_analysis: documented_analysis,
        dest_analysis: different_docs_analysis
      )

      template_decl = documented_analysis.declarations.first
      dest_decl = different_docs_analysis.declarations.first

      expect(resolver.declarations_identical?(template_decl, dest_decl)).to be false
    end
  end

  shared_examples 'documented recursive resolution' do
    let(:documented_template_source) do
      <<~RBS
        # template docs
        class Foo
          def bar: () -> void
        end
      RBS
    end
    let(:documented_dest_source) do
      <<~RBS
        # destination docs
        class Foo
          def baz: () -> void
        end
      RBS
    end
    let(:documented_template_analysis) { Rbs::Merge::FileAnalysis.new(documented_template_source) }
    let(:documented_dest_analysis) { Rbs::Merge::FileAnalysis.new(documented_dest_source) }

    it 'still resolves documented container declarations through the recursive path' do
      resolver = described_class.new(
        preference: :destination,
        template_analysis: documented_template_analysis,
        dest_analysis: documented_dest_analysis
      )

      template_decl = documented_template_analysis.declarations.first
      dest_decl = documented_dest_analysis.declarations.first

      result = resolver.resolve(template_decl, dest_decl, template_index: 0, dest_index: 0)

      expect(result[:source]).to eq(:recursive)
      expect(result[:decision]).to eq(Rbs::Merge::MergeResult::DECISION_RECURSIVE)
    end
  end

  shared_examples 'freeze block resolution parity' do
    let(:template_source_with_class) do
      <<~RBS
        class Foo
          def bar: (String) -> Integer
        end
      RBS
    end
    let(:dest_with_freeze_source) do
      <<~RBS
        # rbs-merge:freeze
        class Foo
          def bar: (Integer) -> String
        end
        # rbs-merge:unfreeze
      RBS
    end
    let(:template_analysis_with_class) { Rbs::Merge::FileAnalysis.new(template_source_with_class) }
    let(:dest_analysis_with_freeze) { Rbs::Merge::FileAnalysis.new(dest_with_freeze_source) }

    it 'treats freeze blocks as destination-owned regardless of preference' do
      resolver = described_class.new(
        preference: :template,
        template_analysis: template_analysis_with_class,
        dest_analysis: dest_analysis_with_freeze
      )

      freeze_node = dest_analysis_with_freeze.freeze_blocks.first
      template_decl = template_analysis_with_class.declarations.first
      result = resolver.resolve(template_decl, freeze_node, template_index: 0, dest_index: 0)

      expect(result[:source]).to eq(:destination)
      expect(result[:declaration]).to eq(freeze_node)
      expect(result[:decision]).to eq(Rbs::Merge::MergeResult::DECISION_FREEZE_BLOCK)
    end
  end

  # Use shared examples to validate base ConflictResolverBase integration
  # Note: rbs-merge uses the :node strategy
  it_behaves_like 'Ast::Merge::ConflictResolverBase' do
    let(:conflict_resolver_class) { described_class }
    let(:strategy) { :node }
    let(:build_conflict_resolver) do
      lambda { |preference:, template_analysis:, dest_analysis:, **_opts|
        described_class.new(
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      }
    end
    let(:build_mock_analysis) do
      lambda {
        source = "class Foo\nend\n"
        Rbs::Merge::FileAnalysis.new(source)
      }
    end
  end

  it_behaves_like 'Ast::Merge::ConflictResolverBase node strategy' do
    let(:conflict_resolver_class) { described_class }
    let(:build_conflict_resolver) do
      lambda { |preference:, template_analysis:, dest_analysis:, **_opts|
        described_class.new(
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      }
    end
    let(:build_mock_analysis) do
      lambda {
        source = "class Foo\nend\n"
        Rbs::Merge::FileAnalysis.new(source)
      }
    end
  end

  let(:template_source) do
    <<~RBS
      class Foo
        def bar: (String) -> Integer
      end
    RBS
  end

  let(:dest_source) do
    <<~RBS
      class Foo
        def bar: (Integer) -> String
      end
    RBS
  end

  let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
  let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

  describe '#resolve' do
    context 'when dest_decl is a FreezeNode' do
      let(:dest_with_freeze) do
        <<~RBS
          # rbs-merge:freeze
          class Foo
            def bar: (Integer) -> String
          end
          # rbs-merge:unfreeze
        RBS
      end
      let(:dest_analysis_frozen) { Rbs::Merge::FileAnalysis.new(dest_with_freeze) }

      it 'always returns destination for freeze blocks' do
        resolver = described_class.new(
          preference: :template,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis_frozen
        )

        freeze_node = dest_analysis_frozen.freeze_blocks.first
        template_decl = template_analysis.declarations.first

        result = resolver.resolve(template_decl, freeze_node, template_index: 0, dest_index: 0)

        expect(result[:source]).to eq(:destination)
        expect(result[:declaration]).to eq(freeze_node)
        expect(result[:decision]).to eq(Rbs::Merge::MergeResult::DECISION_FREEZE_BLOCK)
      end
    end

    context 'when declarations are identical' do
      let(:identical_source) do
        <<~RBS
          class Foo
            def bar: (String) -> Integer
          end
        RBS
      end
      let(:dest_analysis_identical) { Rbs::Merge::FileAnalysis.new(identical_source) }

      it 'returns destination to minimize diffs' do
        resolver = described_class.new(
          preference: :template,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis_identical
        )

        template_decl = template_analysis.declarations.first
        dest_decl = dest_analysis_identical.declarations.first

        result = resolver.resolve(template_decl, dest_decl, template_index: 0, dest_index: 0)

        expect(result[:source]).to eq(:destination)
        expect(result[:decision]).to eq(Rbs::Merge::MergeResult::DECISION_DESTINATION)
      end
    end

    context 'when preference is :template' do
      let(:template_type_alias) { "type my_type = String\n" }
      let(:dest_type_alias) { "type my_type = Integer\n" }
      let(:template_analysis_alias) { Rbs::Merge::FileAnalysis.new(template_type_alias) }
      let(:dest_analysis_alias) { Rbs::Merge::FileAnalysis.new(dest_type_alias) }

      it 'returns template declaration' do
        resolver = described_class.new(
          preference: :template,
          template_analysis: template_analysis_alias,
          dest_analysis: dest_analysis_alias
        )

        template_decl = template_analysis_alias.declarations.first
        dest_decl = dest_analysis_alias.declarations.first

        result = resolver.resolve(template_decl, dest_decl, template_index: 0, dest_index: 0)

        expect(result[:source]).to eq(:template)
        expect(result[:declaration]).to eq(template_decl)
        expect(result[:decision]).to eq(Rbs::Merge::MergeResult::DECISION_TEMPLATE)
      end
    end

    context 'when preference is :destination' do
      let(:template_type_alias) { "type my_type = String\n" }
      let(:dest_type_alias) { "type my_type = Integer\n" }
      let(:template_analysis_alias) { Rbs::Merge::FileAnalysis.new(template_type_alias) }
      let(:dest_analysis_alias) { Rbs::Merge::FileAnalysis.new(dest_type_alias) }

      it 'returns destination declaration' do
        resolver = described_class.new(
          preference: :destination,
          template_analysis: template_analysis_alias,
          dest_analysis: dest_analysis_alias
        )

        template_decl = template_analysis_alias.declarations.first
        dest_decl = dest_analysis_alias.declarations.first

        result = resolver.resolve(template_decl, dest_decl, template_index: 0, dest_index: 0)

        expect(result[:source]).to eq(:destination)
        expect(result[:declaration]).to eq(dest_decl)
        expect(result[:decision]).to eq(Rbs::Merge::MergeResult::DECISION_DESTINATION)
      end
    end

    context 'when preference is per-node-type' do
      let(:template_type_alias) { "type my_type = String\n" }
      let(:dest_type_alias) { "type my_type = Integer\n" }
      let(:template_analysis_alias) { Rbs::Merge::FileAnalysis.new(template_type_alias) }
      let(:dest_analysis_alias) { Rbs::Merge::FileAnalysis.new(dest_type_alias) }

      it 'returns template declaration for typed nodes' do
        node_typing = {
          'TypeAlias' => lambda { |node|
            Ast::Merge::NodeTyping.with_merge_type(node, :alias_type)
          },
          'TreeHaver::Node' => lambda { |node|
            canonical = if node.respond_to?(:type)
                          Rbs::Merge::NodeTypeNormalizer.canonical_type(node.type, :tree_sitter)
                        end

            if canonical == :type_alias
              Ast::Merge::NodeTyping.with_merge_type(node, :alias_type)
            else
              node
            end
          }
        }

        resolver = described_class.new(
          preference: { default: :destination, alias_type: :template },
          template_analysis: template_analysis_alias,
          dest_analysis: dest_analysis_alias,
          node_typing: node_typing
        )

        template_decl = template_analysis_alias.declarations.first
        dest_decl = dest_analysis_alias.declarations.first

        result = resolver.resolve(template_decl, dest_decl, template_index: 0, dest_index: 0)

        expect(result[:source]).to eq(:template)
        expect(result[:declaration]).to eq(template_decl)
        expect(result[:decision]).to eq(Rbs::Merge::MergeResult::DECISION_TEMPLATE)
      end
    end

    context 'when preference is unknown' do
      let(:template_type_alias) { "type my_type = String\n" }
      let(:dest_type_alias) { "type my_type = Integer\n" }
      let(:template_analysis_alias) { Rbs::Merge::FileAnalysis.new(template_type_alias) }
      let(:dest_analysis_alias) { Rbs::Merge::FileAnalysis.new(dest_type_alias) }

      it 'raises ArgumentError for invalid preference' do
        expect do
          described_class.new(
            preference: :unknown_preference,
            template_analysis: template_analysis_alias,
            dest_analysis: dest_analysis_alias
          )
        end.to raise_error(ArgumentError, /Invalid preference/)
      end
    end

    context 'when declarations can be recursively merged' do
      it 'returns recursive resolution for container types with members' do
        resolver = described_class.new(
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        template_decl = template_analysis.declarations.first
        dest_decl = dest_analysis.declarations.first

        result = resolver.resolve(template_decl, dest_decl, template_index: 0, dest_index: 0)

        expect(result[:source]).to eq(:recursive)
        expect(result[:template_declaration]).to eq(template_decl)
        expect(result[:dest_declaration]).to eq(dest_decl)
        expect(result[:decision]).to eq(Rbs::Merge::MergeResult::DECISION_RECURSIVE)
      end
    end
  end

  describe '#declarations_identical?' do
    it 'returns true for identical declarations' do
      resolver = described_class.new(
        preference: :destination,
        template_analysis: template_analysis,
        dest_analysis: template_analysis
      )

      decl1 = template_analysis.declarations.first
      decl2 = template_analysis.declarations.first

      expect(resolver.declarations_identical?(decl1, decl2)).to be true
    end

    it 'returns false for different declarations' do
      resolver = described_class.new(
        preference: :destination,
        template_analysis: template_analysis,
        dest_analysis: dest_analysis
      )

      decl1 = template_analysis.declarations.first
      decl2 = dest_analysis.declarations.first

      expect(resolver.declarations_identical?(decl1, decl2)).to be false
    end
  end

  describe '#can_recursive_merge?' do
    context 'with Class declarations' do
      it 'returns true for classes with members' do
        resolver = described_class.new(
          preference: :destination,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )

        template_decl = template_analysis.declarations.first
        dest_decl = dest_analysis.declarations.first

        expect(resolver.can_recursive_merge?(template_decl, dest_decl)).to be true
      end
    end

    context 'with Module declarations' do
      let(:template_module) do
        <<~RBS
          module Foo
            def bar: () -> void
          end
        RBS
      end
      let(:dest_module) do
        <<~RBS
          module Foo
            def baz: () -> void
          end
        RBS
      end
      let(:template_analysis_mod) { Rbs::Merge::FileAnalysis.new(template_module) }
      let(:dest_analysis_mod) { Rbs::Merge::FileAnalysis.new(dest_module) }

      it 'returns true for modules with members' do
        resolver = described_class.new(
          preference: :destination,
          template_analysis: template_analysis_mod,
          dest_analysis: dest_analysis_mod
        )

        template_decl = template_analysis_mod.declarations.first
        dest_decl = dest_analysis_mod.declarations.first

        expect(resolver.can_recursive_merge?(template_decl, dest_decl)).to be true
      end
    end

    context 'with Interface declarations' do
      let(:template_interface) do
        <<~RBS
          interface _Foo
            def bar: () -> void
          end
        RBS
      end
      let(:dest_interface) do
        <<~RBS
          interface _Foo
            def baz: () -> void
          end
        RBS
      end
      let(:template_analysis_iface) { Rbs::Merge::FileAnalysis.new(template_interface) }
      let(:dest_analysis_iface) { Rbs::Merge::FileAnalysis.new(dest_interface) }

      it 'returns true for interfaces with members' do
        resolver = described_class.new(
          preference: :destination,
          template_analysis: template_analysis_iface,
          dest_analysis: dest_analysis_iface
        )

        template_decl = template_analysis_iface.declarations.first
        dest_decl = dest_analysis_iface.declarations.first

        expect(resolver.can_recursive_merge?(template_decl, dest_decl)).to be true
      end
    end

    context 'with empty containers' do
      let(:empty_class) { "class Foo\nend\n" }
      let(:template_empty) { Rbs::Merge::FileAnalysis.new(empty_class) }
      let(:dest_empty) { Rbs::Merge::FileAnalysis.new(empty_class) }

      it 'returns false for classes without members' do
        resolver = described_class.new(
          preference: :destination,
          template_analysis: template_empty,
          dest_analysis: dest_empty
        )

        template_decl = template_empty.declarations.first
        dest_decl = dest_empty.declarations.first

        expect(resolver.can_recursive_merge?(template_decl, dest_decl)).to be false
      end
    end

    context 'with non-container types' do
      let(:type_alias_source) { "type my_type = String\n" }
      let(:template_alias) { Rbs::Merge::FileAnalysis.new(type_alias_source) }
      let(:dest_alias) { Rbs::Merge::FileAnalysis.new(type_alias_source) }

      it 'returns false for type aliases' do
        resolver = described_class.new(
          preference: :destination,
          template_analysis: template_alias,
          dest_analysis: dest_alias
        )

        template_decl = template_alias.declarations.first
        dest_decl = dest_alias.declarations.first

        expect(resolver.can_recursive_merge?(template_decl, dest_decl)).to be false
      end
    end

    context 'with mismatched types' do
      let(:class_source) { "class Foo\n  def bar: () -> void\nend\n" }
      let(:module_source) { "module Foo\n  def bar: () -> void\nend\n" }
      let(:class_analysis) { Rbs::Merge::FileAnalysis.new(class_source) }
      let(:module_analysis) { Rbs::Merge::FileAnalysis.new(module_source) }

      it 'returns false for mismatched declaration types' do
        resolver = described_class.new(
          preference: :destination,
          template_analysis: class_analysis,
          dest_analysis: module_analysis
        )

        class_decl = class_analysis.declarations.first
        module_decl = module_analysis.declarations.first

        expect(resolver.can_recursive_merge?(class_decl, module_decl)).to be false
      end
    end
  end

  describe 'comment-aware explicit backend parity', :rbs_backend do
    around do |example|
      TreeHaver.with_backend(:rbs) do
        example.run
      end
    end

    it_behaves_like 'comment-aware declaration identity'
    it_behaves_like 'documented recursive resolution'
    it_behaves_like 'freeze block resolution parity'
  end

  describe 'comment-aware explicit backend parity', :mri_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    it_behaves_like 'comment-aware declaration identity'
    it_behaves_like 'documented recursive resolution'
    it_behaves_like 'freeze block resolution parity'
  end

  describe 'comment-aware explicit backend parity', :java_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    it_behaves_like 'comment-aware declaration identity'
    it_behaves_like 'documented recursive resolution'
    it_behaves_like 'freeze block resolution parity'
  end

  describe 'comment-aware explicit backend parity', :rbs_grammar, :rust_backend do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    it_behaves_like 'comment-aware declaration identity'
    it_behaves_like 'documented recursive resolution'
    it_behaves_like 'freeze block resolution parity'
  end

  describe 'comment-aware explicit backend parity', :ffi_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    it_behaves_like 'comment-aware declaration identity'
    it_behaves_like 'documented recursive resolution'
    it_behaves_like 'freeze block resolution parity'
  end
end
