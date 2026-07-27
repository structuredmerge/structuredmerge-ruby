# frozen_string_literal: true

RSpec.describe Html::Merge do
  it "has a version number" do
    expect(Html::Merge::VERSION).not_to be nil
  end

  it "parses HTML through TreeHaver" do
    result = described_class.parse_html(<<~HTML)
      <!doctype html>
      <html>
        <body><main id="content"><h1>Documentation by YARD</h1></main></body>
      </html>
    HTML

    expect(result).to include(ok: true)
    expect(result.dig(:analysis, :root_kind)).to be_a(String)
    expect(result.dig(:analysis, :nodes).map { |node| node.fetch(:type) }).to include("element")
  end

  it "reports the HTML feature profile" do
    expect(described_class.html_plan_context).to include(
      family_profile: include(family: "html"),
      feature_profile: include(supports_dialects: false)
    )
  end

  it "uses ast-crispr with HTML structural owners to repair a YARD content wrapper" do
    source = <<~HTML
      <html>
        <body>
          <h1 class="noborder title">Documentation by YARD</h1>
        </body>
      </html>
    HTML

    updated = described_class.ensure_yard_content_wrapper(source)

    expect(updated).to include('<div id="content"><h1 class="noborder title">Documentation by YARD</h1></div>')
    expect(described_class.parse_html(updated)).to include(ok: true)
  end
end
