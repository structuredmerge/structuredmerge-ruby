# frozen_string_literal: true

require 'spec_helper'

# FileAnalysis specs with explicit backend testing
#
# This spec file tests FileAnalysis behavior across both available backends:
# - :rbs (via RBS gem, tagged :rbs_backend)
# - :tree_sitter (via tree-sitter-rbs grammar, tagged :rbs_grammar)
#
# We define shared examples that are parameterized, then include them in
# backend-specific contexts that use TreeHaver.with_backend to explicitly
# select the backend under test.

RSpec.describe Rbs::Merge::FileAnalysis do
  describe 'FileAnalyzable contract', :rbs_parsing do
    it_behaves_like 'Ast::Merge::FileAnalyzable' do
      let(:file_analysis_class) { described_class }
      let(:freeze_node_class) { Rbs::Merge::FreezeNode }
      let(:sample_source) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end
      let(:sample_source_with_freeze) do
        <<~RBS
          class Before
          end
          # rbs-merge:freeze
          class Locked
          end
          # rbs-merge:unfreeze
          class After
          end
        RBS
      end
      let(:build_file_analysis) do
        ->(source, **opts) { described_class.new(source, **opts) }
      end

      let(:analysis_expected_feature_profile) do
        {
          owner_selector: :rbs_declarations,
          match_key: :signature,
          read_strategy: :source_augmented_portable_write,
          attachment_strategy: :normalize_tracked_layout_merge,
          comment_style: :hash_comment,
          render_family: :rbs_declarations,
          capabilities: { layout_aware: true, logical_owner: false },
          logical_owners: {},
          repair_policies: [],
          surfaces: [],
          delegation_policies: []
        }
      end
    end
  end

  # ============================================================
  # Shared examples for backend-agnostic behavior
  # These examples take the expected backend symbol as a parameter
  # The backend is determined by the TreeHaver context (via with_backend or env var)
  # ============================================================

  shared_examples 'valid RBS parsing' do |expected_backend:|
    describe 'with valid RBS source' do
      subject(:analysis) { described_class.new(valid_source) }

      let(:valid_source) do
        <<~RBS
          class Foo
            def bar: (String) -> Integer
          end
        RBS
      end

      it 'parses successfully' do
        expect(analysis).to be_a(described_class)
      end

      it 'is valid' do
        expect(analysis.valid?).to be true
      end

      it 'has no errors' do
        expect(analysis.errors).to be_empty
      end

      it "uses the #{expected_backend} backend" do
        expect(analysis.backend).to eq(expected_backend)
      end

      it 'returns a NodeWrapper for statements' do
        statements = analysis.statements
        expect(statements).to be_an(Array)
        expect(statements.first).to be_a(Rbs::Merge::NodeWrapper)
      end

      it 'returns source lines' do
        expect(analysis.lines).to be_an(Array)
        expect(analysis.lines.first).to eq('class Foo')
      end

      it 'extracts declarations' do
        expect(analysis.declarations).not_to be_empty
      end
    end
  end

  # NOTE: Strict error detection depends on the parser - RBS gem
  # reports errors more strictly than some tree-sitter backends
  shared_examples 'invalid RBS detection' do
    describe 'with invalid RBS', :rbs_backend do
      subject(:analysis) { described_class.new(invalid_source) }

      let(:invalid_source) do
        <<~RBS
          class Foo
            def bar: (
          end
        RBS
      end

      it 'is not valid' do
        expect(analysis.valid?).to be false
      end

      it 'has errors' do
        expect(analysis.errors).not_to be_empty
      end
    end
  end

  shared_examples 'multiple declarations' do
    describe 'with multiple declarations' do
      subject(:analysis) { described_class.new(multi_decl_source) }

      let(:multi_decl_source) do
        <<~RBS
          class Foo
            def foo: () -> void
          end

          module Bar
            def bar: () -> void
          end

          interface _Baz
            def baz: () -> void
          end

          type my_type = String | Integer

          CONST: String
        RBS
      end

      it 'extracts all declaration types' do
        expect(analysis.declarations.size).to eq(5)
      end

      it 'has statements for all declarations' do
        expect(analysis.statements.size).to eq(5)
      end

      it 'can generate signatures for all statements' do
        analysis.statements.each do |stmt|
          sig = analysis.generate_signature(stmt)
          expect(sig).to be_an(Array)
          expect(sig).not_to be_empty
        end
      end
    end
  end

  shared_examples 'alias declaration extraction' do
    describe 'alias declaration extraction' do
      subject(:analysis) { described_class.new(alias_source) }

      let(:alias_source) do
        <<~RBS
          class Foo = Bar
          module Baz = Quux
        RBS
      end

      it 'extracts class_alias and module_alias declarations with stable signatures' do
        expect(analysis.statements.map(&:canonical_type)).to eq(%i[class_alias module_alias])
        expect(analysis.statements.map(&:name)).to eq(%w[Foo Baz])
        expect(analysis.statements.map(&:signature)).to eq([
                                                             [:class_alias, 'Foo'],
                                                             [:module_alias, 'Baz']
                                                           ])
      end
    end
  end

  shared_examples 'alias wrapper location/text parity' do
    describe 'alias wrapper location/text parity' do
      subject(:analysis) { described_class.new(alias_source) }

      let(:alias_source) do
        <<~RBS
          class Foo = Bar # trailing comment
          module Baz = Quux # trailing comment

          # postlude
        RBS
      end

      it 'extracts exact alias wrapper lines and text without trailing same-line comments' do
        class_alias, module_alias = analysis.statements

        [[class_alias, 1, 'class Foo = Bar'],
         [module_alias, 2, 'module Baz = Quux']].each do |statement, expected_line, expected_text|
          raw = statement.underlying_node
          exact = if analysis.backend == :rbs
                    alias_source.byteslice(raw.location.start_pos...raw.location.end_pos)
                  else
                    alias_source.byteslice(raw.start_byte...raw.end_byte)
                  end

          expect(statement.start_line).to eq(expected_line)
          expect(statement.end_line).to eq(expected_line)
          expect(statement.text).to eq(expected_text)
          expect(statement.text).to eq(exact)
        end

        expect(class_alias.canonical_type).to eq(:class_alias)
        expect(class_alias.name).to eq('Foo')
        expect(class_alias.signature).to eq([:class_alias, 'Foo'])

        expect(module_alias.canonical_type).to eq(:module_alias)
        expect(module_alias.name).to eq('Baz')
        expect(module_alias.signature).to eq([:module_alias, 'Baz'])
      end
    end
  end

  shared_examples 'type alias declaration extraction' do
    describe 'type alias declaration extraction' do
      subject(:analysis) { described_class.new(type_alias_source) }

      let(:type_alias_source) do
        <<~RBS
          type user_id = String | Integer
        RBS
      end

      it 'extracts top-level type aliases with stable names and signatures' do
        statement = analysis.statements.first

        expect(statement.canonical_type).to eq(:type_alias)
        expect(statement.name).to eq('user_id')
        expect(statement.signature).to eq([:type_alias, 'user_id'])
        expect(analysis.generate_signature(statement)).to eq([:type_alias, 'user_id'])
      end
    end
  end

  shared_examples 'interface declaration extraction' do
    describe 'interface declaration extraction' do
      subject(:analysis) { described_class.new(interface_source) }

      let(:interface_source) do
        <<~RBS
          interface _Enumerable[T]
            def each: () -> void
          end
        RBS
      end

      it 'extracts top-level interfaces with stable names and signatures' do
        statement = analysis.statements.first

        expect(statement.canonical_type).to eq(:interface)
        expect(statement.name).to eq('_Enumerable')
        expect(statement.signature).to eq([:interface, '_Enumerable'])
        expect(analysis.generate_signature(statement)).to eq([:interface, '_Enumerable'])
      end
    end
  end

  shared_examples 'module declaration extraction' do
    describe 'module declaration extraction' do
      subject(:analysis) { described_class.new(module_source) }

      let(:module_source) do
        <<~RBS
          module Auth
            def token: () -> String
          end
        RBS
      end

      it 'extracts top-level modules with stable names and signatures' do
        statement = analysis.statements.first

        expect(statement.canonical_type).to eq(:module)
        expect(statement.name).to eq('Auth')
        expect(statement.signature).to eq([:module, 'Auth'])
        expect(analysis.generate_signature(statement)).to eq([:module, 'Auth'])
      end
    end
  end

  shared_examples 'class declaration extraction' do
    describe 'class declaration extraction' do
      subject(:analysis) { described_class.new(class_source) }

      let(:class_source) do
        <<~RBS
          class User
            def name: () -> String
          end
        RBS
      end

      it 'extracts top-level classes with stable names and signatures' do
        statement = analysis.statements.first

        expect(statement.canonical_type).to eq(:class)
        expect(statement.name).to eq('User')
        expect(statement.signature).to eq([:class, 'User'])
        expect(analysis.generate_signature(statement)).to eq([:class, 'User'])
      end
    end
  end

  shared_examples 'class wrapper location/text parity' do
    describe 'class wrapper location/text parity' do
      subject(:analysis) { described_class.new(class_source) }

      let(:class_source) do
        <<~RBS
          class User
            def name: () -> String
          end # trailing comment

          # postlude
        RBS
      end

      it 'extracts exact wrapper lines and text without trailing same-line comments' do
        statement = analysis.statements.first
        raw = statement.underlying_node
        exact = if analysis.backend == :rbs
                  class_source.byteslice(raw.location.start_pos...raw.location.end_pos)
                else
                  class_source.byteslice(raw.start_byte...raw.end_byte)
                end

        expect(statement.canonical_type).to eq(:class)
        expect(statement.name).to eq('User')
        expect(statement.start_line).to eq(1)
        expect(statement.end_line).to eq(3)
        expect(statement.text).to eq("class User\n  def name: () -> String\nend")
        expect(statement.text).to eq(exact)
      end
    end
  end

  shared_examples 'module wrapper location/text parity' do
    describe 'module wrapper location/text parity' do
      subject(:analysis) { described_class.new(module_source) }

      let(:module_source) do
        <<~RBS
          module Auth
            def token: () -> String
          end # trailing comment

          # postlude
        RBS
      end

      it 'extracts exact wrapper lines and text without trailing same-line comments' do
        statement = analysis.statements.first
        raw = statement.underlying_node
        exact = if analysis.backend == :rbs
                  module_source.byteslice(raw.location.start_pos...raw.location.end_pos)
                else
                  module_source.byteslice(raw.start_byte...raw.end_byte)
                end

        expect(statement.canonical_type).to eq(:module)
        expect(statement.name).to eq('Auth')
        expect(statement.start_line).to eq(1)
        expect(statement.end_line).to eq(3)
        expect(statement.text).to eq("module Auth\n  def token: () -> String\nend")
        expect(statement.text).to eq(exact)
      end
    end
  end

  shared_examples 'interface wrapper location/text parity' do
    describe 'interface wrapper location/text parity' do
      subject(:analysis) { described_class.new(interface_source) }

      let(:interface_source) do
        <<~RBS
          interface _Enumerable[T]
            def each: () -> void
          end # trailing comment

          # postlude
        RBS
      end

      it 'extracts exact wrapper lines and text without trailing same-line comments' do
        statement = analysis.statements.first
        raw = statement.underlying_node
        exact = if analysis.backend == :rbs
                  interface_source.byteslice(raw.location.start_pos...raw.location.end_pos)
                else
                  interface_source.byteslice(raw.start_byte...raw.end_byte)
                end

        expect(statement.canonical_type).to eq(:interface)
        expect(statement.name).to eq('_Enumerable')
        expect(statement.start_line).to eq(1)
        expect(statement.end_line).to eq(3)
        expect(statement.text).to eq("interface _Enumerable[T]\n  def each: () -> void\nend")
        expect(statement.text).to eq(exact)
      end
    end
  end

  shared_examples 'type alias wrapper location/text parity' do
    describe 'type alias wrapper location/text parity' do
      subject(:analysis) { described_class.new(type_alias_source) }

      let(:type_alias_source) do
        <<~RBS
          type user_id = String # trailing comment

          # postlude
        RBS
      end

      it 'extracts exact wrapper lines and text without trailing same-line comments' do
        statement = analysis.statements.first
        raw = statement.underlying_node
        exact = if analysis.backend == :rbs
                  type_alias_source.byteslice(raw.location.start_pos...raw.location.end_pos)
                else
                  type_alias_source.byteslice(raw.start_byte...raw.end_byte)
                end

        expect(statement.canonical_type).to eq(:type_alias)
        expect(statement.name).to eq('user_id')
        expect(statement.start_line).to eq(1)
        expect(statement.end_line).to eq(1)
        expect(statement.text).to eq('type user_id = String')
        expect(statement.text).to eq(exact)
      end
    end
  end

  shared_examples 'constant wrapper location/text parity' do
    describe 'constant wrapper location/text parity' do
      subject(:analysis) { described_class.new(constant_source) }

      let(:constant_source) do
        <<~RBS
          USER_ID: String # trailing comment

          # postlude
        RBS
      end

      it 'extracts exact wrapper lines and text without trailing same-line comments' do
        statement = analysis.statements.first
        raw = statement.underlying_node
        exact = if analysis.backend == :rbs
                  constant_source.byteslice(raw.location.start_pos...raw.location.end_pos)
                else
                  constant_source.byteslice(raw.start_byte...raw.end_byte)
                end

        expect(statement.canonical_type).to eq(:constant)
        expect(statement.name).to eq('USER_ID')
        expect(statement.start_line).to eq(1)
        expect(statement.end_line).to eq(1)
        expect(statement.text).to eq('USER_ID: String')
        expect(statement.text).to eq(exact)
      end
    end
  end

  shared_examples 'global wrapper location/text parity' do
    describe 'global wrapper location/text parity' do
      subject(:analysis) { described_class.new(global_source) }

      let(:global_source) do
        <<~RBS
          $stdout: IO # trailing comment

          # postlude
        RBS
      end

      it 'extracts exact wrapper lines and text without trailing same-line comments' do
        statement = analysis.statements.first
        raw = statement.underlying_node
        exact = if analysis.backend == :rbs
                  global_source.byteslice(raw.location.start_pos...raw.location.end_pos)
                else
                  global_source.byteslice(raw.start_byte...raw.end_byte)
                end

        expect(statement.canonical_type).to eq(:global)
        expect(statement.name).to eq('$stdout')
        expect(statement.start_line).to eq(1)
        expect(statement.end_line).to eq(1)
        expect(statement.text).to eq('$stdout: IO')
        expect(statement.text).to eq(exact)
      end
    end
  end

  shared_examples 'constant declaration extraction' do
    describe 'constant declaration extraction' do
      subject(:analysis) { described_class.new(constant_source) }

      let(:constant_source) do
        <<~RBS
          USER_ID: String
        RBS
      end

      it 'extracts top-level constants with stable names and signatures' do
        statement = analysis.statements.first

        expect(statement.canonical_type).to eq(:constant)
        expect(statement.name).to eq('USER_ID')
        expect(statement.signature).to eq([:constant, 'USER_ID'])
        expect(analysis.generate_signature(statement)).to eq([:constant, 'USER_ID'])
      end
    end
  end

  shared_examples 'global declaration extraction' do
    describe 'global declaration extraction' do
      subject(:analysis) { described_class.new(global_source) }

      let(:global_source) do
        <<~RBS
          $stdout: IO
        RBS
      end

      it 'extracts top-level globals with stable names and signatures' do
        statement = analysis.statements.first

        expect(statement.canonical_type).to eq(:global)
        expect(statement.name).to eq('$stdout')
        expect(statement.signature).to eq([:global, '$stdout'])
        expect(analysis.generate_signature(statement)).to eq([:global, '$stdout'])
      end
    end
  end

  shared_examples 'signature generation' do
    describe '#generate_signature' do
      subject(:analysis) { described_class.new(source_for_signature) }

      let(:source_for_signature) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end

      it 'generates signature for a class' do
        stmt = analysis.statements.first
        sig = analysis.generate_signature(stmt)
        expect(sig).to be_an(Array)
        expect(sig.first).to eq(:class)
        expect(sig[1]).to include('Foo')
      end

      it 'returns nil for nil input' do
        sig = analysis.generate_signature(nil)
        expect(sig).to be_nil
      end
    end
  end

  shared_examples 'nested overloaded member extraction' do
    describe 'nested overloaded member extraction' do
      subject(:analysis) { described_class.new(overloaded_source) }

      let(:overloaded_source) do
        <<~RBS
          interface _Foo
            def foo: () -> String
            def foo: (Integer) -> String
          end
        RBS
      end

      it 'extracts overloaded members from container declarations' do
        statement = analysis.statements.first

        expect(statement.name).to eq('_Foo')
        expect(statement.members.size).to eq(2)
        expect(statement.members.map(&:name)).to eq(%w[foo foo])
        expect(statement.members.map(&:signature)).to eq([
                                                           [:method, 'foo', :instance],
                                                           [:method, 'foo', :instance]
                                                         ])
      end
    end
  end

  shared_examples 'nested attribute member extraction' do
    describe 'nested attribute member extraction' do
      subject(:analysis) { described_class.new(attribute_source) }

      let(:attribute_source) do
        <<~RBS
          class Foo
            attr_reader name: String
            attr_writer age: Integer
            attr_accessor admin: bool
          end
        RBS
      end

      it 'extracts attribute members from container declarations' do
        statement = analysis.statements.first

        expect(statement.name).to eq('Foo')
        expect(statement.members.size).to eq(3)
        expect(statement.members.map(&:canonical_type)).to eq(%i[attr_reader attr_writer attr_accessor])
        expect(statement.members.map(&:name)).to eq(%w[name age admin])
        expect(statement.members.map(&:signature)).to eq([
                                                           [:attr_reader, 'name'],
                                                           [:attr_writer, 'age'],
                                                           [:attr_accessor, 'admin']
                                                         ])
      end
    end
  end

  shared_examples 'nested alias member extraction' do
    describe 'nested alias member extraction' do
      subject(:analysis) { described_class.new(alias_source) }

      let(:alias_source) do
        <<~RBS
          class Foo
            alias new_name old_name
          end
        RBS
      end

      it 'extracts alias members from container declarations' do
        statement = analysis.statements.first

        expect(statement.name).to eq('Foo')
        expect(statement.members.size).to eq(1)

        member = statement.members.first
        expect(member.canonical_type).to eq(:alias)
        expect(member.name).to eq('new_name')
        expect(member.alias_new_name).to eq('new_name')
        expect(member.alias_old_name).to eq('old_name')
        expect(member.signature).to eq([:alias, 'new_name', 'old_name'])
      end
    end
  end

  shared_examples 'nested variable member extraction' do
    describe 'nested variable member extraction' do
      subject(:analysis) { described_class.new(variable_source) }

      let(:variable_source) do
        <<~RBS
          class Foo
            @ivar: String
            self.@civar: Integer
            @@cvar: bool
          end
        RBS
      end

      it 'extracts ivar, civar, and cvar members from container declarations' do
        statement = analysis.statements.first

        expect(statement.name).to eq('Foo')
        expect(statement.members.size).to eq(3)
        expect(statement.members.map(&:canonical_type)).to eq(%i[ivar civar cvar])
        expect(statement.members.map(&:name)).to eq(['@ivar', '@civar', '@@cvar'])
        expect(statement.members.map(&:signature)).to eq([
                                                           [:ivar, '@ivar'],
                                                           [:civar, '@civar'],
                                                           [:cvar, '@@cvar']
                                                         ])
      end
    end
  end

  shared_examples 'nested singleton method extraction' do
    describe 'nested singleton method extraction' do
      subject(:analysis) { described_class.new(method_source) }

      let(:method_source) do
        <<~RBS
          class Foo
            def self.build: () -> String
            def instance_call: () -> Integer
          end
        RBS
      end

      it 'distinguishes singleton and instance method kinds inside container declarations' do
        statement = analysis.statements.first

        expect(statement.name).to eq('Foo')
        expect(statement.members.map(&:name)).to eq(%w[build instance_call])
        expect(statement.members.map(&:method_kind)).to eq(%i[singleton instance])
        expect(statement.members.map(&:signature)).to eq([
                                                           [:method, 'build', :singleton],
                                                           [:method, 'instance_call', :instance]
                                                         ])
      end
    end
  end

  shared_examples 'nested visibility member extraction' do
    describe 'nested visibility member extraction' do
      subject(:analysis) { described_class.new(visibility_source) }

      let(:visibility_source) do
        <<~RBS
          class Foo
            public
            def visible: () -> String
            private
            def hidden: () -> Integer
          end
        RBS
      end

      it 'extracts stable public/private visibility members from container declarations' do
        statement = analysis.statements.first

        expect(statement.name).to eq('Foo')
        expect(statement.members.map(&:canonical_type)).to eq(%i[visibility method visibility method])
        expect(statement.members.map(&:name)).to eq(%w[public visible private hidden])
        expect(statement.members.select(&:visibility?).map(&:visibility_kind)).to eq(%i[public private])
        expect(statement.members.map(&:signature)).to eq([
                                                           %i[visibility public],
                                                           [:method, 'visible', :instance],
                                                           %i[visibility private],
                                                           [:method, 'hidden', :instance]
                                                         ])
      end
    end
  end

  shared_examples 'nested mixin member extraction' do
    describe 'nested mixin member extraction' do
      subject(:analysis) { described_class.new(mixin_source) }

      let(:mixin_source) do
        <<~RBS
          class Foo
            include Enumerable[String]
            extend Kernel
            prepend Decorator
          end
        RBS
      end

      it 'extracts stable include/extend/prepend members from container declarations' do
        statement = analysis.statements.first

        expect(statement.name).to eq('Foo')
        expect(statement.members.map(&:canonical_type)).to eq(%i[include extend prepend])
        expect(statement.members.map(&:name)).to eq(%w[Enumerable Kernel Decorator])
        expect(statement.members.map(&:signature)).to eq([
                                                           [:include, 'Enumerable'],
                                                           [:extend, 'Kernel'],
                                                           [:prepend, 'Decorator']
                                                         ])
      end
    end
  end

  shared_examples 'freeze blocks' do
    describe 'with freeze blocks' do
      subject(:analysis) { described_class.new(source_with_freeze) }

      let(:source_with_freeze) do
        <<~RBS
          class Foo
            def foo: () -> void
          end

          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze

          class Bar
            def bar: () -> void
          end
        RBS
      end

      it 'detects freeze blocks' do
        expect(analysis.freeze_blocks.size).to eq(1)
      end

      it 'extracts freeze block content' do
        freeze_block = analysis.freeze_blocks.first
        expect(freeze_block.start_line).to eq(5)
        expect(freeze_block.end_line).to eq(7)
      end

      it 'includes freeze blocks in statements' do
        # Should have: Foo class, freeze block, Bar class
        freeze_nodes = analysis.statements.select { |s| s.is_a?(Rbs::Merge::FreezeNode) }
        expect(freeze_nodes.size).to eq(1)
      end
    end
  end

  shared_examples 'freeze-contained declaration signatures' do
    describe 'with freeze-contained top-level declarations' do
      subject(:analysis) { described_class.new(source_with_frozen_declarations) }

      let(:source_with_frozen_declarations) do
        <<~RBS
          # rbs-merge:freeze
          type custom = String
          class Foo = Bar
          module Baz = Quux
          # rbs-merge:unfreeze
        RBS
      end

      it 'keeps stable signatures for contained declarations inside the freeze block' do
        freeze_block = analysis.freeze_blocks.first

        expect(freeze_block.nodes.map { |node| analysis.generate_signature(node) }).to eq([
                                                                                            [:type_alias, 'custom'],
                                                                                            [:class_alias, 'Foo'],
                                                                                            [:module_alias, 'Baz']
                                                                                          ])
      end
    end
  end

  shared_examples 'default freeze token comment filtering' do
    describe 'with default freeze token markers before a declaration' do
      subject(:analysis) { described_class.new(source_with_default_token) }

      let(:source_with_default_token) do
        <<~RBS
          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze

          class Foo
          end
        RBS
      end

      it 'keeps default-token freeze markers out of tracked comments and following declaration attachments' do
        owner = analysis.statements.find do |statement|
          statement.respond_to?(:canonical_type) && statement.canonical_type == :class
        end

        expect(analysis.comment_nodes).to be_empty
        expect(analysis.comment_attachment_for(owner).leading_region).to be_nil
      end

      it 'keeps reason-bearing default-token freeze markers out of tracked comments and following declaration attachments' do
        analysis_with_reason = described_class.new(<<~RBS)
          # rbs-merge:freeze keep local customization
          type custom = String
          # rbs-merge:unfreeze resume normal merge

          class Foo
          end
        RBS

        owner = analysis_with_reason.statements.find do |statement|
          statement.respond_to?(:canonical_type) && statement.canonical_type == :class
        end

        expect(analysis_with_reason.comment_nodes).to be_empty
        expect(analysis_with_reason.comment_attachment_for(owner).leading_region).to be_nil
      end

      it 'attaches docs immediately above a reason-bearing freeze marker to the freeze block' do
        analysis_with_reason_and_docs = described_class.new(<<~RBS)
          # keep freeze docs
          # rbs-merge:freeze keep local customization
          type custom = String
          # rbs-merge:unfreeze resume normal merge

          class Foo
          end
        RBS

        freeze_block = analysis_with_reason_and_docs.freeze_blocks.first
        owner = analysis_with_reason_and_docs.statements.find do |statement|
          statement.respond_to?(:canonical_type) && statement.canonical_type == :class
        end

        expect(analysis_with_reason_and_docs.comment_nodes.map(&:text)).to eq(['# keep freeze docs'])
        expect(analysis_with_reason_and_docs.comment_attachment_for(freeze_block).leading_region&.normalized_content).to eq('keep freeze docs')
        expect(analysis_with_reason_and_docs.comment_attachment_for(owner).leading_region).to be_nil
      end
    end
  end

  shared_examples 'freeze block leading docs ownership' do
    describe 'with docs immediately above a freeze block' do
      subject(:analysis) { described_class.new(source_with_documented_freeze_block) }

      let(:source_with_documented_freeze_block) do
        <<~RBS
          # keep freeze docs
          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze

          class Foo
          end
        RBS
      end

      it 'attaches the leading docs to the freeze block, not the following declaration' do
        freeze_block = analysis.freeze_blocks.first
        following_class = analysis.statements.find do |statement|
          statement.respond_to?(:canonical_type) && statement.canonical_type == :class
        end

        expect(analysis.comment_nodes.map(&:text)).to eq(['# keep freeze docs'])
        expect(analysis.comment_attachment_for(freeze_block).leading_region&.normalized_content).to eq('keep freeze docs')
        expect(analysis.comment_attachment_for(following_class).leading_region).to be_nil
      end
    end
  end

  shared_examples 'custom freeze token' do
    describe 'with custom freeze token' do
      subject(:analysis) { described_class.new(source_with_custom_token, freeze_token: 'my-token') }

      let(:source_with_custom_token) do
        <<~RBS
          # my-token:freeze
          type custom = String
          # my-token:unfreeze

          class Foo
          end
        RBS
      end

      it 'recognizes the custom token' do
        expect(analysis.freeze_blocks.size).to eq(1)
      end

      it 'keeps custom-token freeze markers out of tracked comments and following declaration attachments' do
        owner = analysis.statements.find do |statement|
          statement.respond_to?(:canonical_type) && statement.canonical_type == :class
        end

        expect(analysis.comment_nodes).to be_empty
        expect(analysis.comment_attachment_for(owner).leading_region).to be_nil
      end

      it 'keeps reason-bearing custom-token freeze markers out of tracked comments and following declaration attachments' do
        analysis_with_reason = described_class.new(<<~RBS, freeze_token: 'my-token')
          # my-token:freeze keep local customization
          type custom = String
          # my-token:unfreeze resume normal merge

          class Foo
          end
        RBS

        owner = analysis_with_reason.statements.find do |statement|
          statement.respond_to?(:canonical_type) && statement.canonical_type == :class
        end

        expect(analysis_with_reason.comment_nodes).to be_empty
        expect(analysis_with_reason.comment_attachment_for(owner).leading_region).to be_nil
      end

      it 'attaches docs immediately above a custom-token freeze marker to the freeze block' do
        documented_analysis = described_class.new(<<~RBS, freeze_token: 'my-token')
          # keep custom freeze docs
          # my-token:freeze
          type custom = String
          # my-token:unfreeze

          class Foo
          end
        RBS

        freeze_block = documented_analysis.freeze_blocks.first
        owner = documented_analysis.statements.find do |statement|
          statement.respond_to?(:canonical_type) && statement.canonical_type == :class
        end

        expect(documented_analysis.comment_nodes.map(&:text)).to eq(['# keep custom freeze docs'])
        expect(documented_analysis.comment_attachment_for(freeze_block).leading_region&.normalized_content).to eq('keep custom freeze docs')
        expect(documented_analysis.comment_attachment_for(owner).leading_region).to be_nil
      end

      it 'attaches docs immediately above a reason-bearing custom-token freeze marker to the freeze block' do
        documented_analysis = described_class.new(<<~RBS, freeze_token: 'my-token')
          # keep custom freeze docs
          # my-token:freeze keep local customization
          type custom = String
          # my-token:unfreeze resume normal merge

          class Foo
          end
        RBS

        freeze_block = documented_analysis.freeze_blocks.first
        owner = documented_analysis.statements.find do |statement|
          statement.respond_to?(:canonical_type) && statement.canonical_type == :class
        end

        expect(documented_analysis.comment_nodes.map(&:text)).to eq(['# keep custom freeze docs'])
        expect(documented_analysis.comment_attachment_for(freeze_block).leading_region&.normalized_content).to eq('keep custom freeze docs')
        expect(documented_analysis.comment_attachment_for(owner).leading_region).to be_nil
      end
    end
  end

  shared_examples 'fallthrough_node? behavior' do
    describe '#fallthrough_node?' do
      subject(:analysis) { described_class.new(valid_source) }

      let(:valid_source) { "class Foo\nend" }

      it 'returns true for NodeWrapper instances' do
        wrapper = analysis.statements.first
        expect(analysis.fallthrough_node?(wrapper)).to be true
      end

      it 'returns false for other objects' do
        expect(analysis.fallthrough_node?('string')).to be false
        expect(analysis.fallthrough_node?(123)).to be false
      end
    end
  end

  shared_examples 'line_at access' do
    describe '#line_at' do
      subject(:analysis) { described_class.new(multiline_source) }

      let(:multiline_source) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end

      it 'returns line at valid index (1-based)' do
        line = analysis.line_at(1)
        expect(line).to eq('class Foo')
      end

      it 'returns nil for invalid index' do
        line = analysis.line_at(100)
        expect(line).to be_nil
      end

      it 'returns nil for zero index' do
        line = analysis.line_at(0)
        expect(line).to be_nil
      end
    end
  end

  shared_examples 'shared comment capability' do
    describe 'shared comment capability' do
      subject(:analysis) { described_class.new(commented_source) }

      let(:commented_source) do
        <<~RBS
          # preamble docs

          class Foo
          end

          # postlude docs
        RBS
      end

      it 'exposes shared comment nodes and line lookup' do
        expect(analysis.comment_nodes.map(&:line_number)).to eq([1, 6])
        expect(analysis.comment_node_at(1)&.text).to include('preamble')
      end

      it 'builds declaration attachments and document boundary regions' do
        owner = analysis.statements.first
        attachment = analysis.comment_attachment_for(owner)

        # Line-1 comment separated by a gap is preamble, not owned by the first node
        expect(attachment.leading_region).to be_nil

        augmenter = analysis.comment_augmenter(owners: analysis.statements)
        expect(augmenter.preamble_region).not_to be_nil
        expect(augmenter.preamble_region.nodes.map(&:line_number)).to eq([1])
        expect(augmenter.postlude_region.nodes.map(&:line_number)).to eq([6])
      end

      it 'reports a source-augmented synthetic support style' do
        expect(analysis.comment_support_style).to be_a(Ast::Merge::Comment::SupportStyle)
        expect(analysis.comment_support_style.source_augmented_portable_write?).to be true
        expect(analysis.comment_support_style.portable_write?).to be true
        expect(analysis.comment_support_style.details[:capability]).to eq(:source_augmented)
        expect(analysis.comment_support_style.details[:source]).to eq(:rbs_source)
        expect(analysis.comment_support_style.details[:style]).to eq(:hash_comment)
      end
    end
  end

  shared_examples 'shared layout compliance' do
    describe 'shared layout compliance' do
      subject(:analysis) { described_class.new(layout_source) }

      let(:layout_source) do
        <<~RBS

          class Foo
          end

          module Bar
          end

        RBS
      end

      let(:first_owner) { analysis.statements.first }
      let(:second_owner) { analysis.statements[1] }
      let(:layout_augmenter) { analysis.layout_augmenter(owners: [first_owner, second_owner].compact) }
      let(:layout_attachment) { layout_augmenter.attachment_for(first_owner) }

      it 'finds stable top-level declaration owners for layout inference' do
        expect(first_owner).not_to be_nil
        expect(second_owner).not_to be_nil
        expect(first_owner.canonical_type).to eq(:class)
        expect(second_owner.canonical_type).to eq(:module)
      end

      it_behaves_like 'Ast::Merge::Layout::Attachment' do
        let(:expected_attachment_owner) { first_owner }
        let(:expected_leading_gap_kind) { :preamble }
        let(:expected_trailing_gap_kind) { :interstitial }
        let(:expected_gap_ranges) { [1..1, 4..4] }
        let(:expected_leading_controls_output) { true }
        let(:expected_trailing_controls_output) { false }
      end

      it_behaves_like 'Ast::Merge::Layout::Augmenter' do
        let(:augmenter_owner) { first_owner }
        let(:expected_preamble_range) { 1..1 }
        let(:expected_postlude_range) { 7..8 }
        let(:expected_interstitial_ranges) { [4..4] }
        let(:expected_owner_leading_gap_kind) { :preamble }
        let(:expected_owner_trailing_gap_kind) { :interstitial }
      end

      it 'surfaces inferred layout gaps on comment attachments' do
        attachment = analysis.comment_attachment_for(first_owner)

        expect(attachment.leading_gap&.kind).to eq(:preamble)
        expect(attachment.trailing_gap&.kind).to eq(:interstitial)
      end
    end
  end

  # ============================================================
  # :auto backend tests (uses whatever is available)
  # This tests the default behavior most users will experience
  # ============================================================

  context 'with :auto backend', :rbs_parsing do
    # With :auto, we don't know which backend will be used, so we can't
    # assert the specific backend. We test that it works regardless.
    describe 'with valid RBS' do
      subject(:analysis) { described_class.new(valid_source) }

      let(:valid_source) do
        <<~RBS
          class Foo
            def bar: (String) -> Integer
          end
        RBS
      end

      it 'parses successfully' do
        expect(analysis).to be_a(described_class)
      end

      it 'is valid' do
        expect(analysis.valid?).to be true
      end

      it 'has no errors' do
        expect(analysis.errors).to be_empty
      end

      it 'uses either :rbs or :tree_sitter backend' do
        expect(analysis.backend).to eq(:rbs).or eq(:tree_sitter)
      end
    end

    it_behaves_like 'invalid RBS detection'
    it_behaves_like 'multiple declarations'
    it_behaves_like 'alias declaration extraction'
    it_behaves_like 'alias wrapper location/text parity'
    it_behaves_like 'type alias declaration extraction'
    it_behaves_like 'interface declaration extraction'
    it_behaves_like 'module declaration extraction'
    it_behaves_like 'class declaration extraction'
    it_behaves_like 'class wrapper location/text parity'
    it_behaves_like 'module wrapper location/text parity'
    it_behaves_like 'interface wrapper location/text parity'
    it_behaves_like 'type alias wrapper location/text parity'
    it_behaves_like 'constant wrapper location/text parity'
    it_behaves_like 'global wrapper location/text parity'
    it_behaves_like 'constant declaration extraction'
    it_behaves_like 'global declaration extraction'
    it_behaves_like 'signature generation'
    it_behaves_like 'nested overloaded member extraction'
    it_behaves_like 'nested attribute member extraction'
    it_behaves_like 'nested alias member extraction'
    it_behaves_like 'nested variable member extraction'
    it_behaves_like 'nested singleton method extraction'
    it_behaves_like 'nested visibility member extraction'
    it_behaves_like 'nested mixin member extraction'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'freeze-contained declaration signatures'
    it_behaves_like 'default freeze token comment filtering'
    it_behaves_like 'freeze block leading docs ownership'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'line_at access'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'shared layout compliance'
  end

  # ============================================================
  # Explicit RBS gem backend tests (MRI only)
  # ============================================================

  context 'with explicit RBS gem backend', :rbs_backend do
    around do |example|
      TreeHaver.with_backend(:rbs) do
        example.run
      end
    end

    it_behaves_like 'valid RBS parsing', expected_backend: :rbs
    it_behaves_like 'invalid RBS detection'
    it_behaves_like 'multiple declarations'
    it_behaves_like 'alias declaration extraction'
    it_behaves_like 'alias wrapper location/text parity'
    it_behaves_like 'type alias declaration extraction'
    it_behaves_like 'interface declaration extraction'
    it_behaves_like 'module declaration extraction'
    it_behaves_like 'class declaration extraction'
    it_behaves_like 'class wrapper location/text parity'
    it_behaves_like 'module wrapper location/text parity'
    it_behaves_like 'interface wrapper location/text parity'
    it_behaves_like 'type alias wrapper location/text parity'
    it_behaves_like 'constant wrapper location/text parity'
    it_behaves_like 'global wrapper location/text parity'
    it_behaves_like 'constant declaration extraction'
    it_behaves_like 'global declaration extraction'
    it_behaves_like 'signature generation'
    it_behaves_like 'nested overloaded member extraction'
    it_behaves_like 'nested attribute member extraction'
    it_behaves_like 'nested alias member extraction'
    it_behaves_like 'nested variable member extraction'
    it_behaves_like 'nested singleton method extraction'
    it_behaves_like 'nested visibility member extraction'
    it_behaves_like 'nested mixin member extraction'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'freeze-contained declaration signatures'
    it_behaves_like 'default freeze token comment filtering'
    it_behaves_like 'freeze block leading docs ownership'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'line_at access'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'shared layout compliance'

    # RBS gem specific tests
    describe 'RBS gem specific features' do
      subject(:analysis) { described_class.new(source_with_comments) }

      let(:source_with_comments) do
        <<~RBS
          # A sample class
          class Foo
            # A method
            def bar: (String) -> Integer
          end
        RBS
      end

      it 'has directives array (even if empty)' do
        expect(analysis.directives).to be_an(Array)
      end
    end
  end

  # ============================================================
  # Explicit tree-sitter backend tests (MRI with tree-sitter-rbs)
  # Uses :mri_backend tag because this context uses tree-sitter on the MRI platform
  # ============================================================

  context 'with explicit tree-sitter backend via MRI', :mri_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    it_behaves_like 'valid RBS parsing', expected_backend: :tree_sitter
    it_behaves_like 'invalid RBS detection'
    it_behaves_like 'multiple declarations'
    it_behaves_like 'alias declaration extraction'
    it_behaves_like 'alias wrapper location/text parity'
    it_behaves_like 'type alias declaration extraction'
    it_behaves_like 'interface declaration extraction'
    it_behaves_like 'module declaration extraction'
    it_behaves_like 'class declaration extraction'
    it_behaves_like 'class wrapper location/text parity'
    it_behaves_like 'module wrapper location/text parity'
    it_behaves_like 'interface wrapper location/text parity'
    it_behaves_like 'type alias wrapper location/text parity'
    it_behaves_like 'constant wrapper location/text parity'
    it_behaves_like 'global wrapper location/text parity'
    it_behaves_like 'constant declaration extraction'
    it_behaves_like 'global declaration extraction'
    it_behaves_like 'signature generation'
    it_behaves_like 'nested overloaded member extraction'
    it_behaves_like 'nested attribute member extraction'
    it_behaves_like 'nested alias member extraction'
    it_behaves_like 'nested variable member extraction'
    it_behaves_like 'nested singleton method extraction'
    it_behaves_like 'nested visibility member extraction'
    it_behaves_like 'nested mixin member extraction'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'freeze-contained declaration signatures'
    it_behaves_like 'default freeze token comment filtering'
    it_behaves_like 'freeze block leading docs ownership'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'line_at access'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'shared layout compliance'
  end

  # ============================================================
  # Explicit Java backend tests
  # ============================================================

  context 'with explicit Java backend', :java_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    it_behaves_like 'valid RBS parsing', expected_backend: :tree_sitter
    it_behaves_like 'invalid RBS detection'
    it_behaves_like 'multiple declarations'
    it_behaves_like 'alias declaration extraction'
    it_behaves_like 'type alias declaration extraction'
    it_behaves_like 'interface declaration extraction'
    it_behaves_like 'module declaration extraction'
    it_behaves_like 'class declaration extraction'
    it_behaves_like 'class wrapper location/text parity'
    it_behaves_like 'module wrapper location/text parity'
    it_behaves_like 'interface wrapper location/text parity'
    it_behaves_like 'type alias wrapper location/text parity'
    it_behaves_like 'constant wrapper location/text parity'
    it_behaves_like 'global wrapper location/text parity'
    it_behaves_like 'constant declaration extraction'
    it_behaves_like 'global declaration extraction'
    it_behaves_like 'signature generation'
    it_behaves_like 'nested overloaded member extraction'
    it_behaves_like 'nested attribute member extraction'
    it_behaves_like 'nested alias member extraction'
    it_behaves_like 'nested variable member extraction'
    it_behaves_like 'nested singleton method extraction'
    it_behaves_like 'nested visibility member extraction'
    it_behaves_like 'nested mixin member extraction'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'freeze-contained declaration signatures'
    it_behaves_like 'default freeze token comment filtering'
    it_behaves_like 'freeze block leading docs ownership'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'line_at access'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'shared layout compliance'
  end

  # ============================================================
  # Explicit Rust backend tests (tree-sitter via rust bindings)
  # ============================================================

  context 'with explicit Rust backend', :rbs_grammar, :rust_backend do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    it_behaves_like 'valid RBS parsing', expected_backend: :tree_sitter
    it_behaves_like 'invalid RBS detection'
    it_behaves_like 'multiple declarations'
    it_behaves_like 'alias declaration extraction'
    it_behaves_like 'alias wrapper location/text parity'
    it_behaves_like 'type alias declaration extraction'
    it_behaves_like 'interface declaration extraction'
    it_behaves_like 'module declaration extraction'
    it_behaves_like 'class declaration extraction'
    it_behaves_like 'class wrapper location/text parity'
    it_behaves_like 'module wrapper location/text parity'
    it_behaves_like 'interface wrapper location/text parity'
    it_behaves_like 'type alias wrapper location/text parity'
    it_behaves_like 'constant wrapper location/text parity'
    it_behaves_like 'global wrapper location/text parity'
    it_behaves_like 'constant declaration extraction'
    it_behaves_like 'global declaration extraction'
    it_behaves_like 'signature generation'
    it_behaves_like 'nested overloaded member extraction'
    it_behaves_like 'nested attribute member extraction'
    it_behaves_like 'nested alias member extraction'
    it_behaves_like 'nested variable member extraction'
    it_behaves_like 'nested singleton method extraction'
    it_behaves_like 'nested visibility member extraction'
    it_behaves_like 'nested mixin member extraction'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'freeze-contained declaration signatures'
    it_behaves_like 'default freeze token comment filtering'
    it_behaves_like 'freeze block leading docs ownership'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'line_at access'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'shared layout compliance'
  end

  # ============================================================
  # Explicit FFI backend tests (tree-sitter via FFI)
  # ============================================================

  context 'with explicit FFI backend', :ffi_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    it_behaves_like 'valid RBS parsing', expected_backend: :tree_sitter
    it_behaves_like 'invalid RBS detection'
    it_behaves_like 'multiple declarations'
    it_behaves_like 'alias declaration extraction'
    it_behaves_like 'alias wrapper location/text parity'
    it_behaves_like 'type alias declaration extraction'
    it_behaves_like 'interface declaration extraction'
    it_behaves_like 'module declaration extraction'
    it_behaves_like 'class declaration extraction'
    it_behaves_like 'class wrapper location/text parity'
    it_behaves_like 'module wrapper location/text parity'
    it_behaves_like 'interface wrapper location/text parity'
    it_behaves_like 'type alias wrapper location/text parity'
    it_behaves_like 'constant wrapper location/text parity'
    it_behaves_like 'global wrapper location/text parity'
    it_behaves_like 'constant declaration extraction'
    it_behaves_like 'global declaration extraction'
    it_behaves_like 'signature generation'
    it_behaves_like 'nested overloaded member extraction'
    it_behaves_like 'nested attribute member extraction'
    it_behaves_like 'nested alias member extraction'
    it_behaves_like 'nested variable member extraction'
    it_behaves_like 'nested singleton method extraction'
    it_behaves_like 'nested visibility member extraction'
    it_behaves_like 'nested mixin member extraction'
    it_behaves_like 'freeze blocks'
    it_behaves_like 'freeze-contained declaration signatures'
    it_behaves_like 'default freeze token comment filtering'
    it_behaves_like 'freeze block leading docs ownership'
    it_behaves_like 'custom freeze token'
    it_behaves_like 'fallthrough_node? behavior'
    it_behaves_like 'line_at access'
    it_behaves_like 'shared comment capability'
    it_behaves_like 'shared layout compliance'
  end
end
