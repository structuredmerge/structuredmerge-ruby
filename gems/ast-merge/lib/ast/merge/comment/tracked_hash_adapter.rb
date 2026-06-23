# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Converts producer-specific tracked comment hashes into standardized
      # Ast::Merge::Comment nodes and regions.
      #
      # This adapter is intentionally conservative. It currently targets the
      # line-comment hash shape used by source trackers such as psych-merge's
      # CommentTracker:
      #
      #   {
      #     line: 12,
      #     indent: 2,
      #     text: "Example comment",
      #     full_line: true,
      #     raw: "  # Example comment"
      #   }
      #
      # The adapter does not infer ownership by itself. Callers provide region
      # kinds explicitly and can preserve original producer facts via metadata.
      class TrackedHashAdapter
        class << self
          # Convert a tracked comment hash into a normalized shared comment node.
          #
          # @param comment_hash [Hash, nil] tracked hash in adapter shape
          # @param style [Comment::Style, Symbol, nil] comment style descriptor
          # @param options [Hash] fallback hash values when +comment_hash+ is nil
          # @return [Comment::Line]
          def node(comment_hash = nil, style: nil, **options)
            hash = normalize_hash(comment_hash || options)
            style = resolve_style(style)
            validate_style!(style)
            validate_hash!(hash)

            Comment::Line.new(
              text: line_text_from(hash, style),
              line_number: hash.fetch(:line),
              style: style
            )
          end

          # Convert tracked comment hashes into a normalized shared comment region.
          #
          # @param kind [Symbol] normalized region kind
          # @param comments [Array<Hash>] tracked comment hashes
          # @param style [Comment::Style, Symbol, nil] comment style descriptor
          # @param metadata [Hash] base metadata for the region
          # @param options [Hash] additional metadata merged into +metadata+
          # @return [Region]
          def region(kind:, comments:, style: nil, metadata: {}, **options)
            normalized = Array(comments).map { |comment_hash| normalize_hash(comment_hash) }
            nodes = normalized.map { |comment_hash| node(comment_hash, style: style) }

            Region.new(
              kind: kind,
              nodes: nodes,
              metadata: metadata.merge(
                source: :tracked_hash,
                tracked_hashes: normalized
              ).merge(options)
            )
          end

          private

          def normalize_hash(comment_hash)
            raise ArgumentError, 'comment_hash must be a Hash' unless comment_hash.is_a?(Hash)

            comment_hash.each_with_object({}) do |(key, value), result|
              result[key.to_sym] = value
            end
          end

          def resolve_style(style)
            case style
            when nil
              Style.for(:hash_comment)
            when Style
              style
            else
              Style.for(style)
            end
          end

          def validate_style!(style)
            return if style.supports_line_comments?

            raise ArgumentError, 'TrackedHashAdapter only supports line-comment styles'
          end

          def validate_hash!(hash)
            raise ArgumentError, 'comment hash must include :line' unless hash.key?(:line)
            raise ArgumentError, 'comment hash must include :text or :raw' unless hash.key?(:text) || hash.key?(:raw)
            raise ArgumentError, 'block comment hashes are not yet supported' if hash[:block]
          end

          def line_text_from(hash, style)
            raw = hash[:raw].to_s
            unless raw.empty?
              return extracted_inline_slice(hash, raw, style) if inline_raw?(hash, raw, style)

              return raw
            end

            indent = hash.fetch(:indent, 0).to_i
            text = hash[:text].to_s
            line = +(' ' * indent)
            line << style.line_start.to_s
            line << ' ' unless text.empty?
            line << text
            line << " #{style.line_end}" if style.line_end
            line
          end

          def inline_raw?(hash, raw, style)
            return false if hash[:full_line]
            return false if style.line_start.nil?

            stripped = raw.lstrip
            !stripped.start_with?(style.line_start)
          end

          def extracted_inline_slice(hash, raw, style)
            indent = hash.fetch(:indent, 0).to_i
            comment_index = raw.rindex(style.line_start.to_s)
            return raw unless comment_index

            inline_slice = raw[comment_index..]
            return raw unless inline_slice.start_with?(style.line_start.to_s)

            (' ' * indent) + inline_slice
          end
        end
      end
    end
  end
end
