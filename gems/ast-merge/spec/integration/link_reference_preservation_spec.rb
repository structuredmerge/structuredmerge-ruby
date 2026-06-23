# frozen_string_literal: true

# Tests for link reference definition preservation during markdown merges.
# The fix uses source-based rendering to preserve original formatting.

RSpec.describe 'Link Reference Preservation' do
  # Input markdown with link reference definitions
  let(:markdown_with_link_refs) do
    <<~MD
      # Test Document

      This is a [link to GitHub][gh-link] and another [link to Ruby][ruby-link].

      [gh-link]: https://github.com
      [ruby-link]: https://ruby-lang.org
    MD
  end

  shared_examples 'link reference handling' do |backend|
    let(:analysis_class) do
      case backend
      when :markly
        # Gem is loaded by spec_helper if available, test is skipped via :markly_merge tag if not
        Markly::Merge::FileAnalysis
      when :commonmarker
        # Gem is loaded by spec_helper if available, test is skipped via :commonmarker_merge tag if not
        Commonmarker::Merge::FileAnalysis
      else
        raise ArgumentError, "Unknown backend: #{backend}"
      end
    end

    describe "source-based rendering with #{backend}" do
      it 'preserves link reference syntax when using source_range' do
        analysis = analysis_class.new(markdown_with_link_refs)

        # Build Navigable::Statements
        statements = Ast::Merge::Navigable::Statement.build_list(analysis.statements)

        # Find a paragraph with link references
        para_stmt = statements.find { |s| s.type.to_s == 'paragraph' }
        expect(para_stmt).not_to be_nil

        # Extract using source_range (should preserve link refs)
        pos = para_stmt.node.source_position
        source_text = analysis.source_range(pos[:start_line], pos[:end_line])

        # The source text should contain the original link reference syntax
        expect(source_text).to include('[gh-link]')
        expect(source_text).to include('[ruby-link]')
        # Should NOT have inline URLs in the paragraph
        expect(source_text).not_to include('https://github.com')
      end

      it 'preserves link definition lines via LinkDefinitionNode' do
        analysis = analysis_class.new(markdown_with_link_refs)

        # Check that link definitions are captured
        link_defs = analysis.statements.select do |s|
          s.respond_to?(:type) && s.type.to_s == 'link_definition'
        end

        # Should have captured the link definitions
        expect(link_defs.size).to eq(2)
        labels = link_defs.map(&:label)
        expect(labels).to include('gh-link')
        expect(labels).to include('ruby-link')
      end
    end
  end

  context 'with markly backend', :markly_merge do
    it_behaves_like 'link reference handling', :markly
  end

  context 'with commonmarker backend', :commonmarker_merge do
    it_behaves_like 'link reference handling', :commonmarker
  end
end
