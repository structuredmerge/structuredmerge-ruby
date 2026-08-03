# frozen_string_literal: true

require 'ast/merge'
require 'tree_haver'

module Markdown
  module Merge
    PACKAGE_NAME = 'markdown-merge'
    BACKEND_REFERENCES = {
      'kreuzberg-language-pack' => TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND,
      'commonmarker' => TreeHaver::BackendReference.new(id: 'commonmarker', family: 'native').freeze,
      'markly' => TreeHaver::BackendReference.new(id: 'markly', family: 'native').freeze,
      'kramdown' => TreeHaver::BackendReference.new(id: 'kramdown', family: 'native').freeze
    }.freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    class Error < Ast::Merge::Error; end

    class ParseError < Ast::Merge::ParseError
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    class TemplateParseError < ParseError; end

    class DestinationParseError < ParseError; end

    class CorruptionDetectedError < Error; end

    autoload :BackendSupport, 'markdown/merge/backend_support'
    autoload :Cleanse, 'markdown/merge/cleanse'
    autoload :CodeBlockMatchRefiner, 'markdown/merge/code_block_match_refiner'
    autoload :CodeBlockMerger, 'markdown/merge/code_block_merger'
    autoload :CommentTracker, 'markdown/merge/comment_tracker'
    autoload :ConflictResolver, 'markdown/merge/conflict_resolver'
    autoload :DebugLogger, 'markdown/merge/debug_logger'
    autoload :DocumentProblems, 'markdown/merge/document_problems'
    autoload :FileAligner, 'markdown/merge/file_aligner'
    autoload :FileAnalysis, 'markdown/merge/file_analysis'
    autoload :FileAnalysisBase, 'markdown/merge/file_analysis_base'
    autoload :FreezeNode, 'markdown/merge/freeze_node'
    autoload :GapLineNode, 'markdown/merge/gap_line_node'
    autoload :LinkDefinitionFormatter, 'markdown/merge/link_definition_formatter'
    autoload :LinkDefinitionNode, 'markdown/merge/link_definition_node'
    autoload :LinkParser, 'markdown/merge/link_parser'
    autoload :LinkReferenceRehydrator, 'markdown/merge/link_reference_rehydrator'
    autoload :ListMatchRefiner, 'markdown/merge/list_match_refiner'
    autoload :ListMerger, 'markdown/merge/list_merger'
    autoload :MarkdownStructure, 'markdown/merge/markdown_structure'
    autoload :MergeResult, 'markdown/merge/merge_result'
    autoload :NodeTypeNormalizer, 'markdown/merge/node_type_normalizer'
    autoload :OutputBuilder, 'markdown/merge/output_builder'
    autoload :PartialTemplateMerger, 'markdown/merge/partial_template_merger'
    autoload :PreservationSupport, 'markdown/merge/preservation_support'
    autoload :SmartMerger, 'markdown/merge/smart_merger'
    autoload :SmartMergerBase, 'markdown/merge/smart_merger_base'
    autoload :TableMatchAlgorithm, 'markdown/merge/table_match_algorithm'
    autoload :TableMatchRefiner, 'markdown/merge/table_match_refiner'
    autoload :WhitespaceNormalizer, 'markdown/merge/whitespace_normalizer'
    autoload :WrapperSupport, 'markdown/merge/wrapper_support'

    def register_backend!
      BACKEND_REGISTRY.mutex.synchronize do
        return if BACKEND_REGISTRY.registered

        TreeHaver::BackendRegistry.register(BACKEND_REFERENCES.fetch('kreuzberg-language-pack'))

        grammar_finder = TreeHaver::GrammarFinder.new(:markdown)
        grammar_finder.register! if grammar_finder.available?

        BACKEND_REGISTRY.registered = true
      end
    end

    def markdown_feature_profile
      {
        family: 'markdown',
        supported_dialects: ['markdown'],
        supported_policies: []
      }
    end

    def available_markdown_backends
      BACKEND_REFERENCES.filter_map do |backend_id, reference|
        reference if markdown_backend_available_for_analysis?(backend_id)
      end
    end

    def markdown_backend_feature_profile(backend: nil)
      resolved_backend = resolve_backend(backend)
      unless BACKEND_REFERENCES.key?(resolved_backend)
        return unsupported_feature_result("Unsupported Markdown backend #{resolved_backend}.")
      end

      markdown_feature_profile.merge(
        backend: resolved_backend,
        backend_ref: BACKEND_REFERENCES.fetch(resolved_backend).to_h
      )
    end

    def markdown_plan_context(backend: nil)
      profile = markdown_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: markdown_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: false,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_markdown(source, dialect, backend: nil)
      return unsupported_feature_result("Unsupported Markdown dialect #{dialect}.") unless dialect == 'markdown'

      resolved_backend = resolve_backend(backend)
      unless BACKEND_REFERENCES.key?(resolved_backend)
        return unsupported_feature_result("Unsupported Markdown backend #{resolved_backend}.")
      end

      register_backend!
      parser = TreeHaver.with_backend(resolved_backend) { TreeHaver.parser_for(:markdown) }
      tree = parser.parse(source)
      collect_parse_errors(tree.root_node)

      normalized_source = normalize_source(source)
      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: 'markdown',
          dialect: dialect,
          normalized_source: normalized_source,
          root_kind: 'document',
          owners: collect_markdown_owners(normalized_source)
        },
        policies: []
      }
    rescue TreeHaver::Error, StandardError => e
      parse_failure_result(e)
    end

    def match_markdown_owners(template, destination)
      destination_paths = destination[:owners].to_h { |owner| [owner[:path], true] }
      template_paths = template[:owners].to_h { |owner| [owner[:path], true] }

      {
        matched: template[:owners]
                 .filter { |owner| destination_paths[owner[:path]] }
                 .map { |owner| { template_path: owner[:path], destination_path: owner[:path] } },
        unmatched_template: template[:owners].map { |owner| owner[:path] }.reject { |path| destination_paths[path] },
        unmatched_destination: destination[:owners].map { |owner| owner[:path] }.reject { |path| template_paths[path] }
      }
    end

    def merge_markdown(template_source, destination_source, dialect, backend: nil)
      template = parse_markdown(template_source, dialect, backend: backend)
      return template unless template[:ok]

      destination = parse_markdown(destination_source, dialect, backend: backend)
      return destination unless destination[:ok]

      destination_sections = collect_markdown_sections(
        destination.dig(:analysis, :normalized_source),
        destination.dig(:analysis, :owners)
      )
      template_sections = collect_markdown_sections(
        template.dig(:analysis, :normalized_source),
        template.dig(:analysis, :owners)
      )
      destination_paths = destination_sections.to_h { |section| [section[:path], true] }
      merged_sections = destination_sections.map { |section| section[:text] }.reject(&:empty?) +
                        template_sections
                        .reject { |section| destination_paths[section[:path]] || section[:text].empty? }
                        .map { |section| section[:text] }

      {
        ok: true,
        diagnostics: [],
        output: "#{merged_sections.join("\n\n").strip}\n",
        policies: []
      }
    end

    def markdown_embedded_families(analysis)
      analysis[:owners].filter_map do |owner|
        next unless owner[:owner_kind] == 'code_fence'
        next if owner[:info_string].to_s.empty?

        family = code_fence_family(owner[:info_string])
        dialect = code_fence_dialect(owner[:info_string], family)
        next unless family && dialect

        {
          path: owner[:path],
          language: owner[:info_string],
          family: family,
          dialect: dialect
        }
      end
    end

    def markdown_discovered_surfaces(analysis)
      markdown_embedded_families(analysis).map do |candidate|
        Ast::Merge.discovered_surface(
          surface_kind: 'markdown_fenced_code_block',
          declared_language: candidate[:language],
          effective_language: candidate[:dialect],
          address: "document[0] > fenced_code_block[#{candidate[:path]}]",
          parent_address: 'document[0]',
          owner: Ast::Merge.surface_owner_ref(kind: 'structural_owner', address: candidate[:path]),
          reconstruction_strategy: 'portable_write',
          metadata: {
            family: candidate[:family],
            dialect: candidate[:dialect],
            path: candidate[:path]
          }
        )
      end
    end

    def markdown_delegated_child_operations(analysis, parent_operation_id: 'markdown-document-0')
      markdown_discovered_surfaces(analysis).each_with_index.map do |surface, index|
        Ast::Merge.delegated_child_operation(
          operation_id: "markdown-fence-#{index}",
          parent_operation_id: parent_operation_id,
          requested_strategy: 'delegate_child_surface',
          language_chain: ['markdown', surface[:effective_language]],
          surface: surface
        )
      end
    end

    def apply_markdown_delegated_child_outputs(source, delegated_operations, apply_plan, applied_children)
      lines = normalize_source(source).split("\n")
      ranges = markdown_fence_ranges(source)
      operations_by_id = delegated_operations.to_h { |operation| [operation[:operation_id], operation] }
      outputs_by_id = applied_children.to_h { |entry| [entry[:operation_id], entry[:output]] }

      replacements = apply_plan[:entries].filter_map do |entry|
        operation = operations_by_id[entry.dig(:delegated_group, :child_operation_id)]
        output = outputs_by_id[entry.dig(:delegated_group, :child_operation_id)]
        next if operation.nil? || output.nil?

        owner_path = operation.dig(:surface, :owner, :address)
        range = ranges[owner_path]
        if range.nil?
          return {
            ok: false,
            diagnostics: [{ severity: 'error', category: 'configuration_error',
                            message: "missing fenced-code range for #{owner_path}" }],
            policies: []
          }
        end

        { range: range, output: output }
      end

      replacements.sort_by { |entry| -entry[:range][:start] }.each do |entry|
        body_lines = entry[:output].empty? ? [] : entry[:output].sub(/\n\z/, '').split("\n")
        lines[entry[:range][:start] + 1...entry[:range][:end]] = body_lines
      end

      {
        ok: true,
        diagnostics: [],
        output: "#{lines.join("\n").sub(/\n+\z/, '')}\n",
        policies: []
      }
    end

    def merge_markdown_with_nested_outputs(template_source, destination_source, dialect, nested_outputs, backend: nil)
      Ast::Merge.execute_nested_merge(
        nested_outputs,
        default_family: 'markdown',
        request_id_prefix: 'nested_markdown_child',
        merge_parent: -> { merge_markdown(template_source, destination_source, dialect, backend: backend) },
        discover_operations: lambda { |merged_output|
          analysis = parse_markdown(merged_output, dialect, backend: backend)
          next { ok: false, diagnostics: analysis[:diagnostics] || [] } unless analysis[:ok]

          {
            ok: true,
            diagnostics: [],
            operations: markdown_delegated_child_operations(analysis[:analysis])
          }
        },
        apply_resolved_outputs: lambda { |merged_output, operations, apply_plan, applied_children|
          apply_markdown_delegated_child_outputs(
            merged_output,
            operations,
            apply_plan,
            applied_children
          )
        }
      )
    end

    def merge_markdown_with_reviewed_nested_outputs(template_source, destination_source, dialect, review_state,
                                                    applied_children, backend: nil)
      Ast::Merge.execute_reviewed_nested_merge(
        review_state,
        'markdown',
        applied_children,
        merge_parent: -> { merge_markdown(template_source, destination_source, dialect, backend: backend) },
        discover_operations: lambda { |merged_output|
          analysis = parse_markdown(merged_output, dialect, backend: backend)
          next({ ok: false, diagnostics: analysis[:diagnostics] || [] }) unless analysis[:ok]

          {
            ok: true,
            diagnostics: [],
            operations: markdown_delegated_child_operations(analysis[:analysis])
          }
        },
        apply_resolved_outputs: lambda { |merged_output, operations, apply_plan, resolved_children|
          apply_markdown_delegated_child_outputs(
            merged_output,
            operations,
            apply_plan,
            resolved_children
          )
        }
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_replay_bundle(template_source, destination_source, dialect,
                                                                       replay_bundle, backend: nil)
      execution = Array(replay_bundle[:reviewed_nested_executions]).find { |entry| entry[:family] == 'markdown' }
      unless execution
        return { ok: false,
                 diagnostics: [{ severity: 'error', category: 'configuration_error', message: 'review replay bundle does not include a reviewed nested execution for markdown.' }], policies: [] }
      end

      merge_markdown_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        execution[:review_state],
        execution[:applied_children],
        backend: backend
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_review_state(template_source, destination_source, dialect,
                                                                      review_state, backend: nil)
      execution = Array(review_state[:reviewed_nested_executions]).find { |entry| entry[:family] == 'markdown' }
      unless execution
        return { ok: false,
                 diagnostics: [{ severity: 'error', category: 'configuration_error', message: 'review state does not include a reviewed nested execution for markdown.' }], policies: [] }
      end

      merge_markdown_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        execution[:review_state],
        execution[:applied_children],
        backend: backend
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_replay_bundle_envelope(template_source, destination_source,
                                                                                dialect, envelope, backend: nil)
      replay_bundle, import_error = Ast::Merge.import_review_replay_bundle_envelope(envelope)
      if import_error
        return { ok: false,
                 diagnostics: [{ severity: 'error', category: import_error[:category], message: import_error[:message] }], policies: [] }
      end

      merge_markdown_with_reviewed_nested_outputs_from_replay_bundle(
        template_source,
        destination_source,
        dialect,
        replay_bundle,
        backend: backend
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_review_state_envelope(template_source, destination_source,
                                                                               dialect, envelope, backend: nil)
      review_state, import_error = Ast::Merge.import_conformance_manifest_review_state_envelope(envelope)
      if import_error
        return { ok: false,
                 diagnostics: [{ severity: 'error', category: import_error[:category], message: import_error[:message] }], policies: [] }
      end

      merge_markdown_with_reviewed_nested_outputs_from_review_state(
        template_source,
        destination_source,
        dialect,
        review_state,
        backend: backend
      )
    end

    def normalize_source(source)
      source.gsub(/\r\n?/, "\n")
    end

    def slugify(value)
      slug = value
             .strip
             .downcase
             .gsub(/[`*_~\[\]()<>]/, '')
             .gsub(/[^a-z0-9]+/, '-')
             .gsub(/\A-+|-+\z/, '')
      slug.empty? ? 'section' : slug
    end

    def collect_markdown_owners(source)
      owners = []
      heading_index = 0
      code_fence_index = 0
      lines = source.split("\n")
      index = 0

      while index < lines.length
        line = lines[index]
        if (heading = line.match(/^(#+)\s+(.+?)\s*#*\s*$/)) && heading[1].length.between?(1, 6)
          level = heading[1].length
          owners << {
            path: "/heading/#{heading_index}",
            owner_kind: 'heading',
            match_key: "h#{level}:#{slugify(heading[2])}",
            level: level
          }
          heading_index += 1
          index += 1
          next
        end

        if (fence = line.match(/^\s*(`{3,}|~{3,})\s*(.*?)\s*$/))
          marker = fence[1]
          marker_char = marker[0]
          marker_length = marker.length
          info_string = fence[2].strip.split(/\s+/).first.to_s
          owners << {
            path: "/code_fence/#{code_fence_index}",
            owner_kind: 'code_fence',
            match_key: "fence:#{info_string.empty? ? 'plain' : info_string}",
            **(info_string.empty? ? {} : { info_string: info_string })
          }
          code_fence_index += 1

          index += 1
          while index < lines.length
            trimmed = lines[index].strip
            break if trimmed.length >= marker_length &&
                     trimmed.start_with?(marker_char * marker_length) &&
                     trimmed.delete(marker_char).empty?

            index += 1
          end
          index += 1
          next
        end

        index += 1
      end

      owners
    end

    def markdown_owner_start_indices(source)
      starts = {}
      lines = normalize_source(source).split("\n")
      heading_index = 0
      code_fence_index = 0
      index = 0

      while index < lines.length
        line = lines[index]
        if (heading = line.match(/^(#+)\s+(.+?)\s*#*\s*$/)) && heading[1].length.between?(1, 6)
          starts["/heading/#{heading_index}"] = index
          heading_index += 1
          index += 1
          next
        end

        if (fence = line.match(/^\s*(`{3,}|~{3,})\s*(.*?)\s*$/))
          starts["/code_fence/#{code_fence_index}"] = index
          code_fence_index += 1
          marker = fence[1]
          marker_char = marker[0]
          marker_length = marker.length
          index += 1
          while index < lines.length
            trimmed = lines[index].strip
            break if trimmed.length >= marker_length &&
                     trimmed.start_with?(marker_char * marker_length) &&
                     trimmed.delete(marker_char).empty?

            index += 1
          end
          index += 1
          next
        end

        index += 1
      end

      starts
    end

    def collect_markdown_sections(source, owners)
      lines = normalize_source(source).split("\n")
      starts = markdown_owner_start_indices(source)
      ordered = owners.filter_map do |owner|
        start = starts[owner[:path]]
        next if start.nil?

        { owner: owner, start: start }
      end.sort_by { |entry| entry[:start] }

      ordered.each_with_index.map do |entry, index|
        finish = ordered[index + 1]&.dig(:start) || lines.length
        {
          path: entry.dig(:owner, :path),
          text: lines[entry[:start]...finish].join("\n").strip
        }
      end
    end

    def markdown_fence_ranges(source)
      ranges = {}
      code_fence_index = 0
      lines = normalize_source(source).split("\n")
      index = 0

      while index < lines.length
        line = lines[index]
        if (fence = line.match(/^\s*(`{3,}|~{3,})\s*(.*?)\s*$/))
          marker = fence[1]
          marker_char = marker[0]
          marker_length = marker.length
          closing_index = index
          cursor = index + 1
          while cursor < lines.length
            trimmed = lines[cursor].strip
            if trimmed.length >= marker_length &&
               trimmed.start_with?(marker_char * marker_length) &&
               trimmed.delete(marker_char).empty?
              closing_index = cursor
              break
            end
            closing_index = cursor if cursor == lines.length - 1
            cursor += 1
          end

          ranges["/code_fence/#{code_fence_index}"] = { start: index, end: closing_index }
          code_fence_index += 1
          index = closing_index + 1
          next
        end

        index += 1
      end

      ranges
    end

    def code_fence_family(info_string)
      case info_string.to_s.downcase
      when 'ts', 'typescript'
        'typescript'
      when 'rust', 'rs'
        'rust'
      when 'go'
        'go'
      when 'json', 'jsonc', 'json5'
        'json'
      when 'yaml', 'yml'
        'yaml'
      when 'toml'
        'toml'
      end
    end

    def code_fence_dialect(info_string, family)
      case family
      when 'typescript', 'rust', 'go', 'yaml', 'toml'
        family
      when 'json'
        %w[json jsonc json5].include?(info_string.to_s.downcase) ? info_string.to_s.downcase : 'json'
      end
    end

    def resolve_backend(backend)
      return backend.to_s unless backend.to_s.empty?

      current = TreeHaver.current_backend_id
      return current if BACKEND_REFERENCES.key?(current.to_s) && markdown_backend_available_for_analysis?(current)

      BACKEND_REFERENCES.keys.find { |backend_id| markdown_backend_available_for_analysis?(backend_id) } ||
        'kreuzberg-language-pack'
    end

    def markdown_backend_available_for_analysis?(backend_id)
      register_backend!
      registrations = TreeHaver.registered_languages(:markdown)
      case backend_id.to_s
      when 'commonmarker', 'markly', 'kramdown'
        registrations.dig(backend_id.to_sym, :backend_module)&.then do |backend_module|
          !backend_module.respond_to?(:available?) || backend_module.available?
        end
      when 'kreuzberg-language-pack'
        registrations.key?(:tree_sitter) || registrations.key?(:tslp)
      else
        false
      end
    end

    def collect_parse_errors(node)
      raise TreeHaver::NotAvailable, 'Markdown parse returned no root node' unless node
      return unless node.respond_to?(:has_error?) && node.has_error?

      raise TreeHaver::NotAvailable,
            'Markdown parse contains syntax errors'
    end

    def parse_failure_result(error)
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'parse_error', message: error.message }],
        policies: []
      }
    end

    def unsupported_feature_result(message)
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: message }],
        policies: []
      }
    end

    module_function(
      :register_backend!,
      :markdown_feature_profile,
      :available_markdown_backends,
      :markdown_backend_feature_profile,
      :markdown_plan_context,
      :parse_markdown,
      :match_markdown_owners,
      :merge_markdown,
      :markdown_embedded_families,
      :markdown_discovered_surfaces,
      :markdown_delegated_child_operations,
      :apply_markdown_delegated_child_outputs,
      :merge_markdown_with_reviewed_nested_outputs,
      :merge_markdown_with_reviewed_nested_outputs_from_replay_bundle,
      :merge_markdown_with_reviewed_nested_outputs_from_replay_bundle_envelope,
      :merge_markdown_with_reviewed_nested_outputs_from_review_state,
      :merge_markdown_with_reviewed_nested_outputs_from_review_state_envelope,
      :merge_markdown_with_nested_outputs,
      :normalize_source,
      :slugify,
      :collect_markdown_owners,
      :markdown_owner_start_indices,
      :collect_markdown_sections,
      :markdown_fence_ranges,
      :code_fence_family,
      :code_fence_dialect,
      :resolve_backend,
      :markdown_backend_available_for_analysis?,
      :collect_parse_errors,
      :parse_failure_result,
      :unsupported_feature_result
    )
  end
end

%w[
  commonmarker/merge/backend
  markly/merge/backend
].each do |feature|
  require feature
rescue LoadError
  nil
end

if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :markdown_merge,
    require_path: 'markdown/merge',
    merger_class: 'Markdown::Merge::SmartMerger',
    test_source: "# Test\n\nParagraph",
    category: :markdown,
    skip_instantiation: true
  )
end
