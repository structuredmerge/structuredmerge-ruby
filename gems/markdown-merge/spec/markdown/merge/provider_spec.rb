# frozen_string_literal: true

require 'spec_helper'
require 'markdown/merge/rspec/shared_examples/source_preserving_provider'

RSpec.describe Markdown::Merge::Provider do
  subject(:provider) { Markdown::Merge.merge_provider }

  let(:provider_backend) { :'kreuzberg-language-pack' }
  let(:provider_dialect) { :markdown }
  let(:provider_role) { :workflow }
  let(:legacy_assertion) { -> { Markdown::Merge.parse_markdown("# A\n\ntext\n", 'markdown')[:ok] } }

  it_behaves_like 'Markdown::Merge::SourcePreservingProvider'
end
