# frozen_string_literal: true

module Ast
  module Merge
    # Namespace for navigation-related classes.
    #
    # Provides unified navigation over AST nodes regardless of the underlying parser.
    # Classes in this namespace work together to enable finding and manipulating
    # positions in document structures.
    #
    # @see Navigable::Statement Wraps nodes with navigation capabilities
    # @see Navigable::InjectionPoint Represents a location for content injection
    # @see Navigable::InjectionPointFinder Finds injection points by matching rules
    module Navigable
      autoload :Statement, 'ast/merge/navigable/statement'
      autoload :InjectionPoint, 'ast/merge/navigable/injection_point'
      autoload :InjectionPointFinder, 'ast/merge/navigable/injection_point_finder'
    end
  end
end
