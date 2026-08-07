# frozen_string_literal: true

module Toml
  module Merge
    # Alias for the shared normalizer module from ast-merge
    NodeTypingNormalizer = Ast::Merge::NodeTyping::Normalizer

    # Normalizes backend-specific node types to canonical TOML types.
    #
    # Uses Ast::Merge::NodeTyping::Wrapper to wrap nodes with canonical
    # merge_type, allowing portable merge rules across backends.
    #
    # ## Thread Safety
    #
    # All backend registration and lookup operations are thread-safe via
    # the shared Ast::Merge::NodeTyping::Normalizer module.
    #
    # ## Backends
    #
    # Currently supports:
    # - `:tree_sitter` - tree-sitter-toml grammar (via ruby_tree_sitter, tree_stump, FFI)
    # - `:citrus` - toml-rb gem with Citrus parser
    # - `:parslet` - toml gem with Parslet parser
    #
    # ## Extensibility
    #
    # New backends can be registered at runtime:
    #
    # @example Registering a new backend
    #   NodeTypeNormalizer.register_backend(:my_toml_parser, {
    #     key_value: :pair,
    #     section: :table,
    #     section_array: :array_of_tables,
    #   })
    #
    # ## Canonical Types
    #
    # The following canonical types are used for portable merge rules:
    #
    # ### Document Structure
    # - `:document` - Root document node
    # - `:table` - Table/section header `[section]`
    # - `:array_of_tables` - Array of tables `[[section]]`
    # - `:pair` - Key-value pair `key = value`
    #
    # ### Key Types
    # - `:bare_key` - Unquoted key
    # - `:quoted_key` - Quoted key `"key"` or `'key'`
    # - `:dotted_key` - Dotted key `a.b.c`
    #
    # ### Value Types
    # - `:string` - String values (basic or literal)
    # - `:integer` - Integer values
    # - `:float` - Floating point values
    # - `:boolean` - Boolean `true`/`false`
    # - `:array` - Array values `[1, 2, 3]`
    # - `:inline_table` - Inline table `{ key = value }`
    #
    # ### Date/Time Types
    # - `:datetime` - Date/time values (offset, local, date-only, time-only)
    #
    # ### Other
    # - `:comment` - Comment lines
    #
    # @see Ast::Merge::NodeTyping::Wrapper
    # @see Ast::Merge::NodeTyping::Normalizer
    module NodeTypeNormalizer
      extend NodeTypingNormalizer

      # Configure default backend mappings.
      # Maps backend-specific type symbols to canonical type symbols.
      #
      # Both tree-sitter-toml and citrus/toml-rb produce similar node types,
      # so the mappings are largely identity mappings with some normalization.
      configure_normalizer(
        # tree-sitter-toml grammar node types
        # Reference: https://github.com/tree-sitter-grammars/tree-sitter-toml
        # All native TreeHaver backends (mri, rust, ffi) use this grammar.
        tree_sitter: {
          # Document structure
          document: :document,
          table: :table,
          table_array_element: :array_of_tables, # tree-sitter uses this name

          # Key-value pairs
          pair: :pair,

          # Key types
          bare_key: :bare_key,
          quoted_key: :quoted_key,
          dotted_key: :dotted_key,

          # Value types
          string: :string,
          basic_string: :string,
          literal_string: :string,
          multiline_basic_string: :string,
          multiline_literal_string: :string,
          integer: :integer,
          float: :float,
          boolean: :boolean,
          array: :array,
          inline_table: :inline_table,

          # Date/time types
          offset_date_time: :datetime,
          local_date_time: :datetime,
          local_date: :datetime,
          local_time: :datetime,

          # Other
          comment: :comment,

          # Punctuation (usually not needed for merge logic, but map them)
          "=": :equals,
          "[": :bracket_open,
          "]": :bracket_close,
          "[[": :double_bracket_open,
          "]]": :double_bracket_close,
          "{": :brace_open,
          "}": :brace_close,
          ",": :comma
        }.freeze,

        # Citrus/toml-rb backend node types
        # These are produced by TreeHaver's Citrus adapter wrapping toml-rb
        # Verified via examples/map_citrus_node_types.rb script
        citrus: {
          # Document structure
          document: :document,
          table: :table,
          table_array: :array_of_tables, # Citrus produces :table_array (not :table_array_element)

          # Key-value pairs
          keyvalue: :pair,  # Citrus produces :keyvalue (not :pair)
          pair: :pair,      # Keep for compatibility if TreeHaver normalizes

          # Key types
          bare_key: :bare_key,
          quoted_key: :quoted_key,
          dotted_key: :dotted_key,
          key: :bare_key,           # Citrus uses :key wrapper
          stripped_key: :bare_key,  # Citrus uses :stripped_key wrapper

          # Value types - Citrus uses more specific type names
          string: :string,
          basic_string: :string,
          literal_string: :string,
          multiline_string: :string,
          multiline_literal: :string,
          integer: :integer,
          decimal_integer: :integer,
          hexadecimal_integer: :integer,
          octal_integer: :integer,
          binary_integer: :integer,
          float: :float,
          fractional_float: :float,
          boolean: :boolean,
          true => :boolean,
          false => :boolean,
          array: :array,
          inline_table: :inline_table,

          # Date/time types - Citrus uses specific names
          datetime: :datetime,
          date: :datetime,
          time: :datetime,
          local_date: :datetime,
          local_time: :datetime,
          local_datetime: :datetime,
          offset_datetime: :datetime,
          date_skeleton: :datetime,
          time_skeleton: :datetime,

          # Other
          comment: :comment,
          space: :whitespace,
          line_break: :whitespace,
          indent: :whitespace,
          repeat: :whitespace,
          unknown: :unknown,

          # Punctuation
          "=": :equals,
          "[": :bracket_open,
          "]": :bracket_close,
          "[[": :double_bracket_open,
          "]]": :double_bracket_close,
          "{": :brace_open,
          "}": :brace_close,
          ",": :comma
        }.freeze,

        # Parslet/toml gem backend node types
        # These are produced by TreeHaver's Parslet adapter wrapping the toml gem
        # Parslet returns Hash/Array/Slice structures with keys from .as(:name) rules
        # Reference: https://github.com/jm/toml (TOML::Parslet grammar)
        parslet: {
          # Document structure
          document: :document,
          hash: :document, # Root result is often a hash
          table: :table,
          table_array: :array_of_tables,

          # Key-value pairs - Parslet uses :key and :value hash keys
          key: :bare_key,
          value: :value,
          pair: :pair, # Synthetic type for key-value combinations

          # Value types - from .as(:type) rules in TOML::Parslet
          string: :string,
          integer: :integer,
          float: :float,
          boolean: :boolean,
          true => :boolean,
          false => :boolean,
          array: :array,

          # Date/time types
          datetime: :datetime,
          datetime_rfc3339: :datetime,

          # Slice types (terminal values)
          slice: :string, # Parslet::Slice defaults to string

          # Structural types from Parslet result structure
          element: :element, # Array elements
          array_element: :element,

          # Unknown/fallback
          unknown: :unknown
        }.freeze
      )

      class << self
        # Default backend for TOML normalization
        DEFAULT_BACKEND = :tree_sitter

        # Get the canonical type for a backend-specific type.
        # Overrides the shared Normalizer to default to :tree_sitter backend.
        #
        # @param backend_type [Symbol, String, nil] The backend's node type
        # @param backend [Symbol] The backend identifier (defaults to :tree_sitter)
        # @return [Symbol, nil] Canonical type (or original if no mapping)
        def canonical_type(backend_type, backend = DEFAULT_BACKEND)
          super(backend_type, backend)
        end

        # Wrap a node with its canonical type as merge_type.
        # Overrides the shared Normalizer to default to :tree_sitter backend.
        #
        # @param node [Object] The backend node to wrap (must respond to #type)
        # @param backend [Symbol] The backend identifier (defaults to :tree_sitter)
        # @return [Ast::Merge::NodeTyping::Wrapper] Wrapped node with canonical merge_type
        def wrap(node, backend = DEFAULT_BACKEND)
          super(node, backend)
        end

        # Check if a type is a table type (regular or array of tables)
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def table_type?(type)
          canonical = type.to_sym
          %i[table array_of_tables].include?(canonical)
        end

        # Check if a type is a value type (string, integer, etc.)
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def value_type?(type)
          canonical = type.to_sym
          %i[string integer float boolean array inline_table datetime].include?(canonical)
        end

        # Check if a type is a key type
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def key_type?(type)
          canonical = type.to_sym
          %i[bare_key quoted_key dotted_key].include?(canonical)
        end

        # Check if a type is a container type (can have children)
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def container_type?(type)
          canonical = type.to_sym
          %i[document table array_of_tables array inline_table].include?(canonical)
        end
      end
    end
  end
end
