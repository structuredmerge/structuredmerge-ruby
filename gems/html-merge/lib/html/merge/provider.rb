# frozen_string_literal: true

require "digest"
require "json"
require_relative "node_wrapper"
require_relative "file_analysis"

module Html
  module Merge
    # Conservative, base-aware HTML provider. Only parser-proven unique IDs and
    # singleton head semantics become independently editable source owners.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- ownership, rendering, and verification are one safety boundary
    class Provider
      DEFAULT_PROFILE = :source_preserving
      VOID_ELEMENTS = %w[area base br col embed hr img input link meta param source track wbr].freeze
      Owner = Data.define(:id, :signature, :fingerprint, :start_byte, :end_byte, :node_start, :node_end,
                          :parent_key, :role, :source_text)
      Document = Data.define(:source, :analysis, :owners, :by_id, :unmanaged_fingerprint, :parents)
      ExactDocument = Data.define(:source, :analysis, :issues, :role)
      Decision = Data.define(:changes, :conflicts, :choices)

      def provider_id = "ruby.html"
      def family = "html"

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[html],
          backends: [BACKEND_REFERENCE.id.to_sym],
          profiles: [DEFAULT_PROFILE],
          role: :workflow,
          ast_ownership: :unique_explicit_ids_and_safe_singletons,
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
            backend: BACKEND_REFERENCE.id,
            valid: true,
            owners: document.owners.map { |owner| owner_description(owner) }
          },
          diagnostics: nonblocking_issues(document.analysis, :source),
          verification: { source_parsed: true, ast_attributes_verified: true }
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
          verification: { before_parsed: true, after_parsed: true, ast_attributes_verified: true }
        )
      end

      def merge2(request)
        merged = merge3(
          request.merge(
            base_source: request.fetch(:current_source),
            ours_source: request.fetch(:current_source),
            theirs_source: request.fetch(:incoming_source)
          )
        )
        merged.merge(operation: :merge2, verification: merged.fetch(:verification).except(:base_participated))
      end

      def merge3(request)
        exact_role = exact_revision_role(request)
        return merge3_exact(request, exact_role) if exact_role

        documents = parse_merge3_documents(request)
        return documents if provider_failure?(documents)

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
        analysis = FileAnalysis.new(source)
        return { parse_error: analysis.errors.map(&:to_s).join("; "), source_role: role } unless analysis.valid?
        return { ambiguous_owner: analysis.issues.first, source_role: role } unless analysis.issues.empty?

        owners = analysis.wrappers.map do |wrapper|
          return { unsafe_range: wrapper.tag_name, source_role: role } unless safe_wrapper?(wrapper, source)

          start_byte, end_byte = expanded_range(source, wrapper.start_byte, wrapper.end_byte)
          signature = owner_signature(wrapper)
          Owner.new(
            id: owner_id(signature),
            signature: signature,
            fingerprint: fingerprint(wrapper.semantic_tree),
            start_byte: start_byte,
            end_byte: end_byte,
            node_start: wrapper.start_byte,
            node_end: wrapper.end_byte,
            parent_key: parent_key(wrapper),
            role: role,
            source_text: source.byteslice(start_byte...end_byte).to_s
          )
        end
        duplicate = owners.group_by(&:id).find { |_id, matches| matches.length > 1 }
        return { ambiguous_owner: duplicate.first, source_role: role } if duplicate
        return { unsafe_range: :overlapping_owners, source_role: role } unless non_overlapping?(owners)

        Document.new(
          source: source,
          analysis: analysis,
          owners: owners.freeze,
          by_id: owners.to_h { |owner| [owner.id, owner] }.freeze,
          unmanaged_fingerprint: unmanaged_fingerprint(source, owners),
          parents: parent_anchors(analysis, source).freeze
        )
      rescue StandardError => e
        { parse_error: e.message, source_role: role }
      end

      def parse_exact_source(source, role)
        analysis = FileAnalysis.new(source)
        return { parse_error: analysis.errors.map(&:to_s).join("; "), source_role: role } unless analysis.valid?

        ExactDocument.new(source: source, analysis: analysis, issues: analysis.issues, role: role)
      rescue StandardError => e
        { parse_error: e.message, source_role: role }
      end

      def owner_signature(wrapper)
        id = wrapper.explicit_id
        return [:id, id] if id.is_a?(String) && !id.empty?

        [:singleton, wrapper.tag_name]
      end

      def owner_id(signature)
        Digest::SHA256.hexdigest(JSON.generate(Ast::Merge.json_ready(signature)))
      end

      def fingerprint(value)
        Digest::SHA256.hexdigest(JSON.generate(Ast::Merge.json_ready(value)))
      end

      def safe_wrapper?(wrapper, source)
        return false unless wrapper.start_byte >= 0 && wrapper.end_byte <= source.bytesize
        return false unless wrapper.end_byte > wrapper.start_byte

        wrapper.self_closing? || wrapper.explicit_end_tag? || VOID_ELEMENTS.include?(wrapper.tag_name)
      end

      def expanded_range(source, start_byte, end_byte)
        line_start = source.rindex("\n", [start_byte - 1, 0].max)
        line_start = line_start ? line_start + 1 : 0
        if end_byte.positive? && source.getbyte(end_byte - 1) == 10 &&
           whitespace?(source.byteslice(line_start...start_byte).to_s)
          return [line_start, end_byte]
        end

        line_end = source.index("\n", end_byte)
        if whitespace?(source.byteslice(line_start...start_byte).to_s) &&
           whitespace?(source.byteslice(end_byte...(line_end || source.bytesize)).to_s)
          [line_start, line_end ? line_end + 1 : source.bytesize]
        else
          [start_byte, end_byte]
        end
      end

      def whitespace?(value)
        value.each_byte.all? { |byte| [9, 13, 32].include?(byte) }
      end

      def non_overlapping?(owners)
        owners.each_cons(2).all? { |left, right| left.end_byte <= right.start_byte }
      end

      def unmanaged_fingerprint(source, owners)
        output = source.dup
        owners.reverse_each { |owner| output[owner.start_byte...owner.end_byte] = "" }
        fingerprint(output)
      end

      def parent_key(wrapper)
        current = wrapper.parent
        while current
          id = current.explicit_id
          return [:id, id] if id.is_a?(String) && !id.empty?
          return [:boundary, current.tag_name] if %w[html head body].include?(current.tag_name)

          current = current.parent
        end
        [:document]
      end

      def parent_anchors(analysis, source)
        anchors = { [:document] => source.bytesize }
        walk = lambda do |node|
          wrapper = NodeWrapper.new(node, source: source)
          if wrapper.element?
            id = wrapper.explicit_id
            anchors[[:id, id]] = insertion_anchor(node) if id.is_a?(String) && !id.empty?
            anchors[[:boundary, wrapper.tag_name]] = insertion_anchor(node) if %w[html head
                                                                                  body].include?(wrapper.tag_name)
          end
          node.children.each { |child| walk.call(child) }
        end
        walk.call(analysis.root_node)
        anchors.compact
      end

      def insertion_anchor(node)
        node.children.find { |child| child.type == "end_tag" }&.start_byte
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

      def ordered_ids(*documents)
        documents.flat_map { |document| document.owners.map(&:id) }.uniq
      end

      def equivalent?(left, right)
        return true if left.nil? && right.nil?
        return false unless left && right

        left.fingerprint == right.fingerprint
      end

      def change_side(owner)
        if owner
          { present: true, source_role: owner.role,
            byte_range: [owner.start_byte, owner.end_byte] }
        else
          { present: false }
        end
      end

      def change_kind(before, after)
        return :added unless before
        return :deleted unless after

        :edited
      end

      def decide(documents)
        changes = []
        conflicts = []
        choices = {}
        append_unmanaged_conflict(changes, conflicts, documents)
        ordered_ids(*documents.values).each do |id|
          base = documents.fetch(:base).by_id[id]
          ours = documents.fetch(:ours).by_id[id]
          theirs = documents.fetch(:theirs).by_id[id]
          ours_change = side_change_kind(base, ours)
          theirs_change = side_change_kind(base, theirs)
          next choices[id] = :ours if ours_change == :unchanged && theirs_change == :unchanged

          change = { path: owner_path(base || ours || theirs), ours: ours_change, theirs: theirs_change }.freeze
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
          path: "<unmanaged-source>",
          ours: base == ours ? :unchanged : :edited,
          theirs: base == theirs ? :unchanged : :edited
        }.freeze
        changes << change
        conflicts << {
          conflict_id: "html-unmanaged-#{fingerprint([base, ours, theirs])[0, 16]}",
          category: :unmanaged_source_change,
          path: change.fetch(:path),
          owner_id: nil,
          change_classification: change
        }.freeze
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
          conflict_id: "html-owner-#{id[0, 16]}",
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
        documents = %i[base ours theirs].to_h do |source_role|
          [source_role, parse_exact_source(request.fetch(:"#{source_role}_source"), source_role)]
        end
        winner = documents.fetch(role)
        return parse_failure(:merge3, request, role, winner) if provider_failure?(winner)

        output = request.fetch(:"#{role}_source")
        verification = verify_exact(output, winner)
        return render_failure(request, verification, :exact_revision) unless verification[:semantic_match]

        result(
          :merge3,
          request,
          output: output,
          diagnostics: exact_diagnostics(documents),
          render_report: exact_render_report(role, output),
          verification: verification.merge(base_participated: true)
        )
      end

      def verify_exact(output, expected)
        parsed = parse_exact_source(output, :output)
        if provider_failure?(parsed)
          return { output_reparsed: false, byte_exact: output == expected.source,
                   semantic_match: false }
        end

        {
          output_reparsed: true,
          byte_exact: output == expected.source,
          semantic_match: parsed.analysis.document_semantics == expected.analysis.document_semantics,
          ordered_semantic_verified: true,
          ast_attributes_verified: true,
          source_role: expected.role
        }
      end

      def exact_diagnostics(documents)
        documents.flat_map do |role, document|
          if provider_failure?(document)
            [{ category: :parse_error, severity: :warning, message: "#{role} parse error", blocking: false,
               source_role: role }]
          else
            nonblocking_issues(document.analysis, role)
          end
        end.freeze
      end

      def nonblocking_issues(analysis, role)
        analysis.issues.map do |issue|
          issue.merge(severity: :warning, blocking: false, source_role: role).freeze
        end
      end

      def render_composite(request, documents, decision)
        ours = documents.fetch(:ours)
        edits = replacement_edits(documents, decision)
        insertion_edits(documents, decision).each do |edit|
          return unsafe_composite_failure(request, decision, :unproven_parent_insertion) unless edit[:start_byte]

          edits << edit
        end
        output = apply_edits(ours.source, edits)
        expected = expected_owner_states(documents, decision)
        verification = verify_composite(output, expected)
        unless verification[:semantic_match]
          return render_failure(request, verification, :exact_html_composite,
                                decision.changes)
        end

        result(
          :merge3,
          request,
          output: output,
          changes: decision.changes,
          render_report: composite_render_report(edits, output),
          verification: verification.merge(base_participated: true)
        )
      end

      def replacement_edits(documents, decision)
        ours = documents.fetch(:ours)
        decision.choices.filter_map do |id, role|
          ours_owner = ours.by_id[id]
          next unless ours_owner
          next if role == :ours

          chosen = role && documents.fetch(role).by_id[id]
          {
            start_byte: ours_owner.start_byte,
            end_byte: ours_owner.end_byte,
            content: chosen&.source_text.to_s,
            source_role: role,
            owner_id: id,
            action: chosen ? :replace : :delete
          }
        end
      end

      def insertion_edits(documents, decision)
        ours = documents.fetch(:ours)
        additions = documents.fetch(:theirs).owners.select do |owner|
          !ours.by_id.key?(owner.id) && decision.choices[owner.id] == :theirs
        end
        additions.group_by(&:parent_key).map do |parent_key, owners|
          {
            start_byte: ours.parents[parent_key],
            end_byte: ours.parents[parent_key],
            content: owners.map(&:source_text).join,
            source_role: :theirs,
            owner_id: owners.map(&:id),
            action: :insert
          }
        end
      end

      def apply_edits(source, edits)
        output = source.dup
        edits.sort_by { |edit| [edit.fetch(:start_byte), edit.fetch(:end_byte)] }.reverse_each do |edit|
          output[edit.fetch(:start_byte)...edit.fetch(:end_byte)] = edit.fetch(:content)
        end
        output
      end

      def expected_owner_states(documents, decision)
        states = decision.choices.filter_map do |id, role|
          owner = role && documents.fetch(role).by_id[id]
          owner && [owner.signature, owner.fingerprint]
        end
        states.sort_by { |value| JSON.generate(Ast::Merge.json_ready(value.first)) }
      end

      def verify_composite(output, expected)
        parsed = parse_source(output, :output)
        if provider_failure?(parsed)
          return { output_reparsed: false, semantic_match: false, parse_error: failure_detail(parsed) }
        end

        actual = parsed.owners.map { |owner| [owner.signature, owner.fingerprint] }
                              .sort_by { |value| JSON.generate(Ast::Merge.json_ready(value.first)) }
        {
          output_reparsed: true,
          semantic_match: actual == expected,
          ordered_semantic_verified: true,
          ast_attributes_verified: actual == expected,
          planned_owner_count: expected.length,
          output_owner_count: actual.length
        }
      end

      def render_conflicts(request, documents, decision)
        localized = localized_conflict_output(request, documents, decision)
        return conflict_failure(request, decision, localized, :element_localized_conflict) if localized

        conflict_failure(request, decision, whole_document_conflict(request), :full_file_conflict,
                         [{ from: :element_localization, to: :full_file_conflict,
                            reason: :source_ownership_unproven }])
      end

      def localized_conflict_output(request, documents, decision)
        return if decision.conflicts.any? { |conflict| conflict[:owner_id].nil? }

        ours = documents.fetch(:ours)
        return unless decision.conflicts.all? { |conflict| ours.by_id.key?(conflict.fetch(:owner_id)) }

        edits = decision.conflicts.map do |conflict|
          owner = ours.by_id.fetch(conflict.fetch(:owner_id))
          {
            start_byte: owner.start_byte,
            end_byte: owner.end_byte,
            content: conflict_text(request, documents, conflict)
          }
        end
        apply_edits(ours.source, edits)
      end

      def conflict_text(request, documents, conflict)
        marker = request.fetch(:conflict_marker_size, 7).to_i
        marker = 7 unless marker.positive?
        labels = { ours: "ours", base: "base", theirs: "theirs" }.merge(request.fetch(:labels, {}))
        sides = %i[ours base theirs].to_h do |role|
          owner = documents.fetch(role).by_id[conflict.fetch(:owner_id)]
          [role, owner&.source_text.to_s]
        end
        [
          "#{"<" * marker} #{labels[:ours]}\n", sides[:ours],
          "#{"|" * marker} #{labels[:base]}\n", sides[:base],
          "#{"=" * marker}\n", sides[:theirs],
          "#{">" * marker} #{labels[:theirs]}\n"
        ].join
      end

      def whole_document_conflict(request)
        marker = request.fetch(:conflict_marker_size, 7).to_i
        marker = 7 unless marker.positive?
        [
          "#{"<" * marker} ours\n", request.fetch(:ours_source),
          "#{"|" * marker} base\n", request.fetch(:base_source),
          "#{"=" * marker}\n", request.fetch(:theirs_source),
          "#{">" * marker} theirs\n"
        ].join
      end

      def conflict_failure(request, decision, output, strategy, fallbacks = [])
        failure(
          :merge3,
          request,
          category: :merge_conflict,
          message: "HTML owner changed incompatibly on both sides.",
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

        category = parsed[:ambiguous_owner] ? :ambiguous_owner : :unsafe_source_range
        conflict = {
          conflict_id: "html-unsafe-#{fingerprint([role, failure_detail(parsed)])[0, 16]}",
          category: category,
          path: "<document>",
          owner_id: nil,
          source_role: role
        }
        failure(
          :merge3,
          request,
          category: category,
          message: "#{role} HTML ownership is unsafe: #{failure_detail(parsed)}",
          conflicts: [conflict],
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
          message: "HTML composite insertion has no parser-proven parent closing boundary.",
          changes: decision.changes,
          conflicts: [{ conflict_id: "html-parent-#{reason}", category: reason, path: "<document>", owner_id: nil }],
          conflicted_output: whole_document_conflict(request),
          fallbacks: [{ from: :element_composite, to: :full_file_conflict, reason: reason }],
          render_report: { strategy: :full_file_conflict, provenance: :exact_source_bytes },
          verification: { base_participated: true }
        )
      end

      def render_failure(request, verification, strategy, changes = [])
        failure(
          :merge3,
          request,
          category: :render_failure,
          message: "HTML output failed native parser and ordered semantic verification.",
          changes: changes,
          render_report: { strategy: strategy },
          verification: verification.merge(base_participated: true)
        )
      end

      def exact_render_report(role, output)
        {
          strategy: :exact_revision,
          provenance: [{ source_role: role, byte_range: [0, output.bytesize], copied_source: true }],
          synthesized_fragments: []
        }
      end

      def composite_render_report(edits, output)
        {
          strategy: :exact_html_composite,
          provenance: edits.map { |edit| edit.slice(:source_role, :owner_id, :action, :start_byte, :end_byte) },
          output_bytes: output.bytesize,
          synthesized_fragments: []
        }
      end

      def owner_path(owner)
        owner ? owner.signature.inspect : "<document>"
      end

      def owner_description(owner)
        {
          path: owner_path(owner),
          signature: owner.signature,
          source_role: owner.role,
          byte_range: [owner.start_byte, owner.end_byte],
          parent: owner.parent_key
        }
      end

      def parse_failure(operation, request, role, parsed)
        category = if parsed[:parse_error]
                     :parse_error
                   else
                     parsed[:ambiguous_owner] ? :ambiguous_owner : :unsafe_source_range
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
        return parsed[:ambiguous_owner].inspect if parsed[:ambiguous_owner]

        parsed[:unsafe_range].inspect
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
            dialect: request[:dialect] || :html,
            backend: request[:backend] || BACKEND_REFERENCE.id.to_sym,
            package: "html-merge",
            package_version: Html::Merge::Version::VERSION
          },
          profile: { profile_id: request[:profile_id] || DEFAULT_PROFILE }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  end
end
