# frozen_string_literal: true

require 'json'
require 'tree_sitter_language_pack'

module TreeHaver
  LanguagePackResultError = Class.new(StandardError) unless const_defined?(:LanguagePackResultError)

  TSLP_BACKEND = BackendReference.new(
    id: 'tslp',
    family: 'tree-sitter'
  ).freeze
  KREUZBERG_LANGUAGE_PACK_BACKEND = BackendReference.new(
    id: 'kreuzberg-language-pack',
    family: 'tree-sitter'
  ).freeze

  BackendRegistry.register(TSLP_BACKEND)
  BackendRegistry.register(KREUZBERG_LANGUAGE_PACK_BACKEND)
  BackendRegistry.register_availability_checker(:tslp) do
    defined?(TreeSitterLanguagePack) && TreeSitterLanguagePack.respond_to?(:process)
  end
  BackendRegistry.register_availability_checker(:"kreuzberg-language-pack") do
    BackendRegistry.available?(:tslp)
  end

  module_function

  def language_pack_adapter_info
    AdapterInfo.new(
      backend: TSLP_BACKEND.id,
      backend_ref: TSLP_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def language_pack_feature_profile
    FeatureProfile.new(
      backend: TSLP_BACKEND.id,
      backend_ref: TSLP_BACKEND,
      supports_dialects: false,
      supported_policies: []
    )
  end

  def parse_with_language_pack(request)
    ensure_language_pack_language(request.language)
    raw = language_pack_result_hash(TreeSitterLanguagePack.process(
                                      request.source,
                                      JSON.generate(language: request.language, diagnostics: true)
                                    ))
    return language_pack_unsupported_result(request.language, 'diagnostics', 'process result was empty') unless raw

    diagnostics = Array(raw['diagnostics'])
    return parse_error_result(request.language) unless diagnostics.empty?

    analysis = LanguagePackAnalysis.new(
      language: request.language,
      dialect: request.dialect,
      root_type: inferred_root_type(request),
      has_error: false,
      backend_ref: TSLP_BACKEND
    )
    parse_result(ok: true, analysis: analysis, diagnostics: [])
  rescue LanguagePackResultError => e
    language_pack_unsupported_result(request.language, 'diagnostics', e.message)
  rescue StandardError => e
    language_pack_runtime_failure(request.language, 'diagnostics', e.message)
  end

  def process_with_language_pack(request)
    ensure_language_pack_language(request.language)
    raw = language_pack_result_hash(TreeSitterLanguagePack.process(
                                      request.source,
                                      JSON.generate(language: request.language, structure: true, imports: true,
                                                    diagnostics: true)
                                    ))
    unless raw
      return language_pack_unsupported_result(request.language, 'structure/imports/diagnostics',
                                              'process result was empty')
    end

    analysis = LanguagePackProcessAnalysis.new(
      language: raw.fetch('language'),
      structure: normalize_structure(Array(raw['structure'])),
      imports: normalize_imports(request.language, Array(raw['imports'])),
      diagnostics: Array(raw['diagnostics']).map do |item|
        ProcessDiagnostic.new(
          message: item.fetch('message'),
          severity: item.fetch('severity')
        )
      end,
      backend_ref: TSLP_BACKEND
    )
    parse_result(ok: true, analysis: analysis, diagnostics: [])
  rescue LanguagePackResultError => e
    language_pack_unsupported_result(request.language, 'structure/imports/diagnostics', e.message)
  rescue StandardError => e
    language_pack_runtime_failure(request.language, 'structure/imports/diagnostics', e.message)
  end

  def ensure_language_pack_language(language)
    return if TreeSitterLanguagePack.has_language(language)

    TreeSitterLanguagePack.init(JSON.generate(languages: [language]))
  end
  private_class_method :ensure_language_pack_language

  def language_pack_result_hash(raw)
    return raw if raw.is_a?(Hash)
    return raw.to_h if raw.respond_to?(:to_h)
    if raw.respond_to?(:language)
      return {
        'language' => raw.language,
        'structure' => Array(raw.structure).map { |item| language_pack_object_hash(item) },
        'imports' => Array(raw.imports).map { |item| language_pack_object_hash(item) },
        'diagnostics' => Array(raw.diagnostics).map { |item| language_pack_object_hash(item) }
      }
    end

    parsed = JSON.parse(raw.to_json)
    parsed.is_a?(Hash) ? parsed : nil
  rescue StandardError
    raise LanguagePackResultError, "Ruby binding could not expose a structured process result from #{raw.class}"
  end
  private_class_method :language_pack_result_hash

  def language_pack_object_hash(object)
    return object if object.is_a?(Hash)

    language_pack_object_methods.each_with_object({}) do |method_name, method_result|
      next unless object.respond_to?(method_name)

      method_result[method_name.to_s] = language_pack_object_value(object.public_send(method_name))
    rescue StandardError
      next
    end
  end
  private_class_method :language_pack_object_hash

  def language_pack_object_value(value)
    case value
    when nil, true, false, Numeric, String, Symbol
      value
    when Array
      value.map { |item| language_pack_object_value(item) }
    when Hash
      value.transform_values { |item| language_pack_object_value(item) }
    else
      language_pack_object_hash(value)
    end
  end
  private_class_method :language_pack_object_value

  def language_pack_object_methods
    %i[
      kind name visibility span children decorators doc_comment signature body_span
      source module names items message severity start_byte end_byte start_line
      start_column end_line end_column start_row start_col end_row end_col
    ]
  end
  private_class_method :language_pack_object_methods

  def language_pack_unsupported_result(language, feature, detail)
    parse_result(
      ok: false,
      diagnostics: [
        diagnostic(
          'error',
          'unsupported_feature',
          "tree-sitter-language-pack did not provide readable #{feature} for #{language}. " \
          "Please report this to tree-sitter-language-pack with this detail: #{detail}"
        )
      ]
    )
  end
  private_class_method :language_pack_unsupported_result

  def language_pack_runtime_failure(language, feature, detail)
    parse_result(
      ok: false,
      diagnostics: [
        diagnostic(
          'error',
          'unsupported_feature',
          "tree-sitter-language-pack failed while providing #{feature} for #{language}. " \
          "Please report this to tree-sitter-language-pack with this detail: #{detail}"
        )
      ]
    )
  end
  private_class_method :language_pack_runtime_failure

  def normalize_structure(items)
    items.flat_map do |item|
      normalized_item = ProcessStructureItem.new(
        kind: item.fetch('kind').downcase,
        name: item['name'],
        span: process_span(item.fetch('span'))
      )
      [normalized_item, *normalize_structure(Array(item['children']))]
    end
  end
  private_class_method :normalize_structure

  def parse_error_result(language)
    parse_result(
      ok: false,
      diagnostics: [
        diagnostic(
          'error',
          'parse_error',
          "tree-sitter-language-pack reported syntax errors for #{language}."
        )
      ]
    )
  end
  private_class_method :parse_error_result

  def process_span(raw)
    ProcessSpan.new(
      start_byte: raw.fetch('start_byte'),
      end_byte: raw.fetch('end_byte'),
      start_row: raw['start_row'] || raw.fetch('start_line'),
      start_col: raw['start_col'] || raw.fetch('start_column'),
      end_row: raw['end_row'] || raw.fetch('end_line'),
      end_col: raw['end_col'] || raw.fetch('end_column')
    )
  end
  private_class_method :process_span

  def inferred_root_type(request)
    stripped = request.source.lstrip
    case request.language
    when 'json'
      return 'object' if stripped.start_with?('{')
      return 'array' if stripped.start_with?('[')

      'scalar'
    else
      request.language
    end
  end
  private_class_method :inferred_root_type

  def normalize_imports(language, raw_imports)
    raw_imports.map do |item|
      source, items =
        if language == 'typescript'
          normalize_typescript_import(item)
        else
          [item['module'] || item['source'] || '', Array(item['names'] || item['items'])]
        end

      ProcessImportInfo.new(
        source: source,
        items: items,
        span: process_span(item.fetch('span'))
      )
    end
  end
  private_class_method :normalize_imports

  def normalize_typescript_import(item)
    raw_source = item['module'] || item['source'] || ''
    source = quoted_import_source(raw_source) || raw_source.strip
    names = if (named_items = braced_import_items(raw_source))
              named_items
                .split(',')
                .map { |part| part.split.reject { |word| word == 'type' }.join(' ') }
                .reject(&:empty?)
            else
              Array(item['names'] || item['items'])
            end

    [source, names]
  end
  private_class_method :normalize_typescript_import

  def quoted_import_source(source)
    %w[from import].each do |marker|
      marker_index = source.index(marker)
      next unless marker_index

      quoted = quoted_segment(source, marker_index + marker.length)
      return quoted if quoted
    end
    nil
  end
  private_class_method :quoted_import_source

  def quoted_segment(source, start_index)
    quote_index = [source.index("'", start_index), source.index('"', start_index)].compact.min
    return nil unless quote_index

    quote = source[quote_index]
    close_index = source.index(quote, quote_index + 1)
    close_index ? source[(quote_index + 1)...close_index] : nil
  end
  private_class_method :quoted_segment

  def braced_import_items(source)
    open_index = source.index('{')
    return nil unless open_index

    close_index = source.index('}', open_index + 1)
    close_index ? source[(open_index + 1)...close_index] : nil
  end
  private_class_method :braced_import_items

  def parse_result(ok:, diagnostics:, analysis: nil, policies: [])
    {
      ok: ok,
      diagnostics: diagnostics,
      **(analysis ? { analysis: analysis } : {}),
      policies: policies
    }
  end
  private_class_method :parse_result

  def diagnostic(severity, category, message)
    {
      severity: severity,
      category: category,
      message: message
    }
  end
  private_class_method :diagnostic
end
