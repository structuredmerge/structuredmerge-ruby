# frozen_string_literal: true

require 'ast/merge/text'
require 'ast/merge/rspec/shared_examples'

RSpec.describe 'Text-based AST merge integration' do
  let(:fixtures_path) { File.expand_path('../fixtures/text', __dir__) }
  let(:merger_class) { Ast::Merge::Text::SmartMerger }
  let(:file_extension) { 'txt' }

  describe 'basic merge scenarios (destination wins by default)' do
    context 'when a top-level node is removed in destination' do
      it_behaves_like 'a reproducible merge', '01_top_level_removed'
    end

    context 'when a top-level node is added in destination' do
      it_behaves_like 'a reproducible merge', '02_top_level_added'
    end

    context 'when a nested word is removed in destination' do
      it_behaves_like 'a reproducible merge', '03_nested_removed'
    end

    context 'when a nested word is added in destination' do
      it_behaves_like 'a reproducible merge', '04_nested_added'
    end

    context 'when a top-level node is changed in destination' do
      it_behaves_like 'a reproducible merge', '05_top_level_changed'
    end

    context 'when multiple top-level nodes are changed in destination' do
      it_behaves_like 'a reproducible merge', '06_multiple_top_level_changed'
    end

    context 'when a nested word is changed in destination' do
      it_behaves_like 'a reproducible merge', '07_nested_changed'
    end

    context 'when multiple nested words are changed in destination' do
      it_behaves_like 'a reproducible merge', '08_multiple_nested_changed'
    end
  end

  describe 'configuration option: preference' do
    context 'with preference: :template' do
      it_behaves_like 'a reproducible merge', 'config_preference_template', {
        preference: :template
      }
    end

    context 'with preference: :destination (default)' do
      # This uses fixture 05 which shows destination changes preserved
      it_behaves_like 'a reproducible merge', '05_top_level_changed', {
        preference: :destination
      }
    end
  end

  describe 'configuration option: add_template_only_nodes' do
    context 'with add_template_only_nodes: true' do
      it_behaves_like 'a reproducible merge', 'config_add_template_only', {
        add_template_only_nodes: true
      }
    end

    context 'with add_template_only_nodes: false (default)' do
      let(:template) do
        <<~TEXT
          Line one
          Line two
          Template only line
          Line three
        TEXT
      end

      let(:destination) do
        <<~TEXT
          Line one
          Line two
          Line three
        TEXT
      end

      it 'skips template-only lines' do
        merger = Ast::Merge::Text::SmartMerger.new(
          template,
          destination,
          add_template_only_nodes: false
        )
        result = merger.merge

        # Template only line should NOT be present
        expect(result).not_to include('Template only line')
        # But matched lines should be
        expect(result).to include('Line one')
        expect(result).to include('Line two')
        expect(result).to include('Line three')
      end
    end
  end

  describe 'configuration option: freeze_token' do
    context 'with default freeze token (text-merge)' do
      it_behaves_like 'a reproducible merge', 'config_freeze_block'
    end

    context 'with custom freeze token' do
      let(:template) do
        <<~TEXT
          Line one
          Line two
        TEXT
      end

      let(:destination) do
        <<~TEXT
          Line one
          # custom-token:freeze
          Frozen content
          # custom-token:unfreeze
        TEXT
      end

      it 'respects custom freeze token' do
        merger = Ast::Merge::Text::SmartMerger.new(
          template,
          destination,
          freeze_token: 'custom-token'
        )
        result = merger.merge

        expect(result).to include('# custom-token:freeze')
        expect(result).to include('Frozen content')
        expect(result).to include('# custom-token:unfreeze')
      end
    end
  end

  describe 'all configuration options combined' do
    context 'with preference: :template and add_template_only_nodes: true' do
      it_behaves_like 'a reproducible merge', 'config_all_options', {
        preference: :template,
        add_template_only_nodes: true
      }
    end
  end

  describe 'edge cases' do
    context 'with empty template' do
      let(:template) { '' }
      let(:destination) { "Line one\nLine two" }

      it 'preserves destination content' do
        merger = Ast::Merge::Text::SmartMerger.new(template, destination)
        result = merger.merge

        expect(result).to eq("Line one\nLine two\n")
      end

      it 'is idempotent' do
        merger1 = Ast::Merge::Text::SmartMerger.new(template, destination)
        result1 = merger1.merge

        merger2 = Ast::Merge::Text::SmartMerger.new(template, result1)
        result2 = merger2.merge

        expect(result2).to eq(result1)
      end
    end

    context 'with empty destination' do
      let(:template) { "Line one\nLine two" }
      let(:destination) { '' }

      it 'returns empty when not adding template-only nodes' do
        merger = Ast::Merge::Text::SmartMerger.new(
          template,
          destination,
          add_template_only_nodes: false
        )
        result = merger.merge

        expect(result).to eq('')
      end

      it 'adds template content when add_template_only_nodes is true' do
        merger = Ast::Merge::Text::SmartMerger.new(
          template,
          destination,
          add_template_only_nodes: true
        )
        result = merger.merge

        expect(result).to eq("Line one\nLine two\n")
      end
    end

    context 'with identical files' do
      let(:content) { "Line one\nLine two\nLine three" }

      it 'returns identical content' do
        merger = Ast::Merge::Text::SmartMerger.new(content, content)
        result = merger.merge

        expect(result).to eq("#{content}\n")
      end

      it 'is idempotent' do
        merger1 = Ast::Merge::Text::SmartMerger.new(content, content)
        result1 = merger1.merge

        merger2 = Ast::Merge::Text::SmartMerger.new(content, result1)
        result2 = merger2.merge

        expect(result2).to eq(result1)
      end
    end

    context 'with whitespace-only differences' do
      let(:template) { "  Line one  \nLine two" }
      let(:destination) { "Line one\n  Line two  " }

      it 'preserves destination whitespace (destination wins)' do
        merger = Ast::Merge::Text::SmartMerger.new(template, destination)
        result = merger.merge

        # Lines are matched by normalized content, but full content is preserved
        expect(result).to include('Line one')
        expect(result).to include('Line two')
      end
    end

    context 'with blank lines' do
      let(:template) { "Line one\n\nLine three" }
      let(:destination) { "Line one\nLine two\n\nLine three" }

      it 'handles blank lines correctly' do
        merger = Ast::Merge::Text::SmartMerger.new(template, destination)
        result = merger.merge

        # Destination has extra content that should be preserved
        expect(result).to include('Line one')
        expect(result).to include('Line two')
        expect(result).to include('Line three')
      end
    end
  end

  describe 'statistics' do
    let(:template) { "Line one\nLine two\nLine three" }
    let(:destination) { "Line one modified\nLine two\nNew line" }

    it 'provides merge statistics' do
      merger = Ast::Merge::Text::SmartMerger.new(template, destination)
      merger.merge

      stats = merger.stats

      expect(stats[:template_lines]).to eq(3)
      expect(stats[:dest_lines]).to eq(3)
      expect(stats).to have_key(:result_lines)
      expect(stats).to have_key(:decisions)
    end
  end
end
