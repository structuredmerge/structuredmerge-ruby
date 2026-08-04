# frozen_string_literal: true

require 'anonymous_loader'
require 'binary/merge'
RSpec.describe Binary::Merge::Version do
  it_behaves_like 'a Version module', described_class

  it 'executes the version file for coverage without redefining constants' do
    path = File.expand_path('../../../lib/binary/merge/version.rb', __dir__)
    anonymous_namespace = AnonymousLoader.load(files: path)

    expect(anonymous_namespace::Binary::Merge::Version::VERSION).to eq(described_class::VERSION)
  end
end
