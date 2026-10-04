# frozen_string_literal: true

module TreeHaver
  module Backends
    # TSLP backend using tree_sitter_language_pack's on-demand parser API.
    #
    # This backend intentionally requires the real parser API. The language-pack
    # process API is not a TreeHaver parser backend and must not be used as a
    # merge-gem integration surface.
    module Tslp
      # Transient grammar hot-load failures (for example a failed on-demand
      # download of the tree-sitter-language-pack bundle) are retried on later
      # availability probes instead of latching for the whole process. After
      # this many consecutive transient failures the backend latches as
      # unavailable so a dead network cannot slow every later parse attempt.
      TRANSIENT_FAILURE_RETRY_LIMIT = 3

      @loaded = false
      @permanently_unavailable = false
      @transient_failures = 0
      @unavailable_reason = nil
      @language_availability = {}
      @language_unavailable_reasons = {}
      @language_attempts = {}
      PARSER_SMOKE_SOURCES = {
        'json' => '{}',
        'json5' => '{}',
        'bash' => "echo tree_haver\n",
        'go' => "package main\nfunc main() {}\n",
        'html' => "<!doctype html>\n<title>TreeHaver</title>\n",
        'markdown' => "# TreeHaver\n",
        'ruby' => "class TreeHaverSmoke\nend\n",
        'rust' => "fn main() {}\n",
        'typescript' => "export const treeHaver = true;\n",
        'toml' => "title = \"tree_haver\"\n",
        'yaml' => "tree_haver: true\n"
      }.freeze
      DEFAULT_PARSER_SMOKE_SOURCE = ''

      # Grammar hot-load failures caused by the on-demand bundle download
      # (network flake, transient GitHub release fetch failure, cache lock
      # contention) must not latch the backend for the whole process.
      TRANSIENT_FAILURE_PATTERN = /
        Download\ error
        | Download\ cache\ lock\ error
        | Failed\ to\ fetch\ manifest
        | Failed\ to\ download
        | Failed\ to\ read\ (cached|download)
        | connection\ (refused|reset)
        | timed?\ out
        | timeout
        | temporarily
      /xi.freeze

      class << self
        attr_reader :unavailable_reason

        def available?
          return true if @loaded
          return false if @permanently_unavailable

          @loaded = probe_availability
          return true if @loaded

          if transient_reason?(@unavailable_reason) && @transient_failures < TRANSIENT_FAILURE_RETRY_LIMIT
            # Leave the backend probeable so a later availability check retries
            # the on-demand grammar download instead of failing every parse for
            # the rest of the process.
            @transient_failures += 1
            return false
          end

          @permanently_unavailable = true
          false
        end

        # Reason the last per-language probe failed, when known.
        def language_unavailable_reason(language_name)
          @language_unavailable_reasons[language_name.to_s]
        end

        # Pre-download and pre-load grammars through the language pack's
        # hot-load API before any parse/smoke probing happens. This turns the
        # on-demand download (which otherwise fires inside the first
        # availability probe and can transiently fail) into an explicit,
        # attributable warm-up step.
        #
        # @param languages [Array<String, Symbol>] grammar names to prefetch
        # @return [Hash] {attempted:, prefetched:, failures: {name => reason}}
        def prefetch(languages)
          names = languages.map(&:to_s).uniq
          begin
            require 'tree_sitter_language_pack' unless defined?(::TreeSitterLanguagePack)
          rescue LoadError => e
            return prefetch_skip_report('tree_sitter_language_pack is not installed', e.message, names)
          end

          unless ::TreeSitterLanguagePack.respond_to?(:prefetch)
            return prefetch_skip_report('tree_sitter_language_pack does not expose prefetch', nil, names)
          end

          failures = {}
          prefetched = names.select do |name|
            ::TreeSitterLanguagePack.prefetch([name])
            true
          rescue StandardError => e
            failures[name] = e.message
            false
          end
          {attempted: true, prefetched: prefetched, failures: failures}
        end

        def transient_reason?(reason)
          !reason.to_s.empty? && TRANSIENT_FAILURE_PATTERN.match?(reason.to_s)
        end

        def reset!
          @loaded = false
          @permanently_unavailable = false
          @transient_failures = 0
          @unavailable_reason = nil
          @language_availability = {}
          @language_unavailable_reasons = {}
          @language_attempts = {}
        end

        def capabilities
          return {} unless available?

          {
            backend: :tslp,
            query: false,
            bytes_field: true,
            incremental: false,
            comment_support: :nodes_only,
            language_pack: true
          }
        end

        def parser_available_for?(language_name)
          return false unless available?

          name = language_name.to_s
          return @language_availability.fetch(name) if @language_availability.key?(name)

          available = smoke_parse_language(name)
          if available
            @language_availability[name] = true
            @language_unavailable_reasons.delete(name)
            return true
          end

          reason = @language_unavailable_reasons[name] = @unavailable_reason
          attempts = (@language_attempts[name] = @language_attempts.fetch(name, 0) + 1)
          if transient_reason?(reason) && attempts < TRANSIENT_FAILURE_RETRY_LIMIT
            # Do not memoize: a later probe retries the on-demand hot load.
            return false
          end

          @language_availability[name] = false
          false
        rescue StandardError => e
          name = language_name.to_s
          @unavailable_reason = e.message
          @language_unavailable_reasons[name] = e.message
          attempts = (@language_attempts[name] = @language_attempts.fetch(name, 0) + 1)
          # Memoize only after exhausting the transient retry budget; raising
          # here is how the on-demand grammar download reports failures.
          @language_availability[name] = false if attempts >= TRANSIENT_FAILURE_RETRY_LIMIT
          false
        end

        private

        def prefetch_skip_report(reason, detail, names)
          @unavailable_reason = detail if detail
          {
            attempted: false,
            reason: reason,
            prefetched: [],
            failures: names.to_h { |name| [name, reason] }
          }
        end

        def probe_availability
          require 'tree_sitter_language_pack' unless defined?(::TreeSitterLanguagePack)
          loaded = parser_api_available?
          if !loaded && @unavailable_reason.to_s.empty?
            @unavailable_reason = 'tree_sitter_language_pack parser API is not exposed'
          end
          loaded
        rescue LoadError => e
          # A missing gem is permanent for the process lifetime.
          @unavailable_reason = e.message
          @permanently_unavailable = true
          false
        rescue StandardError => e
          @unavailable_reason = e.message
          false
        end

        def parser_api_available?
          return false unless ::TreeSitterLanguagePack.respond_to?(:get_parser)
          return false unless defined?(::TreeSitterLanguagePack::Parser)
          return false unless ::TreeSitterLanguagePack::Parser.instance_methods.include?(:parse)

          parser_api_smoke_test
        rescue StandardError => e
          @unavailable_reason = e.message
          false
        end

        def parser_api_smoke_test
          language_name, source = PARSER_SMOKE_SOURCES.find do |name, _smoke_source|
            !::TreeSitterLanguagePack.respond_to?(:has_language) ||
              ::TreeSitterLanguagePack.has_language(name)
          end
          return false unless language_name

          smoke_parse_language(language_name, source: source)
        end

        def smoke_parse_language(language_name, source: smoke_source_for(language_name))
          name = language_name.to_s
          if ::TreeSitterLanguagePack.respond_to?(:has_language) &&
             !::TreeSitterLanguagePack.has_language(name)
            @unavailable_reason = "tree_sitter_language_pack does not publish #{name}"
            return false
          end

          parser = ::TreeSitterLanguagePack.get_parser(name)
          return false unless parser

          tree = parser.parse(source)
          return false unless tree.respond_to?(:root_node)

          root = tree.root_node
          root && !node_has_error?(root)
        end

        def smoke_source_for(language_name)
          PARSER_SMOKE_SOURCES.fetch(language_name.to_s, DEFAULT_PARSER_SMOKE_SOURCE)
        end

        def node_has_error?(node)
          if node.respond_to?(:has_error)
            node.has_error
          elsif node.respond_to?(:has_error?)
            node.has_error?
          else
            false
          end
        end
      end

      class Language < TreeHaver::Base::Language
        def initialize(name)
          super(name.to_sym, backend: :tslp, options: {})
        end

        class << self
          def from_library(_path = nil, symbol: nil, name: nil) # rubocop:disable Lint/UnusedMethodArgument
            new(name || :unknown)
          end
        end
      end

      class Parser < TreeHaver::Base::Parser
        def parse(source)
          raise TreeHaver::NotAvailable, unavailable_message unless Tslp.available?
          raise TreeHaver::NotAvailable, 'TSLP language is not set' unless language

          parser = ::TreeSitterLanguagePack.get_parser(language.name.to_s)
          raise TreeHaver::NotAvailable, "TSLP did not return a parser for #{language.name}" unless parser

          normalized_source = normalize_source_encoding(source)
          raw_tree = parser.parse(normalized_source)
          raise TreeHaver::NotAvailable, "TSLP did not return a parse tree for #{language.name}" unless raw_tree

          Tree.new(raw_tree, source: normalized_source, language: language.name)
        end

        private

        def normalize_source_encoding(source)
          return source unless source.encoding == Encoding::BINARY

          utf8 = source.dup.force_encoding(Encoding::UTF_8)
          utf8.valid_encoding? ? utf8 : source
        end

        def unavailable_message
          reason = Tslp.unavailable_reason
          detail = reason.to_s.empty? ? 'unknown reason' : reason
          "tree_sitter_language_pack parser API is unavailable: #{detail}"
        end
      end

      class Tree < TreeHaver::Base::Tree
        attr_reader :language

        def initialize(inner_tree = nil, source: nil, lines: nil, language: nil)
          super(inner_tree, source: source, lines: lines)
          @language = language.to_s
        end

        def root_node
          Node.new(inner_tree.root_node, source: source, lines: lines, language: language)
        end
      end

      class Node < TreeHaver::Base::Node
        NODE_TYPE_ALIASES = {
          'json5' => {
            'file' => 'document',
            'member' => 'pair'
          }
        }.freeze

        attr_reader :language

        def initialize(node, source: nil, lines: nil, language: nil)
          super(node, source: source, lines: lines)
          @language = language.to_s
        end

        def type
          NODE_TYPE_ALIASES.fetch(language, {}).fetch(native_type, native_type)
        end

        def native_type
          inner_node.kind
        end

        def start_byte
          inner_node.start_byte
        end

        def end_byte
          inner_node.end_byte
        end

        def start_point
          point = inner_node.start_position
          { row: point.row, column: point.column }
        end

        def end_point
          point = inner_node.end_position
          { row: point.row, column: point.column }
        end

        def children
          Array.new(inner_node.child_count) do |index|
            child = inner_node.child(index)
            child && self.class.new(child, source: source, lines: lines, language: language)
          end.compact
        end

        def child_by_field_name(name)
          child = inner_node.child_by_field_name(name.to_s) if inner_node.respond_to?(:child_by_field_name)
          child && self.class.new(child, source: source, lines: lines, language: language)
        end

        def parent
          parent = inner_node.parent if inner_node.respond_to?(:parent)
          parent && self.class.new(parent, source: source, lines: lines, language: language)
        end

        def named?
          inner_node.is_named
        end

        def has_error?
          inner_node.has_error
        end

        def error?
          inner_node.is_error
        end

        def missing?
          inner_node.is_missing
        end

        def extra?
          inner_node.is_extra
        end
      end
    end
  end
end
