# frozen_string_literal: true

require 'ast/merge/text'

RSpec.describe Ast::Merge::Text::MergeResult do
  describe '#add_line' do
    it 'adds a single line' do
      result = described_class.new
      result.add_line('Hello world')

      expect(result.to_s).to eq("Hello world\n")
    end
  end

  describe '#add_lines' do
    it 'adds multiple lines at once' do
      result = described_class.new
      result.add_lines(['Line one', 'Line two', 'Line three'])

      expect(result.to_s).to eq("Line one\nLine two\nLine three\n")
    end
  end

  describe '#record_decision' do
    it 'records decisions with node information' do
      result = described_class.new
      template_node = Ast::Merge::Text::LineNode.new('Hello', line_number: 1)
      dest_node = Ast::Merge::Text::LineNode.new('World', line_number: 1)

      result.add_line('World')
      result.record_decision(:kept_dest, template_node, dest_node)

      expect(result.decisions.size).to eq(1)
      expect(result.decisions.first[:decision]).to eq(:kept_dest)
      expect(result.decisions.first[:template_node]).to eq(template_node)
      expect(result.decisions.first[:dest_node]).to eq(dest_node)
    end
  end

  describe '#to_s' do
    it 'joins lines with newlines' do
      result = described_class.new
      result.add_line('Line one')
      result.add_line('Line two')
      result.add_line('Line three')

      expect(result.to_s).to eq("Line one\nLine two\nLine three\n")
    end

    it 'returns empty string for no lines' do
      result = described_class.new

      expect(result.to_s).to eq('')
    end
  end
end
