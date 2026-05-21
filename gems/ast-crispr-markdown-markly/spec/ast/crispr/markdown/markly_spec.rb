# frozen_string_literal: true

RSpec.describe Ast::Crispr::Markdown::Markly do
  it "has a version number" do
    expect(Ast::Crispr::Markdown::Markly::VERSION).not_to be_nil
  end

  describe ".document_context" do
    it "builds a context with the Markly adapter" do
      context = described_class.document_context(content: "# Title\n", source_label: "README.md")

      expect(context.adapter).to be_a(Ast::Crispr::Markdown::Markly::Adapter)
    end

    context "with a structure profile" do
      let(:context) { described_class.document_context(content: "# Title\n", source_label: "README.md") }
      let(:profile) { context.structure_profile(owner_scope: :heading_sections) }
      let(:expected_owner_scope) { :heading_sections }
      let(:expected_owner_selector) { :heading_sections }
      let(:expected_owner_selector_family) { :section_branch }
      let(:expected_known_owner_selector) { true }
      let(:expected_supported_comment_regions) { [] }

      it_behaves_like "Ast::Crispr::StructureProfile contract"
    end
  end

  describe described_class::Selectors do
    it "finds a heading-owned section span" do
      content = <<~MARKDOWN
        # Title

        ## Synopsis

        Custom synopsis.

        ### Details

        Deep detail.

        ## Install

        Install text.
      MARKDOWN

      target = described_class.heading_section(heading_text: "Synopsis", level: 2)
      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "README.md")

      matches = target.locate_matches(context)

      expect(matches.size).to eq(1)
      expect(matches.first.start_line).to eq(3)
      expect(matches.first.end_line).to eq(10)
      expect(matches.first.slice_from(content)).to include("### Details")
      expect(matches.first.slice_from(content)).not_to include("## Install")
    end

    it "surfaces the selector structure profile through the document context" do
      content = <<~MARKDOWN
        # Title

        ## Synopsis

        Custom synopsis.
      MARKDOWN

      target = described_class.heading_section(heading_text: "Synopsis", level: 2)
      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "README.md")
      profile = target.structure_profile(context)

      expect(target.owner_scope).to eq(:heading_sections)
      expect(profile.owner_selector).to eq(:heading_sections)
      expect(profile.owner_selector_family).to eq(:section_branch)
      expect(profile.metadata[:adapter]).to eq(:markly)
    end

    it "finds link reference definitions by label and URL" do
      content = <<~MARKDOWN
        # Title

        [docs]: README.md
        [policy]: SECURITY.md
      MARKDOWN

      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "README.md")
      label_target = described_class.link_definition(label: "docs")
      url_target = described_class.link_definition(url: "SECURITY.md")

      expect(label_target.locate_matches(context).first.slice_from(content)).to eq("[docs]: README.md\n")
      expect(url_target.locate_matches(context).first.node.label).to eq("policy")
    end

    it "finds inline reference links, images, and linked images" do
      content = <<~MARKDOWN
        [![Ruby][💎ruby-3.2i]][🚎ruby-3.2-wf] ![JRuby][💎jruby-9.4i] [Docs][docs]

        [💎ruby-3.2i]: https://img.shields.io/badge/Ruby-3.2-red.svg
        [🚎ruby-3.2-wf]: https://github.com/example/project/actions/workflows/current.yml
        [💎jruby-9.4i]: https://img.shields.io/badge/JRuby-9.4-red.svg
        [docs]: README.md
      MARKDOWN

      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "README.md")
      owners = context.structural_owners(owner_scope: :inline_references)
      target = described_class.inline_reference(label: "💎ruby-3.2i")
      match = target.locate_matches(context).first

      expect(owners.map(&:reference_kind)).to eq(%i[linked_image_reference image_reference link_reference])
      expect(owners.map(&:labels)).to eq([
        ["💎ruby-3.2i", "🚎ruby-3.2-wf"],
        ["💎jruby-9.4i"],
        ["docs"],
      ])
      expect(match.node.source).to eq("[![Ruby][💎ruby-3.2i]][🚎ruby-3.2-wf]")
      expect(match.metadata[:start_column]).to eq(0)
      expect(match.metadata[:end_column]).to eq(35)
    end

    it "finds exact HTML comments and marker-bounded HTML comment blocks" do
      content = <<~MARKDOWN
        # Title

        <!-- KJ:OPEN_COLLECTIVE:START -->
        Visible content.
        <!-- KJ:OPEN_COLLECTIVE:END -->

        Tail.
      MARKDOWN

      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "README.md")
      comment_target = described_class.html_comment(text: "KJ:OPEN_COLLECTIVE:START")
      block_target = described_class.html_comment_block(
        start_text: "KJ:OPEN_COLLECTIVE:START",
        end_text: "KJ:OPEN_COLLECTIVE:END",
      )

      expect(comment_target.locate_matches(context).first.start_line).to eq(3)
      expect(block_target.locate_matches(context).first.slice_from(content)).to include("Visible content.")
      expect(block_target.locate_matches(context).first.slice_from(content)).not_to include("Tail.")
    end

    it "finds the outer marker-bounded HTML comment block when duplicate blocks exist" do
      content = <<~MARKDOWN
        <!-- KJ:START -->
        One.
        <!-- KJ:END -->
        <!-- KJ:START -->
        Two.
        <!-- KJ:END -->
        Tail.
      MARKDOWN

      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "README.md")
      block_target = described_class.html_comment_block(
        start_text: "KJ:START",
        end_text: "KJ:END",
        span: :outermost,
      )
      match = block_target.locate_matches(context).first

      expect(match.start_line).to eq(1)
      expect(match.end_line).to eq(6)
      expect(match.slice_from(content)).to include("One.")
      expect(match.slice_from(content)).to include("Two.")
      expect(match.slice_from(content)).not_to include("Tail.")
    end

    it "can include the blank trailing gap after a marker-bounded HTML comment block" do
      content = <<~MARKDOWN
        <!-- KJ:START -->
        Managed.
        <!-- KJ:END -->

        Tail.
      MARKDOWN

      context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: "README.md")
      block_target = described_class.html_comment_block(
        start_text: "KJ:START",
        end_text: "KJ:END",
        include_trailing_gap: true,
      )
      match = block_target.locate_matches(context).first

      expect(match.end_line).to eq(4)
      expect(match.slice_from(content)).to end_with("\n\n")
      expect(match.slice_from(content)).not_to include("Tail.")
    end

    context "with a heading-section selection profile" do
      let(:target) { described_class.heading_section(heading_text: "Synopsis", level: 2) }
      let(:context) { Ast::Crispr::Markdown::Markly.document_context(content: "# Title\n\n## Synopsis\n\nCustom synopsis.\n", source_label: "README.md") }
      let(:selection_profile) { target.selection_profile(context) }
      let(:expected_selection_owner_scope) { :heading_sections }
      let(:expected_selection_owner_selector) { :heading_sections }
      let(:expected_selection_owner_selector_family) { :section_branch }
      let(:expected_selector_kind) { :heading_section }
      let(:expected_selection_intent) { :section_branch }
      let(:expected_selection_intent_family) { :section_branch }
      let(:expected_known_selection_intent) { true }
      let(:expected_comment_region) { nil }
      let(:expected_include_trailing_gap) { false }
      let(:expected_comment_anchored) { false }

      it_behaves_like "Ast::Crispr::SelectionProfile contract"
    end

    context "with a heading-section match profile" do
      let(:target) { described_class.heading_section(heading_text: "Synopsis", level: 2) }
      let(:context) { Ast::Crispr::Markdown::Markly.document_context(content: "# Title\n\n## Synopsis\n\nCustom synopsis.\n", source_label: "README.md") }
      let(:match_profile) { target.locate_matches(context).first.match_profile }
      let(:expected_start_boundary) { :owner_start }
      let(:expected_start_boundary_family) { :structural_owner }
      let(:expected_known_start_boundary) { true }
      let(:expected_end_boundary) { :owner_end }
      let(:expected_end_boundary_family) { :structural_owner }
      let(:expected_known_end_boundary) { true }
      let(:expected_payload_kind) { :section_branch }
      let(:expected_payload_family) { :section_branch }
      let(:expected_known_payload_kind) { true }
      let(:expected_match_comment_anchored) { false }
      let(:expected_trailing_gap_extended) { false }

      it_behaves_like "Ast::Crispr::MatchProfile contract"
    end
  end

  describe Ast::Crispr::Replace do
    let(:operation_profile) { described_class.operation_profile }
    let(:expected_operation_kind) { :replace }
    let(:expected_operation_family) { :rewrite }
    let(:expected_known_operation_kind) { true }
    let(:expected_source_requirement) { :required }
    let(:expected_destination_requirement) { :none }
    let(:expected_replacement_source) { :explicit_text }
    let(:expected_captures_source_text) { true }
    let(:expected_supports_if_missing) { false }
    let(:expected_selects_source) { true }
    let(:expected_requires_source) { true }
    let(:expected_supports_destination) { false }
    let(:expected_requires_destination) { false }
    let(:expected_explicit_replacement) { true }
    let(:expected_may_reuse_captured_text) { false }

    it_behaves_like "Ast::Crispr::OperationProfile contract"

    it "replaces a heading-owned section without touching sibling sections" do
      content = <<~MARKDOWN
        # Title

        ## Synopsis

        Old synopsis.

        ## Install

        Install text.
      MARKDOWN

      actor = described_class.call(
        content: content,
        target: Ast::Crispr::Markdown::Markly::Selectors.heading_section(heading_text: "Synopsis", level: 2),
        replacement: "## Synopsis\n\nNew synopsis.\n",
        source_label: "README.md",
      )

      expect(actor.changed).to be(true)
      expect(actor.updated_content).to include("New synopsis.")
      expect(actor.updated_content).not_to include("Old synopsis.")
      expect(actor.updated_content).to include("## Install\n\nInstall text.")
      expect(actor.operation_profile.explicit_replacement?).to be(true)
    end
  end
end
