# frozen_string_literal: true

require 'digest'
require 'json'
require 'ast/merge/source_render'
require_relative 'node_wrapper'
require_relative 'file_analysis'
require_relative 'test_harness_identity'

module Bash
  # Registration and source-preserving workflow implementation for Bash.
  module Merge
    class << self
      def merge_provider
        @merge_provider ||= Provider.new
      end

      def register_provider!(replace: false)
        return unless Ast::Merge.respond_to?(:register_provider)

        Ast::Merge.register_provider(merge_provider, replace: replace)
      end
    end

    # Base-aware, source-preserving provider for native top-level Bash owners.
    # Functions, assignments, and literal-title test_expect_success calls have
    # stable AST identities. Every other top-level form must remain identical
    # across all revisions in a composite.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- provider decisions, source plans, and verification form one boundary
    class Provider
      DEFAULT_PROFILE = :source_preserving
      Owner = Data.define(:id, :signature, :membership, :compound, :fingerprint, :start_line, :end_line, :role)
      Document = Data.define(:source, :analysis, :owners, :by_id, :unmanaged_fingerprint)
      ExactDocument = Data.define(:source, :analysis, :declarations, :issues, :role)
      Decision = Data.define(:changes, :conflicts, :choices)

      def provider_id = 'ruby.bash'
      def family = 'bash'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[bash],
          backends: [TREE_SITTER_BACKEND.id.to_sym],
          profiles: [DEFAULT_PROFILE],
          role: :workflow,
          ast_ownership: :stable_functions_assignments_and_literal_test_titles,
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
            backend: TREE_SITTER_BACKEND.id,
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
        merge3_request = request.merge(
          base_source: request.fetch(:current_source),
          ours_source: request.fetch(:current_source),
          theirs_source: request.fetch(:incoming_source)
        )
        merged = merge3(merge3_request)
        merged.merge(
          operation: :merge2,
          verification: merged.fetch(:verification).except(:base_participated)
        )
      end

      def merge3(request)
        exact_role = exact_revision_role(request)
        return merge3_exact(request, exact_role) if exact_role

        documents = parse_merge3_documents(request)
        return documents if provider_failure?(documents)

        ownership_failure = unstable_ownership_failure(request, documents)
        return ownership_failure if ownership_failure

        ownership_failure = test_harness_ownership_failure(request, documents)
        return ownership_failure if ownership_failure

        decision = decide(documents, include_unmanaged_conflict: true)
        return render_conflicts(request, documents, decision) unless decision.conflicts.empty?

        render_composite(request, documents, decision)
      end

      private

      def parse_merge3_documents(request)
        %i[base ours theirs].each_with_object({}) do |role, documents|
          source = request.fetch(:"#{role}_source")
          document = parse_source(source, role, request[:dialect])
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
        parsed = parse_source(source, role, request[:dialect])
        return parse_failure(operation, request, role, parsed) if provider_failure?(parsed)

        parsed
      end

      def parse_source(source, role, _dialect = nil)
        analysis = FileAnalysis.new(source)
        return { parse_error: analysis.errors.map(&:to_s).join('; '), source_role: role } unless analysis.valid?

        unstable_occurrences = Hash.new(0)
        owners = analysis.top_level_statements.map do |wrapper|
          return { unsafe_range: :heredoc, source_role: role } if wrapper.heredoc?
          return { unsafe_range: wrapper.signature, source_role: role } unless safe_range?(source, wrapper)

          signature = provider_signature(wrapper)
          return { unsafe_range: wrapper.type, source_role: role } unless signature

          occurrence = if stable_signature?(signature)
                         nil
                       else
                         unstable_occurrences[signature] += 1
                       end
          Owner.new(
            id: owner_id(occurrence ? [signature, occurrence] : signature),
            signature: signature,
            membership: signature,
            compound: false,
            fingerprint: owner_fingerprint(wrapper),
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
          unmanaged_fingerprint: unmanaged_fingerprint(source, owners)
        )
      rescue StandardError => e
        { parse_error: e.message, source_role: role }
      end

      def parse_exact_source(source, role, _dialect = nil)
        analysis = FileAnalysis.new(source)
        return { parse_error: analysis.errors.map(&:to_s).join('; '), source_role: role } unless analysis.valid?

        declarations = analysis.top_level_statements.map do |wrapper|
          [provider_signature(wrapper), wrapper.semantic_tree]
        end.freeze
        duplicate_keys = declarations.group_by(&:first).filter_map do |signature, matches|
          signature if matches.length > 1
        end
        issues = duplicate_keys.uniq.map do |identity|
          {
            category: :ambiguous_owner,
            declaration: identity,
            message: duplicate_message(identity)
          }.freeze
        end
        ExactDocument.new(
          source: source,
          analysis: analysis,
          declarations: declarations,
          issues: issues.freeze,
          role: role
        )
      rescue StandardError => e
        { parse_error: e.message, source_role: role }
      end

      def provider_signature(wrapper)
        if wrapper.function_definition?
          name = wrapper.function_name
          name && [:function, name]
        elsif wrapper.variable_assignment?
          name = wrapper.variable_name
          name && [:variable_assignment, name]
        elsif (identity = TestHarnessIdentity.for(wrapper))
          [:test_harness_call, *identity]
        else
          wrapper.signature
        end
      end

      def safe_range?(source, wrapper)
        return false if wrapper.start_byte.negative? || wrapper.end_byte > source.bytesize
        return false if wrapper.end_byte < wrapper.start_byte

        line_start = source.rindex("\n", [wrapper.start_byte - 1, 0].max)
        line_start = line_start ? line_start + 1 : 0
        line_end = source.index("\n", wrapper.end_byte) || source.bytesize
        horizontal_whitespace?(source.byteslice(line_start...wrapper.start_byte).to_s) &&
          horizontal_whitespace?(source.byteslice(wrapper.end_byte...line_end).to_s)
      end

      def horizontal_whitespace?(value)
        value.each_byte.all? { |byte| [9, 13, 32].include?(byte) }
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

      def owner_fingerprint(wrapper)
        Digest::SHA256.hexdigest(
          JSON.generate(Ast::Merge.json_ready([wrapper.semantic_tree, wrapper.source_text]))
        )
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
        append_unmanaged_conflict(changes, conflicts, documents) if include_unmanaged_conflict
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
          conflict_id: "bash-unmanaged-#{Digest::SHA256.hexdigest([base, ours, theirs].join("\0"))[0, 16]}",
          category: :unmanaged_source_change,
          path: change.fetch(:path),
          owner_id: nil,
          change_classification: change
        }.freeze
      end

      def unstable_ownership_failure(request, documents)
        sequences = documents.transform_values do |document|
          document.owners.filter_map do |owner|
            [owner.signature, owner.fingerprint] unless stable_signature?(owner.signature)
          end
        end
        return if sequences.values.uniq.one?

        mismatch_index = (0...sequences.values.map(&:length).max).find do |index|
          sequences.values.map { |sequence| sequence[index] }.uniq.length > 1
        end
        unstable = documents.values.filter_map do |document|
          unstable_owners = document.owners.reject { |owner| stable_signature?(owner.signature) }
          unstable_owners[mismatch_index]
        end.first
        identity = sequences.transform_values { |sequence| sequence[mismatch_index] }
        signature_digest = Digest::SHA256.hexdigest(JSON.generate(Ast::Merge.json_ready(sequences)))
        conflict = {
          conflict_id: "bash-ownership-#{signature_digest[0, 16]}",
          category: :unproven_ast_ownership,
          path: owner_path(unstable),
          owner_id: nil,
          signature: unstable&.signature,
          unstable_index: mismatch_index,
          identities: identity
        }.freeze
        decision = Decision.new(changes: [], conflicts: [conflict], choices: {})
        rendered = render_plan(request, [whole_document_conflict(request, decision)])
        failure(
          :merge3,
          request,
          category: :unproven_ast_ownership,
          message: 'A non-stable Bash top-level AST identity changed; whole-file fallback is required.',
          conflicts: [conflict],
          conflicted_output: rendered.content,
          render_report: render_report(rendered, :full_file_conflict),
          verification: { base_participated: true },
          fallbacks: [{
            from: :top_level_ast_ownership,
            to: :full_file_conflict,
            reason: :identity_changed
          }]
        )
      end

      def stable_signature?(signature)
        %i[function variable_assignment test_harness_call].include?(signature.first)
      end

      def test_harness_ownership_failure(request, documents)
        sequences = documents.transform_values do |document|
          document.owners.filter_map do |owner|
            owner.id if owner.signature.first == :test_harness_call
          end
        end
        base = sequences.fetch(:base)
        invalid_role = %i[ours theirs].find do |role|
          sequence = sequences.fetch(role)
          sequence.length < base.length || sequence.first(base.length) != base
        end
        changed_role = %i[ours theirs].find { |role| sequences.fetch(role) != base }
        return unless invalid_role || changed_role

        reason = if invalid_role
                   :non_append_only_test_harness_change
                 else
                   :test_harness_addition_requires_ordered_rendering
                 end
        source_role = invalid_role || changed_role

        signature_digest = Digest::SHA256.hexdigest(JSON.generate(Ast::Merge.json_ready(sequences)))
        conflict = {
          conflict_id: "bash-test-ownership-#{signature_digest[0, 16]}",
          category: :unproven_ast_ownership,
          path: '<test_expect_success-sequence>',
          owner_id: nil,
          source_role: source_role,
          identities: sequences,
          reason: reason
        }.freeze
        decision = Decision.new(changes: [], conflicts: [conflict], choices: {})
        rendered = render_plan(request, [whole_document_conflict(request, decision)])
        failure(
          :merge3,
          request,
          category: :unproven_ast_ownership,
          message: 'Literal-title test_expect_success membership changes require ordered insertion rendering.',
          conflicts: [conflict],
          conflicted_output: rendered.content,
          render_report: render_report(rendered, :full_file_conflict),
          verification: { base_participated: true },
          fallbacks: [{
            from: :test_harness_ast_ownership,
            to: :full_file_conflict,
            reason: reason
          }]
        )
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
          conflict_id: "bash-declaration-#{id[0, 16]}",
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
          [source_role, parse_exact_source(request.fetch(:"#{source_role}_source"), source_role, request[:dialect])]
        end
        winner = documents.fetch(role)
        return parse_failure(:merge3, request, role, winner) if provider_failure?(winner)

        render_exact(request, documents, role)
      end

      def render_exact(request, documents, role)
        winner = documents.fetch(role)
        rendered = render_plan(request, [whole_source_fragment(role, request.fetch(:"#{role}_source"))])
        verification = verify_exact_rendered(rendered.content, winner)
        unless verification[:semantic_match] && verification[:byte_exact]
          return failure(
            :merge3,
            request,
            category: :render_failure,
            message: 'Bash exact revision did not remain byte-exact and semantically identical ' \
                     'after native reparse.',
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

      def verify_exact_rendered(output, expected)
        parsed = parse_exact_source(output, :output)
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
        verification = verify_rendered(rendered.content, expected, request[:dialect])
        unless verification[:semantic_match]
          return failure(
            :merge3,
            request,
            category: :render_failure,
            message: 'Bash composite did not match the planned ordered declaration structure and AST attributes.',
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
        edits = composite_edits(documents, decision).sort_by do |edit|
          insertion = edit.fetch(:end_line) < edit.fetch(:start_line)
          [edit.fetch(:start_line), insertion ? 0 : 1]
        end
        edits.each do |edit|
          append_range(fragments, :ours, cursor, edit.fetch(:start_line) - 1)
          edit.fetch(:owners).each_with_index do |owner, index|
            append_owner(fragments, owner)
            ensure_plan_boundary!(fragments, documents) if index < edit.fetch(:owners).length - 1
          end
          cursor = [cursor, edit.fetch(:end_line) + 1].max
        end
        append_range(fragments, :ours, cursor, ours.source.lines.length)
        append_declaration_additions(fragments, documents, decision)
        fragments
      end

      def composite_edits(documents, decision)
        replacement_edits(documents, decision) + import_insertion_edits(documents, decision)
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
            owners: [role && documents.fetch(role).by_id[id]].compact
          }
        end
      end

      def import_insertion_edits(documents, decision)
        additions = added_theirs_owners(documents, decision).select { |owner| import_owner?(owner) }
        return [] if additions.empty?

        ours = documents.fetch(:ours)
        anchor = ours.owners.reverse.find { |owner| package_or_import_owner?(owner) }
        insertion_line = anchor ? anchor.end_line + 1 : ours.owners.first&.start_line || ours.source.lines.length + 1
        [{
          start_line: insertion_line,
          end_line: insertion_line - 1,
          owners: additions
        }]
      end

      def append_declaration_additions(fragments, documents, decision)
        additions = added_theirs_owners(documents, decision).reject { |owner| import_owner?(owner) }
        return if additions.empty?

        ensure_plan_boundary!(fragments, documents)
        additions.each_with_index do |owner, index|
          append_owner(fragments, owner)
          ensure_plan_boundary!(fragments, documents) if index < additions.length - 1
        end
      end

      def added_theirs_owners(documents, decision)
        ours = documents.fetch(:ours)
        documents.fetch(:theirs).owners.select do |owner|
          !ours.by_id.key?(owner.id) && decision.choices[owner.id] == :theirs
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
        import_offset = expected.rindex { |owner| package_or_import_owner?(owner) }
        documents.fetch(:theirs).owners.each do |owner|
          next if ours.by_id.key?(owner.id)
          next unless decision.choices[owner.id] == :theirs

          if import_owner?(owner)
            import_offset = import_offset ? import_offset + 1 : 0
            expected.insert(import_offset, owner)
          else
            expected << owner
          end
        end
        expected
      end

      def import_owner?(_owner)
        false
      end

      alias package_or_import_owner? import_owner?

      def verify_rendered(output, expected, dialect)
        parsed = parse_source(output, :output, dialect)
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

        conflict_id = "bash-unsafe-#{Digest::SHA256.hexdigest([role, failure_detail(parsed)].join("\0"))[0, 16]}"
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
          message: 'Bash top-level declaration changed incompatibly on both sides.',
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
            dialect: request[:dialect] || :bash,
            backend: request[:backend] || TREE_SITTER_BACKEND.id.to_sym,
            package: 'bash-merge',
            package_version: Bash::Merge::Version::VERSION
          },
          profile: { profile_id: request[:profile_id] || DEFAULT_PROFILE }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  end
end
