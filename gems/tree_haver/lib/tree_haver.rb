# frozen_string_literal: true

require 'version_gem'

require_relative 'tree_haver/version'

module TreeHaver
  PACKAGE_NAME = 'tree_haver'

  class Error < StandardError; end
  class NotAvailable < Error; end
  class BackendConflict < Error; end
end

require_relative 'tree_haver/backend_registry'
require_relative 'tree_haver/backend_context'
require_relative 'tree_haver/contracts'
require_relative 'tree_haver/backend_api'
require_relative 'tree_haver/base/point'
require_relative 'tree_haver/base/language'
require_relative 'tree_haver/base/parser'
require_relative 'tree_haver/base/tree'
require_relative 'tree_haver/base/node'
require_relative 'tree_haver/base/comment'
require_relative 'tree_haver/point'
require_relative 'tree_haver/node'
require_relative 'tree_haver/tree'
require_relative 'tree_haver/language_registry'
require_relative 'tree_haver/path_validator'
require_relative 'tree_haver/library_path_utils'
require_relative 'tree_haver/backends/mri'
require_relative 'tree_haver/backends/ffi'
require_relative 'tree_haver/backends/rust'
require_relative 'tree_haver/backends/java'
require_relative 'tree_haver/backends/tslp'
require_relative 'tree_haver/grammar_finder'
require_relative 'tree_haver/citrus_grammar_finder'
require_relative 'tree_haver/parslet_grammar_finder'
require_relative 'tree_haver/peg_backends'
require_relative 'tree_haver/kaitai_backend'
require_relative 'tree_haver/language_pack'
require_relative 'tree_haver/backends/psych'
require_relative 'tree_haver/backends/prism'
require_relative 'tree_haver/backends/citrus'
require_relative 'tree_haver/backends/parslet'
require_relative 'tree_haver/language'
require_relative 'tree_haver/parser'

module TreeHaver
  NATIVE_BACKENDS = %i[mri rust ffi java].freeze
  RUBY_BACKENDS = %i[citrus parslet prism psych commonmarker markly rbs].freeze
  VALID_NATIVE_BACKENDS = NATIVE_BACKENDS.map(&:to_s).freeze
  VALID_RUBY_BACKENDS = RUBY_BACKENDS.map(&:to_s).freeze
  VALID_BACKENDS = (VALID_NATIVE_BACKENDS + VALID_RUBY_BACKENDS + %w[auto none tslp kreuzberg-language-pack]).freeze
  DEFAULT_BACKEND_ID = 'tslp'
  NATIVE_BACKEND_REFERENCES = NATIVE_BACKENDS.to_h do |backend_name|
    [
      backend_name,
      BackendReference.new(id: backend_name.to_s, family: 'tree-sitter').freeze
    ]
  end.freeze

  NATIVE_BACKEND_REFERENCES.each_value { |backend_ref| BackendRegistry.register(backend_ref) }

  module_function

  def register_standard_dependency_tags!
    BackendRegistry.register_tag(:mri_backend, category: :backend, backend_name: :mri) do
      Backends::MRI.available?
    end
    BackendRegistry.register_tag(:ffi_backend, category: :backend, backend_name: :ffi) do
      Backends::FFI.available?
    end
    BackendRegistry.register_tag(:rust_backend, category: :backend, backend_name: :rust) do
      Backends::Rust.available?
    end
    BackendRegistry.register_tag(:java_backend, category: :backend, backend_name: :java) do
      Backends::Java.available?
    end
  end

  def default_backend_id
    DEFAULT_BACKEND_ID
  end

  def backend
    @backend ||= parse_single_backend_env
  end

  def backend=(name)
    @backend = name&.to_sym
  end

  def reset_backend!(to: :auto)
    @backend = to&.to_sym
    @allowed_native_backends = nil
    @allowed_ruby_backends = nil
    nil
  end

  def backend_protect=(value)
    backend_protect_mutex.synchronize { @backend_protect = value }
  end

  def backend_protect?
    return @backend_protect if defined?(@backend_protect)

    true
  end

  def backend_protect
    backend_protect?
  end

  def backends_used
    @backends_used ||= Set.new
  end

  def record_backend_usage(backend_name)
    backends_used << backend_name.to_sym
    nil
  end

  def conflicting_backends_for(backend_name)
    blockers = {
      mri: [],
      rust: [],
      ffi: [:mri],
      java: [],
      citrus: [],
      parslet: [],
      prism: [],
      psych: []
    }.fetch(backend_name.to_sym, [])
    blockers & backends_used.to_a
  end

  def check_backend_conflict!(backend_name)
    return unless backend_protect?

    conflicts = conflicting_backends_for(backend_name)
    return if conflicts.empty?

    raise BackendConflict,
          "Cannot use #{backend_name} backend: it is blocked by previously used backend(s): #{conflicts.join(', ')}."
  end

  def allowed_native_backends
    @allowed_native_backends ||= parse_backend_list_env('TREE_HAVER_NATIVE_BACKEND', VALID_NATIVE_BACKENDS)
  end

  def allowed_ruby_backends
    @allowed_ruby_backends ||= parse_backend_list_env('TREE_HAVER_RUBY_BACKEND', VALID_RUBY_BACKENDS)
  end

  def backend_allowed?(backend_name)
    backend_sym = backend_name.to_sym
    if VALID_NATIVE_BACKENDS.include?(backend_sym.to_s)
      allowed = allowed_native_backends
      return true if allowed == [:auto]
      return false if allowed == [:none]

      return allowed.include?(backend_sym)
    end

    if VALID_RUBY_BACKENDS.include?(backend_sym.to_s)
      allowed = allowed_ruby_backends
      return true if allowed == [:auto]
      return false if allowed == [:none]

      return allowed.include?(backend_sym)
    end

    true
  end

  def effective_backend
    contextual = current_backend_id
    return contextual.to_sym if contextual && !contextual.empty?

    backend || :auto
  end

  def resolve_effective_backend(explicit_backend = nil)
    return explicit_backend.to_sym if explicit_backend

    effective_backend
  end

  def resolve_backend_module(explicit_backend = nil)
    requested = resolve_effective_backend(explicit_backend)
    return backend_module if requested == :auto
    return if %i[tslp kreuzberg-language-pack].include?(requested)
    return unless backend_allowed?(requested)

    mod = backend_module_for(requested)
    return unless mod

    check_backend_conflict!(requested)
    return if mod.respond_to?(:available?) && !mod.available?

    record_backend_usage(requested)
    mod
  end

  def resolve_native_backend_module(explicit_backend = nil)
    requested = resolve_effective_backend(explicit_backend)
    return resolve_backend_module(requested) if NATIVE_BACKENDS.include?(requested)
    return if explicit_backend

    native_backend_priority.each do |backend_name|
      mod = resolve_backend_module(backend_name)
      return mod if mod
    rescue BackendConflict
      next
    end

    nil
  end

  def backend_module
    requested = effective_backend
    return backend_module_for(requested) if requested != :auto && backend_module_available?(requested)

    backend_priority.each do |backend_name|
      next unless backend_allowed?(backend_name)

      mod = backend_module_for(backend_name)
      next unless mod
      next if mod.respond_to?(:available?) && !mod.available?

      return mod
    rescue BackendConflict
      next
    end

    nil
  end

  def capabilities
    backend_module&.capabilities || {}
  end

  def register_backend(name, mod)
    backend_module_registry[name.to_sym] = mod
    nil
  end

  def registered_backend(name)
    backend_module_registry[name.to_sym]
  end

  def registered_language(name)
    LanguageRegistry.registered(name)
  end

  def register_language(name, path: nil, symbol: nil, grammar_module: nil, grammar_class: nil, backend_module: nil,
                        backend_type: nil, gem_name: nil)
    LanguageRegistry.register(name, :tree_sitter, path: path, symbol: symbol) if path

    LanguageRegistry.register(name, :citrus, grammar_module: grammar_module, gem_name: gem_name) if grammar_module

    LanguageRegistry.register(name, :parslet, grammar_class: grammar_class, gem_name: gem_name) if grammar_class

    if backend_module
      LanguageRegistry.register(name, backend_type || backend_module.name.split('::').last.downcase.to_sym,
                                backend_module: backend_module, gem_name: gem_name)
      register_backend(backend_type || backend_module.name.split('::').last.downcase.to_sym, backend_module)
    end

    if path.nil? && grammar_module.nil? && grammar_class.nil? && backend_module.nil?
      raise ArgumentError, 'Provide path:, grammar_module:, grammar_class:, or backend_module:'
    end

    nil
  end

  def registered_languages(name)
    LanguageRegistry.registered(name) || {}
  end

  def parser_for(language_name, library_path: nil, symbol: nil, citrus_config: nil, parslet_config: nil)
    name = language_name.to_sym

    return parser_for_tree_sitter(name, library_path, symbol) if library_path

    registrations = LanguageRegistry.registered(name) || {}
    if (backend_type = requested_backend_type(registrations))
      return parser_for_registered_backend(name, backend_type, registrations)
    end

    if (config = registrations[:psych])
      return parser_for_backend_module(config.fetch(:backend_module), name)
    end

    if (config = registrations[:prism])
      return parser_for_backend_module(config.fetch(:backend_module), name)
    end

    if (config = registrations[:citrus]) || citrus_config
      module_config = config || citrus_config
      return parser_for_citrus(module_config.fetch(:grammar_module))
    end

    if (config = registrations[:parslet]) || parslet_config
      class_config = config || parslet_config
      return parser_for_parslet(class_config.fetch(:grammar_class))
    end

    if (config = registrations[:rbs])
      return parser_for_backend_module(config.fetch(:backend_module), name)
    end

    if (config = registrations[:tree_sitter])
      return parser_for_tree_sitter(name, config[:path], config[:symbol])
    end

    raise NotAvailable, "No parser registered for #{name}"
  end

  def ruby_reference_parser_backend_contract_report
    {
      report_id: 'ruby-tree-haver-parser-backend-contract',
      reference_runtime: 'ruby',
      contract_layer: 'tree_haver',
      proves: [
        {
          capability: 'stable_node_spans',
          fixture_roles: %w[portable_byte_location_contract node_span_source_fragment],
          ruby_surface: 'TreeHaver::ByteRange and TreeHaver::SourceSpan',
          portability: 'portable_contract'
        },
        {
          capability: 'source_fragments',
          fixture_roles: %w[source_fragment_extraction node_span_source_fragment],
          ruby_surface: 'TreeHaver.extract_source_fragment',
          portability: 'portable_contract'
        },
        {
          capability: 'comments_when_backend_supports_them',
          fixture_roles: %w[comment_capability],
          ruby_surface: 'TreeHaver::Base::Comment',
          portability: 'backend_restricted_contract'
        },
        {
          capability: 'parser_diagnostics',
          fixture_roles: %w[parse_error_tolerance parser_diagnostics],
          ruby_surface: 'TreeHaver::ParseErrorTolerance and TreeHaver::ParserDiagnostics',
          portability: 'portable_contract'
        },
        {
          capability: 'backend_capability_reports',
          fixture_roles: %w[backend_capability_report backend_availability provider_diagnostics],
          ruby_surface: 'TreeHaver::BackendCapability',
          portability: 'portable_contract'
        },
        {
          capability: 'backend_selection_context',
          fixture_roles: %w[backend_selection_context backend_registry],
          ruby_surface: 'TreeHaver.with_backend and TreeHaver.current_backend_id',
          portability: 'portable_contract_runtime_local_mechanism'
        }
      ],
      release_status: 'ruby_reference_ready',
      diagnostics: [
        {
          severity: 'info',
          category: 'ruby_reference_contract',
          message: 'Ruby tree_haver proves the parser/backend substrate needed by source-region extraction.'
        }
      ]
    }
  end

  def requested_backend_type(registrations)
    backend_id = current_backend_id || ENV['TREE_HAVER_BACKEND']
    return if backend_id.to_s.empty?

    backend_ref = BackendRegistry.fetch(backend_id.to_s)
    type = if registrations.key?(backend_id.to_s.to_sym)
             backend_id.to_s.to_sym
           elsif backend_ref&.family == 'tree-sitter'
             :tree_sitter
           else
             backend_id.to_s.to_sym
           end
    return type if registrations.key?(type)

    raise NotAvailable, "No parser registered for backend #{backend_id}"
  end
  private_class_method :requested_backend_type

  def parser_for_registered_backend(name, backend_type, registrations)
    config = registrations.fetch(backend_type)
    case backend_type
    when :psych, :prism, :commonmarker, :markly, :rbs
      parser_for_backend_module(config.fetch(:backend_module), name)
    when :citrus
      parser_for_citrus(config.fetch(:grammar_module))
    when :parslet
      parser_for_parslet(config.fetch(:grammar_class))
    when :tree_sitter
      parser_for_tree_sitter(name, config[:path], config[:symbol])
    else
      raise NotAvailable, "No parser registered for backend #{backend_type}" unless config[:backend_module]

      parser_for_backend_module(config.fetch(:backend_module), name)

    end
  end
  private_class_method :parser_for_registered_backend

  def parser_for_backend_module(backend_module, name)
    parser = backend_module::Parser.new
    language_factory = backend_module::Language
    parser.language = if language_factory.respond_to?(name)
                        language_factory.public_send(name)
                      elsif language_factory.respond_to?(:from_library)
                        language_factory.from_library(nil, name: name)
                      else
                        language_factory.new(name)
                      end
    parser
  end
  private_class_method :parser_for_backend_module

  def parser_for_citrus(grammar_module)
    parser = Backends::Citrus::Parser.new
    parser.language = Backends::Citrus::Language.new(grammar_module)
    parser
  end
  private_class_method :parser_for_citrus

  def parser_for_parslet(grammar_class)
    parser = Backends::Parslet::Parser.new
    parser.language = Backends::Parslet::Language.new(grammar_class)
    parser
  end
  private_class_method :parser_for_parslet

  def parser_for_tree_sitter(name, library_path, symbol)
    symbol ||= "tree_sitter_#{name}"
    language = Language.from_library(library_path, symbol: symbol, name: name)
    parser = Parser.new
    parser.language = language
    parser
  end
  private_class_method :parser_for_tree_sitter

  def parse_single_backend_env
    value = ENV['TREE_HAVER_BACKEND'].to_s.strip
    return :auto if value.empty?

    VALID_BACKENDS.include?(value) ? value.to_sym : :auto
  end
  private_class_method :parse_single_backend_env

  def parse_backend_list_env(env_name, valid_backends)
    normalized = ENV[env_name].to_s.strip.downcase
    return [:auto] if normalized.empty? || normalized == 'auto'
    return [:none] if normalized == 'none'

    parsed = normalized.split(',').filter_map do |name|
      candidate = name.strip
      valid_backends.include?(candidate) ? candidate.to_sym : nil
    end.uniq
    parsed.empty? ? [:auto] : parsed
  end
  private_class_method :parse_backend_list_env

  def backend_module_for(backend_name)
    case backend_name.to_sym
    when :mri
      Backends::MRI
    when :rust
      Backends::Rust
    when :ffi
      Backends::FFI
    when :java
      Backends::Java
    when :tslp, :"kreuzberg-language-pack"
      Backends::Tslp
    when :citrus
      Backends::Citrus
    when :parslet
      Backends::Parslet
    when :prism
      Backends::Prism
    when :psych
      Backends::Psych
    else
      registered_backend(backend_name)
    end
  end
  private_class_method :backend_module_for

  def backend_module_available?(backend_name)
    mod = backend_module_for(backend_name)
    return false unless mod
    return false unless backend_allowed?(backend_name)
    return false if mod.respond_to?(:available?) && !mod.available?

    true
  end
  private_class_method :backend_module_available?

  def backend_priority
    native_backend_priority + %i[prism psych citrus parslet]
  end
  private_class_method :backend_priority

  def native_backend_priority
    if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
      %i[java ffi]
    else
      %i[mri rust ffi]
    end
  end
  private_class_method :native_backend_priority

  def backend_module_registry
    @backend_module_registry ||= {}
  end
  private_class_method :backend_module_registry

  def backend_protect_mutex
    @backend_protect_mutex ||= Mutex.new
  end
  private_class_method :backend_protect_mutex
end

TreeHaver.register_standard_dependency_tags!

TreeHaver::Version.class_eval do
  extend VersionGem::Basic
end
