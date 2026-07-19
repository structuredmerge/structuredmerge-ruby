# frozen_string_literal: true

RSpec.describe Ast::Merge::CommentLayoutEmissionSupport do
  Statement = Struct.new(:name, :start_line, :end_line, keyword_init: true)

  Region = Struct.new(:start_line, :end_line, :normalized_content, keyword_init: true) do
    def empty?
      false
    end

    def text
      normalized_content
    end
  end

  Attachment = Struct.new(:leading_region, :trailing_region, :trailing_gap, keyword_init: true)

  class Analysis
    attr_reader :lines, :statements, :comment_nodes

    def initialize(lines:, statements:, attachments: {}, preamble_region: nil, postlude_region: nil,
                   comment_nodes: [])
      @lines = lines
      @statements = statements
      @attachments = attachments
      @preamble_region = preamble_region
      @postlude_region = postlude_region
      @comment_nodes = comment_nodes
    end

    def line_at(line_number)
      lines[line_number - 1]
    end

    def comment_attachment_for(owner, **)
      @attachments.fetch(owner) { Attachment.new }
    end

    def comment_augmenter(owners: nil)
      Struct.new(:preamble_region, :postlude_region).new(@preamble_region, @postlude_region)
    end
  end

  class Harness
    include Ast::Merge::CommentLayoutEmissionSupport

    public :blank_line_count_before,
           :leading_region_for,
           :leading_segment_line_numbers_for,
           :leading_segment_lines_for,
           :leading_segment_start_for_output,
           :previous_owner_for,
           :previous_owner_trailing_region_matches?,
           :removed_owner_preserved_line_numbers_for,
           :removed_owner_preserved_lines_for,
           :region_present?,
           :root_boundary_lines_for
  end

  class EmittedSegmentHarness < Harness
    private

    def root_boundary_owner_start_line_for(owner, _analysis)
      owner.start_line - 1
    end
  end

  subject(:harness) { Harness.new }

  it 'counts blank lines immediately before an attached region' do
    analysis = Analysis.new(lines: ['alpha', '', '', '# comment', 'beta'], statements: [])

    expect(harness.blank_line_count_before(4, analysis)).to eq(2)
  end

  it 'keeps a source leading segment from duplicating the previous owner trailing region' do
    first = Statement.new(name: 'first', start_line: 1, end_line: 1)
    second = Statement.new(name: 'second', start_line: 4, end_line: 4)
    shared_region = Region.new(start_line: 3, end_line: 3, normalized_content: 'shared')
    analysis = Analysis.new(
      lines: ['first', '', '# shared', 'second'],
      statements: [first, second],
      attachments: {
        first => Attachment.new(trailing_region: shared_region),
        second => Attachment.new
      }
    )

    expect(
      harness.leading_segment_start_for_output(
        output_owner: second,
        output_analysis: analysis,
        source_region_start: 3,
        source_region: shared_region,
        source_analysis: analysis
      )
    ).to eq(3)
  end

  it 'collects preserved removed-owner leading, inline, trailing, and fallback gap lines' do
    owner = Statement.new(name: 'removed', start_line: 3, end_line: 3)
    later_owner = Statement.new(name: 'later', start_line: 6, end_line: 6)
    gap = Ast::Merge::Layout::Gap.new(
      kind: :interstitial,
      start_line: 5,
      end_line: 5,
      lines: [''],
      before_owner: owner,
      after_owner: later_owner
    )
    analysis = Analysis.new(
      lines: ['# docs', '', 'removed', '# trailing', '', 'later'],
      statements: [owner, later_owner],
      attachments: {
        owner => Attachment.new(
          leading_region: Region.new(start_line: 1, end_line: 1, normalized_content: '# docs'),
          trailing_region: Region.new(start_line: 4, end_line: 4, normalized_content: '# trailing'),
          trailing_gap: gap
        )
      }
    )

    expect(
      harness.removed_owner_preserved_lines_for(owner, analysis, inline_lines: ['# inline'])
    ).to eq(['# docs', '', '# inline', '# trailing', ''])
    expect(
      harness.removed_owner_preserved_line_numbers_for(owner, analysis, inline_line_numbers: [3])
    ).to eq([1, 2, 3, 4, 5])
  end

  it 'returns root preamble lines using root comment attachment regions' do
    statement = Statement.new(name: 'body', start_line: 4, end_line: 4)
    analysis = Analysis.new(
      lines: ['# header', '', '# docs', 'body'],
      statements: [statement],
      preamble_region: Region.new(start_line: 1, end_line: 3, normalized_content: 'header docs')
    )

    expect(harness.root_boundary_lines_for(:preamble, analysis)).to eq(['# header', '', '# docs'])
  end

  it 'treats comment-only files as root preamble lines' do
    analysis = Analysis.new(
      lines: ['# only', '', '# comments'],
      statements: [],
      comment_nodes: []
    )

    expect(harness.root_boundary_lines_for(:preamble, analysis)).to eq(['# only', '', '# comments'])
  end

  it 'can fall back to owner bounds for non-comment root boundary text' do
    statement = Statement.new(name: 'body', start_line: 3, end_line: 3)
    analysis = Analysis.new(
      lines: ['#!/usr/bin/env bash', '# header', 'body', '# footer'],
      statements: [statement]
    )

    expect(
      harness.root_boundary_lines_for(:preamble, analysis, fallback_to_owner_bounds: true)
    ).to eq(['#!/usr/bin/env bash', '# header'])
    expect(
      harness.root_boundary_lines_for(:postlude, analysis, fallback_to_owner_bounds: true)
    ).to eq(['# footer'])
  end

  it 'lets substrates bound root preamble by the emitted owner segment' do
    statement = Statement.new(name: 'body', start_line: 3, end_line: 3)
    analysis = Analysis.new(
      lines: ['#!/usr/bin/env bash', '# header', 'body'],
      statements: [statement]
    )

    expect(
      EmittedSegmentHarness.new.root_boundary_lines_for(:preamble, analysis, fallback_to_owner_bounds: true)
    ).to eq(['#!/usr/bin/env bash'])
  end
end
