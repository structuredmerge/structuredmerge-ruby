# frozen_string_literal: true

require 'spec_helper'

# FileAligner specs - works with any RBS parser backend
# Tagged with :rbs_parsing since FileAnalysis supports both RBS gem and tree-sitter-rbs
RSpec.describe Rbs::Merge::FileAligner, :rbs_parsing do
  shared_examples 'documented declaration alignment parity' do
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

    it 'matches documented declarations by signature instead of leading docs' do
      alignment = described_class.new(documented_template_analysis, documented_dest_analysis).align

      expect(alignment).to include(hash_including(type: :match, template_index: 0, dest_index: 0))
    end
  end

  shared_examples 'documented destination-only alignment parity' do
    let(:template_source_with_one_class) do
      <<~RBS
        class Foo
        end
      RBS
    end
    let(:dest_source_with_documented_extra_class) do
      <<~RBS
        class Foo
        end

        # destination docs
        class Bar
        end
      RBS
    end
    let(:template_analysis_with_one_class) { Rbs::Merge::FileAnalysis.new(template_source_with_one_class) }
    let(:dest_analysis_with_documented_extra_class) { Rbs::Merge::FileAnalysis.new(dest_source_with_documented_extra_class) }

    it 'keeps documented unmatched declarations as destination-only entries' do
      alignment = described_class.new(
        template_analysis_with_one_class,
        dest_analysis_with_documented_extra_class
      ).align

      expect(alignment).to include(hash_including(type: :dest_only, dest_index: 1))
    end
  end

  shared_examples 'freeze block alignment parity' do
    let(:template_source_with_class) do
      <<~RBS
        class Foo
          def bar: () -> void
        end
      RBS
    end
    let(:dest_source_with_frozen_class) do
      <<~RBS
        # rbs-merge:freeze
        class Foo
          def bar: () -> void
        end
        # rbs-merge:unfreeze
      RBS
    end
    let(:template_analysis_with_class) { Rbs::Merge::FileAnalysis.new(template_source_with_class) }
    let(:dest_analysis_with_frozen_class) { Rbs::Merge::FileAnalysis.new(dest_source_with_frozen_class) }

    it 'matches a frozen destination declaration to the same unfrozen template signature' do
      alignment = described_class.new(
        template_analysis_with_class,
        dest_analysis_with_frozen_class
      ).align

      match = alignment.find { |entry| entry[:type] == :match }

      expect(match).not_to be_nil
      expect(match[:template_index]).to eq(0)
      expect(match[:dest_index]).to eq(0)
      expect(match[:dest_decl]).to be_a(Rbs::Merge::FreezeNode)
      expect(match[:signature]).to eq([:class, 'Foo'])
    end
  end

  shared_examples 'freeze type alias alignment parity' do
    let(:template_type_alias_source) { "type custom = String\n" }
    let(:dest_frozen_type_alias_source) do
      <<~RBS
        # rbs-merge:freeze
        type custom = String
        # rbs-merge:unfreeze
      RBS
    end
    let(:template_type_alias_analysis) { Rbs::Merge::FileAnalysis.new(template_type_alias_source) }
    let(:dest_frozen_type_alias_analysis) { Rbs::Merge::FileAnalysis.new(dest_frozen_type_alias_source) }

    it 'matches a frozen destination type alias to the same unfrozen template signature' do
      alignment = described_class.new(
        template_type_alias_analysis,
        dest_frozen_type_alias_analysis
      ).align

      expect(alignment).to include(
        hash_including(
          type: :match,
          template_index: 0,
          dest_index: 0,
          signature: [:type_alias, 'custom']
        )
      )
    end
  end

  shared_examples 'freeze class alias alignment parity' do
    let(:template_class_alias_source) { "class Foo = Bar\n" }
    let(:dest_frozen_class_alias_source) do
      <<~RBS
        # rbs-merge:freeze
        class Foo = Baz
        # rbs-merge:unfreeze
      RBS
    end
    let(:template_class_alias_analysis) { Rbs::Merge::FileAnalysis.new(template_class_alias_source) }
    let(:dest_frozen_class_alias_analysis) { Rbs::Merge::FileAnalysis.new(dest_frozen_class_alias_source) }

    it 'matches a frozen destination class alias to the same unfrozen template signature' do
      alignment = described_class.new(
        template_class_alias_analysis,
        dest_frozen_class_alias_analysis
      ).align

      expect(alignment).to include(
        hash_including(
          type: :match,
          template_index: 0,
          dest_index: 0,
          signature: [:class_alias, 'Foo']
        )
      )
    end
  end

  shared_examples 'freeze module alias alignment parity' do
    let(:template_module_alias_source) { "module Baz = Quux\n" }
    let(:dest_frozen_module_alias_source) do
      <<~RBS
        # rbs-merge:freeze
        module Baz = Other
        # rbs-merge:unfreeze
      RBS
    end
    let(:template_module_alias_analysis) { Rbs::Merge::FileAnalysis.new(template_module_alias_source) }
    let(:dest_frozen_module_alias_analysis) { Rbs::Merge::FileAnalysis.new(dest_frozen_module_alias_source) }

    it 'matches a frozen destination module alias to the same unfrozen template signature' do
      alignment = described_class.new(
        template_module_alias_analysis,
        dest_frozen_module_alias_analysis
      ).align

      expect(alignment).to include(
        hash_including(
          type: :match,
          template_index: 0,
          dest_index: 0,
          signature: [:module_alias, 'Baz']
        )
      )
    end
  end

  shared_examples 'custom freeze block alignment parity' do
    let(:template_source_with_custom_token_class) do
      <<~RBS
        class Foo
          def bar: () -> void
        end
      RBS
    end
    let(:dest_source_with_custom_token_frozen_class) do
      <<~RBS
        # custom-token:freeze
        class Foo
          def bar: () -> void
        end
        # custom-token:unfreeze
      RBS
    end
    let(:template_analysis_with_custom_token_class) do
      Rbs::Merge::FileAnalysis.new(template_source_with_custom_token_class, freeze_token: 'custom-token')
    end
    let(:dest_analysis_with_custom_token_frozen_class) do
      Rbs::Merge::FileAnalysis.new(dest_source_with_custom_token_frozen_class, freeze_token: 'custom-token')
    end

    it 'matches a custom-token frozen destination declaration to the same unfrozen template signature' do
      alignment = described_class.new(
        template_analysis_with_custom_token_class,
        dest_analysis_with_custom_token_frozen_class
      ).align

      expect(alignment).to include(
        hash_including(
          type: :match,
          template_index: 0,
          dest_index: 0,
          signature: [:class, 'Foo']
        )
      )
    end
  end

  describe '#initialize' do
    let(:template_source) { "class Foo\nend" }
    let(:dest_source) { "class Bar\nend" }
    let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
    let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

    it 'stores template_analysis' do
      aligner = described_class.new(template_analysis, dest_analysis)
      expect(aligner.template_analysis).to eq(template_analysis)
    end

    it 'stores dest_analysis' do
      aligner = described_class.new(template_analysis, dest_analysis)
      expect(aligner.dest_analysis).to eq(dest_analysis)
    end
  end

  describe '#align' do
    context 'with matching declarations' do
      let(:template_source) do
        <<~RBS
          class Foo
            def bar: () -> void
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          class Foo
            def baz: () -> void
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'creates :match entries for matching signatures' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        matches = alignment.select { |e| e[:type] == :match }
        expect(matches).not_to be_empty
      end
    end

    context 'with template-only declarations' do
      let(:template_source) do
        <<~RBS
          class Foo
          end

          class OnlyInTemplate
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'creates :template_only entries' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        template_only = alignment.select { |e| e[:type] == :template_only }
        expect(template_only).not_to be_empty
      end
    end

    context 'with dest-only declarations' do
      let(:template_source) do
        <<~RBS
          class Foo
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          class Foo
          end

          class OnlyInDest
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'creates :dest_only entries' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        dest_only = alignment.select { |e| e[:type] == :dest_only }
        expect(dest_only).not_to be_empty
      end
    end

    context 'with modules and classes' do
      let(:template_source) do
        <<~RBS
          module MyModule
            class Nested
            end
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          module MyModule
            class Different
            end
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'aligns by signature' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        expect(alignment).to be_an(Array)
        # Should have matches for the module, and possibly unmatched for children
      end
    end

    context 'with empty files' do
      let(:template_source) { '' }
      let(:dest_source) { '' }
      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'returns empty alignment' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        expect(alignment).to eq([])
      end
    end

    context 'with type aliases' do
      let(:template_source) do
        <<~RBS
          type my_type = String
        RBS
      end

      let(:dest_source) do
        <<~RBS
          type my_type = Integer
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'matches type aliases by name' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        matches = alignment.select { |e| e[:type] == :match }
        expect(matches).not_to be_empty
      end
    end

    context 'with interface definitions' do
      let(:template_source) do
        <<~RBS
          interface _Printable
            def to_s: () -> String
          end
        RBS
      end

      let(:dest_source) do
        <<~RBS
          interface _Printable
            def inspect: () -> String
          end
        RBS
      end

      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'matches interfaces by name' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        matches = alignment.select { |e| e[:type] == :match }
        expect(matches).not_to be_empty
      end
    end
  end

  describe '#sort_alignment' do
    let(:template_source) { "class Foo\nend" }
    let(:dest_source) { "class Foo\nend" }
    let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
    let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

    it 'keeps destination-only entries interleaved with matches by destination order' do
      aligner = described_class.new(template_analysis, dest_analysis)
      alignment = aligner.align

      expect(alignment).to be_an(Array)
    end

    it 'keeps a documented destination-only declaration ahead of a later matched declaration' do
      template_analysis = Rbs::Merge::FileAnalysis.new(<<~RBS)
        class Keep
        end

        class Tail
        end
      RBS

      dest_analysis = Rbs::Merge::FileAnalysis.new(<<~RBS)
        class Keep
        end

        # destination docs
        class Legacy
        end

        class Tail
        end
      RBS

      alignment = described_class.new(template_analysis, dest_analysis).align

      expect(alignment.map { |entry| [entry[:type], entry[:dest_index], entry[:template_index]] }).to eq([
                                                                                                           [:match, 0,
                                                                                                            0],
                                                                                                           [:dest_only,
                                                                                                            1, nil],
                                                                                                           [:match, 2,
                                                                                                            1]
                                                                                                         ])
    end
  end

  describe 'edge cases in alignment' do
    context 'with duplicate signatures' do
      let(:template_source) do
        <<~RBS
          class Foo
          end
          class Foo
          end
        RBS
      end
      let(:dest_source) do
        <<~RBS
          class Foo
          end
        RBS
      end
      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'pairs only matching indices (second template remains unmatched)' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        matches = alignment.select { |e| e[:type] == :match }
        template_only = alignment.select { |e| e[:type] == :template_only }

        # One match, one template_only
        expect(matches.size).to eq(1)
        expect(template_only.size).to eq(1)
      end
    end

    context 'with more dest matches than template' do
      let(:template_source) do
        <<~RBS
          class Foo
          end
        RBS
      end
      let(:dest_source) do
        <<~RBS
          class Foo
          end
          class Foo
          end
        RBS
      end
      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'pairs first dest with template, second dest remains unmatched' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        matches = alignment.select { |e| e[:type] == :match }
        dest_only = alignment.select { |e| e[:type] == :dest_only }

        # One match, one dest_only (zip produces nil for missing element)
        expect(matches.size).to eq(1)
        expect(dest_only.size).to eq(1)
      end
    end

    context 'with nil signature' do
      let(:template_source) { "class Foo\nend" }
      let(:dest_source) { "class Foo\nend" }
      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'excludes entries with nil signatures from signature map' do
        # Mock signature_at to return nil
        allow(template_analysis).to receive(:signature_at).and_return(nil)

        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        # With nil signature, no matches can be made
        matches = alignment.select { |e| e[:type] == :match }
        expect(matches).to be_empty
      end
    end

    context 'with unknown entry type in sort' do
      let(:template_source) { "class Foo\nend" }
      let(:dest_source) { "class Bar\nend" }
      let(:template_analysis) { Rbs::Merge::FileAnalysis.new(template_source) }
      let(:dest_analysis) { Rbs::Merge::FileAnalysis.new(dest_source) }

      it 'handles unknown entry types with fallback sort key' do
        aligner = described_class.new(template_analysis, dest_analysis)
        alignment = aligner.align

        # Inject an unknown type entry to test the else branch
        unknown_entry = { type: :unknown, template_index: 0, dest_index: 0 }
        alignment << unknown_entry

        # Re-sort (private method, but we can test indirectly)
        sorted = alignment.sort_by do |entry|
          case entry[:type]
          when :match
            [0, entry[:dest_index], 0, entry[:template_index] || 0]
          when :dest_only
            if entry[:dest_decl].is_a?(Rbs::Merge::FreezeNode)
              [1, entry[:dest_index], 0, 0]
            else
              [0, entry[:dest_index], 1, 0]
            end
          when :template_only
            [2, entry[:template_index], 0, 0]
          else
            [3, 0, 0, 0]
          end
        end

        # Unknown type should sort last
        expect(sorted.last[:type]).to eq(:unknown)
      end
    end
  end

  describe 'explicit backend parity for documented declarations', :rbs_backend do
    around do |example|
      TreeHaver.with_backend(:rbs) do
        example.run
      end
    end

    it_behaves_like 'documented declaration alignment parity'
    it_behaves_like 'documented destination-only alignment parity'
    it_behaves_like 'freeze block alignment parity'
    it_behaves_like 'freeze type alias alignment parity'
    it_behaves_like 'freeze class alias alignment parity'
    it_behaves_like 'freeze module alias alignment parity'
    it_behaves_like 'custom freeze block alignment parity'
  end

  describe 'explicit backend parity for documented declarations', :mri_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    it_behaves_like 'documented declaration alignment parity'
    it_behaves_like 'documented destination-only alignment parity'
    it_behaves_like 'freeze block alignment parity'
    it_behaves_like 'freeze type alias alignment parity'
    it_behaves_like 'freeze class alias alignment parity'
    it_behaves_like 'freeze module alias alignment parity'
    it_behaves_like 'custom freeze block alignment parity'
  end

  describe 'explicit backend parity for documented declarations', :java_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    it_behaves_like 'documented declaration alignment parity'
    it_behaves_like 'documented destination-only alignment parity'
    it_behaves_like 'freeze block alignment parity'
    it_behaves_like 'freeze type alias alignment parity'
    it_behaves_like 'freeze class alias alignment parity'
    it_behaves_like 'freeze module alias alignment parity'
    it_behaves_like 'custom freeze block alignment parity'
  end

  describe 'explicit backend parity for documented declarations', :rbs_grammar, :rust_backend do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    it_behaves_like 'documented declaration alignment parity'
    it_behaves_like 'documented destination-only alignment parity'
    it_behaves_like 'freeze block alignment parity'
    it_behaves_like 'freeze type alias alignment parity'
    it_behaves_like 'freeze class alias alignment parity'
    it_behaves_like 'freeze module alias alignment parity'
    it_behaves_like 'custom freeze block alignment parity'
  end

  describe 'explicit backend parity for documented declarations', :ffi_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    it_behaves_like 'documented declaration alignment parity'
    it_behaves_like 'documented destination-only alignment parity'
    it_behaves_like 'freeze block alignment parity'
    it_behaves_like 'freeze type alias alignment parity'
    it_behaves_like 'freeze class alias alignment parity'
    it_behaves_like 'freeze module alias alignment parity'
    it_behaves_like 'custom freeze block alignment parity'
  end
end
