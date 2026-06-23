# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bash::Merge::Version do
  it_behaves_like 'a Version module', described_class

  describe 'VERSION' do
    it 'is a string' do
      expect(Bash::Merge::VERSION).to be_a(String)
    end

    it 'follows semantic versioning format' do
      expect(Bash::Merge::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end
end
