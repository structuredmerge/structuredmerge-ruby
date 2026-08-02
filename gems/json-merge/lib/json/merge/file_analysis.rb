# frozen_string_literal: true

module Json
  module Merge
    # Analyzes JSON / JSONC file structure, extracting nodes, comments, and
    # freeze blocks for merging.
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      DEFAULT_FREEZE_TOKEN = 'json-merge'

      attr_reader :comment_tracker, :ast, :errors, :dialect

      class << self
        def find_parser_path
          TreeHaver::GrammarFinder.new(:json).find_library_path
        end
      end

      def initialize(source, freeze_token: DEFAULT_FREEZE_TOKEN, signature_generator: nil, parser_path: nil, dialect: :jsonc,
                     **_options)
        @source = source
        @lines = source.lines.map(&:chomp)
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @parser_path = parser_path
        @dialect = dialect.to_sym
        @errors = []

        @comment_tracker = CommentTracker.new(source)

        DebugLogger.time('FileAnalysis#parse_json') { parse_json }
        validate_jsonc_dialect! if valid? && @dialect == :jsonc

        @freeze_blocks = extract_freeze_blocks
        @nodes = integrate_nodes_and_freeze_blocks

        DebugLogger.debug('FileAnalysis initialized', {
                            signature_generator: signature_generator ? 'custom' : 'default',
                            nodes_count: @nodes.size,
                            freeze_blocks: @freeze_blocks.size,
                            valid: valid?
                          })
      end

      def valid?
        @errors.empty? && !@ast.nil?
      end

      def comment_capability
        @comment_capability ||= comment_tracker.augment(owners: []).capability
      end

      def comment_support_style
        @comment_support_style ||= shared_comment_support_style(
          source: :json_source,
          style: :c_style_line,
          read_strategy: :source_augmented_portable_write
        )
      end

      def comment_nodes
        comment_tracker.comment_nodes
      end

      def comment_node_at(line_num)
        comment_tracker.comment_node_at(line_num)
      end

      def comment_region_for_range(range, kind:, full_line_only: false)
        comment_tracker.comment_region_for_range(
          range,
          kind: kind,
          full_line_only: full_line_only
        )
      end

      def comment_augmenter(owners: nil, **options)
        comment_tracker.augment(
          owners: owners || comment_augmenter_default_owners,
          **options
        )
      end

      def statements
        @nodes ||= []
      end
      alias nodes statements

      def in_freeze_block?(line_num)
        @freeze_blocks.any? { |fb| fb.location.cover?(line_num) }
      end

      def freeze_block_at(line_num)
        @freeze_blocks.find { |fb| fb.location.cover?(line_num) }
      end

      def generate_signature(node)
        return super if @signature_generator
        return super unless node.is_a?(NodeWrapper)
        return super unless node.object?

        return [:root_object] if statements.size == 1 && statements.first == node

        super
      end

      def fallthrough_node?(value)
        value.is_a?(NodeWrapper) || value.is_a?(FreezeNode) || super
      end

      def root_node
        return @root_node if defined?(@root_node)
        return @root_node = nil unless valid?

        @root_node = NodeWrapper.new(@ast.root_node, lines: @lines, source: @source, dialect: @dialect)
      end

      def root_object
        return @root_object if defined?(@root_object)
        return @root_object = nil unless valid?

        root = @ast.root_node
        return @root_object = nil unless root

        root.each do |child|
          if child.type.to_s == 'object'
            return @root_object = NodeWrapper.new(child, lines: @lines, source: @source,
                                                         dialect: @dialect)
          end
        end

        @root_object = nil
      end

      def root_object_open_line
        obj = root_object
        return unless obj&.start_line

        line_at(obj.start_line)&.chomp
      end

      def root_object_close_line
        obj = root_object
        return unless obj&.end_line

        line_at(obj.end_line)&.chomp
      end

      def root_pairs
        @root_pairs ||= begin
          obj = root_object
          obj ? obj.pairs : []
        end
      end

      def comment_attachment_for(owner, line_num: nil, **options)
        shared_comment_attachment_for(
          owner,
          tracker_attachment: @comment_tracker.comment_attachment_for(owner, line_num: line_num, **options),
          line_num: line_num,
          **options
        )
      end

      # @return [Symbol]
      def comment_attachment_strategy
        :augmenter_preferred_tracker_layout
      end

      def ruleset_owner_selector
        :line_bound_statements
      end

      def ruleset_render_family
        :json_object_pairs
      end

      private

      def layout_augmenter_default_owners
        pairs = root_pairs.select { |pair| pair.respond_to?(:start_line) && pair.respond_to?(:end_line) }
        return pairs unless pairs.empty?

        comment_augmenter_default_owners
      end

      def root_merge_node
        return unless valid?

        root = @ast.root_node
        return unless root

        root_type = root.type.to_s
        return NodeWrapper.new(root, lines: @lines, source: @source, dialect: @dialect) if %w[object
                                                                                              array].include?(root_type)

        root.each do |child|
          child_type = child.type.to_s
          next if child_type == 'comment'
          next unless %w[object array].include?(child_type)

          return NodeWrapper.new(child, lines: @lines, source: @source, dialect: @dialect)
        end

        nil
      end

      def parse_json
        Json::Merge.register_backend!
        parser = TreeHaver.parser_for(parser_language, backend_type: :tree_sitter)

        @ast = parser.parse(@source)

        collect_parse_errors(@ast.root_node) if @ast&.root_node
      rescue TreeHaver::Error => e
        @errors << e
        @ast = nil
      rescue StandardError => e
        @errors << e
        @ast = nil
      end

      def parser_language
        %i[jsonc json5].include?(@dialect) ? :json5 : :json
      end

      def validate_jsonc_dialect!
        validate_jsonc_node!(@ast.root_node)
      end

      def validate_jsonc_node!(node)
        native_type = node.respond_to?(:native_type) ? node.native_type.to_s : node.type.to_s
        case native_type
        when 'identifier'
          add_jsonc_dialect_error(node, 'unquoted object keys are JSON5-only')
        when 'string'
          validate_json_literal!(node, String, 'single-quoted strings and JSON5 escapes are not supported')
        when 'number'
          validate_json_literal!(node, Numeric, 'JSON5 numeric literals are not supported')
        end

        node.each { |child| validate_jsonc_node!(child) } if node.respond_to?(:each)
      end

      # Tree-sitter identifies complete string and number tokens. Delegating those
      # token semantics to Ruby's strict JSON parser avoids a second hand-written
      # lexer while retaining AST-derived source locations.
      def validate_json_literal!(node, expected_class, reason)
        value = ::JSON.parse(node.text)
        return if value.is_a?(expected_class)

        add_jsonc_dialect_error(node, reason)
      rescue ::JSON::ParserError
        add_jsonc_dialect_error(node, reason)
      end

      def add_jsonc_dialect_error(node, reason)
        @errors << Json::Merge::JsoncDialectError.new(
          "JSONC rejects #{reason} at line #{node.start_line}, column #{node.start_point[:column] + 1}."
        )
      end

      def collect_parse_errors(node, found_errors = [])
        if node.type.to_s == 'ERROR' ||
           (node.respond_to?(:has_error?) && node.has_error?) ||
           (node.respond_to?(:missing?) && node.missing?)
          found_errors << {
            type: node.type.to_s,
            start_point: node.respond_to?(:start_point) ? node.start_point : nil,
            end_point: node.respond_to?(:end_point) ? node.end_point : nil,
            text: node.to_s
          }
        end

        node.each { |child| collect_parse_errors(child, found_errors) } if node.respond_to?(:each)
        @errors.concat(found_errors) unless found_errors.empty?
        found_errors
      end

      def extract_freeze_blocks
        freeze_starts = []
        freeze_ends = []

        single_line_pattern = %r{^\s*//\s*#{Regexp.escape(@freeze_token)}:(freeze|unfreeze)\b}i
        block_pattern = %r{^\s*/\*\s*#{Regexp.escape(@freeze_token)}:(freeze|unfreeze)\b.*\*/}i

        @lines.each_with_index do |line, idx|
          line_num = idx + 1

          marker_type = nil
          if (match = line.match(single_line_pattern))
            marker_type = match[1]&.downcase
          elsif (match = line.match(block_pattern))
            marker_type = match[1]&.downcase
          end

          next unless marker_type

          if marker_type == 'freeze'
            freeze_starts << { line: line_num, marker: line }
          elsif marker_type == 'unfreeze'
            freeze_ends << { line: line_num, marker: line }
          end
        end

        blocks = []
        freeze_starts.each do |start_info|
          matching_end = freeze_ends.find { |ending| ending[:line] > start_info[:line] }
          next unless matching_end

          freeze_ends.delete(matching_end)
          blocks << FreezeNode.new(
            start_line: start_info[:line],
            end_line: matching_end[:line],
            lines: @lines,
            start_marker: start_info[:marker],
            end_marker: matching_end[:marker]
          )
        end

        blocks
      end

      def integrate_nodes_and_freeze_blocks
        return @freeze_blocks.dup unless valid?

        result = []
        processed_lines = ::Set.new

        @freeze_blocks.each do |fb|
          (fb.start_line..fb.end_line).each { |ln| processed_lines << ln }
          result << fb
        end

        root = root_merge_node
        if root&.start_line
          root_lines = (root.start_line..root.end_line).to_a
          result << root unless root_lines.any? { |ln| processed_lines.include?(ln) }
        end

        result.sort_by { |node| node&.start_line || 0 }
      end

      def compute_node_signature(node)
        case node
        when FreezeNode
          node.signature
        when NodeWrapper
          node.signature
        end
      end
    end
  end
end
