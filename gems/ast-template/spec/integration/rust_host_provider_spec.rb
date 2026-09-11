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

  it 'returns a read-only Rust template plan without claiming filesystem execution' do
    Dir.mktmpdir('ast-template-rust-plan') do |root|
      template_root = File.join(root, 'templates')
      destination_root = File.join(root, 'destination')
      FileUtils.mkdir_p(template_root)
      FileUtils.mkdir_p(destination_root)
      File.write(File.join(template_root, 'README.md'), "# {{PACKAGE_NAME}}\n")

      report = described_class.new.plan(
        options: {
          mode: 'plan',
          template_root: template_root,
          destination_root: destination_root,
          context: { project_name: 'widget' },
          default_strategy: 'raw_copy',
          overrides: [],
          replacements: { 'PACKAGE_NAME' => 'widget' },
          allowed_families: nil
        }
      )

      expect(report[:mode]).to eq('plan')
      expect(report.dig(:runner_report, 'plan_report', 'entries')).not_to be_empty
      expect(File.exist?(File.join(destination_root, 'README.md'))).to be(false)
    end
  end
end
