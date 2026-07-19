# frozen_string_literal: true

RSpec.shared_examples 'Ast::Merge::TreeHaverBackendContract' do |language:, backend_id:, source:|
  it "registers #{backend_id} as a concrete TreeHaver backend for #{language}" do
    backend_ref = TreeHaver::BackendRegistry.fetch(backend_id)
    registrations = TreeHaver.registered_languages(language)

    expect(backend_ref).not_to be_nil
    expect(registrations).not_to be_empty

    tree = TreeHaver.with_backend(backend_id) do
      TreeHaver.parser_for(language).parse(source)
    end

    expect(tree).to respond_to(:root_node)
    expect(tree.root_node).not_to be_nil
    expect(tree.root_node.type.to_s).not_to be_empty
  end
end
