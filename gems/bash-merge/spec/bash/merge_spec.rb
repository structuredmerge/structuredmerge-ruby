# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bash::Merge do
  it 'has a version number' do
    expect(Bash::Merge::VERSION).not_to be_nil
  end

  it 'has the expected version format' do
    expect(Bash::Merge::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  describe 'module structure' do
    it 'defines Error class inheriting from Ast::Merge::Error' do
      expect(Bash::Merge::Error).to be < Ast::Merge::Error
    end

    it 'defines ParseError class inheriting from Ast::Merge::ParseError' do
      expect(Bash::Merge::ParseError).to be < Ast::Merge::ParseError
    end

    it 'defines TemplateParseError class' do
      expect(Bash::Merge::TemplateParseError).to be < Bash::Merge::ParseError
    end

    it 'defines DestinationParseError class' do
      expect(Bash::Merge::DestinationParseError).to be < Bash::Merge::ParseError
    end
  end

  describe 'autoloaded classes' do
    it 'autoloads CommentTracker' do
      expect(Bash::Merge::CommentTracker).to be_a(Class)
    end

    it 'autoloads DebugLogger' do
      expect(Bash::Merge::DebugLogger).to be_a(Module)
    end

    it 'autoloads Emitter' do
      expect(Bash::Merge::Emitter).to be_a(Class)
    end

    it 'autoloads FreezeNode' do
      expect(Bash::Merge::FreezeNode).to be_a(Class)
    end

    it 'autoloads FileAnalysis' do
      expect(Bash::Merge::FileAnalysis).to be_a(Class)
    end

    it 'autoloads MergeResult' do
      expect(Bash::Merge::MergeResult).to be_a(Class)
    end

    it 'autoloads NodeWrapper' do
      expect(Bash::Merge::NodeWrapper).to be_a(Class)
    end

    it 'autoloads SmartMerger' do
      expect(Bash::Merge::SmartMerger).to be_a(Class)
    end
  end

  describe '.register_backend!' do
    it 'registers bash with TreeHaver when a grammar is available' do
      skip 'tree-sitter bash grammar is not available' unless TreeHaver::GrammarFinder.new(:bash).available?

      registrations = TreeHaver::LanguageRegistry.registered(:bash)

      expect(registrations).to be_a(Hash)
    end
  end

  describe '.availability' do
    it 'reports language-pack processing separately from node parser availability' do
      availability = described_class.availability

      expect(availability.language_pack_process).to eq(described_class.language_pack_process_available?)
      expect(availability.node_parser).to eq(described_class.available?)
      expect(availability.diagnostics).to be_an(Array)
    end
  end

  describe Bash::Merge::ParseError do
    it 'can be instantiated with no arguments' do
      error = described_class.new
      expect(error).to be_a(described_class)
      expect(error.errors).to eq([])
      expect(error.content).to be_nil
    end

    it 'can be instantiated with a message' do
      error = described_class.new('custom message')
      expect(error.message).to eq('custom message')
    end

    it 'can be instantiated with content' do
      error = described_class.new(content: 'echo "invalid')
      expect(error.content).to eq('echo "invalid')
    end

    it 'can be instantiated with errors array' do
      errors = [StandardError.new('error 1'), StandardError.new('error 2')]
      error = described_class.new(errors: errors)
      expect(error.errors).to eq(errors)
    end

    it 'can be instantiated with all arguments' do
      errors = [StandardError.new('parse error')]
      error = described_class.new('failed to parse', content: 'echo "bad', errors: errors)
      expect(error.message).to eq('failed to parse')
      expect(error.content).to eq('echo "bad')
      expect(error.errors).to eq(errors)
    end
  end

  describe Bash::Merge::TemplateParseError do
    it 'inherits from ParseError' do
      expect(described_class.superclass).to eq(Bash::Merge::ParseError)
    end

    it 'can be instantiated' do
      error = described_class.new('template error', content: 'echo "bad')
      expect(error.message).to eq('template error')
      expect(error.content).to eq('echo "bad')
    end
  end

  describe Bash::Merge::DestinationParseError do
    it 'inherits from ParseError' do
      expect(described_class.superclass).to eq(Bash::Merge::ParseError)
    end

    it 'can be instantiated' do
      error = described_class.new('destination error', content: 'echo "bad')
      expect(error.message).to eq('destination error')
      expect(error.content).to eq('echo "bad')
    end
  end
end
