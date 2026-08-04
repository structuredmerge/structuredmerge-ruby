# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Prism::Merge::BeginNodeRescueSemantics do
  describe '#rewrite_local_reference_in_source' do
    it 'applies Prism byte offsets after non-ASCII content' do
      semantics = described_class.new(template_analysis: nil, dest_analysis: nil)
      source = <<~RUBY
        metadata = "🔖 release"
        puts destination_error.message
      RUBY

      updated = semantics.send(
        :rewrite_local_reference_in_source,
        source,
        from: 'destination_error',
        to: 'template_error'
      )

      expect(updated).to include('metadata = "🔖 release"')
      expect(updated).to include('puts template_error.message')
      if defined?(RubyVM::InstructionSequence)
        expect(RubyVM::InstructionSequence.compile(updated)).to be_a(RubyVM::InstructionSequence)
      end
    end
  end

  describe '#source_defined_exception_definitions' do
    it 'collects nested source exception definitions without recursive initialization' do
      analysis = Struct.new(:parse_result).new(
        Prism.parse(<<~RUBY)
          module Example
            class Error < StandardError
            end
          end
        RUBY
      )
      semantics = described_class.new(template_analysis: analysis, dest_analysis: nil)

      expect(semantics.send(:source_defined_exception_definitions)).to include(
        name: 'Example::Error',
        namespace: 'Example',
        superclass: 'StandardError'
      )
    end
  end
end
