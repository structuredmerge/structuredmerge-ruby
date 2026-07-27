# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Yaml::Merge::SmartMerger, :yaml_grammar do
  it 'preserves destination blank gaps between retained matched top-level pairs under template preference' do
    template = <<~YAML
      alpha: 1
      beta: 2
    YAML
    destination = <<~YAML
      alpha: 9

      beta: 8
    YAML
    expected = <<~YAML
      alpha: 1

      beta: 2
    YAML

    expect(described_class.new(template, destination, preference: :template).merge).to eq(expected)
  end

  it 'preserves destination blank gaps between retained matched nested pairs under template preference' do
    template = <<~YAML
      app:
        alpha: 1
        beta: 2
    YAML
    destination = <<~YAML
      app:
        alpha: 9

        beta: 8
    YAML
    expected = <<~YAML
      app:
        alpha: 1

        beta: 2
    YAML

    expect(described_class.new(template, destination, preference: :template).merge).to eq(expected)
  end
end
