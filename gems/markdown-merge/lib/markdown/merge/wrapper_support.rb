# frozen_string_literal: true

module Markdown
  module Merge
    # Shared bootstrap helpers for backend-specific Markdown wrapper gems.
    module WrapperSupport
      SHARED_REEXPORTS = {
        FileAligner: Markdown::Merge::FileAligner,
        ConflictResolver: Markdown::Merge::ConflictResolver,
        MergeResult: Markdown::Merge::MergeResult,
        TableMatchAlgorithm: Markdown::Merge::TableMatchAlgorithm,
        TableMatchRefiner: Markdown::Merge::TableMatchRefiner,
        CodeBlockMerger: Markdown::Merge::CodeBlockMerger,
        NodeTypeNormalizer: Markdown::Merge::NodeTypeNormalizer
      }.freeze

      WRAPPER_AUTOLOADS = {
        DebugLogger: 'debug_logger',
        CommentTracker: 'comment_tracker',
        FreezeNode: 'freeze_node',
        FileAnalysis: 'file_analysis',
        PartialTemplateMerger: 'partial_template_merger',
        SmartMerger: 'smart_merger',
        Backend: 'backend'
      }.freeze

      module_function

      def install!(
        wrapper_module:,
        require_prefix:,
        default_freeze_token:,
        default_inner_merge_code_blocks:,
        registry_tag:,
        merger_class:,
        test_source: "# Test\n\nParagraph",
        category: :markdown
      )
        define_error_classes!(wrapper_module)
        define_constant_unless_present(wrapper_module, :DEFAULT_FREEZE_TOKEN, default_freeze_token)
        define_constant_unless_present(wrapper_module, :DEFAULT_INNER_MERGE_CODE_BLOCKS,
                                       default_inner_merge_code_blocks)

        SHARED_REEXPORTS.each do |name, value|
          define_constant_unless_present(wrapper_module, name, value)
        end

        WRAPPER_AUTOLOADS.each do |name, suffix|
          next if wrapper_module.const_defined?(name, false) || wrapper_module.autoload?(name)

          wrapper_module.send(:autoload, name, "#{require_prefix}/#{suffix}")
        end

        install_backend_loader!(wrapper_module)
        register_merge_gem!(
          registry_tag: registry_tag,
          require_path: require_prefix,
          merger_class: merger_class,
          test_source: test_source,
          category: category
        )
      end

      def configure_debug_logger!(debug_logger_module:, env_var_name:, log_prefix:)
        debug_logger_module.extend(Ast::Merge::DebugLogger)
        debug_logger_module.env_var_name = env_var_name
        debug_logger_module.log_prefix = log_prefix
      end

      def configure_file_analysis_subclass!(klass, default_backend:, default_parser_options: nil)
        install_singleton_value_method!(klass, :default_backend, default_backend)
        return unless default_parser_options

        install_singleton_value_method!(klass, :default_parser_options,
                                        default_parser_options)
      end

      def configure_smart_merger_subclass!(
        klass,
        default_backend:,
        default_freeze_token: nil,
        default_inner_merge_code_blocks: nil,
        default_parser_options: nil,
        file_analysis_class: nil,
        template_parse_error_class: nil,
        destination_parse_error_class: nil
      )
        install_singleton_value_method!(klass, :default_backend, default_backend)
        install_singleton_value_method!(klass, :default_freeze_token, default_freeze_token) if default_freeze_token
        unless default_inner_merge_code_blocks.nil?
          install_singleton_value_method!(klass, :default_inner_merge_code_blocks,
                                          default_inner_merge_code_blocks)
        end
        if default_parser_options
          install_singleton_value_method!(klass, :default_parser_options,
                                          default_parser_options)
        end
        install_singleton_value_method!(klass, :file_analysis_class, file_analysis_class) if file_analysis_class
        if template_parse_error_class
          install_singleton_value_method!(klass, :template_parse_error_class,
                                          template_parse_error_class)
        end
        return unless destination_parse_error_class

        install_singleton_value_method!(klass, :destination_parse_error_class,
                                        destination_parse_error_class)
      end

      def configure_partial_template_merger_subclass!(klass, default_backend:, file_analysis_class:,
                                                      smart_merger_class:)
        install_singleton_value_method!(klass, :default_backend, default_backend)
        install_singleton_value_method!(klass, :file_analysis_class, file_analysis_class)
        install_singleton_value_method!(klass, :smart_merger_class, smart_merger_class)
      end

      def install_backend_loader!(wrapper_module)
        return if wrapper_module.respond_to?(:ensure_backend_loaded!)

        wrapper_module.singleton_class.class_eval do
          define_method(:ensure_backend_loaded!) do
            const_get(:Backend)
          end
        end
      end
      private_class_method :install_backend_loader!

      def define_error_classes!(wrapper_module)
        define_constant_unless_present(wrapper_module, :Error, Class.new(Markdown::Merge::Error))
        define_constant_unless_present(wrapper_module, :ParseError, Class.new(Markdown::Merge::ParseError))
        define_constant_unless_present(
          wrapper_module,
          :TemplateParseError,
          Class.new(wrapper_module.const_get(:ParseError))
        )
        define_constant_unless_present(
          wrapper_module,
          :DestinationParseError,
          Class.new(wrapper_module.const_get(:ParseError))
        )
      end
      private_class_method :define_error_classes!

      def install_singleton_value_method!(klass, method_name, value)
        klass.singleton_class.class_eval do
          define_method(method_name) do
            WrapperSupport.send(:resolve_config_value, value, context: self)
          end
        end
      end
      private_class_method :install_singleton_value_method!

      def resolve_config_value(value, context:)
        return context.instance_exec(&value) if value.respond_to?(:call)

        duplicate_config_value(value)
      end
      private_class_method :resolve_config_value

      def duplicate_config_value(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), result|
            result[key] = duplicate_config_value(nested_value)
          end
        when Array
          value.map { |nested_value| duplicate_config_value(nested_value) }
        else
          value
        end
      end
      private_class_method :duplicate_config_value

      def register_merge_gem!(registry_tag:, require_path:, merger_class:, test_source:, category:)
        return unless defined?(Ast::Merge::RSpec::MergeGemRegistry)

        Ast::Merge::RSpec::MergeGemRegistry.register(
          registry_tag,
          require_path: require_path,
          merger_class: merger_class,
          test_source: test_source,
          category: category
        )
      end
      private_class_method :register_merge_gem!

      def define_constant_unless_present(wrapper_module, name, value)
        return if wrapper_module.const_defined?(name, false)

        wrapper_module.const_set(name, value)
      end
      private_class_method :define_constant_unless_present
    end
  end
end
