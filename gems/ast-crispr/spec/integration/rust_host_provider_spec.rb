# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ast::Crispr::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled Rust host is unavailable' unless described_class.available? }

  it 'advertises profile-report capabilities without claiming edit execution' do
    expect(provider.provider_id).to eq('rust.ast-crispr.profile')
    expect(provider.capabilities).to include(
      backend: :rust_tslp,
      execution: :profile_reports_only,
      source_projection: :ruby_owned
    )
  end

  it 'round-trips the Rust operation profile report' do
    report = provider.report(
      kind: 'operation',
      operation_kind: 'insert',
      source_requirement: 'none',
      destination_requirement: 'optional',
      replacement_source: 'explicit_text',
      captures_source_text: false,
      supports_if_missing: true
    )

    expect(report).to include(
      'operation_kind' => 'insert',
      'supports_destination' => true,
      'supports_if_missing' => true
    )
  end

  it 'round-trips a batch report while keeping execution Ruby-owned' do
    report = provider.report(
      kind: 'batch_operations',
      operations: [
        {
          operation_kind: 'replace',
          source_requirement: 'required',
          destination_requirement: 'none',
          replacement_source: 'explicit_text',
          captures_source_text: true,
          supports_if_missing: false
        }
      ]
    )

    expect(report).to include('operation_count' => 1, 'operation_kinds' => ['replace'])
  end
end
