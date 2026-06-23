# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rbs::Merge do
  it 'has a version number' do
    expect(Rbs::Merge::VERSION).not_to be_nil
  end

  describe 'Error classes' do
    describe Rbs::Merge::Error do
      it 'inherits from Ast::Merge::Error' do
        expect(described_class).to be < Ast::Merge::Error
      end
    end

    describe Rbs::Merge::ParseError do
      it 'inherits from Ast::Merge::ParseError' do
        expect(described_class).to be < Ast::Merge::ParseError
      end
    end

    describe Rbs::Merge::TemplateParseError do
      it 'inherits from Rbs::Merge::ParseError' do
        expect(described_class).to be < Rbs::Merge::ParseError
      end

      it 'stores errors' do
        mock_error = double('RBS::BaseError', message: 'syntax error')
        error = described_class.new(errors: [mock_error])
        expect(error.errors).to eq([mock_error])
        expect(error.message).to include('syntax error')
      end
    end

    describe Rbs::Merge::DestinationParseError do
      it 'inherits from Rbs::Merge::ParseError' do
        expect(described_class).to be < Rbs::Merge::ParseError
      end

      it 'stores errors' do
        mock_error = double('RBS::BaseError', message: 'parse error')
        error = described_class.new(errors: [mock_error])
        expect(error.errors).to eq([mock_error])
        expect(error.message).to include('parse error')
      end
    end
  end
end
