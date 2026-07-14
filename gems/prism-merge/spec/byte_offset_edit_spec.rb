# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Prism::Merge::BeginNodeRescueSemantics do
  describe "#rewrite_local_reference_in_source" do
    it "applies Prism byte offsets after non-ASCII content" do
      semantics = described_class.new(template_analysis: nil, dest_analysis: nil)
      source = <<~RUBY
        metadata = "🔖 release"
        puts destination_error.message
      RUBY

      updated = semantics.send(
        :rewrite_local_reference_in_source,
        source,
        from: "destination_error",
        to: "template_error"
      )

      expect(updated).to include('metadata = "🔖 release"')
      expect(updated).to include("puts template_error.message")
      expect(RubyVM::InstructionSequence.compile(updated)).to be_a(RubyVM::InstructionSequence) if defined?(RubyVM::InstructionSequence)
    end
  end
end
