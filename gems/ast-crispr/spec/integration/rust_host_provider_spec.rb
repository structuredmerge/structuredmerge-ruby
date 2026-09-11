# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ast::Crispr::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled Rust host is unavailable' unless described_class.available? }

  it 'advertises profile reports and explicit source edits without claiming selection' do
    expect(provider.provider_id).to eq('rust.ast-crispr.profile')
    expect(provider.capabilities).to include(
      backend: :rust_tslp,
      execution: :profile_reports_and_explicit_source_edits,
      source_projection: :explicit_byte_ranges,
      structural_selection: :ruby_owned
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

  it 'round-trips a batch report while keeping structural selection Ruby-owned' do
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

  it 'applies explicit UTF-8 source edits through the Rust renderer' do
    report = provider.apply_source_edits(
      source: "alpha = 1\nβeta = 2\n",
      edits: [
        { start_byte: 8, end_byte: 9, replacement: '9' },
        { start_byte: 10, end_byte: 15, replacement: 'gamma' }
      ]
    )

    expect(report).to include(
      'ok' => true,
      'output' => "alpha = 9\ngamma = 2\n",
      'edit_count' => 2,
      'source_projection' => 'explicit_byte_ranges'
    )
  end

  it 'reports overlapping explicit edits without mutating source' do
    report = provider.apply_source_edits(
      source: 'abcdef',
      edits: [
        { start_byte: 1, end_byte: 4, replacement: 'x' },
        { start_byte: 3, end_byte: 5, replacement: 'y' }
      ]
    )

    expect(report).to include('ok' => false, 'source_projection' => 'explicit_byte_ranges')
    expect(report.fetch('diagnostics').first.fetch('category')).to eq('source_edit_rejected')
  end
end
