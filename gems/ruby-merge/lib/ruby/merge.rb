# frozen_string_literal: true

require "tree_haver"
require "ast/merge"

module Ruby
  module Merge
    extend self

    PACKAGE_NAME = "ruby-merge"
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    DESTINATION_WINS_ARRAY_POLICY = { surface: "array", name: "destination_wins_array" }.freeze
    DIRECTIVE_LINE = /\A(?::nocov:|[\w-]+:(?:freeze|unfreeze))\z/
    MAGIC_COMMENT_PREFIXES = %w[coding encoding frozen_string_literal shareable_constant_value typed warn_indent].freeze
    REQUIRE_PATTERN = /^\s*require(?:_relative)?\s+["']([^"']+)["']/.freeze
    CLASS_PATTERN = /^\s*class\s+([A-Z]\w*(?:::\w+)*)/.freeze
    MODULE_PATTERN = /^\s*module\s+([A-Z]\w*(?:::\w+)*)/.freeze
    DEF_PATTERN = /^\s*def\s+(?:self\.)?([a-zA-Z_]\w*[!?=]?)/.freeze
    EXAMPLE_TAG = /\A@example\b(?<rest>.*)\z/.freeze
    TAG_PREFIX = /\A@[a-z_]+\b/.freeze

    def ruby_feature_profile
      {
        family: "ruby",
        supported_dialects: ["ruby"],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def available_ruby_backends
      [TREE_SITTER_BACKEND]
    end

    def ruby_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? TREE_SITTER_BACKEND.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == TREE_SITTER_BACKEND.id

      ruby_feature_profile.merge(
        backend: requested,
        backend_ref: TREE_SITTER_BACKEND.to_h,
        supports_dialects: true
      )
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

    def parse_ruby(source, dialect, backend: nil)
      requested = backend.to_s.empty? ? TREE_SITTER_BACKEND.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == "ruby"
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == TREE_SITTER_BACKEND.id

      syntax = TreeHaver.parse_with_language_pack(
        TreeHaver::ParserRequest.new(source: source, language: "ruby", dialect: dialect)
      )
      return { ok: false, diagnostics: syntax[:diagnostics], policies: [] } unless syntax[:ok]

      {
        ok: true,
        diagnostics: [],
        analysis: analyze_ruby_document(source),
        policies: []
      }
    end

    def match_ruby_owners(template, destination)
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

    def merge_ruby(template_source, destination_source, dialect)
      template = parse_ruby(template_source, dialect)
      return template unless template[:ok]

      destination = parse_ruby(destination_source, dialect)
      unless destination[:ok]
        return {
          ok: false,
          diagnostics: destination[:diagnostics].map do |diagnostic|
            diagnostic[:category] == "parse_error" ? diagnostic.merge(category: "destination_parse_error") : diagnostic
          end,
          policies: []
        }
      end

      require_block = collect_ruby_require_entries(destination.dig(:analysis, :source)).map { |entry| entry[:text] }.join("\n").strip
      destination_declarations = collect_ruby_declaration_entries(destination.dig(:analysis, :source))
      template_declarations = collect_ruby_declaration_entries(template.dig(:analysis, :source))
      destination_paths = destination_declarations.to_h { |entry| [entry[:path], true] }
      sections = []
      sections << require_block unless require_block.empty?
      sections.concat(destination_declarations.map { |entry| entry[:text] })
      sections.concat(
        template_declarations.reject { |entry| destination_paths[entry[:path]] }.map { |entry| entry[:text] }
      )

      {
        ok: true,
        diagnostics: [],
        output: "#{sections.join("\n\n").strip}\n",
        policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def ruby_discovered_surfaces(analysis)
      analysis[:discovered_surfaces] || []
    end

    def ruby_delegated_child_operations(analysis, parent_operation_id: "ruby-document-0")
      surfaces = ruby_discovered_surfaces(analysis)
      doc_operation_ids = {}
      operations = []

      surfaces.each_with_index do |surface, index|
        next unless surface[:surface_kind] == "ruby_doc_comment"

        operation_id = "ruby-doc-comment-#{index}"
        doc_operation_ids[surface[:address]] = operation_id
        operations << Ast::Merge.delegated_child_operation(
          operation_id: operation_id,
          parent_operation_id: parent_operation_id,
          requested_strategy: "delegate_child_surface",
          language_chain: ["ruby", surface[:effective_language]],
          surface: surface
        )
      end

      example_index = 0
      surfaces.each do |surface|
        next unless surface[:surface_kind] == "yard_example_block"

        operations << Ast::Merge.delegated_child_operation(
          operation_id: "yard-example-#{example_index}",
          parent_operation_id: doc_operation_ids.fetch(surface[:parent_address], parent_operation_id),
          requested_strategy: "delegate_child_surface",
          language_chain: ["ruby", "yard", surface[:effective_language]],
          surface: surface
        )
        example_index += 1
      end

      operations
    end

    def apply_ruby_delegated_child_outputs(source, delegated_operations, apply_plan, applied_children)
      lines = normalize_source(source).split("\n")
      operations_by_id = delegated_operations.to_h { |operation| [operation[:operation_id], operation] }
      outputs_by_id = applied_children.to_h { |entry| [entry[:operation_id], entry[:output]] }

      replacements = apply_plan[:entries].filter_map do |entry|
        operation = operations_by_id[entry.dig(:delegated_group, :child_operation_id)]
        output = outputs_by_id[entry.dig(:delegated_group, :child_operation_id)]
        span = operation&.dig(:surface, :span)
        next if operation.nil? || output.nil? || span.nil?

        { start: span[:start_line] - 1, finish: span[:end_line] - 1, output: output }
      end

      replacements.sort_by { |entry| -entry[:start] }.each do |entry|
        prefix = comment_prefix_for(lines[entry[:start]])
        replacement_lines = entry[:output].empty? ? [] : entry[:output].sub(/\n\z/, "").split("\n").map { |line| "#{prefix}#{line}" }
        lines[entry[:start]..entry[:finish]] = replacement_lines
      end

      {
        ok: true,
        diagnostics: [],
        output: "#{lines.join("\n").sub(/\n+\z/, "")}\n",
        policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def merge_ruby_with_nested_outputs(template_source, destination_source, dialect, nested_outputs)
      Ast::Merge.execute_nested_merge(
        nested_outputs,
        default_family: "ruby",
        request_id_prefix: "nested_ruby_child",
        merge_parent: -> { merge_ruby(template_source, destination_source, dialect) },
        discover_operations: lambda { |merged_output|
          analysis = parse_ruby(merged_output, dialect)
          next { ok: false, diagnostics: analysis[:diagnostics] || [] } unless analysis[:ok]

          {
            ok: true,
            diagnostics: [],
            operations: ruby_delegated_child_operations(analysis[:analysis])
          }
        },
        apply_resolved_outputs: lambda { |merged_output, operations, apply_plan, applied_children|
          apply_ruby_delegated_child_outputs(
            merged_output,
            operations,
            apply_plan,
            applied_children
          )
        }
      )
    end

    def analyze_ruby_document(source)
      lines = normalize_source(source).split("\n", -1)
      requires = []
      declarations = []
      discovered_surfaces = []
      pending_comments = []

      lines.each_with_index do |line, index|
        line_number = index + 1
        stripped = line.strip

        if comment_line?(line)
          pending_comments << { line: line_number, raw: line }
          next
        end

        if stripped.empty?
          pending_comments = []
          next
        end

        if (match = REQUIRE_PATTERN.match(line))
          requires << {
            path: "/requires/#{requires.length}",
            owner_kind: "require",
            match_key: match[1]
          }
          pending_comments = []
          next
        end

        declaration = declaration_for_line(line)
        if declaration
          declarations << {
            path: "/declarations/#{declaration[:name]}",
            owner_kind: "declaration",
            match_key: declaration[:name]
          }
          surfaces = surfaces_for_owner(
            owner_name: declaration[:name],
            comment_entries: pending_comments
          )
          discovered_surfaces.concat(surfaces)
          pending_comments = []
          next
        end

        pending_comments = []
      end

      {
        kind: "ruby",
        dialect: "ruby",
        root_kind: "document",
        source: normalize_source(source),
        owners: (requires + declarations).sort_by { |owner| owner[:path] },
        discovered_surfaces: discovered_surfaces
      }
    end

    def collect_ruby_require_entries(source)
      normalize_source(source).split("\n").filter_map do |line|
        next unless REQUIRE_PATTERN.match?(line)

        { text: line.rstrip }
      end
    end

    def collect_ruby_declaration_entries(source)
      lines = normalize_source(source).split("\n")
      entries = []
      pending_comments = []
      index = 0

      while index < lines.length
        line = lines[index]
        stripped = line.strip

        if comment_line?(line)
          pending_comments << index
          index += 1
          next
        end

        if stripped.empty?
          pending_comments = []
          index += 1
          next
        end

        if REQUIRE_PATTERN.match?(line)
          pending_comments = []
          index += 1
          next
        end

        declaration = declaration_for_line(line)
        unless declaration
          pending_comments = []
          index += 1
          next
        end

        start_index = pending_comments.first || index
        depth = 1
        cursor = index + 1
        while cursor < lines.length
          candidate = lines[cursor].strip
          depth += 1 if declaration_for_line(candidate)
          if candidate == "end"
            depth -= 1
            if depth.zero?
              cursor += 1
              break
            end
          end
          cursor += 1
        end

        entries << {
          path: "/declarations/#{declaration[:name]}",
          text: lines[start_index...cursor].join("\n").strip
        }
        pending_comments = []
        index = cursor
      end

      entries
    end

    def unsupported_feature_result(message)
      {
        ok: false,
        diagnostics: [{ severity: "error", category: "unsupported_feature", message: message }],
        policies: []
      }
    end

    private

    def comment_line?(line)
      line.lstrip.start_with?("#")
    end

    def declaration_for_line(line)
      if (match = CLASS_PATTERN.match(line))
        { kind: "class", name: match[1] }
      elsif (match = MODULE_PATTERN.match(line))
        { kind: "module", name: match[1] }
      elsif (match = DEF_PATTERN.match(line))
        { kind: "def", name: match[1] }
      end
    end

    def surfaces_for_owner(owner_name:, comment_entries:)
      filtered_entries = comment_entries.filter { |entry| doc_comment_content?(entry[:raw]) }
      return [] if filtered_entries.empty?

      start_line = filtered_entries.first[:line]
      end_line = filtered_entries.last[:line]
      doc_surface = Ast::Merge.discovered_surface(
        surface_kind: "ruby_doc_comment",
        declared_language: "yard",
        effective_language: "yard",
        address: "document[0] > ruby_doc_comment[#{owner_name}]",
        parent_address: "document[0]",
        owner: Ast::Merge.surface_owner_ref(kind: "owned_region", address: "/declarations/#{owner_name}"),
        span: Ast::Merge.surface_span(start_line: start_line, end_line: end_line),
        reconstruction_strategy: "rewrite_with_prefix_preservation",
        metadata: {
          owner_signature: owner_name,
          comment_prefix: comment_prefix_for(filtered_entries.first[:raw]),
          entries: filtered_entries.map { |entry| { line: entry[:line], raw: entry[:raw] } }
        }
      )

      [doc_surface] + example_surfaces_for(doc_surface)
    end

    def example_surfaces_for(surface)
      entries = Array(surface.dig(:metadata, :entries))
      normalized = entries.map { |entry| normalize_comment_content(entry[:raw]) }

      normalized.each_with_index.filter_map do |content, tag_index|
        match = EXAMPLE_TAG.match(content)
        next unless match

        body_start = tag_index + 1
        body_end = next_tag_index(normalized, body_start) || normalized.length
        next if body_start >= body_end

        body_entries = entries[body_start...body_end]
        next if body_entries.nil? || body_entries.empty?

        declared_language = declared_example_language(match[:rest]) || "ruby"
        Ast::Merge.discovered_surface(
          surface_kind: "yard_example_block",
          declared_language: declared_language,
          effective_language: declared_language,
          address: "#{surface[:address]} > yard_example[#{tag_index}]",
          parent_address: surface[:address],
          owner: Ast::Merge.surface_owner_ref(kind: "owned_region", address: surface[:address]),
          span: Ast::Merge.surface_span(start_line: body_entries.first[:line], end_line: body_entries.last[:line]),
          reconstruction_strategy: "rewrite_with_prefix_preservation",
          metadata: {
            tag_kind: "example",
            tag_index: tag_index,
            tag_text: normalized[tag_index],
            comment_prefix: surface.dig(:metadata, :comment_prefix)
          }
        )
      end
    end

    def next_tag_index(normalized_lines, start_index)
      normalized_lines.each_with_index do |content, index|
        next if index < start_index
        return index if TAG_PREFIX.match?(content)
      end
      nil
    end

    def normalize_source(source)
      source.gsub(/\r\n?/, "\n")
    end

    def normalize_comment_content(raw)
      raw.to_s.sub(/\A\s*#\s?/, "").strip
    end

    def doc_comment_content?(raw)
      content = normalize_comment_content(raw)
      return false if content.empty?
      return false if DIRECTIVE_LINE.match?(content)
      return false if MAGIC_COMMENT_PREFIXES.any? { |prefix| content.start_with?("#{prefix}:") }

      true
    end

    def comment_prefix_for(raw)
      raw.to_s[/\A\s*#\s*/] || "# "
    end

    def declared_example_language(rest)
      match = rest.to_s.strip.match(/\A\[(?<language>[^\]]+)\]/)
      language = match && match[:language]
      return if language.nil? || language.empty?

      language.downcase.tr("-", "_")
    end

    module_function(
      :ruby_feature_profile,
      :available_ruby_backends,
      :ruby_backend_feature_profile,
      :ruby_plan_context,
      :parse_ruby,
      :match_ruby_owners,
      :merge_ruby,
      :ruby_discovered_surfaces,
      :ruby_delegated_child_operations,
      :apply_ruby_delegated_child_outputs,
      :merge_ruby_with_nested_outputs,
      :analyze_ruby_document,
      :collect_ruby_require_entries,
      :collect_ruby_declaration_entries,
      :unsupported_feature_result
    )
  end
end
