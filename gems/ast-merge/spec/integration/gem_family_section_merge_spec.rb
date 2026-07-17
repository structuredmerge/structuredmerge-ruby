# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength -- integration specs keep related backend scenarios together.
# Integration tests for the gem_family_section merge recipe.
#
# These tests validate the actual behavior of merging a partial template (GEM_FAMILY_SECTION.md)
# into destination README files, as done by bin/update_gem_family_section.
#
# The fixtures in spec/fixtures/markdown/01_gem_family_section/ contain:
# - partial_template.md: The template content to inject
# - destination.md: A realistic destination file (commonmarker-merge README)
# - result.md: The expected result after merging
#
# Known issues being tested:
# 1. Link reference definitions may be replaced with inline links by some backends
# 2. Template content may be incorrectly spread around the result
# 3. Paragraph matching may fail causing duplicate content

RSpec.describe 'Gem Family Section Merge Integration', :aggregate_failures, :markdown_merge do
  let(:fixtures_dir) { File.expand_path('../fixtures/markdown/01_gem_family_section', __dir__) }
  let(:partial_template) { File.read(File.join(fixtures_dir, 'partial_template.md')) }
  let(:destination) { File.read(File.join(fixtures_dir, 'destination.md')) }
  let(:expected_result) { File.read(File.join(fixtures_dir, 'result.md')) }

  # Recipe configuration matching .merge-recipes/gem_family_section.yml
  let(:anchor_config) do
    {
      type: :heading,
      text: /Gem Family/
    }
  end

  let(:boundary_config) do
    {
      type: :heading,
      same_or_shallower: true
    }
  end

  merge_result_cache = {}

  shared_examples 'gem family section merge' do |backend|
    describe "with #{backend} backend" do
      let(:result) do
        merge_result_cache[backend] ||= Markdown::Merge::PartialTemplateMerger.new(
          template: partial_template,
          destination: destination,
          anchor: anchor_config,
          boundary: boundary_config,
          backend: backend,
          preference: :template,
          add_missing: true,
          replace_mode: true # Full replacement - template content replaces destination section
        ).merge
      end

      it 'finds the injection point' do
        expect(result.section_found?).to be true
      end

      it 'produces changed content' do
        expect(result.changed).to be true
      end

      describe 'merged content structure' do
        let(:merged_content) { result.content }

        it 'preserves content before the gem family section' do
          # The NOTE table at the beginning should be preserved
          expect(merged_content).to include('📍 NOTE')
          expect(merged_content).to include('RubyGems (the [GitHub org]')
        end

        it 'preserves content after the gem family section' do
          # Quickstart section should be preserved
          expect(merged_content).to include('### Quickstart')
          expect(merged_content).to include('require "commonmarker/merge"')
        end

        it 'includes the template heading' do
          expect(merged_content).to include('### The `*-merge` Gem Family')
        end

        it 'includes the template introduction paragraph' do
          # This is the paragraph that may fail to match
          expect(merged_content).to include('The `*-merge` gem family provides intelligent, AST-based merging')
          expect(merged_content).to include('At the foundation is [tree_haver]')
        end

        it 'includes the main gem table from template' do
          expect(merged_content).to include('[tree_haver][tree_haver]')
          expect(merged_content).to include('[ast-merge][ast-merge]')
          expect(merged_content).to include('[bash-merge][bash-merge]')
        end

        it 'includes the Backend Platform Compatibility section from template' do
          expect(merged_content).to include('#### Backend Platform Compatibility')
          expect(merged_content).to include('tree_haver supports multiple parsing backends')
        end

        it 'includes the platform compatibility table from template' do
          expect(merged_content).to include('**MRI** ([ruby_tree_sitter][ruby_tree_sitter])')
          expect(merged_content).to include('**Rust** ([tree_stump][tree_stump])')
          expect(merged_content).to include('**Java** ([jtreesitter][jtreesitter])')
        end

        it 'includes the legend from template' do
          expect(merged_content).to include('**Legend**: ✅ = Works, ❌ = Does not work, ❓ = Untested')
        end

        it 'includes the explanation paragraphs from template' do
          expect(merged_content).to include("**Why some backends don't work on certain platforms**")
          expect(merged_content).to include('**JRuby**: Runs on the JVM')
        end

        it 'includes the example implementations table from template' do
          expect(merged_content).to include('[kettle-dev][kettle-dev]')
          expect(merged_content).to include('[kettle-jem][kettle-jem]')
        end

        it 'includes link reference definitions from template' do
          # These may be converted to inline links - this tests the expected behavior
          expect(merged_content).to include('[tree_haver]:')
          expect(merged_content).to include('[ast-merge]:')
          expect(merged_content).to include('[prism-merge]:')
          expect(merged_content).to include('[ruby_tree_sitter]:')
          expect(merged_content).to include('[jtreesitter]:')
        end
      end

      describe 'content integrity' do
        let(:merged_content) { result.content }

        it 'does not duplicate the gem family heading' do
          # Count occurrences of the heading
          heading_count = merged_content.scan('### The `*-merge` Gem Family').count
          expect(heading_count).to eq(1), "Expected exactly 1 gem family heading, found #{heading_count}"
        end

        it 'does not duplicate the introduction paragraph' do
          # The intro paragraph should appear exactly once
          intro_count = merged_content.scan('gem family provides intelligent, AST-based merging').count
          expect(intro_count).to eq(1), "Expected exactly 1 introduction paragraph, found #{intro_count}"
        end

        it 'does not have stray template content outside the section' do
          # Find where Quickstart section begins (marks end of gem family section)
          quickstart_pos = merged_content.index('### Quickstart')
          expect(quickstart_pos).not_to be_nil

          # Content after Quickstart should not contain gem family specific content
          after_quickstart = merged_content[quickstart_pos..]
          expect(after_quickstart).not_to include('Backend Platform Compatibility')
          expect(after_quickstart).not_to include('tree_haver supports multiple parsing backends')
        end

        it 'does not have double blank lines (3+ consecutive newlines)' do
          # The original README has no double blank lines.
          # A single blank line = 2 newlines (\n\n)
          # A double blank line = 3 newlines (\n\n\n) - THIS IS A BUG
          # This is a regression test for the node_to_text double-newline bug
          double_blank_matches = merged_content.scan(/\n{3,}/)
          expect(double_blank_matches).to be_empty,
                                          "Found #{double_blank_matches.length} occurrence(s) of double+ blank lines (3+ consecutive newlines). " \
                                            'This indicates the node_to_text method is adding extra newlines.'
        end
      end

      describe 'comparison with expected result' do
        let(:merged_content) { result.content }

        # This test compares against a known-good result file
        it 'matches expected result' do
          expect(merged_content).to eq(expected_result)
        end

        it 'preserves link reference definitions' do
          # Source-based rendering preserves link reference definitions
          # Original has: [GitHub org][rubygems-org]
          expect(merged_content).to include('[rubygems-org]'),
                                    'Link reference definitions should be preserved'
        end

        it 'preserves table cell padding' do
          # Source-based rendering preserves original table formatting
          # Original has: | 📍 NOTE                                                   |
          expect(merged_content).to include('| 📍 NOTE '),
                                    'Table cell padding should be preserved'
        end
      end
    end
  end

  context 'with markly backend', :markly_merge do
    it_behaves_like 'gem family section merge', :markly
  end

  context 'with commonmarker backend', :commonmarker_merge do
    it_behaves_like 'gem family section merge', :commonmarker
  end

  describe 'link reference definition handling' do
    # Link reference definitions are a known issue - some backends convert them to inline links

    shared_examples 'link reference preservation' do |backend|
      let(:result) do
        merge_result_cache[backend] ||= Markdown::Merge::PartialTemplateMerger.new(
          template: partial_template,
          destination: destination,
          anchor: anchor_config,
          boundary: boundary_config,
          backend: backend,
          preference: :template,
          add_missing: true,
          replace_mode: true # Full replacement - template content replaces destination section
        ).merge
      end

      it "preserves link reference definition format for #{backend}" do
        merged_content = result.content

        # Check that link references are preserved as references, not converted to inline
        # For example: [tree_haver]: https://... should stay as reference, not become [tree_haver](https://...)

        # Count link reference definitions (lines starting with [identifier]:)
        link_ref_pattern = /^\[[\w-]+\]:\s+https?:/m
        link_ref_count = merged_content.scan(link_ref_pattern).count

        # The template has many link reference definitions that should be preserved
        expect(link_ref_count).to be >= 20,
                                  "Expected at least 20 link reference definitions, found #{link_ref_count}. " \
                                    'Link references may have been converted to inline links.'
      end
    end

    context 'with markly backend', :markly_merge do
      it_behaves_like 'link reference preservation', :markly
    end

    context 'with commonmarker backend', :commonmarker_merge do
      it_behaves_like 'link reference preservation', :commonmarker
    end
  end

  describe 'paragraph matching behavior' do
    # The destination has a different introduction paragraph than the template.
    # With replace_mode: true, the template section completely replaces the destination section.
    # With replace_mode: false (smart merge), a signature_generator is needed to match paragraphs.

    let(:destination_intro) do
      'This gem is part of a family of gems that provide intelligent merging for various file formats:'
    end

    let(:template_intro) do
      'The `*-merge` gem family provides intelligent, AST-based merging for various file formats.'
    end

    shared_examples 'paragraph replacement' do |backend|
      context 'with replace_mode: true (recommended)' do
        let(:result) do
          merge_result_cache[backend] ||= Markdown::Merge::PartialTemplateMerger.new(
            template: partial_template,
            destination: destination,
            anchor: anchor_config,
            boundary: boundary_config,
            backend: backend,
            preference: :template,
            add_missing: true,
            replace_mode: true # Full replacement
          ).merge
        end

        it "replaces destination intro with template intro for #{backend}" do
          merged_content = result.content

          section_start = merged_content.index('### The `*-merge` Gem Family')
          expect(section_start).not_to be_nil

          section_end = merged_content.index('### Quickstart')
          expect(section_end).not_to be_nil

          gem_family_section = merged_content[section_start...section_end]

          # With replace_mode: true, destination intro is replaced by template
          expect(gem_family_section).not_to include(destination_intro),
                                            'Destination introduction paragraph should have been replaced by template'
          expect(gem_family_section).to include(template_intro),
                                        'Template introduction paragraph should be present'
        end
      end
    end

    context 'with markly backend', :markly_merge do
      it_behaves_like 'paragraph replacement', :markly
    end

    context 'with commonmarker backend', :commonmarker_merge do
      it_behaves_like 'paragraph replacement', :commonmarker
    end
  end
end
# rubocop:enable Metrics/BlockLength
