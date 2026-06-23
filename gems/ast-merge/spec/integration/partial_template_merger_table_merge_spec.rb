# frozen_string_literal: true

# Integration specs for PartialTemplateMerger table and paragraph merging
#
# These specs test the merge behavior for sections containing tables and paragraphs

RSpec.describe 'PartialTemplateMerger table and paragraph merge', :markdown_merge, :markly_merge do
  # Tests paragraph merging behavior when template and destination have different content
  describe 'paragraph merging with different content', :aggregate_failures do
    let(:template) do
      <<~MD
        ### Gem Family

        Template intro about gem family.

        | Gem | Description |
        |-----|-------------|
        | gem-a | Does A |
      MD
    end

    let(:destination) do
      <<~MD
        # Project

        Intro text.

        ### Gem Family

        Destination intro about gem family.

        | Gem | Description |
        |-----|-------------|
        | gem-b | Does B |

        ### Next Section
      MD
    end

    it 'keeps both paragraphs when they have different content signatures' do
      merger = Markdown::Merge::PartialTemplateMerger.new(
        template: template,
        destination: destination,
        anchor: { type: :heading, text: /Gem Family/, level: 3 },
        boundary: { type: :heading, level: 3 },
        backend: :markly,
        preference: :template,
        add_missing: true,
        replace_mode: false
      )

      result = merger.merge
      gem_family_start = result.content.index('### Gem Family')
      next_section_start = result.content.index('### Next Section')
      section = result.content[gem_family_start...next_section_start]

      # Both paragraphs are kept because they have different content
      # and thus different signatures
      expect(section).to include('Template intro'),
                         'Template paragraph should be present'
      expect(section).to include('Destination intro'),
                         'Destination paragraph is also present (different content = different signature)'
    end

    context 'with signature_generator to force paragraph matching' do
      let(:signature_generator) do
        lambda do |node|
          text = node.text.to_s.strip
          type = node.type.to_s

          %i[gem_family paragraph intro] if type == 'paragraph' && text.include?('intro about gem family')
        end
      end

      it 'replaces destination paragraph when signatures match' do
        merger = Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination,
          anchor: { type: :heading, text: /Gem Family/, level: 3 },
          boundary: { type: :heading, level: 3 },
          backend: :markly,
          preference: :template,
          add_missing: true,
          replace_mode: false,
          signature_generator: signature_generator
        )

        result = merger.merge
        gem_family_start = result.content.index('### Gem Family')
        next_section_start = result.content.index('### Next Section')
        section = result.content[gem_family_start...next_section_start]

        expect(section).to include('Template intro'),
                           'Template paragraph should be present'
        expect(section).not_to include('Destination intro'),
                               'With matching signatures, destination paragraph should be replaced'
      end
    end
  end

  # Tests blank line handling in merged output
  describe 'blank line handling in merged output', :aggregate_failures do
    let(:template) do
      <<~MD
        ### Section

        Para 1.

        Para 2.
      MD
    end

    let(:destination) do
      <<~MD
        # Doc

        ### Section

        Old para.

        ### Other
      MD
    end

    it 'avoids excessive blank lines in merged output' do
      merger = Markdown::Merge::PartialTemplateMerger.new(
        template: template,
        destination: destination,
        anchor: { type: :heading, text: /Section/, level: 3 },
        boundary: { type: :heading, level: 3 },
        backend: :markly,
        preference: :template,
        add_missing: true,
        replace_mode: false
      )

      result = merger.merge

      # Check for excessive blank lines (3+ consecutive newlines = 2+ blank lines)
      expect(result.content).not_to match(/\n{4,}/),
                                    'Should not have excessive blank lines (4+ consecutive newlines)'
    end
  end

  # Tests table replacement using position-based signature generation
  # Tables at the same relative position in their sections match regardless of structure
  describe 'table replacement with position-based signatures', :aggregate_failures do
    let(:template) do
      <<~MD
        ### Section

        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
      MD
    end

    let(:destination) do
      <<~MD
        # Doc

        ### Section

        | A | B |
        |---|---|
        | x | y |

        ### Other
      MD
    end

    it 'replaces destination table with template table' do
      merger = Markdown::Merge::PartialTemplateMerger.new(
        template: template,
        destination: destination,
        anchor: { type: :heading, text: /^Section/, level: 3 },
        boundary: { type: :heading, level: 3 },
        backend: :markly,
        preference: :template,
        add_missing: true,
        replace_mode: false
      )

      result = merger.merge
      section_start = result.content.index('### Section')
      section_end = result.content.index('### Other')
      section = result.content[section_start...section_end]

      # Count table separator lines
      table_separators = section.lines.count { |l| l.strip.match?(/^\|[-:\s|]+\|$/) }

      # Template table should replace destination table
      # With position-based signature generation, tables at the same position match
      expect(table_separators).to eq(1),
                                  "Should have exactly one table after merge, got #{table_separators}"

      # Verify it's the template table (has 3 columns with C)
      expect(section).to include('| C |'),
                         'Template table should be present (has C column)'
    end

    context 'with custom signature_generator for explicit matching' do
      let(:signature_generator) do
        lambda do |node|
          type = node.type.to_s
          %i[section table main] if type == 'table'
        end
      end

      it 'replaces destination table with explicit matching signatures' do
        merger = Markdown::Merge::PartialTemplateMerger.new(
          template: template,
          destination: destination,
          anchor: { type: :heading, text: /^Section/, level: 3 },
          boundary: { type: :heading, level: 3 },
          backend: :markly,
          preference: :template,
          add_missing: true,
          replace_mode: false,
          signature_generator: signature_generator
        )

        result = merger.merge
        section_start = result.content.index('### Section')
        section_end = result.content.index('### Other')
        section = result.content[section_start...section_end]

        # With matching signatures, only template table should remain
        expect(section).to include('| C |'),
                           'Template table (3 columns) should be present'

        table_separators = section.lines.count { |l| l.strip.match?(/^\|[-:\s|]+\|$/) }
        expect(table_separators).to eq(1),
                                    "With matching signatures, should have exactly one table, got #{table_separators}"
      end
    end
  end
end
