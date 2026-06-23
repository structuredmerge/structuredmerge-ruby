# frozen_string_literal: true

RSpec.describe Dotenv::Merge do
  it 'has a version number' do
    expect(Dotenv::Merge::VERSION).not_to be_nil
  end

  describe Dotenv::Merge::Error do
    it 'inherits from Ast::Merge::Error' do
      expect(described_class.superclass).to eq(Ast::Merge::Error)
    end

    it 'can be instantiated with a message' do
      error = described_class.new('test error')
      expect(error.message).to eq('test error')
    end
  end

  describe Dotenv::Merge::ParseError do
    it 'inherits from Ast::Merge::ParseError' do
      expect(described_class.superclass).to eq(Ast::Merge::ParseError)
    end

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
      error = described_class.new(content: 'API_KEY=value')
      expect(error.content).to eq('API_KEY=value')
    end

    it 'can be instantiated with errors array' do
      errors = [StandardError.new('error 1'), StandardError.new('error 2')]
      error = described_class.new(errors: errors)
      expect(error.errors).to eq(errors)
    end

    it 'can be instantiated with all arguments' do
      errors = [StandardError.new('parse error')]
      error = described_class.new('failed to parse', content: 'BAD=', errors: errors)
      expect(error.message).to eq('failed to parse')
      expect(error.content).to eq('BAD=')
      expect(error.errors).to eq(errors)
    end
  end

  describe Dotenv::Merge::TemplateParseError do
    it 'inherits from Dotenv::Merge::ParseError' do
      expect(described_class.superclass).to eq(Dotenv::Merge::ParseError)
    end

    it 'can be instantiated' do
      error = described_class.new('template error', content: 'BAD_TEMPLATE')
      expect(error.message).to eq('template error')
      expect(error.content).to eq('BAD_TEMPLATE')
    end
  end

  describe Dotenv::Merge::DestinationParseError do
    it 'inherits from Dotenv::Merge::ParseError' do
      expect(described_class.superclass).to eq(Dotenv::Merge::ParseError)
    end

    it 'can be instantiated' do
      error = described_class.new('destination error', content: 'BAD_DEST')
      expect(error.message).to eq('destination error')
      expect(error.content).to eq('BAD_DEST')
    end
  end
end
