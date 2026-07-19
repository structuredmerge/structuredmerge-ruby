# frozen_string_literal: true

module Markdown
  module Merge
    # Shared boilerplate for backend-specific Markdown wrapper backends.
    module BackendSupport
      DEFAULT_CAPABILITIES = {
        query: false,
        bytes_field: false,
        incremental: false,
        pure_ruby: false,
        markdown_only: true,
        error_tolerant: true
      }.freeze

      module_function

      def install!(backend_module:, backend_name:, gem_name:, require_path:, capabilities: {})
        install_availability_methods!(
          backend_module: backend_module,
          backend_name: backend_name,
          gem_name: gem_name,
          capabilities: capabilities
        )
        install_tree_wrapper!(backend_module)
        register_backend!(
          backend_module: backend_module,
          backend_name: backend_name,
          gem_name: gem_name,
          require_path: require_path
        )
      end

      def configure_markdown_only_language_class!(klass, backend_label:, factory_method: :markdown,
                                                  unsupported_language_message: nil)
        klass.singleton_class.class_eval do
          define_method(:from_library) do |_path = nil, symbol: nil, name: nil|
            lang_name = name || symbol&.to_s&.sub(/^tree_sitter_/, '')&.to_sym || :markdown

            unless lang_name == :markdown
              message = if unsupported_language_message.respond_to?(:call)
                          unsupported_language_message.call(lang_name)
                        else
                          unsupported_language_message || "#{backend_label} backend only supports Markdown, not #{lang_name}."
                        end
              raise TreeHaver::NotAvailable, message
            end

            public_send(factory_method)
          end
        end
      end

      def configure_node_link_and_navigation!(klass, next_sibling_selector:, prev_sibling_selector:,
                                              parent_selector: :parent)
        klass.class_eval do
          define_method(:url) do
            Markdown::Merge::BackendSupport.send(:safe_inner_node_call, inner_node, :url)
          end

          define_method(:title) do
            Markdown::Merge::BackendSupport.send(:safe_inner_node_call, inner_node, :title)
          end

          define_method(:next_sibling) do
            sibling = Markdown::Merge::BackendSupport.send(:safe_inner_node_call, inner_node, next_sibling_selector)
            sibling ? self.class.new(sibling, source: source, lines: lines) : nil
          end

          define_method(:prev_sibling) do
            sibling = Markdown::Merge::BackendSupport.send(:safe_inner_node_call, inner_node, prev_sibling_selector)
            sibling ? self.class.new(sibling, source: source, lines: lines) : nil
          end

          define_method(:parent) do
            parent_node = Markdown::Merge::BackendSupport.send(:safe_inner_node_call, inner_node, parent_selector)
            parent_node ? self.class.new(parent_node, source: source, lines: lines) : nil
          end
        end
      end

      def configure_node_heading_and_code_block_helpers!(klass, heading_matcher:, code_block_matcher:,
                                                         heading_level_extractor: nil,
                                                         code_block_info_extractor: nil)
        klass.class_eval do
          define_method(:header_level) do
            return unless Markdown::Merge::BackendSupport.send(:node_helper_match?, self, heading_matcher)

            if heading_level_extractor.respond_to?(:call)
              heading_level_extractor.call(inner_node)
            else
              Markdown::Merge::BackendSupport.send(:safe_inner_node_call, inner_node, :header_level)
            end
          end

          define_method(:fence_info) do
            return unless Markdown::Merge::BackendSupport.send(:node_helper_match?, self, code_block_matcher)

            if code_block_info_extractor.respond_to?(:call)
              code_block_info_extractor.call(inner_node)
            else
              Markdown::Merge::BackendSupport.send(:safe_inner_node_call, inner_node, :fence_info)
            end
          end
        end
      end

      def install_availability_methods!(backend_module:, backend_name:, gem_name:, capabilities: {})
        backend_module.instance_variable_set(:@load_attempted, false)
        backend_module.instance_variable_set(:@loaded, false)

        merged_capabilities = DEFAULT_CAPABILITIES.merge(backend: backend_name).merge(capabilities)

        backend_module.singleton_class.class_eval do
          define_method(:available?) do
            return @loaded if @load_attempted

            @load_attempted = true
            begin
              require gem_name
              @loaded = true
            rescue LoadError, StandardError
              @loaded = false
            end
            @loaded
          end

          define_method(:reset!) do
            @load_attempted = false
            @loaded = false
          end

          define_method(:capabilities) do
            return {} unless available?

            merged_capabilities.dup
          end
        end
      end
      private_class_method :install_availability_methods!

      def install_tree_wrapper!(backend_module)
        return if backend_module.const_defined?(:Tree, false)

        tree_class = Class.new(::TreeHaver::Base::Tree) do
          define_method(:initialize) do |document, source|
            super(document, source: source)
          end

          define_method(:root_node) do
            backend_module.const_get(:Node).new(inner_tree, source: source, lines: lines)
          end
        end

        backend_module.const_set(:Tree, tree_class)
        backend_module.const_set(:Point, ::TreeHaver::Base::Point) unless backend_module.const_defined?(:Point, false)
      end
      private_class_method :install_tree_wrapper!

      def register_backend!(backend_module:, backend_name:, gem_name:, require_path:)
        ::TreeHaver::BackendRegistry.register(
          ::TreeHaver::BackendReference.new(id: backend_name.to_s, family: 'native')
        )

        ::TreeHaver.register_language(
          :markdown,
          backend_type: backend_name,
          backend_module: backend_module,
          gem_name: gem_name
        )

        if ::TreeHaver::BackendRegistry.respond_to?(:register_tag)
          ::TreeHaver::BackendRegistry.register_tag(
            :"#{backend_name}_backend",
            category: :backend,
            backend_name: backend_name,
            require_path: require_path
          ) { backend_module.available? }
        else
          ::TreeHaver::BackendRegistry.register_availability_checker(backend_name) do
            backend_module.available?
          end
        end
      end
      private_class_method :register_backend!

      def safe_inner_node_call(node, method_name)
        node.public_send(method_name)
      rescue StandardError
        nil
      end
      private_class_method :safe_inner_node_call

      def node_helper_match?(node, matcher)
        matcher.respond_to?(:call) ? matcher.call(node) : false
      end
      private_class_method :node_helper_match?
    end
  end
end
