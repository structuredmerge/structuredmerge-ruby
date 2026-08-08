# frozen_string_literal: true

require 'open3'
require 'yaml'

module StructuredMerge
  module FixtureRepository
    module_function

    ROOT = Pathname(__dir__).join('..', '..').expand_path
    LOCK_PATH = ROOT.join('.structuredmerge', 'fixtures.lock')
    CHECKOUT_PATH = ROOT.join('..', 'fixtures')

    def lock
      @lock ||= YAML.load_file(LOCK_PATH.to_s)
    end

    def version
      lock.fetch('version')
    end

    def tag
      lock.fetch('tag')
    end

    def revision
      lock.fetch('revision')
    end

    def repository
      lock.fetch('repository')
    end

    def checkout_revision
      git_output('rev-parse', 'HEAD')
    end

    def tag_revision
      git_output('rev-parse', "refs/tags/#{tag}^{commit}")
    end

    def report
      "StructuredMerge fixtures: version=#{version} tag=#{tag} revision=#{revision} checkout=#{checkout_revision}"
    end

    def git_output(*args, strip: true)
      command_output, error_output, status = Open3.capture3('git', '-C', CHECKOUT_PATH.to_s, *args)
      return strip ? command_output.strip : command_output if status.success?

      raise "fixture repository git command failed: #{error_output.strip}"
    end
  end
end
