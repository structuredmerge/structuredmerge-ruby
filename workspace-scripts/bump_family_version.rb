#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "set"
require "rubygems"
require "prism"

module StructuredMergeRuby
  class FamilyVersionBump
    DependencyCallNames = %i[
      add_dependency
      add_runtime_dependency
      add_development_dependency
    ].freeze

    Edit = Struct.new(:path, :start_offset, :end_offset, :replacement, :reason, keyword_init: true)
    GemEntry = Struct.new(:name, :dir, :gemspec_path, :version_path, :version, keyword_init: true)

    def self.call(argv)
      new(argv).call
    end

    def initialize(argv)
      @root = Pathname(__dir__).parent.expand_path
      @options = {
        dry_run: false,
        check: false,
        allow_dirty: false,
      }
      @target_version = nil
      @from_version = nil
      parse_options(argv)
    end

    def call
      fail_usage!("target version is required") unless @target_version
      validate_version!(@target_version, "target")
      validate_version!(@from_version, "from") if @from_version
      validate_clean_worktree! unless @options[:allow_dirty] || @options[:check] || @options[:dry_run]

      gems = discover_gems
      family_names = gems.map(&:name).to_set
      validate_current_versions!(gems)

      edits = []
      gems.each do |entry|
        edits.concat(version_file_edits(entry))
        edits.concat(gemspec_edits(entry, family_names))
      end

      report_plan(gems, edits)

      if @options[:check]
        exit(edits.empty? ? 0 : 1)
      elsif @options[:dry_run]
        return
      end

      apply_edits(edits)
      puts
      puts "Updated #{edits.map(&:path).uniq.length} file(s)."
    end

    private

    def parse_options(argv)
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: ruby workspace-scripts/bump_family_version.rb VERSION [options]"

        opts.on("--from VERSION", "Require the current family version before bumping") do |version|
          @from_version = version
        end

        opts.on("--check", "Validate and exit nonzero if edits would be needed") do
          @options[:check] = true
        end

        opts.on("--dry-run", "Print planned edits without writing files") do
          @options[:dry_run] = true
        end

        opts.on("--allow-dirty", "Allow writes with a dirty git worktree") do
          @options[:allow_dirty] = true
        end

        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit 0
        end
      end

      rest = parser.parse(argv)
      fail_usage!("provide exactly one target version") unless rest.length == 1
      @target_version = rest.fetch(0)
    rescue OptionParser::ParseError => e
      fail_usage!(e.message)
    end

    def fail_usage!(message)
      warn "error: #{message}"
      warn "Run with --help for usage."
      exit 2
    end

    def fail!(message)
      warn "error: #{message}"
      exit 1
    end

    def validate_version!(version, label)
      fail_usage!("#{label} version cannot be empty") if version.to_s.empty?
      fail_usage!("#{label} version must not contain surrounding whitespace") unless version == version.strip
      Gem::Version.new(version)
    rescue ArgumentError => e
      fail_usage!("invalid #{label} version #{version.inspect}: #{e.message}")
    end

    def validate_clean_worktree!
      status = IO.popen(["git", "status", "--porcelain"], chdir: @root.to_s, &:read)
      return if status.empty?

      warn "error: worktree is dirty; commit/stash first or pass --allow-dirty"
      warn status
      exit 1
    end

    def discover_gems
      gem_dirs = Dir.children(@root.join("gems"))
        .map { |name| @root.join("gems", name) }
        .select(&:directory?)
        .select { |path| Dir.children(path).any? { |name| name.end_with?(".gemspec") } }
        .sort_by { |path| path.basename.to_s }

      gem_dirs.map do |dir|
        gemspecs = Dir.children(dir).select { |name| name.end_with?(".gemspec") }.sort
        fail!("expected one gemspec in #{relative(dir)}, found #{gemspecs.length}") unless gemspecs.length == 1

        gemspec_path = dir.join(gemspecs.fetch(0))
        name = read_gemspec_name(gemspec_path)
        version_path, version = read_version_file(dir)
        GemEntry.new(name: name, dir: dir, gemspec_path: gemspec_path, version_path: version_path, version: version)
      end
    end

    def read_gemspec_name(path)
      source = path.read
      root = parse_ruby(path, source)
      call = each_node(root).find do |node|
        node.is_a?(Prism::CallNode) &&
          node.name == :"name=" &&
          receiver_named?(node.receiver, :spec) &&
          node.arguments&.arguments&.first.is_a?(Prism::StringNode)
      end
      fail!("could not find spec.name assignment in #{relative(path)}") unless call
      call.arguments.arguments.first.unescaped
    end

    def read_version_file(gem_dir)
      paths = Dir.glob(gem_dir.join("lib", "**", "version.rb").to_s).sort.map { |path| Pathname(path) }
      fail!("expected one lib/**/version.rb in #{relative(gem_dir)}, found #{paths.length}") unless paths.length == 1

      path = paths.fetch(0)
      source = path.read
      root = parse_ruby(path, source)
      writes = each_node(root).select do |node|
        node.is_a?(Prism::ConstantWriteNode) &&
          node.name == :VERSION &&
          node.value.is_a?(Prism::StringNode)
      end
      fail!("expected one VERSION string write in #{relative(path)}, found #{writes.length}") unless writes.length == 1

      [path, writes.fetch(0).value.unescaped]
    end

    def validate_current_versions!(gems)
      versions = gems.map(&:version).uniq.sort
      if @from_version
        mismatches = gems.reject { |entry| entry.version == @from_version }
        return if mismatches.empty?

        warn "error: --from #{@from_version} did not match every gem"
        mismatches.each { |entry| warn "  #{entry.name}: #{entry.version}" }
        exit 1
      end

      return if versions.length == 1

      warn "error: family versions are inconsistent; pass --from VERSION after resolving the expected current version"
      gems.each { |entry| warn "  #{entry.name}: #{entry.version}" }
      exit 1
    end

    def version_file_edits(entry)
      return [] if entry.version == @target_version

      source = entry.version_path.read
      root = parse_ruby(entry.version_path, source)
      write = each_node(root).find do |node|
        node.is_a?(Prism::ConstantWriteNode) &&
          node.name == :VERSION &&
          node.value.is_a?(Prism::StringNode)
      end

      content_loc = write.value.content_loc
      [
        Edit.new(
          path: entry.version_path,
          start_offset: content_loc.start_offset,
          end_offset: content_loc.end_offset,
          replacement: @target_version,
          reason: "#{entry.name} VERSION #{entry.version} -> #{@target_version}",
        ),
      ]
    end

    def gemspec_edits(entry, family_names)
      source = entry.gemspec_path.read
      root = parse_ruby(entry.gemspec_path, source)
      edits = []

      each_node(root).each do |node|
        next unless dependency_call?(node)

        args = node.arguments&.arguments || []
        gem_name_node = args.first
        next unless gem_name_node.is_a?(Prism::StringNode)

        dependency_name = gem_name_node.unescaped
        next unless family_names.include?(dependency_name)

        requirement_nodes = args.drop(1)
        if requirement_nodes.any? { |arg| spec_version_interpolation?(arg) }
          next
        end

        exact_string = requirement_nodes.find { |arg| exact_version_string?(arg, entry.version) }
        if exact_string
          edits << Edit.new(
            path: entry.gemspec_path,
            start_offset: exact_string.content_loc.start_offset,
            end_offset: exact_string.content_loc.end_offset,
            replacement: "= #{@target_version}",
            reason: "#{entry.name} dependency #{dependency_name} #{entry.version} -> #{@target_version}",
          )
          next
        end

        fail!(
          "#{relative(entry.gemspec_path)} has family dependency #{dependency_name.inspect} " \
          "without an exact spec.version lock"
        )
      end

      edits
    end

    def dependency_call?(node)
      node.is_a?(Prism::CallNode) &&
        DependencyCallNames.include?(node.name) &&
        receiver_named?(node.receiver, :spec)
    end

    def exact_version_string?(node, version)
      return false unless node.is_a?(Prism::StringNode)

      parts = node.unescaped.split(" ", 2)
      parts.length == 2 && parts.fetch(0) == "=" && parts.fetch(1) == version
    end

    def spec_version_interpolation?(node)
      return false unless node.is_a?(Prism::InterpolatedStringNode)

      parts = node.parts
      return false unless parts.length == 2
      return false unless parts.fetch(0).is_a?(Prism::StringNode)
      return false unless parts.fetch(0).unescaped == "= "

      embedded = parts.fetch(1)
      return false unless embedded.is_a?(Prism::EmbeddedStatementsNode)

      body = embedded.statements&.body || []
      body.length == 1 && spec_version_call?(body.fetch(0))
    end

    def spec_version_call?(node)
      node.is_a?(Prism::CallNode) &&
        node.name == :version &&
        receiver_named?(node.receiver, :spec) &&
        node.arguments.nil?
    end

    def receiver_named?(node, name)
      return node.name == name if node.is_a?(Prism::LocalVariableReadNode)

      node.is_a?(Prism::CallNode) &&
        node.name == name &&
        node.receiver.nil? &&
        node.arguments.nil?
    end

    def parse_ruby(path, source)
      result = Prism.parse(source)
      return result.value if result.success?

      messages = result.errors.map(&:message).join("; ")
      fail!("could not parse #{relative(path)} with Prism: #{messages}")
    end

    def each_node(root)
      nodes = []
      stack = [root]
      until stack.empty?
        node = stack.pop
        next unless node.respond_to?(:child_nodes)

        nodes << node
        node.child_nodes.reverse_each { |child| stack << child if child }
      end
      nodes
    end

    def apply_edits(edits)
      edits.group_by(&:path).each do |path, path_edits|
        source = path.read
        updated = apply_path_edits(source, path_edits)
        path.write(updated)
      end
    end

    def apply_path_edits(source, edits)
      edits.sort_by(&:start_offset).reverse_each do |edit|
        source = source.byteslice(0, edit.start_offset) + edit.replacement + source.byteslice(edit.end_offset..)
      end
      source
    end

    def report_plan(gems, edits)
      puts "StructuredMerge Ruby family gems: #{gems.length}"
      puts "Current version(s): #{gems.map(&:version).uniq.sort.join(", ")}"
      puts "Target version: #{@target_version}"
      puts

      if edits.empty?
        puts "No edits needed."
        return
      end

      puts "Planned edits:"
      edits.each do |edit|
        puts "  #{relative(edit.path)}: #{edit.reason}"
      end
    end

    def relative(path)
      Pathname(path).relative_path_from(@root).to_s
    end
  end
end

StructuredMergeRuby::FamilyVersionBump.call(ARGV)
