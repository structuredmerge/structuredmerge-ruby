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

  ParserIdentity = Struct.new(:name, :version, :implementation, keyword_init: true) do
    def to_h
      {
        name: name,
        version: version,
        implementation: implementation
      }
    end
  end

  LanguageVersion = Struct.new(:version, :dialect, keyword_init: true) do
    def to_h
      {
        version: version,
        dialect: dialect
      }
    end
  end

  BackendCapability = Struct.new(
    :backend_ref,
    :language,
    :parser_identity,
    :language_version,
    :parse_error_behavior,
    :source_span_support,
    :source_fragment_support,
    :render_strategies,
    :semantic_role_support,
    :normalized_tree_support,
    :native_node_access,
    :known_node_kinds,
    :known_fields,
    :grammar_inventory,
    :diagnostics,
    keyword_init: true
  ) do
    def to_h
      {
        backend_ref: backend_ref.to_h,
        language: language,
        parser_identity: parser_identity.to_h,
        language_version: language_version.to_h,
        parse_error_behavior: parse_error_behavior,
        source_span_support: source_span_support,
        source_fragment_support: source_fragment_support,
        render_strategies: render_strategies,
        semantic_role_support: semantic_role_support,
        normalized_tree_support: normalized_tree_support,
        native_node_access: native_node_access,
        known_node_kinds: known_node_kinds || [],
        known_fields: known_fields || [],
        grammar_inventory: grammar_inventory,
        diagnostics: diagnostics
      }
    end
  end

  ParseErrorNode = Struct.new(:kind, :span, :message, keyword_init: true) do
    def to_h
      {
        kind: kind,
        span: span.to_h,
        message: message
      }
    end
  end

  ParseErrorTolerance = Struct.new(:backend_ref, :language, :behavior, :tolerates_errors, :error_nodes, :diagnostics,
                                   keyword_init: true) do
    def to_h
      {
        backend_ref: backend_ref.to_h,
        language: language,
        behavior: behavior,
        tolerates_errors: tolerates_errors,
        error_nodes: (error_nodes || []).map(&:to_h),
        diagnostics: diagnostics
      }
    end
  end

  NativeParserProvider = Struct.new(:id, :family, :language, :operations, :retains_native_tree,
                                    :native_tree_visibility, :metadata_policy, keyword_init: true) do
    def to_h
      {
        id: id,
        family: family,
        language: language,
        operations: operations || [],
        retains_native_tree: retains_native_tree,
        native_tree_visibility: native_tree_visibility,
        metadata_policy: metadata_policy
      }
    end
  end

  NativeProviderMetadata = Struct.new(
    :provider_id,
    :family,
    :host_language,
    :target_language,
    :parser_name,
    :parser_version,
    :language_version,
    :dialect,
    :parse_error_behavior,
    :source_span_support,
    :render_support,
    :semantic_role_support,
    :retains_native_tree,
    :native_tree_visibility,
    :metadata_policy,
    :diagnostics,
    keyword_init: true
  ) do
    def to_h
      {
        provider_id: provider_id,
        family: family,
        host_language: host_language,
        target_language: target_language,
        parser_name: parser_name,
        parser_version: parser_version,
        language_version: language_version,
        dialect: dialect,
        parse_error_behavior: parse_error_behavior,
        source_span_support: source_span_support,
        render_support: render_support,
        semantic_role_support: semantic_role_support,
        retains_native_tree: retains_native_tree,
        native_tree_visibility: native_tree_visibility,
        metadata_policy: metadata_policy,
        diagnostics: diagnostics || []
      }
    end
  end

  NormalizedParseResult = Struct.new(
    :ok,
    :backend_capability,
    :root_id,
    :nodes,
    :parse_error_tolerance,
    :source_fragments_available,
    :diagnostics,
    :metadata,
    keyword_init: true
  ) do
    def to_h
      {
        ok: ok,
        backend_capability: backend_capability.to_h,
        root_id: root_id,
        nodes: (nodes || []).map(&:to_h),
        parse_error_tolerance: parse_error_tolerance.to_h,
        source_fragments_available: source_fragments_available,
        diagnostics: diagnostics || [],
        metadata: metadata || {}
      }
    end
  end

  TreeHaverProfile = Struct.new(
    :profile_id,
    :language,
    :backend_ref,
    :provider_id,
    :node_roles,
    :normalized_node_fields,
    :optional_node_features,
    :unsupported_defaults,
    :capability,
    :fixture_slices,
    :diagnostics,
    keyword_init: true
  ) do
    def to_h
      {
        profile_id: profile_id,
        language: language,
        backend_ref: backend_ref.to_h,
        provider_id: provider_id,
        node_roles: node_roles || [],
        normalized_node_fields: normalized_node_fields || [],
        optional_node_features: optional_node_features || [],
        unsupported_defaults: unsupported_defaults || {},
        capability: capability.to_h,
        fixture_slices: fixture_slices || [],
        diagnostics: diagnostics || []
      }
    end
  end

  OrderedSiblingEdge = Struct.new(:parent_id, :node_id, :previous_sibling_id, :next_sibling_id, keyword_init: true) do
    def to_h
      {
        parent_id: parent_id,
        node_id: node_id,
        previous_sibling_id: previous_sibling_id,
        next_sibling_id: next_sibling_id
      }
    end
  end

  OrderedTreePrimitives = Struct.new(:root_id, :child_order, :sibling_edges, :diagnostics, keyword_init: true) do
    def to_h
      {
        root_id: root_id,
        child_order: child_order || {},
        sibling_edges: (sibling_edges || []).map(&:to_h),
        diagnostics: diagnostics || []
      }
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

  ByteRange = Struct.new(:start_byte, :end_byte, keyword_init: true) do
    def valid?
      start_byte.to_i >= 0 && end_byte.to_i >= start_byte.to_i
    end

    def length
      valid? ? end_byte.to_i - start_byte.to_i : 0
    end

    def contains_byte?(offset)
      valid? && offset.to_i >= start_byte.to_i && offset.to_i < end_byte.to_i
    end

    def contains_range?(other)
      valid? && other.valid? && other.start_byte.to_i >= start_byte.to_i && other.end_byte.to_i <= end_byte.to_i
    end

    def overlaps?(other)
      valid? && other.valid? && start_byte.to_i < other.end_byte.to_i && other.start_byte.to_i < end_byte.to_i
    end

    def to_h
      {
        start_byte: start_byte,
        end_byte: end_byte
      }
    end
  end

  EditProjectionSupport = Struct.new(
    :backend_ref,
    :language,
    :supports_edit_projection,
    :native_edit_target,
    :normalized_edit_target,
    :supported_operations,
    :required_node_fields,
    :correlation_keys,
    :preserves_source_fragments,
    :unsupported_reason,
    :diagnostics,
    keyword_init: true
  ) do
    def to_h
      {
        backend_ref: backend_ref.to_h,
        language: language,
        supports_edit_projection: supports_edit_projection,
        native_edit_target: native_edit_target,
        normalized_edit_target: normalized_edit_target,
        supported_operations: supported_operations || [],
        required_node_fields: required_node_fields || [],
        correlation_keys: correlation_keys || [],
        preserves_source_fragments: preserves_source_fragments,
        unsupported_reason: unsupported_reason,
        diagnostics: diagnostics || []
      }
    end
  end

  LibraryPathValidation = Struct.new(:path, :valid, :errors, keyword_init: true) do
    def to_h
      {
        path: path,
        valid: valid,
        errors: errors || []
      }
    end
  end

  BackendAvailabilityCheck = Struct.new(:name, :status, :required, :diagnostics, keyword_init: true) do
    def to_h
      {
        name: name,
        status: status,
        required: required,
        diagnostics: diagnostics || []
      }
    end
  end

  BackendAvailabilityReport = Struct.new(:backend_ref, :status, :checks, :diagnostics, keyword_init: true) do
    def to_h
      {
        backend_ref: backend_ref.to_h,
        status: status,
        checks: (checks || []).map(&:to_h),
        diagnostics: diagnostics || []
      }
    end
  end

  ProviderDiagnostic = Struct.new(:severity, :category, :code, :message, :path, :blocking, keyword_init: true) do
    def to_h
      {
        severity: severity,
        category: category,
        code: code,
        message: message,
        path: path,
        blocking: blocking
      }
    end
  end

  ProviderDiagnosticsReport = Struct.new(:provider_id, :backend_ref, :language, :status, :diagnostics,
                                         keyword_init: true) do
    def to_h
      {
        provider_id: provider_id,
        backend_ref: backend_ref.to_h,
        language: language,
        status: status,
        diagnostics: (diagnostics || []).map(&:to_h)
      }
    end
  end

  EditProjectionOperationRequest = Struct.new(:operation, :target_node_id, :target_node_path, :replacement_source,
                                              keyword_init: true) do
    def to_h
      {
        operation: operation,
        target_node_id: target_node_id,
        target_node_path: target_node_path,
        replacement_source: replacement_source
      }
    end
  end

  EditProjectionExecutionRequest = Struct.new(:provider_id, :backend_ref, :language, :source, :operations,
                                              keyword_init: true) do
    def to_h
      {
        provider_id: provider_id,
        backend_ref: backend_ref.to_h,
        language: language,
        source: source,
        operations: (operations || []).map(&:to_h)
      }
    end
  end

  AppliedEditProjectionOperation = Struct.new(:operation, :target_node_id, :correlation_key, :correlation_value,
                                              keyword_init: true) do
    def to_h
      {
        operation: operation,
        target_node_id: target_node_id,
        correlation_key: correlation_key,
        correlation_value: correlation_value
      }
    end
  end

  EditProjectionExecutionResult = Struct.new(:ok, :status, :source, :applied_operations, :diagnostics,
                                             keyword_init: true) do
    def to_h
      {
        ok: ok,
        status: status,
        source: source,
        applied_operations: (applied_operations || []).map(&:to_h),
        diagnostics: (diagnostics || []).map(&:to_h)
      }
    end
  end

  EditProjectionProviderOperation = Struct.new(
    :operation,
    :status,
    :node_scope,
    :correlation_keys,
    :fixture_slices,
    :formatting_preservation,
    :diagnostics,
    keyword_init: true
  ) do
    def to_h
      {
        operation: operation,
        status: status,
        node_scope: node_scope,
        correlation_keys: correlation_keys || [],
        fixture_slices: fixture_slices || [],
        formatting_preservation: formatting_preservation,
        diagnostics: diagnostics || []
      }
    end
  end

  EditProjectionProviderMatrixEntry = Struct.new(
    :provider_id,
    :backend_ref,
    :language,
    :formatting_preservation,
    :preserves_source_fragments,
    :operations,
    keyword_init: true
  ) do
    def to_h
      {
        provider_id: provider_id,
        backend_ref: backend_ref.to_h,
        language: language,
        formatting_preservation: formatting_preservation,
        preserves_source_fragments: preserves_source_fragments,
        operations: (operations || []).map(&:to_h)
      }
    end
  end

  EditProjectionProviderMatrix = Struct.new(:operations, :providers, :diagnostics, keyword_init: true) do
    def to_h
      {
        operations: operations || [],
        providers: (providers || []).map(&:to_h),
        diagnostics: diagnostics || []
      }
    end
  end

  SourcePoint = Struct.new(:row, :column, keyword_init: true) do
    def to_h
      {
        row: row,
        column: column
      }
    end
  end

  SourceSpan = Struct.new(:range, :start_point, :end_point, keyword_init: true) do
    def to_h
      {
        range: range.to_h,
        start_point: start_point.to_h,
        end_point: end_point.to_h
      }
    end
  end

  NODE_ROLES = %w[
    structural
    token
    trivia
    comment
    delimiter
    separator
    virtual
    error
    opaque
  ].freeze

  NormalizedTreeNode = Struct.new(
    :id,
    :kind,
    :role,
    :parent_id,
    :child_ids,
    :span,
    :field_name,
    :named,
    :anonymous,
    :has_source_text,
    :source_fragment,
    :backend_kind,
    :semantic_roles,
    :backend_roles,
    :unsupported_features,
    :metadata,
    keyword_init: true
  ) do
    def to_h
      {
        id: id,
        kind: kind,
        role: role,
        parent_id: parent_id,
        child_ids: child_ids,
        span: span.to_h,
        field_name: field_name,
        named: named,
        anonymous: anonymous,
        has_source_text: has_source_text,
        source_fragment: source_fragment,
        backend_kind: backend_kind,
        semantic_roles: semantic_roles || [],
        backend_roles: backend_roles || [],
        unsupported_features: unsupported_features || [],
        metadata: metadata || {}
      }
    end
  end

  SourceFragment = Struct.new(:text, :span, :available, :strategy, :byte_length, :diagnostics, keyword_init: true) do
    def to_h
      {
        text: text,
        span: span.to_h,
        available: available,
        strategy: strategy,
        byte_length: byte_length,
        diagnostics: diagnostics
      }
    end
  end

  def node_roles
    NODE_ROLES.dup
  end
  module_function :node_roles

  MAX_LIBRARY_PATH_LENGTH = 4096
  VALID_LIBRARY_FILENAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
  VALID_LANGUAGE_NAME_PATTERN = /\A[a-z][a-z0-9_]*\z/
  VALID_SYMBOL_NAME_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/
  VERSIONED_SHARED_OBJECT_PATTERN = /\.so\.\d+\z/

  def validate_library_path(path)
    errors = library_path_errors(path)
    LibraryPathValidation.new(path: path, valid: errors.empty?, errors: errors)
  end
  module_function :validate_library_path

  def library_path_errors(path)
    value = path.to_s
    errors = []

    errors << 'path_empty' if value.empty?
    errors << 'path_too_long' if value.length > MAX_LIBRARY_PATH_LENGTH
    errors << 'path_contains_null_byte' if value.include?("\0")
    errors << 'path_not_absolute' unless value.start_with?('/') || windows_absolute_path?(value)

    segments = value.split(%r{[/\\]})
    errors << 'path_contains_parent_traversal' if segments.include?('..')
    errors << 'path_contains_current_directory_traversal' if segments.include?('.')
    errors << 'path_extension_not_allowed' unless allowed_library_extension?(value)
    unless VALID_LIBRARY_FILENAME_PATTERN.match?(library_filename(value))
      errors << 'filename_contains_invalid_characters'
    end

    errors
  end
  module_function :library_path_errors

  def safe_language_name?(name)
    VALID_LANGUAGE_NAME_PATTERN.match?(name.to_s)
  end
  module_function :safe_language_name?

  def sanitize_language_name(name)
    sanitized = name.to_s.downcase.gsub(/[^a-z0-9_]/, '')
    safe_language_name?(sanitized) ? sanitized : nil
  end
  module_function :sanitize_language_name

  def safe_symbol_name?(symbol)
    VALID_SYMBOL_NAME_PATTERN.match?(symbol.to_s)
  end
  module_function :safe_symbol_name?

  def safe_backend_name?(name)
    name.to_s == 'auto' || !BackendRegistry.fetch(name.to_s).nil?
  end
  module_function :safe_backend_name?

  def build_backend_availability_report(backend_ref, checks)
    if checks.empty?
      return BackendAvailabilityReport.new(
        backend_ref: backend_ref,
        status: 'unknown',
        checks: [],
        diagnostics: ['backend availability unknown: no checks supplied']
      )
    end

    diagnostics = []
    status = 'available'
    checks.each do |check|
      next unless check.required && check.status != 'available'

      status = 'unavailable'
      diagnostics << "backend unavailable: required check #{check.name} is #{check.status}"
    end
    BackendAvailabilityReport.new(backend_ref: backend_ref, status: status, checks: checks, diagnostics: diagnostics)
  end
  module_function :build_backend_availability_report

  def build_provider_diagnostics_report(provider_id, backend_ref, language, diagnostics)
    status = 'clean'
    diagnostics.each do |diagnostic|
      if diagnostic.blocking
        status = 'blocked'
        break
      end
      status = 'warning' if diagnostic.severity == 'warning'
    end
    ProviderDiagnosticsReport.new(
      provider_id: provider_id,
      backend_ref: backend_ref,
      language: language,
      status: status,
      diagnostics: diagnostics
    )
  end
  module_function :build_provider_diagnostics_report

  def build_edit_projection_execution_result(source, applied_operations, diagnostics)
    if diagnostics.any?(&:blocking)
      return EditProjectionExecutionResult.new(
        ok: false,
        status: 'rejected',
        source: source,
        applied_operations: [],
        diagnostics: diagnostics
      )
    end

    EditProjectionExecutionResult.new(
      ok: true,
      status: 'applied',
      source: source,
      applied_operations: applied_operations,
      diagnostics: diagnostics
    )
  end
  module_function :build_edit_projection_execution_result

  def build_edit_projection_provider_matrix(operations, providers, diagnostics)
    EditProjectionProviderMatrix.new(
      operations: operations || [],
      providers: providers || [],
      diagnostics: diagnostics || []
    )
  end
  module_function :build_edit_projection_provider_matrix

  def windows_absolute_path?(path)
    %r{\A[A-Za-z]:[/\\]}.match?(path)
  end
  module_function :windows_absolute_path?
  private_class_method :windows_absolute_path?

  def allowed_library_extension?(path)
    normalized_path = path.downcase
    normalized_path.end_with?('.so', '.dylib', '.dll') || VERSIONED_SHARED_OBJECT_PATTERN.match?(normalized_path)
  end
  module_function :allowed_library_extension?
  private_class_method :allowed_library_extension?

  def library_filename(path)
    path.split(%r{[/\\]}).last.to_s
  end
  module_function :library_filename
  private_class_method :library_filename

  ByteEditSpan = Struct.new(:start_byte, :old_end_byte, :new_end_byte, :start_point, :old_end_point, :new_end_point,
                            keyword_init: true) do
    def old_range
      ByteRange.new(start_byte: start_byte, end_byte: old_end_byte)
    end

    def new_range
      ByteRange.new(start_byte: start_byte, end_byte: new_end_byte)
    end

    def byte_delta
      new_end_byte.to_i - old_end_byte.to_i
    end

    def to_h
      {
        start_byte: start_byte,
        old_end_byte: old_end_byte,
        new_end_byte: new_end_byte,
        start_point: start_point.to_h,
        old_end_point: old_end_point.to_h,
        new_end_point: new_end_point.to_h
      }
    end
  end

  BinaryScalarValue = Struct.new(:kind, :value, :symbol, :raw_value, :encoding, :format, :description,
                                 keyword_init: true) do
    def to_h
      {
        kind: kind,
        **(value.nil? ? {} : { value: value }),
        **(symbol.nil? ? {} : { symbol: symbol }),
        **(raw_value.nil? ? {} : { raw_value: raw_value }),
        **(encoding.nil? ? {} : { encoding: encoding }),
        **(format.nil? ? {} : { format: format }),
        **(description.nil? ? {} : { description: description })
      }
    end
  end

  BinaryRenderPolicy = Struct.new(:schema_path, :byte_range, :operation, :disposition, :reason, keyword_init: true) do
    def to_h
      {
        schema_path: schema_path,
        **(byte_range ? { byte_range: byte_range.to_h } : {}),
        operation: operation,
        disposition: disposition,
        reason: reason
      }
    end
  end

  BinaryDiagnostic = Struct.new(:severity, :category, :message, :schema_path, :byte_range, keyword_init: true) do
    def to_h
      {
        severity: severity,
        category: category,
        message: message,
        schema_path: schema_path,
        **(byte_range ? { byte_range: byte_range.to_h } : {})
      }
    end
  end

  BinaryNestedDispatch = Struct.new(:schema_path, :family, :status, keyword_init: true) do
    def to_h
      {
        schema_path: schema_path,
        family: family,
        status: status
      }
    end
  end

  BinaryPayloadRegion = Struct.new(:kind, :schema_path, :byte_range, :expected_hex, keyword_init: true) do
    def to_h
      {
        kind: kind,
        schema_path: schema_path,
        byte_range: byte_range.to_h,
        expected_hex: expected_hex
      }
    end
  end

  BinaryRawPayload = Struct.new(:encoding, :value, :byte_length, :regions, keyword_init: true) do
    def to_h
      {
        encoding: encoding,
        value: value,
        byte_length: byte_length,
        regions: (regions || []).map(&:to_h)
      }
    end
  end

  BinaryMergeReport = Struct.new(:format, :schema, :matched_schema_paths, :preserved_ranges, :rewritten_nodes,
                                 :checksum_updates, :nested_dispatches, :diagnostics, keyword_init: true) do
    def to_h
      {
        format: format,
        schema: schema,
        matched_schema_paths: deep_dup(matched_schema_paths || []),
        preserved_ranges: (preserved_ranges || []).map(&:to_h),
        rewritten_nodes: deep_dup(rewritten_nodes || []),
        checksum_updates: deep_dup(checksum_updates || []),
        nested_dispatches: (nested_dispatches || []).map(&:to_h),
        diagnostics: (diagnostics || []).map(&:to_h)
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  ZipArchiveInfo = Struct.new(:format, :schema, :entry_count, :central_directory_range, keyword_init: true) do
    def to_h
      {
        format: format,
        schema: schema,
        entry_count: entry_count,
        central_directory_range: central_directory_range.to_h
      }
    end
  end

  ZipArchiveEntry = Struct.new(:path, :normalized_path, :directory, :compression, :compressed_size, :uncompressed_size,
                               :crc32, :local_header_range, :data_range, :central_directory_range, keyword_init: true) do
    def to_h
      {
        path: path,
        normalized_path: normalized_path,
        directory: directory,
        compression: compression,
        compressed_size: compressed_size,
        uncompressed_size: uncompressed_size,
        crc32: crc32,
        local_header_range: local_header_range.to_h,
        data_range: data_range.to_h,
        central_directory_range: central_directory_range.to_h
      }
    end
  end

  ZipMemberDecision = Struct.new(:normalized_path, :operation, :disposition, :nested_family, :reason,
                                 keyword_init: true) do
    def to_h
      {
        normalized_path: normalized_path,
        operation: operation,
        disposition: disposition,
        **(nested_family ? { nested_family: nested_family } : {}),
        reason: reason
      }
    end
  end

  ZipUnsafeEntry = Struct.new(:path, :normalized_path, :category, :reason, keyword_init: true) do
    def to_h
      {
        path: path,
        normalized_path: normalized_path,
        category: category,
        reason: reason
      }
    end
  end

  ZipFamilyReport = Struct.new(:archive, :entries, :member_decisions, :merge_report, :unsafe_entries,
                               keyword_init: true) do
    def to_h
      {
        archive: archive.to_h,
        entries: (entries || []).map(&:to_h),
        member_decisions: (member_decisions || []).map(&:to_h),
        unsafe_entries: (unsafe_entries || []).map(&:to_h),
        merge_report: merge_report.to_h
      }
    end
  end

  def self.slice_byte_range(source, byte_range)
    source_bytesize = source.to_s.bytesize
    unless byte_range.valid? && byte_range.end_byte.to_i <= source_bytesize
      raise RangeError,
            "invalid byte range [#{byte_range.start_byte}, #{byte_range.end_byte}) for source length #{source_bytesize}"
    end

    source.to_s.byteslice(byte_range.start_byte.to_i...byte_range.end_byte.to_i)
  end

  def self.extract_source_fragment(source, span, strategy)
    text = slice_byte_range(source, span.range)
    SourceFragment.new(
      text: text,
      span: span,
      available: true,
      strategy: strategy,
      byte_length: text.bytesize,
      diagnostics: []
    )
  rescue RangeError => e
    SourceFragment.new(
      text: '',
      span: span,
      available: false,
      strategy: strategy,
      byte_length: 0,
      diagnostics: [e.message]
    )
  end

  def self.byte_offset_for_point(source, point)
    if point.row.to_i.negative? || point.column.to_i.negative?
      raise RangeError,
            "invalid source point (#{point.row}, #{point.column})"
    end

    row = 0
    column = 0
    source.to_s.bytes.each_with_index do |byte, offset|
      return offset if row == point.row.to_i && column == point.column.to_i

      if byte == 10
        row += 1
        column = 0
      else
        column += 1
      end
    end
    return source.to_s.bytesize if row == point.row.to_i && column == point.column.to_i

    raise RangeError, "source point (#{point.row}, #{point.column}) is outside source"
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
      'tree-sitter'
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

  LanguagePackProcessAnalysis = Struct.new(:language, :structure, :imports, :diagnostics, :backend_ref,
                                           keyword_init: true) do
    def kind
      'tree-sitter-process'
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

  KaitaiByteSpan = Struct.new(:start_byte, :end_byte, keyword_init: true) do
    def to_h
      {
        start_byte: start_byte,
        end_byte: end_byte
      }
    end
  end

  KaitaiTreeNode = Struct.new(:kind, :schema_path, :span, :fields, :children, keyword_init: true) do
    def to_h
      {
        kind: kind,
        schema_path: schema_path,
        span: span.to_h,
        fields: deep_dup(fields || {}),
        children: (children || []).map(&:to_h)
      }
    end

    private

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  KaitaiTreeAnalysis = Struct.new(:schema, :root, :backend_ref, :source_byte_length, :diagnostics,
                                  keyword_init: true) do
    def kind
      'kaitai-tree'
    end

    def to_h
      {
        kind: kind,
        schema: schema,
        **(source_byte_length.nil? ? {} : { source_byte_length: source_byte_length }),
        root: root.to_h,
        backend_ref: backend_ref.to_h,
        diagnostics: (diagnostics || []).map(&:to_h)
      }
    end
  end
end
