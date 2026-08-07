# frozen_string_literal: true

# Shared examples for validating comment/layout ownership and merge-option
# behavior through a standardized analysis/merger contract.
#
# Required let blocks:
# - comment_matrix_analysis_class: analysis class under test
# - comment_matrix_merger_class: merger class under test
# - comment_matrix_line_builder: lambda building one structural line
# - comment_matrix_comment_line_builder: lambda building one comment line
# - comment_matrix_source_builder: lambda rendering a full source string
# Optional let blocks:
# - comment_matrix_default_indent: indentation to use for promoted standalone
#   comment expectations in removal-mode scenarios (defaults to "")
# - comment_matrix_owner_value_reader: lambda extracting the owner value used by
#   the quoted-literal scenario (defaults to `owner.value`)
# - comment_matrix_expected_literal_hash_value: expected value representation for
#   a quoted literal containing `#` (defaults to the harness-preserved quoted form)
# - comment_matrix_capabilities: optional hash of capability flags / skip reasons.
#   Use `true` for supported, `false` for unsupported, or a string/symbol reason.
# - comment_matrix_line_equivalents: lambda returning equivalent output lines
#   that should count as the same logical line for exact-occurrence assertions.
# - comment_matrix_structural_owners_reader: lambda returning the structural
#   owners under test from an analysis (defaults to `analysis.statements`)
#
# The line builder receives:
# - name [String]
# - value [String]
# - inline: [String, nil]
#
# It must return one complete structural line for the target format.
#
# The comment line builder receives:
# - text [String]
# - indent [String] textual indentation prefix (defaults to "")
RSpec.shared_examples('Ast::Merge::CommentBehaviorMatrix') do
  let(:comment_matrix_default_indent) { '' }
  let(:comment_matrix_owner_value_reader) { lambda(&:value) }
  let(:comment_matrix_expected_literal_hash_value) { '"literal # hash"' }
  let(:comment_matrix_capabilities) { {} }
  let(:comment_matrix_line_equivalents) { ->(line) { [line] } }
  let(:comment_matrix_structural_owners_reader) { lambda(&:statements) }

  def comment_matrix_source(*lines)
    comment_matrix_source_builder.call(*lines)
  end

  def comment_matrix_comment(text, indent: '')
    comment_matrix_comment_line_builder.call(text, indent: indent)
  end

  def comment_matrix_skip_unless!(capability, message)
    support = comment_matrix_capabilities.fetch(capability, true)
    return if support == true

    reason = support.is_a?(String) || support.is_a?(Symbol) ? support.to_s : 'unsupported by adapter'
    skip("#{message} (#{reason})")
  end

  def comment_matrix_structural_owners(analysis)
    comment_matrix_structural_owners_reader.call(analysis)
  end

  def comment_matrix_line_occurrences(content, line)
    expected_lines = Array(comment_matrix_line_equivalents.call(line)).uniq
    content.lines.count { |candidate| expected_lines.include?(candidate.chomp) }
  end

  describe 'analysis matrix' do
    let(:matrix_analysis) { comment_matrix_analysis_class.new(source) }

    context 'with preamble, floating docs, and inline docs' do
      let(:source) do
        comment_matrix_source(
          comment_matrix_comment('Document header'),
          '',
          comment_matrix_comment('Alpha docs'),
          '',
          comment_matrix_line_builder.call('alpha', '1'),
          comment_matrix_line_builder.call('beta', '2', inline: 'beta docs')
        )
      end

      it 'distinguishes file preamble from floating leading and inline ownership' do
        comment_matrix_skip_unless!(
          :preamble_floating_split,
          'line-1 preamble vs floating-owner split scenario is not supported'
        )
        comment_matrix_skip_unless!(
          :floating_leading_regions,
          'gap-separated leading docs are not exposed as floating layout-owned regions'
        )

        first_owner, second_owner = comment_matrix_structural_owners(matrix_analysis)
        augmenter = matrix_analysis.comment_augmenter
        first_attachment = matrix_analysis.comment_attachment_for(first_owner)
        second_attachment = matrix_analysis.comment_attachment_for(second_owner)

        expect(augmenter.preamble_region&.normalized_content).to(eq('Document header'))
        expect(first_attachment.leading_region).to(be_floating)
        expect(first_attachment.leading_region&.normalized_content).to(eq('Alpha docs'))
        expect(first_attachment.leading_region_layout_owned?).to(be(true))
        expect(first_attachment.leading_gap).not_to(be_nil)
        if comment_matrix_capabilities.fetch(:inline_comments, true) == true
          expect(second_attachment.inline_region&.normalized_content).to(eq('beta docs'))
        else
          expect(second_attachment.inline_region).to(be_nil)
        end
      end
    end

    context 'with attached leading docs and a shared interstitial gap' do
      let(:source) do
        comment_matrix_source(
          comment_matrix_comment('Alpha docs'),
          comment_matrix_line_builder.call('alpha', '1'),
          '',
          comment_matrix_line_builder.call('beta', '2')
        )
      end

      it 'keeps adjacent leading docs attached while exposing the shared gap between neighbors' do
        first_owner, second_owner = comment_matrix_structural_owners(matrix_analysis)
        first_attachment = matrix_analysis.comment_attachment_for(first_owner)
        second_attachment = matrix_analysis.comment_attachment_for(second_owner)

        expect(first_attachment.leading_region).not_to(be_floating)
        expect(first_attachment.leading_region&.normalized_content).to(eq('Alpha docs'))
        expect(first_attachment.trailing_gap).not_to(be_nil)
        expect(second_attachment.leading_gap).not_to(be_nil)
        expect(second_attachment.leading_gap.kind).to(eq(first_attachment.trailing_gap.kind))
        expect(second_attachment.leading_gap.start_line).to(eq(first_attachment.trailing_gap.start_line))
        expect(second_attachment.leading_gap.end_line).to(eq(first_attachment.trailing_gap.end_line))
        expect(first_attachment.trailing_gap.trailing_for?(first_owner)).to(be(true))
        expect(second_attachment.leading_gap.leading_for?(second_owner)).to(be(true))
        expect(first_attachment.trailing_gap.controller_side).to(eq(:after))
        expect(second_attachment.leading_gap.controller_side).to(eq(:after))
      end
    end

    context 'with quoted hashes and mixed inline/leading docs on one owner' do
      let(:source) do
        comment_matrix_source(
          comment_matrix_comment('Beta docs'),
          comment_matrix_line_builder.call('beta', '"literal # hash"', inline: 'real inline docs')
        )
      end

      it 'keeps literal hashes in content while separately tracking leading and inline docs' do
        comment_matrix_skip_unless!(
          :quoted_hash_inline_literals,
          'quoted hash literal scenario is not supported'
        )

        owner = comment_matrix_structural_owners(matrix_analysis).first
        attachment = matrix_analysis.comment_attachment_for(owner)

        expect(comment_matrix_owner_value_reader.call(owner)).to(eq(comment_matrix_expected_literal_hash_value))
        expect(attachment.leading_region&.normalized_content).to(eq('Beta docs'))
        expect(attachment.inline_region&.normalized_content).to(eq('real inline docs'))
      end
    end
  end

  describe 'merge option matrix' do
    it 'uses destination content for matched nodes by default' do
      result = comment_matrix_merger_class.new(
        comment_matrix_source(comment_matrix_line_builder.call('alpha', '1')),
        comment_matrix_source(comment_matrix_line_builder.call('alpha', '9'))
      ).merge

      expect(result).to(eq(comment_matrix_source(comment_matrix_line_builder.call('alpha', '9'))))
    end

    it 'uses template content for matched nodes when template preference is selected' do
      result = comment_matrix_merger_class.new(
        comment_matrix_source(comment_matrix_line_builder.call('alpha', '1')),
        comment_matrix_source(comment_matrix_line_builder.call('alpha', '9')),
        preference: :template
      ).merge

      expect(result).to(eq(comment_matrix_source(comment_matrix_line_builder.call('alpha', '1'))))
    end

    it 'skips template-only nodes unless add_template_only_nodes is enabled' do
      template = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '1'),
        comment_matrix_line_builder.call('beta', '2')
      )
      destination = comment_matrix_source(comment_matrix_line_builder.call('alpha', '9'))

      without_add = comment_matrix_merger_class.new(template, destination).merge
      with_add = comment_matrix_merger_class.new(template, destination, add_template_only_nodes: true).merge

      expect(without_add).to(eq(comment_matrix_source(comment_matrix_line_builder.call('alpha', '9'))))
      expect(with_add).to(eq(
                            comment_matrix_source(
                              comment_matrix_line_builder.call('alpha', '9'),
                              comment_matrix_line_builder.call('beta', '2')
                            )
                          ))
    end

    it 'adds attached leading docs with a template-only node when enabled' do
      comment_matrix_skip_unless!(
        :template_only_attached_comment_additions,
        'template-only attached comment additions are not supported'
      )

      template = comment_matrix_source(
        comment_matrix_comment('Alpha docs'),
        comment_matrix_line_builder.call('alpha', '1')
      )

      result = comment_matrix_merger_class.new(template, '', add_template_only_nodes: true).merge

      expect(result).to(eq(template))
    end

    it 'adds floating leading docs with their separating gap for a template-only node' do
      comment_matrix_skip_unless!(
        :template_only_floating_comment_additions,
        'template-only floating comment additions are not supported'
      )

      template = comment_matrix_source(
        comment_matrix_comment('Alpha docs'),
        '',
        comment_matrix_line_builder.call('alpha', '1')
      )

      result = comment_matrix_merger_class.new(template, '', add_template_only_nodes: true).merge

      expect(result).to(eq(template))
    end

    it 'adds first-owner preamble comments with a template-only node when enabled' do
      comment_matrix_skip_unless!(
        :template_only_preamble_additions,
        'template-only preamble additions are not supported'
      )

      template = comment_matrix_source(
        comment_matrix_comment('Document header'),
        '',
        comment_matrix_line_builder.call('alpha', '1')
      )

      result = comment_matrix_merger_class.new(template, '', add_template_only_nodes: true).merge

      expect(result).to(eq(template))
    end

    it 'adds trailing docs with a template-only node when enabled' do
      comment_matrix_skip_unless!(
        :template_only_trailing_comment_additions,
        'template-only trailing comment additions are not supported'
      )

      template = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '1'),
        comment_matrix_comment('Alpha trailing docs', indent: comment_matrix_default_indent)
      )

      result = comment_matrix_merger_class.new(template, '', add_template_only_nodes: true).merge

      expect(result).to(eq(template))
    end

    it 'adds template-only prefix nodes ahead of the first matched anchor when enabled' do
      comment_matrix_skip_unless!(
        :prefix_anchor_additions,
        'template-only prefix insertion before the first matched anchor is not supported'
      )

      template = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '1'),
        comment_matrix_line_builder.call('beta', '2')
      )
      destination = comment_matrix_source(comment_matrix_line_builder.call('beta', '9'))

      result = comment_matrix_merger_class.new(template, destination, add_template_only_nodes: true).merge

      expect(result).to(eq(
                          comment_matrix_source(
                            comment_matrix_line_builder.call('alpha', '1'),
                            comment_matrix_line_builder.call('beta', '9')
                          )
                        ))
    end

    it 'does not duplicate a shared interstitial comment block between adjacent matched nodes' do
      comment_matrix_skip_unless!(
        :adjacent_shared_comment_dedup,
        'shared interstitial comment ownership between adjacent matched nodes is not deduplicated'
      )

      shared_comment = comment_matrix_comment('Shared docs')
      template = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '1'),
        shared_comment,
        comment_matrix_line_builder.call('beta', '2')
      )
      destination = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '9'),
        shared_comment,
        comment_matrix_line_builder.call('beta', '8')
      )

      kept_destination = comment_matrix_merger_class.new(template, destination).merge
      kept_template = comment_matrix_merger_class.new(template, destination, preference: :template).merge

      expect(comment_matrix_line_occurrences(kept_destination, shared_comment)).to(eq(1), kept_destination)
      expect(comment_matrix_line_occurrences(kept_destination, comment_matrix_line_builder.call('alpha', '9'))).to(
        eq(1), kept_destination
      )
      expect(comment_matrix_line_occurrences(kept_destination, comment_matrix_line_builder.call('beta', '8'))).to(
        eq(1), kept_destination
      )

      expect(comment_matrix_line_occurrences(kept_template, shared_comment)).to(eq(1), kept_template)
      expect(comment_matrix_line_occurrences(kept_template, comment_matrix_line_builder.call('alpha', '1'))).to(eq(1),
                                                                                                                kept_template)
      expect(comment_matrix_line_occurrences(kept_template, comment_matrix_line_builder.call('beta', '2'))).to(eq(1),
                                                                                                               kept_template)
    end

    it 'keeps a destination-owned first-owner doc block singular when the template models the same position as a preamble' do
      comment_matrix_skip_unless!(
        :cross_source_preamble_ownership_dedup,
        'cross-source preamble vs first-owner ownership is not deduplicated'
      )

      template_header = comment_matrix_comment('Template header')
      destination_header = comment_matrix_comment('Destination header')
      template = comment_matrix_source(
        template_header,
        '',
        comment_matrix_line_builder.call('alpha', '1')
      )
      destination = comment_matrix_source(
        destination_header,
        comment_matrix_line_builder.call('alpha', '9')
      )

      merged = comment_matrix_merger_class.new(template, destination, add_template_only_nodes: true).merge

      expect(comment_matrix_line_occurrences(merged, template_header)).to(eq(0), merged)
      expect(comment_matrix_line_occurrences(merged, destination_header)).to(eq(1), merged)
      expect(comment_matrix_line_occurrences(merged, comment_matrix_line_builder.call('alpha', '9'))).to(eq(1), merged)
    end

    it 'does not duplicate a first-owner doc block when only blank-line ownership differs across sources' do
      comment_matrix_skip_unless!(
        :cross_source_preamble_spacing_dedup,
        'equivalent preamble blocks with different blank-line ownership are not deduplicated'
      )

      shared_header = comment_matrix_comment('Shared header')
      template = comment_matrix_source(
        shared_header,
        '',
        comment_matrix_line_builder.call('alpha', '1')
      )
      destination = comment_matrix_source(
        shared_header,
        comment_matrix_line_builder.call('alpha', '9')
      )

      merged = comment_matrix_merger_class.new(
        template,
        destination,
        preference: :template,
        add_template_only_nodes: true
      ).merge

      expect(comment_matrix_line_occurrences(merged, shared_header)).to(eq(1), merged)
      expect(comment_matrix_line_occurrences(merged, comment_matrix_line_builder.call('alpha', '1'))).to(eq(1), merged)
      expect(comment_matrix_line_occurrences(merged, comment_matrix_line_builder.call('alpha', '9'))).to(eq(0), merged)
    end

    it 'collapses duplicated template-owned preamble prefixes back to the destination-specific first-owner docs' do
      comment_matrix_skip_unless!(
        :duplicate_template_preamble_prefix_collapse,
        'duplicated template preamble prefixes are not collapsed back to the destination-specific docs'
      )

      template_header = comment_matrix_comment('Shared header')
      destination_header = comment_matrix_comment('Destination header')
      template = comment_matrix_source(
        template_header,
        '',
        comment_matrix_line_builder.call('alpha', '1')
      )
      destination = comment_matrix_source(
        template_header,
        template_header,
        destination_header,
        comment_matrix_line_builder.call('alpha', '9')
      )

      merged = comment_matrix_merger_class.new(
        template,
        destination,
        add_template_only_nodes: true
      ).merge

      expect(comment_matrix_line_occurrences(merged, template_header)).to(eq(0), merged)
      expect(comment_matrix_line_occurrences(merged, destination_header)).to(eq(1), merged)
      expect(comment_matrix_line_occurrences(merged, comment_matrix_line_builder.call('alpha', '9'))).to(eq(1), merged)
    end

    it 'preserves destination-only nodes unless remove_template_missing_nodes is enabled' do
      comment_matrix_skip_unless!(
        :remove_template_missing_nodes,
        'destination-only structural nodes are not removed by this adapter'
      )

      template = comment_matrix_source(comment_matrix_line_builder.call('alpha', '1'))
      destination = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '9'),
        comment_matrix_line_builder.call('beta', '2')
      )

      without_remove = comment_matrix_merger_class.new(template, destination).merge
      with_remove = comment_matrix_merger_class.new(template, destination, remove_template_missing_nodes: true).merge

      expect(without_remove).to(eq(
                                  comment_matrix_source(
                                    comment_matrix_line_builder.call('alpha', '9'),
                                    comment_matrix_line_builder.call('beta', '2')
                                  )
                                ))
      expect(with_remove).to(eq(comment_matrix_source(comment_matrix_line_builder.call('alpha', '9'))))
    end

    it 'removes destination-only prefix nodes when removal mode is enabled' do
      comment_matrix_skip_unless!(
        :remove_template_missing_nodes,
        'destination-only structural nodes are not removed by this adapter'
      )

      template = comment_matrix_source(comment_matrix_line_builder.call('beta', '1'))
      destination = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '9'),
        comment_matrix_line_builder.call('beta', '2')
      )

      result = comment_matrix_merger_class.new(template, destination, remove_template_missing_nodes: true).merge

      expect(result).to(eq(comment_matrix_source(comment_matrix_line_builder.call('beta', '2'))))
    end

    it 'applies preference to matched inline comments as part of the chosen node payload' do
      comment_matrix_skip_unless!(
        :inline_comments,
        'inline comment preference scenarios are not supported'
      )
      comment_matrix_skip_unless!(
        :matched_inline_comment_preference,
        'matched-node inline comments do not follow chosen-side payload preference'
      )

      template = comment_matrix_source(comment_matrix_line_builder.call('alpha', '1', inline: 'template docs'))
      destination = comment_matrix_source(comment_matrix_line_builder.call('alpha', '9', inline: 'dest docs'))

      kept_destination = comment_matrix_merger_class.new(template, destination).merge
      kept_template = comment_matrix_merger_class.new(template, destination, preference: :template).merge

      expect(kept_destination).to(eq(comment_matrix_source(comment_matrix_line_builder.call('alpha', '9',
                                                                                            inline: 'dest docs'))))
      expect(kept_template).to(eq(comment_matrix_source(comment_matrix_line_builder.call('alpha', '1',
                                                                                         inline: 'template docs'))))
    end

    it 'can add template-only nodes while removing destination-only nodes under template preference' do
      comment_matrix_skip_unless!(
        :prefix_anchor_additions,
        'template-only prefix insertion before the first matched anchor is not supported'
      )
      comment_matrix_skip_unless!(
        :inline_comments,
        'combined inline comment option scenarios are not supported'
      )
      comment_matrix_skip_unless!(
        :matched_inline_comment_preference,
        'matched-node inline comments do not follow chosen-side payload preference'
      )

      template = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '1'),
        comment_matrix_line_builder.call('beta', '2', inline: 'template docs'),
        comment_matrix_line_builder.call('gamma', '3')
      )
      destination = comment_matrix_source(
        comment_matrix_line_builder.call('beta', '9', inline: 'dest docs'),
        comment_matrix_line_builder.call('delta', '4')
      )

      result = comment_matrix_merger_class.new(
        template,
        destination,
        preference: :template,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true
      ).merge

      expect(result).to(eq(
                          comment_matrix_source(
                            comment_matrix_line_builder.call('alpha', '1'),
                            comment_matrix_line_builder.call('beta', '2', inline: 'template docs'),
                            comment_matrix_line_builder.call('gamma', '3')
                          )
                        ))
    end

    it 'promotes floating leading docs when removing a destination-only node' do
      comment_matrix_skip_unless!(
        :remove_template_missing_nodes,
        'destination-only structural nodes are not removed by this adapter'
      )
      comment_matrix_skip_unless!(
        :removed_node_floating_gap_preservation,
        'removed-node floating leading docs are not preserved with their separating gap'
      )

      template = comment_matrix_source(comment_matrix_line_builder.call('alpha', '1'))
      destination = comment_matrix_source(
        comment_matrix_comment('Beta docs'),
        '',
        comment_matrix_line_builder.call('beta', '2'),
        comment_matrix_line_builder.call('alpha', '9')
      )

      result = comment_matrix_merger_class.new(template, destination, remove_template_missing_nodes: true).merge

      expect(result).to(eq(
                          comment_matrix_source(
                            comment_matrix_comment('Beta docs'),
                            '',
                            comment_matrix_line_builder.call('alpha', '9')
                          )
                        ))
    end

    it 'promotes attached leading docs when removing a destination-only node' do
      comment_matrix_skip_unless!(
        :remove_template_missing_nodes,
        'destination-only structural nodes are not removed by this adapter'
      )

      template = comment_matrix_source(comment_matrix_line_builder.call('alpha', '1'))
      destination = comment_matrix_source(
        comment_matrix_comment('Beta docs'),
        comment_matrix_line_builder.call('beta', '2'),
        comment_matrix_line_builder.call('alpha', '9')
      )

      result = comment_matrix_merger_class.new(template, destination, remove_template_missing_nodes: true).merge

      expect(result).to(eq(
                          comment_matrix_source(
                            comment_matrix_comment('Beta docs'),
                            comment_matrix_line_builder.call('alpha', '9')
                          )
                        ))
    end

    it 'promotes inline docs from removed destination-only nodes into standalone comments' do
      comment_matrix_skip_unless!(
        :remove_template_missing_nodes,
        'destination-only structural nodes are not removed by this adapter'
      )
      comment_matrix_skip_unless!(
        :inline_comments,
        'removed-node inline comment promotion is not supported'
      )

      template = comment_matrix_source(comment_matrix_line_builder.call('alpha', '1'))
      destination = comment_matrix_source(
        comment_matrix_line_builder.call('beta', '2', inline: 'beta docs'),
        comment_matrix_line_builder.call('alpha', '9')
      )

      result = comment_matrix_merger_class.new(template, destination, remove_template_missing_nodes: true).merge

      expect(result).to(eq(
                          comment_matrix_source(
                            comment_matrix_comment('beta docs', indent: comment_matrix_default_indent),
                            comment_matrix_line_builder.call('alpha', '9')
                          )
                        ))
    end

    it 'preserves first-owner preamble comments when removing the first destination-only node' do
      comment_matrix_skip_unless!(
        :remove_template_missing_nodes,
        'destination-only structural nodes are not removed by this adapter'
      )
      comment_matrix_skip_unless!(
        :removed_node_preamble_gap_preservation,
        'removed-node preamble comments are not preserved with their separating gap'
      )

      template = comment_matrix_source(comment_matrix_line_builder.call('alpha', '1'))
      destination = comment_matrix_source(
        comment_matrix_comment('Document header'),
        '',
        comment_matrix_line_builder.call('beta', '2'),
        comment_matrix_line_builder.call('alpha', '9')
      )

      result = comment_matrix_merger_class.new(template, destination, remove_template_missing_nodes: true).merge

      expect(result).to(eq(
                          comment_matrix_source(
                            comment_matrix_comment('Document header'),
                            '',
                            comment_matrix_line_builder.call('alpha', '9')
                          )
                        ))
    end

    it 'preserves trailing docs when removing a destination-only node' do
      comment_matrix_skip_unless!(
        :remove_template_missing_nodes,
        'destination-only structural nodes are not removed by this adapter'
      )
      comment_matrix_skip_unless!(
        :removed_node_trailing_comment_preservation,
        'removed-node trailing comment preservation is not supported'
      )

      template = comment_matrix_source(comment_matrix_line_builder.call('alpha', '1'))
      destination = comment_matrix_source(
        comment_matrix_line_builder.call('beta', '2'),
        comment_matrix_comment('Beta trailing docs', indent: comment_matrix_default_indent),
        comment_matrix_line_builder.call('alpha', '9')
      )

      result = comment_matrix_merger_class.new(template, destination, remove_template_missing_nodes: true).merge

      expect(result).to(eq(
                          comment_matrix_source(
                            comment_matrix_comment('Beta trailing docs', indent: comment_matrix_default_indent),
                            comment_matrix_line_builder.call('alpha', '9')
                          )
                        ))
    end

    it 'does not duplicate a terminal trailing comment block when last-owner and document-postlude ownership overlap' do
      comment_matrix_skip_unless!(
        :terminal_comment_postlude_dedup,
        'terminal trailing vs document-postlude ownership is not deduplicated'
      )

      trailing_comment = comment_matrix_comment('Terminal docs', indent: comment_matrix_default_indent)
      template = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '1'),
        trailing_comment
      )
      destination = comment_matrix_source(
        comment_matrix_line_builder.call('alpha', '9'),
        trailing_comment
      )

      kept_destination = comment_matrix_merger_class.new(template, destination).merge
      kept_template = comment_matrix_merger_class.new(template, destination, preference: :template).merge

      expect(comment_matrix_line_occurrences(kept_destination, trailing_comment)).to(eq(1), kept_destination)
      expect(comment_matrix_line_occurrences(kept_destination, comment_matrix_line_builder.call('alpha', '9'))).to(
        eq(1), kept_destination
      )

      expect(comment_matrix_line_occurrences(kept_template, trailing_comment)).to(eq(1), kept_template)
      expect(comment_matrix_line_occurrences(kept_template, comment_matrix_line_builder.call('alpha', '1'))).to(eq(1),
                                                                                                                kept_template)
    end
  end
end
