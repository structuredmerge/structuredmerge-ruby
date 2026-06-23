# frozen_string_literal: true

RSpec.describe Dotenv::Merge::CommentTracker do
  describe 'comment extraction' do
    it 'extracts full-line comments' do
      tracker = described_class.new(<<~DOTENV)
        # Database configuration
        DATABASE_URL=postgres://localhost/db
      DOTENV

      expect(tracker.comments).to include(
        include(
          line: 1,
          indent: 0,
          text: 'Database configuration',
          full_line: true,
          raw: '# Database configuration'
        )
      )
    end

    it 'extracts safe inline comments from unquoted assignments' do
      tracker = described_class.new("PORT=3000 # default port\n")

      expect(tracker.inline_comment_at(1)).to include(
        line: 1,
        text: 'default port',
        full_line: false,
        raw: '# default port'
      )
    end

    it 'ignores # inside quoted values' do
      tracker = described_class.new(<<~DOTENV)
        PASSWORD="abc#123"
        TOKEN='xyz#789'
      DOTENV

      expect(tracker.comments).to be_empty
    end

    it 'ignores # in unquoted values when it is not preceded by whitespace' do
      tracker = described_class.new("PASSWORD=abc#123\n")

      expect(tracker.comments).to be_empty
    end
  end

  describe 'shared comment capability' do
    let(:tracker) do
      described_class.new(<<~DOTENV)
        # Header docs

        API_KEY=secret # default secret

        # Footer docs
      DOTENV
    end

    it 'builds shared comment nodes' do
      expect(tracker.comment_nodes.map(&:line_number)).to eq([1, 3, 5])
      expect(tracker.comment_node_at(1).to_s).to eq('# Header docs')
      expect(tracker.comment_node_at(3).to_s).to eq('# default secret')
    end

    it 'builds comment regions for ranges' do
      region = tracker.comment_region_for_range(1..3, kind: :orphan)
      full_line_region = tracker.comment_region_for_range(1..3, kind: :leading, full_line_only: true)

      expect(region.nodes.map(&:line_number)).to eq([1, 3])
      expect(full_line_region.nodes.map(&:line_number)).to eq([1])
    end

    it 'builds a source-augmented augmenter with attachments and postlude' do
      analysis = Dotenv::Merge::FileAnalysis.new(<<~DOTENV)
        # Header docs

        API_KEY=secret # default secret

        # Footer docs
      DOTENV
      owner = analysis.env_var('API_KEY')
      augmenter = tracker.augment(owners: [owner])
      attachment = augmenter.attachment_for(owner)

      expect(augmenter.capability.source_augmented?).to be true
      expect(attachment.leading_region).to be_nil
      expect(augmenter.preamble_region.normalized_content).to eq('Header docs')
      expect(attachment.inline_region.normalized_content).to eq('default secret')
      expect(augmenter.postlude_region.normalized_content).to eq('Footer docs')
    end
  end
end
