# frozen_string_literal: true

module TreeHaver
  ParserRequest = Struct.new(:source, :language, :dialect, keyword_init: true) do
    def to_h
      {
        source: source,
        language: language,
        **(dialect ? { dialect: dialect } : {})
      }
    end
  end

  BackendReference = Struct.new(:id, :family, keyword_init: true) do
    def to_h
      { id: id, family: family }
    end
  end

  AdapterInfo = Struct.new(:backend, :backend_ref, :supports_dialects, :supported_policies, keyword_init: true) do
    def to_h
      {
        backend: backend,
        **(backend_ref ? { backend_ref: backend_ref.to_h } : {}),
        supports_dialects: supports_dialects,
        supported_policies: deep_dup(supported_policies || [])
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  FeatureProfile = Struct.new(:backend, :backend_ref, :supports_dialects, :supported_policies, keyword_init: true) do
    def to_h
      {
        backend: backend,
        **(backend_ref ? { backend_ref: backend_ref.to_h } : {}),
        supports_dialects: supports_dialects,
        supported_policies: deep_dup(supported_policies || [])
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  ParserDiagnostics = Struct.new(:backend, :backend_ref, :diagnostics, keyword_init: true) do
    def to_h
      {
        backend: backend,
        **(backend_ref ? { backend_ref: backend_ref.to_h } : {}),
        diagnostics: deep_dup(diagnostics || [])
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  ProcessRequest = Struct.new(:source, :language, keyword_init: true) do
    def to_h
      {
        source: source,
        language: language
      }
    end
  end

  ProcessSpan = Struct.new(:start_byte, :end_byte, :start_row, :start_col, :end_row, :end_col, keyword_init: true) do
    def to_h
      {
        start_byte: start_byte,
        end_byte: end_byte,
        start_row: start_row,
        start_col: start_col,
        end_row: end_row,
        end_col: end_col
      }
    end
  end

  ProcessStructureItem = Struct.new(:kind, :name, :span, keyword_init: true) do
    def to_h
      {
        kind: kind,
        **(name ? { name: name } : {}),
        span: span.to_h
      }
    end
  end

  ProcessImportInfo = Struct.new(:source, :items, :span, keyword_init: true) do
    def to_h
      {
        source: source,
        items: deep_dup(items || []),
        span: span.to_h
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  ProcessDiagnostic = Struct.new(:message, :severity, keyword_init: true) do
    def to_h
      {
        message: message,
        severity: severity
      }
    end
  end

  LanguagePackAnalysis = Struct.new(:language, :dialect, :root_type, :has_error, :backend_ref, keyword_init: true) do
    def kind
      "tree-sitter"
    end

    def to_h
      {
        kind: kind,
        language: language,
        **(dialect ? { dialect: dialect } : {}),
        root_type: root_type,
        has_error: has_error,
        backend_ref: backend_ref.to_h
      }
    end
  end

  LanguagePackProcessAnalysis = Struct.new(:language, :structure, :imports, :diagnostics, :backend_ref, keyword_init: true) do
    def kind
      "tree-sitter-process"
    end

    def to_h
      {
        kind: kind,
        language: language,
        structure: (structure || []).map(&:to_h),
        imports: (imports || []).map(&:to_h),
        diagnostics: (diagnostics || []).map(&:to_h),
        backend_ref: backend_ref.to_h
      }
    end
  end
end
