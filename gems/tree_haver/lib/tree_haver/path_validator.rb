# frozen_string_literal: true

module TreeHaver
  # Security utilities for validating paths and inputs before loading shared libraries.
  #
  # Loading shared libraries (.so/.dylib/.dll) is inherently dangerous as it executes
  # arbitrary native code. This module provides defense-in-depth validations to reduce
  # the attack surface when paths come from potentially untrusted sources like
  # environment variables or user input.
  #
  # @example Validate a path before loading
  #   path = ENV["TREE_SITTER_TOML_PATH"]
  #   if TreeHaver::PathValidator.safe_library_path?(path)
  #     language = TreeHaver::Language.from_library(path)
  #   else
  #     raise "Unsafe path: #{path}"
  #   end
  #
  # @example Register custom trusted directories
  #   # For Homebrew on Linux (linuxbrew)
  #   TreeHaver::PathValidator.add_trusted_directory("/home/linuxbrew/.linuxbrew/Cellar")
  #
  #   # For luarocks-installed grammars
  #   TreeHaver::PathValidator.add_trusted_directory("~/.local/share/mise/installs/lua")
  #
  #   # Or via environment variable (comma-separated)
  #   # export TREE_HAVER_TRUSTED_DIRS="/home/linuxbrew/.linuxbrew/Cellar,~/.local/share/mise"
  #
  # @note These validations provide defense-in-depth but cannot guarantee safety.
  #   Loading shared libraries from untrusted sources is always risky.
  module PathValidator
    # Allowed shared library extensions by platform
    ALLOWED_EXTENSIONS = %w[.so .dylib .dll].freeze

    # Default directories that are generally trusted for system libraries
    # These are searched by the dynamic linker anyway
    DEFAULT_TRUSTED_DIRECTORIES = [
      "/usr/lib",
      "/usr/lib64",
      "/usr/lib/x86_64-linux-gnu",
      "/usr/lib/aarch64-linux-gnu",
      "/usr/local/lib",
      "/opt/homebrew/lib",
      "/opt/local/lib",
    ].freeze

    # Environment variable for adding trusted directories (comma-separated)
    TRUSTED_DIRS_ENV_VAR = "TREE_HAVER_TRUSTED_DIRS"

    # Maximum reasonable path length (prevents DoS via extremely long paths)
    MAX_PATH_LENGTH = 4096

    # Pattern for valid library filenames (alphanumeric, hyphens, underscores, dots)
    # This prevents shell metacharacters and other injection attempts
    VALID_FILENAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

    # Pattern for valid language names (lowercase alphanumeric and underscores)
    VALID_LANGUAGE_PATTERN = /\A[a-z][a-z0-9_]*\z/

    # Pattern for valid symbol names (C identifier format)
    VALID_SYMBOL_PATTERN = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

    @custom_trusted_directories = [] # rubocop:disable ThreadSafety/MutableClassInstanceVariable
    @mutex = Mutex.new

    module_function

    # Get all trusted directories (default + user-local + custom + from ENV)
    #
    # @return [Array<String>] list of all trusted directory prefixes
    def trusted_directories
      dirs = DEFAULT_TRUSTED_DIRECTORIES.dup

      # Add user-local XDG directories (computed at call time from HOME)
      begin
        home = Dir.home
        dirs << File.join(home, ".local", "lib", "tree-sitter")
        dirs << File.join(home, ".local", "lib")
      rescue ArgumentError
        # HOME not set — skip user-local dirs
      end

      # Add custom registered directories
      @mutex.synchronize { dirs.concat(@custom_trusted_directories) }

      # Add directories from environment variable
      ENV[TRUSTED_DIRS_ENV_VAR]&.split(",")&.each do |dir|
        expanded = File.expand_path(dir.strip)
        # simplecov:disable
        # File.expand_path always returns absolute paths on Unix/macOS.
        # This guard exists for defensive programming on exotic platforms
        # where expand_path might behave differently, but cannot be tested
        # in standard CI environments.
        dirs << expanded if expanded.start_with?("/")
        # simplecov:enable
      end

      dirs.uniq
    end

    # Register a custom trusted directory
    #
    # Use this to add directories where you install tree-sitter grammars,
    # such as Homebrew locations, luarocks paths, or other package managers.
    #
    # @param directory [String] absolute path to trust (~ is expanded)
    # @return [void]
    # @raise [ArgumentError] if directory is not an absolute path
    #
    # @example Register linuxbrew directory
    #   TreeHaver::PathValidator.add_trusted_directory("/home/linuxbrew/.linuxbrew/Cellar")
    #
    # @example Register user's luarocks directory
    #   TreeHaver::PathValidator.add_trusted_directory("~/.local/share/mise/installs/lua")
    def add_trusted_directory(directory)
      expanded = File.expand_path(directory)

      # simplecov:disable
      # File.expand_path always returns absolute paths on Unix/macOS.
      # This guard exists for defensive programming on exotic platforms
      # where expand_path might behave differently, but cannot be tested
      # in standard CI environments.
      unless expanded.start_with?("/")
        raise ArgumentError, "Trusted directory must be an absolute path: #{directory.inspect}"
      end
      # simplecov:enable

      @mutex.synchronize do
        @custom_trusted_directories << expanded unless @custom_trusted_directories.include?(expanded)
      end
      nil
    end

    # Remove a custom trusted directory
    #
    # @param directory [String] the directory to remove
    # @return [void]
    def remove_trusted_directory(directory)
      expanded = File.expand_path(directory)
      @mutex.synchronize { @custom_trusted_directories.delete(expanded) }
      nil
    end

    # Clear all custom trusted directories
    #
    # Does not affect DEFAULT_TRUSTED_DIRECTORIES or ENV-based directories.
    # Primarily useful for testing.
    #
    # @return [void]
    def clear_custom_trusted_directories!
      @mutex.synchronize { @custom_trusted_directories.clear }
      nil
    end

    # Get the list of custom trusted directories (for debugging)
    #
    # @return [Array<String>] list of custom registered directories
    def custom_trusted_directories
      @mutex.synchronize { @custom_trusted_directories.dup }
    end

    # Validate a path is safe for loading as a shared library
    #
    # Checks performed:
    # - Path is not nil or empty
    # - Path length is reasonable
    # - Path is absolute (no relative path traversal)
    # - Path has an allowed extension
    # - Path does not contain null bytes
    # - Filename portion matches safe pattern
    #
    # @param path [String, nil] the path to validate
    # @param require_trusted_dir [Boolean] if true, path must be in a trusted directory
    # @return [Boolean] true if the path passes all safety checks
    #
    # @example
    #   PathValidator.safe_library_path?("/usr/lib/libtree-sitter-toml.so")
    #   # => true
    #
    #   PathValidator.safe_library_path?("../../../tmp/evil.so")
    #   # => false
    def safe_library_path?(path, require_trusted_dir: false)
      return false if path.nil? || path.empty?
      return false if path.length > MAX_PATH_LENGTH
      return false if path.include?("\0") # Null byte injection

      # Must be absolute path (prevents relative path traversal)
      return false unless path.start_with?("/") || windows_absolute_path?(path)

      # Check for path traversal attempts
      return false if path.include?("/../") || path.end_with?("/..")
      return false if path.include?("/./") || path.end_with?("/.")

      # Validate extension
      # Allow versioned .so files like .so.0, .so.14, etc. (common on Linux)
      return false unless has_valid_extension?(path)

      # Validate filename portion
      filename = File.basename(path)
      return false unless filename.match?(VALID_FILENAME_PATTERN)

      # Optionally require the path to be in a trusted directory
      if require_trusted_dir
        return false unless in_trusted_directory?(path)
      end

      true
    end

    # Check if a path is within a trusted directory
    #
    # Checks against DEFAULT_TRUSTED_DIRECTORIES, custom registered directories,
    # and directories from TREE_HAVER_TRUSTED_DIRS environment variable.
    #
    # @param path [String] the path to check
    # @return [Boolean] true if the path is in a trusted directory
    def in_trusted_directory?(path)
      return false if path.nil?

      # Resolve the real path to handle symlinks
      check_path = resolve_check_path(path)
      return false if check_path.nil?

      trusted_directories.any? { |trusted| check_path.start_with?(trusted) }
    end

    # Resolve a path to its real path for trust checking
    #
    # @param path [String] the path to resolve
    # @return [String, nil] the resolved path or nil if unresolvable
    # @api private
    def resolve_check_path(path)
      File.realpath(path)
    rescue Errno::ENOENT
      # File doesn't exist yet, check the directory
      dir = File.dirname(path)
      begin
        File.realpath(dir)
      rescue Errno::ENOENT
        nil
      end
    end

    # Validate a language name is safe
    #
    # Language names are used to construct:
    # - Environment variable names (TREE_SITTER_<LANG>_PATH)
    # - Library filenames (libtree-sitter-<lang>.so)
    # - Symbol names (tree_sitter_<lang>)
    #
    # @param name [String, Symbol, nil] the language name to validate
    # @return [Boolean] true if the name is safe
    #
    # @example
    #   PathValidator.safe_language_name?(:toml)  # => true
    #   PathValidator.safe_language_name?("json") # => true
    #   PathValidator.safe_language_name?("../../etc") # => false
    def safe_language_name?(name)
      return false if name.nil?

      name_str = name.to_s
      return false if name_str.empty?
      return false if name_str.length > 64 # Reasonable limit

      name_str.match?(VALID_LANGUAGE_PATTERN)
    end

    # Validate a symbol name is safe for dlsym lookup
    #
    # @param symbol [String, nil] the symbol name to validate
    # @return [Boolean] true if the symbol name is safe
    #
    # @example
    #   PathValidator.safe_symbol_name?("tree_sitter_toml") # => true
    #   PathValidator.safe_symbol_name?("evil; rm -rf /")   # => false
    def safe_symbol_name?(symbol)
      return false if symbol.nil?
      return false if symbol.empty?
      return false if symbol.length > 256 # Reasonable limit

      symbol.match?(VALID_SYMBOL_PATTERN)
    end

    # Validate a backend name
    #
    # @param backend [String, Symbol, nil] the backend name
    # @return [Boolean] true if it's a valid backend name
    def safe_backend_name?(backend)
      return true if backend.nil? # nil means :auto

      %i[auto mri rust ffi java].include?(backend.to_s.to_sym)
    end

    # Sanitize a language name for safe use
    #
    # @param name [String, Symbol] the language name
    # @return [Symbol, nil] sanitized name or nil if invalid
    #
    # @example
    #   PathValidator.sanitize_language_name("TOML")  # => :toml
    #   PathValidator.sanitize_language_name("c++")   # => nil (invalid)
    def sanitize_language_name(name)
      return if name.nil?

      sanitized = name.to_s.downcase.gsub(/[^a-z0-9_]/, "")
      return if sanitized.empty?
      return unless sanitized.match?(/\A[a-z]/)

      sanitized.to_sym
    end

    # Get validation errors for a path (for debugging/error messages)
    #
    # @param path [String, nil] the path to validate
    # @return [Array<String>] list of validation errors (empty if valid)
    def validation_errors(path)
      errors = []

      if path.nil? || path.empty?
        errors << "Path is nil or empty"
        return errors
      end

      errors << "Path exceeds maximum length (#{MAX_PATH_LENGTH})" if path.length > MAX_PATH_LENGTH
      errors << "Path contains null byte" if path.include?("\0")
      errors << "Path is not absolute" unless path.start_with?("/") || windows_absolute_path?(path)
      errors << "Path contains traversal sequence (/../)" if path.include?("/../") || path.end_with?("/..")
      errors << "Path contains traversal sequence (/./)" if path.include?("/./") || path.end_with?("/.")

      unless has_valid_extension?(path)
        errors << "Path does not have allowed extension (.so, .so.X, .dylib, .dll)"
      end

      filename = File.basename(path)
      unless filename.match?(VALID_FILENAME_PATTERN)
        errors << "Filename contains invalid characters"
      end

      errors
    end

    # @api private
    def windows_absolute_path?(path)
      # Match Windows absolute paths like C:\path or D:/path
      path.match?(/\A[A-Za-z]:[\\\/]/)
    end

    # @api private
    # Check if path has a valid library extension
    # Allows: .so, .dylib, .dll, and versioned .so files like .so.0, .so.14
    def has_valid_extension?(path)
      # Check for exact matches first (.so, .dylib, .dll)
      return true if ALLOWED_EXTENSIONS.any? { |ext| path.end_with?(ext) }

      # Check for versioned .so files (Linux convention)
      # e.g., libtree-sitter.so.0, libtree-sitter.so.14
      return true if path.match?(/\.so\.\d+\z/)

      false
    end
  end
end
