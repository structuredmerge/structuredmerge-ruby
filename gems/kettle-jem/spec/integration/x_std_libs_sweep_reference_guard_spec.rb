# frozen_string_literal: true

RSpec.describe Kettle::Jem, "x_std_libs sweep reference-closure guard" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  let(:version_split_loader) do
    <<~RUBY
      ### Std Lib Extracted Gems
      ruby_version = Gem::Version.new(RUBY_VERSION)

      if ruby_version >= Gem::Version.new("4.0")
        eval_gemfile "x_std_libs/r4/libs.gemfile"
      elsif ruby_version >= Gem::Version.new("3.2")
        eval_gemfile "x_std_libs/r3/libs.gemfile"
      elsif ruby_version >= Gem::Version.new("3.1")
        eval_gemfile "x_std_libs/r3.1/libs.gemfile"
      else
        eval_gemfile "x_std_libs/r2/libs.gemfile"
      end
    RUBY
  end

  def write_member_gemfile_tree(root, loader:)
    write_tree(root, {
      "example.gemspec" => <<~RUBY,
        Gem::Specification.new do |spec|
          spec.name = "example"
          spec.summary = "Example gem"
          spec.required_ruby_version = ">= 3.1"
        end
      RUBY
      ".kettle-jem.yml" => <<~YAML,
        templates:
          root: packaged
          apply: true
          entries:
            - gemfiles/modular/x_std_libs.gemfile
            - gemfiles/modular/x_std_libs/r2/libs.gemfile
            - gemfiles/modular/x_std_libs/r3/libs.gemfile
            - gemfiles/modular/x_std_libs/r3.1/libs.gemfile
            - gemfiles/modular/x_std_libs/r4/libs.gemfile
            - gemfiles/modular/erb/r2/v3.0.gemfile
            - gemfiles/modular/erb/r3/v5.0.gemfile
            - gemfiles/modular/erb/r3.1/v4.0.gemfile
            - gemfiles/modular/erb/r4/v5.0.gemfile
            - gemfiles/modular/mutex_m/r3/v0.3.gemfile
      YAML
      "Gemfile" => <<~RUBY,
        eval_gemfile "gemfiles/modular/x_std_libs.gemfile"
      RUBY
      "gemfiles/modular/x_std_libs.gemfile" => loader,
      "gemfiles/modular/x_std_libs/r4/libs.gemfile" => <<~RUBY,
        eval_gemfile "../../erb/r4/v5.0.gemfile"
      RUBY
      "gemfiles/modular/x_std_libs/r3/libs.gemfile" => <<~RUBY,
        eval_gemfile "../../erb/r3/v5.0.gemfile"
        eval_gemfile "../../mutex_m/r3/v0.3.gemfile"
      RUBY
      "gemfiles/modular/x_std_libs/r3.1/libs.gemfile" => <<~RUBY,
        eval_gemfile "../../erb/r3.1/v4.0.gemfile"
      RUBY
      "gemfiles/modular/x_std_libs/r2/libs.gemfile" => <<~RUBY,
        eval_gemfile "../../erb/r2/v3.0.gemfile"
      RUBY
      "gemfiles/modular/erb/r4/v5.0.gemfile" => %(gem "erb", "~> 6.0"   # ruby >= 4.0\n),
      "gemfiles/modular/erb/r3/v5.0.gemfile" => %(gem "erb", "~> 6.0", ">= 6.0.7"   # ruby >= 3.2.0\n),
      "gemfiles/modular/erb/r3.1/v4.0.gemfile" => %(gem "erb", "~> 4.0", ">= 4.0.4"   # ruby >= 3.1.0\n),
      "gemfiles/modular/erb/r2/v3.0.gemfile" => %(gem "erb", "~> 3.0"   # ruby < 3.1\n),
      "gemfiles/modular/mutex_m/r3/v0.3.gemfile" => %(gem "mutex_m", "~> 0.3.0"\n)
    })
  end

  # A Ruby 4.0+ test floor makes every bucket below r4 irrelevant to the sweep,
  # which is what deleted the referenced r2/r3/r3.1 variants in the 7.1.41
  # family-wide incident while the committed loaders still branched to them.
  let(:min_ruby_4_config) { {"ruby" => {"test_minimum" => "4.0"}} }

  it "keeps variant gemfiles a remaining version-split loader still references" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-x-stdlib-reference-guard", tmp_root) do |root|
      write_member_gemfile_tree(root, loader: version_split_loader)

      cleanup_paths = described_class.inactive_packaged_template_cleanup_files(root, min_ruby_4_config)
        .map { |cleanup| cleanup.fetch(:target_path) }

      expect(cleanup_paths).not_to include(
        "gemfiles/modular/x_std_libs/r3/libs.gemfile",
        "gemfiles/modular/x_std_libs/r3.1/libs.gemfile",
        "gemfiles/modular/x_std_libs/r2/libs.gemfile"
      )
      # Transitive closure: the kept r3 loader references these in turn.
      expect(cleanup_paths).not_to include(
        "gemfiles/modular/erb/r3/v5.0.gemfile",
        "gemfiles/modular/mutex_m/r3/v0.3.gemfile",
        "gemfiles/modular/erb/r3.1/v4.0.gemfile",
        "gemfiles/modular/erb/r2/v3.0.gemfile"
      )
    end
  end

  it "deletes variant gemfiles once the loader stops referencing them" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-x-stdlib-reference-drop", tmp_root) do |root|
      ruby4_only_loader = <<~RUBY
        ### Std Lib Extracted Gems
        eval_gemfile "x_std_libs/r4/libs.gemfile"
      RUBY
      write_member_gemfile_tree(root, loader: ruby4_only_loader)

      cleanup_paths = described_class.inactive_packaged_template_cleanup_files(root, min_ruby_4_config)
        .map { |cleanup| cleanup.fetch(:target_path) }

      expect(cleanup_paths).to include(
        "gemfiles/modular/x_std_libs/r3/libs.gemfile",
        "gemfiles/modular/x_std_libs/r3.1/libs.gemfile",
        "gemfiles/modular/x_std_libs/r2/libs.gemfile",
        "gemfiles/modular/erb/r3/v5.0.gemfile",
        "gemfiles/modular/mutex_m/r3/v0.3.gemfile",
        "gemfiles/modular/erb/r3.1/v4.0.gemfile",
        "gemfiles/modular/erb/r2/v3.0.gemfile"
      )
    end
  end

  it "emits no deletion recipe for loader-referenced variants in the full plan" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-x-stdlib-reference-plan", tmp_root) do |root|
      write_member_gemfile_tree(root, loader: version_split_loader)

      plan = described_class.plan_project(root, env: {})
      deletion_reports = plan.fetch(:recipe_reports).select do |report|
        report.fetch(:metadata, {}).fetch(:delete_file, false)
      end
      deleted_paths = deletion_reports.map { |report| report.fetch(:relative_path) }

      expect(deleted_paths).not_to include(
        "gemfiles/modular/x_std_libs/r3/libs.gemfile",
        "gemfiles/modular/x_std_libs/r3.1/libs.gemfile",
        "gemfiles/modular/x_std_libs/r2/libs.gemfile",
        "gemfiles/modular/erb/r3/v5.0.gemfile",
        "gemfiles/modular/mutex_m/r3/v0.3.gemfile",
        "gemfiles/modular/erb/r3.1/v4.0.gemfile",
        "gemfiles/modular/erb/r2/v3.0.gemfile"
      )
    end
  end
end
