# frozen_string_literal: true

RSpec.describe Ast::Template::RustHostProvider do
  describe '.available?' do
    it 'reports the generated host bridge when loaded' do
      expect(described_class).to be_available
    end
  end

  it 'reports missing roots through the portable options contract' do
    report = described_class.new.report(
      kind: 'options',
      options: {
        mode: 'plan',
        template_root: '',
        destination_root: '',
        context: {},
        default_strategy: 'merge',
        overrides: [],
        replacements: {},
        allowed_families: nil
      }
    )

    expect(report[:request_kind]).to eq('options')
    expect(report[:ready]).to be(false)
    expect(report[:diagnostics].map { |entry| entry['reason'] }).to eq(
      %w[missing_destination_root missing_template_root]
    )
  end

  it 'reports an unknown profile through the portable profile contract' do
    report = described_class.new.report(
      kind: 'profile',
      profile_name: 'missing',
      profiles: {},
      options: {
        mode: 'plan',
        template_root: '/templates',
        destination_root: '/destination',
        context: {},
        default_strategy: 'merge',
        overrides: [],
        replacements: {},
        allowed_families: nil
      }
    )

    expect(report[:request_kind]).to eq('profile')
    expect(report[:ready]).to be(false)
    expect(report[:diagnostics].map { |entry| entry['reason'] }).to include('missing_profile')
  end
end

