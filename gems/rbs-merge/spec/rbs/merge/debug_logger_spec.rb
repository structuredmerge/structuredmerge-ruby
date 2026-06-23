# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

RSpec.describe Rbs::Merge::DebugLogger do
  # Use the shared examples to validate base DebugLogger integration
  it_behaves_like 'Ast::Merge::DebugLogger' do
    let(:described_logger) { described_class }
    let(:env_var_name) { 'RBS_MERGE_DEBUG' }
    let(:log_prefix) { '[rbs-merge]' }
  end
end
