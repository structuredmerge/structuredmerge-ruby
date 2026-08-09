# frozen_string_literal: true

require "spec_helper"
require "json"
require "ast/merge/rspec/shared_examples"

# rubocop:disable Metrics/BlockLength -- HTML ownership and adversarial boundaries form one contract
RSpec.describe Html::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) do
    <<~HTML
      <!doctype html>
      <!-- document comment -->
      <html lang=en>
        <head>
          <title>Base title</title>
          <style id=theme>body { color: black; }</style>
        </head>
        <body>
          <main id="content" class="page primary">Base</main>
          <footer id='footer'>Footer</footer>
        </body>
      </html>
    HTML
  end

  it "registers the exact HTML workflow selector" do
    expect(provider).to have_attributes(provider_id: "ruby.html", family: "html")
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[html],
      backends: [:"kreuzberg-language-pack"],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: "ruby.html",
        family: :html,
        dialect: :html,
        backend: :"kreuzberg-language-pack",
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Html::Merge.merge_provider)
  end

  it "analyzes explicit unique IDs and safe singleton semantics from AST attributes" do
    result = provider.analyze(source: base)
    signatures = result.dig(:analysis, :owners).map { |owner| owner.fetch(:signature) }

    expect(result).to include(ok: true)
    expect(signatures).to contain_exactly(
      [:singleton, "title"],
      [:id, "theme"],
      [:id, "content"],
      [:id, "footer"]
    )
  end

  it "uses an explicit ID as the sole owner when a title or base singleton is identified" do
    source = "<head><base id=origin href=/><title id=page-title>Title</title></head>"
    signatures = provider.analyze(source: source).dig(:analysis, :owners).map { |owner| owner.fetch(:signature) }

    expect(signatures).to contain_exactly([:id, "origin"], [:id, "page-title"])
  end

  it "diffs, merges two-way, and emits JSON-ready envelopes" do
    changed = base.sub("Base</main>", "Changed</main>")
    diff = provider.diff2(before_source: base, after_source: changed)
    merged = provider.merge2(current_source: base, incoming_source: changed)

    expect(diff.fetch(:changes)).to contain_exactly(hash_including(change: :edited, path: "[:id, \"content\"]"))
    expect(merged).to include(ok: true, operation: :merge2, output: changed)
    expect { JSON.generate(Ast::Merge.json_ready(merged)) }.not_to raise_error
  end

  it "base-aware merges independent unique-owner edits" do
    ours = base.sub("Base</main>", "Ours</main>")
    theirs = base.sub("Footer</footer>", "Theirs</footer>")
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include("Ours</main>", "Theirs</footer>")
    expect(result.fetch(:verification)).to include(
      output_reparsed: true,
      semantic_match: true,
      ast_attributes_verified: true,
      base_participated: true
    )
  end

  it "merges independent head and body additions at parser-proven closing boundaries" do
    ours = base.sub("  </head>", "    <meta id=ours-meta name=ours content=yes>\n  </head>")
    theirs = base.sub("  </body>", "    <aside id=theirs-aside>Theirs</aside>\n  </body>")
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include("<meta id=ours-meta", "<aside id=theirs-aside>")
  end

  it "honors deletions from base while retaining an independent edit" do
    ours = base.sub("Base</main>", "Ours</main>")
    theirs = base.sub("    <footer id='footer'>Footer</footer>\n", "")
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include("Ours</main>")
    expect(result.fetch(:output)).not_to include("<footer")
  end

  it "localizes a same-owner conflict to its proven element range" do
    ours = base.sub("Base</main>", "Ours</main>")
    theirs = base.sub("Base</main>", "Theirs</main>")
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:element_localized_conflict)
    expect(result.fetch(:conflicted_output)).to include("<!-- document comment -->",
                                                        "<footer id='footer'>Footer</footer>")
  end

  it "treats duplicate IDs as ambiguous and falls back to a full-file conflict for composites" do
    duplicate = base.sub("<footer id='footer'>", "<footer id='content'>")
    expect(provider.analyze(source: duplicate)).to include(
      ok: false,
      diagnostics: include(hash_including(category: :ambiguous_owner))
    )

    result = provider.merge3(
      base_source: duplicate,
      ours_source: duplicate.sub("Base</main>", "Ours</main>"),
      theirs_source: duplicate.sub("Footer</footer>", "Theirs</footer>")
    )
    expect(result).to include(ok: false)
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it "does not infer identity from classes, repeated tags, or source positions" do
    source = "<section class=x>A</section><section class=x>B</section>"
    expect(provider.analyze(source: source).dig(:analysis, :owners)).to be_empty

    result = provider.merge3(
      base_source: source,
      ours_source: source.sub(">A<", ">Ours<"),
      theirs_source: source.sub(">B<", ">Theirs<")
    )
    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :unmanaged_source_change))
  end

  it "fails closed for mixed text, comments, and unmanaged document structure changes" do
    mixed = "<main>Hello <em>world</em></main><!-- tail -->"
    result = provider.merge3(
      base_source: mixed,
      ours_source: mixed.sub("Hello", "Hi"),
      theirs_source: mixed.sub("tail", "changed")
    )

    expect(result).to include(ok: false)
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it "preserves script, style, template, SVG, MathML, entities, and attribute syntax in independent owners" do
    source = <<~HTML
      <script id=code>if (left < right) value = "&amp;";</script>
      <style id='css'>x > y { color:red }</style>
      <template id="card"><p disabled>Hi&nbsp;</p></template>
      <user-card id=custom><pre id=pre>  x
       y</pre><textarea id=notes>&lt;x&gt;</textarea></user-card>
      <svg id=icon viewBox="0 0 1 1"><path d="M0 0"/></svg>
      <math id='formula'><mi>x</mi></math>
    HTML
    ours = source.sub("color:red", "color:blue")
    theirs = source.sub("<mi>x</mi>", "<mi>y</mi>")
    result = provider.merge3(base_source: source, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include(
      "if (left < right)",
      "color:blue",
      "<template id=\"card\"><p disabled>Hi&nbsp;</p></template>",
      "<user-card id=custom>",
      "<textarea id=notes>&lt;x&gt;</textarea>",
      "viewBox=\"0 0 1 1\"",
      "<mi>y</mi>"
    )
  end

  it "preserves exact doctype, comments, whitespace, quotes, entities, void elements, and no final newline winner" do
    exact = "<!DOCTYPE HTML><!--x--><html><body><input disabled><p id=x title='a&amp;b'>x</p></body></html>"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.fetch(:verification)).to include(byte_exact: true, semantic_match: true, base_participated: true)
  end

  it "exact-copies parser-valid duplicate and recovered optional-closing-tag winners with nonblocking diagnostics" do
    duplicate = "<ul><li id=x>one<li id=x>two</ul>"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: duplicate)

    expect(result).to include(ok: true, output: duplicate)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :ambiguous_owner, blocking: false, source_role: :theirs)
    )
  end

  it "fails closed instead of synthesizing inside parser-implied optional closing tags" do
    optional = "<ul><li id=one>Base<li id=two>Other</ul>"
    result = provider.merge3(
      base_source: optional,
      ours_source: optional.sub("Base", "Ours"),
      theirs_source: optional.sub("Other", "Theirs")
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :unsafe_source_range))
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it "rejects malformed exact winners and attributes the selected role" do
    malformed = "<html><body><div id=x></body></html"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: malformed)

    expect(result).to include(ok: false, source_role: :theirs)
    expect(result.fetch(:diagnostics)).to contain_exactly(hash_including(category: :parse_error, blocking: true))
  end

  it "preserves the legacy parser and CRISPR APIs alongside provider dispatch" do
    expect(Html::Merge.parse_html(base)).to include(ok: true)
    expect(Html::Merge.document_context(content: base)).to be_a(Ast::Crispr::DocumentContext)
    expect(Html::Merge.ensure_yard_content_wrapper("<h1>Documentation by YARD</h1>")).to include("id=\"content\"")
  end
end

RSpec.describe "HTML provider conformance" do
  subject(:provider) { Html::Merge.merge_provider }

  let(:stable) { "<main id=stable>stable</main>\n" }
  let(:provider_conformance) do
    {
      dialect: :html,
      backend: :"kreuzberg-language-pack",
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: stable.sub("stable</main>", "changed</main>") },
        merge2: { current_source: stable, incoming_source: "#{stable}<aside id=added>added</aside>\n" },
        merge3: {
          base_source: stable,
          ours_source: "#{stable}<aside id=ours>ours</aside>\n",
          theirs_source: "#{stable}<footer id=theirs>theirs</footer>\n"
        }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "<main id=broken",
        theirs_source: stable,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "<main id=obsolete>old</main>\n#{stable}",
          ours_source: "<main id=obsolete>old</main>\n#{stable}",
          theirs_source: stable
        },
        expected_value: [[:id, "stable"]]
      },
      parse_output: lambda { |source|
        Html::Merge::FileAnalysis.new(source).wrappers.map do |wrapper|
          id = wrapper.explicit_id
          id ? [:id, id] : [:singleton, wrapper.tag_name]
        end
      }
    }
  end

  it_behaves_like "Ast::Merge::ProviderConformance"
end
# rubocop:enable Metrics/BlockLength
