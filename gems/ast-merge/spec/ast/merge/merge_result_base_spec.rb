# frozen_string_literal: true

RSpec.describe Ast::Merge::MergeResultBase do
  describe 'decision constants' do
    it 'defines DECISION_KEPT_TEMPLATE' do
      expect(described_class::DECISION_KEPT_TEMPLATE).to eq(:kept_template)
    end

    it 'defines DECISION_KEPT_DEST' do
      expect(described_class::DECISION_KEPT_DEST).to eq(:kept_destination)
    end

    it 'defines DECISION_MERGED' do
      expect(described_class::DECISION_MERGED).to eq(:merged)
    end

    it 'defines DECISION_ADDED' do
      expect(described_class::DECISION_ADDED).to eq(:added)
    end

    it 'defines DECISION_FREEZE_BLOCK' do
      expect(described_class::DECISION_FREEZE_BLOCK).to eq(:freeze_block)
    end

    it 'defines DECISION_REPLACED' do
      expect(described_class::DECISION_REPLACED).to eq(:replaced)
    end

    it 'defines DECISION_APPENDED' do
      expect(described_class::DECISION_APPENDED).to eq(:appended)
    end

    it 'defines DECISION_UNRESOLVED' do
      expect(described_class::DECISION_UNRESOLVED).to eq(:unresolved)
    end
  end

  describe '#initialize' do
    context 'with no arguments' do
      subject(:result) { described_class.new }

      it 'starts with empty lines' do
        expect(result.lines).to eq([])
      end

      it 'starts with empty decisions' do
        expect(result.decisions).to eq([])
      end

      it 'has nil template_analysis' do
        expect(result.template_analysis).to be_nil
      end

      it 'has nil dest_analysis' do
        expect(result.dest_analysis).to be_nil
      end

      it 'has empty conflicts' do
        expect(result.conflicts).to eq([])
      end

      it 'has empty frozen_blocks' do
        expect(result.frozen_blocks).to eq([])
      end

      it 'has empty stats' do
        expect(result.stats).to eq({})
      end

      it 'has empty unresolved_cases' do
        expect(result.unresolved_cases).to eq([])
      end
    end

    context 'with template_analysis and dest_analysis' do
      subject(:result) do
        described_class.new(
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
      end

      let(:template_analysis) { double('template') }
      let(:dest_analysis) { double('dest') }

      it 'stores template_analysis' do
        expect(result.template_analysis).to eq(template_analysis)
      end

      it 'stores dest_analysis' do
        expect(result.dest_analysis).to eq(dest_analysis)
      end
    end

    context 'with conflicts' do
      subject(:result) { described_class.new(conflicts: conflicts) }

      let(:conflicts) { [{ location: 1, message: 'test' }] }

      it 'stores conflicts' do
        expect(result.conflicts).to eq(conflicts)
      end
    end

    context 'with frozen_blocks' do
      subject(:result) { described_class.new(frozen_blocks: frozen_blocks) }

      let(:frozen_blocks) { [{ start: 1, end: 5 }] }

      it 'stores frozen_blocks' do
        expect(result.frozen_blocks).to eq(frozen_blocks)
      end
    end

    context 'with stats' do
      subject(:result) { described_class.new(stats: stats) }

      let(:stats) { { nodes_added: 5, nodes_removed: 2 } }

      it 'stores stats' do
        expect(result.stats).to eq(stats)
      end
    end

    context 'with unresolved_cases' do
      subject(:result) { described_class.new(unresolved_cases: unresolved_cases) }

      let(:unresolved_cases) do
        [
          Ast::Merge::Runtime::ResolutionCase.new(
            case_id: 'case-1',
            reason: :conflict,
            candidates: { template: 'a', destination: 'b' },
            provisional_winner: :destination
          )
        ]
      end

      it 'stores unresolved_cases' do
        expect(result.unresolved_cases).to eq(unresolved_cases)
      end
    end
  end

  describe '#content' do
    subject(:result) { described_class.new }

    it 'returns @lines array' do
      expect(result.content).to eq([])
      expect(result.content).to be(result.lines)
    end

    it 'reflects changes to @lines' do
      result.lines << 'line1'
      result.lines << 'line2'
      expect(result.content).to eq(%w[line1 line2])
    end
  end

  describe '#content=' do
    subject(:result) { described_class.new }

    it 'sets content from a string' do
      result.content = "line1\nline2\nline3"
      expect(result.lines).to eq(%w[line1 line2 line3])
    end

    it 'handles empty string' do
      result.content = ''
      expect(result.lines).to eq([])
    end

    it 'handles nil by converting to empty string' do
      result.content = nil
      expect(result.lines).to eq([])
    end

    it 'preserves trailing empty lines' do
      result.content = "line1\nline2\n"
      expect(result.lines).to eq(['line1', 'line2', ''])
    end

    it 'preserves multiple trailing newlines' do
      result.content = "line1\n\n\n"
      expect(result.lines).to eq(['line1', '', '', ''])
    end
  end

  describe '#to_s' do
    subject(:result) { described_class.new }

    context 'when lines is empty' do
      it 'returns empty string' do
        expect(result.to_s).to eq('')
      end
    end

    context 'when lines has content' do
      before do
        result.lines << 'line1'
        result.lines << 'line2'
      end

      it 'joins lines with newlines and ensures trailing newline' do
        expect(result.to_s).to eq("line1\nline2\n")
      end
    end
  end

  describe '#content?' do
    subject(:result) { described_class.new }

    context 'when lines is empty' do
      it 'returns false' do
        expect(result.content?).to be(false)
      end
    end

    context 'when lines has content' do
      before { result.lines << 'line1' }

      it 'returns true' do
        expect(result.content?).to be(true)
      end
    end
  end

  describe '#empty?' do
    it 'returns true when no lines' do
      result = described_class.new
      expect(result.empty?).to be(true)
    end

    it 'returns false when lines exist' do
      result = described_class.new
      result.instance_variable_get(:@lines) << 'content'
      expect(result.empty?).to be(false)
    end
  end

  describe '#blank_lines?' do
    it 'returns true when every provided line is blank' do
      result = described_class.new

      expect(result.blank_lines?(['', " \t"])).to be(true)
    end

    it 'returns false when any provided line has content' do
      result = described_class.new

      expect(result.blank_lines?(['', 'content'])).to be(false)
    end
  end

  describe '#ends_with_blank_line?' do
    it 'returns true when the current result ends with a blank line' do
      result = described_class.new
      result.lines.concat(['content', ''])

      expect(result.ends_with_blank_line?).to be(true)
    end

    it 'returns false when the current result is empty or ends with content' do
      result = described_class.new

      expect(result.ends_with_blank_line?).to be(false)

      result.lines << 'content'

      expect(result.ends_with_blank_line?).to be(false)
    end
  end

  describe '#line_count' do
    it 'returns 0 for empty result' do
      result = described_class.new
      expect(result.line_count).to eq(0)
    end

    it 'returns correct count' do
      result = described_class.new
      lines = result.instance_variable_get(:@lines)
      lines << 'line1'
      lines << 'line2'
      expect(result.line_count).to eq(2)
    end
  end

  describe '#unresolved?' do
    it 'returns false when unresolved_cases is empty' do
      result = described_class.new
      expect(result.unresolved?).to be(false)
      expect(result.review_required?).to be(false)
    end

    it 'returns true when unresolved_cases exist' do
      result = described_class.new
      result.add_unresolved_case(
        Ast::Merge::Runtime::ResolutionCase.new(
          case_id: 'case-1',
          reason: :conflict,
          candidates: { template: 'a', destination: 'b' },
          provisional_winner: :destination
        )
      )

      expect(result.unresolved?).to be(true)
      expect(result.review_required?).to be(true)
    end
  end

  describe '#record_unresolved_choice' do
    it 'adds both conflict and resolution case entries' do
      result = described_class.new

      resolution_case = result.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        surface_path: 'document[0]',
        metadata: { node_type: :pair },
        conflict_fields: { identifier: 'name' }
      )

      expect(result.conflicts).to eq([
                                       {
                                         case_id: 'case-1',
                                         reason: :conflict,
                                         template: 'template',
                                         destination: 'destination',
                                         provisional_winner: :destination,
                                         identifier: 'name'
                                       }
                                     ])
      expect(result.unresolved_cases).to eq([resolution_case])
      expect(resolution_case.to_h).to include(
        case_id: 'case-1',
        surface_path: 'document[0]',
        metadata: { node_type: :pair }
      )
    end

    it 'skips identical candidate text' do
      result = described_class.new

      result.record_unresolved_choice(
        template_text: 'same',
        destination_text: 'same',
        provisional_winner: :destination,
        case_id: 'case-1'
      )

      expect(result.conflicts).to eq([])
      expect(result.unresolved_cases).to eq([])
    end
  end

  describe '#apply_unresolved_resolutions!' do
    it 'accepts provisional winners and clears unresolved review state' do
      result = described_class.new
      result.content = 'destination'
      result.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        metadata: { line: 1 }
      )

      returned = result.apply_unresolved_resolutions!('case-1' => :destination)

      expect(returned).to be(result)
      expect(result.review_required?).to be(false)
      expect(result.unresolved_cases).to eq([])
      expect(result.conflicts).to eq([])
      expect(result.to_s).to eq("destination\n")
    end

    it 'replaces line-backed provisional content when caller chooses a different candidate' do
      result = described_class.new
      result.content = 'destination'
      result.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        metadata: { line: 1 }
      )
      result.instance_variable_get(:@decisions) << { decision: :unresolved, line: 1 }

      result.apply_unresolved_resolutions!('case-1' => :template)

      expect(result.review_required?).to be(false)
      expect(result.to_s).to eq("template\n")
      expect(result.decision_summary[:kept_template]).to eq(1)
    end

    it 'raises when caller chooses a non-provisional candidate without line metadata' do
      result = described_class.new
      result.content = 'destination'
      result.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1'
      )

      expect do
        result.apply_unresolved_resolutions!('case-1' => :template)
      end.to raise_error(ArgumentError, /without line metadata/)

      expect(result.review_required?).to be(true)
      expect(result.unresolved_case('case-1')).not_to be_nil
    end
  end

  describe 'unresolved review state persistence' do
    it 'exports unresolved review state' do
      result = described_class.new
      result.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        metadata: { line: 1 }
      )

      state = result.to_unresolved_review_state(
        selections: { 'case-1' => :template },
        metadata: { document: 'example' }
      )

      expect(state.to_h).to include(
        schema_version: 1,
        cases: [result.unresolved_cases.first.to_h],
        selections: { 'case-1' => :template }
      )
      expect(state.to_h[:metadata]).to include(document: 'example')
      expect(state.to_h.dig(:metadata, :review_state, :replay_context)).to include(
        merge_result_class: described_class.name
      )
    end

    it 'applies a persisted unresolved review state' do
      result = described_class.new
      result.content = 'destination'
      result.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        metadata: { line: 1 }
      )

      state = Ast::Merge::UnresolvedReviewState.new(
        cases: result.unresolved_cases,
        selections: { 'case-1' => :template }
      )
      result.instance_variable_get(:@decisions) << { decision: :unresolved, line: 1 }

      result.apply_unresolved_review_state!(state)

      expect(result.review_required?).to be(false)
      expect(result.to_s).to eq("template\n")
    end

    it 'rejects persisted review state when the selected case is no longer present' do
      result = described_class.new
      result.content = 'destination'
      result.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        metadata: { line: 1 }
      )

      state = Ast::Merge::UnresolvedReviewState.new(
        cases: result.unresolved_cases,
        selections: { 'case-2' => :template }
      )

      expect do
        result.apply_unresolved_review_state!(state)
      end.to raise_error(ArgumentError, /case case-2 is not present/)
    end

    it 'rejects persisted review state when review identity no longer matches' do
      result = described_class.new
      result.content = 'destination'
      result.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        metadata: { line: 1, review_identity: 'current-identity' }
      )

      state = Ast::Merge::UnresolvedReviewState.new(
        cases: [
          Ast::Merge::Runtime::ResolutionCase.new(
            case_id: 'case-1',
            reason: :conflict,
            candidates: { template: 'template', destination: 'destination' },
            provisional_winner: :destination,
            metadata: { line: 1, review_identity: 'stale-identity' }
          )
        ],
        selections: { 'case-1' => :template },
        metadata: { review_state: { selection_identities: { 'case-1' => 'stale-identity' } } }
      )

      expect do
        result.apply_unresolved_review_state!(state)
      end.to raise_error(ArgumentError, /case case-1 no longer matches the current unresolved surface/)
    end

    it 'exports replay context for detached review-state replay' do
      analysis_class = Struct.new(:source)
      result = described_class.new(
        template_analysis: analysis_class.new('template'),
        dest_analysis: analysis_class.new('destination')
      )
      result.content = 'destination'
      result.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        metadata: { line: 1, review_identity: 'current-identity' }
      )

      state = result.to_unresolved_review_state(selections: { 'case-1' => :template }).to_h
      replay_context = state.dig(:metadata, :review_state, :replay_context)

      expect(replay_context).to include(
        merge_result_class: described_class.name,
        template_input_fingerprint: Digest::SHA256.hexdigest('template'),
        destination_input_fingerprint: Digest::SHA256.hexdigest('destination')
      )
    end

    it 'rejects persisted review state when template input fingerprint drifts' do
      analysis_class = Struct.new(:source)
      original = described_class.new(
        template_analysis: analysis_class.new('template'),
        dest_analysis: analysis_class.new('destination')
      )
      original.content = 'destination'
      original.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        metadata: { line: 1, review_identity: 'current-identity' }
      )
      state = original.to_unresolved_review_state(selections: { 'case-1' => :template })

      current = described_class.new(
        template_analysis: analysis_class.new('template changed'),
        dest_analysis: analysis_class.new('destination')
      )
      current.content = 'destination'
      current.record_unresolved_choice(
        template_text: 'template',
        destination_text: 'destination',
        provisional_winner: :destination,
        case_id: 'case-1',
        metadata: { line: 1, review_identity: 'current-identity' }
      )

      expect do
        current.apply_unresolved_review_state!(state)
      end.to raise_error(ArgumentError, /template input fingerprint no longer matches/)
    end
  end

  describe '#decision_summary' do
    it 'returns empty hash for no decisions' do
      result = described_class.new
      expect(result.decision_summary).to eq({})
    end

    it 'summarizes decisions by type' do
      result = described_class.new
      decisions = result.instance_variable_get(:@decisions)
      decisions << { decision: :kept_template }
      decisions << { decision: :kept_template }
      decisions << { decision: :kept_destination }

      summary = result.decision_summary
      expect(summary[:kept_template]).to eq(2)
      expect(summary[:kept_destination]).to eq(1)
    end
  end

  describe '#inspect' do
    it 'returns a readable string' do
      result = described_class.new
      expect(result.inspect).to include('MergeResult')
      expect(result.inspect).to include('lines=0')
      expect(result.inspect).to include('decisions=0')
    end
  end

  describe '#track_decision (protected)' do
    # We test via a subclass that exposes the method
    let(:test_class) do
      Class.new(described_class) do
        def add_tracked_decision(decision, source, line: nil)
          track_decision(decision, source, line: line)
        end
      end
    end

    it 'records decision type' do
      result = test_class.new
      result.add_tracked_decision(:kept_template, :template)

      expect(result.decisions.first[:decision]).to eq(:kept_template)
    end

    it 'records source' do
      result = test_class.new
      result.add_tracked_decision(:kept_template, :template)

      expect(result.decisions.first[:source]).to eq(:template)
    end

    it 'records line number when provided' do
      result = test_class.new
      result.add_tracked_decision(:kept_template, :template, line: 5)

      expect(result.decisions.first[:line]).to eq(5)
    end

    it 'records timestamp' do
      result = test_class.new
      result.add_tracked_decision(:kept_template, :template)

      expect(result.decisions.first[:timestamp]).to be_a(Time)
    end

    it 'records nil line when not provided' do
      result = test_class.new
      result.add_tracked_decision(:kept_template, :template)

      expect(result.decisions.first[:line]).to be_nil
    end
  end

  describe 'subclass inheritance' do
    let(:subclass) do
      Class.new(described_class) do
        def add_line(content, decision:, source:)
          @lines << content
          track_decision(decision, source)
        end
      end
    end

    it 'inherits decision constants' do
      expect(subclass::DECISION_KEPT_TEMPLATE).to eq(:kept_template)
      expect(subclass::DECISION_FREEZE_BLOCK).to eq(:freeze_block)
    end

    it 'can use track_decision' do
      result = subclass.new
      result.add_line('test', decision: :kept_template, source: :template)

      expect(result.line_count).to eq(1)
      expect(result.decisions.length).to eq(1)
    end
  end
end
