# frozen_string_literal: true

require 'digest'

module Prism
  module Merge
    # Base-aware, source-preserving Ruby provider backed by Prism top-level owners.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- provider decisions, source plans, and verification form one boundary
    class Provider
      DEFAULT_PROFILE = :source_preserving
      Owner = Data.define(:id, :signature, :fingerprint, :start_line, :end_line, :role)
      Document = Data.define(:source, :analysis, :owners, :by_id, :unmanaged_fingerprint)
      Decision = Data.define(:changes, :conflicts, :choices)

      def provider_id = 'ruby.ruby.prism'
      def family = 'ruby'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[ruby],
          backends: %i[prism],
          profiles: [DEFAULT_PROFILE],
          role: :backend,
          source_preservation: %i[exact_source owner_fragments line_provenance reparse semantic_verification]
        }.freeze
      end

      def analyze(request)
        document = parse_document(:analyze, request, :source)
        return document if provider_failure?(document)

        result(
          :analyze,
          request,
          analysis: {
            backend: 'prism',
            valid: true,
            owners: document.owners.map { |owner| owner_description(owner) }
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
        merged = Prism::Merge.merge_ruby(
          request.fetch(:incoming_source),
          request.fetch(:current_source),
          'ruby',
          backend: request[:backend],
          add_template_only_nodes: true
        )
        return merge2_failure(request, merged) unless merged[:ok]

        output = merged.fetch(:output)
        parsed = parse_source(output, :output)
        return render_failure(:merge2, request, parsed) if provider_failure?(parsed)

        result(
          :merge2,
          request,
          output: output,
          render_report: { strategy: :prism_smart_merger, synthesis: :family_emission },
          verification: { output_reparsed: true }
        )
      end

      def merge3(request)
        documents = parse_merge3_documents(request)
        return documents if provider_failure?(documents)

        exact_role = exact_revision_role(request)
        decision = decide(documents, include_unmanaged_conflict: exact_role.nil?)
        return render_conflicts(request, documents, decision) unless decision.conflicts.empty?

        return render_exact(request, documents, decision, exact_role) if exact_role

        render_composite(request, documents, decision)
      end

      private

      def parse_merge3_documents(request)
        %i[base ours theirs].each_with_object({}) do |role, documents|
          document = parse_document(:merge3, request, role)
          return document if provider_failure?(document)

          documents[role] = document
        end
      end

      def parse_document(operation, request, role)
        source = request.fetch(role == :source ? :source : :"#{role}_source")
        parsed = parse_source(source, role)
        return parse_failure(operation, request, role, parsed) if provider_failure?(parsed)

        parsed
      end

      def parse_source(source, role)
        analysis = Prism::Merge::FileAnalysis.new(source, source_label: role.to_s)
        unless analysis.valid?
          return {
            parse_error: analysis.errors.map(&:message).join('; '),
            source_role: role
          }
        end

        owners = analysis.nodes_with_comments.map do |node_info|
          signature = node_info.fetch(:signature)
          Owner.new(
            id: owner_id(signature),
            signature: signature,
            fingerprint: owner_fingerprint(source, node_info),
            start_line: node_info.fetch(:line_range).begin,
            end_line: node_info.fetch(:line_range).end,
            role: role
          )
        end
        duplicate = owners.group_by(&:id).find { |_id, matches| matches.length > 1 }
        return { ambiguous_owner: duplicate.first, source_role: role } if duplicate

        Document.new(
          source: source,
          analysis: analysis,
          owners: owners.freeze,
          by_id: owners.to_h { |owner| [owner.id, owner] }.freeze,
          unmanaged_fingerprint: unmanaged_fingerprint(source, owners)
        )
      rescue Prism::Merge::Error => e
        { parse_error: e.message, source_role: role }
      end

      def unmanaged_fingerprint(source, owners)
        owned_lines = owners.each_with_object({}) do |owner, lines|
          (owner.start_line..owner.end_line).each { |line| lines[line] = true }
        end
        source.lines.each_with_index.filter_map do |line, index|
          line unless owned_lines[index + 1]
        end.join
      end

      def semantic_fingerprint(value)
        case value
        when ::Prism::Node
          fields = value.deconstruct_keys(nil).reject do |key, _item|
            key == :node_id || key == :location || key.to_s.end_with?('_loc')
          end
          [value.type, fields.map { |key, item| [key, semantic_fingerprint(item)] }]
        when Array
          value.map { |item| semantic_fingerprint(item) }
        when Hash
          value.map { |key, item| [key, semantic_fingerprint(item)] }
        else
          value
        end
      end

      def owner_fingerprint(source, node_info)
        range = node_info.fetch(:line_range)
        {
          ast: semantic_fingerprint(node_info.fetch(:node)),
          source: source.lines.slice(range.begin - 1, range.end - range.begin + 1).join.delete_suffix("\n"),
          leading_comments: node_info.fetch(:leading_comments).map(&:slice),
          inline_comments: node_info.fetch(:inline_comments).map(&:slice)
        }.freeze
      end

      def owner_id(signature)
        Digest::SHA256.hexdigest(Marshal.dump(signature))
      end

      def owner_path(owner)
        owner ? owner.signature.inspect : '<document>'
      end

      def owner_description(owner)
        {
          path: owner_path(owner),
          signature: owner.signature,
          line_range: [owner.start_line, owner.end_line]
        }
      end

      def diff_documents(before, after)
        ordered_ids(before, after).filter_map do |id|
          left = before.by_id[id]
          right = after.by_id[id]
          next if left && right && left.fingerprint == right.fingerprint

          {
            path: owner_path(left || right),
            ours: :unchanged,
            theirs: change_kind(left, right)
          }.freeze
        end.freeze
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
        return if ours == theirs || base == theirs

        change = {
          path: '<unmanaged-source>',
          ours: base == ours ? :unchanged : :edited,
          theirs: base == theirs ? :unchanged : :edited
        }.freeze
        changes << change
        conflicts << {
          conflict_id: "ruby-unmanaged-#{Digest::SHA256.hexdigest([base, ours, theirs].join("\0"))[0, 16]}",
          category: :unmanaged_source_change,
          path: change.fetch(:path),
          owner_id: nil,
          change_classification: change
        }.freeze
      end

      def side_change(base, side)
        return :unchanged if base && side && base.fingerprint == side.fingerprint
        return :added if !base && side
        return :deleted if base && !side
        return :unchanged unless base || side

        :edited
      end

      def owner_choice(base, ours, theirs)
        return :ours if equivalent?(ours, theirs)
        return :theirs if equivalent?(base, ours)
        return :ours if equivalent?(base, theirs)
        return nil if ours.nil? && theirs.nil?

        :conflict
      end

      def equivalent?(left, right)
        return true if left.nil? && right.nil?
        return false unless left && right

        left.fingerprint == right.fingerprint
      end

      def conflict_for(id, base, ours, theirs, change)
        {
          conflict_id: "ruby-owner-#{id[0, 16]}",
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
        { present: !owner.nil?, fingerprint: owner&.fingerprint }.freeze
      end

      def exact_revision_role(request)
        base = request.fetch(:base_source)
        ours = request.fetch(:ours_source)
        theirs = request.fetch(:theirs_source)
        return :ours if ours == theirs || base == theirs

        :theirs if base == ours
      end

      def render_exact(request, documents, decision, role)
        rendered = render_plan(request, [whole_source_fragment(role, request.fetch(:"#{role}_source"))])
        verification = verify_rendered(rendered.content, documents.fetch(role).owners, role: :output)
        result(
          :merge3,
          request,
          output: rendered.content,
          changes: decision.changes,
          render_report: render_report(rendered, :exact_revision),
          verification: verification.merge(base_participated: true)
        )
      end

      def render_composite(request, documents, decision)
        fragments = composite_fragments(documents, decision)
        rendered = render_plan(request, fragments)
        expected = expected_owners(documents, decision)
        verification = verify_rendered(rendered.content, expected, role: :output)
        unless verification[:semantic_match]
          return failure(
            :merge3,
            request,
            category: :render_failure,
            message: 'Prism composite did not match the planned top-level owner structure.',
            changes: decision.changes,
            render_report: render_report(rendered, :exact_owner_composite),
            verification: verification.merge(base_participated: true)
          )
        end

        result(
          :merge3,
          request,
          output: rendered.content,
          changes: decision.changes,
          render_report: render_report(rendered, :exact_owner_composite),
          verification: verification.merge(base_participated: true)
        )
      end

      def composite_fragments(documents, decision)
        ours = documents.fetch(:ours)
        edits = replacement_edits(documents, decision)
        fragments = []
        cursor = 1
        edits.sort_by { |edit| edit.fetch(:start_line) }.each do |edit|
          append_range(fragments, :ours, cursor, edit.fetch(:start_line) - 1)
          replacement = edit[:owner]
          append_owner(fragments, replacement) if replacement
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

          chosen = role && documents.fetch(role).by_id[id]
          next if role == :ours

          { start_line: ours_owner.start_line, end_line: ours_owner.end_line, owner: chosen }
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
          reason: :owner_separator,
          producer: provider_id,
          metadata: { copied_source: true }
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

      def verify_rendered(output, expected, role:)
        parsed = parse_source(output, role)
        if provider_failure?(parsed)
          return {
            output_reparsed: false,
            semantic_match: false,
            parse_error: parsed[:parse_error]
          }
        end

        actual = parsed.owners.map { |owner| [owner.id, owner.fingerprint] }
        planned = expected.map { |owner| [owner.id, owner.fingerprint] }
        {
          output_reparsed: true,
          semantic_match: actual == planned,
          planned_owner_count: planned.length,
          output_owner_count: actual.length
        }
      end

      def render_conflicts(request, documents, decision)
        localized = localized_conflict_fragments(request, documents, decision)
        if localized
          rendered = render_plan(request, localized)
          return conflict_failure(request, decision, rendered, :owner_localized_conflict)
        end

        rendered = render_plan(request, [whole_document_conflict(request, decision)])
        conflict_failure(
          request,
          decision,
          rendered,
          :full_file_conflict,
          fallbacks: [{ from: :owner_localization, to: :full_file_conflict, reason: :owner_not_addressable }]
        )
      end

      def localized_conflict_fragments(request, documents, decision)
        ours = documents.fetch(:ours)
        return unless decision.conflicts.all? do |conflict|
          ours.by_id.key?(conflict.fetch(:owner_id))
        end

        ranges = decision.conflicts.map do |conflict|
          [conflict, ours.by_id.fetch(conflict.fetch(:owner_id))]
        end
        return unless ranges.sort_by { |_conflict, owner| owner.start_line }.each_cons(2).none? do |left, right|
          left.last.end_line >= right.last.start_line
        end

        fragments = []
        cursor = 1
        ranges.sort_by { |_conflict, owner| owner.start_line }.each do |conflict, owner|
          append_range(fragments, :ours, cursor, owner.start_line - 1)
          fragments << owner_conflict_fragment(request, documents, conflict)
          cursor = owner.end_line + 1
        end
        append_range(fragments, :ours, cursor, ours.source.lines.length)
        fragments
      end

      def owner_conflict_fragment(request, documents, conflict)
        Ast::Merge::SourceRender::ConflictFragment.new(
          conflict_id: conflict.fetch(:conflict_id),
          base: conflict_owner_side(documents, conflict, :base),
          ours: conflict_owner_side(documents, conflict, :ours),
          theirs: conflict_owner_side(documents, conflict, :theirs),
          labels: request.fetch(:labels, {}),
          marker_size: request.fetch(:conflict_marker_size, 7),
          metadata: { path: conflict.fetch(:path), category: conflict.fetch(:category) }
        )
      end

      def conflict_owner_side(documents, conflict, role)
        document = documents.fetch(role)
        owner = document.by_id[conflict.fetch(:owner_id)]
        owner ? [conflict_source_fragment(owner, document.source)] : []
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

        Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: "#{fragment_source}\n",
          reason: :conflict_line_boundary,
          producer: provider_id,
          metadata: { source_role: owner.role, copied_source: true }
        )
      end

      def conflict_whole_source_fragment(role, source)
        return whole_source_fragment(role, source) if source.empty? || source.end_with?("\n")

        Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: "#{source}\n",
          reason: :conflict_line_boundary,
          producer: provider_id,
          metadata: { source_role: role, copied_source: true }
        )
      end

      def whole_source_fragment(role, source)
        return empty_source_fragment(role) if source.empty?

        source_range_fragment(role, 1, source.lines.length)
      end

      def empty_source_fragment(role)
        Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: '',
          reason: :exact_empty_source,
          producer: provider_id,
          metadata: { source_role: role }
        )
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
          message: 'Ruby top-level owner changed incompatibly on both sides.',
          changes: decision.changes,
          conflicts: decision.conflicts,
          conflicted_output: rendered.content,
          render_report: render_report(rendered, strategy),
          verification: { base_participated: true },
          fallbacks: fallbacks
        )
      end

      def merge2_failure(request, merged)
        failure(
          :merge2,
          request,
          category: :merge_failure,
          message: Array(merged[:diagnostics]).map { |item| item[:message] }.compact.join('; ')
        )
      end

      def parse_failure(operation, request, role, parsed)
        detail = parsed[:parse_error] || "ambiguous duplicate owner #{parsed[:ambiguous_owner].inspect}"
        failure(
          operation,
          request,
          category: parsed[:parse_error] ? :parse_error : :ambiguous_owner,
          message: "#{role} parse error: #{detail}",
          source_role: role
        )
      end

      def render_failure(operation, request, parsed)
        failure(
          operation,
          request,
          category: :render_failure,
          message: "Prism emitter produced invalid output: #{parsed[:parse_error]}",
          source_role: :output
        )
      end

      def provider_failure?(value)
        value.is_a?(Hash) && (value[:ok] == false || value.key?(:parse_error) || value.key?(:ambiguous_owner))
      end

      def result(operation, request, changes: [], render_report: {}, verification: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: true,
          envelope: envelope(request, changes: changes, render_report: render_report, verification: verification),
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
            dialect: request[:dialect] || :ruby,
            backend: request[:backend] || :prism,
            package: Prism::Merge::PACKAGE_NAME,
            package_version: Prism::Merge::Version::VERSION
          },
          profile: { profile_id: request[:profile_id] || DEFAULT_PROFILE }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  end
end
