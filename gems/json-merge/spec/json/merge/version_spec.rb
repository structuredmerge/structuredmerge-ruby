# frozen_string_literal: true

require 'anonymous_loader'
require 'json/merge'
RSpec.describe Json::Merge::Version do
  it_behaves_like 'a Version module', described_class

  it 'executes the version file for coverage without redefining constants' do
    path = File.expand_path('../../../lib/json/merge/version.rb', __dir__)
    anonymous_namespace = AnonymousLoader.load(files: path)

    expect(anonymous_namespace::Json::Merge::Version::VERSION).to eq(described_class::VERSION)
  end
end
