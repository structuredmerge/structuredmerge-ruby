# frozen_string_literal: true

# std libs

# External gems
# TreeHaver provides a unified cross-Ruby interface to tree-sitter.
# Bash::Merge registers its TreeHaver grammar bootstrap when loaded so
# parser_for(:bash) can resolve a registered grammar consistently.
#
# BACKEND COMPATIBILITY for Bash:
# - FFI: Most portable and reliable with bash grammar (recommended)
# - MRI: Has ABI incompatibility with bash grammar
# - Rust: Has version mismatch with bash grammar
#
# Set TREE_HAVER_BACKEND=ffi (or mri/rust) to control backend selection.
# When MRI loads a grammar first, FFI gets incompatible pointers (symbol conflict).
# MRI statically links tree-sitter, FFI dynamically links libtree-sitter.so.
require 'tree_haver'

# Shared merge infrastructure
require 'ast/merge'

# This gem

# Bash::Merge provides a generic Bash script smart merge system using tree-sitter AST analysis.
# It intelligently merges template and destination Bash scripts by identifying matching
# statements and resolving differences using structural signatures.
#
# @example Basic usage
#   template = File.read("template.sh")
#   destination = File.read("destination.sh")
#   merger = Bash::Merge::SmartMerger.new(template, destination)
#   result = merger.merge
#
# @example With debug information
#   merger = Bash::Merge::SmartMerger.new(template, destination)
#   debug_result = merger.merge_with_debug
#   puts debug_result[:content]
#   puts debug_result[:statistics]
module Bash
  # Smart merge system for Bash scripts using tree-sitter AST analysis.
  # Provides intelligent merging by understanding Bash structure
  # rather than treating files as plain text.
  #
  # @see SmartMerger Main entry point for merge operations
  # @see FileAnalysis Analyzes Bash structure
  module Merge
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)
    Availability = Struct.new(
      :grammar_path,
      :node_parser,
      :diagnostics,
      keyword_init: true
    ) do
      def available?
        node_parser == true
      end
    end

    # Base error class for Bash::Merge
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    class Error < Ast::Merge::Error; end

    # Raised when a Bash script has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    #
    # @example Handling parse errors
    #   begin
    #     analysis = FileAnalysis.new(bash_content)
    #   rescue ParseError => e
    #     puts "Bash syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error}" }
    #   end
    class ParseError < Ast::Merge::ParseError
      # @param message [String, nil] Error message (auto-generated if nil)
      # @param content [String, nil] The Bash source that failed to parse
      # @param errors [Array] Parse errors from tree-sitter
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    # Raised when the template file has syntax errors.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class TemplateParseError < ParseError; end

    # Raised when the destination file has syntax errors.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class DestinationParseError < ParseError; end

    class CorruptionDetectedError < Error; end

    autoload :CommentTracker, 'bash/merge/comment_tracker'
    autoload :DebugLogger, 'bash/merge/debug_logger'
    autoload :Emitter, 'bash/merge/emitter'
    autoload :FreezeNode, 'bash/merge/freeze_node'
    autoload :FileAnalysis, 'bash/merge/file_analysis'
    autoload :MergeResult, 'bash/merge/merge_result'
    autoload :NodeWrapper, 'bash/merge/node_wrapper'
    autoload :SmartMerger, 'bash/merge/smart_merger'

    class << self
      def register_backend!
        BACKEND_REGISTRY.mutex.synchronize do
          return if BACKEND_REGISTRY.registered

          TreeHaver::BackendRegistry.register(TREE_SITTER_BACKEND)

          grammar_finder = TreeHaver::GrammarFinder.new(:bash)
          grammar_finder.register! if grammar_finder.available?

          BACKEND_REGISTRY.registered = true
        end
      end

      def available_bash_backends
        bash_backend_available_for_analysis?(TREE_SITTER_BACKEND.id) ? [TREE_SITTER_BACKEND] : []
      end

      def available?(source: "#!/usr/bin/env bash\necho hello\n")
        availability(source: source).available?
      end

      def availability(source: "#!/usr/bin/env bash\necho hello\n")
        diagnostics = []
        grammar_path = bash_grammar_path(diagnostics)
        Availability.new(
          grammar_path: grammar_path,
          node_parser: node_parser_available_for?(source, grammar_path, diagnostics),
          diagnostics: diagnostics
        )
      end

      private

      def bash_grammar_path(diagnostics)
        TreeHaver::GrammarFinder.new(:bash).find_library_path
      rescue TreeHaver::Error => e
        diagnostics << { kind: 'bash_grammar_unavailable', message: e.message }
        nil
      end

      def node_parser_available_for?(source, grammar_path, diagnostics)
        register_backend!
        parser = if grammar_path
                   TreeHaver.with_language_registration(
                     :bash,
                     :tree_sitter,
                     path: grammar_path,
                     symbol: TreeHaver::GrammarFinder.new(:bash).symbol_name
                   ) { TreeHaver.parser_for(:bash, backend_type: :tree_sitter) }
                 else
                   TreeHaver.parser_for(:bash, backend_type: :tree_sitter)
                 end
        tree = parser.parse(source)
        !tree.nil? && !tree.root_node.nil?
      rescue TreeHaver::Error => e
        diagnostics << { kind: 'bash_node_parser_unavailable', message: e.message }
        false
      rescue StandardError => e
        diagnostics << { kind: 'bash_node_parser_unavailable', message: e.message }
        false
      end

      def bash_backend_available_for_analysis?(backend_id)
        register_backend!

        if backend_id.to_s.empty?
          TreeHaver.parser_for(:bash, backend_type: :tree_sitter)
        else
          TreeHaver.with_backend(backend_id) { TreeHaver.parser_for(:bash, backend_type: :tree_sitter) }
        end
        true
      rescue TreeHaver::Error, ArgumentError
        false
      end
    end
  end
end

Bash::Merge.register_backend!

# Register with ast-merge's MergeGemRegistry for RSpec dependency tags
# Only register if MergeGemRegistry is loaded (i.e., in test environment)
if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :bash_merge,
    require_path: 'bash/merge',
    merger_class: 'Bash::Merge::SmartMerger',
    test_source: "#!/bin/bash\necho hello",
    category: :code
  )
end
