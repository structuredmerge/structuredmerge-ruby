# frozen_string_literal: true

require 'spec_helper'
require 'markdown/merge/rspec/shared_examples/source_preserving_provider'

RSpec.describe Commonmarker::Merge::Provider do
  subject(:provider) { Commonmarker::Merge.merge_provider }

  let(:provider_backend) { :commonmarker }
  let(:provider_dialect) { :commonmark }
  let(:provider_role) { :backend }
  let(:legacy_assertion) { -> { Commonmarker::Merge.parse_markdown("# A\n\ntext\n", 'commonmark')[:ok] } }

  it_behaves_like 'Markdown::Merge::SourcePreservingProvider'
end
