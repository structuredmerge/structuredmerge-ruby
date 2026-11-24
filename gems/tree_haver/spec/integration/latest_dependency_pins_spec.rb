# frozen_string_literal: true

require 'json'
require 'net/http'

# Release gate. tree-sitter-language-pack and structuredmerge-core ship more than once a
# day, and a stale lock silently changes behavior (the released core gem once compiled
# against a newer TSLP crate than the family had been tested with). The family root
# lockfile must pin the latest release of each, otherwise the release fails here.
# Skipped only when RubyGems cannot be reached or the monorepo root lockfile is absent.
RSpec.describe 'latest dependency pins' do
  let(:lockfile) { File.expand_path('../../../../Gemfile.lock', __dir__) }

  def latest_release(gem_name)
    response = Net::HTTP.get_response(URI("https://rubygems.org/api/v1/versions/#{gem_name}/latest.json"))
    JSON.parse(response.body).fetch('version') if response.is_a?(Net::HTTPSuccess)
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError
    nil
  end

  def locked_versions(gem_name)
    File.read(lockfile).scan(/^    #{Regexp.escape(gem_name)} \((\d+(?:\.\d+)*)(?:-[\w.-]+)?\)$/).flatten.uniq
  end

  %w[tree_sitter_language_pack structuredmerge-core].each do |gem_name|
    it "locks the latest released #{gem_name} in the family root Gemfile.lock" do
      skip 'monorepo root Gemfile.lock not present' unless File.file?(lockfile)
      latest = latest_release(gem_name)
      skip 'rubygems.org is unreachable' unless latest

      locked = locked_versions(gem_name)
      message = "#{gem_name} #{latest} is released but the family root Gemfile.lock pins #{locked.inspect}. " \
                'Update the family root bundle (and the core pins in the core repo via ' \
                'workspace-scripts/check_latest_pins.py --write) before releasing.'

      expect(locked).to eq([latest]), message
    end
  end
end
