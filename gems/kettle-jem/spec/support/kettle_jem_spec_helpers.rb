# frozen_string_literal: true

module KettleJemSpecHelpers
  def isolate_kettle_jem_env
    tmp_root = File.join(__dir__, "..", "tmp")
    previous_ceiling = ENV.fetch("GIT_CEILING_DIRECTORIES", nil)
    isolated_env_keys = ENV.keys.grep(/\AKJ_|KETTLE_JEM_|OPENCOLLECTIVE_HANDLE|FUNDING_ORG|K_JEM_TEMPLATING/)
    previous_env = isolated_env_keys.to_h { |key| [key, ENV[key]] }
    # rubocop:disable Env/Assign
    isolated_env_keys.each { |key| ENV.delete(key) }
    ENV["GIT_CEILING_DIRECTORIES"] = [previous_ceiling, tmp_root].compact.reject(&:empty?).join(File::PATH_SEPARATOR)
    # rubocop:enable Env/Assign
    Kettle::Jem::GemSpecReader.clear_cache!
    yield
  ensure
    Kettle::Jem::GemSpecReader.clear_cache!
    # rubocop:disable Env/Assign
    isolated_env_keys.to_a.each { |key| ENV.delete(key) }
    previous_env.to_h.each { |key, value| ENV[key] = value }
    if previous_ceiling.nil?
      ENV.delete("GIT_CEILING_DIRECTORIES")
    else
      ENV["GIT_CEILING_DIRECTORIES"] = previous_ceiling
    end
    # rubocop:enable Env/Assign
  end

  def json_ready(value)
    JSON.parse(JSON.generate(value), symbolize_names: true)
  end

  def kettle_jem_handoff_command(*args)
    [
      "bundle",
      "exec",
      "ruby",
      "-e",
      %(load Gem.bin_path("kettle-jem", "kettle-jem")),
      "--",
      *args
    ]
  end

  def write_tree(root, files)
    files.each do |relative_path, content|
      path = File.join(root, relative_path.to_s)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def project_files(root, paths)
    paths.to_h do |relative_path|
      path = File.join(root, relative_path)
      [relative_path.to_sym, File.exist?(path) ? File.read(path) : nil]
    end
  end

  def normalize_workflow_pins_for_spec(value)
    case value
    when Hash
      value.to_h { |key, item| [key, normalize_workflow_pins_for_spec(item)] }
    when String
      value.gsub(%r{([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?@)[a-f0-9]{40}(\s+#\s+v?[^\s]+)}, "\\1<sha> # <version>")
    else
      value
    end
  end

  def expect_pinned_action(content, action)
    expect(content).to match(%r{#{Regexp.escape(action)}@[a-f0-9]{40}\s+#\s+v?[^\s]+})
  end

  def prism_string_argument(call, index = 0)
    argument = call&.arguments&.arguments&.[](index)
    argument.unescaped if argument.is_a?(::Prism::StringNode)
  end

  def expect_gem_dependency_declared(content, gem_name)
    declared = Kettle::Jem.ruby_call_records(content, :gem).any? do |call|
      prism_string_argument(call) == gem_name
    end

    expect(declared).to be(true), "expected Gemfile dependency #{gem_name.inspect}"
  end

  def expect_gemspec_dependency_declared(content, gem_name, kind: nil)
    names = Array(kind || %i[add_dependency add_development_dependency])
    declared = Kettle::Jem.ruby_call_records(content, nil).any? do |call|
      names.include?(call.name) && prism_string_argument(call) == gem_name
    end

    expect(declared).to be(true), "expected gemspec dependency #{gem_name.inspect}"
  end

  def appraisals_eval_gemfile_paths(content, appraisal_name)
    result = ::Prism.parse(content.to_s)
    raise "invalid Appraisals fixture" unless result.success?

    calls = result.value.breadth_first_search_all { |node| node.is_a?(::Prism::CallNode) }
    appraise = calls.find { |call| call.name == :appraise && prism_string_argument(call) == appraisal_name }
    return [] unless appraise

    calls.filter_map do |call|
      next unless call.name == :eval_gemfile
      next unless call.location.start_line >= appraise.location.start_line
      next unless call.location.end_line <= appraise.location.end_line

      prism_string_argument(call)
    end
  end
end

RSpec.shared_context "with isolated kettle-jem environment" do
  around do |example|
    isolate_kettle_jem_env { example.run }
  end
end
