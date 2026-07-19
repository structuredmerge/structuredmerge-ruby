# frozen_string_literal: true

RSpec.describe Ast::Crispr::Ruby::Prism do
  it 'has a version number' do
    expect(Ast::Crispr::Ruby::Prism::VERSION).not_to be_nil
  end

  describe '.document_context' do
    it 'builds a context with the Prism adapter' do
      context = described_class.document_context(content: "puts :ok\n", source_label: 'example.rb')

      expect(context.adapter).to be_a(Ast::Crispr::Ruby::Prism::Adapter)
    end

    it 'uses prism-merge analysis for Ruby structure' do
      analysis = described_class::Utils.parse_analysis("puts :ok\n", source_label: 'example.rb')
      result = described_class::Utils.parse_with_comments("puts :ok\n")

      expect(analysis).to be_a(::Prism::Merge::FileAnalysis)
      expect(analysis).to be_valid
      expect(result).to be_success
    end

    context 'with a structure profile' do
      let(:context) { described_class.document_context(content: "puts :ok\n", source_label: 'example.rb') }
      let(:profile) { context.structure_profile(owner_scope: :top_level_statements) }
      let(:expected_owner_scope) { :top_level_statements }
      let(:expected_owner_selector) { :line_bound_statements }
      let(:expected_owner_selector_family) { :line_oriented }
      let(:expected_known_owner_selector) { true }
      let(:expected_supported_comment_regions) { [:leading] }

      it_behaves_like 'Ast::Crispr::StructureProfile contract'

      it 'supports leading comment regions' do
        expect(profile.supports_comment_region?(:leading)).to be(true)
      end
    end
  end

  describe described_class::Selectors do
    let(:target) do
      described_class.comment_region_owned_owner(
        marker: '### MANAGED SNIPPET',
        limit: { exactly: 1 }
      )
    end

    it 'finds the comment-region-owned structural owner span' do
      content = <<~RUBY
        ### MANAGED SNIPPET
        begin
          puts "managed"
        rescue LoadError
          nil
        end

        task :default do
          puts "ok"
        end
      RUBY

      context = Ast::Crispr::Ruby::Prism.document_context(content: content, source_label: 'Rakefile')
      matches = target.locate_matches(context)

      expect(matches.size).to eq(1)
      expect(matches.first.start_line).to eq(1)
      expect(matches.first.end_line).to eq(7)
      expect(matches.first.slice_from(content)).to include('puts "managed"')
    end

    it 'surfaces the selector structure profile through the document context' do
      content = <<~RUBY
        ### MANAGED SNIPPET
        puts "managed"
      RUBY

      context = Ast::Crispr::Ruby::Prism.document_context(content: content, source_label: 'Rakefile')
      profile = target.structure_profile(context)

      expect(target.owner_scope).to eq(:shared_default)
      expect(profile.owner_selector).to eq(:line_bound_statements)
    end

    it 'finds a marker-bounded Ruby comment line block through Prism comments' do
      content = <<~RUBY
        # frozen_string_literal: true

        source "https://rubygems.org"

        # <<kettle-jem:generated>> do not edit below this line
        gem "debug", "~> 1.9"
        # <</kettle-jem:generated>>

        group :test do
          gem "rspec"
        end
      RUBY

      target = described_class.comment_line_block(
        start_text: '# <<kettle-jem:generated>> do not edit below this line',
        end_text: '# <</kettle-jem:generated>>',
        span: :outermost,
        include_trailing_gap: true,
        limit: { exactly: 1 }
      )
      context = Ast::Crispr::Ruby::Prism.document_context(content: content, source_label: 'shunted.gemfile')
      match = target.locate_matches(context).first

      expect(match.start_line).to eq(5)
      expect(match.end_line).to eq(8)
      expect(match.slice_from(content)).to include('gem "debug"')
      expect(match.slice_from(content)).not_to include('group :test')
    end

    context 'with a selector selection profile' do
      let(:context) { Ast::Crispr::Ruby::Prism.document_context(content: "### MANAGED SNIPPET\nputs \"managed\"\n", source_label: 'Rakefile') }
      let(:selection_profile) { target.selection_profile(context) }
      let(:expected_selection_owner_scope) { :shared_default }
      let(:expected_selection_owner_selector) { :line_bound_statements }
      let(:expected_selection_owner_selector_family) { :line_oriented }
      let(:expected_selector_kind) { :comment_region_owned_owner }
      let(:expected_selection_intent) { :comment_anchored_owner }
      let(:expected_selection_intent_family) { :comment_anchor }
      let(:expected_known_selection_intent) { true }
      let(:expected_comment_region) { :leading }
      let(:expected_include_trailing_gap) { true }
      let(:expected_comment_anchored) { true }

      it_behaves_like 'Ast::Crispr::SelectionProfile contract'
    end

    context 'with a comment-anchored match profile' do
      let(:content) { "### MANAGED SNIPPET\nputs \"managed\"\n\n" }
      let(:context) { Ast::Crispr::Ruby::Prism.document_context(content: content, source_label: 'Rakefile') }
      let(:match_profile) { target.locate_matches(context).first.match_profile }
      let(:expected_start_boundary) { :comment_region_start }
      let(:expected_start_boundary_family) { :comment_anchor }
      let(:expected_known_start_boundary) { true }
      let(:expected_end_boundary) { :owner_end_plus_trailing_gap }
      let(:expected_end_boundary_family) { :gap_extension }
      let(:expected_known_end_boundary) { true }
      let(:expected_payload_kind) { :comment_owned_body }
      let(:expected_payload_family) { :comment_owned }
      let(:expected_known_payload_kind) { true }
      let(:expected_match_comment_anchored) { true }
      let(:expected_trailing_gap_extended) { true }

      it_behaves_like 'Ast::Crispr::MatchProfile contract'
    end
  end

  describe Ast::Crispr::Replace do
    it 'fails closed when target cardinality is out of bounds' do
      content = <<~RUBY
        ### MANAGED SNIPPET
        puts "one"

        ### MANAGED SNIPPET
        puts "two"
      RUBY

      target = Ast::Crispr::Ruby::Prism::Selectors.comment_region_owned_owner(marker: '### MANAGED SNIPPET')
      actor = described_class.result(content: content, target: target, replacement: "puts \"fresh\"\n")

      expect(actor.failure?).to be(true)
      expect(actor.error).to include('matched 2 node(s); expected == 1')
    end
  end

  describe Ast::Crispr::Delete do
    it 'deletes the structurally owned statement span' do
      content = <<~RUBY
        ### MANAGED SNIPPET
        begin
          puts "managed"
        rescue LoadError
          nil
        end

        task :default do
          puts "ok"
        end
      RUBY

      target = Ast::Crispr::Ruby::Prism::Selectors.comment_region_owned_owner(marker: '### MANAGED SNIPPET')
      actor = described_class.call(content: content, target: target)

      expect(actor.changed).to be(true)
      expect(actor.updated_content).not_to include('### MANAGED SNIPPET')
      expect(actor.updated_content).to include('task :default')
    end
  end

  describe Ast::Crispr::Move do
    let(:operation_profile) { described_class.operation_profile }
    let(:expected_operation_kind) { :move }
    let(:expected_operation_family) { :relocation }
    let(:expected_known_operation_kind) { true }
    let(:expected_source_requirement) { :optional }
    let(:expected_destination_requirement) { :optional }
    let(:expected_replacement_source) { :captured_text_or_explicit }
    let(:expected_captures_source_text) { true }
    let(:expected_supports_if_missing) { true }
    let(:expected_selects_source) { true }
    let(:expected_requires_source) { false }
    let(:expected_supports_destination) { true }
    let(:expected_requires_destination) { false }
    let(:expected_explicit_replacement) { false }
    let(:expected_may_reuse_captured_text) { true }

    it_behaves_like 'Ast::Crispr::OperationProfile contract'

    context 'with a callable destination profile' do
      let(:content) do
        <<~RUBY
          ### MANAGED SNIPPET
          begin
            puts "old"
          rescue LoadError
            nil
          end

          # frozen_string_literal: true
          require "kettle/dev"

          ### TEMPLATING TASKS
        RUBY
      end
      let(:target) do
        Ast::Crispr::Ruby::Prism::Selectors.comment_region_owned_owner(
          marker: '### MANAGED SNIPPET',
          limit: { at_least: 0 }
        )
      end
      let(:actor) do
        described_class.call(
          content: content,
          source_target: target,
          destination: lambda do |context|
            line_number = context.content.lines.find_index { |line| line.include?('require "kettle/dev"') } + 1
            Struct.new(:anchor).new(Struct.new(:start_line, :end_line, :node).new(line_number, line_number, nil))
          end,
          replacement: "### MANAGED SNIPPET\nputs \"new\"\n",
          if_missing: :append
        )
      end
      let(:destination_profile) { actor.destination_profile }
      let(:expected_resolution_kind) { :anchor_after_statement }
      let(:expected_resolution_family) { :anchored }
      let(:expected_known_resolution_kind) { true }
      let(:expected_resolution_source) { :callable }
      let(:expected_resolution_source_family) { :callable }
      let(:expected_known_resolution_source) { true }
      let(:expected_anchor_boundary) { :statement_end_plus_following_gap }
      let(:expected_anchor_boundary_family) { :gap_preserving_statement }
      let(:expected_known_anchor_boundary) { true }
      let(:expected_used_if_missing) { false }
      let(:expected_append_fallback) { false }
      let(:expected_destination_anchored) { true }

      it_behaves_like 'Ast::Crispr::DestinationProfile contract'
    end

    it 'removes a stale managed span and reinserts the new text at the destination anchor' do
      content = <<~RUBY
        ### MANAGED SNIPPET
        begin
          puts "old"
        rescue LoadError
          nil
        end

        # frozen_string_literal: true
        require "kettle/dev"

        ### TEMPLATING TASKS
      RUBY

      target = Ast::Crispr::Ruby::Prism::Selectors.comment_region_owned_owner(
        marker: '### MANAGED SNIPPET',
        limit: { at_least: 0 }
      )

      actor = described_class.call(
        content: content,
        source_target: target,
        destination: lambda do |context|
          line_number = context.content.lines.find_index { |line| line.include?('require "kettle/dev"') } + 1
          Struct.new(:anchor).new(Struct.new(:start_line, :end_line, :node).new(line_number, line_number, nil))
        end,
        replacement: <<~RUBY,
          ### MANAGED SNIPPET
          begin
            puts "new"
          rescue LoadError
            warn("missing")
          end
        RUBY
        if_missing: :append
      )

      expect(actor.changed).to be(true)
      expect(actor.source_match_count).to eq(1)
      expect(actor.updated_content.scan('### MANAGED SNIPPET').size).to eq(1)
      expect(actor.updated_content).not_to include('puts "old"')
      expect(actor.updated_content.index('require "kettle/dev"')).to be < actor.updated_content.index('### MANAGED SNIPPET')
      expect(actor.updated_content.index('### MANAGED SNIPPET')).to be < actor.updated_content.index('### TEMPLATING TASKS')
      expect(actor.operation_profile.may_reuse_captured_text?).to be(true)
      expect(actor.destination_profile.callable_resolved?).to be(true)
    end
  end
end
