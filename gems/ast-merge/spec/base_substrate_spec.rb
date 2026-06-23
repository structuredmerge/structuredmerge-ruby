# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'Ast::Merge restored Ruby provider substrate' do
  class SubstrateMergeResult < Ast::Merge::MergeResultBase
    def add_line(line, decision:, source:)
      lines << line
      track_decision(decision, source, line: lines.length)
    end
  end

  class SubstrateEmitter < Ast::Merge::EmitterBase
    def emit_comment(text, inline: false)
      if inline && lines.any?
        lines[-1] = "#{lines[-1]} # #{text}"
      else
        lines << "# #{text}"
      end
    end

    def emit_tracked_comment(comment)
      lines << comment.fetch(:text)
    end

    def emit_payload(text)
      add_indented_line(text)
    end
  end

  class SubstrateResolver < Ast::Merge::ConflictResolverBase
    def initialize(template_analysis:, dest_analysis:, preference: :destination, **options)
      super(
        strategy: :node,
        preference: preference,
        template_analysis: template_analysis,
        dest_analysis: dest_analysis,
        **options
      )
    end

    def resolve_node_pair(template_node, dest_node, **)
      if preference_for_node(template_node) == :template
        { decision: DECISION_TEMPLATE,
          node: template_node }
      else
        { decision: DECISION_DESTINATION,
          node: dest_node }
      end
    end
  end

  class SubstrateAnalysis
    include Ast::Merge::FileAnalyzable

    def initialize(source, freeze_token: 'smorg', statements: nil)
      @source = source
      @lines = source.split("\n", -1)
      @freeze_token = freeze_token
      @signature_generator = nil
      @statements = statements || []
    end

    def compute_node_signature(node)
      node.respond_to?(:signature) ? node.signature : [:line, node.to_s]
    end
  end

  Point = Struct.new(:row)
  TestNode = Struct.new(:type, :start_point, :end_point, :start_byte, :end_byte)

  class SubstrateNodeWrapper < Ast::Merge::NodeWrapperBase
    private

    def compute_signature(node)
      [node.type.to_sym, text]
    end
  end

  it 'keeps merge results inspectable, reviewable, and replayable' do
    result = SubstrateMergeResult.new
    result.add_line('alpha', decision: Ast::Merge::MergeResultBase::DECISION_ADDED, source: :template)
    result.record_unresolved_choice(
      template_text: 'alpha = 1',
      destination_text: 'alpha = 2',
      provisional_winner: :destination,
      case_id: 'alpha-conflict',
      surface_path: ['alpha'],
      reason: :conflict
    )

    expect(result.to_s).to eq("alpha\n")
    expect(result.decision_summary).to eq(added: 1)
    expect(result.review_required?).to be(true)

    review_state = result.to_unresolved_review_state(selections: { 'alpha-conflict' => :destination })
    result.apply_unresolved_review_state!(review_state)

    expect(result.review_required?).to be(false)
    expect(result.conflicts).to be_empty
  end

  it 'detects freeze block markers and preserves freeze content identity' do
    freeze_node = Ast::Merge::FreezeNodeBase.new(
      start_line: 2,
      end_line: 4,
      content: "# smorg:freeze keep local\nlocal-only\n# smorg:unfreeze",
      start_marker: '# smorg:freeze keep local'
    )

    expect(Ast::Merge::FreezeNodeBase.freeze_start?('# smorg:freeze keep local')).to be(true)
    expect(Ast::Merge::FreezeNodeBase.freeze_end?('# smorg:unfreeze')).to be(true)
    expect(freeze_node.location.cover?(3)).to be(true)
    expect(freeze_node.reason).to eq('keep local')
    expect(freeze_node.signature.first).to eq(:FreezeNode)
    expect(freeze_node.content).to include('local-only')
  end

  it 'provides parser-neutral file analysis hooks for freeze, comments, layout, and feature profiles' do
    freeze_node = Ast::Merge::FreezeNodeBase.new(
      start_line: 2,
      end_line: 4,
      content: "# smorg:freeze\nlocal\n# smorg:unfreeze"
    )
    analysis = SubstrateAnalysis.new("alpha\n# smorg:freeze\nlocal\n# smorg:unfreeze\n", statements: [freeze_node])
    owner = Struct.new(:start_line, :end_line).new(1, 1)

    expect(analysis.freeze_blocks).to eq([freeze_node])
    expect(analysis.in_freeze_block?(3)).to be(true)
    expect(analysis.signature_at(0).first).to eq(:FreezeNode)
    expect(analysis.comment_capability.none?).to be(true)
    expect(analysis.layout_attachment_for(owner).owner).to eq(owner)
    expect(analysis.feature_profile.owner_selector).to eq(:shared_default)
  end

  it 'lets provider emitters preserve normalized comment and layout fragments' do
    emitter = SubstrateEmitter.new
    style = Ast::Merge::Comment::Style.for(:hash_comment)
    region = Ast::Merge::Comment::Region.new(
      kind: :leading,
      nodes: [
        Ast::Merge::Comment::Line.new(text: '# first', line_number: 1, style: style),
        Ast::Merge::Comment::Line.new(text: '# second', line_number: 3, style: style)
      ]
    )

    emitter.emit_comment_region(region, source_lines: ['# first', '', '# second'])
    emitter.indent
    emitter.emit_payload('value')

    expect(emitter.to_s).to eq("# first\n\n# second\n  value\n")
  end

  it 'keeps conflict resolver policy and node wrapper extension points available to providers' do
    resolver = SubstrateResolver.new(template_analysis: :template, dest_analysis: :destination, preference: :template)
    node = TestNode.new('pair', Point.new(0), Point.new(0), 0, 5)
    wrapper = SubstrateNodeWrapper.new(
      node,
      lines: ['alpha'],
      source: 'alpha',
      leading_comments: [{ text: 'docs', line: 1 }]
    )

    expect(resolver.resolve_node_pair(:template_node, :destination_node)).to eq(
      decision: :template,
      node: :template_node
    )
    expect(wrapper.start_line).to eq(1)
    expect(wrapper.text).to eq('alpha')
    expect(wrapper.signature).to eq([:pair, 'alpha'])
    expect(wrapper.comment_attachment.leading_region.nodes.first.slice).to eq('# docs')
  end
end
