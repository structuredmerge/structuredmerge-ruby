# frozen_string_literal: true

RSpec.describe 'Native-first and native-only family dispatch boundary' do
  # Parser availability (rust_tslp) is not a Rust merge-operation adapter. Every operation for these
  # families must report unsupported instead of falling back to a generic Rust provider.
  families = {
    'rust.ruby' => %i[ruby ruby source_preserving],
    'rust.markdown' => %i[markdown markdown source_preserving],
    'rust.yaml' => %i[yaml yaml source_preserving],
    'rust.toml' => %i[toml toml source_preserving],
    'rust.rbs' => %i[rbs rbs source_preserving],
    'rust.text' => %i[text text coarse_document],
    'rust.binary' => %i[binary binary opaque_binary],
    'rust.zip' => %i[zip zip opaque_archive]
  }.freeze

  requests = {
    analyze: { source: 'a' },
    diff2: { before_source: 'a', after_source: 'b' },
    merge2: { incoming_source: 'a', current_source: 'b' },
    merge3: { base_source: 'a', ours_source: 'b', theirs_source: 'c' }
  }.freeze

  families.each do |provider_id, (family, dialect, profile_id)|
    requests.each do |operation, payload|
      it "#{provider_id} reports #{operation} as unsupported without a generic Rust fallback" do
        result = Ast::Merge.dispatch_provider(
          operation,
          { provider_id: provider_id, family: family, dialect: dialect, backend: :rust_tslp,
            profile_id: profile_id }.merge(payload)
        )

        expect(result.fetch(:ok)).to be(false)
        expect(result.fetch(:diagnostics)).to include(hash_including(category: :unsupported_capability))
      end
    end
  end
end
