# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Prism::Merge::MethodMatchRefiner do
  def parse_method(source)
    Prism.parse(source).value.statements.body.first
  end

  it 'delegates Ruby method similarity while adapting Prism method nodes' do
    refiner = described_class.new(threshold: 0.5)
    template_node = parse_method('def process_user(user, options); end')
    dest_node = parse_method('def process_users(user, config); end')

    matches = refiner.call([template_node], [dest_node])

    expect(matches.length).to eq(1)
    expect(matches.first.template_node).to eq(template_node)
    expect(matches.first.dest_node).to eq(dest_node)
    expect(matches.first.score).to be > 0.75
  end
end
