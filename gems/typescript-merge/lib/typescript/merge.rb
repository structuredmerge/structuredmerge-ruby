# frozen_string_literal: true

require "tree_haver"

module TypeScript
  module Merge
    PACKAGE_NAME = "typescript-merge"
    DESTINATION_WINS_ARRAY_POLICY = { surface: "array", name: "destination_wins_array" }.freeze

    module_function

    def type_script_feature_profile
      { family: "typescript", supported_dialects: ["typescript"], supported_policies: [DESTINATION_WINS_ARRAY_POLICY] }
    end

    def parse_type_script(source, dialect)
      return analyze_type_script_module(source) if dialect == "typescript"

      { ok: false, diagnostics: [{ severity: "error", category: "unsupported_feature", message: "Unsupported TypeScript dialect #{dialect}." }], policies: [] }
    end

    def match_type_script_owners(template, destination)
      destination_paths = destination[:owners].to_h { |owner| [owner[:path], true] }
      template_paths = template[:owners].to_h { |owner| [owner[:path], true] }
      {
        matched: template[:owners].filter { |owner| destination_paths[owner[:path]] }.map { |owner| { template_path: owner[:path], destination_path: owner[:path] } },
        unmatched_template: template[:owners].map { |owner| owner[:path] }.reject { |path| destination_paths[path] },
        unmatched_destination: destination[:owners].map { |owner| owner[:path] }.reject { |path| template_paths[path] }
      }
    end

    def merge_type_script(template_source, destination_source, dialect)
      template = parse_type_script(template_source, dialect)
      return { ok: false, diagnostics: template[:diagnostics], policies: [] } unless template[:ok]
      destination = parse_type_script(destination_source, dialect)
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

    def analyze_type_script_module(source)
      parsed = TreeHaver.parse_with_language_pack(TreeHaver::ParserRequest.new(source: source, language: "typescript", dialect: "typescript"))
      return { ok: false, diagnostics: parsed[:diagnostics], policies: [] } unless parsed[:ok]
      processed = TreeHaver.process_with_language_pack(TreeHaver::ProcessRequest.new(source: source, language: "typescript"))
      return { ok: false, diagnostics: processed[:diagnostics], policies: [] } unless processed[:ok]

      imports = processed[:analysis].imports.each_with_index.map do |item, index|
        { path: "/imports/#{index}", match_key: item.source, text: import_text(source, item.span) }
      end
      declarations = processed[:analysis].structure
        .select { |item| item.name }
        .map { |item| { path: "/declarations/#{item.name}", match_key: item.name, text: declaration_text(source, item.span) } }
        .sort_by { |item| item[:path] }

      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: "typescript",
          dialect: "typescript",
          source: source,
          owners: imports.map { |item| { path: item[:path], owner_kind: "import", match_key: item[:match_key] } } +
            declarations.map { |item| { path: item[:path], owner_kind: "declaration", match_key: item[:match_key] } },
          imports: imports,
          declarations: declarations
        },
        policies: []
      }
    end
    private_class_method :analyze_type_script_module

    def import_text(source, span)
      "#{slice_span(source, span)}\n"
    end
    private_class_method :import_text

    def declaration_text(source, span)
      "#{line_anchored_slice(source, span)}\n"
    end
    private_class_method :declaration_text

    def slice_span(source, span)
      source[span.start_byte...span.end_byte].strip
    end
    private_class_method :slice_span

    def line_anchored_slice(source, span)
      line_start = source.rindex("\n", [span.start_byte - 1, 0].max)
      line_start = line_start ? line_start + 1 : 0
      source[line_start...span.end_byte].strip
    end
    private_class_method :line_anchored_slice
  end
end
