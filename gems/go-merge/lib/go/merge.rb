# frozen_string_literal: true

require "tree_haver"
require "ast/merge"

module Go
  module Merge
    extend self

    PACKAGE_NAME = "go-merge"
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    DESTINATION_WINS_ARRAY_POLICY = { surface: "array", name: "destination_wins_array" }.freeze

    def go_feature_profile
      { family: "go", supported_dialects: ["go"], supported_policies: [DESTINATION_WINS_ARRAY_POLICY] }
    end

    def available_go_backends
      [TREE_SITTER_BACKEND]
    end

    def go_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? TREE_SITTER_BACKEND.id : backend.to_s
      return unsupported_feature_result("Unsupported Go backend #{requested}.") unless requested == TREE_SITTER_BACKEND.id

      go_feature_profile.merge(
        backend: requested,
        backend_ref: TREE_SITTER_BACKEND.to_h,
        supports_dialects: true
      )
    end

    def go_plan_context(backend: nil)
      profile = go_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: go_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_go(source, dialect)
      requested = TREE_SITTER_BACKEND.id
      return unsupported_feature_result("Unsupported Go backend #{requested}.") unless requested == TREE_SITTER_BACKEND.id
      return analyze_go_module(source) if dialect == "go"

      { ok: false, diagnostics: [{ severity: "error", category: "unsupported_feature", message: "Unsupported Go dialect #{dialect}." }], policies: [] }
    end

    def match_go_owners(template, destination)
      destination_paths = destination[:owners].to_h { |owner| [owner[:path], true] }
      template_paths = template[:owners].to_h { |owner| [owner[:path], true] }
      {
        matched: template[:owners].filter { |owner| destination_paths[owner[:path]] }.map { |owner| { template_path: owner[:path], destination_path: owner[:path] } },
        unmatched_template: template[:owners].map { |owner| owner[:path] }.reject { |path| destination_paths[path] },
        unmatched_destination: destination[:owners].map { |owner| owner[:path] }.reject { |path| template_paths[path] }
      }
    end

    def merge_go(template_source, destination_source, dialect)
      template = parse_go(template_source, dialect)
      return { ok: false, diagnostics: template[:diagnostics], policies: [] } unless template[:ok]
      destination = parse_go(destination_source, dialect)
      unless destination[:ok]
        return {
          ok: false,
          diagnostics: destination[:diagnostics].map { |diagnostic| diagnostic[:category] == "parse_error" ? diagnostic.merge(category: "destination_parse_error") : diagnostic },
          policies: []
        }
      end

      destination_declarations = destination.dig(:analysis, :declarations).to_h { |item| [item[:path], item] }
      merged_declaration_texts = destination.dig(:analysis, :declarations).map { |item| item[:text] } +
        template.dig(:analysis, :declarations).reject { |item| destination_declarations[item[:path]] }.map { |item| item[:text] }
      import_block = destination.dig(:analysis, :imports).map { |item| item[:text] }.join
      declaration_block = merged_declaration_texts.join("\n").rstrip
      sections = [import_block.rstrip, declaration_block].reject(&:empty?)
      { ok: true, diagnostics: [], output: "#{sections.join("\n\n").rstrip}\n", policies: [DESTINATION_WINS_ARRAY_POLICY] }
    end

    def analyze_go_module(source)
      parsed = TreeHaver.parse_with_language_pack(TreeHaver::ParserRequest.new(source: source, language: "go", dialect: "go"))
      return { ok: false, diagnostics: parsed[:diagnostics], policies: [] } unless parsed[:ok]
      processed = TreeHaver.process_with_language_pack(TreeHaver::ProcessRequest.new(source: source, language: "go"))
      return { ok: false, diagnostics: processed[:diagnostics], policies: [] } unless processed[:ok]

      deduped_imports = {}
      processed[:analysis].imports.each do |item|
        match_key = normalize_go_import_path(item.source)
        candidate = { path: nil, match_key: match_key, text: import_text(source, item.span) }
        current = deduped_imports[match_key]
        deduped_imports[match_key] = candidate if current.nil? || candidate[:text].length > current[:text].length
      end
      imports = deduped_imports.values.each_with_index.map { |item, index| item.merge(path: "/imports/#{index}") }
      declarations = processed[:analysis].structure
        .select { |item| item.name }
        .map { |item| { path: "/declarations/#{item.name}", match_key: item.name, text: declaration_text(source, item.span) } }
        .sort_by { |item| item[:path] }

      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: "go",
          dialect: "go",
          source: source,
          owners: imports.map { |item| { path: item[:path], owner_kind: "import", match_key: item[:match_key] } } +
            declarations.map { |item| { path: item[:path], owner_kind: "declaration", match_key: item[:match_key] } },
          imports: imports,
          declarations: declarations
        },
        policies: []
      }
    end
    private_class_method :analyze_go_module

    def normalize_go_import_path(import_source)
      match = import_source.match(/"([^"]+)"/)
      match ? match[1] : import_source.sub(/\Aimport\s+/, "").strip
    end
    private_class_method :normalize_go_import_path

    def import_text(source, span) = "#{slice_span(source, span)}\n"
    def declaration_text(source, span) = "#{line_anchored_slice(source, span)}\n"
    def slice_span(source, span) = source[span.start_byte...span.end_byte].strip
    def line_anchored_slice(source, span)
      line_start = source.rindex("\n", [span.start_byte - 1, 0].max)
      line_start = line_start ? line_start + 1 : 0
      source[line_start...span.end_byte].strip
    end
    private_class_method :import_text, :declaration_text, :slice_span, :line_anchored_slice

    def unsupported_feature_result(message)
      Ast::Merge.unsupported_feature_result(message)
    end
    private_class_method :unsupported_feature_result
  end
end
