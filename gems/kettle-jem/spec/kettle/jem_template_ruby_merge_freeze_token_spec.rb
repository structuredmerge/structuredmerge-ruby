# frozen_string_literal: true

# kettle-jem is the merge orchestrator, so ALL freeze tags in templated
# files are uniformly owned by kettle-jem. The Ruby/gemfile merge paths
# must pass the configured freeze_token through to Prism::Merge, whose
# own default ("prism-merge") must never decide ownership.
#
# Scope note: with a *balanced* freeze pair around a node that conflicts
# with a template node, Prism::Merge preserves the frozen region verbatim
# AND still emits the template-only node (block semantics live in the
# merge engine). These specs assert the token contract — frozen content
# survives — not the engine's block placement policy.
RSpec.describe Kettle::Jem do
  def merged_output(file_type, recipe, template, destination)
    result = described_class.send(:merge_ruby_template_source, file_type, recipe, template, destination)
    expect(result[:ok]).to be(true)
    result.fetch(:output)
  end

  let(:gemfile_template) do
    <<~GEMFILE
      # Ruby >= 2.5
      gem "ostruct", "~> 0.6"
    GEMFILE
  end

  let(:gemfile_recipe) do
    {target_path: "gemfiles/modular/ostruct/r4/v0.6.gemfile", template_preference: {}}
  end

  it "preserves kettle-jem freeze blocks in gemfiles" do
    destination = <<~GEMFILE
      # Ruby >= 2.5
      # kettle-jem:freeze
      gem "ostruct", "~> 0.6", ">= 0.6.1"
      # kettle-jem:unfreeze
    GEMFILE

    output = merged_output(:gemfile, gemfile_recipe, gemfile_template, destination)

    expect(output).to include('gem "ostruct", "~> 0.6", ">= 0.6.1"')
  end

  it "honors a recipe-configured custom freeze token in gemfiles" do
    recipe = {
      target_path: "gemfiles/modular/ostruct/r4/v0.6.gemfile",
      template_preference: {freeze_token: "custom-freeze"}
    }
    destination = <<~GEMFILE
      # Ruby >= 2.5
      # custom-freeze:freeze
      gem "ostruct", "~> 0.6", ">= 0.6.1"
      # custom-freeze:unfreeze
    GEMFILE

    output = merged_output(:gemfile, recipe, gemfile_template, destination)

    expect(output).to include('gem "ostruct", "~> 0.6", ">= 0.6.1"')
  end

  it "preserves kettle-jem freeze blocks in plain Ruby template targets" do
    template = <<~RUBY
      module Example
        def self.greeting
          "template"
        end
      end
    RUBY
    destination = <<~RUBY
      # kettle-jem:freeze
      module DestinationOwned
        MARKER = true
      end
      # kettle-jem:unfreeze
    RUBY
    recipe = {target_path: "lib/example.rb", template_preference: {}}

    output = merged_output(:ruby, recipe, template, destination)

    expect(output).to include("module DestinationOwned", "MARKER = true", "module Example")
  end
end
