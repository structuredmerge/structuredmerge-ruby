# frozen_string_literal: true

RSpec.describe Ast::Merge::SourceRegionReportSupport do
  Owner = Struct.new(:region_id, :address, :start_index, :declaration_start_index, :end_index, keyword_init: true)

  class SourceRegionReportHarness
    include Ast::Merge::SourceRegionReportSupport

    public :source_blank_line_ownership_regions,
           :source_comment_block_attachment_report,
           :source_interleaved_regions_for_report,
           :source_attached_comment_regions_for_report
  end

  subject(:harness) { SourceRegionReportHarness.new }

  it 'reports comment block attachment against already-discovered owners' do
    lines = [
      '# file note',
      '',
      'def alpha',
      'end',
      '',
      '# beta docs',
      'def beta',
      'end',
      '# beta tail',
      '',
      'def gamma',
      'end'
    ]
    owners = [
      Owner.new(address: '/methods/alpha', start_index: 2, declaration_start_index: 2, end_index: 3),
      Owner.new(address: '/methods/beta', start_index: 5, declaration_start_index: 6, end_index: 7),
      Owner.new(address: '/methods/gamma', start_index: 10, declaration_start_index: 10, end_index: 11)
    ]

    expect(
      harness.source_comment_block_attachment_report(
        lines: lines,
        owners: owners,
        comment_line: ->(line) { line.start_with?('#') }
      )
    ).to eq(
      comments: [
        {
          attachment: 'standalone',
          next_owner: '/methods/alpha',
          span: { start_line: 1, end_line: 1 },
          content: "# file note\n"
        },
        {
          attachment: 'following_owner',
          previous_owner: '/methods/alpha',
          next_owner: '/methods/beta',
          span: { start_line: 6, end_line: 6 },
          content: "# beta docs\n"
        },
        {
          attachment: 'preceding_owner',
          previous_owner: '/methods/beta',
          next_owner: '/methods/gamma',
          span: { start_line: 9, end_line: 9 },
          content: "# beta tail\n"
        }
      ]
    )
  end

  it 'interleaves public owner regions with shared interstitial report regions' do
    lines = [
      '# file note',
      '',
      'def alpha',
      'end',
      '',
      'def beta',
      'end'
    ]
    owners = [
      {
        region_id: 'method:alpha',
        region_kind: 'owner',
        address: '/methods/alpha',
        start_index: 2,
        declaration_start_index: 2,
        end_index: 3,
        span: { start_line: 3, end_line: 4 },
        content: "def alpha\nend\n"
      },
      {
        region_id: 'method:beta',
        region_kind: 'owner',
        address: '/methods/beta',
        start_index: 5,
        declaration_start_index: 5,
        end_index: 6,
        span: { start_line: 6, end_line: 7 },
        content: "def beta\nend\n"
      }
    ]

    expect(harness.source_interleaved_regions_for_report(lines: lines, owners: owners)).to eq(
      [
        {
          region_id: 'file_header',
          region_kind: 'interstitial',
          position: 'file_header',
          next_owner: '/methods/alpha',
          span: { start_line: 1, end_line: 2 },
          content: "# file note\n\n"
        },
        {
          region_id: 'method:alpha',
          region_kind: 'owner',
          address: '/methods/alpha',
          span: { start_line: 3, end_line: 4 },
          content: "def alpha\nend\n"
        },
        {
          region_id: 'between:method:alpha:method:beta',
          region_kind: 'interstitial',
          position: 'between',
          previous_owner: '/methods/alpha',
          next_owner: '/methods/beta',
          span: { start_line: 5, end_line: 5 },
          content: "\n"
        },
        {
          region_id: 'method:beta',
          region_kind: 'owner',
          address: '/methods/beta',
          span: { start_line: 6, end_line: 7 },
          content: "def beta\nend\n"
        }
      ]
    )
  end

  it 'reports attached leading comment regions using the Ruby source-region contract shape' do
    expect(
      harness.source_attached_comment_regions_for_report(
        lines: ['# docs', 'def alpha'],
        start_index: 0,
        declaration_index: 1
      )
    ).to eq(
      [
        {
          attachment: 'leading',
          start_line: 1,
          end_line: 1,
          content: "# docs\n"
        }
      ]
    )
  end

  it 'extracts blank interstitial ownership recursively' do
    regions = [
      {
        region_id: 'outer',
        region_kind: 'owner',
        child_regions: [
          {
            region_id: 'between:a:b',
            region_kind: 'interstitial',
            position: 'between',
            previous_owner: '/a',
            next_owner: '/b',
            span: { start_line: 3, end_line: 4 },
            content: "\n\n"
          },
          {
            region_id: 'comment-gap',
            region_kind: 'interstitial',
            position: 'between',
            previous_owner: '/b',
            next_owner: '/c',
            span: { start_line: 8, end_line: 8 },
            content: "# comment\n"
          }
        ]
      }
    ]

    expect(harness.source_blank_line_ownership_regions(regions: regions)).to eq(
      [
        {
          region_id: 'between:a:b',
          position: 'between',
          previous_owner: '/a',
          next_owner: '/b',
          span: { start_line: 3, end_line: 4 },
          ownership: 'declared_interstitial_region'
        }
      ]
    )
  end
end
