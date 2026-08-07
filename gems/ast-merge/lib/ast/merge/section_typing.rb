# frozen_string_literal: true

module Ast
  module Merge
    # AST-aware section typing for identifying logical sections within parsed trees.
    #
    # Unlike text-based splitting (see `Ast::Merge::Text::SectionSplitter`), SectionTyping
    # works with already-parsed AST nodes where the parser has already identified
    # structural boundaries. This eliminates the need for regex pattern matching.
    #
    # ## Use Cases
    #
    # - Identifying `appraise` blocks in Appraisals files
    # - Identifying `group` blocks in Gemfiles
    # - Identifying method definitions in Ruby files
    # - Any case where the AST parser provides structural information
    #
    # ## How It Works
    #
    # 1. **Classifier**: A callable that inspects an AST node and returns section info
    # 2. **Typed Node**: The node wrapped with its section classification
    # 3. **Merge Logic**: Section-aware merging based on classifications
    #
    # @example Defining an Appraisals block classifier
    #   AppraisalClassifier = ->(node) do
    #     return nil unless node.is_a?(Prism::CallNode)
    #     return nil unless node.name == :appraise
    #
    #     # Extract the block name from the first argument
    #     block_name = node.arguments&.arguments&.first
    #     return nil unless block_name.is_a?(Prism::StringNode)
    #
    #     {
    #       type: :appraise_block,
    #       name: block_name.unescaped,
    #       node: node
    #     }
    #   end
    #
    # @example Using the classifier
    #   typing = SectionTyping.new(classifier: AppraisalClassifier)
    #   sections = typing.classify_children(parsed_tree.statements)
    #
    #   sections.each do |section|
    #     puts "#{section.type}: #{section.name}"
    #   end
    #
    # @api public
    module SectionTyping
      # Represents a classified section from an AST node.
      #
      # Unlike `Text::Section` which is text-based, this wraps actual AST nodes
      # with their classification information.
      #
      # @api public
      TypedSection = Struct.new(
        # @return [Symbol] The section type (e.g., :appraise_block, :gem_group)
        :type,

        # @return [String, Symbol] Unique identifier for matching (e.g., block name)
        :name,

        # @return [Object] The original AST node
        :node,

        # @return [Hash, nil] Additional metadata from classification
        :metadata,
        keyword_init: true
      ) do
        # Normalize the section name for matching.
        #
        # @return [String] Normalized name
        def normalized_name
          return '' if name.nil?
          return name.to_s if name.is_a?(Symbol)

          name.to_s.strip.downcase
        end

        # Check if this is an unclassified/preamble section.
        #
        # @return [Boolean]
        def unclassified?
          %i[unclassified preamble].include?(type)
        end
      end

      # Base class for AST-aware section classifiers.
      #
      # Subclasses implement `classify(node)` to identify section boundaries
      # and extract section names from AST nodes.
      #
      # @abstract Subclass and implement {#classify}
      # @api public
      class Classifier
        # Classify a single AST node.
        #
        # @param node [Object] An AST node to classify
        # @return [TypedSection, nil] Section info if node starts a section, nil otherwise
        # @abstract Subclasses must implement this method
        def classify(node)
          raise NotImplementedError, "#{self.class}#classify must be implemented"
        end

        # Classify all children of a parent node.
        #
        # Iterates through child nodes and classifies each, grouping consecutive
        # unclassified nodes into preamble/interstitial sections.
        #
        # @param children [Array, Enumerable] Child nodes to classify
        # @return [Array<TypedSection>] Classified sections
        def classify_all(children)
          sections = []
          unclassified_buffer = []

          children.each do |child|
            if (section = classify(child))
              # Flush unclassified buffer as preamble/interstitial
              if unclassified_buffer.any?
                sections << build_unclassified_section(unclassified_buffer)
                unclassified_buffer = []
              end
              sections << section
            else
              unclassified_buffer << child
            end
          end

          # Flush remaining unclassified nodes
          sections << build_unclassified_section(unclassified_buffer) if unclassified_buffer.any?

          sections
        end

        # Check if a node can be classified by this classifier.
        #
        # @param node [Object] Node to check
        # @return [Boolean]
        def classifies?(node)
          !classify(node).nil?
        end

        private

        # Build a section for unclassified nodes.
        #
        # @param nodes [Array] Unclassified nodes
        # @return [TypedSection]
        def build_unclassified_section(nodes)
          TypedSection.new(
            type: :unclassified,
            name: :unclassified,
            node: nodes.length == 1 ? nodes.first : nodes,
            metadata: { node_count: nodes.length }
          )
        end
      end

      # A classifier that uses a callable (proc/lambda) for classification.
      #
      # This allows defining classifiers without creating a subclass.
      #
      # @example Using a lambda classifier
      #   classifier = CallableClassifier.new(->(node) {
      #     return nil unless node.respond_to?(:name) && node.name == :appraise
      #     TypedSection.new(type: :appraise, name: extract_name(node), node: node)
      #   })
      #
      class CallableClassifier < Classifier
        # @return [#call] The callable used for classification
        attr_reader :callable

        # Initialize with a callable.
        #
        # @param callable [#call] A callable that takes a node and returns TypedSection or nil
        def initialize(callable)
          super()
          @callable = callable
        end

        # Classify using the callable.
        #
        # @param node [Object] Node to classify
        # @return [TypedSection, nil]
        def classify(node)
          result = callable.call(node)
          return if result.nil?

          # Allow callable to return a Hash and convert to TypedSection
          if result.is_a?(Hash)
            TypedSection.new(**result)
          else
            result
          end
        end
      end

      # A composite classifier that tries multiple classifiers in order.
      #
      # Useful when a file may contain multiple types of sections
      # (e.g., both `appraise` blocks and `group` blocks).
      #
      # @example Combining classifiers
      #   composite = CompositeClassifier.new(
      #     AppraisalClassifier.new,
      #     GemGroupClassifier.new
      #   )
      #   sections = composite.classify_all(children)
      #
      class CompositeClassifier < Classifier
        # @return [Array<Classifier>] Classifiers to try in order
        attr_reader :classifiers

        # Initialize with multiple classifiers.
        #
        # @param classifiers [Array<Classifier>] Classifiers to try
        def initialize(*classifiers)
          super()
          @classifiers = classifiers.flatten
        end

        # Try each classifier until one matches.
        #
        # @param node [Object] Node to classify
        # @return [TypedSection, nil]
        def classify(node)
          classifiers.each do |classifier|
            if (section = classifier.classify(node))
              return section
            end
          end
          nil
        end
      end

      # Merge typed sections from template and destination.
      #
      # Similar to `Text::SectionSplitter#merge_section_lists` but works with
      class << self
        # TypedSection objects wrapping AST nodes.
        #
        # @param template_sections [Array<TypedSection>] Sections from template
        # @param dest_sections [Array<TypedSection>] Sections from destination
        # @param preference [Symbol, Hash] Merge preference (:template, :destination, or per-section Hash)
        # @param add_template_only [Boolean] Whether to add sections only in template
        # @return [Array<TypedSection>] Merged sections
        def merge_sections(template_sections, dest_sections, preference: :destination, add_template_only: false)
          dest_by_name = dest_sections.each_with_object({}) do |section, hash|
            key = section.normalized_name
            hash[key] = section unless section.unclassified?
          end

          merged = []
          seen_names = Set.new

          template_sections.each do |template_section|
            if template_section.unclassified?
              # Unclassified sections are typically kept as-is or merged specially
              merged << template_section if add_template_only
              next
            end

            key = template_section.normalized_name
            seen_names << key

            dest_section = dest_by_name[key]

            if dest_section
              # Section exists in both - choose based on preference
              section_pref = preference_for(template_section.name, preference)
              merged << (section_pref == :template ? template_section : dest_section)
            elsif add_template_only
              merged << template_section
            end
          end

          # Append destination-only sections
          dest_sections.each do |dest_section|
            next if dest_section.unclassified?

            key = dest_section.normalized_name
            next if seen_names.include?(key)

            merged << dest_section
          end

          merged
        end

        # Get preference for a specific section.
        #
        # @param section_name [String, Symbol] The section name
        # @param preference [Symbol, Hash] Overall preference
        # @return [Symbol] :template or :destination
        def preference_for(section_name, preference)
          return preference unless preference.is_a?(Hash)

          normalized = section_name.to_s.strip.downcase
          preference.each do |key, value|
            return value if key.to_s.strip.downcase == normalized
          end

          preference.fetch(:default, :destination)
        end
      end
    end
  end
end
