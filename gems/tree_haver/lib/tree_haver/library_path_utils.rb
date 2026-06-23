# frozen_string_literal: true

module TreeHaver
  # Utility methods for deriving tree-sitter symbol and language names from library paths
  #
  # This module provides consistent path parsing across all backends that load
  # tree-sitter grammar libraries from shared object files (.so/.dylib/.dll).
  #
  # @example
  #   TreeHaver::LibraryPathUtils.derive_symbol_from_path("/usr/lib/libtree-sitter-toml.so")
  #   # => "tree_sitter_toml"
  #
  #   TreeHaver::LibraryPathUtils.derive_language_name_from_path("/usr/lib/libtree-sitter-toml.so")
  #   # => "toml"
  module LibraryPathUtils
    module_function

    # Derive the tree-sitter symbol name from a library path
    #
    # Symbol names are the exported C function names (e.g., "tree_sitter_toml")
    # that return a pointer to the TSLanguage struct.
    #
    # Handles various naming conventions:
    # - libtree-sitter-toml.so → tree_sitter_toml
    # - libtree_sitter_toml.so → tree_sitter_toml
    # - tree-sitter-toml.so → tree_sitter_toml
    # - tree_sitter_toml.so → tree_sitter_toml
    # - toml.so → tree_sitter_toml (assumes simple language name)
    #
    # @param path [String, nil] path like "/usr/lib/libtree-sitter-toml.so"
    # @return [String, nil] symbol like "tree_sitter_toml", or nil if path is nil
    def derive_symbol_from_path(path)
      return unless path

      # Extract filename without extension: "libtree-sitter-toml" or "toml"
      filename = File.basename(path, '.*')

      # Handle multi-part extensions like .so.0.24
      filename = filename.sub(/\.so(\.\d+)*\z/, '')

      # Match patterns and normalize to tree_sitter_<lang>
      case filename
      when /\Alib[-_]?tree[-_]sitter[-_](.+)\z/
        "tree_sitter_#{Regexp.last_match(1).tr('-', '_')}"
      when /\Atree[-_]sitter[-_](.+)\z/
        "tree_sitter_#{Regexp.last_match(1).tr('-', '_')}"
      else
        # Assume filename is just the language name (e.g., "toml.so" -> "tree_sitter_toml")
        # Also strip "lib" prefix if present (e.g., "libtoml.so" -> "tree_sitter_toml")
        lang = filename.sub(/\Alib/, '').tr('-', '_')
        "tree_sitter_#{lang}"
      end
    end

    # Derive the language name from a library path
    #
    # Language names are the short identifiers (e.g., "toml", "json", "ruby")
    # used by some backends (like tree_stump/Rust) to register grammars.
    #
    # @param path [String, nil] path like "/usr/lib/libtree-sitter-toml.so"
    # @return [String, nil] language name like "toml", or nil if path is nil
    def derive_language_name_from_path(path)
      symbol = derive_symbol_from_path(path)
      return unless symbol

      # Strip the "tree_sitter_" prefix to get the language name
      symbol.sub(/\Atree_sitter_/, '')
    end

    # Derive language name from a symbol
    #
    # @param symbol [String, nil] symbol like "tree_sitter_toml"
    # @return [String, nil] language name like "toml", or nil if symbol is nil
    def derive_language_name_from_symbol(symbol)
      return unless symbol

      symbol.sub(/\Atree_sitter_/, '')
    end
  end
end
