# frozen_string_literal: true

module Ast
  module Merge
    # RSpec integration helpers for dependency-tagged merge-family test suites.
    module RSpec
      # Registry for merge gem dependency tag availability checkers
      #
      # This module allows merge gems (like markly-merge, prism-merge, json-merge)
      # to register their availability checker for RSpec dependency tags without
      # ast-merge needing to know about them directly.
      #
      # == Purpose
      #
      # When running RSpec tests with dependency tags (e.g., `:markly_merge`),
      # ast-merge needs to know if each merge gem is available. The MergeGemRegistry
      # provides a way for gems to register their availability checkers. Test
      # bootstraps can also register known gem metadata before gems are loaded so
      # RSpec filters are configured in time.
      #
      # == Registration
      #
      # Each merge gem registers itself when loaded using {register}:
      # - Tag name (e.g., :markly_merge)
      # - Require path (e.g., "markly/merge")
      # - Merger class name (e.g., "Markly::Merge::SmartMerger")
      # - Test source code to verify the merger works
      # - Optional category for grouping (e.g., :markdown, :data, :code)
      #
      # When a tag is registered, an availability method is automatically defined
      # on `Ast::Merge::RSpec::DependencyTags`.
      #
      # == Thread Safety
      #
      # All operations are thread-safe using a Mutex for synchronization.
      # Results are cached after first check for performance.
      #
      # @example Registering a merge gem (in your gem's lib file)
      #   # In markly-merge/lib/markly/merge.rb
      #   if defined?(Ast::Merge::RSpec::MergeGemRegistry)
      #     Ast::Merge::RSpec::MergeGemRegistry.register(
      #       :markly_merge,
      #       require_path: "markly/merge",
      #       merger_class: "Markly::Merge::SmartMerger",
      #       test_source: "# Test\n\nParagraph",
      #       category: :markdown
      #     )
      #   end
      #
      # @example Checking availability
      #   Ast::Merge::RSpec::MergeGemRegistry.available?(:markly_merge)  # => true/false
      #
      # @example Getting all registered gems
      #   Ast::Merge::RSpec::MergeGemRegistry.registered_gems # => [:markly_merge, :prism_merge, ...]
      #
      # @see Ast::Merge::RSpec::DependencyTags Uses MergeGemRegistry for dynamic gem detection
      # @api public
      module MergeGemRegistry
        @mutex = Mutex.new
        @registry = {}
        @known_gems = {}
        @availability_cache = {}

        # Valid categories for merge gems
        CATEGORIES = %i[markdown data code config other].freeze

        module_function

        # Register a merge gem for dependency tag support
        #
        # When a gem is registered, this also dynamically defines a `*_available?` method
        # on `Ast::Merge::RSpec::DependencyTags` if it doesn't already exist.
        #
        # @param tag_name [Symbol] the RSpec tag name (e.g., :markly_merge)
        # @param require_path [String] the require path for the gem (e.g., "markly/merge")
        # @param merger_class [String] the full class name of the SmartMerger
        # @param test_source [String] sample source code to test merging
        # @param category [Symbol] category for grouping (:markdown, :data, :code, :config, :other)
        # @param skip_instantiation [Boolean] if true, only check class exists (for gems requiring backends)
        # @return [void]
        #
        # @example Register a merge gem
        #   Ast::Merge::RSpec::MergeGemRegistry.register(
        #     :markly_merge,
        #     require_path: "markly/merge",
        #     merger_class: "Markly::Merge::SmartMerger",
        #     test_source: "# Test\n\nParagraph",
        #     category: :markdown
        #   )
        def register(tag_name, require_path:, merger_class:, test_source:, category: :other, skip_instantiation: false)
          raise ArgumentError, "Invalid category: #{category}" unless CATEGORIES.include?(category)

          tag_sym = tag_name.to_sym

          @mutex.synchronize do
            @registry[tag_sym] = {
              require_path: require_path,
              merger_class: merger_class,
              test_source: test_source,
              category: category,
              skip_instantiation: skip_instantiation
            }
            # Clear cache when re-registering
            @availability_cache.delete(tag_sym)
          end

          # Define availability method on DependencyTags
          define_availability_method(tag_sym)

          nil
        end

        # Register metadata for a merge gem that may not be loaded yet.
        #
        # This is intended for spec/bootstrap layers that need to declare the tag
        # universe before RSpec filters examples. Runtime provider gems should
        # still call {register} when loaded.
        def register_known_gem(tag_name, require_path:, merger_class:, test_source:, category: :other,
                               skip_instantiation: false)
          raise ArgumentError, "Invalid category: #{category}" unless CATEGORIES.include?(category)

          @mutex.synchronize do
            @known_gems[tag_name.to_sym] = {
              require_path: require_path,
              merger_class: merger_class,
              test_source: test_source,
              category: category,
              skip_instantiation: skip_instantiation
            }
          end

          define_availability_method(tag_name.to_sym)
          nil
        end

        # Check if a merge gem is available and functional
        #
        # This method will try to load the gem if it was registered directly or
        # predeclared by a spec bootstrap before the gem was explicitly loaded.
        #
        # @param tag_name [Symbol] the tag name to check
        # @return [Boolean] true if the merge gem is available and works
        def available?(tag_name)
          tag_sym = tag_name.to_sym

          # Check cache first
          @mutex.synchronize do
            return @availability_cache[tag_sym] if @availability_cache.key?(tag_sym)
          end

          # Get registration info (from loaded registry or bootstrap metadata)
          info = @mutex.synchronize { @registry[tag_sym] }
          info ||= @mutex.synchronize { @known_gems[tag_sym] }

          return false unless info

          # Check if gem works
          result = gem_works?(
            info[:require_path],
            info[:merger_class],
            info[:test_source],
            info[:skip_instantiation]
          )

          # Cache result
          @mutex.synchronize do
            @availability_cache[tag_sym] = result
          end

          result
        end

        # Check if a tag is registered
        #
        # @param tag_name [Symbol] the tag name
        # @return [Boolean] true if the tag is registered
        def registered?(tag_name)
          @mutex.synchronize do
            @registry.key?(tag_name.to_sym)
          end
        end

        # Register one or more known gems for RSpec dependency tag support
        #
        # This allows test suites to explicitly register only the merge gems they need
        # for their tests, avoiding the overhead of registering all known gems.
        #
        # @param gem_names [Array<Symbol>] list of predeclared gem names to register
        # @return [void]
        #
        # @example In spec/config/tree_haver.rb
        #   # Only register the markdown merge gems that markly-merge tests depend on
        #   Ast::Merge::RSpec::MergeGemRegistry.register_known_gems(:prism_merge)
        #
        # @example Register multiple gems
        #   Ast::Merge::RSpec::MergeGemRegistry.register_known_gems(
        #     :commonmarker_merge,
        #     :markly_merge
        #   )
        def register_known_gems(*gem_names)
          gem_names.each do |tag_name|
            tag_sym = tag_name.to_sym

            unless known_gems.key?(tag_sym)
              warn("Unknown gem: #{tag_name}. Available: #{known_gems.keys.join(', ')}")
              next
            end

            # Skip if already registered
            next if registered?(tag_sym)

            metadata = known_gems.fetch(tag_sym)
            register(
              tag_sym,
              require_path: metadata[:require_path],
              merger_class: metadata[:merger_class],
              test_source: metadata[:test_source],
              category: metadata[:category],
              skip_instantiation: metadata[:skip_instantiation]
            )
          end
        end

        # Get all explicitly registered gem tag names
        #
        # This returns ONLY gems that were explicitly registered via register() or
        # register_known_gems(), NOT every predeclared gem. This prevents premature
        # loading of gems during RSpec tag setup, which would happen before SimpleCov
        # and ruin coverage reporting.
        #
        # @return [Array<Symbol>] list of registered tag names
        def registered_gems
          @mutex.synchronize do
            @registry.keys
          end
        end

        def known_gems
          @mutex.synchronize do
            @known_gems.transform_values(&:dup)
          end
        end

        # Get gems filtered by category
        #
        # @param category [Symbol] one of :markdown, :data, :code, :config, :other
        # @return [Array<Symbol>] list of tag names in that category
        def gems_by_category(category)
          @mutex.synchronize do
            known = @known_gems.select { |_, info| info[:category] == category }.keys
            registered = @registry.select { |_, info| info[:category] == category }.keys
            (known + registered).uniq
          end
        end

        # Force availability checking for all registered gems
        #
        # This method should be called AFTER SimpleCov is loaded (typically at the end
        # of spec_helper.rb) to trigger gem loading and availability checking. Calling
        # this ensures RSpec exclusion filters are properly configured based on which
        # gems are actually available.
        #
        # This is necessary because register_known_gems() only registers gems without
        # checking availability. The actual availability check (which requires loading
        # the gem) must happen AFTER coverage instrumentation is set up.
        #
        # @return [void]
        #
        # @example At the end of spec_helper.rb (after SimpleCov loads)
        #   # Force availability checking now that coverage is instrumented
        #   Ast::Merge::RSpec::MergeGemRegistry.force_check_availability!
        def force_check_availability!
          registered_gems.each do |tag|
            # This will trigger gem_works? which loads the gem
            # Results are cached, so subsequent calls are fast
            available?(tag)
          end
          nil
        end

        # Get registration info for a gem
        #
        # @param tag_name [Symbol] the tag name
        # @return [Hash, nil] registration info or nil if not registered/known
        def info(tag_name)
          tag_sym = tag_name.to_sym
          @mutex.synchronize do
            @registry[tag_sym]&.dup || @known_gems[tag_sym]&.dup
          end
        end

        # Get a summary of all registered gems and their availability
        #
        # @return [Hash{Symbol => Boolean}] map of tag name to availability
        def summary
          registered_gems.each_with_object({}) do |tag, result|
            result[tag] = available?(tag)
          end
        end

        # Clear the availability cache
        #
        # @return [void]
        def clear_cache!
          @mutex.synchronize do
            @availability_cache.clear
          end
          nil
        end

        # Clear all registrations and cache
        #
        # @return [void]
        def clear!
          @mutex.synchronize do
            @registry.clear
            @known_gems.clear
            @availability_cache.clear
          end
          nil
        end

        # Reset memoized availability on DependencyTags
        #
        # @return [void]
        def reset_availability!
          clear_cache!
          return unless defined?(DependencyTags)

          registered_gems.each do |tag|
            ivar = :"@#{tag}_available"
            DependencyTags.remove_instance_variable(ivar) if DependencyTags.instance_variable_defined?(ivar)
          end
        end

        # ============================================================
        # Private Helpers
        # ============================================================

        # Check if a merge gem is available and functional
        #
        # @param require_path [String] the require path for the gem
        # @param merger_class [String] the full class name of the SmartMerger
        # @param test_source [String] sample source code to test merging
        # @param skip_instantiation [Boolean] if true, only check class exists
        # @return [Boolean] true if the merger can be loaded/instantiated
        # @api private
        def gem_works?(require_path, merger_class, test_source, skip_instantiation)
          require require_path
          klass = Object.const_get(merger_class)

          if skip_instantiation
            # Just check that the class exists and looks like a SmartMerger
            klass.is_a?(Class) && klass.ancestors.any? { |a| a.name&.include?('SmartMergerBase') }
          else
            klass.new(test_source, test_source)
            true
          end
        rescue LoadError, StandardError
          false
        end
        private_class_method :gem_works?

        # Dynamically define an availability method on DependencyTags
        #
        # @param tag_name [Symbol] the tag name (e.g., :markly_merge)
        # @return [void]
        # @api private
        def define_availability_method(tag_name)
          method_name = :"#{tag_name}_available?"

          # Only define if DependencyTags is loaded
          return unless defined?(DependencyTags)

          # Don't override existing methods
          return if DependencyTags.respond_to?(method_name)

          # Define the method dynamically - MergeGemRegistry.available? handles caching
          DependencyTags.define_singleton_method(method_name) do
            MergeGemRegistry.available?(tag_name)
          end
        end
        private_class_method :define_availability_method
      end
    end
  end
end
