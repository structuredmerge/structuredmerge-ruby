# frozen_string_literal: true

require "version_gem"
require_relative "merge/version"

require "set"

require "prism"
require "ruby-merge"
require "ast/merge"
require "tree_haver"

module Prism
  module Merge
    extend self

    PACKAGE_NAME = "prism-merge"
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: "prism", family: "native").freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)
    TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)

    class Error < Ast::Merge::Error; end

    class CorruptionDetectedError < Error; end

    class ParseError < Ast::Merge::ParseError
      attr_reader :parse_result

      def initialize(message = nil, errors: [], content: nil, parse_result: nil)
        @parse_result = parse_result
        super(message, errors: parse_result&.errors || errors, content: content)
      end
    end

    class TemplateParseError < ParseError; end

    class DestinationParseError < ParseError; end

    class MissingAnalyzedLineError < Error; end

    autoload :BeginNodeClauseBodySupport, "prism/merge/begin_node_clause_body_support"
    autoload :BeginNodeClauseBodyMerger, "prism/merge/begin_node_clause_body_merger"
    autoload :BeginNodeClauseHeaderEmitter, "prism/merge/begin_node_clause_header_emitter"
    autoload :BeginNodeMergePlanner, "prism/merge/begin_node_merge_planner"
    autoload :BeginNodePlanEmitter, "prism/merge/begin_node_plan_emitter"
    autoload :BeginNodeRescueSemantics, "prism/merge/begin_node_rescue_semantics"
    autoload :BeginNodeStructure, "prism/merge/begin_node_structure"
    autoload :BlockDirectiveDetector, "prism/merge/block_directive_detector"
    autoload :Comment, "prism/merge/comment"
    autoload :CommentOnlyFileMerger, "prism/merge/comment_only_file_merger"
    autoload :DebugLogger, "prism/merge/debug_logger"
    autoload :FileAnalysis, "prism/merge/file_analysis"
    autoload :FreezeNode, "prism/merge/freeze_node"
    autoload :GemspecVarRenamer, "prism/merge/gemspec_var_renamer"
    autoload :MagicCommentSupport, "prism/merge/magic_comment_support"
    autoload :MergeResult, "prism/merge/merge_result"
    autoload :MethodMatchRefiner, "prism/merge/method_match_refiner"
    autoload :NestedStatementWalker, "prism/merge/nested_statement_walker"
    autoload :NocovNode, "prism/merge/nocov_node"
    autoload :NoCovWrapper, "prism/merge/nocov_wrapper"
    autoload :NodeBodyLayout, "prism/merge/node_body_layout"
    autoload :NodeEmissionSupport, "prism/merge/node_emission_support"
    autoload :NodeTypeNormalizer, "prism/merge/node_type_normalizer"
    autoload :NodeWrapper, "prism/merge/node_wrapper"
    autoload :PartialTemplateMerger, "prism/merge/partial_template_merger"
    autoload :PartialTemplateNode, "prism/merge/partial_template_node"
    autoload :RecursiveMergePolicy, "prism/merge/recursive_merge_policy"
    autoload :RecursiveNodeBodyMerger, "prism/merge/recursive_node_body_merger"
    autoload :RubyDocSurfaceAnalyzer, "prism/merge/ruby_doc_surface_analyzer"
    autoload :ScaffoldChunkRemover, "prism/merge/scaffold_chunk_remover"
    autoload :SmartMerger, "prism/merge/smart_merger"
    autoload :SourceLineLookup, "prism/merge/source_line_lookup"
    autoload :TopLevelMergeRunner, "prism/merge/top_level_merge_runner"
    autoload :WrapperCommentSupport, "prism/merge/wrapper_comment_support"

    def register_backend!
      BACKEND_REGISTRY.mutex.synchronize do
        return if BACKEND_REGISTRY.registered

        TreeHaver.register_language(
          :ruby,
          backend_module: TreeHaver::Backends::Prism,
          backend_type: :prism,
          gem_name: "prism",
        )

        BACKEND_REGISTRY.registered = true
      end
    end

    def ruby_feature_profile
      Ruby::Merge.ruby_feature_profile
    end

    def available_ruby_backends
      [BACKEND_REFERENCE]
    end

    def ruby_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      ruby_feature_profile.merge(backend: BACKEND_REFERENCE.id, backend_ref: BACKEND_REFERENCE.to_h)
    end

    def ruby_plan_context(backend: nil)
      profile = ruby_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: ruby_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def ruby_structured_edit_provider_profile
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_profile: {
          family: "ruby",
          structure_profile: Ast::Merge.structured_edit_structure_profile(
            owner_scope: "shared_default",
            owner_selector: "line_bound_statements",
            owner_selector_family: "line_oriented",
            known_owner_selector: true,
            supported_comment_regions: ["leading"],
            metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          ),
          selection_profile: Ast::Merge.structured_edit_selection_profile(
            owner_scope: "shared_default",
            owner_selector: "line_bound_statements",
            owner_selector_family: "line_oriented",
            selector_kind: "comment_region_owned_owner",
            selection_intent: "comment_anchored_owner",
            selection_intent_family: "comment_anchor",
            known_selection_intent: true,
            comment_region: "leading",
            include_trailing_gap: true,
            comment_anchored: true,
            metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          ),
          match_profile: Ast::Merge.structured_edit_match_profile(
            start_boundary: "comment_region_start",
            start_boundary_family: "comment_anchor",
            known_start_boundary: true,
            end_boundary: "owner_end_plus_trailing_gap",
            end_boundary_family: "gap_extension",
            known_end_boundary: true,
            payload_kind: "comment_owned_body",
            payload_family: "comment_owned",
            known_payload_kind: true,
            comment_anchored: true,
            trailing_gap_extended: true,
            metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          )
        }
      }
    end

    def ruby_structured_edit_request_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_request: Ast::Merge.structured_edit_request(
          operation_kind: "replace",
          content: "class App\n  # managed snippet\n  old_call\nend\n",
          source_label: "source",
          target_selector: "managed_snippet",
          target_selector_family: "comment_anchor",
          target_selection: Ast::Merge.structured_edit_target_selection(
            selector_kind: "comment_region_owned_owner",
            selection_intent: "comment_anchored_owner",
            selection_intent_family: "comment_anchor",
            known_selection_intent: true,
            comment_region: "leading",
            include_trailing_gap: true,
            comment_anchored: true,
            metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          ),
          target_match: Ast::Merge.structured_edit_target_match(
            start_boundary: "comment_region_start",
            start_boundary_family: "comment_anchor",
            known_start_boundary: true,
            end_boundary: "owner_end_plus_trailing_gap",
            end_boundary_family: "gap_extension",
            known_end_boundary: true,
            payload_kind: "comment_owned_body",
            payload_family: "comment_owned",
            known_payload_kind: true,
            comment_anchored: true,
            trailing_gap_extended: true,
            metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          ),
          payload_text: "new_call\n",
          metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_result_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_result: Ast::Merge.structured_edit_result(
          operation_kind: "replace",
          updated_content: "class App\n  # managed snippet\n  new_call\nend\n",
          changed: true,
          captured_text: "old_call\n",
          match_count: 1,
          operation_profile: Ast::Merge.structured_edit_operation_profile(
            operation_kind: "replace",
            operation_family: "rewrite",
            known_operation_kind: true,
            source_requirement: "required",
            destination_requirement: "none",
            replacement_source: "explicit_text",
            captures_source_text: true,
            supports_if_missing: false,
            metadata: { source: "legacy_crispr_reference" }
          ),
          metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_application_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_application: Ast::Merge.structured_edit_application(
          request: ruby_structured_edit_request_projection[:structured_edit_request],
          result: ruby_structured_edit_result_projection[:structured_edit_result],
          metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_execution_report_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_execution_report: Ast::Merge.structured_edit_execution_report(
          application: ruby_structured_edit_application_projection[:structured_edit_application],
          provider_family: "ruby",
          provider_backend: BACKEND_REFERENCE.id,
          diagnostics: [
            {
              severity: "warning",
              category: "assumed_default",
              message: "using managed snippet fallback selection."
            }
          ],
          metadata: { source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_batch_request_projection
      content = "class App\n  # managed snippet\n  old_call\n\n  anchor_call\n\n  # obsolete snippet\n  obsolete_call\nend\n"
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_batch_request: Ast::Merge.structured_edit_batch_request(
          requests: [
            Ast::Merge.structured_edit_request(
              operation_kind: "replace",
              content: content,
              source_label: "source",
              target_selector: "managed_snippet",
              target_selector_family: "comment_anchor",
              payload_text: "new_call\n",
              metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
            ),
            Ast::Merge.structured_edit_request(
              operation_kind: "insert",
              content: content,
              source_label: "source",
              destination_selector: "after_anchor_call",
              destination_selector_family: "gap_preserving_statement",
              payload_text: "inserted_call\n",
              if_missing: "append",
              metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
            ),
            Ast::Merge.structured_edit_request(
              operation_kind: "delete",
              content: content,
              source_label: "source",
              target_selector: "obsolete_snippet",
              target_selector_family: "comment_anchor",
              metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
            )
          ],
          metadata: { batch_label: "ruby_prism_triad", source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_batch_report_projection
      content = "class App\n  # managed snippet\n  old_call\n\n  anchor_call\n\n  # obsolete snippet\n  obsolete_call\nend\n"
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_batch_report: Ast::Merge.structured_edit_batch_report(
          reports: [
            Ast::Merge.structured_edit_execution_report(
              application: Ast::Merge.structured_edit_application(
                request: Ast::Merge.structured_edit_request(
                  operation_kind: "replace",
                  content: content,
                  source_label: "source",
                  target_selector: "managed_snippet",
                  target_selector_family: "comment_anchor",
                  payload_text: "new_call\n",
                  metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
                ),
                result: Ast::Merge.structured_edit_result(
                  operation_kind: "replace",
                  updated_content: "class App\n  # managed snippet\n  new_call\n\n  anchor_call\n\n  # obsolete snippet\n  obsolete_call\nend\n",
                  changed: true,
                  captured_text: "old_call\n",
                  match_count: 1,
                  operation_profile: Ast::Merge.structured_edit_operation_profile(
                    operation_kind: "replace",
                    operation_family: "rewrite",
                    known_operation_kind: true,
                    source_requirement: "required",
                    destination_requirement: "none",
                    replacement_source: "explicit_text",
                    captures_source_text: true,
                    supports_if_missing: false,
                    metadata: { source: "legacy_crispr_reference" }
                  ),
                  metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
                ),
                metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
              ),
              provider_family: "ruby",
              provider_backend: BACKEND_REFERENCE.id,
              diagnostics: [],
              metadata: { source: "legacy_crispr_reference" }
            ),
            Ast::Merge.structured_edit_execution_report(
              application: Ast::Merge.structured_edit_application(
                request: Ast::Merge.structured_edit_request(
                  operation_kind: "insert",
                  content: content,
                  source_label: "source",
                  destination_selector: "after_anchor_call",
                  destination_selector_family: "gap_preserving_statement",
                  payload_text: "inserted_call\n",
                  if_missing: "append",
                  metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
                ),
                result: Ast::Merge.structured_edit_result(
                  operation_kind: "insert",
                  updated_content: "class App\n  # managed snippet\n  old_call\n\n  anchor_call\n  inserted_call\n\n  # obsolete snippet\n  obsolete_call\nend\n",
                  changed: true,
                  operation_profile: Ast::Merge.structured_edit_operation_profile(
                    operation_kind: "insert",
                    operation_family: "insertion",
                    known_operation_kind: true,
                    source_requirement: "none",
                    destination_requirement: "optional",
                    replacement_source: "explicit_text",
                    captures_source_text: false,
                    supports_if_missing: true,
                    metadata: { source: "legacy_crispr_reference" }
                  ),
                  destination_profile: Ast::Merge.structured_edit_destination_profile(
                    resolution_kind: "selector",
                    resolution_source: "destination_selector",
                    anchor_boundary: "after",
                    resolution_family: "anchored",
                    resolution_source_family: "selector",
                    anchor_boundary_family: "gap_preserving_statement",
                    known_resolution_kind: true,
                    known_resolution_source: true,
                    known_anchor_boundary: true,
                    used_if_missing: false,
                    metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
                  ),
                  metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
                ),
                metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
              ),
              provider_family: "ruby",
              provider_backend: BACKEND_REFERENCE.id,
              diagnostics: [],
              metadata: { source: "legacy_crispr_reference" }
            ),
            Ast::Merge.structured_edit_execution_report(
              application: Ast::Merge.structured_edit_application(
                request: Ast::Merge.structured_edit_request(
                  operation_kind: "delete",
                  content: content,
                  source_label: "source",
                  target_selector: "obsolete_snippet",
                  target_selector_family: "comment_anchor",
                  metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
                ),
                result: Ast::Merge.structured_edit_result(
                  operation_kind: "delete",
                  updated_content: "class App\n  # managed snippet\n  old_call\n\n  anchor_call\nend\n",
                  changed: true,
                  captured_text: "obsolete_call\n",
                  match_count: 1,
                  operation_profile: Ast::Merge.structured_edit_operation_profile(
                    operation_kind: "delete",
                    operation_family: "removal",
                    known_operation_kind: true,
                    source_requirement: "required",
                    destination_requirement: "none",
                    replacement_source: "none",
                    captures_source_text: true,
                    supports_if_missing: false,
                    metadata: { source: "legacy_crispr_reference" }
                  ),
                  metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
                ),
                metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
              ),
              provider_family: "ruby",
              provider_backend: BACKEND_REFERENCE.id,
              diagnostics: [],
              metadata: { source: "legacy_crispr_reference" }
            )
          ],
          diagnostics: [
            {
              severity: "info",
              category: "assumed_default",
              message: "ruby batch preserved request ordering."
            }
          ],
          metadata: { batch_label: "ruby_prism_triad", source: "legacy_crispr_reference" }
        )
      }
    end

    def parse_ruby(source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == "ruby"
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      result = ::Prism.parse(source)
      unless result.success?
        return {
          ok: false,
          diagnostics: result.errors.map do |error|
            { severity: "error", category: "parse_error", message: error.message }
          end,
          policies: []
        }
      end

      {
        ok: true,
        diagnostics: [],
        analysis: Ruby::Merge.analyze_ruby_document(source),
        policies: []
      }
    end

    def parse_ruby_normalized(source, dialect = "ruby", backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == "ruby"
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      result = ::Prism.parse(source)
      unless result.success?
        return TreeHaver::NormalizedParseResult.new(
          ok: false,
          backend_capability: ruby_normalized_backend_capability(dialect),
          root_id: nil,
          nodes: [],
          parse_error_tolerance: ruby_prism_parse_error_tolerance,
          source_fragments_available: false,
          diagnostics: result.errors.map(&:message),
          metadata: prism_normalized_metadata
        ).to_h
      end

      root_node = result.value
      body = root_node.statements&.body || []
      method_nodes = body.each_with_index.flat_map do |node, class_index|
        next [] unless node.is_a?(::Prism::ClassNode)

        Array(node.body&.body).each_with_index.filter_map do |child, method_index|
          next unless child.is_a?(::Prism::DefNode)

          prism_method_node(source, child, class_index, method_index)
        end
      end
      comment_nodes = prism_comment_nodes(source, result.comments, result.magic_comments, body)
      class_nodes = body.each_with_index.filter_map do |node, index|
        next unless node.is_a?(::Prism::ClassNode)

        child_ids = comment_nodes.filter_map { |comment| comment.id if comment.parent_id == "prism:class:#{index}" }
        child_ids.concat(method_nodes.filter_map { |method| method.id if method.parent_id == "prism:class:#{index}" })
        prism_class_node(source, node, index, child_ids: child_ids)
      end
      top_comment_nodes = comment_nodes.filter { |comment| comment.parent_id == "prism:program:0" }

      root = TreeHaver::NormalizedTreeNode.new(
        id: "prism:program:0",
        kind: "program",
        role: "structural",
        parent_id: nil,
        child_ids: top_comment_nodes.map(&:id) + class_nodes.map(&:id),
        span: full_source_span(source),
        field_name: nil,
        named: true,
        anonymous: false,
        has_source_text: true,
        source_fragment: source,
        backend_kind: root_node.class.name,
        semantic_roles: ["compilation_unit"],
        backend_roles: ["prism.ProgramNode"],
        unsupported_features: [],
        metadata: {
          prism: {
            node_path: "program",
            native_tree_visibility: "provider_internal"
          }
        }
      )

      TreeHaver::NormalizedParseResult.new(
        ok: true,
        backend_capability: ruby_normalized_backend_capability(dialect),
        root_id: root.id,
        nodes: [root] + top_comment_nodes + class_nodes + comment_nodes.reject { |comment| comment.parent_id == "prism:program:0" } + method_nodes,
        parse_error_tolerance: ruby_prism_parse_error_tolerance,
        source_fragments_available: true,
        diagnostics: [],
        metadata: prism_normalized_metadata
      ).to_h
    end

    def apply_edit_projection(request)
      source = request.fetch(:source)
      provider_id = request.fetch(:provider_id)
      backend_id = request.fetch(:backend_ref).fetch(:id)
      language = request.fetch(:language)
      operations = request.fetch(:operations)

      unless provider_id == BACKEND_REFERENCE.id && backend_id == BACKEND_REFERENCE.id
        return edit_projection_rejection(source, "provider_id", "provider_edit_projection_unsupported", "provider #{provider_id} does not support Prism edit projection")
      end
      unless language == "ruby"
        return edit_projection_rejection(source, "language", "edit_projection_language_unsupported", "language #{language} is not supported by Prism edit projection")
      end
      unless operations.length == 1
        return edit_projection_rejection(source, "operations", "edit_projection_batch_unsupported", "Prism edit projection currently supports exactly one operation")
      end

      operation = operations.first
      unless %w[replace_node insert_child delete_node].include?(operation.fetch(:operation))
        return edit_projection_rejection(source, "operations[0].operation", "edit_projection_operation_unsupported", "Prism edit projection does not support #{operation.fetch(:operation)}")
      end

      normalized = parse_ruby_normalized(source, "ruby")
      return edit_projection_rejection(source, "source", "edit_projection_parse_failed", normalized[:diagnostics].join("; ")) unless normalized[:ok]

      target = normalized[:nodes].find do |node|
        node.dig(:metadata, :prism, :node_path) == operation.fetch(:target_node_path)
      end
      return edit_projection_rejection(source, "operations[0].target_node_path", "edit_projection_target_not_found", "Prism node path #{operation.fetch(:target_node_path)} was not found") unless target

      range = target.dig(:span, :range)
      output = if operation.fetch(:operation) == "delete_node"
        delete_range = line_deletion_range(source, range)
        source.byteslice(0...delete_range[:start_byte]) + source.byteslice(delete_range[:end_byte]..)
      elsif operation.fetch(:operation) == "insert_child"
        insertion_byte = class_body_insertion_byte(source, range)
        source.byteslice(0...insertion_byte) +
          operation.fetch(:replacement_source) +
          "\n" +
          source.byteslice(insertion_byte..)
      else
        source.byteslice(0...range[:start_byte]) +
          operation.fetch(:replacement_source) +
          source.byteslice(range[:end_byte]..)
      end
      reparsed = parse_ruby_normalized(output, "ruby")
      return edit_projection_rejection(source, "operations[0].replacement_source", "edit_projection_reparse_failed", reparsed[:diagnostics].join("; ")) unless reparsed[:ok]

      TreeHaver.build_edit_projection_execution_result(
        output,
        [
          TreeHaver::AppliedEditProjectionOperation.new(
            operation: operation.fetch(:operation),
            target_node_id: operation.fetch(:target_node_id),
            correlation_key: "metadata.prism.node_path",
            correlation_value: operation.fetch(:target_node_path)
          )
        ],
        []
      ).to_h
    end

    def match_ruby_owners(template, destination)
      Ruby::Merge.match_ruby_owners(template, destination)
    end

    def merge_ruby(
      template_source,
      destination_source,
      dialect,
      backend: nil,
      preference: :destination,
      add_template_only_nodes: true,
      signature_generator: nil,
      **options
    )
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == "ruby"

      merger = SmartMerger.new(
        template_source,
        destination_source,
        preference: preference,
        add_template_only_nodes: add_template_only_nodes,
        signature_generator: signature_generator,
        **options
      )
      {
        ok: true,
        diagnostics: [],
        output: merger.merge.to_s,
        policies: Ruby::Merge.ruby_feature_profile.fetch(:supported_policies),
      }
    rescue Prism::Merge::ParseError => e
      {
        ok: false,
        diagnostics: [
          {
            severity: "error",
            category: e.is_a?(Prism::Merge::DestinationParseError) ? "destination_parse_error" : "parse_error",
            message: e.message,
          },
        ],
        policies: [],
      }
    end

    def ruby_dsl_signature_generator
      @ruby_dsl_signature_generator ||= lambda do |node|
        ruby_dsl_signature_for(node) || node
      end
    end

    def ruby_dsl_signature_for(node)
      call = ruby_dsl_call_node(node)
      return unless call

      case call.name
      when :source, :gemspec
        [:ruby_dsl_singleton, call.name]
      when :git_source, :gem, :eval_gemfile, :platform, :group, :task
        [:ruby_dsl_call, call.name, ruby_dsl_first_argument(call)]
      when :desc
        [:ruby_dsl_desc, call.slice]
      end
    end

    def ruby_dsl_call_node(node)
      return node if node.is_a?(::Prism::CallNode)

      if node.is_a?(::Prism::IfNode) || node.is_a?(::Prism::UnlessNode)
        body = node.statements&.body
        return body.first if body&.length == 1 && body.first.is_a?(::Prism::CallNode)
      end

      nil
    end

    def ruby_dsl_first_argument(call)
      argument = call.arguments&.arguments&.first
      case argument
      when ::Prism::StringNode
        argument.unescaped
      when ::Prism::SymbolNode
        argument.unescaped.to_sym
      else
        argument&.slice
      end
    end

    def merge_ruby_with_reviewed_nested_outputs(template_source, destination_source, dialect, review_state, applied_children, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        review_state,
        applied_children
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(template_source, destination_source, dialect, replay_bundle, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
        template_source,
        destination_source,
        dialect,
        replay_bundle
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(template_source, destination_source, dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(
        template_source,
        destination_source,
        dialect,
        envelope
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_review_state(template_source, destination_source, dialect, review_state, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs_from_review_state(
        template_source,
        destination_source,
        dialect,
        review_state
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(template_source, destination_source, dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(
        template_source,
        destination_source,
        dialect,
        envelope
      )
    end

    def ruby_discovered_surfaces(analysis)
      Ruby::Merge.ruby_discovered_surfaces(analysis)
    end

    def ruby_delegated_child_operations(analysis, parent_operation_id: "ruby-document-0")
      Ruby::Merge.ruby_delegated_child_operations(analysis, parent_operation_id: parent_operation_id)
    end

    def unsupported_feature_result(message)
      Ruby::Merge.unsupported_feature_result(message)
    end

    def edit_projection_rejection(source, path, code, message)
      TreeHaver.build_edit_projection_execution_result(
        source,
        [],
        [
          TreeHaver::ProviderDiagnostic.new(
            severity: "error",
            category: "unsupported_feature",
            code: code,
            message: message,
            path: path,
            blocking: true
          )
        ]
      ).to_h
    end

    def line_deletion_range(source, range)
      start_byte = range.fetch(:start_byte)
      end_byte = range.fetch(:end_byte)
      line_start = source.rindex("\n", start_byte - 1)&.+(1) || 0
      next_newline = source.index("\n", end_byte)
      line_end = next_newline ? next_newline + 1 : end_byte
      { start_byte: line_start, end_byte: line_end }
    end

    def class_body_insertion_byte(source, range)
      end_byte = range.fetch(:end_byte)
      source.rindex("\n", end_byte - 1)&.+(1) || end_byte
    end

    def ruby_normalized_backend_capability(dialect)
      TreeHaver::BackendCapability.new(
        backend_ref: BACKEND_REFERENCE,
        language: "ruby",
        parser_identity: TreeHaver::ParserIdentity.new(
          name: "prism",
          version: ::Prism::VERSION,
          implementation: "ruby"
        ),
        language_version: TreeHaver::LanguageVersion.new(version: "ruby", dialect: dialect),
        parse_error_behavior: "diagnostic_without_tree",
        source_span_support: "byte_range_and_points",
        source_fragment_support: "source_slice",
        render_strategies: ["source_fragment_reuse", "full_file_fallback"],
        semantic_role_support: "backend_specific_with_portable_mapping",
        normalized_tree_support: true,
        native_node_access: true,
        diagnostics: []
      )
    end

    def ruby_prism_parse_error_tolerance
      TreeHaver::ParseErrorTolerance.new(
        backend_ref: BACKEND_REFERENCE,
        language: "ruby",
        behavior: "diagnostic_without_tree",
        tolerates_errors: false,
        error_nodes: [],
        diagnostics: []
      )
    end

    def prism_normalized_metadata
      {
        prism: {
          native_tree_retained: "true",
          native_tree_visibility: "provider_internal"
        }
      }
    end

    def prism_class_node(source, node, index, child_ids:)
      TreeHaver::NormalizedTreeNode.new(
        id: "prism:class:#{index}",
        kind: "class_declaration",
        role: "structural",
        parent_id: "prism:program:0",
        child_ids: child_ids,
        span: source_span_for_location(node.location),
        field_name: "declaration",
        named: true,
        anonymous: false,
        has_source_text: true,
        source_fragment: source.byteslice(node.location.start_offset...node.location.end_offset),
        backend_kind: node.class.name,
        semantic_roles: ["declaration", "class", "named_symbol"],
        backend_roles: ["prism.ClassNode"],
        unsupported_features: [],
        metadata: {
          prism: {
            node_path: "statements.body[#{index}]",
            raw_identifier: node.name.to_s
          }
        }
      )
    end

    def prism_comment_nodes(source, comments, magic_comments, body)
      comments.each_with_index.map do |comment, index|
        prism_comment_node(
          source,
          comment,
          index,
          magic_comment_for(comment, magic_comments),
          parent_id: comment_parent_id(comment, body)
        )
      end
    end

    def prism_comment_node(source, comment, index, magic_comment, parent_id:)
      directive = prism_comment_directive(source.byteslice(comment.location.start_offset...comment.location.end_offset), magic_comment)
      TreeHaver::NormalizedTreeNode.new(
        id: "prism:comment:#{index}",
        kind: directive.fetch(:kind),
        role: "comment",
        parent_id: parent_id,
        child_ids: [],
        span: source_span_for_location(comment.location),
        field_name: "comment",
        named: false,
        anonymous: false,
        has_source_text: true,
        source_fragment: source.byteslice(comment.location.start_offset...comment.location.end_offset),
        backend_kind: comment.class.name,
        semantic_roles: directive.fetch(:semantic_roles),
        backend_roles: ["prism.Comment"],
        unsupported_features: [],
        metadata: {
          prism: {
            node_path: "comments[#{index}]",
            directive_kind: directive.fetch(:directive_kind),
            magic_key: directive[:magic_key],
            magic_value: directive[:magic_value]
          }.compact
        }
      )
    end

    def prism_comment_directive(comment_text, magic_comment)
      if comment_text.strip.match?(/\A#\s*smorg:freeze\b/)
        {
          kind: "freeze_directive",
          directive_kind: "freeze",
          semantic_roles: ["comment", "directive", "freeze"]
        }
      elsif magic_comment
        {
          kind: "magic_comment",
          directive_kind: "magic_comment",
          semantic_roles: ["comment", "directive", "magic_comment"],
          magic_key: magic_comment.key,
          magic_value: magic_comment.value
        }
      elsif comment_text.strip == "# :nocov:"
        {
          kind: "coverage_directive",
          directive_kind: "coverage",
          semantic_roles: ["comment", "directive", "coverage"]
        }
      else
        {
          kind: "comment",
          directive_kind: "comment",
          semantic_roles: ["comment"]
        }
      end
    end

    def magic_comment_for(comment, magic_comments)
      magic_comments.find do |magic_comment|
        comment.location.start_offset <= magic_comment.key_loc.start_offset &&
          magic_comment.key_loc.start_offset < comment.location.end_offset
      end
    end

    def comment_parent_id(comment, body)
      body.each_with_index do |node, index|
        next unless node.is_a?(::Prism::ClassNode)
        next unless comment.location.start_offset > node.location.start_offset &&
          comment.location.end_offset < node.location.end_offset

        return "prism:class:#{index}"
      end
      "prism:program:0"
    end

    def prism_method_node(source, node, class_index, method_index)
      TreeHaver::NormalizedTreeNode.new(
        id: "prism:def:#{method_index}",
        kind: "method_declaration",
        role: "structural",
        parent_id: "prism:class:#{class_index}",
        child_ids: [],
        span: source_span_for_location(node.location),
        field_name: "body",
        named: true,
        anonymous: false,
        has_source_text: true,
        source_fragment: source.byteslice(node.location.start_offset...node.location.end_offset),
        backend_kind: node.class.name,
        semantic_roles: ["declaration", "method", "named_symbol"],
        backend_roles: ["prism.DefNode"],
        unsupported_features: [],
        metadata: {
          prism: {
            node_path: "statements.body[#{class_index}].body.body[#{method_index}]",
            raw_identifier: node.name.to_s
          }
        }
      )
    end

    def full_source_span(source)
      lines = source.split("\n", -1)
      TreeHaver::SourceSpan.new(
        range: TreeHaver::ByteRange.new(start_byte: 0, end_byte: source.bytesize),
        start_point: TreeHaver::SourcePoint.new(row: 0, column: 0),
        end_point: TreeHaver::SourcePoint.new(row: lines.length - 1, column: lines.last.bytesize)
      )
    end

    def source_span_for_location(location)
      TreeHaver::SourceSpan.new(
        range: TreeHaver::ByteRange.new(start_byte: location.start_offset, end_byte: location.end_offset),
        start_point: TreeHaver::SourcePoint.new(row: location.start_line - 1, column: location.start_column),
        end_point: TreeHaver::SourcePoint.new(row: location.end_line - 1, column: location.end_column)
      )
    end

    module_function(
      :ruby_feature_profile,
      :available_ruby_backends,
      :ruby_backend_feature_profile,
      :ruby_plan_context,
      :ruby_structured_edit_provider_profile,
      :ruby_structured_edit_request_projection,
      :ruby_structured_edit_result_projection,
      :ruby_structured_edit_application_projection,
      :ruby_structured_edit_execution_report_projection,
      :ruby_structured_edit_batch_request_projection,
      :ruby_structured_edit_batch_report_projection,
      :parse_ruby,
      :parse_ruby_normalized,
      :apply_edit_projection,
      :match_ruby_owners,
      :merge_ruby,
      :merge_ruby_with_reviewed_nested_outputs,
      :merge_ruby_with_reviewed_nested_outputs_from_replay_bundle,
      :merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope,
      :merge_ruby_with_reviewed_nested_outputs_from_review_state,
      :merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope,
      :ruby_discovered_surfaces,
      :ruby_delegated_child_operations,
      :unsupported_feature_result,
      :edit_projection_rejection,
      :line_deletion_range,
      :class_body_insertion_byte,
      :ruby_normalized_backend_capability,
      :ruby_prism_parse_error_tolerance,
      :prism_normalized_metadata,
      :prism_class_node,
      :prism_comment_nodes,
      :prism_comment_node,
      :prism_comment_directive,
      :magic_comment_for,
      :comment_parent_id,
      :prism_method_node,
      :full_source_span,
      :source_span_for_location
    )
  end
end

Prism::Merge.register_backend!

if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :prism_merge,
    require_path: "prism/merge",
    merger_class: "Prism::Merge::SmartMerger",
    test_source: "def foo; end",
    category: :code,
  )
end

Prism::Merge::Version.class_eval do
  extend VersionGem::Basic
end
