# frozen_string_literal: true

RSpec.describe Toml::Merge do
  let(:qlty_toml) do
    <<~TOML
      # For a guide to configuration, visit https://qlty.sh/d/config
      # Or for a full reference, visit https://qlty.sh/d/qlty-toml
      config_version = "0"

      exclude_patterns = [
        "**/docs/**",
        "**/vendor/**",
      ]

      [smells]
      mode = "comment"

      [smells.duplication]
      enabled = true
      threshold = 20
    TOML
  end

  it 'merges commented qlty-style TOML without treating the path builder block as a Proc intersection' do
    result = described_class.merge_toml(qlty_toml, qlty_toml, 'toml')

    expect(result[:ok]).to be(true)
    expect(result[:output]).to include('config_version = "0"')
    expect(result[:output]).to include('[smells.duplication]')
    expect(result[:output]).to include('threshold = 20')
  end
end
