# frozen_string_literal: true

module Plain
  # StructuredMerge plain text fallback behavior.
  module Merge
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: 'plain-line', family: 'line')

    module Backend
      # TreeHaver language wrapper for plain text parsed into normalized line
      # and paragraph/block ownership data.
      class Language < TreeHaver::Base::Language
        def initialize(name = :text)
          super(name, backend: :line, options: {})
        end

        def self.text
          new(:text)
        end

        def self.plain
          new(:plain)
        end
      end

      # Parser adapter that exposes plain text analysis through TreeHaver's
      # normalized backend registry.
      class Parser < TreeHaver::Base::Parser
        def parse(source)
          raise 'Language not set' unless language

          Plain::Merge.analyze_text(source)
        end

        def parse_string(_old_tree, source)
          parse(source)
        end
      end
    end

    def self.register_backend!
      TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)
      %i[text plain].each do |language_name|
        register_language!(language_name)
      end
      nil
    end

    def self.register_language!(language_name)
      TreeHaver.register_language(
        language_name,
        backend_module: Backend,
        backend_type: :line,
        gem_name: 'plain-merge',
        contract: :line
      )
    end
  end
end
