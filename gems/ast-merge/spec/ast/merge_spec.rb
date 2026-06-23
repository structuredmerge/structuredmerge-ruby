# frozen_string_literal: true

RSpec.describe Ast::Merge do
  it 'has a version number' do
    expect(Ast::Merge::VERSION).not_to be_nil
  end

  # - Testing nested error classes within module describe
  describe Ast::Merge::ParseError do
    describe '#initialize' do
      context 'with custom message' do
        it 'uses the provided message' do
          error = Ast::Merge::ParseError.new('Custom error message')
          expect(error.message).to eq('Custom error message')
        end
      end

      context 'without custom message and empty errors' do
        it 'generates a default message' do
          error = Ast::Merge::ParseError.new(errors: [])
          expect(error.message).to include('ast merge parseerror')
        end
      end

      context 'without custom message and with errors' do
        it 'generates message from errors' do
          error_obj = double('Error', message: 'syntax error on line 1')
          error = Ast::Merge::ParseError.new(errors: [error_obj])
          expect(error.message).to include('syntax error on line 1')
        end

        it 'handles errors that respond to to_s but not message' do
          error_obj = 'simple string error'
          error = Ast::Merge::ParseError.new(errors: [error_obj])
          expect(error.message).to include('simple string error')
        end

        it 'joins multiple errors' do
          error1 = double('Error1', message: 'error one')
          error2 = double('Error2', message: 'error two')
          error = Ast::Merge::ParseError.new(errors: [error1, error2])
          expect(error.message).to include('error one')
          expect(error.message).to include('error two')
        end
      end

      context 'with content' do
        it 'stores the content' do
          error = Ast::Merge::ParseError.new('Error', content: 'some source code')
          expect(error.content).to eq('some source code')
        end
      end

      context 'with errors array' do
        it 'stores the errors' do
          errors = [double('Error1'), double('Error2')]
          error = Ast::Merge::ParseError.new('Error', errors: errors)
          expect(error.errors).to eq(errors)
        end

        it 'wraps single error in array' do
          single_error = double('Error')
          error = Ast::Merge::ParseError.new('Error', errors: single_error)
          expect(error.errors).to eq([single_error])
        end
      end
    end
  end

  describe Ast::Merge::TemplateParseError do
    it 'inherits from ParseError' do
      expect(Ast::Merge::TemplateParseError).to be < Ast::Merge::ParseError
    end

    it 'can be instantiated' do
      error = Ast::Merge::TemplateParseError.new('Template parse failed')
      expect(error.message).to eq('Template parse failed')
    end
  end

  describe Ast::Merge::DestinationParseError do
    it 'inherits from ParseError' do
      expect(Ast::Merge::DestinationParseError).to be < Ast::Merge::ParseError
    end

    it 'can be instantiated' do
      error = Ast::Merge::DestinationParseError.new('Destination parse failed')
      expect(error.message).to eq('Destination parse failed')
    end
  end
end
