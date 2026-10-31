# frozen_string_literal: true

require 'spec_helper'
require 'markdown/merge/rspec/shared_examples/source_preserving_provider'

RSpec.describe Markdown::Merge::Provider do
  subject(:provider) { Markdown::Merge.merge_provider }

  it 'does not treat a Rust parser or crate as a Rust merge-operation provider' do
    result = Ast::Merge.dispatch_provider(
      :merge3,
      provider_id: 'rust.markdown',
      family: :markdown,
      dialect: :markdown,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      base_source: 'base',
      ours_source: 'ours',
      theirs_source: 'theirs'
    )

    expect(result).to include(operation: :merge3, ok: false)
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :unsupported_capability))
  end

  let(:provider_backend) { :'kreuzberg-language-pack' }
  let(:provider_dialect) { :markdown }
  let(:provider_role) { :workflow }
  let(:legacy_assertion) { -> { Markdown::Merge.parse_markdown("# A\n\ntext\n", 'markdown')[:ok] } }

  it_behaves_like 'Markdown::Merge::SourcePreservingProvider'
end
