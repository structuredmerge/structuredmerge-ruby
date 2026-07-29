# frozen_string_literal: true

require 'anonymous_loader'
RSpec.describe Smorg::RB::Version do
  it_behaves_like 'a Version module', described_class

  it 'executes the version file for coverage without redefining constants' do
    path = File.expand_path('../../../lib/smorg/rb/version.rb', __dir__)
    anonymous_namespace = AnonymousLoader.load(files: path)

    expect(anonymous_namespace::Smorg::RB::Version::VERSION).to eq(described_class::VERSION)
  end
end
