# frozen_string_literal: true

require 'anonymous_loader'
require 'ast/crispr'
RSpec.describe Ast::Crispr::Version do
  it_behaves_like 'a Version module', described_class

  it 'executes the version file for coverage without redefining constants' do
    path = File.expand_path('../../../lib/ast/crispr/version.rb', __dir__)
    anonymous_namespace = AnonymousLoader.load(files: path)

    expect(anonymous_namespace::Ast::Crispr::Version::VERSION).to eq(described_class::VERSION)
  end
end
