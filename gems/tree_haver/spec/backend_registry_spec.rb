# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe TreeHaver::BackendRegistry do
  it "registers the generic language-pack and restored native tree-sitter backends" do
    expect(described_class.fetch("tslp")&.family).to eq("tree-sitter")
    expect(described_class.fetch("kreuzberg-language-pack")&.family).to eq("tree-sitter")

    %w[mri rust ffi java].each do |backend_id|
      expect(described_class.fetch(backend_id)&.family).to eq("tree-sitter")
    end
  end

  it "exposes graceful availability checks for restored native backends" do
    %i[mri rust ffi java tslp].each do |backend_name|
      expect { described_class.available?(backend_name) }.not_to raise_error
      expect(described_class.available?(backend_name)).to satisfy { |value| value == true || value == false }
    end
  end

  it "loads MRI tree-sitter languages with a string language name" do
    stub_const("TreeSitter", Module.new)
    language_class = class_double("TreeSitter::Language")
    stub_const("TreeSitter::Language", language_class)
    allow(TreeHaver::Backends::MRI).to receive(:available?).and_return(true)

    expect(language_class).to receive(:load).with("json", "/workspace/libtree-sitter-json.so").and_return(:native_language)

    language = TreeHaver::Backends::MRI::Language.from_library(
      "/workspace/libtree-sitter-json.so",
      symbol: "tree_sitter_json",
      name: :json,
    )

    expect(language).to be_a(TreeHaver::Backends::MRI::Language)
  end

  describe ".register_tag" do
    let(:tag_name) { :example_backend }
    let(:backend_name) { :example }

    it "registers tag metadata and exposes tag availability" do
      described_class.register_tag(tag_name, category: :backend, backend_name: backend_name) { true }

      expect(described_class.tag_registered?(tag_name)).to be(true)
      expect(described_class.registered_tags).to include(tag_name)
      expect(described_class.tags_by_category(:backend)).to include(tag_name)
      expect(described_class.tag_metadata(tag_name)).to include(
        category: :backend,
        backend_name: backend_name,
      )
      expect(described_class.tag_available?(tag_name)).to be(true)
    end

    it "defines dependency-tag availability methods after the RSpec helper is loaded" do
      require "tree_haver/rspec/dependency_tags"

      described_class.register_tag(:dynamic_example_backend, category: :backend, backend_name: :dynamic_example) { true }

      expect(TreeHaver::RSpec::DependencyTags.dynamic_example_available?).to be(true)
    end
  end
end
