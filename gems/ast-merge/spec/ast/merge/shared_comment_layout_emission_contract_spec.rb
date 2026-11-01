# frozen_string_literal: true

RSpec.describe Ast::Merge::CommentLayoutEmissionSupport do
  class SharedEmissionHarness
    include Ast::Merge::CommentLayoutEmissionSupport

    public :leading_segment_start_for_output
  end

  it 'matches the shared retained-owner leading segment contract' do
    fixture_path = File.expand_path('../../../../../../fixtures/polyglot/ast-merge/comment_layout_emission.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    owner_class = Struct.new(:start_line, :end_line)
    region_class = Struct.new(:start_line, :end_line, :normalized_content) do
      def empty? = false
    end
    attachment_class = Struct.new(:leading_region, :trailing_region)

    fixture.fetch('cases').each do |contract|
      owner = owner_class.new(contract.fetch('output_owner_start_line'), contract.fetch('output_owner_start_line'))
      previous = owner_class.new(1, 1)
      source_region = region_class.new(contract.fetch('source_region_start_line'),
                                       contract.fetch('source_region_start_line'), 'shared')
      attachments = {
        owner => attachment_class.new(nil, nil),
        previous => attachment_class.new(nil, nil)
      }
      if contract['target_leading_region_start_line']
        start_line = contract.fetch('target_leading_region_start_line')
        attachments[owner] = attachment_class.new(region_class.new(start_line, start_line, 'target'), nil)
      end
      if contract.fetch('previous_owner_trailing_region_matches')
        attachments[previous] =
          attachment_class.new(nil,
                               region_class.new(source_region.start_line, source_region.end_line,
                                                source_region.normalized_content))
      end
      analysis_class = Struct.new(:lines, :statements) do
        def line_at(line_number)
          lines[line_number - 1]
        end

        define_method(:comment_attachment_for) { |entry, **_kwargs| attachments.fetch(entry) }
      end
      output_analysis = analysis_class.new(contract.fetch('output_lines'), [previous, owner])
      source_analysis_class = Struct.new(:lines) do
        def line_at(line_number)
          lines[line_number - 1]
        end
      end
      source_analysis = source_analysis_class.new(contract.fetch('source_lines'))

      expect(
        SharedEmissionHarness.new.leading_segment_start_for_output(
          output_owner: owner,
          output_analysis: output_analysis,
          source_region_start: contract.fetch('source_region_start_line'),
          source_region: source_region,
          source_analysis: source_analysis
        )
      ).to eq(contract.fetch('expected_line_numbers').first), contract.fetch('name')
    end
  end
end

RSpec.describe Ast::Merge::CommentLayoutEmissionSupport do
  class SharedRootBoundaryHarness
    include Ast::Merge::CommentLayoutEmissionSupport

    public :root_boundary_lines_for
  end

  it 'matches shared preamble and postlude line selection contracts' do
    fixture_path = File.expand_path('../../../../../../fixtures/polyglot/ast-merge/comment_layout_emission.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    owner_class = Struct.new(:start_line, :end_line)
    region_class = Struct.new(:start_line, :end_line) do
      def empty? = false
    end
    augmenter_class = Struct.new(:preamble_region, :postlude_region)
    analysis_class = Struct.new(:lines, :statements, :augmenter) do
      def line_at(line_number)
        lines[line_number - 1]
      end

      def comment_augmenter(owners:)
        augmenter
      end
    end

    fixture.fetch('root_boundary_cases').each do |contract|
      owners = contract.fetch('owners').map do |owner|
        owner_class.new(owner.fetch('start_line'), owner.fetch('end_line'))
      end
      build_region = lambda do |entry|
        entry && region_class.new(entry.fetch('start_line'), entry.fetch('end_line'))
      end
      analysis = analysis_class.new(
        contract.fetch('lines'),
        owners,
        augmenter_class.new(build_region.call(contract['preamble_region']),
                            build_region.call(contract['postlude_region']))
      )
      actual = SharedRootBoundaryHarness.new.root_boundary_lines_for(
        contract.fetch('kind').to_sym,
        analysis,
        fallback_to_owner_bounds: contract.fetch('fallback_to_owner_bounds')
      )
      actual_numbers = actual.map { |line| contract.fetch('lines').index(line) + 1 }

      expect(actual_numbers).to eq(contract.fetch('expected_line_numbers')), contract.fetch('name')
    end
  end
end
