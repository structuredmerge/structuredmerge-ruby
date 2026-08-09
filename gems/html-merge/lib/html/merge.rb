# frozen_string_literal: true

require "version_gem"

require "tree_haver"
require "ast/merge"
require_relative "merge/version"

module Html
  module Merge
    PACKAGE_NAME = "html-merge"
    BACKEND_REFERENCE = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    class Error < Ast::Merge::Error; end
    class ParseError < Ast::Merge::ParseError; end

    autoload :CrisprAdapter, "html/merge/crispr_adapter"
    autoload :NodeWrapper, "html/merge/node_wrapper"
    autoload :FileAnalysis, "html/merge/file_analysis"
    autoload :Provider, "html/merge/provider"

    module_function

    def register_backend!
      BACKEND_REGISTRY.mutex.synchronize do
        return if BACKEND_REGISTRY.registered

        TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)

        grammar_finder = TreeHaver::GrammarFinder.new(:html)
        grammar_finder.register! if grammar_finder.available?

        BACKEND_REGISTRY.registered = true
      end
    end

    def html_feature_profile
      {
        family: "html",
        supported_dialects: ["html"],
        supported_policies: []
      }
    end

    def available_html_backends
      html_backend_available_for_analysis?(BACKEND_REFERENCE.id) ? [BACKEND_REFERENCE] : []
    end

    def html_backend_feature_profile(backend: nil)
      requested = requested_html_backend_id(backend)
      unless available_html_backends.any? { |backend_ref| backend_ref.id == requested }
        return unsupported_feature_result("Unsupported HTML backend #{requested}.")
      end

      html_feature_profile.merge(
        backend: requested,
        backend_ref: BACKEND_REFERENCE.to_h
      )
    end

    def html_plan_context(backend: nil)
      profile = html_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: html_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: false,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_html(source, dialect = "html", backend: nil)
      return unsupported_feature_result("Unsupported HTML dialect #{dialect}.") unless dialect.to_s == "html"

      requested = requested_html_backend_id(backend)
      unless available_html_backends.any? { |backend_ref| backend_ref.id == requested }
        return unsupported_feature_result("Unsupported HTML backend #{requested}.")
      end

      register_backend!
      tree = TreeHaver.with_backend(requested) { TreeHaver.parser_for(:html).parse(source.to_s) }
      root = tree.root_node
      diagnostics = html_parse_error_nodes(root).map do |node|
        {
          severity: "error",
          category: "parse_error",
          message: "HTML parse error in #{node.type}",
          span: html_node_span(node)
        }
      end
      return { ok: false, diagnostics: diagnostics, policies: [] } unless diagnostics.empty?

      {
        ok: true,
        diagnostics: [],
        analysis: {
          dialect: "html",
          root_kind: root.type,
          nodes: html_node_summaries(root)
        },
        policies: []
      }
    rescue TreeHaver::Error, StandardError => e
      {
        ok: false,
        diagnostics: [{
          severity: "error",
          category: "parse_error",
          message: e.message
        }],
        policies: []
      }
    end

    def html_root_node(source, backend: nil)
      requested = requested_html_backend_id(backend)
      register_backend!
      TreeHaver.with_backend(requested) { TreeHaver.parser_for(:html).parse(source.to_s).root_node }
    end

    def html_node_summaries(root)
      nodes = []
      visit_html_node(root) do |node|
        next unless node.structural?

        nodes << {
          type: node.type,
          span: html_node_span(node),
          text: node.text.to_s.strip[0, 120]
        }
      end
      nodes
    end

    def html_parse_error_nodes(root)
      errors = []
      visit_html_node(root) do |node|
        errors << node if node.has_error? || node.type == "ERROR"
      end
      errors
    end

    def visit_html_node(node, &block)
      yield node
      node.child_count.times do |index|
        child = node.child(index)
        visit_html_node(child, &block) if child
      end
    end

    def html_node_span(node)
      start_point = html_point(html_raw_point(node, :start))
      end_point = html_point(html_raw_point(node, :end))
      {
        start_byte: node.start_byte,
        end_byte: node.end_byte,
        start_line: start_point.fetch(:row) + 1,
        end_line: end_point.fetch(:row) + 1,
        start_column: start_point.fetch(:column),
        end_column: end_point.fetch(:column)
      }
    end

    def html_raw_point(node, boundary)
      raw_node = node.respond_to?(:inner_node) ? node.inner_node : node
      methods = boundary == :start ? %i[start_point start_position] : %i[end_point end_position]
      methods.each do |method_name|
        return raw_node.public_send(method_name) if raw_node.respond_to?(method_name)
      end

      node.public_send(methods.first)
    end

    def html_point(point)
      return { row: point.row, column: point.column } if point.respond_to?(:row) && point.respond_to?(:column)

      return { row: point[:row], column: point[:column] } if point.respond_to?(:[])

      raise Error, "Unsupported TreeHaver point #{point.inspect}"
    end

    def html_backend_available_for_analysis?(backend_id)
      requested = requested_html_backend_id(backend_id)
      register_backend!
      TreeHaver.with_backend(requested) { TreeHaver.parser_for(:html).respond_to?(:parse) }
    rescue TreeHaver::Error, StandardError
      false
    end

    def requested_html_backend_id(backend)
      backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
    end

    def unsupported_feature_result(message)
      {
        ok: false,
        diagnostics: [{
          severity: "error",
          category: "unsupported_feature",
          message: message
        }],
        policies: []
      }
    end

    def document_context(content:, source_label: "source")
      require "ast/crispr"

      Ast::Crispr::DocumentContext.new(
        content: content,
        source_label: source_label,
        adapter: CrisprAdapter.new
      )
    end

    def element_text_selector(text:, id: nil)
      require "ast/crispr"

      Ast::Crispr::Selectors.owner_filter(
        id: id || "html_element_text:#{text}",
        adapter: CrisprAdapter.new,
        owner_scope: :html_element
      ) do |_context, owner|
        owner.type == "element" &&
          owner.text.include?(text.to_s) &&
          !html_descendant_element_text?(owner.node, text.to_s)
      end
    end

    def html_descendant_element_text?(node, text)
      node.child_count.times.any? do |index|
        child = node.child(index)
        next false unless child

        (child.type == "element" && child.text.include?(text)) || html_descendant_element_text?(child, text)
      end
    end

    def ensure_yard_content_wrapper(source)
      require "ast/crispr"

      replacement = %(<div id="content"><h1 class="noborder title">Documentation by YARD</h1></div>\n)
      target = element_text_selector(text: "Documentation by YARD", id: "yard_title_element")
      actor = Ast::Crispr::Replace.result(content: source.to_s, target: target, replacement: replacement)
      if actor.failure?
        raise Error, actor.respond_to?(:error) ? actor.error.to_s : "HTML CRISPR replacement failed"
      end

      actor.updated_content
    end

    def merge_provider
      @merge_provider ||= Provider.new
    end

    def register_provider!(replace: false)
      return unless Ast::Merge.respond_to?(:register_provider)

      Ast::Merge.register_provider(merge_provider, replace: replace)
    end
  end
end

Html::Merge::Version.class_eval do
  extend VersionGem::Basic
end

Html::Merge.register_backend!
Html::Merge.register_provider!
