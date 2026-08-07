# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Ruby::Merge::RubyHashLiteralProjector do
  it 'projects Ruby hash literals through TreeHaver nodes' do
    hash = described_class.new(
      '{ foo: 1, "quoted": 2, :sym => 3, "str" => { nested: true }, works?: call(1, 2), }'
    ).call

    expect(hash).to be_a(Ruby::Merge::RubyHashNode)
    expect(hash.trailing_comma).to be(true)
    expect(hash.pairs.map(&:key)).to eq(%w[foo quoted sym str works?])
    expect(hash.pairs.map(&:delimiter)).to eq([':', ':', '=>', '=>', ':'])
    expect(hash.pairs[3].value).to be_a(Ruby::Merge::RubyHashNode)
    expect(hash.pairs[4].value.source).to eq('call(1, 2)')
  end
end
