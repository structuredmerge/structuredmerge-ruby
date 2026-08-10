# frozen_string_literal: true

module Commonmarker
  # Source-preserving Markdown provider integration for Commonmarker.
  module Merge
    # Native Commonmarker backend configuration for the shared provider engine.
    class Provider < Markdown::Merge::SourcePreservingProvider
      # rubocop:disable Metrics/MethodLength -- constructor declares the complete backend boundary
      def initialize
        super(
          provider_id: 'ruby.markdown.commonmarker',
          role: :backend,
          backend: Markdown::Merge::ProviderBackend.new(
            id: :commonmarker,
            package: PACKAGE_NAME,
            dialects: %i[markdown commonmark],
            parser: lambda { |source|
              parser = Backend::Parser.new
              parser.language = Backend::Language.markdown
              parser.parse(source)
            },
            headings: Markdown::Merge::ProviderBackend.method(:native_headings)
          )
        )
      end
      # rubocop:enable Metrics/MethodLength
    end

    class << self
      def merge_provider
        @merge_provider ||= Provider.new
      end

      def register_provider!(replace: false)
        return unless Ast::Merge.respond_to?(:register_provider)

        Ast::Merge.register_provider(merge_provider, replace: replace)
      end
    end
  end
end
