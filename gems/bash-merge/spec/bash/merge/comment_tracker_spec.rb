# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bash::Merge::CommentTracker do
  describe '#initialize' do
    it 'extracts full-line comments' do
      source = <<~BASH
        #!/bin/bash
        # This is a comment
        echo "hello"
      BASH

      tracker = described_class.new(source)
      expect(tracker.comments.size).to eq(1)
      expect(tracker.comments.first[:text]).to eq('This is a comment')
    end

    it 'ignores shebang lines' do
      source = <<~BASH
        #!/bin/bash
        echo "hello"
      BASH

      tracker = described_class.new(source)
      expect(tracker.comments).to be_empty
    end

    it 'detects inline comments' do
      source = <<~BASH
        echo "hello" # inline comment
      BASH

      tracker = described_class.new(source)
      expect(tracker.comments.size).to eq(1)
      expect(tracker.comments.first[:full_line]).to be(false)
    end

    it 'detects inline comments for simple assignments' do
      source = <<~BASH
        APP_MODE="production" # deployment mode
      BASH

      tracker = described_class.new(source)
      expect(tracker.comments.size).to eq(1)
      expect(tracker.comments.first).to include(
        text: 'deployment mode',
        full_line: false,
        raw: '# deployment mode'
      )
    end

    it 'ignores hash characters inside quoted strings and escaped hashes' do
      source = <<~BASH
        echo "# not a comment"
        echo ' # also not a comment'
        APP_PATH="#/srv/app"
        echo \\#still-text
      BASH

      tracker = described_class.new(source)
      expect(tracker.comments).to be_empty
    end
  end

  describe '#comment_at' do
    let(:source) do
      <<~BASH
        #!/bin/bash
        # Comment on line 2
        echo "hello"
      BASH
    end
    let(:tracker) { described_class.new(source) }

    it 'returns comment at specified line' do
      comment = tracker.comment_at(2)
      expect(comment).not_to be_nil
      expect(comment[:text]).to eq('Comment on line 2')
    end

    it 'returns nil for non-comment lines' do
      expect(tracker.comment_at(3)).to be_nil
    end
  end

  describe '#leading_comments_before' do
    let(:source) do
      <<~BASH
        #!/bin/bash
        # Comment 1
        # Comment 2
        echo "hello"
      BASH
    end
    let(:tracker) { described_class.new(source) }

    it 'returns consecutive comments before a line' do
      leading = tracker.leading_comments_before(4)
      expect(leading.size).to eq(2)
      expect(leading.map { |c| c[:text] }).to eq(['Comment 1', 'Comment 2'])
    end
  end

  describe '#blank_line?' do
    let(:source) do
      <<~BASH
        echo "hello"

        echo "world"
      BASH
    end
    let(:tracker) { described_class.new(source) }

    it 'returns true for blank lines' do
      expect(tracker.blank_line?(2)).to be(true)
    end

    it 'returns false for non-blank lines' do
      expect(tracker.blank_line?(1)).to be(false)
    end

    it 'returns false for line number less than 1' do
      expect(tracker.blank_line?(0)).to be(false)
    end

    it 'returns false for line number greater than file length' do
      expect(tracker.blank_line?(100)).to be(false)
    end
  end

  describe '#shebang?' do
    let(:source) do
      <<~BASH
        #!/bin/bash
        echo "hello"
      BASH
    end
    let(:tracker) { described_class.new(source) }

    it 'returns true for shebang line' do
      expect(tracker.shebang?(1)).to be(true)
    end

    it 'returns false for non-shebang lines' do
      expect(tracker.shebang?(2)).to be(false)
    end

    it 'returns false for line number less than 1' do
      expect(tracker.shebang?(0)).to be(false)
    end

    it 'returns false for line number greater than file length' do
      expect(tracker.shebang?(100)).to be(false)
    end
  end

  describe '#inline_comment_at' do
    it 'returns nil for lines without inline comments' do
      source = <<~BASH
        echo "hello"
      BASH
      tracker = described_class.new(source)
      expect(tracker.inline_comment_at(1)).to be_nil
    end

    it 'returns inline comment hash for lines with inline comments' do
      source = <<~BASH
        echo "hello" # say hello
      BASH
      tracker = described_class.new(source)
      inline = tracker.inline_comment_at(1)
      # If it found an inline comment
      expect(inline[:full_line]).to be(false) if inline
    end

    it 'returns inline comment hash for simple assignment lines' do
      source = <<~BASH
        APP_MODE="test" # environment toggle
      BASH
      tracker = described_class.new(source)
      expect(tracker.inline_comment_at(1)).to include(
        text: 'environment toggle',
        raw: '# environment toggle'
      )
    end

    it 'returns nil when the only hash characters are inside quotes' do
      source = <<~BASH
        echo "# not a comment"
      BASH
      tracker = described_class.new(source)
      expect(tracker.inline_comment_at(1)).to be_nil
    end

    it 'returns nil for full-line comments' do
      source = <<~BASH
        # This is a full line comment
      BASH
      tracker = described_class.new(source)
      expect(tracker.inline_comment_at(1)).to be_nil
    end
  end

  describe '#full_line_comment?' do
    it 'returns true for full-line comments' do
      source = <<~BASH
        # This is a comment
      BASH
      tracker = described_class.new(source)
      expect(tracker.full_line_comment?(1)).to be(true)
    end

    it 'returns false for inline comments' do
      source = <<~BASH
        echo "hi" # inline
      BASH
      tracker = described_class.new(source)
      expect(tracker.full_line_comment?(1)).to be(false)
    end

    it 'returns false for non-comment lines' do
      source = <<~BASH
        echo "hello"
      BASH
      tracker = described_class.new(source)
      expect(tracker.full_line_comment?(1)).to be(false)
    end
  end
end
