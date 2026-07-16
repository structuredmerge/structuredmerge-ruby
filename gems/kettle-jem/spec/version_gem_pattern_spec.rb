# frozen_string_literal: true

VERSION_GEM_PATTERN_GEMSPEC_EXAMPLES = Dir.glob(Pathname(__dir__).join("..", "..", "*", "*.gemspec")).sort.map do |gemspec_path|
  [gemspec_path, Pathname(gemspec_path).dirname, File.basename(gemspec_path, ".gemspec")]
end

RSpec.describe Kettle::Jem do
  VERSION_GEM_PATTERN_GEMSPEC_EXAMPLES.each do |gemspec_path, gem_root, gem_name|
    it "keeps #{gem_name} aligned with the Kettle/Jem version_gem bootstrap shape" do
      version_paths = Dir.glob(gem_root.join("lib", "**", "version.rb"))
      expect(version_paths).not_to be_empty

      version_paths.each do |version_path|
        version_content = File.read(version_path)
        expect(version_content).to include("module Version")
        expect(version_content).to include("VERSION = Version::VERSION # Traditional Constant Location")
        expect(version_content).not_to include("version_gem")
        expect(version_content).not_to include("VersionGem")

        namespace = version_content.scan(/^\s*module\s+([A-Z][A-Za-z0-9_]*)\s*$/).flatten.take_while { |name| name != "Version" }.join("::")
        expect(namespace).not_to be_empty

        version_dir = File.dirname(version_path)
        entrypoint_path = File.join(File.dirname(version_dir), "#{File.basename(version_dir)}.rb")
        expect(File).to exist(entrypoint_path)

        entrypoint_content = File.read(entrypoint_path)
        non_default_version_gem_path = File.join(version_dir, "version_gem.rb")
        version_require_pattern = /^\s*require_relative\s+["']#{Regexp.escape(File.basename(version_dir))}\/version["']/
        class_eval = "#{namespace}::Version.class_eval do"
        if File.exist?(non_default_version_gem_path)
          expect(entrypoint_content).not_to match(/^\s*require\s+["']version_gem["']/)
          expect(entrypoint_content).to match(version_require_pattern)
          expect(entrypoint_content).not_to include(class_eval)
          next
        end

        expect(entrypoint_content).to match(/^\s*require\s+["']version_gem["']/)
        version_require_index = entrypoint_content =~ version_require_pattern
        expect(version_require_index).not_to be_nil
        expect(version_require_index).to be < entrypoint_content.index(class_eval)
        expect(entrypoint_content).to include(class_eval)
        expect(entrypoint_content).to include("extend VersionGem::Basic")
      end

      gemspec_content = File.read(gemspec_path)
      if Dir.glob(gem_root.join("lib", "**", "version_gem.rb")).any?
        expect(gemspec_content).not_to match(/spec\.add_dependency(?:\(| )["']version_gem["']/)
      else
        expect(gemspec_content).to match(/spec\.add_dependency(?:\(| )["']version_gem["']/)
      end
    end
  end
end
