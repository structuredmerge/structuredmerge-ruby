# frozen_string_literal: true

RSpec.describe 'Rust TSLP language matrix' do
  samples = {
    bash: "echo hi\n",
    go: "package main\nfunc main() {}\n",
    json: '{"name":"x"}',
    markdown: "# Title\n",
    ruby: "class Example; end\n",
    rust: "fn main() {}\n",
    toml: "name = \"x\"\n",
    typescript: "const answer: number = 42;\n",
    yaml: "name: value\n"
  }.freeze

  samples.each do |language, source|
    it "discovers and parses #{language} with normalized provenance" do
      tree = TreeHaver.with_backend(:rust_tslp) do
        TreeHaver::GrammarFinder.new(language).register!(raise_on_missing: true)
        TreeHaver.parser_for(language).parse(source)
      end

      expect(tree.root_node).not_to be_nil
      expect(tree.root_node.text).to eq(source)
      expect(tree.has_error?).to be(false)
      expect(tree.provenance).to include(
        'backend_ref' => include('id' => 'kreuzberg-language-pack'),
        'language' => language.to_s
      )
    end
  end
end
