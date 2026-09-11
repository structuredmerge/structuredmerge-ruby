# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'RBS native parser selection' do
  it 'preserves the native RBS parser under the Rust TSLP fallback context' do
    skip 'native RBS parser is unavailable' unless Rbs::Merge::Backends::RbsBackend.available?

    analysis = TreeHaver.with_backend(:rust_tslp) do
      Rbs::Merge::FileAnalysis.new("module Version\n  VERSION: String\nend\n")
    end

    expect(analysis).to be_valid
    expect(analysis.backend).to eq(:rbs)
    expect(analysis.statements.map(&:signature)).to eq([[:module, 'Version']])
  end
end
