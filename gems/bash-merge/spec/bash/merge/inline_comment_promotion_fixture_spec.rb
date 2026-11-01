# frozen_string_literal: true

require 'json'
require 'spec_helper'

RSpec.describe Bash::Merge::SmartMerger, 'shared inline-promotion fixture' do
  it 'matches the Ruby provider output recorded in the shared contract' do
    path = File.expand_path('../../../../../../fixtures/polyglot/ast-merge/removed_owner_inline_promotion.json',
                            __dir__)
    fixture = JSON.parse(File.read(path))

    fixture.fetch('cases').each do |entry|
      output = described_class.new(
        entry.fetch('template'),
        entry.fetch('source'),
        remove_template_missing_nodes: true
      ).merge

      expect(output).to eq(entry.dig('expected', 'output')), entry.fetch('name')
    end
  end
end
