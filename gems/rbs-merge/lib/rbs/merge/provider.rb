# frozen_string_literal: true

require 'digest'
require 'json'

module Rbs
  module Merge
    # Base-aware, source-preserving provider for normalized RBS declarations.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- provider decisions, source plans, and verification form one boundary
    class Provider
      DEFAULT_PROFILE = :source_preserving
      SUPPORTED_BACKENDS = %i[rbs tslp kreuzberg-language-pack].freeze
      Owner = Data.define(:id, :signature, :fingerprint, :start_line, :end_line, :role)
      Document = Data.define(:source, :analysis, :owners, :by_id, :unmanaged_fingerprint, :backend)
      ExactDocument = Data.define(:source, :analysis, :declarations, :issues, :role, :backend)
      Decision = Data.define(:changes, :conflicts, :choices)

      def provider_id = 'ruby.rbs'
      def family = 'rbs'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[rbs],
          backends: SUPPORTED_BACKENDS,
          profiles: [DEFAULT_PROFILE],
          role: :workflow,
          parser_requirements: {
            allowed_backend_families: %w[rbs tree-sitter],
            required_capabilities: %w[normalized-nodes exact-byte-spans]
          },
          source_preservation: %i[exact_source declaration_fragments line_provenance reparse semantic_verification]
        }.freeze
      end

      def analyze(request)
        document = parse_document(:analyze, request, :source)
        return document if provider_failure?(document)

        result(
          :analyze,
          request,
          analysis: {
            backend: document.backend.to_s,
            valid: true,
            declarations: document.owners.map { |owner| owner_description(owner) }
          },
          verification: { source_parsed: true }
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
          verification: { before_parsed: true, after_parsed: true }
        )
      end

      def merge2(request)
        incoming = parse_document(:merge2, request, :incoming)
        return incoming if provider_failure?(incoming)

        current = parse_document(:merge2, request, :current)
        return current if provider_failure?(current)

        merged = with_requested_backend(request) do
          SmartMerger.new(
            request.fetch(:incoming_source),
            request.fetch(:current_source),
            add_template_only_nodes: true
          ).merge_result
        end
        output = merged.to_s
        parsed = parse_source(output, :output, request)
        return parse_failure(:merge2, request, :output, parsed) if provider_failure?(parsed)

        planned_ids = current.owners.map(&:id) + incoming.owners.reject do |owner|
          current.by_id.key?(owner.id)
        end.map(&:id)
        actual_ids = parsed.owners.map(&:id)
        verification = {
          output_reparsed: true,
          semantic_match: actual_ids == planned_ids,
          ordered_declaration_signatures_verified: actual_ids == planned_ids,
          planned_declaration_count: planned_ids.length,
          output_declaration_count: actual_ids.length
        }
        unless verification[:semantic_match]
          return failure(
            :merge2,
            request,
            category: :render_failure,
            message: 'RBS two-way merge did not match the planned ordered declaration structure.',
            verification: verification
          )
        end

        changes = diff_documents(current, parsed)
        result(
          :merge2,
          request,
          output: output,
          changes: changes,
          render_report: {
            strategy: :rbs_substrate,
            decisions: merged.decisions,
            summary: merged.summary
          },
          verification: verification
        )
      rescue StandardError => e
        failure(:merge2, request, category: :merge_failure, message: e.message)
      end

      def merge3(request)
        exact_role = exact_revision_role(request)
        return merge3_exact(request, exact_role) if exact_role

        documents = parse_merge3_documents(request)
        return documents if provider_failure?(documents)

        decision = decide(documents, include_unmanaged_conflict: true)
        return render_conflicts(request, documents, decision) unless decision.conflicts.empty?

        render_composite(request, documents, decision)
      end

      private

      def parse_merge3_documents(request)
        %i[base ours theirs].each_with_object({}) do |role, documents|
          source = request.fetch(:"#{role}_source")
          document = parse_source(source, role, request)
          if document.is_a?(Hash) && document[:parse_error]
            return parse_failure(:merge3, request, role, document)
          elsif provider_failure?(document)
            return unsafe_document_failure(request, role, document)
          end

          documents[role] = document
        end
      end

      def parse_document(operation, request, role)
        source = request.fetch(role == :source ? :source : :"#{role}_source")
        parsed = parse_source(source, role, request)
        return parse_failure(operation, request, role, parsed) if provider_failure?(parsed)

        parsed
      end

      def parse_source(source, role, request)
        analysis = with_requested_backend(request) { FileAnalysis.new(source) }
        unless analysis.errors.empty?
          return { parse_error: analysis.errors.map(&:to_s).join('; '), source_role: role }
        end

        owners = analysis.declarations.map do |declaration|
          wrapper = NodeWrapper.new(
            declaration,
            lines: source.split("\n", -1),
            source: source,
            backend: analysis.backend
          )
          unless safe_declaration_range?(source, declaration, wrapper, analysis.backend)
            return { unsafe_range: wrapper.signature, source_role: role }
          end

          signature = wrapper.signature
          Owner.new(
            id: owner_id(signature),
            signature: signature,
            fingerprint: owner_fingerprint(source, declaration, wrapper, analysis.backend),
            start_line: wrapper.start_line,
            end_line: wrapper.end_line,
            role: role
          )
        end
        duplicate = owners.group_by(&:id).find { |_id, matches| matches.length > 1 }
        return { ambiguous_owner: duplicate.first, source_role: role } if duplicate
        return { unsafe_range: :overlapping_declarations, source_role: role } unless non_overlapping?(owners)

        Document.new(
          source: source,
          analysis: analysis,
          owners: owners.freeze,
          by_id: owners.to_h { |owner| [owner.id, owner] }.freeze,
          unmanaged_fingerprint: unmanaged_fingerprint(source, owners),
          backend: analysis.backend
        )
      rescue StandardError => e
        { parse_error: e.message, source_role: role }
      end

      def parse_exact_source(source, role, request)
        analysis = with_requested_backend(request) { FileAnalysis.new(source) }
        unless analysis.errors.empty?
          return { parse_error: analysis.errors.map(&:to_s).join('; '), source_role: role }
        end

        declarations = analysis.declarations.map do |declaration|
          wrapper = NodeWrapper.new(
            declaration,
            lines: source.split("\n", -1),
            source: source,
            backend: analysis.backend
          )
          [wrapper.signature, semantic_projection(declaration, wrapper, analysis.backend)]
        end.freeze
        duplicate = declarations.group_by(&:first).find { |_signature, matches| matches.length > 1 }
        issues = if duplicate
                   [{
                     category: :ambiguous_owner,
                     declaration: duplicate.first,
                     message: duplicate_message(duplicate.first)
                   }]
                 else
                   []
                 end
        ExactDocument.new(
          source: source,
          analysis: analysis,
          declarations: declarations,
          issues: issues.freeze,
          role: role,
          backend: analysis.backend
        )
      rescue StandardError => e
        { parse_error: e.message, source_role: role }
      end

      def safe_range?(source, location)
        return false unless location
        return false unless location.start_line.positive? && location.end_line >= location.start_line
        return false unless location.start_column.zero?
        return false if location.start_pos.negative? || location.end_pos > source.bytesize

        line_end = source.index("\n", location.end_pos) || source.bytesize
        source.byteslice(location.end_pos...line_end).to_s.each_byte.all? { |byte| [9, 13, 32].include?(byte) }
      end

      def safe_declaration_range?(source, declaration, wrapper, backend)
        return safe_range?(source, declaration.location) if backend == :rbs
        return false unless wrapper.start_line&.positive? && wrapper.end_line.to_i >= wrapper.start_line
        return false unless declaration.respond_to?(:start_byte) && declaration.respond_to?(:end_byte)

        start_byte = declaration.start_byte
        end_byte = declaration.end_byte
        return false unless start_byte && end_byte && start_byte >= 0 && end_byte <= source.bytesize
        return false unless point_column(declaration.start_point) == 0

        line_end = source.index("\n", end_byte) || source.bytesize
        source.byteslice(end_byte...line_end).to_s.each_byte.all? { |byte| [9, 13, 32].include?(byte) }
      end

      def point_column(point)
        return point.column if point.respond_to?(:column)
        return point[:column] if point.respond_to?(:[])

        nil
      end

      def non_overlapping?(owners)
        owners.each_cons(2).all? { |left, right| left.end_line < right.start_line }
      end

      def unmanaged_fingerprint(source, owners)
        owned_lines = owners.each_with_object({}) do |owner, lines|
          (owner.start_line..owner.end_line).each { |line| lines[line] = true }
        end
        source.lines.each_with_index.filter_map do |line, index|
          line unless owned_lines[index + 1]
        end.join
      end

      def owner_fingerprint(source, declaration, wrapper, backend)
        exact_source = if backend == :rbs
                         location = declaration.location
                         source.byteslice(location.start_pos...location.end_pos)
                       else
                         source.byteslice(declaration.start_byte...declaration.end_byte)
                       end
        fingerprint_value = [semantic_projection(declaration, wrapper, backend), exact_source]
        Digest::SHA256.hexdigest(JSON.generate(Ast::Merge.json_ready(fingerprint_value)))
      end

      def semantic_projection(declaration, wrapper, backend)
        return NativeProjection.call(declaration) if backend == :rbs

        [wrapper.signature, tree_projection(declaration)]
      end

      def tree_projection(node)
        children = []
        node.each { |child| children << tree_projection(child) } if node.respond_to?(:each)
        leaf_text = node.text.to_s if children.empty? && node.respond_to?(:text)
        [node.type.to_s, leaf_text, children]
      end

      def with_requested_backend(request, &block)
        backend = request[:backend]
        return yield unless backend

        TreeHaver.with_backend(backend, &block)
      end

      def owner_id(signature)
        Digest::SHA256.hexdigest(JSON.generate(Ast::Merge.json_ready(signature)))
      end

      def owner_path(owner)
        owner ? owner.signature.inspect : '<document>'
      end

      def owner_description(owner)
        {
          path: owner_path(owner),
          signature: owner.signature,
          source_role: owner.role,
          line_range: [owner.start_line, owner.end_line]
        }
      end

      def diff_documents(before, after)
        ordered_ids(before, after).filter_map do |id|
          left = before.by_id[id]
          right = after.by_id[id]
          next if equivalent?(left, right)

          {
            path: owner_path(left || right),
            before: change_side(left),
            after: change_side(right),
            change: change_kind(left, right)
          }.freeze
        end.freeze
      end

      def change_side(owner)
        return { present: false } unless owner

        { present: true, source_role: owner.role, line_range: [owner.start_line, owner.end_line] }
      end

      def ordered_ids(*documents)
        documents.flat_map { |document| document.owners.map(&:id) }.uniq
      end

      def change_kind(before, after)
        return :added unless before
        return :deleted unless after

        :edited
      end

      def decide(documents, include_unmanaged_conflict:)
        changes = []
        conflicts = []
        choices = {}
        if include_unmanaged_conflict
          append_unmanaged_conflict(changes, conflicts, documents)
          append_directive_conflict(changes, conflicts, documents)
        end
        ordered_ids(*documents.values).each do |id|
          base = documents.fetch(:base).by_id[id]
          ours = documents.fetch(:ours).by_id[id]
          theirs = documents.fetch(:theirs).by_id[id]
          ours_change = side_change(base, ours)
          theirs_change = side_change(base, theirs)
          next choices[id] = :ours if ours_change == :unchanged && theirs_change == :unchanged

          change = {
            path: owner_path(base || ours || theirs),
            ours: ours_change,
            theirs: theirs_change
          }.freeze
          changes << change
          choice = owner_choice(base, ours, theirs)
          if choice == :conflict
            conflicts << conflict_for(id, base, ours, theirs, change)
          else
            choices[id] = choice
          end
        end
        Decision.new(changes: changes.freeze, conflicts: conflicts.freeze, choices: choices.freeze)
      end

      def append_unmanaged_conflict(changes, conflicts, documents)
        base = documents.fetch(:base).unmanaged_fingerprint
        ours = documents.fetch(:ours).unmanaged_fingerprint
        theirs = documents.fetch(:theirs).unmanaged_fingerprint
        return if ours == theirs

        change = {
          path: '<unmanaged-source>',
          ours: base == ours ? :unchanged : :edited,
          theirs: base == theirs ? :unchanged : :edited
        }.freeze
        changes << change
        conflicts << {
          conflict_id: "rbs-unmanaged-#{Digest::SHA256.hexdigest([base, ours, theirs].join("\0"))[0, 16]}",
          category: :unmanaged_source_change,
          path: change.fetch(:path),
          owner_id: nil,
          change_classification: change
        }.freeze
      end

      def append_directive_conflict(changes, conflicts, documents)
        return unless documents.values.any? { |document| document.analysis.directives.any? }

        change = { path: '<directives>', ours: :unsafe, theirs: :unsafe }.freeze
        changes << change
        conflicts << {
          conflict_id: "rbs-directives-#{Digest::SHA256.hexdigest(documents.values.map(&:source).join("\0"))[0, 16]}",
          category: :unsafe_directives,
          path: change.fetch(:path),
          owner_id: nil,
          change_classification: change
        }.freeze
      end

      def side_change(base, side)
        return :unchanged if equivalent?(base, side)
        return :added if !base && side
        return :deleted if base && !side
        return :unchanged unless base || side

        :edited
      end

      def owner_choice(base, ours, theirs)
        return :ours if equivalent?(ours, theirs)
        return :theirs if equivalent?(base, ours)
        return :ours if equivalent?(base, theirs)
        return if ours.nil? && theirs.nil?

        :conflict
      end

      def equivalent?(left, right)
        return true if left.nil? && right.nil?
        return false unless left && right

        left.fingerprint == right.fingerprint
      end

      def conflict_for(id, base, ours, theirs, change)
        {
          conflict_id: "rbs-declaration-#{id[0, 16]}",
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
        {
          present: !owner.nil?,
          fingerprint: owner&.fingerprint,
          source_role: owner&.role,
          line_range: owner && [owner.start_line, owner.end_line]
        }
      end

      def exact_revision_role(request)
        base = request.fetch(:base_source)
        ours = request.fetch(:ours_source)
        theirs = request.fetch(:theirs_source)
        return :ours if ours == theirs || base == theirs

        :theirs if base == ours
      end

      def merge3_exact(request, role)
        documents = %i[base ours theirs].to_h do |source_role|
          [source_role, parse_exact_source(request.fetch(:"#{source_role}_source"), source_role, request)]
        end
        winner = documents.fetch(role)
        return parse_failure(:merge3, request, role, winner) if provider_failure?(winner)

        render_exact(request, documents, role)
      end

      def render_exact(request, documents, role)
        winner = documents.fetch(role)
        rendered = render_plan(request, [whole_source_fragment(role, request.fetch(:"#{role}_source"))])
        verification = verify_exact_rendered(rendered.content, winner, request)
        unless verification[:semantic_match] && verification[:byte_exact]
          return failure(
            :merge3,
            request,
            category: :render_failure,
            message: 'RBS exact revision did not remain byte-exact and semantically identical after native reparse.',
            source_role: role,
            render_report: render_report(rendered, :exact_revision),
            verification: verification.merge(base_participated: true)
          )
        end

        result(
          :merge3,
          request,
          output: rendered.content,
          diagnostics: exact_diagnostics(documents),
          render_report: render_report(rendered, :exact_revision),
          verification: verification.merge(base_participated: true)
        )
      end

      def verify_exact_rendered(output, expected, request)
        parsed = parse_exact_source(output, :output, request)
        if provider_failure?(parsed)
          return {
            output_reparsed: false,
            byte_exact: output == expected.source,
            semantic_match: false,
            parse_error: failure_detail(parsed),
            source_role: expected.role
          }
        end

        actual_signatures = parsed.declarations.map(&:first)
        expected_signatures = expected.declarations.map(&:first)
        actual_attributes = parsed.declarations.map(&:last)
        expected_attributes = expected.declarations.map(&:last)
        {
          output_reparsed: true,
          byte_exact: output == expected.source,
          semantic_match: parsed.declarations == expected.declarations,
          ordered_declaration_signatures_verified: actual_signatures == expected_signatures,
          ast_attributes_verified: actual_attributes == expected_attributes,
          planned_declaration_count: expected.declarations.length,
          output_declaration_count: parsed.declarations.length,
          source_role: expected.role
        }
      end

      def exact_diagnostics(documents)
        documents.flat_map do |role, document|
          if provider_failure?(document)
            [{
              category: :parse_error,
              severity: :warning,
              message: "#{role} parse error: #{failure_detail(document)}",
              blocking: false,
              source_role: role
            }]
          else
            document.issues.map do |issue|
              issue.merge(severity: :warning, blocking: false, source_role: role).freeze
            end
          end
        end.freeze
      end

      def duplicate_message(signature)
        "ambiguous duplicate declaration #{signature.inspect}"
      end

      def render_composite(request, documents, decision)
        fragments = composite_fragments(documents, decision)
        rendered = render_plan(request, fragments)
        expected = expected_owners(documents, decision)
        verification = verify_rendered(rendered.content, expected, request)
        unless verification[:semantic_match]
          return failure(
            :merge3,
            request,
            category: :render_failure,
            message: 'RBS composite did not match the planned ordered declaration structure and AST attributes.',
            changes: decision.changes,
            render_report: render_report(rendered, :exact_declaration_composite),
            verification: verification.merge(base_participated: true)
          )
        end

        result(
          :merge3,
          request,
          output: rendered.content,
          changes: decision.changes,
          render_report: render_report(rendered, :exact_declaration_composite),
          verification: verification.merge(base_participated: true)
        )
      end

      def composite_fragments(documents, decision)
        ours = documents.fetch(:ours)
        fragments = []
        cursor = 1
        replacement_edits(documents, decision).sort_by { |edit| edit.fetch(:start_line) }.each do |edit|
          append_range(fragments, :ours, cursor, edit.fetch(:start_line) - 1)
          append_owner(fragments, edit[:owner]) if edit[:owner]
          cursor = edit.fetch(:end_line) + 1
        end
        append_range(fragments, :ours, cursor, ours.source.lines.length)
        append_additions(fragments, documents, decision)
        fragments
      end

      def replacement_edits(documents, decision)
        ours = documents.fetch(:ours)
        decision.choices.filter_map do |id, role|
          ours_owner = ours.by_id[id]
          next unless ours_owner
          next if role == :ours

          {
            start_line: ours_owner.start_line,
            end_line: ours_owner.end_line,
            owner: role && documents.fetch(role).by_id[id]
          }
        end
      end

      def append_additions(fragments, documents, decision)
        ours = documents.fetch(:ours)
        additions = documents.fetch(:theirs).owners.select do |owner|
          !ours.by_id.key?(owner.id) && decision.choices[owner.id] == :theirs
        end
        return if additions.empty?

        ensure_plan_boundary!(fragments, documents)
        additions.each_with_index do |owner, index|
          append_owner(fragments, owner)
          ensure_plan_boundary!(fragments, documents) if index < additions.length - 1
        end
      end

      def ensure_plan_boundary!(fragments, documents)
        fragment = fragments.last
        return if fragment.nil? || fragment_content(fragment, documents).end_with?("\n")

        if fragment.is_a?(Ast::Merge::SourceRender::SourceFragment) && fragment.start_line < fragment.end_line
          fragments[-1] = source_range_fragment(fragment.revision, fragment.start_line, fragment.end_line - 1)
        else
          fragments.pop
        end
        content = if fragment.is_a?(Ast::Merge::SourceRender::SourceFragment)
                    documents.fetch(fragment.revision).source.lines.fetch(fragment.end_line - 1)
                  else
                    fragment.content
                  end
        fragments << Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: "#{content}\n",
          reason: :declaration_separator,
          producer: provider_id,
          metadata: { source_role: fragment.respond_to?(:revision) ? fragment.revision : nil, copied_source: true }
        )
      end

      def fragment_content(fragment, documents)
        return fragment.content if fragment.is_a?(Ast::Merge::SourceRender::SynthesizedFragment)

        document = documents.fetch(fragment.revision)
        document.source.lines.slice(fragment.start_line - 1, fragment.end_line - fragment.start_line + 1).join
      end

      def append_owner(fragments, owner)
        fragments << source_range_fragment(owner.role, owner.start_line, owner.end_line)
      end

      def append_range(fragments, role, start_line, end_line)
        return if start_line > end_line

        fragments << source_range_fragment(role, start_line, end_line)
      end

      def expected_owners(documents, decision)
        ours = documents.fetch(:ours)
        expected = ours.owners.filter_map do |owner|
          role = decision.choices[owner.id]
          role && documents.fetch(role).by_id[owner.id]
        end
        documents.fetch(:theirs).owners.each do |owner|
          next if ours.by_id.key?(owner.id)
          next unless decision.choices[owner.id] == :theirs

          expected << owner
        end
        expected
      end

      def verify_rendered(output, expected, request)
        parsed = parse_source(output, :output, request)
        if provider_failure?(parsed)
          return {
            output_reparsed: false,
            semantic_match: false,
            parse_error: failure_detail(parsed)
          }
        end

        actual = parsed.owners.map { |owner| [owner.signature, owner.fingerprint] }
        planned = expected.map { |owner| [owner.signature, owner.fingerprint] }
        {
          output_reparsed: true,
          semantic_match: actual == planned,
          ordered_declaration_signatures_verified: actual.map(&:first) == planned.map(&:first),
          ast_attributes_verified: actual.map(&:last) == planned.map(&:last),
          planned_declaration_count: planned.length,
          output_declaration_count: actual.length
        }
      end

      def render_conflicts(request, documents, decision)
        localized = localized_conflict_fragments(request, documents, decision)
        if localized
          rendered = render_plan(request, localized)
          return conflict_failure(request, decision, rendered, :declaration_localized_conflict)
        end

        rendered = render_plan(request, [whole_document_conflict(request, decision)])
        conflict_failure(
          request,
          decision,
          rendered,
          :full_file_conflict,
          fallbacks: [{ from: :declaration_localization, to: :full_file_conflict, reason: :source_ownership_unproven }]
        )
      end

      def localized_conflict_fragments(request, documents, decision)
        return if decision.conflicts.any? { |conflict| conflict[:owner_id].nil? }

        ours = documents.fetch(:ours)
        return unless decision.conflicts.all? { |conflict| ours.by_id.key?(conflict.fetch(:owner_id)) }

        ranges = decision.conflicts.map { |conflict| [conflict, ours.by_id.fetch(conflict.fetch(:owner_id))] }
        return unless ranges.sort_by { |_conflict, owner| owner.start_line }.each_cons(2).none? do |left, right|
          left.last.end_line >= right.last.start_line
        end

        fragments = []
        cursor = 1
        ranges.sort_by { |_conflict, owner| owner.start_line }.each do |conflict, owner|
          append_range(fragments, :ours, cursor, owner.start_line - 1)
          fragments << declaration_conflict_fragment(request, documents, conflict)
          cursor = owner.end_line + 1
        end
        append_range(fragments, :ours, cursor, ours.source.lines.length)
        fragments
      end

      def declaration_conflict_fragment(request, documents, conflict)
        Ast::Merge::SourceRender::ConflictFragment.new(
          conflict_id: conflict.fetch(:conflict_id),
          base: conflict_declaration_side(documents, conflict, :base),
          ours: conflict_declaration_side(documents, conflict, :ours),
          theirs: conflict_declaration_side(documents, conflict, :theirs),
          labels: request.fetch(:labels, {}),
          marker_size: request.fetch(:conflict_marker_size, 7),
          metadata: { path: conflict.fetch(:path), category: conflict.fetch(:category) }
        )
      end

      def conflict_declaration_side(documents, conflict, role)
        document = documents.fetch(role)
        owner = document.by_id[conflict.fetch(:owner_id)]
        owner ? [conflict_source_fragment(owner, document.source)] : []
      end

      def unsafe_document_failure(request, role, parsed)
        return parsed unless parsed[:unsafe_range] || parsed[:ambiguous_owner]

        conflict_id = "rbs-unsafe-#{Digest::SHA256.hexdigest([role, failure_detail(parsed)].join("\0"))[0, 16]}"
        conflict = {
          conflict_id: conflict_id,
          category: parsed[:ambiguous_owner] ? :ambiguous_owner : :unsafe_source_range,
          path: '<document>',
          owner_id: nil,
          source_role: role
        }
        rendered = render_plan(
          request,
          [whole_document_conflict(request, Decision.new(changes: [], conflicts: [conflict], choices: {}))]
        )
        failure(
          :merge3,
          request,
          category: conflict.fetch(:category),
          message: "#{role} cannot be merged safely: #{failure_detail(parsed)}",
          conflicts: [conflict],
          conflicted_output: rendered.content,
          source_role: role,
          render_report: render_report(rendered, :full_file_conflict),
          verification: { base_participated: true }
        )
      end

      def whole_document_conflict(request, decision)
        Ast::Merge::SourceRender::ConflictFragment.new(
          conflict_id: decision.conflicts.first.fetch(:conflict_id),
          base: [conflict_whole_source_fragment(:base, request.fetch(:base_source))],
          ours: [conflict_whole_source_fragment(:ours, request.fetch(:ours_source))],
          theirs: [conflict_whole_source_fragment(:theirs, request.fetch(:theirs_source))],
          labels: request.fetch(:labels, {}),
          marker_size: request.fetch(:conflict_marker_size, 7),
          metadata: { conflicts: decision.conflicts.map { |conflict| conflict[:conflict_id] } }
        )
      end

      def conflict_source_fragment(owner, source)
        fragment_source = source.lines.slice(owner.start_line - 1, owner.end_line - owner.start_line + 1).join
        return source_range_fragment(owner.role, owner.start_line, owner.end_line) if fragment_source.end_with?("\n")

        synthesized_copy("#{fragment_source}\n", :conflict_line_boundary, owner.role)
      end

      def conflict_whole_source_fragment(role, source)
        return whole_source_fragment(role, source) if source.empty? || source.end_with?("\n")

        synthesized_copy("#{source}\n", :conflict_line_boundary, role)
      end

      def synthesized_copy(content, reason, role)
        Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: content,
          reason: reason,
          producer: provider_id,
          metadata: { source_role: role, copied_source: true }
        )
      end

      def whole_source_fragment(role, source)
        return synthesized_copy('', :exact_empty_source, role) if source.empty?

        source_range_fragment(role, 1, source.lines.length)
      end

      def source_range_fragment(role, start_line, end_line)
        Ast::Merge::SourceRender::SourceFragment.new(
          revision: role,
          start_line: start_line,
          end_line: end_line,
          metadata: { source_role: role }
        )
      end

      def render_plan(request, fragments)
        Ast::Merge::SourceRender::Renderer.new.render(
          Ast::Merge::SourceRender::Plan.new(
            sources: {
              base: request[:base_source].to_s,
              ours: request[:ours_source].to_s,
              theirs: request[:theirs_source].to_s
            },
            fragments: fragments,
            metadata: { provider_id: provider_id }
          )
        )
      end

      def render_report(rendered, strategy)
        {
          strategy: strategy,
          line_records: rendered.line_records,
          synthesized_fragments: rendered.synthesized_fragments,
          conflicts: rendered.conflicts,
          verification_input: rendered.verification_input
        }
      end

      def conflict_failure(request, decision, rendered, strategy, fallbacks: [])
        failure(
          :merge3,
          request,
          category: :merge_conflict,
          message: 'RBS top-level declaration changed incompatibly on both sides.',
          changes: decision.changes,
          conflicts: decision.conflicts,
          conflicted_output: rendered.content,
          render_report: render_report(rendered, strategy),
          verification: { base_participated: true },
          fallbacks: fallbacks
        )
      end

      def parse_failure(operation, request, role, parsed)
        category = if parsed[:parse_error]
                     :parse_error
                   elsif parsed[:ambiguous_owner]
                     :ambiguous_owner
                   else
                     :unsafe_source_range
                   end
        failure(
          operation,
          request,
          category: category,
          message: "#{role} parse error: #{failure_detail(parsed)}",
          source_role: role
        )
      end

      def failure_detail(parsed)
        return parsed[:parse_error] if parsed[:parse_error]
        return "ambiguous duplicate declaration #{parsed[:ambiguous_owner].inspect}" if parsed[:ambiguous_owner]

        "unsafe declaration range #{parsed[:unsafe_range].inspect}"
      end

      def provider_failure?(value)
        value.is_a?(Hash) &&
          (value[:ok] == false || value.key?(:parse_error) || value.key?(:ambiguous_owner) || value.key?(:unsafe_range))
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
            dialect: request[:dialect] || :rbs,
            backend: request[:backend] || :rbs,
            package: 'rbs-merge',
            package_version: Rbs::Merge::Version::VERSION
          },
          profile: { profile_id: request[:profile_id] || DEFAULT_PROFILE }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  end
end
