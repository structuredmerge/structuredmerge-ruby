# frozen_string_literal: true

require 'spec_helper'
require 'json/merge'

RSpec.describe Json::Merge::SmartMerger, :json_grammar do
  it 'preserves destination blank gaps between retained matched pairs' do
    template = <<~JSON
      {
        "alpha": "1",
        "beta": "2"
      }
    JSON
    destination = <<~JSON
      {
        "alpha": "9",

        "beta": "8"
      }
    JSON

    expect(described_class.new(template, destination).merge).to eq(destination)
  end

  it 'preserves destination blank gaps between retained matched pairs under template preference' do
    template = <<~JSON
      {
        "alpha": "1",
        "beta": "2"
      }
    JSON
    destination = <<~JSON
      {
        "alpha": "9",

        "beta": "8"
      }
    JSON
    expected = <<~JSON
      {
        "alpha": "1",

        "beta": "2"
      }
    JSON

    expect(described_class.new(template, destination, preference: :template).merge).to eq(expected)
  end

  it 'preserves destination blank gaps between retained matched nested pairs under template preference' do
    template = <<~JSON
      {
        "app": {
          "alpha": "1",
          "beta": "2"
        }
      }
    JSON
    destination = <<~JSON
      {
        "app": {
          "alpha": "9",

          "beta": "8"
        }
      }
    JSON
    expected = <<~JSON
      {
        "app": {
          "alpha": "1",

          "beta": "2"
        }
      }
    JSON

    expect(described_class.new(template, destination, preference: :template).merge).to eq(expected)
  end

  it 'preserves destination blank gaps before nested destination-only pairs' do
    template = <<~JSON
      {
        "app": {
          "managed": "new"
        }
      }
    JSON
    destination = <<~JSON
      {
        "app": {
          "managed": "current",

          "local": true
        }
      }
    JSON

    expect(described_class.new(template, destination).merge).to eq(destination)
  end
end
