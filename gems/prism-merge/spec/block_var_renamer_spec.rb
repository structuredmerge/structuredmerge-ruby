# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Prism::Merge::BlockVarRenamer do
  it 'normalizes a selected block parameter and its receiver references' do
    source = <<~RUBY
      RSpec.configure do |cfg|
        cfg.order = :random
      end
    RUBY
    binding = Prism::Merge::BlockBinding.find(source) { |call| call.receiver&.slice == 'RSpec' && call.name == :configure }

    expect(described_class.normalize(source, binding: binding, canonical_name: 'config')).to eq(<<~RUBY)
      RSpec.configure do |config|
        config.order = :random
      end
    RUBY
  end

  it 'does not rewrite matching receivers outside the selected block' do
    source = <<~RUBY
      cfg = Object.new
      RSpec.configure do |cfg|
        cfg.order = :random
      end
      cfg.inspect
    RUBY
    binding = Prism::Merge::BlockBinding.find(source) { |call| call.receiver&.slice == 'RSpec' && call.name == :configure }

    normalized = described_class.normalize(source, binding: binding, canonical_name: 'config')

    expect(normalized).to include("cfg = Object.new\n")
    expect(normalized).to include('config.order = :random')
    expect(normalized).to end_with("cfg.inspect\n")
  end

  it 'does not rewrite a nested block that shadows the selected parameter' do
    source = <<~RUBY
      RSpec.configure do |cfg|
        cfg.before do |cfg|
          cfg.example = :nested
        end
        cfg.order = :random
      end
    RUBY
    binding = Prism::Merge::BlockBinding.find(source) { |call| call.receiver&.slice == 'RSpec' && call.name == :configure }

    normalized = described_class.normalize(source, binding: binding, canonical_name: 'config')

    expect(normalized).to include('RSpec.configure do |config|')
    expect(normalized).to include('config.before do |cfg|')
    expect(normalized).to include('cfg.example = :nested')
    expect(normalized).to include('config.order = :random')
  end
end
