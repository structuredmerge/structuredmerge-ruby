# frozen_string_literal: true

module TreeHaver
  # Backend API contract definitions and validation
  #
  # This module defines the expected API surface for TreeHaver backends.
  # Each backend must provide Parser, Language, Tree, and Node classes/objects
  # that conform to these interfaces.
  #
  # == Architecture
  #
  # TreeHaver backends fall into two categories:
  #
  # 1. **Raw backends** (MRI, FFI, Rust) - Return raw tree-sitter objects
  #    (e.g., ::TreeSitter::Node). TreeHaver::Node wraps these and provides
  #    a unified API via method delegation.
  #
  # 2. **Wrapper backends** (Java, Citrus, Prism, Psych, Commonmarker, Markly) -
  #    Return their own wrapper objects that must implement the expected API
  #    directly, since TreeHaver::Node will delegate to them.
  #
  # == Usage
  #
  #   # Validate a backend's API compliance
  #   TreeHaver::BackendAPI.validate!(backend_module)
  #
  #   # Check specific class compliance
  #   TreeHaver::BackendAPI.validate_node!(node_instance)
  #
  module BackendAPI
    # Descriptive levels for backend comment support.
    #
    # - :full - backend can expose comment nodes plus strong attachment hints
    # - :partial - backend can expose comments, but ownership/attachment is incomplete
    # - :nodes_only - backend can surface comment nodes/tokens only
    # - :none - backend does not expose comments through TreeHaver
    COMMENT_SUPPORT_LEVELS = %i[
      full
      partial
      nodes_only
      none
    ].freeze

    # Required methods for Language class/instances
    #
    # All backends MUST implement `from_library` for API consistency.
    # Language-specific backends (Psych, Prism, Commonmarker, Markly) should
    # implement `from_library` to accept (and ignore) path/symbol parameters,
    # returning their single supported language.
    #
    # This ensures `TreeHaver.parser_for(:yaml)` works regardless of backend -
    # tree-sitter backends load the YAML grammar, while Psych returns its
    # built-in YAML support.
    #
    # Convenience methods (yaml, ruby, markdown) are OPTIONAL and only make
    # sense on backends that only support one language family.
    LANGUAGE_CLASS_METHODS = %i[
      from_library
    ].freeze

    # Optional convenience methods for language-specific backends
    # These are NOT required - they're just shortcuts for single-language backends
    LANGUAGE_OPTIONAL_CLASS_METHODS = %i[
      yaml
      ruby
      markdown
    ].freeze

    LANGUAGE_INSTANCE_METHODS = %i[
      backend
    ].freeze

    # Required methods for Parser class/instances
    PARSER_CLASS_METHODS = %i[
      new
    ].freeze

    PARSER_INSTANCE_METHODS = %i[
      language=
      parse
    ].freeze

    # Optional Parser methods (for incremental parsing)
    PARSER_OPTIONAL_METHODS = %i[
      parse_string
    ].freeze

    # Required methods for Tree instances
    # Note: Tree is returned by Parser#parse, not instantiated directly
    TREE_INSTANCE_METHODS = %i[
      root_node
    ].freeze

    # Optional Tree methods (for incremental parsing)
    TREE_OPTIONAL_METHODS = %i[
      edit
    ].freeze

    # Required methods for Node instances returned by wrapper backends
    # These are the methods TreeHaver::Node delegates to inner_node
    #
    # Raw backends (MRI, FFI, Rust) return tree-sitter native nodes which
    # have their own API. TreeHaver::Node handles the translation.
    #
    # Wrapper backends (Java, Citrus, etc.) must implement these methods
    # on their Node class since TreeHaver::Node delegates to them.
    NODE_INSTANCE_METHODS = %i[
      type
      child_count
      child
      start_byte
      end_byte
    ].freeze

    # Optional Node methods - should return nil if not supported
    NODE_OPTIONAL_METHODS = %i[
      parent
      next_sibling
      prev_sibling
      named?
      has_error?
      missing?
      text
      child_by_field_name
      start_point
      end_point
    ].freeze

    # Methods that have common aliases across backends
    NODE_ALIASES = {
      type: %i[kind],
      named?: %i[is_named? is_named],
      has_error?: %i[has_error],
      missing?: %i[is_missing? is_missing],
      next_sibling: %i[next_named_sibling],
      prev_sibling: %i[previous_sibling previous_named_sibling prev_named_sibling]
    }.freeze

    class << self
      # Validate a backend module for API compliance
      #
      # @param backend_module [Module] The backend module (e.g., TreeHaver::Backends::Java)
      # @param strict [Boolean] If true, raise on missing optional methods
      # @return [Hash] Validation results with :valid, :errors, :warnings keys
      def validate(backend_module, strict: false)
        results = {
          valid: true,
          errors: [],
          warnings: [],
          capabilities: {}
        }

        # Check module-level methods
        validate_module_methods(backend_module, results)

        # Check Language class
        if backend_module.const_defined?(:Language)
          validate_language(backend_module::Language, results)
        else
          results[:errors] << 'Missing Language class'
          results[:valid] = false
        end

        # Check Parser class
        if backend_module.const_defined?(:Parser)
          validate_parser(backend_module::Parser, results)
        else
          results[:errors] << 'Missing Parser class'
          results[:valid] = false
        end

        # Check Tree class if present (some backends return raw trees)
        if backend_module.const_defined?(:Tree)
          validate_tree(backend_module::Tree, results)
        else
          results[:warnings] << 'No Tree class (backend returns raw trees)'
        end

        # Check Node class if present (wrapper backends)
        if backend_module.const_defined?(:Node)
          validate_node_class(backend_module::Node, results, strict: strict)
        else
          results[:warnings] << 'No Node class (backend returns raw nodes, TreeHaver::Node will wrap)'
        end

        # Fail on warnings in strict mode
        results[:valid] = false if strict && results[:warnings].any?

        results
      end

      # Validate and raise on failure
      #
      # @param backend_module [Module] The backend module to validate
      # @param strict [Boolean] If true, treat warnings as errors
      # @raise [TreeHaver::Error] if validation fails
      # @return [Hash] Validation results if valid
      def validate!(backend_module, strict: false)
        results = validate(backend_module, strict: strict)
        unless results[:valid]
          raise TreeHaver::Error,
                "Backend #{backend_module.name} API validation failed:\n  " \
                  "Errors: #{results[:errors].join(', ')}\n  " \
                  "Warnings: #{results[:warnings].join(', ')}"
        end
        results
      end

      # Validate a Node instance for API compliance
      #
      # @param node [Object] A node instance to validate
      # @return [Hash] Validation results
      def validate_node_instance(node)
        results = {
          valid: true,
          errors: [],
          warnings: [],
          supported_methods: [],
          unsupported_methods: []
        }

        # Check required methods
        NODE_INSTANCE_METHODS.each do |method|
          if responds_to_with_aliases?(node, method)
            results[:supported_methods] << method
          else
            results[:errors] << "Missing required method: #{method}"
            results[:valid] = false
          end
        end

        # Check optional methods
        NODE_OPTIONAL_METHODS.each do |method|
          if responds_to_with_aliases?(node, method)
            results[:supported_methods] << method
          else
            results[:unsupported_methods] << method
            results[:warnings] << "Missing optional method: #{method}"
          end
        end

        results
      end

      private

      def validate_module_methods(mod, results)
        unless mod.singleton_class.method_defined?(:available?)
          results[:errors] << 'Missing module method: available?'
          results[:valid] = false
        end

        unless mod.singleton_class.method_defined?(:capabilities)
          results[:warnings] << 'Missing module method: capabilities'
          return
        end

        validate_capabilities_hash(mod.capabilities, results)
      end

      def validate_capabilities_hash(capabilities, results)
        return if capabilities.nil? || capabilities.empty?

        unless capabilities.is_a?(Hash)
          results[:errors] << 'Backend capabilities must return a Hash'
          results[:valid] = false
          return
        end

        comment_support = capabilities[:comment_support]
        if comment_support.nil?
          results[:warnings] << 'Capabilities missing :comment_support'
          return
        end

        unless COMMENT_SUPPORT_LEVELS.include?(comment_support)
          results[:errors] << "Invalid :comment_support #{comment_support.inspect}; expected one of #{COMMENT_SUPPORT_LEVELS.inspect}"
          results[:valid] = false
          return
        end

        results[:capabilities][:comment_support] = comment_support

        return unless capabilities.key?(:comment_attachment_hints)

        attachment_hints = capabilities[:comment_attachment_hints]
        unless [true, false].include?(attachment_hints)
          results[:errors] << "Invalid :comment_attachment_hints #{attachment_hints.inspect}; expected true or false"
          results[:valid] = false
          return
        end

        results[:capabilities][:comment_attachment_hints] = attachment_hints
      end

      def validate_language(klass, results)
        # from_library is REQUIRED for all backends
        # Language-specific backends should implement it to ignore path/symbol
        # and return their single language (for API consistency)
        unless klass.singleton_class.method_defined?(:from_library)
          results[:errors] << 'Language missing required class method: from_library'
          results[:valid] = false
        end

        # Check for optional convenience methods
        optional_methods = LANGUAGE_OPTIONAL_CLASS_METHODS.select { |m| klass.singleton_class.method_defined?(m) }
        results[:capabilities][:language_shortcuts] = optional_methods if optional_methods.any?

        results[:capabilities][:language] = {
          class_methods: LANGUAGE_CLASS_METHODS.select { |m| klass.singleton_class.method_defined?(m) } +
                         optional_methods
        }
      end

      def validate_parser(klass, results)
        PARSER_CLASS_METHODS.each do |method|
          unless klass.singleton_class.method_defined?(method)
            results[:errors] << "Parser missing class method: #{method}"
            results[:valid] = false
          end
        end

        # Check instance methods by inspecting the class
        PARSER_INSTANCE_METHODS.each do |method|
          unless klass.method_defined?(method) || klass.private_method_defined?(method)
            results[:errors] << "Parser missing instance method: #{method}"
            results[:valid] = false
          end
        end

        PARSER_OPTIONAL_METHODS.each do |method|
          results[:warnings] << "Parser missing optional method: #{method}" unless klass.method_defined?(method)
        end
      end

      def validate_tree(klass, results)
        TREE_INSTANCE_METHODS.each do |method|
          unless klass.method_defined?(method)
            results[:errors] << "Tree missing instance method: #{method}"
            results[:valid] = false
          end
        end

        TREE_OPTIONAL_METHODS.each do |method|
          results[:warnings] << "Tree missing optional method: #{method}" unless klass.method_defined?(method)
        end
      end

      def validate_node_class(klass, results, strict: false)
        NODE_INSTANCE_METHODS.each do |method|
          unless has_method_or_alias?(klass, method)
            results[:errors] << "Node missing required method: #{method}"
            results[:valid] = false
          end
        end

        NODE_OPTIONAL_METHODS.each do |method|
          next if has_method_or_alias?(klass, method)

          msg = "Node missing optional method: #{method}"
          if strict
            results[:errors] << msg
            results[:valid] = false
          else
            results[:warnings] << msg
          end
        end

        results[:capabilities][:node] = {
          required: NODE_INSTANCE_METHODS.select { |m| has_method_or_alias?(klass, m) },
          optional: NODE_OPTIONAL_METHODS.select { |m| has_method_or_alias?(klass, m) }
        }
      end

      def has_method_or_alias?(klass, method)
        return true if klass.method_defined?(method)

        # Check aliases
        aliases = NODE_ALIASES[method] || []
        aliases.any? { |alt| klass.method_defined?(alt) }
      end

      def responds_to_with_aliases?(obj, method)
        return true if obj.respond_to?(method)

        # Check aliases
        aliases = NODE_ALIASES[method] || []
        aliases.any? { |alt| obj.respond_to?(alt) }
      end
    end
  end
end
