# frozen_string_literal: true

module TreeHaver
  module Base
    # Base class for backend Language implementations
    #
    # This class defines the API contract for all language implementations.
    # Backend-specific Language classes should inherit from this and implement
    # the required interface.
    #
    # @abstract Subclasses must implement #name and #backend at minimum
    class Language
      include Comparable

      # The language name (e.g., :markdown, :ruby, :json)
      # @return [Symbol] Language name
      attr_reader :name

      # The backend this language is for
      # @return [Symbol] Backend identifier (e.g., :commonmarker, :markly, :prism)
      attr_reader :backend

      # Language-specific options
      # @return [Hash] Options hash
      attr_reader :options

      # Create a new Language instance
      #
      # @param name [Symbol, String] Language name
      # @param backend [Symbol] Backend identifier
      # @param options [Hash] Backend-specific options
      def initialize(name, backend:, options: {})
        @name = name.to_sym
        @backend = backend.to_sym
        @options = options
      end

      # Alias for name (tree-sitter compatibility)
      alias language_name name

      # -- Shared Implementation ------------------------------------------------

      # Comparison based on backend then name
      # @param other [Object]
      # @return [Integer, nil]
      def <=>(other)
        return unless other.is_a?(Language)
        return unless other.respond_to?(:backend) && other.backend == backend

        name <=> other.name
      end

      # Hash value for use in Sets/Hashes
      # @return [Integer]
      def hash
        [backend, name, options.to_a.sort].hash
      end

      # Equality check for Hash keys
      # @param other [Object]
      # @return [Boolean]
      def eql?(other)
        return false unless other.is_a?(Language)

        backend == other.backend && name == other.name && options == other.options
      end

      # Human-readable representation
      # @return [String]
      def inspect
        opts = options.empty? ? '' : " options=#{options}"
        class_name = self.class.name || "#{self.class.superclass.name}(anonymous)"
        "#<#{class_name} name=#{name} backend=#{backend}#{opts}>"
      end

      # -- Class Methods --------------------------------------------------------

      class << self
        # Load a language from a library path (factory method)
        #
        # For pure-Ruby backends (Commonmarker, Markly, Prism, Psych), this
        # typically ignores the path and returns the single supported language.
        #
        # For tree-sitter backends (MRI, Rust, FFI, Java), this loads the
        # language from the shared library file.
        #
        # @param _path [String, nil] Path to shared library (optional for pure-Ruby)
        # @param symbol [String, nil] Symbol name to load (optional)
        # @param name [String, nil] Language name hint (optional)
        # @return [Language] Loaded language instance
        # @raise [NotImplementedError] If not implemented by subclass
        def from_library(_path = nil, symbol: nil, name: nil)
          raise NotImplementedError, "#{self}.from_library must be implemented"
        end
      end
    end
  end
end
