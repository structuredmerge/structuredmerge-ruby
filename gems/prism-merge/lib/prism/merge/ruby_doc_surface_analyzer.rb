# frozen_string_literal: true

module Prism
  module Merge
    # Discovers doc-comment and @example child surfaces while leaving raw span
    # ownership and reconstruction anchored to Prism-owned source lines.
    class RubyDocSurfaceAnalyzer
      DEFAULT_DOC_LANGUAGE = :yard
      DEFAULT_EXAMPLE_LANGUAGE = :ruby

      attr_reader :analysis

      def initialize(analysis, doc_language: DEFAULT_DOC_LANGUAGE, default_example_language: DEFAULT_EXAMPLE_LANGUAGE)
        @analysis = analysis
        @doc_language = normalize_language(doc_language).to_sym
        @default_example_language = normalize_language(default_example_language).to_sym
      end

      def discover_doc_comment_surfaces(owners: analysis.statements)
        Array(owners).filter_map do |owner|
          attachment = analysis.comment_attachment_for(owner)
          region = attachment.leading_region
          next unless doc_comment_region?(region)

          build_doc_comment_surface(owner, region)
        end
      end

      def discover_surfaces(owners: analysis.statements)
        discovered = []
        queue = discover_doc_comment_surfaces(owners: owners)

        until queue.empty?
          surface = queue.shift
          discovered << surface
          queue.concat(discover_child_surfaces(surface))
        end

        discovered
      end

      def discover_child_surfaces(surface)
        return [] unless surface.surface_kind == :ruby_doc_comment

        discover_example_surfaces(surface)
      end

      private

      def build_doc_comment_surface(owner, region)
        owner_signature = analysis.generate_signature(owner)
        owner_reference = owner_reference_for(owner, owner_signature)
        doc_entries = Array(region.metadata[:entries]).select { |entry| doc_comment_content?(entry) }
        span = if doc_entries.empty?
                 region.start_line..region.end_line
               else
                 doc_entries.first[:line]..doc_entries.last[:line]
               end
        owned_entries = doc_comment_entries(region, span)
        owned_line_numbers = owned_entries.map { |entry| entry[:line] }
        owned_entry_indexes = owned_entries.map { |entry| entry[:entry_index] }

        Ast::Merge::Runtime::Surface.new(
          surface_kind: :ruby_doc_comment,
          effective_language: @doc_language,
          address: "document[0] > ruby_doc_comment[#{owner_reference}]",
          parent_address: 'document[0]',
          span: span,
          reconstruction_strategy: :rewrite_with_prefix_preservation,
          metadata: {
            owner_signature: owner_signature,
            owner_type: normalized_owner_type(owner),
            owner_span: owner_span_for(owner),
            comment_prefix: comment_prefix_for(span.begin),
            line_numbers: owned_line_numbers,
            owned_entry_indexes: owned_entry_indexes,
            line_span: span
          }
        )
      end

      def discover_example_surfaces(surface)
        doc_entries = comment_entries_for(surface)
        return [] if doc_entries.empty?

        Ruby::Merge::DocCommentSupport.example_blocks(doc_entries).map do |block|
          build_example_surface(surface, block)
        end
      end

      def build_example_surface(surface, block)
        body_entries = block.fetch(:body_entries)
        declared_language = normalize_language(block[:declared_language])&.to_sym
        tag_index = block.fetch(:tag_index)
        body_span = body_entries.first[:line]..body_entries.last[:line]

        Ast::Merge::Runtime::Surface.new(
          surface_kind: :yard_example_block,
          declared_language: declared_language,
          effective_language: declared_language || @default_example_language,
          address: "#{surface.address} > yard_example[#{tag_index}]",
          parent_address: surface.address,
          span: body_span,
          reconstruction_strategy: :rewrite_with_prefix_preservation,
          metadata: {
            tag_kind: :example,
            tag_index: tag_index,
            tag_relative_line: tag_index + 1,
            tag_line: block.fetch(:tag_line),
            tag_text: block.fetch(:tag_text),
            body_relative_span: (block.fetch(:body_start_index) + 1)..block.fetch(:body_end_index),
            comment_prefix: surface.metadata[:comment_prefix],
            preserved_boundaries: {
              tag_header: comment_entries_for(surface)[tag_index][:raw]
            }
          }
        )
      end

      def comment_entries_for(surface)
        entries = surface.metadata[:entries] || []
        return entries unless entries.empty?

        line_numbers = surface.metadata[:line_numbers] || surface.span&.to_a || []
        line_numbers.map do |line_number|
          raw = analysis.line_at(line_number).to_s.sub(/\r?\n\z/, '')
          { line: line_number, raw: raw }
        end
      end

      def doc_comment_entries(region, span)
        entries = Array(region.metadata[:entries])
        return span.to_a.map.with_index { |line, index| { line: line, entry_index: index } } if entries.empty?

        entries
          .each_with_index
          .map { |entry, index| entry.merge(entry_index: index) }
          .select { |entry| span.cover?(entry[:line]) }
          .reject do |entry|
            content = normalize_comment_content(entry[:raw])
            directive_line?(content) || magic_comment_line?(entry, content)
          end
      end

      def doc_comment_region?(region)
        return false unless region && !region.empty?

        entries = Array(region.metadata[:entries])
        return false if entries.empty?

        entries.any? { |entry| doc_comment_content?(entry) }
      end

      def doc_comment_content?(entry)
        content = normalize_comment_content(entry[:raw])
        Ruby::Merge::DocCommentSupport.doc_comment_content?(
          entry[:raw],
          magic_comment: magic_comment_line?(entry, content)
        )
      end

      def directive_line?(content)
        Ruby::Merge::BlockDirectiveDetector.directive_content?(content)
      end

      def magic_comment_line?(entry, content)
        node = entry[:node]
        return true if node.respond_to?(:magic_comment_type) && !node.magic_comment_type.nil?

        Ruby::Merge::DocCommentSupport.magic_comment_content?(content)
      end

      def normalize_comment_content(raw)
        Ruby::Merge::DocCommentSupport.normalize_comment_content(raw)
      end

      def owner_reference_for(owner, owner_signature)
        if owner.respond_to?(:name) && !owner.name.nil?
          owner.name.to_s
        elsif owner_signature && !owner_signature.empty?
          owner_signature.join(':')
        else
          "#{normalized_owner_type(owner)}@#{owner_span_for(owner)}"
        end
      end

      def normalized_owner_type(owner)
        owner.class.name.split('::').last.gsub(/Node\z/, '').downcase.to_sym
      end

      def owner_span_for(owner)
        "#{owner.location.start_line}-#{owner.location.end_line}"
      end

      def comment_prefix_for(line_number)
        line_text = analysis.line_at(line_number).to_s.sub(/\r?\n\z/, '')
        line_text[/\A\s*#\s?/] || '# '
      end

      def normalize_language(language)
        Ruby::Merge::DocCommentSupport.normalize_language(language)
      end
    end
  end
end
