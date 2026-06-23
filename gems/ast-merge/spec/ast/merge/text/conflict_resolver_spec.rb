# frozen_string_literal: true

require 'ast/merge/text'

RSpec.describe Ast::Merge::Text::ConflictResolver do
  let(:template_source) { "Line one\nLine two\nLine three" }
  let(:dest_source) { "Line one\nLine two\nLine three" }
  let(:template_analysis) { Ast::Merge::Text::FileAnalysis.new(template_source) }
  let(:dest_analysis) { Ast::Merge::Text::FileAnalysis.new(dest_source) }

  describe '#initialize' do
    it 'accepts preference option' do
      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :template
      )

      expect(resolver.instance_variable_get(:@preference)).to eq(:template)
    end

    it 'accepts add_template_only_nodes option' do
      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        add_template_only_nodes: true
      )

      expect(resolver.instance_variable_get(:@add_template_only_nodes)).to be true
    end
  end

  describe '#resolve' do
    context 'with identical content' do
      it 'preserves all lines' do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Ast::Merge::Text::MergeResult.new

        resolver.resolve(result)

        expect(result.to_s).to eq("Line one\nLine two\nLine three\n")
      end

      it 'records identical decisions' do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Ast::Merge::Text::MergeResult.new

        resolver.resolve(result)

        identical_decisions = result.decisions.select { |d| d[:decision] == :identical }
        expect(identical_decisions.size).to eq(3)
      end
    end

    context 'with destination-only lines' do
      let(:dest_source) { "Line one\nLine two\nNew line\nLine three" }

      it 'preserves destination-only lines' do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Ast::Merge::Text::MergeResult.new

        resolver.resolve(result)

        expect(result.to_s).to include('New line')
      end

      it 'records appended decision for destination-only lines' do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Ast::Merge::Text::MergeResult.new

        resolver.resolve(result)

        appended_decisions = result.decisions.select { |d| d[:decision] == :appended }
        expect(appended_decisions.size).to eq(1)
      end
    end

    context 'with template-only lines' do
      let(:dest_source) { "Line one\nLine three" }

      context 'when add_template_only_nodes is false (default)' do
        it 'does not add template-only lines' do
          resolver = described_class.new(template_analysis, dest_analysis)
          result = Ast::Merge::Text::MergeResult.new

          resolver.resolve(result)

          expect(result.to_s).not_to include('Line two')
        end
      end

      context 'when add_template_only_nodes is true' do
        it 'adds template-only lines in template order' do
          resolver = described_class.new(
            template_analysis,
            dest_analysis,
            add_template_only_nodes: true
          )
          result = Ast::Merge::Text::MergeResult.new

          resolver.resolve(result)

          expect(result.to_s).to eq("Line one\nLine two\nLine three\n")
        end

        it 'records added decision for template-only lines' do
          resolver = described_class.new(
            template_analysis,
            dest_analysis,
            add_template_only_nodes: true
          )
          result = Ast::Merge::Text::MergeResult.new

          resolver.resolve(result)

          added_decisions = result.decisions.select { |d| d[:decision] == :added }
          expect(added_decisions.size).to eq(1)
        end
      end

      context 'when a template-only line precedes the first matched line' do
        let(:template_source) { "Header\nLine one\nLine two\nLine three" }

        it 'emits the prefix line before destination-backed content' do
          resolver = described_class.new(
            template_analysis,
            dest_analysis,
            add_template_only_nodes: true
          )
          result = Ast::Merge::Text::MergeResult.new

          resolver.resolve(result)

          expect(result.to_s).to start_with("Header\nLine one\n")
        end
      end
    end

    context 'with whitespace differences (same normalized content)' do
      let(:template_source) { "  Line one  \nLine two" }
      let(:dest_source) { "Line one\n  Line two  " }

      context 'with preference: :destination (default)' do
        it 'uses destination content' do
          resolver = described_class.new(template_analysis, dest_analysis)
          result = Ast::Merge::Text::MergeResult.new

          resolver.resolve(result)

          lines = result.to_s.split("\n")
          expect(lines[0]).to eq('Line one')
          expect(lines[1]).to eq('  Line two  ')
        end

        it 'records kept_destination decisions' do
          resolver = described_class.new(template_analysis, dest_analysis)
          result = Ast::Merge::Text::MergeResult.new

          resolver.resolve(result)

          kept_dest_decisions = result.decisions.select { |d| d[:decision] == :kept_destination }
          expect(kept_dest_decisions.size).to eq(2)
        end
      end

      context 'with preference: :template' do
        it 'uses template content' do
          resolver = described_class.new(
            template_analysis,
            dest_analysis,
            preference: :template
          )
          result = Ast::Merge::Text::MergeResult.new

          resolver.resolve(result)

          lines = result.to_s.split("\n")
          expect(lines[0]).to eq('  Line one  ')
          expect(lines[1]).to eq('Line two')
        end

        it 'records kept_template decisions' do
          resolver = described_class.new(
            template_analysis,
            dest_analysis,
            preference: :template
          )
          result = Ast::Merge::Text::MergeResult.new

          resolver.resolve(result)

          kept_template_decisions = result.decisions.select { |d| d[:decision] == :kept_template }
          expect(kept_template_decisions.size).to eq(2)
        end
      end
    end

    context 'with freeze blocks' do
      let(:dest_source) do
        <<~TEXT.chomp
          Line one
          # text-merge:freeze
          Frozen content
          # text-merge:unfreeze
          Line three
        TEXT
      end

      it 'preserves freeze blocks from destination' do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Ast::Merge::Text::MergeResult.new

        resolver.resolve(result)

        expect(result.to_s).to include('# text-merge:freeze')
        expect(result.to_s).to include('Frozen content')
        expect(result.to_s).to include('# text-merge:unfreeze')
      end

      it 'records frozen decisions' do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Ast::Merge::Text::MergeResult.new

        resolver.resolve(result)

        frozen_decisions = result.decisions.select { |d| d[:decision] == :frozen }
        expect(frozen_decisions.size).to eq(1)
      end
    end

    context 'with freeze blocks in template' do
      let(:template_source) do
        <<~TEXT.chomp
          Line one
          # text-merge:freeze
          Template frozen content
          # text-merge:unfreeze
          Line three
        TEXT
      end

      context 'when add_template_only_nodes is true' do
        it 'does not add freeze blocks from template' do
          resolver = described_class.new(
            template_analysis,
            dest_analysis,
            add_template_only_nodes: true
          )
          result = Ast::Merge::Text::MergeResult.new

          resolver.resolve(result)

          # Freeze blocks from template should be skipped
          expect(result.to_s).not_to include('Template frozen content')
        end
      end
    end

    context 'with destination-only lines between matched anchors' do
      let(:template_source) { "Line one\nLine two\nTemplate only line\nLine three" }
      let(:dest_source) { "Line one\nLine two\nDestination only line\nLine three" }

      it 'emits template-only lines before later destination-only content' do
        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          add_template_only_nodes: true
        )
        result = Ast::Merge::Text::MergeResult.new

        resolver.resolve(result)

        expect(result.to_s).to eq("Line one\nLine two\nTemplate only line\nDestination only line\nLine three\n")
      end
    end

    context 'with duplicate normalized content' do
      let(:template_source) { "Line\nLine\nLine" }
      let(:dest_source) { "  Line  \n Line \nLine" }

      it 'matches in order' do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Ast::Merge::Text::MergeResult.new

        resolver.resolve(result)

        lines = result.to_s.split("\n")
        expect(lines.size).to eq(3)
      end
    end
  end
end
