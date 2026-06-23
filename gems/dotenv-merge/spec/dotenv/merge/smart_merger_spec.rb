# frozen_string_literal: true

RSpec.describe Dotenv::Merge::SmartMerger do
  describe '#initialize' do
    let(:template) { "API_KEY=template\n" }
    let(:destination) { "API_KEY=dest\n" }

    it 'creates a merger' do
      merger = described_class.new(template, destination)
      expect(merger).to be_a(described_class)
    end

    it 'has template_analysis' do
      merger = described_class.new(template, destination)
      expect(merger.template_analysis).to be_a(Dotenv::Merge::FileAnalysis)
    end

    it 'has dest_analysis' do
      merger = described_class.new(template, destination)
      expect(merger.dest_analysis).to be_a(Dotenv::Merge::FileAnalysis)
    end
  end

  describe '#merge' do
    context 'with identical files' do
      let(:content) do
        <<~DOTENV
          API_KEY=secret
          DATABASE_URL=postgres://localhost
        DOTENV
      end

      it 'returns destination content' do
        merger = described_class.new(content, content)
        result = merger.merge_result
        expect(result.to_s).to include('API_KEY=secret')
        expect(result.to_s).to include('DATABASE_URL=postgres://localhost')
      end
    end

    context 'with destination-only variables' do
      let(:template) { "API_KEY=template\n" }
      let(:destination) do
        <<~DOTENV
          API_KEY=dest
          CUSTOM_VAR=custom
        DOTENV
      end

      it 'preserves destination-only variables' do
        merger = described_class.new(template, destination)
        result = merger.merge_result
        expect(result.to_s).to include('CUSTOM_VAR=custom')
      end
    end

    context 'with template-only variables' do
      let(:template) do
        <<~DOTENV
          API_KEY=template
          NEW_VAR=new_value
        DOTENV
      end
      let(:destination) { "API_KEY=dest\n" }

      context 'when add_template_only_nodes is false (default)' do
        it 'does not add template-only variables' do
          merger = described_class.new(template, destination)
          result = merger.merge_result
          expect(result.to_s).not_to include('NEW_VAR')
        end
      end

      context 'when add_template_only_nodes is true' do
        it 'adds template-only variables' do
          merger = described_class.new(template, destination, add_template_only_nodes: true)
          result = merger.merge_result
          expect(result.to_s).to include('NEW_VAR=new_value')
        end

        it 'inserts template-only prefix variables before the first matched anchor' do
          template = <<~DOTENV
            ALPHA=1
            BETA=2
          DOTENV
          destination = <<~DOTENV
            BETA=9
          DOTENV

          merger = described_class.new(template, destination, add_template_only_nodes: true)

          expect(merger.merge).to eq(
            <<~DOTENV
              ALPHA=1
              BETA=9
            DOTENV
          )
        end
      end
    end

    context 'with matching variables' do
      let(:template) { "API_KEY=template_value\n" }
      let(:destination) { "API_KEY=dest_value\n" }

      context 'when preference is :destination (default)' do
        it 'uses destination version' do
          merger = described_class.new(template, destination)
          result = merger.merge_result
          expect(result.to_s).to include('API_KEY=dest_value')
          expect(result.to_s).not_to include('API_KEY=template_value')
        end
      end

      context 'when preference is :template' do
        it 'uses template version' do
          merger = described_class.new(template, destination, preference: :template)
          result = merger.merge_result
          expect(result.to_s).to include('API_KEY=template_value')
          expect(result.to_s).not_to include('API_KEY=dest_value')
        end
      end
    end

    context 'with freeze blocks' do
      let(:template) do
        <<~DOTENV
          API_KEY=template_key
          SECRET=template_secret
        DOTENV
      end
      let(:destination) do
        <<~DOTENV
          API_KEY=dest_key
          # dotenv-merge:freeze
          SECRET=frozen_secret
          # dotenv-merge:unfreeze
        DOTENV
      end

      it 'preserves freeze block content' do
        merger = described_class.new(template, destination)
        result = merger.merge_result
        expect(result.to_s).to include('SECRET=frozen_secret')
        expect(result.to_s).to include('dotenv-merge:freeze')
        expect(result.to_s).to include('dotenv-merge:unfreeze')
      end

      it 'respects destination preference for non-frozen variables' do
        merger = described_class.new(template, destination)
        result = merger.merge_result
        expect(result.to_s).to include('API_KEY=dest_key')
      end
    end

    context 'with comments and blank lines' do
      let(:template) do
        <<~DOTENV
          # Template comment
          API_KEY=template

          NEW_VAR=new
        DOTENV
      end
      let(:destination) do
        <<~DOTENV
          # Destination comment
          API_KEY=dest

          CUSTOM=custom
        DOTENV
      end

      it 'preserves destination structure' do
        merger = described_class.new(template, destination)
        result = merger.merge_result
        expect(result.to_s).to include('# Destination comment')
        expect(result.to_s).to include('CUSTOM=custom')
      end

      it 'does not add template comments by default' do
        merger = described_class.new(template, destination, add_template_only_nodes: true)
        result = merger.merge_result
        # Template comments/blanks are skipped even with add_template_only_nodes
        expect(result.to_s).not_to include('# Template comment')
      end

      it 'preserves destination heading comments and inline comments when template content wins' do
        template = <<~DOTENV
          # Template heading
          API_KEY=template-value
        DOTENV
        destination = <<~DOTENV
          # Destination heading

          API_KEY=dest-value # local guidance
        DOTENV

        merger = described_class.new(template, destination, preference: :template)
        result = merger.merge_result

        expect(result.to_s).to include("# Destination heading\n\nAPI_KEY=template-value # local guidance")
        expect(result.to_s).not_to include('API_KEY=dest-value')
      end

      it 'keeps grouped destination comment sections and blank lines around template-preferred matches' do
        template = <<~DOTENV
          APP_ENV=production
          DATABASE_URL=postgres://prod/db
        DOTENV
        destination = <<~DOTENV
          # App settings
          APP_ENV=development # local mode

          # Database settings
          DATABASE_URL=postgres://localhost/dev
        DOTENV

        merger = described_class.new(template, destination, preference: :template)
        result = merger.merge_result

        expect(result.to_s).to include("# App settings\nAPP_ENV=production # local mode\n\n# Database settings\nDATABASE_URL=postgres://prod/db")
      end
    end

    context 'with document boundary comments' do
      let(:template) do
        <<~DOTENV
          API_KEY=template
        DOTENV
      end
      let(:destination) do
        <<~DOTENV
          # Header docs

          API_KEY=destination

          # Footer docs
        DOTENV
      end

      it 'preserves destination header and footer comments around a matched assignment' do
        merger = described_class.new(template, destination, preference: :template)
        result = merger.merge_result

        expect(result.to_s).to include('# Header docs')
        expect(result.to_s).to include('API_KEY=template')
        expect(result.to_s).to include('# Footer docs')
      end

      it 'preserves a shared interstitial comment block singularly between adjacent matched assignments' do
        template = <<~DOTENV
          ALPHA=1
          # Shared docs
          BETA=2
        DOTENV
        destination = <<~DOTENV
          ALPHA=9
          # Shared docs
          BETA=8
        DOTENV

        merged = described_class.new(template, destination).merge

        expect(merged.lines.grep("# Shared docs\n").size).to eq(1)
        expect(merged).to include("ALPHA=9\n# Shared docs\nBETA=8")
      end

      it 'collapses duplicated template-owned preamble prefixes in heal mode' do
        template = <<~DOTENV
          # Shared header

          ALPHA=1
        DOTENV
        destination = <<~DOTENV
          # Shared header
          # Shared header
          # Destination header
          ALPHA=9
        DOTENV

        merged = described_class.new(template, destination, add_template_only_nodes: true).merge

        expect(merged.lines.grep("# Shared header\n").size).to eq(0)
        expect(merged.lines.grep("# Destination header\n").size).to eq(1)
        expect(merged).to include('ALPHA=9')
      end

      it 'preserves duplicated template-owned preamble prefixes in skip mode' do
        template = <<~DOTENV
          # Shared header

          ALPHA=1
        DOTENV
        destination = <<~DOTENV
          # Shared header
          # Shared header
          # Destination header
          ALPHA=9
        DOTENV

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
        allow(Dotenv::Merge::DebugLogger).to receive(:debug_warning)

        template = <<~DOTENV
          # Shared header

          ALPHA=1
        DOTENV
        destination = <<~DOTENV
          # Shared header
          # Shared header
          # Destination header
          ALPHA=9
        DOTENV

        merged = described_class.new(
          template,
          destination,
          add_template_only_nodes: true,
          corruption_handling: :warn
        ).merge

        expect(Dotenv::Merge::DebugLogger).to have_received(:debug_warning).with(
          /Suspected corruption \(duplicate_template_preamble_prefix\)/,
          hash_including(template_comment_lines: 2, merged_comment_lines: 3, destination_specific_comment_lines: 1)
        )
        expect(merged.lines.grep("# Shared header\n").size).to eq(2)
      end

      it 'raises on duplicated template-owned preamble prefixes in error mode' do
        template = <<~DOTENV
          # Shared header

          ALPHA=1
        DOTENV
        destination = <<~DOTENV
          # Shared header
          # Shared header
          # Destination header
          ALPHA=9
        DOTENV

        expect do
          described_class.new(
            template,
            destination,
            add_template_only_nodes: true,
            corruption_handling: :error
          ).merge
        end.to raise_error(Dotenv::Merge::CorruptionDetectedError, /duplicate_template_preamble_prefix/)
      end
    end

    context 'with a comment-only destination' do
      let(:template) { "API_KEY=template\n" }
      let(:destination) do
        <<~DOTENV
          # Local-only notes
          # Still configuring this file
        DOTENV
      end

      it 'preserves the destination comments when there are no assignments to match' do
        merger = described_class.new(template, destination)
        result = merger.merge_result

        expect(result.to_s).to include('# Local-only notes')
        expect(result.to_s).to include('# Still configuring this file')
        expect(result.to_s).not_to include('API_KEY=template')
      end
    end

    context 'with export statements' do
      let(:template) { "export API_KEY=template\n" }
      let(:destination) { "export API_KEY=dest\n" }

      it 'matches exported variables' do
        merger = described_class.new(template, destination, preference: :template)
        result = merger.merge_result
        expect(result.to_s).to include('export API_KEY=template')
      end
    end

    context 'with complex merge' do
      let(:template) do
        <<~DOTENV
          # Application config
          APP_NAME=MyApp
          APP_ENV=production
          DEBUG=false

          # Database
          DATABASE_URL=postgres://prod-server/myapp

          # New feature
          FEATURE_FLAG=enabled
        DOTENV
      end
      let(:destination) do
        <<~DOTENV
          # Application config
          APP_NAME=MyApp
          APP_ENV=development
          DEBUG=true

          # Database
          # dotenv-merge:freeze
          DATABASE_URL=postgres://localhost/myapp_dev
          # dotenv-merge:unfreeze

          # Custom local settings
          CUSTOM_PATH=/usr/local/custom
        DOTENV
      end

      it 'produces correct merged output' do
        merger = described_class.new(
          template,
          destination,
          preference: :destination,
          add_template_only_nodes: true
        )
        result = merger.merge_result

        # Destination values preserved
        expect(result.to_s).to include('APP_ENV=development')
        expect(result.to_s).to include('DEBUG=true')

        # Freeze block preserved
        expect(result.to_s).to include('DATABASE_URL=postgres://localhost/myapp_dev')
        expect(result.to_s).to include('dotenv-merge:freeze')

        # Destination-only preserved
        expect(result.to_s).to include('CUSTOM_PATH=/usr/local/custom')

        # Template-only added
        expect(result.to_s).to include('FEATURE_FLAG=enabled')
      end
    end
  end

  describe 'custom freeze token' do
    let(:template) { "SECRET=template\n" }
    let(:destination) do
      <<~DOTENV
        # my-token:freeze
        SECRET=frozen
        # my-token:unfreeze
      DOTENV
    end

    it 'uses custom freeze token' do
      merger = described_class.new(template, destination, freeze_token: 'my-token')
      result = merger.merge_result
      expect(result.to_s).to include('SECRET=frozen')
      expect(result.to_s).to include('my-token:freeze')
    end

    it 'ignores freeze with wrong token' do
      merger = described_class.new(template, destination, freeze_token: 'other-token')
      result = merger.merge_result
      # Without recognizing freeze, it would match by key
      expect(result.to_s).to include('SECRET=')
    end
  end

  describe 'merge result information' do
    let(:template) do
      <<~DOTENV
        API_KEY=template
        NEW_VAR=new
      DOTENV
    end
    let(:destination) do
      <<~DOTENV
        API_KEY=dest
        CUSTOM=custom
      DOTENV
    end

    it 'provides summary' do
      merger = described_class.new(template, destination, add_template_only_nodes: true)
      result = merger.merge_result
      summary = result.summary

      expect(summary).to have_key(:total_decisions)
      expect(summary).to have_key(:total_lines)
      expect(summary).to have_key(:by_decision)
    end

    it 'tracks decisions correctly' do
      merger = described_class.new(template, destination, add_template_only_nodes: true)
      result = merger.merge_result
      summary = result.summary

      # API_KEY matched (dest wins), CUSTOM is dest-only, NEW_VAR is template-only (added)
      expect(summary[:total_decisions]).to eq(3)
    end
  end

  describe 'Hash preference with node_typing' do
    let(:template) do
      <<~DOTENV
        API_KEY=template_key
        SECRET=template_secret
      DOTENV
    end
    let(:destination) do
      <<~DOTENV
        API_KEY=dest_key
        SECRET=dest_secret
      DOTENV
    end

    context 'with node_typing callable' do
      it 'applies node_typing to resolve preference' do
        # Set up node_typing to mark API_KEY lines as :api_key type
        node_typing = {
          'EnvLine' => lambda { |stmt|
            if stmt.key == 'API_KEY'
              Ast::Merge::NodeTyping.with_merge_type(stmt, :api_key)
            else
              stmt
            end
          }
        }

        merger = described_class.new(
          template,
          destination,
          preference: { default: :destination, api_key: :template },
          node_typing: node_typing
        )
        result = merger.merge_result

        # API_KEY should use template (node_typing marked it, preference[:api_key] = :template)
        expect(result.to_s).to include('API_KEY=template_key')
        # SECRET should use destination (default)
        expect(result.to_s).to include('SECRET=dest_secret')
      end
    end

    context 'with Hash preference but no node_typing' do
      it 'falls back to default preference' do
        merger = described_class.new(
          template,
          destination,
          preference: { default: :template }
        )
        result = merger.merge_result

        # All should use template (default)
        expect(result.to_s).to include('API_KEY=template_key')
        expect(result.to_s).to include('SECRET=template_secret')
      end
    end

    context 'with Hash preference missing default' do
      it 'falls back to :destination' do
        merger = described_class.new(
          template,
          destination,
          preference: { some_other_type: :template }
        )
        result = merger.merge_result

        # Should use destination (fallback when no match and no :default)
        expect(result.to_s).to include('API_KEY=dest_key')
        expect(result.to_s).to include('SECRET=dest_secret')
      end
    end
  end

  describe 'freeze blocks in matched positions' do
    let(:template) do
      <<~DOTENV
        API_KEY=template_key
        SECRET=template_secret
      DOTENV
    end
    let(:destination) do
      <<~DOTENV
        # dotenv-merge:freeze
        API_KEY=frozen_key
        # dotenv-merge:unfreeze
        SECRET=dest_secret
      DOTENV
    end

    it 'uses freeze block for matched entry' do
      merger = described_class.new(template, destination, preference: :template)
      result = merger.merge_result

      # Even with :template preference, freeze block content is preserved
      expect(result.to_s).to include('API_KEY=frozen_key')
      expect(result.to_s).to include('dotenv-merge:freeze')
      # Non-frozen matched variable uses preference
      expect(result.to_s).to include('SECRET=template_secret')
    end
  end

  describe 'process_template_only with comments and blanks' do
    let(:template) do
      <<~DOTENV
        # Template comment
        API_KEY=template

        NEW_VAR=new_value
      DOTENV
    end
    let(:destination) { "OTHER_VAR=other\n" }

    it 'adds only assignment lines from template' do
      merger = described_class.new(template, destination, add_template_only_nodes: true)
      result = merger.merge_result

      # API_KEY doesn't match anything in dest, so it's template-only
      expect(result.to_s).to include('API_KEY=template')
      expect(result.to_s).to include('NEW_VAR=new_value')
      # Comments and blank lines are skipped
      expect(result.to_s).not_to include('# Template comment')
    end
  end

  describe 'process_dest_only with freeze blocks' do
    let(:template) { "API_KEY=template\n" }
    let(:destination) do
      <<~DOTENV
        API_KEY=dest
        # dotenv-merge:freeze
        FROZEN_VAR=frozen_value
        # dotenv-merge:unfreeze
        OTHER_VAR=other
      DOTENV
    end

    it 'handles dest-only freeze blocks' do
      merger = described_class.new(template, destination)
      result = merger.merge_result

      # Freeze block (FROZEN_VAR) is dest-only and should be preserved with markers
      expect(result.to_s).to include('FROZEN_VAR=frozen_value')
      expect(result.to_s).to include('dotenv-merge:freeze')
      expect(result.to_s).to include('dotenv-merge:unfreeze')
      # Regular dest-only should also be preserved
      expect(result.to_s).to include('OTHER_VAR=other')
    end
  end

  describe 'remove_template_missing_nodes with destination-only assignment comments' do
    let(:template) do
      <<~DOTENV
        KEEP_VAR=keep
      DOTENV
    end
    let(:destination) do
      <<~DOTENV
        KEEP_VAR=keep

        # Legacy docs
        REMOVE_VAR=remove-me # local-only note
      DOTENV
    end

    it 'preserves heading comments and promotes inline comments when removing destination-only assignments' do
      merger = described_class.new(template, destination, remove_template_missing_nodes: true)
      result = merger.merge_result

      expect(result.to_s).to include('# Legacy docs')
      expect(result.to_s).to include('# local-only note')
      expect(result.to_s).not_to include('REMOVE_VAR=remove-me')
      expect(result.to_s).to include('KEEP_VAR=keep')
    end

    it 'preserves trailing full-line docs when removing destination-only assignments' do
      destination = <<~DOTENV
        REMOVE_VAR=remove-me
        # trailing docs
        KEEP_VAR=keep
      DOTENV

      merger = described_class.new(template, destination, remove_template_missing_nodes: true)
      result = merger.merge_result

      expect(result.to_s).to eq(
        <<~DOTENV
          # trailing docs
          KEEP_VAR=keep
        DOTENV
      )
    end
  end
end
