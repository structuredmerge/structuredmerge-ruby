# frozen_string_literal: true

require 'digest'
require 'json'
require 'rubygems/package'
require 'tmpdir'

spec = Gem.loaded_specs.fetch('structuredmerge-core')
raise 'Wrong installed core selected' unless File.realpath(spec.full_gem_path) == File.realpath(ENV.fetch('STRUCTUREDMERGE_CORE_INSTALLED_DIR'))
raise 'Prototype loaded' if Gem.loaded_specs.key?('structuredmerge_host_prototype')
export_root = File.join(ENV.fetch('RUNNER_TEMP'), 'structuredmerge-core-export')
report = JSON.parse(File.read(File.join(export_root, 'core-ruby-artifact.json')))
archive = Gem::Package.new(File.join(export_root, report.fetch('artifact')))
# Compare every installed payload byte with the verified archive, not just the
# version: a registry package with the same version must not silently substitute.
archive.verify
Dir.mktmpdir('payload-check-', export_root) do |directory|
  archive.extract_files(directory)
  report.fetch('files').each do |name|
    installed = File.join(spec.full_gem_path, name)
    expected = File.join(directory, name)
    raise "Installed payload mismatch: #{name}" unless File.file?(installed) && Digest::SHA256.file(installed).hexdigest == Digest::SHA256.file(expected).hexdigest
  end
end
require 'structuredmerge_core'
puts "structuredmerge-core #{spec.version} loaded from the installed CI artifact"
