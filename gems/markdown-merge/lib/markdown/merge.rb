# frozen_string_literal: true

require "kramdown"
require "tree_haver"

module Markdown
  module Merge
    PACKAGE_NAME = "markdown-merge"
    KRAMDOWN_BACKEND = TreeHaver::BackendReference.new(id: "kramdown", family: "native").freeze
    BACKEND_REFERENCES = {
      "kramdown" => KRAMDOWN_BACKEND,
      "kreuzberg-language-pack" => TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    }.freeze

    def markdown_feature_profile
      {
        family: "markdown",
        supported_dialects: ["markdown"],
        supported_policies: []
      }
    end

    def available_markdown_backends
      BACKEND_REFERENCES.values
    end

    def markdown_backend_feature_profile(backend: nil)
      resolved_backend = resolve_backend(backend)
      return unsupported_feature_result("Unsupported Markdown backend #{resolved_backend}.") unless BACKEND_REFERENCES.key?(resolved_backend)

      markdown_feature_profile.merge(backend: resolved_backend)
    end

    def markdown_plan_context(backend: nil)
      profile = markdown_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: markdown_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: profile[:backend] != "kreuzberg-language-pack",
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_markdown(source, dialect, backend: nil)
      return unsupported_feature_result("Unsupported Markdown dialect #{dialect}.") unless dialect == "markdown"

      resolved_backend = resolve_backend(backend)
      case resolved_backend
      when "kramdown"
        Kramdown::Document.new(source)
      when "kreuzberg-language-pack"
        syntax = TreeHaver.parse_with_language_pack(
          TreeHaver::ParserRequest.new(source: source, language: "markdown", dialect: dialect)
        )
        return { ok: false, diagnostics: syntax[:diagnostics], policies: [] } unless syntax[:ok]
      else
        return unsupported_feature_result("Unsupported Markdown backend #{resolved_backend}.")
      end

      normalized_source = normalize_source(source)
      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: "markdown",
          dialect: dialect,
          normalized_source: normalized_source,
          root_kind: "document",
          owners: collect_markdown_owners(normalized_source)
        },
        policies: []
      }
    rescue StandardError => e
      {
        ok: false,
        diagnostics: [{ severity: "error", category: "parse_error", message: e.message }],
        policies: []
      }
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

    def markdown_embedded_families(analysis)
      analysis[:owners].filter_map do |owner|
        next unless owner[:owner_kind] == "code_fence"
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
          surface_kind: "markdown_fenced_code_block",
          declared_language: candidate[:language],
          effective_language: candidate[:dialect],
          address: "document[0] > fenced_code_block[#{candidate[:path]}]",
          parent_address: "document[0]",
          owner: Ast::Merge.surface_owner_ref(kind: "structural_owner", address: candidate[:path]),
          reconstruction_strategy: "portable_write",
          metadata: {
            family: candidate[:family],
            dialect: candidate[:dialect],
            path: candidate[:path]
          }
        )
      end
    end

    def markdown_delegated_child_operations(analysis, parent_operation_id: "markdown-document-0")
      markdown_discovered_surfaces(analysis).each_with_index.map do |surface, index|
        Ast::Merge.delegated_child_operation(
          operation_id: "markdown-fence-#{index}",
          parent_operation_id: parent_operation_id,
          requested_strategy: "delegate_child_surface",
          language_chain: ["markdown", surface[:effective_language]],
          surface: surface
        )
      end
    end

    def normalize_source(source)
      source.gsub(/\r\n?/, "\n")
    end

    def slugify(value)
      slug = value
        .strip
        .downcase
        .gsub(/[`*_~\[\]()<>]/, "")
        .gsub(/[^a-z0-9]+/, "-")
        .gsub(/\A-+|-+\z/, "")
      slug.empty? ? "section" : slug
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
            owner_kind: "heading",
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
            owner_kind: "code_fence",
            match_key: "fence:#{info_string.empty? ? "plain" : info_string}",
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

    def code_fence_family(info_string)
      case info_string.to_s.downcase
      when "ts", "typescript"
        "typescript"
      when "rust", "rs"
        "rust"
      when "go"
        "go"
      when "json", "jsonc"
        "json"
      when "yaml", "yml"
        "yaml"
      when "toml"
        "toml"
      end
    end

    def code_fence_dialect(info_string, family)
      case family
      when "typescript", "rust", "go", "yaml", "toml"
        family
      when "json"
        info_string.to_s.downcase == "jsonc" ? "jsonc" : "json"
      end
    end

    def resolve_backend(backend)
      backend.to_s.empty? ? (TreeHaver.current_backend_id || "kramdown") : backend.to_s
    end

    def unsupported_feature_result(message)
      {
        ok: false,
        diagnostics: [{ severity: "error", category: "unsupported_feature", message: message }],
        policies: []
      }
    end

    module_function(
      :markdown_feature_profile,
      :available_markdown_backends,
      :markdown_backend_feature_profile,
      :markdown_plan_context,
      :parse_markdown,
      :match_markdown_owners,
      :markdown_embedded_families,
      :markdown_discovered_surfaces,
      :markdown_delegated_child_operations,
      :normalize_source,
      :slugify,
      :collect_markdown_owners,
      :code_fence_family,
      :code_fence_dialect,
      :resolve_backend,
      :unsupported_feature_result
    )
  end
end
