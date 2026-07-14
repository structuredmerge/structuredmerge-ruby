# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Kettle::Jem do
  describe ".replace_source_offsets" do
    it "applies Prism byte offsets after non-ASCII content" do
      source = <<~RUBY
        Gem::Specification.new do |spec|
          spec.summary = "🔖 release metadata"
          spec.add_dependency("demo_gem", ">= 1.0.0")
        end
      RUBY
      parse_result = Prism.parse(source)
      dependency = parse_result.value.breadth_first_search do |node|
        node.is_a?(Prism::CallNode) && node.name == :add_dependency
      end
      floor_node = dependency.arguments.arguments.last

      updated = described_class.send(
        :replace_source_offsets,
        source,
        [
          {
            start_offset: floor_node.location.start_offset,
            end_offset: floor_node.location.end_offset,
            replacement: %(">= 1.0.1")
          }
        ]
      )

      expect(updated).to include('spec.summary = "🔖 release metadata"')
      expect(updated).to include('spec.add_dependency("demo_gem", ">= 1.0.1")')
      expect(RubyVM::InstructionSequence.compile(updated)).to be_a(RubyVM::InstructionSequence) if defined?(RubyVM::InstructionSequence)
    end
  end
end
