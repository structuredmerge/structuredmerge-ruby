# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ast::Crispr::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled Rust host is unavailable' unless described_class.available? }

  it 'uses the typed core without activating the prototype package' do
    expect(defined?(StructuredmergeCore)).to eq('constant')
    expect(Gem.loaded_specs.keys).not_to include('structuredmerge_host_prototype')
  end

  it 'preserves historical boundary keys and all profile report shapes' do
    boundary = provider.report(kind: 'boundary')
    expect(boundary.fetch('metadata').fetch('source')).to eq('legacy_crispr_reference')
    ruby = boundary.fetch('implementations').find { |item| item.fetch('language') == 'ruby' }
    expect(ruby).to eq('language' => 'ruby', 'package_name' => 'ast-crispr', 'require' => 'ast/crispr')
    expect(provider.report(kind: 'match', start_boundary: 'future', end_boundary: 'owner_end_plus_trailing_gap', payload_kind: 'comment_owned_body')).to include(
      'known_start_boundary' => false, 'trailing_gap_extended' => true, 'comment_anchored' => true)
    expect(provider.report(kind: 'selection', owner_scope: '', owner_selector: '', selector_kind: '', selection_intent: '')).to include(
      'owner_scope' => 'shared_default', 'comment_region' => nil)
    expect(provider.report(kind: 'destination', resolution_kind: '', resolution_source: '', anchor_boundary: '')).to include(
      'append_fallback' => true, 'used_if_missing' => false)
  end

  it 'normalizes supported limit inputs without changing default or empty conjunctions' do
    expect(provider.report(kind: 'limit')).to eq('description' => '== 1')
    expect(provider.report(kind: 'limit', spec: [])).to eq('description' => '')
    expect(provider.report(kind: 'limit', spec: [{ at_least: 1, at_most: 3 }, '!= 2'])).to eq('description' => '<= 3 and >= 1 and != 2')
    expect(provider.report(kind: 'limit', spec: { none_or_one: true })).to eq('description' => '<= 1')
    expect { provider.report(kind: 'limit', spec: 'nonsense') }.to raise_error(RuntimeError)
  end

  it 'preserves BOM, Unicode, CRLF and missing final newline through explicit edits' do
    source = "\uFEFFé: one\r\nlast"
    report = provider.apply_source_edits(source: source, edits: [{ start_byte: 7, end_byte: 10, replacement: 'two' }])
    expect(report.fetch('output')).to eq("\uFEFFé: two\r\nlast")
    expect(source).to eq("\uFEFFé: one\r\nlast")
  end

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
