# frozen_string_literal: true

# Shared examples for unresolved helper support mixed into base classes.
#
# Usage:
#   let(:unresolved_helper_host) { instance_under_test }
#   let(:expected_unresolved_case_id) { "json-pair_value-name-12" }
#   it_behaves_like "Ast::Merge::UnresolvedHelperContract"
RSpec.shared_examples('Ast::Merge::UnresolvedHelperContract') do
  it 'builds a root-level unresolved surface path' do
    expect(unresolved_helper_host.send(:unresolved_surface_path, 'pair["name"]')).to(eq('document[0] > pair["name"]'))
  end

  it 'scopes nested unresolved path segments to the current block' do
    nested_path = unresolved_helper_host.send(:with_unresolved_path_segment, 'pair["package"]') do
      unresolved_helper_host.send(:unresolved_surface_path, 'pair["name"]')
    end

    expect(nested_path).to(eq('document[0] > pair["package"] > pair["name"]'))
    expect(unresolved_helper_host.send(:unresolved_surface_path, 'pair["root"]')).to(eq('document[0] > pair["root"]'))
  end

  it 'builds compact unresolved case identifiers with line suffixes' do
    node = double('Node', start_line: 12)

    expect(unresolved_helper_host.send(:unresolved_case_id_for, *unresolved_case_id_parts,
                                       node: node)).to(eq(expected_unresolved_case_id))
  end

  it 'selects the first unresolved identifier from the configured node methods' do
    template_node = double('TemplateNode', key_name: nil, table_name: 'widgets')
    destination_node = double('DestinationNode', key_name: 'name', table_name: nil)

    identifier = unresolved_helper_host.send(
      :unresolved_identifier_for_nodes,
      destination_node,
      template_node,
      methods: %i[key_name table_name]
    )

    expect(identifier).to(eq('name'))
  end

  it 'builds typed unresolved path segments with identifier or line fallback' do
    node = double('Node', start_line: 8)

    expect(
      unresolved_helper_host.send(:unresolved_typed_path_segment, 'pair', identifier: 'name', node: node,
                                                                          fallback: nil)
    ).to(eq('pair["name"]'))
    expect(
      unresolved_helper_host.send(:unresolved_typed_path_segment, 'pair', identifier: nil, node: node,
                                                                          fallback: 'pair')
    ).to(eq('pair[line=8]'))
  end

  it 'builds unresolved surface paths with fallback segments' do
    expect(
      unresolved_helper_host.send(:unresolved_surface_path_for, nil, fallback_segment: 'line[12]')
    ).to(eq('document[0] > line[12]'))
    expect(
      unresolved_helper_host.send(:unresolved_surface_path_for, nil, fallback_segment: nil)
    ).to(eq('document[0]'))
  end

  it 'scopes the first available unresolved path segment from candidate nodes' do
    node_without_segment = double('NoSegmentNode')
    node_with_segment = double('SegmentNode')

    scoped_path = unresolved_helper_host.send(
      :with_first_unresolved_path_segment,
      node_without_segment,
      node_with_segment,
      segment_builder: lambda { |node|
        case node
        when node_with_segment then 'pair["name"]'
        end
      }
    ) do
      unresolved_helper_host.send(:unresolved_surface_path, 'pair["value"]')
    end

    expect(scoped_path).to(eq('document[0] > pair["name"] > pair["value"]'))
  end

  it 'extracts unresolved line spans using effective_end_line when available' do
    effective_node = double('EffectiveNode', start_line: 4, effective_end_line: 9)
    plain_node = double('PlainNode', start_line: 2, end_line: 5)

    expect(unresolved_helper_host.send(:unresolved_line_span, effective_node)).to(eq([4, 9]))
    expect(unresolved_helper_host.send(:unresolved_line_span, plain_node)).to(eq([2, 5]))
  end

  it 'records unresolved node choices with shared case and line metadata' do
    result = instance_double('MergeResult')
    template_node = double('TemplateNode', start_line: 2, end_line: 3)
    destination_node = double('DestinationNode', start_line: 4, end_line: 6)
    allow(result).to(receive(:record_unresolved_choice))

    unresolved_helper_host.send(
      :record_unresolved_node_choice,
      result: result,
      template_node: template_node,
      destination_node: destination_node,
      template_text: '"template"',
      destination_text: '"destination"',
      provisional_winner: :destination,
      case_prefix: 'json',
      case_parts: %w[pair name],
      surface_path: 'document[0] > pair["name"]',
      metadata: { key_name: 'name' },
      conflict_fields: { key_name: 'name' }
    )

    expect(result).to(have_received(:record_unresolved_choice).with(
                        template_text: '"template"',
                        destination_text: '"destination"',
                        provisional_winner: :destination,
                        case_id: 'json-pair-name-4',
                        surface_path: 'document[0] > pair["name"]',
                        reason: :conflict,
                        metadata: {
                          key_name: 'name',
                          template_lines: [2, 3],
                          destination_lines: [4, 6]
                        },
                        conflict_fields: { key_name: 'name' }
                      ))
  end

  it 'allows unresolved node choices to override the generated case identifier' do
    result = instance_double('MergeResult')
    template_node = double('TemplateNode', start_line: 2, end_line: 3)
    destination_node = double('DestinationNode', start_line: 4, end_line: 6)
    allow(result).to(receive(:record_unresolved_choice))

    unresolved_helper_host.send(
      :record_unresolved_node_choice,
      result: result,
      template_node: template_node,
      destination_node: destination_node,
      template_text: '"template"',
      destination_text: '"destination"',
      provisional_winner: :destination,
      case_prefix: 'text',
      case_parts: [],
      case_id: 'text-line-2',
      surface_path: nil,
      metadata: { line: 2 },
      conflict_fields: { line: 2 }
    )

    expect(result).to(have_received(:record_unresolved_choice).with(
                        hash_including(case_id: 'text-line-2', metadata: hash_including(line: 2))
                      ))
  end
end
