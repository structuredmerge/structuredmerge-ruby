# frozen_string_literal: true

module Dotenv
  # StructuredMerge dotenv assignment and comment merge behavior.
  module Merge
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: 'dotenv-line', family: 'line')

    module Backend
      # TreeHaver language wrapper for dotenv files parsed through the line
      # substrate supplied by plain-merge.
      class Language < TreeHaver::Base::Language
        def initialize(name = :dotenv)
          super(name, backend: :line, options: {})
        end

        def self.dotenv
          new(:dotenv)
        end

        def self.env
          new(:env)
        end
      end

      # Parser adapter that exposes Dotenv::Merge::FileAnalysis via
      # TreeHaver.parser_for(:dotenv, backend_type: :line).
      class Parser < TreeHaver::Base::Parser
        def parse(source)
          raise 'Language not set' unless language

          attach_line_analysis(Dotenv::Merge::FileAnalysis.new(source), source)
        end

        def parse_string(_old_tree, source)
          parse(source)
        end

        private

        def attach_line_analysis(analysis, source)
          analysis.instance_variable_set(:@line_analysis, plain_line_analysis(source))
          analysis.define_singleton_method(:line_analysis) { @line_analysis }
          analysis
        end

        def plain_line_analysis(source)
          Plain::Merge.analyze_text(source)
        end
      end
    end

    def self.register_backend!
      TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)
      %i[dotenv env].each do |language_name|
        register_language!(language_name)
      end
      nil
    end

    def self.register_language!(language_name)
      TreeHaver.register_language(
        language_name,
        backend_module: Backend,
        backend_type: :line,
        gem_name: 'dotenv-merge',
        contract: :line
      )
    end
  end
end
