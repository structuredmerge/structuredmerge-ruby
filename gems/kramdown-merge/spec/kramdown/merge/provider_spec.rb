# frozen_string_literal: true

require 'spec_helper'
require 'markdown/merge/rspec/shared_examples/source_preserving_provider'

RSpec.describe Kramdown::Merge::Provider do
  subject(:provider) { Kramdown::Merge.merge_provider }

  let(:provider_backend) { :kramdown }
  let(:provider_dialect) { :kramdown }
  let(:provider_role) { :backend }
  let(:legacy_assertion) { -> { Kramdown::Merge.parse_markdown("# A\n\ntext\n", 'markdown')[:ok] } }

  it_behaves_like 'Markdown::Merge::SourcePreservingProvider'
end
