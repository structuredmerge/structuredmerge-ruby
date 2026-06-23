# frozen_string_literal: true

module Ast
  module Merge
    # Recipe namespace for YAML-based merge recipe functionality.
    #
    # This module contains classes for loading, configuring, and executing
    # merge recipes that define how to perform partial template merges.
    #
    # @example Loading and running a recipe
    #   recipe = Ast::Merge::Recipe::Config.load("my_recipe.yml")
    #   runner = Ast::Merge::Recipe::Runner.new(recipe, dry_run: true)
    #   results = runner.run
    #
    # @see Recipe::Config Recipe configuration and loading
    # @see Recipe::Runner Recipe execution
    # @see Recipe::ScriptLoader Loading Ruby scripts from recipe folders
    #
    module Recipe
      autoload :Config, 'ast/merge/recipe/config'
      autoload :Preset, 'ast/merge/recipe/preset'
      autoload :Runner, 'ast/merge/recipe/runner'
      autoload :ScriptLoader, 'ast/merge/recipe/script_loader'
    end
  end
end
