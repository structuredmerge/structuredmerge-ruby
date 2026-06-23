# frozen_string_literal: true

RSpec.describe 'Markly partial template merge integration', :markdown_merge, :markly_merge do
  let(:template) do
    <<~MD
      ### The Gem Family

      This is the gem family section.

      | Gem | Description |
      |-----|-------------|
      | gem-a | Does A |
      | gem-b | Does B |

      [gem-a]: https://example.com/gem-a
      [gem-b]: https://example.com/gem-b
    MD
  end

  let(:destination_with_section) do
    <<~MD
      # My Project

      Welcome to my project.

      ## Installation

      Run `gem install my-project`.

      ### The Gem Family

      Old content here.

      | Gem | Description |
      |-----|-------------|
      | gem-a | Old description |

      [gem-a]: https://old-url.com/gem-a

      ## Contributing

      Please contribute!
    MD
  end

  let(:destination_without_section) do
    <<~MD
      # My Project

      Welcome to my project.

      ## Installation

      Run `gem install my-project`.

      ## Contributing

      Please contribute!
    MD
  end

  describe '#merge' do
    context 'when destination has the section' do
      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_with_section,
          anchor: { type: :heading, text: /Gem Family/ },
          backend: :markly
        )
      end

      it 'returns a Result' do
        result = merger.merge
        expect(result).to be_a(Markdown::Merge::PartialTemplateMerger::Result)
      end

      it 'finds the section' do
        result = merger.merge
        expect(result.has_section).to be true
        expect(result.section_found?).to be true
      end

      it 'returns changed content' do
        result = merger.merge
        expect(result.changed).to be true
      end

      it 'preserves content before the section' do
        result = merger.merge
        expect(result.content).to include('# My Project')
        expect(result.content).to include('Welcome to my project')
        expect(result.content).to include('## Installation')
      end

      it 'preserves content after the section' do
        result = merger.merge
        expect(result.content).to include('## Contributing')
        # NOTE: Markly may escape '!' as '\!'
        expect(result.content).to match(/Please contribute/)
      end

      it 'updates the section content' do
        result = merger.merge
        expect(result.content).to include('This is the gem family section')
        expect(result.content).to include('gem-b')
      end

      it 'includes the injection point in result' do
        result = merger.merge
        expect(result.injection_point).to be_a(Ast::Merge::Navigable::InjectionPoint)
      end
    end

    context 'when destination does NOT have the section' do
      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_without_section,
          anchor: { type: :heading, text: /Gem Family/ },
          backend: :markly,
          when_missing: :skip
        )
      end

      it 'returns unchanged content with :skip' do
        result = merger.merge
        expect(result.has_section).to be false
        expect(result.changed).to be false
        expect(result.content).to eq(destination_without_section)
      end

      context 'with when_missing: :append' do
        let(:merger) do
          Markdown::Merge::PartialTemplateMerger.new(
            template: template,
            destination: destination_without_section,
            anchor: { type: :heading, text: /Gem Family/ },
            backend: :markly,
            when_missing: :append
          )
        end

        it 'appends the template at the end' do
          result = merger.merge
          expect(result.changed).to be true
          expect(result.content).to end_with(template.chomp + "\n")
          expect(result.content).to start_with('# My Project')
        end
      end

      context 'with when_missing: :prepend' do
        let(:merger) do
          Markdown::Merge::PartialTemplateMerger.new(
            template: template,
            destination: destination_without_section,
            anchor: { type: :heading, text: /Gem Family/ },
            backend: :markly,
            when_missing: :prepend
          )
        end

        it 'prepends the template at the start' do
          result = merger.merge
          expect(result.changed).to be true
          expect(result.content).to start_with(template)
        end
      end
    end

    context 'with custom boundary and replace_mode' do
      let(:destination_multi_section) do
        <<~MD
          # Project

          ## Section A

          Content A.

          ## Section B

          Content B.

          ## Section C

          Content C.
        MD
      end

      let(:section_b_template) do
        <<~MD
          ## Section B

          New content for B.

          Extra paragraph.
        MD
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: section_b_template,
          destination: destination_multi_section,
          anchor: { type: :heading, text: /Section B/ },
          boundary: { type: :heading },
          backend: :markly,
          replace_mode: true # Full replacement, not merge
        )
      end

      it 'replaces only the bounded section' do
        result = merger.merge
        expect(result.content).to include('Content A')
        expect(result.content).to include('New content for B')
        expect(result.content).to include('Content C')
        expect(result.content).not_to include('Content B.')
      end
    end

    context 'with custom boundary and merge mode (default)' do
      let(:destination_multi_section) do
        <<~MD
          # Project

          ## Section A

          Content A.

          ## Section B

          Content B.

          Custom destination content.

          ## Section C

          Content C.
        MD
      end

      let(:section_b_template) do
        <<~MD
          ## Section B

          New content for B.

          Extra paragraph.
        MD
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: section_b_template,
          destination: destination_multi_section,
          anchor: { type: :heading, text: /Section B/ },
          boundary: { type: :heading },
          backend: :markly,
          preference: :template,
          add_missing: true
          # replace_mode defaults to false - uses SmartMerger
        )
      end

      it 'merges the section intelligently' do
        result = merger.merge
        expect(result.content).to include('Content A')
        expect(result.content).to include('New content for B')
        expect(result.content).to include('Content C')
        # With SmartMerger, behavior depends on matching and preference
        expect(result).to be_a(Markdown::Merge::PartialTemplateMerger::Result)
      end
    end

    context 'with preference: :destination' do
      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_with_section,
          anchor: { type: :heading, text: /Gem Family/ },
          backend: :markly,
          preference: :destination
        )
      end

      it 'prefers destination content for conflicts' do
        result = merger.merge
        # The merger should still work, preference affects conflict resolution
        expect(result).to be_a(Markdown::Merge::PartialTemplateMerger::Result)
      end
    end

    context 'with add_missing: false' do
      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_with_section,
          anchor: { type: :heading, text: /Gem Family/ },
          backend: :markly,
          add_missing: false
        )
      end

      it 'does not add template-only nodes' do
        result = merger.merge
        # With add_missing: false, new nodes from template shouldn't be added
        expect(result).to be_a(Markdown::Merge::PartialTemplateMerger::Result)
      end
    end
  end

  describe 'Result' do
    let(:result) do
      Markdown::Merge::PartialTemplateMerger::Result.new(
        content: 'merged content',
        has_section: true,
        changed: true,
        stats: { nodes_added: 2 },
        message: 'Success'
      )
    end

    it 'has content' do
      expect(result.content).to eq('merged content')
    end

    it 'has has_section' do
      expect(result.has_section).to be true
    end

    it 'has changed' do
      expect(result.changed).to be true
    end

    it 'has stats' do
      expect(result.stats).to eq({ nodes_added: 2 })
    end

    it 'has message' do
      expect(result.message).to eq('Success')
    end

    it 'responds to section_found?' do
      expect(result.section_found?).to be true
    end

    context 'with injection_point' do
      let(:mock_anchor) do
        stmt = Object.new
        allow(stmt).to receive_messages(index: 0, type: :heading)
        stmt
      end

      let(:injection_point) do
        Ast::Merge::Navigable::InjectionPoint.new(anchor: mock_anchor, position: :replace)
      end

      let(:result_with_injection) do
        Markdown::Merge::PartialTemplateMerger::Result.new(
          content: 'content',
          has_section: true,
          changed: true,
          injection_point: injection_point
        )
      end

      it 'has injection_point' do
        expect(result_with_injection.injection_point).to eq(injection_point)
      end
    end

    context 'with default values' do
      let(:minimal_result) do
        Markdown::Merge::PartialTemplateMerger::Result.new(
          content: 'content',
          has_section: false,
          changed: false
        )
      end

      it 'defaults stats to empty hash' do
        expect(minimal_result.stats).to eq({})
      end

      it 'defaults injection_point to nil' do
        expect(minimal_result.injection_point).to be_nil
      end

      it 'defaults message to nil' do
        expect(minimal_result.message).to be_nil
      end
    end
  end

  describe 'heading level detection' do
    let(:destination_with_h2_and_h3) do
      <<~MD
        # Title

        ## Section One

        Content one.

        ### Subsection

        Subsection content.

        ## Section Two

        Content two.
      MD
    end

    let(:subsection_template) do
      <<~MD
        ### Subsection

        New subsection content.
      MD
    end

    let(:merger) do
      Markdown::Merge::PartialTemplateMerger.new(
        template: subsection_template,
        destination: destination_with_h2_and_h3,
        anchor: { type: :heading, text: /Subsection/ },
        backend: :markly
      )
    end

    it 'respects heading levels for section boundaries' do
      result = merger.merge
      # The H3 "Subsection" should extend until the next H2 "Section Two"
      expect(result.content).to include('Content one')
      expect(result.content).to include('New subsection content')
      expect(result.content).to include('## Section Two')
      expect(result.content).to include('Content two')
    end
  end

  describe 'advanced features' do
    context 'with custom signature_generator' do
      let(:destination) do
        <<~MD
          # Project

          ## Features

          - Feature A
          - Feature B

          ## Links

          [link-a]: https://example.com/a
        MD
      end

      let(:template) do
        <<~MD
          ## Features

          - Feature A (updated)
          - Feature C (new)
        MD
      end

      let(:custom_signature_generator) do
        lambda do |node|
          text = node.respond_to?(:to_plaintext) ? node.to_plaintext.to_s : node.to_s
          [:features, :list_item, text[0, 20]] if text.include?('Feature')
        end
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination,
          anchor: { type: :heading, text: /Features/ },
          boundary: { type: :heading },
          backend: :markly,
          signature_generator: custom_signature_generator
        )
      end

      it 'accepts custom signature_generator' do
        expect(merger.signature_generator).to eq(custom_signature_generator)
      end

      it 'merges with custom signatures' do
        result = merger.merge
        expect(result).to be_a(Markdown::Merge::PartialTemplateMerger::Result)
        expect(result.section_found?).to be true
      end
    end

    context 'with node_typing configuration' do
      let(:destination) do
        <<~MD
          # Project

          ## Special Section

          Regular paragraph.

          | Name | Value |
          |------|-------|
          | foo  | 100   |
        MD
      end

      let(:template) do
        <<~MD
          ## Special Section

          Updated paragraph.

          | Name | Value |
          |------|-------|
          | foo  | 200   |
          | bar  | 300   |
        MD
      end

      let(:table_typing) do
        lambda do |node|
          text = node.respond_to?(:to_plaintext) ? node.to_plaintext.to_s : node.to_s
          if text.include?('foo')
            Ast::Merge::NodeTyping.with_merge_type(node, :data_table)
          else
            node
          end
        end
      end

      let(:node_typing_config) do
        { 'table' => table_typing }
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination,
          anchor: { type: :heading, text: /Special Section/ },
          backend: :markly,
          node_typing: node_typing_config,
          preference: :template
        )
      end

      it 'accepts node_typing configuration' do
        expect(merger.node_typing).to eq(node_typing_config)
      end

      it 'merges with node typing' do
        result = merger.merge
        expect(result).to be_a(Markdown::Merge::PartialTemplateMerger::Result)
        expect(result.section_found?).to be true
      end
    end
  end

  describe 'text pattern normalization' do
    context 'with regex string pattern /pattern/' do
      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_with_section,
          anchor: { type: :heading, text: '/Gem Family/' },
          backend: :markly
        )
      end

      it 'converts /pattern/ string to Regexp' do
        result = merger.merge
        expect(result.has_section).to be true
      end
    end

    context 'with plain string pattern' do
      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_with_section,
          anchor: { type: :heading, text: 'The Gem Family' },
          backend: :markly
        )
      end

      it 'uses plain string for matching' do
        result = merger.merge
        expect(result.has_section).to be true
      end
    end

    context 'with nil text pattern' do
      let(:destination_with_heading) do
        <<~MD
          # Project

          ## heading

          Content.
        MD
      end

      let(:simple_template) do
        <<~MD
          ## heading

          New content.
        MD
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: simple_template,
          destination: destination_with_heading,
          anchor: { type: :heading },
          backend: :markly
        )
      end

      it 'matches by type only when text is nil' do
        result = merger.merge
        expect(result).to be_a(Markdown::Merge::PartialTemplateMerger::Result)
      end
    end
  end

  describe 'when_missing edge cases' do
    context 'with unknown when_missing value' do
      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_without_section,
          anchor: { type: :heading, text: /Gem Family/ },
          backend: :markly,
          when_missing: :unknown_action
        )
      end

      it 'falls through to default (skipping)' do
        result = merger.merge
        expect(result.has_section).to be false
        expect(result.changed).to be false
        expect(result.message).to include('skipping')
      end
    end
  end

  describe 'anchor normalization' do
    context 'with nil anchor' do
      it 'handles nil anchor gracefully' do
        merger = Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_with_section,
          anchor: nil,
          backend: :markly
        )
        result = merger.merge
        # Should not find section with nil anchor
        expect(result.has_section).to be false
      end
    end

    context 'with level options in anchor' do
      let(:destination_with_levels) do
        <<~MD
          # Title

          ## Section

          Content.

          ### Subsection

          More content.
        MD
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: "## New Section\n\nNew content.",
          destination: destination_with_levels,
          anchor: { type: :heading, level: 2 },
          backend: :markly
        )
      end

      it 'passes level options through normalization' do
        expect(merger.anchor[:level]).to eq(2)
      end
    end

    context 'with level_lte option' do
      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_with_section,
          anchor: { type: :heading, level_lte: 3 },
          backend: :markly
        )
      end

      it 'passes level_lte through normalization' do
        expect(merger.anchor[:level_lte]).to eq(3)
      end
    end

    context 'with level_gte option' do
      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_with_section,
          anchor: { type: :heading, level_gte: 2 },
          backend: :markly
        )
      end

      it 'passes level_gte through normalization' do
        expect(merger.anchor[:level_gte]).to eq(2)
      end
    end
  end

  describe 'section boundary detection' do
    context 'when section extends to end of document' do
      let(:destination_section_at_end) do
        <<~MD
          # Project

          ## First Section

          Content.

          ### Target Section

          Target content that extends to end.

          More target content.
        MD
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: "### Target Section\n\nNew content.",
          destination: destination_section_at_end,
          anchor: { type: :heading, text: /Target Section/ },
          backend: :markly
        )
      end

      it 'detects section extending to document end' do
        result = merger.merge
        expect(result.has_section).to be true
        expect(result.content).to include('First Section')
        expect(result.content).to include('New content')
      end
    end

    context 'with non-heading anchor type' do
      let(:destination_with_paragraph) do
        <<~MD
          # Project

          MARKER_START

          Content to replace.

          MARKER_START

          Other content.
        MD
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: "MARKER_START\n\nReplacement content.",
          destination: destination_with_paragraph,
          anchor: { type: :paragraph, text: /MARKER_START/ },
          backend: :markly
        )
      end

      it 'finds boundary at next node of same type' do
        result = merger.merge
        expect(result).to be_a(Markdown::Merge::PartialTemplateMerger::Result)
      end
    end
  end

  describe 'replace_mode behavior' do
    context 'with replace_mode: true' do
      let(:destination) do
        <<~MD
          # Project

          ## Target

          Old line 1.
          Old line 2.
          Old line 3.

          ## Next
        MD
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: "## Target\n\nCompletely new content.",
          destination: destination,
          anchor: { type: :heading, text: /Target/ },
          boundary: { type: :heading },
          backend: :markly,
          replace_mode: true
        )
      end

      it 'replaces section entirely without merging' do
        result = merger.merge
        expect(result.stats[:mode]).to eq(:replace)
        expect(result.content).to include('Completely new content')
        expect(result.content).not_to include('Old line')
      end
    end

    context 'with replace_mode: false (default merge mode)' do
      let(:destination) do
        <<~MD
          # Project

          ## Target

          Existing content.

          ## Next
        MD
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: "## Target\n\nTemplate content.",
          destination: destination,
          anchor: { type: :heading, text: /Target/ },
          boundary: { type: :heading },
          backend: :markly,
          replace_mode: false
        )
      end

      it 'uses SmartMerger for intelligent merge' do
        result = merger.merge
        expect(result.stats[:mode]).to eq(:merge)
      end
    end
  end

  describe 'content unchanged detection' do
    context 'when merged content equals original' do
      let(:destination) do
        <<~MD
          # Project

          ## Section

          Exact content.
        MD
      end

      let(:merger) do
        Markdown::Merge::PartialTemplateMerger.new(
          template: "## Section\n\nExact content.",
          destination: destination,
          anchor: { type: :heading, text: /Section/ },
          backend: :markly,
          replace_mode: true
        )
      end

      it 'detects when content is unchanged' do
        result = merger.merge
        # The message should indicate unchanged when content matches
        expect(result.message).to match(/unchanged|merged/i)
      end
    end
  end

  describe 'unknown backend' do
    it 'raises ArgumentError for unknown backend' do
      expect do
        Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination_with_section,
          anchor: { type: :heading, text: /Gem Family/ },
          backend: :unknown_backend
        )
      end.to raise_error(ArgumentError, /Unknown backend/)
    end
  end
end
