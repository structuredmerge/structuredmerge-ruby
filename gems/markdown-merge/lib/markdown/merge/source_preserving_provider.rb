# frozen_string_literal: true

require 'digest'
require 'json'

module Markdown
  module Merge
    # Parser adapter used by the conservative Markdown provider. Backends supply
    # native AST facts; the provider owns all source-range and merge policy.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- backend ASTs expose materially different heading facts
    class ProviderBackend
      Heading = Data.define(:level, :text, :start_line, :end_line, :style)

      attr_reader :id, :package, :dialects

      def initialize(id:, package:, dialects:, parser:, headings:)
        @id = id.to_sym
        @package = package
        @dialects = dialects.map(&:to_sym).freeze
        @parser = parser
        @headings = headings
      end

      def parse(source)
        tree = @parser.call(source)
        root = tree.root_node
        raise TreeHaver::NotAvailable, 'Markdown parser returned no root node' unless root
        if root.respond_to?(:has_error?) && root.has_error?
          raise TreeHaver::NotAvailable, 'Markdown parser reported a syntax error'
        end

        [root, @headings.call(root, source)]
      end

      class << self
        def native_headings(root, source, kramdown: false)
          root.children.filter_map do |node|
            next unless node.type.to_s == 'heading'

            start_line = point_row(node.start_point)
            end_line = point_row(node.end_point)
            level = node.header_level.to_i
            text = node.text.to_s.chomp
            style = if kramdown
                      kramdown_atx?(node, source, start_line, level, text) ? :atx : :setext
                    else
                      start_line == end_line ? :atx : :setext
                    end
            Heading.new(level: level, text: text, start_line: start_line, end_line: end_line, style: style)
          end
        end

        def tree_sitter_headings(root, _source)
          document_section_headings(root).filter_map do |node|
            type = node.type.to_s
            level = atx_level(node)
            if level
              Heading.new(
                level: level,
                text: heading_inline_text(node),
                start_line: point_row(node.start_point),
                end_line: point_row(node.end_point),
                style: :atx
              )
            elsif type.start_with?('setext_') && type.end_with?('_heading')
              Heading.new(
                level: type.include?('h1') ? 1 : 2,
                text: heading_inline_text(node),
                start_line: point_row(node.start_point),
                end_line: point_row(node.end_point),
                style: :setext
              )
            end
          end
        end

        private

        def document_section_headings(root)
          output = []
          visit = lambda do |node|
            node.children.each do |child|
              type = child.type.to_s
              if type == 'atx_heading' || (type.start_with?('setext_') && type.end_with?('_heading'))
                output << child
              elsif type == 'section'
                visit.call(child)
              end
            end
          end
          visit.call(root)
          output
        end

        def atx_level(node)
          return unless node.type.to_s == 'atx_heading'

          marker = node.children.first&.type.to_s
          {
            'atx_h1_marker' => 1,
            'atx_h2_marker' => 2,
            'atx_h3_marker' => 3,
            'atx_h4_marker' => 4,
            'atx_h5_marker' => 5,
            'atx_h6_marker' => 6
          }[marker]
        end

        def heading_inline_text(node)
          inline = node.children.find { |child| child.type.to_s == 'inline' }
          inline&.text.to_s
        end

        def point_row(point)
          point.respond_to?(:row) ? point.row : point.fetch(:row)
        end

        def kramdown_atx?(node, source, line, level, text)
          options = node.inner_node.options
          return false unless options[:location].to_i == line + 1
          return false unless options[:raw_text].to_s == text

          source_line = source.each_line.with_index.find { |_value, index| index == line }&.first.to_s
          bytes = source_line.bytes
          return false unless level.between?(1, 6) && bytes.first(level).all? { |byte| byte == 35 }
          return false unless [9, 32].include?(bytes[level])

          true
        end
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # Base-aware source-preserving provider for a deliberately small Markdown
    # subset: complete documents partitioned by unique, same-level ATX headings.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- parsing, ownership, rendering, and verification are one safety boundary
    class SourcePreservingProvider
      DEFAULT_PROFILE = :source_preserving
      Owner = Data.define(:id, :signature, :fingerprint, :start_byte, :end_byte, :role, :source_text)
      Document = Data.define(:source, :owners, :by_id, :role)
      ExactDocument = Data.define(:source, :headings, :issues, :role)
      Decision = Data.define(:changes, :conflicts, :choices)

      attr_reader :backend, :provider_id

      def initialize(provider_id:, role:, backend:)
        @provider_id = provider_id
        @role = role.to_sym
        @backend = backend
      end

      def family = 'markdown'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: backend.dialects,
          backends: [backend.id],
          profiles: [DEFAULT_PROFILE],
          role: @role,
          ast_ownership: :unique_same_level_atx_heading_sections,
          source_preservation: %i[exact_source exact_fragments byte_provenance reparse semantic_verification]
        }.freeze
      end

      def analyze(request)
        document = parse_document(:analyze, request, :source)
        return document if provider_failure?(document)

        result(
          :analyze,
          request,
          analysis: {
            backend: backend.id,
            delegated_backend: backend.id,
            valid: true,
            owners: document.owners.map { |owner| owner_description(owner) }
          },
          verification: { source_parsed: true, ast_headings_verified: true }
        )
      end

      def diff2(request)
        before = parse_document(:diff2, request, :before)
        return before if provider_failure?(before)

        after = parse_document(:diff2, request, :after)
        return after if provider_failure?(after)

        changes = diff_documents(before, after)
        result(
          :diff2,
          request,
          diff: { changes: changes },
          changes: changes,
          verification: { before_parsed: true, after_parsed: true, ast_headings_verified: true }
        )
      end

      def merge2(request)
        current = parse_document(:merge2, request, :current)
        return current if provider_failure?(current)

        incoming = parse_document(:merge2, request, :incoming)
        return incoming if provider_failure?(incoming)

        choices = current.owners.to_h { |owner| [owner.id, :current] }
        incoming.owners.each { |owner| choices[owner.id] ||= :incoming }
        decision = Decision.new(changes: [], conflicts: [], choices: choices.freeze)
        documents = { current: current, incoming: incoming }.freeze
        ordered = merged_order(documents, decision)
        return unsafe_merge2_order_failure(request) unless ordered

        fragments = ordered.map do |id|
          role = decision.choices.fetch(id)
          [documents.fetch(role).by_id.fetch(id), role]
        end
        output = composite_prefix(documents, :current) + fragments.map { |owner, _role| owner.source_text }.join
        expected = fragments.map { |owner, _role| [owner.signature, owner.fingerprint] }
        verification = verify_composite(output, expected)
        unless verification[:semantic_match]
          return render_failure(request, verification, :exact_markdown_composite, operation: :merge2)
        end

        output_document = parse_source(output, :output)
        changes = diff_documents(current, output_document)
        result(
          :merge2,
          request,
          output: output,
          changes: changes,
          render_report: composite_render_report(fragments, output),
          verification: verification
        )
      end

      def merge3(request)
        exact_role = exact_revision_role(request)
        return merge3_exact(request, exact_role) if exact_role

        documents = parse_merge3_documents(request)
        return documents if provider_failure?(documents)

        identity_failure = changed_identity_failure(request, documents)
        return identity_failure if identity_failure

        decision = decide(documents)
        return render_conflicts(request, documents, decision) unless decision.conflicts.empty?

        render_composite(request, documents, decision)
      end

      private

      def parse_merge3_documents(request)
        %i[base ours theirs].each_with_object({}) do |role, documents|
          parsed = parse_source(request.fetch(:"#{role}_source"), role)
          return unsafe_document_failure(request, role, parsed) if provider_failure?(parsed)

          documents[role] = parsed
        end
      end

      def parse_document(operation, request, role)
        key = role == :source ? :source : :"#{role}_source"
        parsed = parse_source(request.fetch(key), role)
        return parse_failure(operation, request, role, parsed) if provider_failure?(parsed)

        parsed
      end

      def parse_source(source, role)
        parsed = parse_ast(source, role)
        return parsed if provider_failure?(parsed)

        headings = parsed.fetch(:headings)
        return { unsafe: :headingless_document, source_role: role } if headings.empty?
        return { unsafe: :setext_heading, source_role: role } unless headings.all? { |heading| heading.style == :atx }
        headings = independently_ownable_headings(headings)
        return { unsafe: :nested_heading_hierarchy, source_role: role } if headings.empty?

        starts = headings.map(&:start_line).map { |line| line_start_byte(source, line) }
        if starts.any?(&:nil?) || starts != starts.sort.uniq
          return { unsafe: :invalid_heading_start, source_role: role }
        end
        unless starts.first.zero? || heading_only_prefix?(source, parsed.fetch(:headings), starts.first)
          return { unsafe: :source_before_first_section, source_role: role }
        end

        owners = headings.each_with_index.map do |heading, index|
          signature = [heading.level, heading.text].freeze
          start_byte = starts.fetch(index)
          end_byte = starts[index + 1] || source.bytesize
          return { unsafe: :overlapping_heading_sections, source_role: role } unless end_byte > start_byte

          source_text = source.byteslice(start_byte...end_byte).to_s
          Owner.new(
            id: owner_id(signature),
            signature: signature,
            fingerprint: fingerprint(source_text),
            start_byte: start_byte,
            end_byte: end_byte,
            role: role,
            source_text: source_text
          )
        end
        duplicate = owners.group_by(&:id).find { |_id, matches| matches.length > 1 }
        return { ambiguous: duplicate.first, source_role: role } if duplicate

        Document.new(
          source: source,
          owners: owners.freeze,
          by_id: owners.to_h { |owner| [owner.id, owner] }.freeze,
          role: role
        )
      rescue StandardError => e
        { parse_error: e.message, source_role: role }
      end

      # A nested heading is ownable when it has no descendant headings. Ancestor
      # headings remain unmanaged framing, so edits to them still fail closed.
      def independently_ownable_headings(headings)
        headings.each_with_index.reject do |heading, index|
          headings[(index + 1)..].any? do |candidate|
            candidate.level > heading.level &&
              headings[(index + 1)..].take_while { |item| item.level > heading.level }.include?(candidate)
          end
        end.map(&:first)
      end

      def heading_only_prefix?(source, headings, first_owner_start)
        prefix = source.byteslice(0...first_owner_start).to_s
        heading_lines = headings.select { |heading| line_start_byte(source, heading.start_line) < first_owner_start }
        heading_lines.any? && prefix.lines.all? do |line|
          line.strip.empty? || heading_lines.any? do |heading|
            line.strip.match?(/\A\#{1,6}\s+#{Regexp.escape(heading.text.to_s)}\s*\z/)
          end
        end
      end

      def parse_exact_source(source, role)
        parsed = parse_ast(source, role)
        return parsed if provider_failure?(parsed)

        headings = parsed.fetch(:headings)
        issues = []
        duplicates = headings.group_by { |heading| [heading.level, heading.text] }
                             .select { |_signature, matches| matches.length > 1 }
        duplicates.each_key do |signature|
          issues << { category: :ambiguous_owner, heading: signature,
                      message: "Duplicate Markdown heading #{signature.inspect}" }.freeze
        end
        issues << { category: :unsafe_source_range, message: 'Setext heading is not independently ownable.' }.freeze if
          headings.any? { |heading| heading.style != :atx }
        ExactDocument.new(source: source, headings: headings.freeze, issues: issues.freeze, role: role)
      rescue StandardError => e
        { parse_error: e.message, source_role: role }
      end

      def parse_ast(source, role)
        return { parse_error: 'Markdown source must be a String', source_role: role } unless source.is_a?(String)

        parser_source = source.dup.force_encoding(Encoding::UTF_8)
        return { parse_error: 'Markdown source must be valid UTF-8', source_role: role } unless
          parser_source.valid_encoding?
        return { parse_error: 'Markdown source contains a NUL byte', source_role: role } if source.include?("\0")

        _root, headings = backend.parse(parser_source)
        { headings: headings }
      rescue StandardError => e
        { parse_error: e.message, source_role: role }
      end

      def line_start_byte(source, line)
        return if line.negative?
        return 0 if line.zero?

        offset = 0
        source.each_line.with_index do |text, index|
          return offset if index == line

          offset += text.bytesize
        end
        nil
      end

      def owner_id(signature)
        fingerprint(JSON.generate(Ast::Merge.json_ready(signature)))
      end

      def fingerprint(value)
        Digest::SHA256.hexdigest(value)
      end

      def diff_documents(before, after)
        ordered_ids(before, after).filter_map do |id|
          left = before.by_id[id]
          right = after.by_id[id]
          next if equivalent?(left, right)

          {
            path: owner_path(left || right),
            before: owner_state(left),
            after: owner_state(right),
            change: change_kind(left, right)
          }.freeze
        end.freeze
      end

      def ordered_ids(*documents)
        documents.flat_map { |document| document.owners.map(&:id) }.uniq
      end

      def equivalent?(left, right)
        return true if left.nil? && right.nil?
        return false unless left && right

        left.fingerprint == right.fingerprint
      end

      def change_kind(before, after)
        return :added unless before
        return :deleted unless after

        :edited
      end

      def changed_identity_failure(request, documents)
        base_ids = documents.fetch(:base).by_id.keys
        %i[ours theirs].each do |role|
          side_ids = documents.fetch(role).by_id.keys
          removed = base_ids - side_ids
          added = side_ids - base_ids
          next if removed.empty? || added.empty?

          return failure(
            :merge3,
            request,
            category: :unstable_owner_identity,
            message: "#{role} both removes and adds heading identities; rename or level change cannot be excluded.",
            conflicts: [{ category: :unstable_owner_identity, source_role: role, path: '<document>' }],
            conflicted_output: whole_document_conflict(request),
            source_role: role,
            render_report: { strategy: :full_file_conflict },
            verification: { base_participated: true }
          )
        end
        nil
      end

      def decide(documents)
        changes = []
        conflicts = []
        choices = {}
        ordered_ids(*documents.values).each do |id|
          base = documents.fetch(:base).by_id[id]
          ours = documents.fetch(:ours).by_id[id]
          theirs = documents.fetch(:theirs).by_id[id]
          ours_change = side_change_kind(base, ours)
          theirs_change = side_change_kind(base, theirs)
          choice = owner_choice(base, ours, theirs)
          choices[id] = choice unless choice == :conflict
          next if ours_change == :unchanged && theirs_change == :unchanged

          change = { path: owner_path(base || ours || theirs), ours: ours_change, theirs: theirs_change }.freeze
          changes << change
          conflicts << conflict_for(id, base, ours, theirs, change) if choice == :conflict
        end
        Decision.new(changes: changes.freeze, conflicts: conflicts.freeze, choices: choices.freeze)
      end

      def side_change_kind(base, side)
        return :unchanged if equivalent?(base, side)
        return :added if !base && side
        return :deleted if base && !side

        :edited
      end

      def owner_choice(base, ours, theirs)
        return :ours if equivalent?(ours, theirs)
        return :theirs if equivalent?(base, ours)
        return :ours if equivalent?(base, theirs)
        return nil if ours.nil? && theirs.nil?

        :conflict
      end

      def conflict_for(id, base, ours, theirs, change)
        {
          conflict_id: "markdown-owner-#{id[0, 16]}",
          category: base && (!ours || !theirs) ? :delete_edit : :edit_edit,
          path: change.fetch(:path),
          owner_id: id,
          base: owner_state(base),
          ours: owner_state(ours),
          theirs: owner_state(theirs),
          change_classification: change
        }.freeze
      end

      def owner_state(owner)
        { present: !owner.nil?, fingerprint: owner&.fingerprint, source_role: owner&.role }
      end

      def exact_revision_role(request)
        base = request.fetch(:base_source)
        ours = request.fetch(:ours_source)
        theirs = request.fetch(:theirs_source)
        return :ours if ours == theirs || base == theirs

        :theirs if base == ours
      end

      def merge3_exact(request, role)
        winner = parse_exact_source(request.fetch(:"#{role}_source"), role)
        return parse_failure(:merge3, request, role, winner) if provider_failure?(winner)

        output = winner.source
        verification = verify_exact(output, winner)
        return render_failure(request, verification, :exact_revision) unless verification[:semantic_match]

        result(
          :merge3,
          request,
          output: output,
          diagnostics: winner.issues.map { |issue| nonblocking_issue(issue, role) },
          render_report: {
            strategy: :exact_revision,
            provenance: [{ source_role: role, byte_range: [0, output.bytesize], copied_source: true }],
            synthesized_fragments: []
          },
          verification: verification.merge(base_participated: true)
        )
      end

      def verify_exact(output, expected)
        parsed = parse_exact_source(output, :output)
        return { output_reparsed: false, byte_exact: output == expected.source, semantic_match: false } if
          provider_failure?(parsed)

        {
          output_reparsed: true,
          byte_exact: output == expected.source,
          semantic_match: heading_semantics(parsed.headings) == heading_semantics(expected.headings),
          ordered_heading_semantics_verified: true,
          delegated_backend_verified: true,
          backend: backend.id,
          source_role: expected.role
        }
      end

      def heading_semantics(headings)
        headings.map { |heading| [heading.level, heading.text, heading.style] }
      end

      def nonblocking_issue(issue, role)
        issue.merge(severity: :warning, blocking: false, source_role: role).freeze
      end

      def render_composite(request, documents, decision)
        ordered = merged_order(documents, decision)
        return unsafe_composite_failure(request, decision, :incompatible_section_order) unless ordered

        fragments = ordered.filter_map do |id|
          role = decision.choices[id]
          owner = role && documents.fetch(role).by_id[id]
          owner && [owner, role]
        end
        output = composite_prefix(documents) + fragments.map { |owner, _role| owner.source_text }.join
        expected = fragments.map { |owner, _role| [owner.signature, owner.fingerprint] }
        verification = verify_composite(output, expected)
        return render_failure(request, verification, :exact_markdown_composite, decision.changes) unless
          verification[:semantic_match]

        result(
          :merge3,
          request,
          output: output,
          changes: decision.changes,
          render_report: composite_render_report(fragments, output),
          verification: verification.merge(base_participated: true)
        )
      end

      def merged_order(documents, decision)
        selected = decision.choices.select { |_id, role| role }.keys
        edges = Hash.new { |hash, key| hash[key] = [] }
        indegree = selected.to_h { |id| [id, 0] }
        documents.each_value do |document|
          ids = document.owners.map(&:id).select { |id| indegree.key?(id) }
          ids.each_cons(2) do |left, right|
            next if edges[left].include?(right)

            edges[left] << right
            indegree[right] += 1
          end
        end
        rank = ordered_ids(*documents.values).each_with_index.to_h
        ready = indegree.select { |_id, count| count.zero? }.keys.sort_by { |id| rank.fetch(id) }
        output = []
        until ready.empty?
          id = ready.shift
          output << id
          edges[id].each do |target|
            indegree[target] -= 1
            ready << target if indegree[target].zero?
          end
          ready.sort_by! { |candidate| rank.fetch(candidate) }
        end
        output.length == selected.length ? output : nil
      end

      def verify_composite(output, expected)
        return verify_empty_composite(output) if expected.empty?

        parsed = parse_source(output, :output)
        return { output_reparsed: false, semantic_match: false, parse_error: failure_detail(parsed) } if
          provider_failure?(parsed)

        actual = parsed.owners.map { |owner| [owner.signature, owner.fingerprint] }
        {
          output_reparsed: true,
          semantic_match: actual == expected,
          ordered_heading_semantics_verified: actual == expected,
          byte_provenance_verified: actual == expected,
          delegated_backend_verified: true,
          backend: backend.id,
          planned_owner_count: expected.length,
          output_owner_count: actual.length
        }
      end

      def verify_empty_composite(output)
        parsed = parse_exact_source(output, :output)
        valid = !provider_failure?(parsed) && parsed.headings.empty?
        {
          output_reparsed: valid,
          semantic_match: valid,
          ordered_heading_semantics_verified: valid,
          byte_provenance_verified: valid,
          delegated_backend_verified: valid,
          backend: backend.id,
          planned_owner_count: 0,
          output_owner_count: valid ? 0 : nil
        }
      end

      def composite_render_report(fragments, output)
        {
          strategy: :exact_markdown_composite,
          provenance: fragments.map do |owner, role|
            {
              source_role: role,
              owner_id: owner.id,
              source_byte_range: [owner.start_byte, owner.end_byte],
              copied_source: true
            }
          end,
          output_bytes: output.bytesize,
          line_records: fragments.map.with_index do |(owner, role), index|
            { output_index: index, source_role: role, owner_id: owner.id }
          end,
          synthesized_fragments: []
        }
      end

      def composite_prefix(documents, role = :ours)
        document = documents.fetch(role)
        first_owner = document.owners.first
        return '' unless first_owner

        document.source.byteslice(0...first_owner.start_byte).to_s
      end

      def render_conflicts(request, documents, decision)
        localized = localized_conflict_output(request, documents, decision)
        strategy = localized ? :section_localized_conflict : :full_file_conflict
        conflict_failure(
          request,
          decision,
          localized || whole_document_conflict(request),
          strategy,
          localized ? [] : [{ from: :section_localization, to: :full_file_conflict,
                              reason: :source_ownership_unproven }]
        )
      end

      def localized_conflict_output(request, documents, decision)
        ours = documents.fetch(:ours)
        return unless decision.conflicts.all? { |conflict| ours.by_id.key?(conflict.fetch(:owner_id)) }

        output = ours.source.dup
        edits = decision.conflicts.map do |conflict|
          owner = ours.by_id.fetch(conflict.fetch(:owner_id))
          [owner.start_byte, owner.end_byte, conflict_text(request, documents, conflict)]
        end
        edits.sort_by(&:first).reverse_each { |start_byte, end_byte, text| output[start_byte...end_byte] = text }
        output
      end

      def conflict_text(request, documents, conflict)
        marker = request.fetch(:conflict_marker_size, 7).to_i
        marker = 7 unless marker.positive?
        labels = { ours: 'ours', base: 'base', theirs: 'theirs' }.merge(request.fetch(:labels, {}))
        sides = %i[ours base theirs].to_h do |role|
          owner = documents.fetch(role).by_id[conflict.fetch(:owner_id)]
          [role, owner&.source_text.to_s]
        end
        [
          "#{'<' * marker} #{labels[:ours]}\n", sides[:ours],
          "#{'|' * marker} #{labels[:base]}\n", sides[:base],
          "#{'=' * marker}\n", sides[:theirs],
          "#{'>' * marker} #{labels[:theirs]}\n"
        ].join
      end

      def whole_document_conflict(request)
        marker = request.fetch(:conflict_marker_size, 7).to_i
        marker = 7 unless marker.positive?
        [
          "#{'<' * marker} ours\n", request.fetch(:ours_source),
          "#{'|' * marker} base\n", request.fetch(:base_source),
          "#{'=' * marker}\n", request.fetch(:theirs_source),
          "#{'>' * marker} theirs\n"
        ].join
      end

      def conflict_failure(request, decision, output, strategy, fallbacks)
        failure(
          :merge3,
          request,
          category: :merge_conflict,
          message: 'Markdown heading section changed incompatibly on both sides.',
          changes: decision.changes,
          conflicts: decision.conflicts,
          conflicted_output: output,
          fallbacks: fallbacks,
          render_report: { strategy: strategy, provenance: :exact_source_bytes },
          verification: { base_participated: true }
        )
      end

      def unsafe_document_failure(request, role, parsed)
        return parse_failure(:merge3, request, role, parsed) if parsed[:parse_error]

        category = parsed[:ambiguous] ? :ambiguous_owner : :unsafe_source_range
        failure(
          :merge3,
          request,
          category: category,
          message: "#{role} Markdown ownership is unsafe: #{failure_detail(parsed)}",
          conflicts: [{ category: category, source_role: role, path: '<document>' }],
          conflicted_output: whole_document_conflict(request),
          source_role: role,
          render_report: { strategy: :full_file_conflict, provenance: :exact_source_bytes },
          verification: { base_participated: true }
        )
      end

      def unsafe_composite_failure(request, decision, reason)
        failure(
          :merge3,
          request,
          category: :unsafe_source_range,
          message: 'Markdown section order cannot be proven across revisions.',
          changes: decision.changes,
          conflicts: [{ category: reason, path: '<document>' }],
          conflicted_output: whole_document_conflict(request),
          render_report: { strategy: :full_file_conflict },
          verification: { base_participated: true }
        )
      end

      def unsafe_merge2_order_failure(request)
        failure(
          :merge2,
          request,
          category: :unsafe_source_range,
          message: 'Markdown section order cannot be proven across current and incoming sources.',
          conflicts: [{ category: :incompatible_section_order, path: '<document>' }],
          render_report: { strategy: :no_output, provenance: :exact_source_bytes }
        )
      end

      def render_failure(request, verification, strategy, changes = [], operation: :merge3)
        failure(
          operation,
          request,
          category: :render_failure,
          message: 'Markdown output failed backend reparse and ordered semantic verification.',
          changes: changes,
          render_report: { strategy: strategy },
          verification: verification.merge(base_participated: true)
        )
      end

      def owner_path(owner)
        owner ? owner.signature.inspect : '<document>'
      end

      def owner_description(owner)
        {
          path: owner_path(owner),
          signature: owner.signature,
          source_role: owner.role,
          byte_range: [owner.start_byte, owner.end_byte]
        }
      end

      def parse_failure(operation, request, role, parsed)
        category = if parsed[:parse_error]
                     :parse_error
                   else
                     parsed[:ambiguous] ? :ambiguous_owner : :unsafe_source_range
                   end
        failure(
          operation,
          request,
          category: category,
          message: "#{role} Markdown parse error: #{failure_detail(parsed)}",
          source_role: role
        )
      end

      def failure_detail(parsed)
        parsed[:parse_error] || parsed[:ambiguous]&.inspect || parsed[:unsafe]&.inspect
      end

      def provider_failure?(value)
        value.is_a?(Hash) &&
          (value[:ok] == false || value.key?(:parse_error) || value.key?(:ambiguous) || value.key?(:unsafe))
      end

      def result(operation, request, changes: [], diagnostics: [], render_report: {}, verification: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: true,
          envelope: envelope(
            request,
            changes: changes,
            diagnostics: diagnostics,
            render_report: render_report,
            verification: verification
          ),
          **payload
        )
      end

      def failure(operation, request, category:, message:, changes: [], conflicts: [], fallbacks: [],
                  render_report: {}, verification: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: false,
          envelope: envelope(
            request,
            changes: changes,
            conflicts: conflicts,
            fallbacks: fallbacks,
            diagnostics: [{ category: category, severity: :error, message: message, blocking: true }],
            render_report: render_report,
            verification: verification
          ),
          **payload
        )
      end

      def envelope(request, **fields)
        {
          provider: {
            provider_id: provider_id,
            family: family,
            dialect: request[:dialect] || backend.dialects.first,
            backend: request[:backend] || backend.id,
            package: backend.package
          },
          profile: { profile_id: request[:profile_id] || DEFAULT_PROFILE }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  end
end
