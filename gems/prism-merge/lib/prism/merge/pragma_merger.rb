# frozen_string_literal: true

module Prism
  module Merge
    # Merges file-level pragmas as a discrete document.
    #
    # == Why a dedicated resolver
    #
    # A magic comment is syntactically a comment but semantically a file-level
    # directive, and the two axes of a merge resolve differently for it:
    #
    #   KEPT     - preference resolved, exactly like any other content. Either
    #              side may add or remove a pragma, governed by the same
    #              `preference`, `add_template_only_nodes` and
    #              `remove_template_missing_nodes` settings that govern code.
    #   POSITION - never follows merge placement rules. Ruby only honours a magic
    #              comment that appears in the leading comment region, before the
    #              first statement; one emitted after code is inert. So a pragma
    #              must always be pinned to the top.
    #
    # Modelling a pragma as an ordinary comment attached to a statement satisfies
    # neither axis: it inherits the host statement's placement (so it can be
    # stranded below code, silently disabling e.g. frozen string literals), and it
    # bypasses the add/remove flags (which operate on statements), so retention
    # follows `preference` alone.
    #
    # Treating the pragma region as its own document resolves both at once:
    # retention is computed here by the same rule code uses, and the rendered block
    # is pinned above the first statement, so it cannot be misplaced.
    #
    # == Scope
    #
    # Only file-level pragmas are handled here. Prism classifies ANY leading
    # `# key: value` as a magic comment, which includes block directives such as
    # `# kettle-jem:freeze` and `# simplecov:disable`. Those are positionally
    # meaningful and legitimately appear mid-file, so they are excluded by key and
    # remain the main resolver's concern.
    #
    # Identity and position come from Prism natively (ParseResult#magic_comments
    # with key, value and value_loc), so no text pattern matching is involved.
    #
    # == What this REPLACES
    #
    # Magic-comment handling elsewhere in this gem is legacy and is classification
    # only. It must not grow pragma retention or placement logic. Each such site
    # carries a "NOT THE PRAGMA RESOLVER" / "CLASSIFICATION ONLY" marker pointing
    # back here:
    #
    #   magic_comment_support.rb       regex/line-based header classification
    #   comment/line.rb                magic_comment_type attribute (feeds signatures)
    #   comment/block.rb               signature making a pragma matchable as a node
    #   comment/parser.rb              header tagging during parse
    #   file_analysis.rb               native_header_magic_comment_types
    #   comment_only_file_merger.rb    within-one-side header dedup only
    #   node_emission_support.rb       leading-comment prefix emission
    #   wrapper_comment_support.rb     leading-comment emission
    #   recursive_node_body_merger.rb  prefix comment filtering
    #   ruby_doc_surface_analyzer.rb   doc-vs-directive split
    #   merge.rb                       prism_comment_directive classification
    #
    # Removing them is deliberately deferred: Comment::Line#magic_comment_type feeds
    # node signatures, so deleting it changes match identity well beyond pragmas.
    # That needs its own pass with the full monorepo suite as guard.
    #
    # @example
    #   merger = PragmaMerger.new(
    #     template_source: template,
    #     destination_source: destination,
    #     preference: :destination,
    #     add_template_only_nodes: true,
    #     remove_template_missing_nodes: false
    #   )
    #   merger.resolved_entries  # => [#<Entry key="frozen_string_literal" value="true" line=1>]
    #   merger.render            # => "# frozen_string_literal: true\n"
    #   merger.place_in(body)    # => pragma block pinned above the first statement
    #
    # @example Removing pragmas the node resolver emitted
    #   PragmaMerger.strip_pragma_lines("# frozen_string_literal: true\nx = 1\n")
    #   # => "x = 1\n"
    # rubocop:disable Metrics/ClassLength -- the retention rule, the rendering of the
    # pragma block, its header placement, and the AST-derived line scan form one
    # boundary: splitting them across classes would separate the two merge axes
    # (KEPT and POSITION) that must stay resolved together.
    class PragmaMerger
      # File-level pragmas, as opposed to block directives. Filtering happens on
      # the AST-derived key (Set membership), never by matching comment text.
      PRAGMA_KEYS = %w[
        frozen_string_literal
        encoding
        coding
        warn_indent
        shareable_constant_value
      ].to_set.freeze

      # A single pragma occurrence.
      #
      # @!attribute key
      #   @return [String] pragma name, e.g. "frozen_string_literal"
      # @!attribute value
      #   @return [String] pragma value, e.g. "true"
      # @!attribute line
      #   @return [Integer] 1-based source line the pragma occupies
      Entry = Struct.new(:key, :value, :line, keyword_init: true) do
        # Renders the pragma in canonical `# key: value` form.
        #
        # @return [String]
        def to_line
          "# #{key}: #{value}"
        end
      end

      # @param template_source [String]
      # @param destination_source [String]
      # @param preference [Symbol] :destination or :template
      # @param add_template_only_nodes [Boolean]
      # @param remove_template_missing_nodes [Boolean]
      def initialize(template_source:, destination_source:, preference: :destination,
                     add_template_only_nodes: false, remove_template_missing_nodes: false)
        @template_source = template_source.to_s
        @destination_source = destination_source.to_s
        @preference = preference.to_sym
        @add_template_only_nodes = add_template_only_nodes
        @remove_template_missing_nodes = remove_template_missing_nodes
      end

      attr_reader :preference

      # Pragma entries declared by the template, in source order.
      #
      # @return [Array<Entry>]
      def template_entries
        @template_entries ||= entries_for(@template_source)
      end

      # Pragma entries declared by the destination, in source order.
      #
      # @return [Array<Entry>]
      def destination_entries
        @destination_entries ||= entries_for(@destination_source)
      end

      # The pragmas to keep, in render order.
      #
      # Retention mirrors how ordinary nodes resolve:
      #   declared by both      -> kept, value resolved by preference
      #   template only         -> kept iff preference is :template, or
      #                            add_template_only_nodes is set
      #   destination only      -> kept iff remove_template_missing_nodes is unset
      #
      # Order is deterministic: template order first, then any destination-only
      # pragma in destination order. The template is the authority on header
      # structure; ordering is not itself preference resolved because neither side
      # expresses an ordering preference for a region it may not declare at all.
      #
      # @return [Array<Entry>]
      def resolved_entries
        @resolved_entries ||= compute_resolved_entries
      end

      # True when at least one pragma survives the merge.
      #
      # @return [Boolean]
      def any?
        resolved_entries.any?
      end

      # Renders the merged pragma block, one pragma per line, no trailing newline
      # separation logic (callers place it in the header region).
      #
      # @return [String] empty when no pragma is kept
      def render
        return '' if resolved_entries.empty?

        resolved_entries.map { |entry| "#{entry.to_line}\n" }.join
      end

      # Places the merged pragma block into +content+, honouring the two
      # positional constraints Ruby imposes:
      #
      #   * a shebang must remain the very first line, so pragmas go below it
      #   * pragmas must precede the first statement, so they go above all code
      #
      # A blank line separates the block from whatever follows, matching normal
      # file layout. Returns +content+ unchanged when no pragma is kept.
      #
      # @param content [String] merged body with pragma lines already removed
      # @return [String]
      def place_in(content)
        block = render
        return content.to_s if block.empty?

        text = content.to_s
        lines = text.lines
        shebang = lines.first.to_s.start_with?('#!') ? lines.shift : nil
        prefix = [shebang, block].compact
        rest = drop_leading_blank_lines(lines)
        [*prefix, "\n", *rest].join
      end

      # Removes pragma lines from +source+, leaving every other line untouched.
      #
      # A line is only removed when the pragma is the whole line. A pragma sharing
      # a line with code is left alone rather than risk corrupting the statement,
      # which cannot happen for a recognised magic comment in any case.
      #
      # @param source [String]
      # @return [String]
      def self.strip_pragma_lines(source)
        text = source.to_s
        return text if text.empty?

        lines_to_drop = pragma_line_numbers(text)
        return text if lines_to_drop.empty?

        text.lines.each_with_index.reject { |_, index| lines_to_drop.include?(index + 1) }.map(&:first).join
      end

      # Line numbers (1-based) occupied by a file-level pragma in +source+.
      #
      # @param source [String]
      # @return [Set<Integer>]
      def self.pragma_line_numbers(source)
        parse = Prism.parse(source.to_s)
        lines = source.to_s.lines
        pragma_magic_comments(parse)
          .filter_map { |magic_comment| pragma_line(magic_comment, lines) }
          .to_set
      end

      # Prism's own magic comments, narrowed to the file-level pragma keys.
      def self.pragma_magic_comments(parse)
        parse.magic_comments.select { |magic_comment| PRAGMA_KEYS.include?(magic_comment.key.to_s) }
      end

      # The 1-based line a pragma occupies, or nil when the pragma shares its line
      # with code. Only wholly-comment lines are reported, so stripping one cannot
      # take code with it.
      def self.pragma_line(magic_comment, lines)
        line = magic_comment.value_loc.start_line
        comment_only_line?(lines[line - 1]) ? line : nil
      end

      def self.comment_only_line?(line)
        line.to_s.strip.start_with?('#')
      end

      private

      def compute_resolved_entries
        by_key = merge_entry_values
        apply_template_retention(by_key)
        order_entries(by_key)
      end

      # Indexes every pragma by key, resolving the value where both sides declare
      # one. A destination-only pragma is recorded exactly when destination-only
      # nodes would be kept.
      def merge_entry_values
        by_key = {}
        template_entries.each { |entry| by_key[entry.key] ||= entry }
        destination_entries.each do |entry|
          merged = merged_entry(by_key[entry.key], entry)
          by_key[entry.key] = merged unless merged.nil?
        end
        by_key
      end

      # Resolves one key present on the template side (+existing+) against the
      # destination side (+entry+). Returns nil when the pragma should not be
      # recorded at all.
      def merged_entry(existing, entry)
        return merged_conflicting_entry(existing, entry) if existing

        keep_destination_only? ? entry : nil
      end

      # Both sides declare the pragma, so it is always kept and only its value is
      # preference resolved. The template's line anchors the rendered position.
      def merged_conflicting_entry(existing, entry)
        Entry.new(key: entry.key, value: preferred_value(existing.value, entry.value), line: existing.line)
      end

      # Drops template-declared pragmas whose retention rule says they do not
      # survive, mirroring how template-only nodes are dropped.
      def apply_template_retention(by_key)
        template_entries.each do |entry|
          by_key.delete(entry.key) unless keep_template_declared?(entry.key)
        end
        by_key
      end

      # Template order first, then destination-only pragmas in destination order.
      def order_entries(by_key)
        template_keys = template_entries.map(&:key).uniq
        ordered = template_keys.filter_map { |key| by_key[key] }
        destination_only = destination_entries.map(&:key).uniq - template_keys
        ordered + destination_only.filter_map { |key| by_key[key] }
      end

      def keep_template_declared?(key)
        template_declares = template_entries.any? { |entry| entry.key == key }
        destination_declares = destination_entries.any? { |entry| entry.key == key }
        # Declared by both: retention is unconditional, only the value is resolved.
        return true if template_declares && destination_declares
        return false unless template_declares

        # Template-only: retained exactly when template-only NODES are retained.
        # `preference` does not govern this. Measured against ordinary code, a
        # template-only method or constant is dropped under preference: :template
        # when add_template_only_nodes is false, and kept under
        # preference: :destination when it is true - so presence of a one-sided
        # node follows the add/remove flags, while preference only resolves
        # conflicts between nodes both sides declare. Treating preference as an
        # addition trigger would make pragmas resolve differently from code.
        @add_template_only_nodes
      end

      def keep_destination_only?
        !@remove_template_missing_nodes
      end

      def preferred_value(template_value, destination_value)
        preference == :template ? template_value : destination_value
      end

      # Drops leading blank lines so the pragma block is followed by exactly one
      # separator blank line rather than accumulating them across repeated merges
      # (idempotency).
      def drop_leading_blank_lines(lines)
        index = 0
        index += 1 while index < lines.length && lines[index].to_s.strip.empty?
        lines[index..] || []
      end

      def entries_for(source)
        return [] if source.empty?

        parse = Prism.parse(source)
        parse.magic_comments.filter_map do |magic_comment|
          key = magic_comment.key.to_s
          next unless PRAGMA_KEYS.include?(key)

          Entry.new(key: key, value: magic_comment.value.to_s, line: magic_comment.value_loc.start_line)
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
