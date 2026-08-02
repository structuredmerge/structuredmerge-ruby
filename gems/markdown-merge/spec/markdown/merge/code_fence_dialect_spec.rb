# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe Markdown::Merge do
  it 'routes JSON5 fenced blocks to the JSON merge family and dialect' do
    expect(described_class.code_fence_family('json5')).to eq('json')
    expect(described_class.code_fence_dialect('json5', 'json')).to eq('json5')
  end
end
