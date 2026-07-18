# frozen_string_literal: true

require 'rbconfig'

module TreeHaver
  # Registration-first utility for finding tree-sitter grammar shared libraries.
  #
  # GrammarFinder resolves tree-sitter grammars in a constrained order:
  #
  # 1. explicit environment override
  # 2. existing TreeHaver registration
  # 3. explicit extra paths
  # 4. tree_sitter_language_pack cache/provisioning
  #
  # This class is designed to be used by language-specific merge gems
  # without requiring TreeHaver to own parser- or grammar-specific policy.
  #
  # == Security Considerations
  #
  # Loading shared libraries is inherently dangerous as it executes arbitrary
  # native code. GrammarFinder performs the following security validations:
  #
  # - Language names are validated to contain only safe characters
  # - Paths from environment variables are validated before use
  # - Path traversal attempts (../) are rejected
  # - Only files with expected extensions (.so, .dylib, .dll) are accepted
  #
  # For additional security, use {#find_library_path_safe} which only returns
  # paths from trusted system directories.
  #
  # @example Basic usage
  #   finder = TreeHaver::GrammarFinder.new(:toml)
  #   path = finder.find_library_path
  #   # => "/home/user/.cache/tree-sitter-language-pack/vX/libs/libtree_sitter_toml.so"
  #
  # @example Check availability
  #   finder = TreeHaver::GrammarFinder.new(:json)
  #   if finder.available?
  #     language = TreeHaver::Language.load(finder.language_name, finder.find_library_path)
  #   end
  #
  # @example Register with TreeHaver
  #   finder = TreeHaver::GrammarFinder.new(:bash)
  #   finder.register! if finder.available?
  #   # Now you can use: TreeHaver::Language.bash
  #
  # @example With custom search paths
  #   finder = TreeHaver::GrammarFinder.new(:toml, extra_paths: ["/opt/custom/lib"])
  #
  # @example Secure mode (trusted directories only)
  #   finder = TreeHaver::GrammarFinder.new(:toml)
  #   path = finder.find_library_path_safe  # Only returns paths in trusted dirs
  #
  # @see PathValidator For details on security validations
  class GrammarFinder
    # @return [Symbol] the language identifier
    attr_reader :language_name

    # @return [Array<String>] additional search paths provided at initialization
    attr_reader :extra_paths

    # Initialize a grammar finder for a specific language
    #
    # @param language_name [Symbol, String] the tree-sitter language name (e.g., :toml, :json, :bash)
    # @param extra_paths [Array<String>] additional paths to search (searched first after ENV)
    # @param validate [Boolean] if true, validates the language name (default: true)
    # @raise [ArgumentError] if language_name is invalid and validate is true
    def initialize(language_name, extra_paths: [], validate: true)
      name_str = language_name.to_s.downcase

      if validate && !PathValidator.safe_language_name?(name_str)
        raise ArgumentError, "Invalid language name: #{language_name.inspect}. " \
          'Language names must start with a letter and contain only lowercase letters, numbers, and underscores.'
      end

      @language_name = name_str.to_sym
      @extra_paths = Array(extra_paths)
    end

    # Get the environment variable name for this language
    #
    # @return [String] the ENV var name (e.g., "TREE_SITTER_TOML_PATH")
    def env_var_name
      "TREE_SITTER_#{@language_name.to_s.upcase}_PATH"
    end

    # Get the expected symbol name exported by the grammar library
    #
    # @return [String] the symbol name (e.g., "tree_sitter_toml")
    def symbol_name
      "tree_sitter_#{@language_name}"
    end

    # Get the canonical tree-sitter-language-pack filename for the current platform
    #
    # @return [String] the library filename (e.g., "libtree_sitter_toml.so")
    def library_filename
      library_filenames.first
    end

    # Get all accepted library filenames for this language
    #
    # Accept both the tree-sitter-language-pack naming convention and the
    # historical hyphenated form used by some standalone grammar builds.
    #
    # @return [Array<String>]
    def library_filenames
      ext = platform_extension
      [
        "libtree_sitter_#{@language_name}#{ext}",
        "libtree-sitter-#{@language_name}#{ext}"
      ]
    end

    # Generate the full list of search paths for this language
    #
    # Order: registered path, explicit extra paths, then tree_sitter_language_pack cache
    #
    # @return [Array<String>] all paths to search
    def search_paths
      paths = []

      registration = registered_tree_sitter_registration
      paths << registration[:path] if registration&.dig(:path)

      @extra_paths.each do |dir|
        library_filenames.each do |filename|
          paths << File.join(dir, filename)
        end
      end

      cache_dir = tree_sitter_language_pack_cache_dir
      if cache_dir
        library_filenames.each do |filename|
          paths << File.join(cache_dir, filename)
        end
      end

      paths.uniq
    end

    # Find the grammar library path
    #
    # Searches in order:
    # 1. Environment variable override (validated for safety)
    # 2. Existing TreeHaver tree-sitter registration
    # 3. Extra paths provided at initialization
    # 4. tree_sitter_language_pack cache / on-demand download
    #
    # @note Paths from ENV are validated using {PathValidator.safe_library_path?}
    #   to prevent path traversal and other attacks. Invalid ENV paths cause
    #   an error to be raised (Principle of Least Surprise - explicit paths must work).
    #
    # @note Setting the ENV variable to an empty string explicitly disables
    #   this grammar. This allows fallback to alternative backends (e.g., Citrus).
    #
    # @return [String, nil] the path to the library, or nil if not found
    # @raise [TreeHaver::NotAvailable] if ENV variable is set to an invalid path
    # @see #find_library_path_safe For stricter validation (trusted directories only)
    def find_library_path
      # Check environment variable first (highest priority)
      # Use key? to distinguish between "not set" and "set to empty"
      env_var = env_var_name
      if ENV[env_var] || ENV.key?(env_var)
        env_path = ENV[env_var]

        # simplecov:disable defensive - ENV.key? true with nil value is rare edge case
        if env_path.nil?
          @env_rejection_reason = 'explicitly disabled (set to nil)'
          return
        end
        # simplecov:enable

        # Empty string means "explicitly skip this grammar"
        # This allows users to disable tree-sitter for specific languages
        # and fall back to alternative backends like Citrus
        if env_path.empty?
          @env_rejection_reason = 'explicitly disabled (set to empty string)'
          return
        end

        # Store why env path was rejected for better error messages
        @env_rejection_reason = validate_env_path(env_path)

        # Principle of Least Surprise: If user explicitly sets an ENV variable
        # to a path, that path MUST work. Don't silently fall back to auto-discovery.
        if @env_rejection_reason
          raise TreeHaver::NotAvailable,
                "#{env_var_name} is set to #{env_path.inspect} but #{@env_rejection_reason}. " \
                  'Either fix the path, unset the variable to use auto-discovery, ' \
                  'or set it to empty string to explicitly disable this grammar.'
        end

        return env_path
      end

      registered_path = registered_tree_sitter_path
      return registered_path if registered_path

      explicit_path = explicit_search_path
      return explicit_path if explicit_path

      tree_sitter_language_pack_path
    end

    # Validate an environment variable path and return reason if invalid
    # @return [String, nil] rejection reason or nil if valid
    def validate_env_path(path)
      # Check for leading/trailing whitespace
      return "contains leading or trailing whitespace (use #{path.strip.inspect})" if path != path.strip

      # Check if path is safe
      unless PathValidator.safe_library_path?(path)
        return 'failed security validation (may contain path traversal or suspicious characters)'
      end

      # Check if file exists
      return 'file does not exist' unless File.exist?(path)

      nil # Valid!
    end

    # Find the grammar library path with strict security validation
    #
    # This method only returns paths that are in trusted system directories.
    # Use this when you want maximum security and don't need to support
    # custom installation locations.
    #
    # @return [String, nil] the path to the library, or nil if not found
    # @see PathValidator::TRUSTED_DIRECTORIES For the list of trusted directories
    def find_library_path_safe
      search_paths.find do |path|
        File.exist?(path) && PathValidator.in_trusted_directory?(path)
      end
    end

    # Check if the grammar library is available AND usable
    #
    # This checks:
    # 1. The grammar library file exists
    # 2. The tree-sitter runtime is functional (can create a parser)
    #
    # This prevents registering grammars when tree-sitter isn't actually usable,
    # allowing clean fallback to alternative backends like Citrus.
    #
    # @return [Boolean] true if the library can be found AND tree-sitter runtime works
    def available?
      return true if tree_sitter_language_pack_parser_available?

      path = find_library_path
      return false if path.nil?

      # Check if tree-sitter runtime is actually functional
      # This is cached at the class level since it's the same for all grammars
      self.class.tree_sitter_runtime_usable?
    end

    # Backends that use tree-sitter (require native runtime libraries)
    # Other backends (Citrus, Prism, Psych, etc.) don't use tree-sitter
    TREE_SITTER_BACKENDS = [
      TreeHaver::Backends::MRI,
      TreeHaver::Backends::FFI,
      TreeHaver::Backends::Rust,
      TreeHaver::Backends::Java
    ].freeze

    class << self
      # Check if the tree-sitter runtime is usable
      #
      # Tests whether we can actually create a tree-sitter parser.
      # Result is cached since this is expensive and won't change during runtime.
      #
      # @return [Boolean] true if tree-sitter runtime is functional
      def tree_sitter_runtime_usable?
        return @tree_sitter_runtime_usable if defined?(@tree_sitter_runtime_usable)

        @tree_sitter_runtime_usable = begin
          # Try to create a parser using the current backend
          mod = TreeHaver.resolve_backend_module(nil)

          # Only tree-sitter backends are relevant here
          # Non-tree-sitter backends (Citrus, Prism, Psych, etc.) don't use grammar files
          if mod.nil? || !TREE_SITTER_BACKENDS.include?(mod)
            false
          else
            # Try to instantiate a parser - this will fail if runtime isn't available
            mod::Parser.new
            true
          end
        rescue NoMethodError, LoadError, NotAvailable => _e
          # NOTE: FFI::NotFoundError inherits from LoadError, so it's caught here too
          false
        end
      end

      # Reset the cached tree-sitter runtime check (for testing)
      #
      # @api private
      def reset_runtime_check!
        remove_instance_variable(:@tree_sitter_runtime_usable) if defined?(@tree_sitter_runtime_usable)
      end
    end

    # Check if the grammar library is available in a trusted directory
    #
    # @return [Boolean] true if the library can be found in a trusted directory
    # @see #find_library_path_safe
    def available_safe?
      !find_library_path_safe.nil?
    end

    # Register this language with TreeHaver
    #
    # After registration, the language can be loaded via dynamic method
    # (e.g., `TreeHaver::Language.toml`).
    #
    # @param raise_on_missing [Boolean] if true, raises when library not found
    # @return [Boolean] true if registration succeeded
    # @raise [NotAvailable] if library not found and raise_on_missing is true
    def register!(raise_on_missing: false)
      if tree_sitter_language_pack_parser_available?
        TreeHaver.register_language(
          @language_name,
          backend_module: TreeHaver::Backends::Tslp,
          backend_type: :tslp,
          gem_name: 'tree_sitter_language_pack'
        )
        return true
      end

      path = find_library_path
      unless path
        raise NotAvailable, not_found_message if raise_on_missing

        return false
      end

      TreeHaver.register_language(@language_name, path: path, symbol: symbol_name)
      true
    end

    # Get debug information about the search
    #
    # @return [Hash] diagnostic information
    def search_info
      found = find_library_path # This populates @env_rejection_reason
      {
        language: @language_name,
        env_var: env_var_name,
        env_value: ENV[env_var_name],
        env_rejection_reason: @env_rejection_reason,
        symbol: symbol_name,
        library_filename: library_filename,
        library_filenames: library_filenames,
        search_paths: search_paths,
        found_path: found,
        available: !found.nil?
      }
    end

    # Get a human-readable error message when library is not found
    #
    # @return [String] error message with installation hints
    def not_found_message
      msg = "tree-sitter #{@language_name} grammar not found."

      # Check if env var is set but rejected
      env_value = ENV[env_var_name]
      msg += if env_value && @env_rejection_reason
               " #{env_var_name} is set to #{env_value.inspect} but #{@env_rejection_reason}."
             elsif env_value && File.exist?(env_value) && !self.class.tree_sitter_runtime_usable?
               " #{env_var_name} is set and file exists, but no tree-sitter runtime is available. " \
                 'Add ruby_tree_sitter, ffi, or tree_stump gem to your Gemfile.'
             else
               " Searched: #{search_paths.join(', ')}."
             end

      msg + " Register the grammar, install tree_sitter_language_pack, or set #{env_var_name} to a valid path."
    end

    private

    def registered_tree_sitter_registration
      TreeHaver::LanguageRegistry.registered(@language_name, :tree_sitter)
    end

    def registered_tree_sitter_path
      registration = registered_tree_sitter_registration
      path = registration&.dig(:path)
      return unless path
      return path if File.exist?(path)

      @registered_rejection_reason = "registered path does not exist: #{path}"
      nil
    end

    def explicit_search_path
      search_paths.find { |path| File.exist?(path) }
    end

    def tree_sitter_language_pack_path
      return @tree_sitter_language_pack_path if defined?(@tree_sitter_language_pack_path)

      @tree_sitter_language_pack_path = begin
        require 'tree_sitter_language_pack'
        language = @language_name.to_s
        if TreeSitterLanguagePack.has_language(language)
          TreeSitterLanguagePack.download([language])
          cache_dir = TreeSitterLanguagePack.cache_dir
          @tree_sitter_language_pack_cache_dir = cache_dir

          library_filenames
            .map { |filename| File.join(cache_dir, filename) }
            .find { |path| File.exist?(path) }
        else
          @tree_sitter_language_pack_rejection_reason = 'language not published by tree_sitter_language_pack'
          nil
        end
      rescue LoadError
        @tree_sitter_language_pack_rejection_reason = 'tree_sitter_language_pack gem not available'
        nil
      rescue StandardError => e
        @tree_sitter_language_pack_rejection_reason = e.message
        nil
      end
    end

    def tree_sitter_language_pack_parser_available?
      return @tree_sitter_language_pack_parser_available if defined?(@tree_sitter_language_pack_parser_available)

      @tree_sitter_language_pack_parser_available = begin
        require 'tree_sitter_language_pack'
        TreeHaver::Backends::Tslp.available? &&
          TreeSitterLanguagePack.respond_to?(:has_language) &&
          TreeSitterLanguagePack.has_language(@language_name.to_s)
      rescue LoadError
        false
      rescue StandardError => e
        @tree_sitter_language_pack_rejection_reason = e.message
        false
      end
    end

    def tree_sitter_language_pack_cache_dir
      return @tree_sitter_language_pack_cache_dir if defined?(@tree_sitter_language_pack_cache_dir)

      @tree_sitter_language_pack_cache_dir = begin
        require 'tree_sitter_language_pack'
        TreeSitterLanguagePack.cache_dir
      rescue LoadError, StandardError
        nil
      end
    end

    # Get the platform-appropriate shared library extension
    #
    # @return [String] ".so" on Linux, ".dylib" on macOS
    def platform_extension
      case RbConfig::CONFIG['host_os']
      when /darwin/i
        '.dylib'
      when /mswin|mingw|cygwin/i
        '.dll'
      else
        '.so'
      end
    end
  end
end
