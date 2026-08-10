# frozen_string_literal: true

require 'spec_helper'
require 'markdown/merge/rspec/shared_examples/source_preserving_provider'

RSpec.describe Markly::Merge::Provider do
  subject(:provider) { Markly::Merge.merge_provider }

  let(:provider_backend) { :markly }
  let(:provider_dialect) { :commonmark }
  let(:provider_role) { :backend }
  let(:legacy_assertion) { -> { Markly::Merge.parse_markdown("# A\n\ntext\n", 'commonmark')[:ok] } }

  it_behaves_like 'Markdown::Merge::SourcePreservingProvider'
end
