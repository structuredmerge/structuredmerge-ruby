# frozen_string_literal: true

require 'spec_helper'

# SmartMerger specs with explicit backend testing
#
# This spec file tests SmartMerger behavior across both available backends:
# - :rbs (via RBS gem, tagged :rbs_backend)
# - :tree_sitter (via tree-sitter-rbs grammar, tagged :rbs_grammar)
#
# We define shared examples that are parameterized, then include them in
# backend-specific contexts.

RSpec.describe Rbs::Merge::SmartMerger do
  let(:template_content) do
    <<~RBS
      class Foo
        def bar: (String) -> Integer
      end
    RBS
  end

  let(:dest_content) do
    <<~RBS
      class Foo
        def bar: (Integer) -> String
        def baz: () -> void
      end
    RBS
  end

  # ============================================================
  # Shared examples for error detection
  # ============================================================

  # ============================================================
  # Shared examples for parse error handling
  # Note: Strict error detection depends on the parser - RBS gem
  # reports errors more strictly than some tree-sitter backends
  # ============================================================

  shared_examples 'invalid template detection' do
    let(:invalid_template) do
      <<~RBS
        class Foo
          def bar: (
        end
      RBS
    end

    it 'raises TemplateParseError', :rbs_backend do
      expect do
        described_class.new(invalid_template, dest_content)
      end.to raise_error(Rbs::Merge::TemplateParseError)
    end
  end

  shared_examples 'invalid destination detection' do
    let(:invalid_dest) do
      <<~RBS
        class Bar
          def baz: (
        end
      RBS
    end

    it 'raises DestinationParseError', :rbs_backend do
      expect do
        described_class.new(template_content, invalid_dest)
      end.to raise_error(Rbs::Merge::DestinationParseError)
    end
  end

  # ============================================================
  # Shared examples for basic functionality
  # ============================================================

  shared_examples 'basic initialization' do
    it 'accepts template and destination content' do
      merger = described_class.new(template_content, dest_content)
      expect(merger).to be_a(described_class)
    end

    it 'has template_analysis' do
      merger = described_class.new(template_content, dest_content)
      expect(merger.template_analysis).to be_a(Rbs::Merge::FileAnalysis)
    end

    it 'has dest_analysis' do
      merger = described_class.new(template_content, dest_content)
      expect(merger.dest_analysis).to be_a(Rbs::Merge::FileAnalysis)
    end

    it 'accepts optional preference' do
      merger = described_class.new(template_content, dest_content, preference: :template)
      expect(merger.preference).to eq(:template)
    end
  end

  shared_examples 'merge with identical files' do
    context 'with identical files' do
      let(:identical_content) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end

      it 'returns content unchanged' do
        merger = described_class.new(identical_content, identical_content)
        result = merger.merge
        expect(result).to eq(identical_content)
      end
    end
  end

  shared_examples 'merge with added declarations' do
    context 'when destination has additional declarations' do
      let(:template_simple) do
        <<~RBS
          class Foo
            def foo: () -> void
          end
        RBS
      end

      let(:dest_with_extra) do
        <<~RBS
          class Foo
            def foo: () -> void
          end

          class Bar
            def bar: () -> void
          end
        RBS
      end

      it 'preserves destination additions' do
        merger = described_class.new(template_simple, dest_with_extra)
        result = merger.merge
        expect(result).to include('class Bar')
        expect(result).to include('def bar')
      end
    end
  end

  shared_examples 'retained declaration blank line preservation' do
    context 'when destination-owned top-level declarations are separated by blank lines' do
      let(:template_top_level) do
        <<~RBS
          class Foo
          end

          class Bar
          end
        RBS
      end

      let(:destination_top_level) do
        <<~RBS
          class Foo
          end

          class Bar
          end
        RBS
      end

      it 'preserves the destination-owned blank line between retained declarations' do
        merger = described_class.new(template_top_level, destination_top_level)

        expect(merger.merge).to eq(destination_top_level)
      end
    end
  end

  shared_examples 'merge with freeze blocks' do
    context 'with freeze blocks' do
      let(:template_with_freeze) do
        <<~RBS
          # rbs-merge:freeze
          class Frozen
            def frozen_method: () -> void
          end
          # rbs-merge:unfreeze

          class Normal
            def normal_method: () -> void
          end
        RBS
      end

      let(:dest_modified) do
        <<~RBS
          class Frozen
            def modified_method: () -> void
          end

          class Normal
            def other_method: () -> void
          end
        RBS
      end

      it 'preserves frozen content from template' do
        merger = described_class.new(template_with_freeze, dest_modified)
        result = merger.merge
        expect(result).to include('frozen_method')
      end
    end

    context 'when the destination freezes a documented type alias' do
      let(:template_with_type_alias) do
        <<~RBS
          type custom = Integer
        RBS
      end

      let(:destination_with_frozen_type_alias) do
        <<~RBS
          # rbs-merge:freeze
          # keep frozen docs
          type custom = String
          # rbs-merge:unfreeze
        RBS
      end

      it 'keeps the destination freeze block intact without duplicating the matched type alias' do
        merger = described_class.new(template_with_type_alias, destination_with_frozen_type_alias)

        expect(merger.merge).to eq(<<~RBS)
          # rbs-merge:freeze
          # keep frozen docs
          type custom = String
          # rbs-merge:unfreeze
        RBS
      end
    end

    context 'when the destination freezes documented alias declarations' do
      let(:template_with_aliases) do
        <<~RBS
          class Foo = Bar
          module Baz = Quux
        RBS
      end

      let(:destination_with_frozen_aliases) do
        <<~RBS
          # rbs-merge:freeze
          # keep alias docs
          class Foo = CustomBar
          module Baz = CustomQuux
          # rbs-merge:unfreeze
        RBS
      end

      it 'keeps the destination frozen alias block intact without duplicating matched aliases' do
        merger = described_class.new(template_with_aliases, destination_with_frozen_aliases)

        expect(merger.merge).to eq(<<~RBS)
          # rbs-merge:freeze
          # keep alias docs
          class Foo = CustomBar
          module Baz = CustomQuux
          # rbs-merge:unfreeze
        RBS
      end
    end

    context 'when a matched declaration immediately follows a frozen destination block' do
      let(:template_with_following_class) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:destination_with_frozen_block_before_class) do
        <<~RBS
          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze
          class Foo
          end
        RBS
      end

      it "does not leak freeze markers into the following declaration's leading docs" do
        merger = described_class.new(
          template_with_following_class,
          destination_with_frozen_block_before_class,
          preference: :template
        )

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end
          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze
        RBS
      end
    end

    context 'when a frozen destination block has docs immediately above its marker' do
      let(:template_with_following_class) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:destination_with_documented_frozen_block_before_class) do
        <<~RBS
          # keep freeze docs
          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze
          class Foo
          end
        RBS
      end

      it "preserves the freeze block's leading docs with the block" do
        merger = described_class.new(
          template_with_following_class,
          destination_with_documented_frozen_block_before_class,
          preference: :template
        )

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end
          # keep freeze docs
          # rbs-merge:freeze
          type custom = String
          # rbs-merge:unfreeze
        RBS
      end
    end

    context 'when a matched declaration immediately follows a custom-token frozen destination block' do
      let(:template_with_following_class) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:destination_with_custom_token_frozen_block_before_class) do
        <<~RBS
          # custom-token:freeze
          type custom = String
          # custom-token:unfreeze
          class Foo
          end
        RBS
      end

      it "does not leak custom freeze markers into the following declaration's leading docs" do
        merger = described_class.new(
          template_with_following_class,
          destination_with_custom_token_frozen_block_before_class,
          preference: :template,
          freeze_token: 'custom-token'
        )

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end
          # custom-token:freeze
          type custom = String
          # custom-token:unfreeze
        RBS
      end
    end

    context 'when a custom-token frozen destination block has docs immediately above its marker' do
      let(:template_with_following_class) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:destination_with_documented_custom_token_frozen_block_before_class) do
        <<~RBS
          # keep custom freeze docs
          # custom-token:freeze
          type custom = String
          # custom-token:unfreeze
          class Foo
          end
        RBS
      end

      it "preserves the custom-token freeze block's leading docs with the block" do
        merger = described_class.new(
          template_with_following_class,
          destination_with_documented_custom_token_frozen_block_before_class,
          preference: :template,
          freeze_token: 'custom-token'
        )

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end
          # keep custom freeze docs
          # custom-token:freeze
          type custom = String
          # custom-token:unfreeze
        RBS
      end
    end

    context 'when a matched declaration immediately follows a reason-bearing frozen destination block' do
      let(:template_with_following_class) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:destination_with_reason_bearing_frozen_block_before_class) do
        <<~RBS
          # rbs-merge:freeze keep local customization
          type custom = String
          # rbs-merge:unfreeze resume normal merge
          class Foo
          end
        RBS
      end

      it "does not leak reason-bearing freeze markers into the following declaration's leading docs" do
        merger = described_class.new(
          template_with_following_class,
          destination_with_reason_bearing_frozen_block_before_class,
          preference: :template
        )

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end
          # rbs-merge:freeze keep local customization
          type custom = String
          # rbs-merge:unfreeze resume normal merge
        RBS
      end
    end

    context 'when a reason-bearing frozen destination block has docs immediately above its marker' do
      let(:template_with_following_class) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:destination_with_documented_reason_bearing_frozen_block_before_class) do
        <<~RBS
          # keep freeze docs
          # rbs-merge:freeze keep local customization
          type custom = String
          # rbs-merge:unfreeze resume normal merge
          class Foo
          end
        RBS
      end

      it "preserves the reason-bearing freeze block's leading docs with the block" do
        merger = described_class.new(
          template_with_following_class,
          destination_with_documented_reason_bearing_frozen_block_before_class,
          preference: :template
        )

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end
          # keep freeze docs
          # rbs-merge:freeze keep local customization
          type custom = String
          # rbs-merge:unfreeze resume normal merge
        RBS
      end
    end

    context 'when a matched declaration immediately follows a reason-bearing custom-token frozen destination block' do
      let(:template_with_following_class) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:destination_with_reason_bearing_custom_token_frozen_block_before_class) do
        <<~RBS
          # custom-token:freeze keep local customization
          type custom = String
          # custom-token:unfreeze resume normal merge
          class Foo
          end
        RBS
      end

      it "does not leak reason-bearing custom freeze markers into the following declaration's leading docs" do
        merger = described_class.new(
          template_with_following_class,
          destination_with_reason_bearing_custom_token_frozen_block_before_class,
          preference: :template,
          freeze_token: 'custom-token'
        )

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end
          # custom-token:freeze keep local customization
          type custom = String
          # custom-token:unfreeze resume normal merge
        RBS
      end
    end

    context 'when a reason-bearing custom-token frozen destination block has docs immediately above its marker' do
      let(:template_with_following_class) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:destination_with_documented_reason_bearing_custom_token_frozen_block_before_class) do
        <<~RBS
          # keep custom freeze docs
          # custom-token:freeze keep local customization
          type custom = String
          # custom-token:unfreeze resume normal merge
          class Foo
          end
        RBS
      end

      it "preserves the reason-bearing custom-token freeze block's leading docs with the block" do
        merger = described_class.new(
          template_with_following_class,
          destination_with_documented_reason_bearing_custom_token_frozen_block_before_class,
          preference: :template,
          freeze_token: 'custom-token'
        )

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end
          # keep custom freeze docs
          # custom-token:freeze keep local customization
          type custom = String
          # custom-token:unfreeze resume normal merge
        RBS
      end
    end
  end

  shared_examples 'template-preferred declaration-leading comment fallback' do
    context 'when the destination owns declaration-leading docs' do
      let(:commented_template) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:commented_destination) do
        <<~RBS
          # keep destination docs
          class Foo
          end
        RBS
      end

      it 'preserves destination declaration-leading comments when template content wins' do
        merger = described_class.new(commented_template, commented_destination, preference: :template)

        expect(merger.merge).to eq(<<~RBS)
          # keep destination docs
          class Foo
          end
        RBS
      end
    end

    context 'when the matched declaration is an alias' do
      let(:commented_template) do
        <<~RBS
          class Foo = Bar
        RBS
      end

      let(:commented_destination) do
        <<~RBS
          # keep alias docs
          class Foo = Baz
        RBS
      end

      it 'preserves destination declaration-leading comments for matched aliases when template content wins' do
        merger = described_class.new(commented_template, commented_destination, preference: :template)

        expect(merger.merge).to eq(<<~RBS)
          # keep alias docs
          class Foo = Bar
        RBS
      end
    end

    context 'when the template already owns declaration-leading docs' do
      let(:commented_template) do
        <<~RBS
          # template docs
          class Foo
          end
        RBS
      end

      let(:commented_destination) do
        <<~RBS
          # destination docs
          class Foo
          end
        RBS
      end

      it 'keeps template declaration-leading comments' do
        merger = described_class.new(commented_template, commented_destination, preference: :template)

        expect(merger.merge).to eq(commented_template)
      end
    end

    context 'when a later matched declaration owns blank-line-separated destination docs' do
      let(:commented_template) do
        <<~RBS
          class One
          end

          class Two
          end
        RBS
      end

      let(:commented_destination) do
        <<~RBS
          class One
          end

          # keep second declaration docs
          class Two
          end
        RBS
      end

      it 'preserves blank-line-separated destination docs for adjacent declarations when template content wins' do
        merger = described_class.new(commented_template, commented_destination, preference: :template)

        expect(merger.merge).to eq(<<~RBS)
          class One
          end

          # keep second declaration docs
          class Two
          end
        RBS
      end
    end
  end

  shared_examples 'removed destination declaration comment preservation' do
    context 'when removal is enabled and the destination has an extra documented declaration' do
      let(:template_without_extra) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:destination_with_extra) do
        <<~RBS
          class Foo
          end

          # keep removed declaration docs
          class Legacy
          end
        RBS
      end

      it "promotes the removed declaration's leading comments without keeping the declaration body" do
        merger = described_class.new(
          template_without_extra,
          destination_with_extra,
          remove_template_missing_nodes: true
        )

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end

          # keep removed declaration docs
        RBS
      end
    end

    context 'when removal is enabled for a later blank-line-separated documented declaration' do
      let(:template_without_extra) do
        <<~RBS
          class One
          end
        RBS
      end

      let(:destination_with_extra) do
        <<~RBS
          class One
          end

          # keep removed second declaration docs
          class Two
          end
        RBS
      end

      it 'promotes adjacent removed declaration docs while preserving the separating blank line' do
        merger = described_class.new(
          template_without_extra,
          destination_with_extra,
          remove_template_missing_nodes: true
        )

        expect(merger.merge).to eq(<<~RBS)
          class One
          end

          # keep removed second declaration docs
        RBS
      end
    end
  end

  shared_examples 'document boundary comment preservation' do
    context 'when the destination has postlude comments after matched declarations' do
      let(:commented_template) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:commented_destination) do
        <<~RBS
          class Foo
          end

          # keep footer docs
        RBS
      end

      it 'preserves destination postlude comments' do
        merger = described_class.new(commented_template, commented_destination)

        expect(merger.merge).to eq(<<~RBS)
          class Foo
          end

          # keep footer docs
        RBS
      end
    end

    context 'when the destination is comment-only' do
      let(:commented_template) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:comment_only_destination) do
        <<~RBS
          # only docs
          # still docs
        RBS
      end

      it 'preserves the comment-only destination' do
        merger = described_class.new(commented_template, comment_only_destination)

        expect(merger.merge).to eq(comment_only_destination)
      end
    end

    it 'keeps a shared interstitial comment block singular between adjacent matched declarations' do
      template = <<~RBS
        type alpha = 1
        # Shared docs
        type beta = 2
      RBS
      destination = <<~RBS
        type alpha = 9
        # Shared docs
        type beta = 8
      RBS

      merged = described_class.new(template, destination).merge

      expect(merged.lines.grep("# Shared docs\n").size).to eq(1)
      expect(merged).to include("type alpha = 9\n# Shared docs\ntype beta = 8")
    end

    it 'keeps destination-owned first-owner docs singular when template models them as a preamble' do
      template = <<~RBS
        # Shared header

        type alpha = 1
      RBS
      destination = <<~RBS
        # Shared header
        type alpha = 9
      RBS

      merged = described_class.new(template, destination, preference: :template).merge

      expect(merged.lines.grep("# Shared header\n").size).to eq(1)
      expect(merged).to include('type alpha = 1')
    end

    it 'does not duplicate a first-owner doc block when only blank-line ownership differs across sources' do
      template = <<~RBS
        # Shared header

        type alpha = 1
      RBS
      destination = <<~RBS
        # Shared header
        type alpha = 9
      RBS

      merged = described_class.new(template, destination, preference: :destination).merge

      expect(merged.lines.grep("# Shared header\n").size).to eq(1)
      expect(merged).to eq(<<~RBS)
        # Shared header
        type alpha = 9
      RBS
    end

    it 'collapses duplicated template-owned preamble prefixes in heal mode' do
      template = <<~RBS
        # Shared header

        type alpha = 1
      RBS
      destination = <<~RBS
        # Shared header
        # Shared header
        # Destination header
        type alpha = 9
      RBS

      merged = described_class.new(template, destination, add_template_only_nodes: true).merge

      expect(merged.lines.grep("# Shared header\n").size).to eq(0)
      expect(merged.lines.grep("# Destination header\n").size).to eq(1)
      expect(merged).to include('type alpha = 9')
    end

    it 'preserves duplicated template-owned preamble prefixes in skip mode' do
      template = <<~RBS
        # Shared header

        type alpha = 1
      RBS
      destination = <<~RBS
        # Shared header
        # Shared header
        # Destination header
        type alpha = 9
      RBS

      merged = described_class.new(
        template,
        destination,
        add_template_only_nodes: true,
        corruption_handling: :skip
      ).merge

      expect(merged.lines.grep("# Shared header\n").size).to eq(2)
      expect(merged.lines.grep("# Destination header\n").size).to eq(1)
    end

    it 'warns and preserves duplicated template-owned preamble prefixes in warn mode' do
      allow(Rbs::Merge::DebugLogger).to receive(:debug_warning)

      template = <<~RBS
        # Shared header

        type alpha = 1
      RBS
      destination = <<~RBS
        # Shared header
        # Shared header
        # Destination header
        type alpha = 9
      RBS

      merged = described_class.new(
        template,
        destination,
        add_template_only_nodes: true,
        corruption_handling: :warn
      ).merge

      expect(Rbs::Merge::DebugLogger).to have_received(:debug_warning).with(
        /Suspected corruption \(duplicate_template_preamble_prefix\)/,
        hash_including(template_comment_lines: 2, merged_comment_lines: 3, destination_specific_comment_lines: 1)
      )
      expect(merged.lines.grep("# Shared header\n").size).to eq(2)
    end

    it 'raises on duplicated template-owned preamble prefixes in error mode' do
      template = <<~RBS
        # Shared header

        type alpha = 1
      RBS
      destination = <<~RBS
        # Shared header
        # Shared header
        # Destination header
        type alpha = 9
      RBS

      expect do
        described_class.new(
          template,
          destination,
          add_template_only_nodes: true,
          corruption_handling: :error
        ).merge
      end.to raise_error(Rbs::Merge::CorruptionDetectedError, /duplicate_template_preamble_prefix/)
    end
  end

  shared_examples 'source-augmented comment ownership preservation' do
    context 'when a floating comment block is attached to different declarations in template vs destination' do
      let(:template_with_floating_docs) do
        <<~RBS
          class Foo
          end

          # shared docs for the custom type
          type custom = String
        RBS
      end

      let(:destination_with_shifted_docs) do
        <<~RBS
          class Foo
          end

          # shared docs for the custom type
          class Extra
          end

          type custom = String
        RBS
      end

      it 'keeps the floating comment block singular while preserving all declarations' do
        merged = begin
          described_class.new(
            template_with_floating_docs,
            destination_with_shifted_docs,
            preference: :destination,
            add_template_only_nodes: true
          ).merge
        rescue Rbs::Merge::TemplateParseError => e
          pending(e.message) if e.message.include?('No RBS parser available')
          raise
        end

        expect(merged.scan(/^# shared docs for the custom type$/).size).to eq(1), merged
        expect(merged.scan(/^class Foo$/).size).to eq(1), merged
        expect(merged.scan(/^class Extra$/).size).to eq(1), merged
        expect(merged.scan(/^type custom = String$/).size).to eq(1), merged
      end
    end

    context 'when template preference removes the separating gap ahead of a matched declaration' do
      let(:template_with_attached_docs) do
        <<~RBS
          class Keep
          end
          # floating note
          class App
          end
        RBS
      end

      let(:destination_with_floating_docs) do
        <<~RBS
          class Keep
          end

          # floating note
          class App
          end
        RBS
      end

      it 'attaches the formerly floating docs to the matched declaration' do
        merged = begin
          described_class.new(
            template_with_attached_docs,
            destination_with_floating_docs,
            preference: :template
          ).merge
        rescue Rbs::Merge::TemplateParseError => e
          pending(e.message) if e.message.include?('No RBS parser available')
          raise
        end

        expect(merged).to eq(template_with_attached_docs)
      end
    end

    context 'when a commented destination-only declaration is removed but its separating gap should remain' do
      let(:template_without_removed_declaration) do
        <<~RBS
          class Keep
          end

          class App
          end
        RBS
      end

      let(:destination_with_floating_removed_docs) do
        <<~RBS
          class Keep
          end

          # floating note
          class RemoveMe
          end

          class App
          end
        RBS
      end

      it 'preserves the floating docs and their separating blank line' do
        merged = begin
          described_class.new(
            template_without_removed_declaration,
            destination_with_floating_removed_docs,
            preference: :template,
            remove_template_missing_nodes: true
          ).merge
        rescue Rbs::Merge::TemplateParseError => e
          pending(e.message) if e.message.include?('No RBS parser available')
          raise
        end

        expect(merged).to eq(<<~RBS)
          class Keep
          end

          # floating note

          class App
          end
        RBS
      end
    end

    context 'when both inputs have the same preamble ahead of a matched declaration' do
      let(:commented_template) do
        <<~RBS
          # shared preamble docs

          class Foo
          end
        RBS
      end

      let(:commented_destination) do
        <<~RBS
          # shared preamble docs

          class Foo
          end
        RBS
      end

      it 'keeps the document preamble singular' do
        merged = begin
          described_class.new(
            commented_template,
            commented_destination,
            preference: :destination,
            add_template_only_nodes: true
          ).merge
        rescue Rbs::Merge::TemplateParseError => e
          pending(e.message) if e.message.include?('No RBS parser available')
          raise
        end

        expect(merged.scan(/^# shared preamble docs$/).size).to eq(1), merged
        expect(merged.scan(/^class Foo$/).size).to eq(1), merged
      end
    end
  end

  shared_examples 'recursive member merge parity' do
    context 'when template preference merges matched container members' do
      let(:template_members) do
        <<~RBS
          class MyClass
            def shared: () -> String
            def template_only: () -> Integer
          end
        RBS
      end

      let(:destination_members) do
        <<~RBS
          class MyClass
            def shared: () -> Symbol
            def dest_only: () -> bool
          end
        RBS
      end

      it 'keeps destination-only members while applying template-preferred shared and template-only members' do
        merger = described_class.new(
          template_members,
          destination_members,
          preference: :template,
          add_template_only_nodes: true
        )

        expect(merger.merge).to eq(<<~RBS)
          class MyClass
            def shared: () -> String
            def dest_only: () -> bool
            def template_only: () -> Integer
          end
        RBS
      end
    end

    context 'when destination-owned nested members are separated by blank lines' do
      let(:template_members_with_gaps) do
        <<~RBS
          module Kettle
            module Wash
              VERSION: String
              def self.delete_constants: (Module owner, String | Symbol | Array[String | Symbol] constants) -> nil
              def self.reset_constants: (owner: Module, constants: String | Symbol | Array[String | Symbol], path: String) -> nil
              class Error < StandardError
              end
            end
          end
        RBS
      end

      let(:destination_members_with_gaps) do
        <<~RBS
          module Kettle
            module Wash
              VERSION: String

              def self.delete_constants: (Module owner, String | Symbol | Array[String | Symbol] constants) -> nil
              def self.reset_constants: (owner: Module, constants: String | Symbol | Array[String | Symbol], path: String) -> nil

              class Error < StandardError
              end
            end
          end
        RBS
      end

      it 'preserves destination-owned blank lines between retained nested members' do
        merger = described_class.new(
          template_members_with_gaps,
          destination_members_with_gaps,
          preference: :destination
        )

        expect(merger.merge).to eq(destination_members_with_gaps)
      end
    end
  end

  shared_examples 'recursive member comment preservation' do
    context 'when a matched nested member owns destination-leading docs' do
      let(:template_members) do
        <<~RBS
          class MyClass
            def shared: () -> String
          end
        RBS
      end

      let(:destination_members) do
        <<~RBS
          class MyClass
            # keep shared docs
            def shared: () -> Symbol
          end
        RBS
      end

      it 'preserves destination-leading docs for the matched member when template content wins' do
        merger = described_class.new(
          template_members,
          destination_members,
          preference: :template
        )

        expect(merger.merge).to eq(<<~RBS)
          class MyClass
            # keep shared docs
            def shared: () -> String
          end
        RBS
      end
    end
  end

  shared_examples 'recursive empty preferred container parity' do
    context 'when the preferred matched container is empty and destination owns nested members' do
      let(:template_members) do
        <<~RBS
          class MyClass
          end
        RBS
      end

      let(:destination_members) do
        <<~RBS
          class MyClass
            def dest_only: () -> bool
          end
        RBS
      end

      it 'keeps destination-only nested members inside the preferred declaration shell' do
        merger = described_class.new(
          template_members,
          destination_members,
          preference: :template
        )

        expect(merger.merge).to eq(<<~RBS)
          class MyClass
            def dest_only: () -> bool
          end
        RBS
      end
    end
  end

  shared_examples 'recursive template-only member parity' do
    context 'when destination preference keeps a matched container with no nested members' do
      let(:template_members) do
        <<~RBS
          class MyClass
            def template_only: () -> Integer
          end
        RBS
      end

      let(:destination_members) do
        <<~RBS
          class MyClass
          end
        RBS
      end

      it 'does not leak template-only nested members when add_template_only_nodes is disabled' do
        merger = described_class.new(
          template_members,
          destination_members,
          preference: :destination,
          add_template_only_nodes: false
        )

        expect(merger.merge).to eq(<<~RBS)
          class MyClass
          end
        RBS
      end

      it 'inserts template-only nested members into the empty preferred shell when add_template_only_nodes is enabled' do
        merger = described_class.new(
          template_members,
          destination_members,
          preference: :destination,
          add_template_only_nodes: true
        )

        expect(merger.merge).to eq(<<~RBS)
          class MyClass
            def template_only: () -> Integer
          end
        RBS
      end
    end

    context 'when destination preference keeps existing nested members' do
      let(:template_members) do
        <<~RBS
          class MyClass
            # keep template docs
            def template_only: () -> Integer
          end
        RBS
      end

      let(:destination_members) do
        <<~RBS
          class MyClass
            def dest_only: () -> bool
          end
        RBS
      end

      it 'appends documented template-only nested members after destination-owned members when enabled' do
        merger = described_class.new(
          template_members,
          destination_members,
          preference: :destination,
          add_template_only_nodes: true
        )

        expect(merger.merge).to eq(<<~RBS)
          class MyClass
            def dest_only: () -> bool
            # keep template docs
            def template_only: () -> Integer
          end
        RBS
      end
    end
  end

  shared_examples 'recursive overloaded member merge parity' do
    context 'when matched container members include reordered overloads' do
      let(:template_members) do
        <<~RBS
          interface _Foo
            def foo: () -> String
            def foo: (Integer) -> String
            def template_only: () -> Integer
          end
        RBS
      end

      let(:destination_members) do
        <<~RBS
          interface _Foo
            def foo: (String) -> Symbol
            def foo: () -> Symbol
            def dest_only: () -> bool
          end
        RBS
      end

      it 'matches overloads by callable shape instead of only method name and order' do
        merger = described_class.new(
          template_members,
          destination_members,
          preference: :template,
          add_template_only_nodes: true
        )

        expect(merger.merge).to eq(<<~RBS)
          interface _Foo
            def foo: (String) -> Symbol
            def foo: () -> String
            def dest_only: () -> bool
            def foo: (Integer) -> String
            def template_only: () -> Integer
          end
        RBS
      end
    end
  end

  # ============================================================
  # :auto backend tests (uses whatever is available)
  # ============================================================

  context 'with :auto backend', :rbs_parsing do
    describe '#initialize' do
      it_behaves_like 'basic initialization'

      context 'with invalid template' do
        it_behaves_like 'invalid template detection'
      end

      context 'with invalid destination' do
        it_behaves_like 'invalid destination detection'
      end
    end

    describe '#merge' do
      it_behaves_like 'merge with identical files'
      it_behaves_like 'merge with added declarations'
      it_behaves_like 'retained declaration blank line preservation'
      it_behaves_like 'merge with freeze blocks'
      it_behaves_like 'template-preferred declaration-leading comment fallback'
      it_behaves_like 'removed destination declaration comment preservation'
      it_behaves_like 'document boundary comment preservation'
      it_behaves_like 'source-augmented comment ownership preservation'
      it_behaves_like 'recursive member merge parity'
      it_behaves_like 'recursive member comment preservation'
      it_behaves_like 'recursive empty preferred container parity'
      it_behaves_like 'recursive template-only member parity'
      it_behaves_like 'recursive overloaded member merge parity'
    end
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

    describe '#initialize' do
      it_behaves_like 'basic initialization'

      context 'with invalid template' do
        it_behaves_like 'invalid template detection'
      end

      context 'with invalid destination' do
        it_behaves_like 'invalid destination detection'
      end
    end

    describe '#merge' do
      it_behaves_like 'merge with identical files'
      it_behaves_like 'merge with added declarations'
      it_behaves_like 'retained declaration blank line preservation'
      it_behaves_like 'merge with freeze blocks'
      it_behaves_like 'template-preferred declaration-leading comment fallback'
      it_behaves_like 'removed destination declaration comment preservation'
      it_behaves_like 'document boundary comment preservation'
      it_behaves_like 'source-augmented comment ownership preservation'
      it_behaves_like 'recursive member merge parity'
      it_behaves_like 'recursive member comment preservation'
      it_behaves_like 'recursive empty preferred container parity'
      it_behaves_like 'recursive template-only member parity'
      it_behaves_like 'recursive overloaded member merge parity'
    end
  end

  # ============================================================
  # Explicit tree-sitter backend tests via MRI
  # ============================================================

  context 'with explicit tree-sitter backend via MRI', :mri_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    describe '#initialize' do
      it_behaves_like 'basic initialization'

      context 'with invalid template' do
        it_behaves_like 'invalid template detection'
      end

      context 'with invalid destination' do
        it_behaves_like 'invalid destination detection'
      end
    end

    describe '#merge' do
      it_behaves_like 'merge with identical files'
      it_behaves_like 'merge with added declarations'
      it_behaves_like 'retained declaration blank line preservation'
      it_behaves_like 'merge with freeze blocks'
      it_behaves_like 'template-preferred declaration-leading comment fallback'
      it_behaves_like 'removed destination declaration comment preservation'
      it_behaves_like 'document boundary comment preservation'
      it_behaves_like 'source-augmented comment ownership preservation'
      it_behaves_like 'recursive member merge parity'
      it_behaves_like 'recursive member comment preservation'
      it_behaves_like 'recursive empty preferred container parity'
      it_behaves_like 'recursive template-only member parity'
      it_behaves_like 'recursive overloaded member merge parity'
    end
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

    describe '#initialize' do
      it_behaves_like 'basic initialization'

      context 'with invalid template' do
        it_behaves_like 'invalid template detection'
      end

      context 'with invalid destination' do
        it_behaves_like 'invalid destination detection'
      end
    end

    describe '#merge' do
      it_behaves_like 'merge with identical files'
      it_behaves_like 'merge with added declarations'
      it_behaves_like 'retained declaration blank line preservation'
      it_behaves_like 'merge with freeze blocks'
      it_behaves_like 'template-preferred declaration-leading comment fallback'
      it_behaves_like 'removed destination declaration comment preservation'
      it_behaves_like 'document boundary comment preservation'
      it_behaves_like 'source-augmented comment ownership preservation'
      it_behaves_like 'recursive member merge parity'
      it_behaves_like 'recursive member comment preservation'
      it_behaves_like 'recursive empty preferred container parity'
      it_behaves_like 'recursive template-only member parity'
      it_behaves_like 'recursive overloaded member merge parity'
    end
  end

  # ============================================================
  # Explicit Rust backend tests
  # ============================================================

  context 'with explicit Rust backend', :rbs_grammar, :rust_backend do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    describe '#initialize' do
      it_behaves_like 'basic initialization'

      context 'with invalid template' do
        it_behaves_like 'invalid template detection'
      end

      context 'with invalid destination' do
        it_behaves_like 'invalid destination detection'
      end
    end

    describe '#merge' do
      it_behaves_like 'merge with identical files'
      it_behaves_like 'merge with added declarations'
      it_behaves_like 'retained declaration blank line preservation'
      it_behaves_like 'merge with freeze blocks'
      it_behaves_like 'template-preferred declaration-leading comment fallback'
      it_behaves_like 'removed destination declaration comment preservation'
      it_behaves_like 'document boundary comment preservation'
      it_behaves_like 'source-augmented comment ownership preservation'
      it_behaves_like 'recursive member merge parity'
      it_behaves_like 'recursive member comment preservation'
      it_behaves_like 'recursive empty preferred container parity'
      it_behaves_like 'recursive template-only member parity'
      it_behaves_like 'recursive overloaded member merge parity'
    end
  end

  # ============================================================
  # Explicit FFI backend tests
  # ============================================================

  context 'with explicit FFI backend', :ffi_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    describe '#initialize' do
      it_behaves_like 'basic initialization'

      context 'with invalid template' do
        it_behaves_like 'invalid template detection'
      end

      context 'with invalid destination' do
        it_behaves_like 'invalid destination detection'
      end
    end

    describe '#merge' do
      it_behaves_like 'merge with identical files'
      it_behaves_like 'merge with added declarations'
      it_behaves_like 'retained declaration blank line preservation'
      it_behaves_like 'merge with freeze blocks'
      it_behaves_like 'template-preferred declaration-leading comment fallback'
      it_behaves_like 'removed destination declaration comment preservation'
      it_behaves_like 'document boundary comment preservation'
      it_behaves_like 'source-augmented comment ownership preservation'
      it_behaves_like 'recursive member merge parity'
      it_behaves_like 'recursive member comment preservation'
      it_behaves_like 'recursive empty preferred container parity'
      it_behaves_like 'recursive template-only member parity'
      it_behaves_like 'recursive overloaded member merge parity'
    end
  end
end
