# frozen_string_literal: true

module Kramdown
  # Source-preserving Markdown provider integration for Kramdown.
  module Merge
    # Native Kramdown backend configuration for the shared provider engine.
    class Provider < Markdown::Merge::SourcePreservingProvider
      # rubocop:disable Metrics/MethodLength -- constructor declares the complete backend boundary
      def initialize
        super(
          provider_id: 'ruby.markdown.kramdown',
          role: :backend,
          backend: Markdown::Merge::ProviderBackend.new(
            id: :kramdown,
            package: PACKAGE_NAME,
            dialects: %i[markdown kramdown],
            parser: lambda { |source|
              parser = Backend::Parser.new
              parser.language = Backend::Language.markdown
              parser.parse(source)
            },
            headings: lambda { |root, source|
              Markdown::Merge::ProviderBackend.native_headings(root, source, kramdown: true)
            }
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
