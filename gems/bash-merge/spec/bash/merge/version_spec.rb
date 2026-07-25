# frozen_string_literal: true

require 'spec_helper'
require "anonymous_loader"

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

it "executes the version file for coverage without redefining constants" do
  path = File.expand_path("../../../lib/bash/merge/version.rb", __dir__)
  anonymous_namespace = AnonymousLoader.load(files: path)

  expect(anonymous_namespace::Bash::Merge::Version::VERSION).to eq(described_class::VERSION)
end
end
