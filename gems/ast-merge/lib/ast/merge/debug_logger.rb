# frozen_string_literal: true

module Ast
  module Merge
    # Base debug logging utility for AST merge libraries.
    # Provides conditional debug output based on environment configuration.
    #
    # This module is designed to be extended by file-type-specific merge libraries
    # (e.g., Prism::Merge, Psych::Merge) which configure their own environment
    # variable and log prefix.
    #
    # == Minimal Integration
    #
    # Simply extend this module and configure your environment variable and log prefix:
    #
    # @example Creating a custom debug logger (minimal integration)
    #   module MyMerge
    #     module DebugLogger
    #       extend Ast::Merge::DebugLogger
    #
    #       self.env_var_name = "MY_MERGE_DEBUG"
    #       self.log_prefix = "[MyMerge]"
    #     end
    #   end
    #
    # == Overriding Methods
    #
    # When you +extend+ a module, its instance methods become singleton methods on
    # your module. To override inherited behavior, you must define *singleton methods*
    # (+def self.method_name+), not instance methods (+def method_name+).
    #
    # @example Overriding a method (correct - singleton method)
    #   module MyMerge
    #     module DebugLogger
    #       extend Ast::Merge::DebugLogger
    #
    #       self.env_var_name = "MY_MERGE_DEBUG"
    #       self.log_prefix = "[MyMerge]"
    #
    #       # Override extract_node_info for custom node types
    #       def self.extract_node_info(node)
    #         case node
    #         when MyMerge::CustomNode
    #           {type: "CustomNode", lines: "#{node.start_line}..#{node.end_line}"}
    #         else
    #           # Delegate to base implementation
    #           Ast::Merge::DebugLogger.extract_node_info(node)
    #         end
    #       end
    #     end
    #   end
    #
    # @example Enable debug logging
    #   ENV['AST_MERGE_DEBUG'] = '1'
    #   Ast::Merge::DebugLogger.debug("Processing node", {type: "mapping", line: 5})
    #
    # == Testing with Shared Examples
    #
    # Use the provided shared examples to validate your integration:
    #
    #   require "ast/merge/rspec/shared_examples"
    #
    #   RSpec.describe MyMerge::DebugLogger do
    #     it_behaves_like "Ast::Merge::DebugLogger" do
    #       let(:described_logger) { MyMerge::DebugLogger }
    #       let(:env_var_name) { "MY_MERGE_DEBUG" }
    #       let(:log_prefix) { "[MyMerge]" }
    #     end
    #   end
    #
    # @note Shared examples require +silent_stream+ and +rspec-stubbed_env+ gems.
    module DebugLogger
      # Benchmark is optional - gracefully degrade if not available.
      # As of Ruby 4.0, benchmark is a bundled gem (not default), so it may not be available.
      # We attempt to require it at load time and set a flag for later use.
      BENCHMARK_AVAILABLE = begin
        require 'benchmark'
        true
      rescue LoadError
        # benchmark gem not available (Ruby 4.0+ without explicit dependency, or unusual Ruby builds)
        false
      end

      class << self
        # @return [String] Environment variable name to check for debug mode # - Configuration attribute, set once at load time
        attr_accessor :env_var_name
        # @return [String] Prefix for log messages # - Configuration attribute, set once at load time
        attr_accessor :log_prefix

        # Hook called when a module extends Ast::Merge::DebugLogger.
        # Sets up attr_accessor for env_var_name and log_prefix on the extending module,
        # and copies the BENCHMARK_AVAILABLE constant.
        #
        # @param base [Module] The module that is extending this module
        def extended(base)
          # Create a module with the accessors and prepend it to the singleton class.
          # This avoids "method redefined" warnings when extending multiple times.
          accessors_module = Module.new do
            attr_accessor :env_var_name
            attr_accessor :log_prefix
          end
          base.singleton_class.prepend(accessors_module)

          # Set default values (inherit from Ast::Merge::DebugLogger)
          base.env_var_name = env_var_name
          base.log_prefix = log_prefix

          # Copy the BENCHMARK_AVAILABLE constant
          base.const_set(:BENCHMARK_AVAILABLE, BENCHMARK_AVAILABLE) unless base.const_defined?(:BENCHMARK_AVAILABLE)
        end
      end

      UNIVERSAL_DEBUG_ENV_VAR = 'KETTLE_DEV_DEBUG'

      # Default configuration
      self.env_var_name = 'AST_MERGE_DEBUG'
      self.log_prefix = '[Ast::Merge]'

      # Check if debug mode is enabled
      #
      # @return [Boolean]
      def enabled?
        truthy_env_value?(ENV[UNIVERSAL_DEBUG_ENV_VAR]) || truthy_env_value?(ENV[env_var_name])
      end

      # Get the environment variable name.
      # When called as a module method (via extend self), returns own config.
      # When called as instance method, checks class first, then falls back to base.
      #
      # @return [String]
      def env_var_name
        if is_a?(Module) && singleton_class.method_defined?(:env_var_name)
          # Called as module method on a module that extended us
          self.class.superclass == Module ? @env_var_name : self.class.env_var_name
        elsif self.class.respond_to?(:env_var_name)
          self.class.env_var_name
        else
          Ast::Merge::DebugLogger.env_var_name
        end
      end

      # Get the log prefix.
      # When called as a module method (via extend self), returns own config.
      # When called as instance method, checks class first, then falls back to base.
      #
      # @return [String]
      def log_prefix
        if is_a?(Module) && singleton_class.method_defined?(:log_prefix)
          # Called as module method on a module that extended us
          self.class.superclass == Module ? @log_prefix : self.class.log_prefix
        elsif self.class.respond_to?(:log_prefix)
          self.class.log_prefix
        else
          Ast::Merge::DebugLogger.log_prefix
        end
      end

      # Log a debug message with optional context
      #
      # @param message [String] The debug message
      # @param context [Hash] Optional context to include
      def debug(message, context = {})
        return unless enabled?

        output = "#{log_prefix} #{message}"
        output += " #{context.inspect}" unless context.empty?
        warn(output)
      end

      # Log an info message (always shown when debug is enabled)
      #
      # @param message [String] The info message
      def info(message)
        return unless enabled?

        warn("#{log_prefix} INFO] #{message}")
      end

      # Log a warning message (always shown)
      #
      # @param message [String] The warning message
      def warning(message)
        warn("#{log_prefix} WARNING] #{message}")
      end

      # Log a warning message only when debug mode is enabled.
      #
      # Use this for internal safety rails that indicate a logic bug when they
      # fire, but should remain silent in normal runs.
      #
      # @param message [String] The warning message
      # @param context [Hash] Optional context to include
      def debug_warning(message, context = {})
        return unless enabled?

        output = "#{log_prefix} WARNING] #{message}"
        output += " #{context.inspect}" unless context.empty?
        warn(output)
      end

      # Time a block and log the duration
      #
      # @param operation [String] Name of the operation
      # @yield The block to time
      # @return [Object] The result of the block
      def time(operation)
        return yield unless enabled?

        unless BENCHMARK_AVAILABLE
          warning("Benchmark gem not available - timing disabled for: #{operation}")
          return yield
        end

        debug("Starting: #{operation}")
        result = nil
        timing = Benchmark.measure { result = yield }
        debug("Completed: #{operation}", {
                real_ms: (timing.real * 1000).round(2),
                user_ms: (timing.utime * 1000).round(2),
                system_ms: (timing.stime * 1000).round(2)
              })
        result
      end

      # Log node information - override in submodules for file-type-specific logging
      #
      # @param node [Object] Node to log information about
      # @param label [String] Label for the node
      def log_node(node, label: 'Node')
        return unless enabled?

        info = extract_node_info(node)
        debug(label, info)
      end

      # Extract information from a node for logging.
      # Override in submodules for file-type-specific node types.
      #
      # @param node [Object] Node to extract info from
      # @return [Hash] Node information
      def extract_node_info(node)
        type_name = safe_type_name(node)
        lines = extract_lines(node)

        info = { type: type_name }
        info[:lines] = lines if lines
        info
      end

      # Safely extract the type name from a node
      #
      # @param node [Object] Node to get type from
      # @return [String] Type name
      def safe_type_name(node)
        klass = node.class
        if klass.respond_to?(:name) && klass.name
          klass.name.split('::').last
        else
          klass.to_s
        end
      rescue StandardError
        node.class.to_s
      end

      # Extract line information from a node if available
      #
      # @param node [Object] Node to extract lines from
      # @return [String, nil] Line range string or nil
      def extract_lines(node)
        if node.respond_to?(:location)
          loc = node.location
          if loc.respond_to?(:start_line) && loc.respond_to?(:end_line)
            "#{loc.start_line}..#{loc.end_line}"
          elsif loc.respond_to?(:start_line)
            loc.start_line.to_s
          end
        elsif node.respond_to?(:start_line) && node.respond_to?(:end_line)
          "#{node.start_line}..#{node.end_line}"
        end
      end

      def truthy_env_value?(value)
        %w[1 true].include?(value.to_s.downcase)
      end

      # Make all methods available as both instance and module methods
      extend self
    end
  end
end
