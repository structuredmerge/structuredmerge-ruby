# frozen_string_literal: true

require 'anonymous_loader'
require 'toml/merge'
RSpec.describe Toml::Merge::Version do
  it_behaves_like 'a Version module', described_class

  it 'executes the version file for coverage without redefining constants' do
    path = File.expand_path('../../../lib/toml/merge/version.rb', __dir__)
    anonymous_namespace = AnonymousLoader.load(files: path)

    expect(anonymous_namespace::Toml::Merge::Version::VERSION).to eq(described_class::VERSION)
  end
end
