# frozen_string_literal: true

require 'ast/merge'
require 'service_actor'
require_relative 'crispr/version'

module Ast
  module Crispr
    PACKAGE_NAME = 'ast-crispr'

    class Error < StandardError
      attr_reader :code, :details

      def initialize(message, code: 'ast_crispr_error', details: {}, **options)
        @code = code
        @details = details.merge(options)
        super(message)
      end
    end

    class Limit
      Constraint = Struct.new(:description, :predicate, keyword_init: true)

      class << self
        def coerce(limit = nil, **options)
          limit.is_a?(self) ? limit : new(limit, **options)
        end
      end

      attr_reader :constraints

      def initialize(limit = nil, **options)
        @constraints = normalize(limit, **options)
      end

      def allows?(count)
        constraints.all? { |constraint| constraint.predicate.call(count) }
      end

      def describe
        constraints.map(&:description).join(' and ')
      end

      private

      def normalize(limit, **options)
        spec = limit.nil? ? options.fetch(:default, { exactly: 1 }) : limit

        case spec
        when Limit
          spec.constraints.dup
        when Hash
          normalize_hash(spec)
        when Array
          spec.flat_map { |entry| normalize(entry) }
        when String
          [constraint_for_operator(spec)]
        else
          raise Error.new('Unsupported CRISPR limit specification', code: 'ast_crispr_limit_unsupported',
                                                                    details: { spec: spec.inspect, limit: spec.inspect })
        end
      end

      def normalize_hash(spec)
        constraints = []
        if spec.key?(:exactly)
          constraints << constraint("== #{spec.fetch(:exactly)}") do |count|
            count == spec.fetch(:exactly)
          end
        end
        if spec.key?(:at_most)
          constraints << constraint("<= #{spec.fetch(:at_most)}") do |count|
            count <= spec.fetch(:at_most)
          end
        end
        if spec.key?(:at_least)
          constraints << constraint(">= #{spec.fetch(:at_least)}") do |count|
            count >= spec.fetch(:at_least)
          end
        end
        if spec.key?(:between)
          constraints << constraint("between #{spec.fetch(:between)}") do |count|
            spec.fetch(:between).cover?(count)
          end
        end
        constraints << constraint('<= 1') { |count| count <= 1 } if spec[:none_or_one]
        if constraints.empty?
          raise Error.new('CRISPR limit must define at least one constraint', code: 'ast_crispr_limit_empty',
                                                                              details: { spec: spec.inspect, limit: spec.inspect })
        end

        constraints
      end

      def constraint_for_operator(spec)
        match = /\A(==|!=|<=|>=|<|>)\s*(\d+)\z/.match(spec.strip)
        unless match
          raise Error.new('Invalid CRISPR limit expression', code: 'ast_crispr_limit_invalid_expression',
                                                             details: { spec: spec.inspect, limit: spec.inspect })
        end

        operator = match[1]
        value = match[2].to_i
        predicate = lambda do |count|
          case operator
          when '==' then count == value
          when '!=' then count != value
          when '<=' then count <= value
          when '>=' then count >= value
          when '<' then count < value
          when '>' then count > value
          else false
          end
        end
        constraint("#{operator} #{value}", &predicate)
      end

      def constraint(description, &predicate)
        Constraint.new(description: description, predicate: predicate)
      end
    end

    class Match
      attr_reader :target, :node, :start_line, :end_line, :metadata

      def initialize(start_line:, end_line:, target: nil, node: nil, metadata: {}, **options)
        @target = target
        @node = node
        @start_line = Integer(start_line)
        @end_line = Integer(end_line)
        @metadata = metadata.merge(options)
        return unless @end_line < @start_line

        raise Error.new('CRISPR match end_line must be >= start_line',
                        details: { start_line: @start_line, end_line: @end_line })
      end

      def with_target(target)
        return self if self.target.equal?(target)

        self.class.new(
          target: target,
          node: node,
          start_line: start_line,
          end_line: end_line,
          metadata: metadata
        )
      end

      def line_range
        start_line..end_line
      end

      def slice_from(content)
        lines = content.to_s.lines
        return '' if lines.empty?

        lines[(start_line - 1)..(end_line - 1)].to_a.join
      end

      def match_profile
        MatchProfile.new(
          start_boundary: metadata.fetch(:start_boundary, :owner_start),
          end_boundary: metadata.fetch(:end_boundary, :owner_end),
          payload_kind: metadata.fetch(:payload_kind, :structural_owner_body),
          metadata: metadata
        )
      end
    end

    class MatchProfile
      KNOWN_START_BOUNDARIES = {
        owner_start: {
          family: :structural_owner,
          description: "Span starts at the structural owner's boundary"
        },
        comment_region_start: {
          family: :comment_anchor,
          description: 'Span starts at an owning comment-region boundary'
        }
      }.freeze
      KNOWN_END_BOUNDARIES = {
        owner_end: {
          family: :structural_owner,
          description: "Span ends at the structural owner's boundary"
        },
        owner_end_plus_trailing_gap: {
          family: :gap_extension,
          description: 'Span extends past the owner boundary to include trailing blank-line gap'
        }
      }.freeze
      KNOWN_PAYLOAD_KINDS = {
        structural_owner_body: {
          family: :owner_body,
          description: "Span represents a structural owner's body"
        },
        comment_owned_body: {
          family: :comment_owned,
          description: 'Span represents a structural owner body selected through an owning comment marker'
        },
        section_branch: {
          family: :section_branch,
          description: 'Span represents a heading-owned section branch payload'
        }
      }.freeze

      attr_reader :start_boundary, :end_boundary, :payload_kind, :metadata

      def initialize(start_boundary:, end_boundary:, payload_kind:, metadata: {}, **options)
        @start_boundary = normalize_start_boundary(start_boundary)
        @end_boundary = normalize_end_boundary(end_boundary)
        @payload_kind = normalize_payload_kind(payload_kind)
        @metadata = metadata.merge(options).freeze
      end

      def start_boundary_metadata
        KNOWN_START_BOUNDARIES[start_boundary]&.dup&.freeze
      end

      def end_boundary_metadata
        KNOWN_END_BOUNDARIES[end_boundary]&.dup&.freeze
      end

      def start_boundary_family
        start_boundary_metadata&.fetch(:family, nil)
      end

      def end_boundary_family
        end_boundary_metadata&.fetch(:family, nil)
      end

      def known_start_boundary?
        KNOWN_START_BOUNDARIES.key?(start_boundary)
      end

      def known_end_boundary?
        KNOWN_END_BOUNDARIES.key?(end_boundary)
      end

      def payload_kind_metadata
        KNOWN_PAYLOAD_KINDS[payload_kind]&.dup&.freeze
      end

      def payload_family
        payload_kind_metadata&.fetch(:family, nil)
      end

      def known_payload_kind?
        KNOWN_PAYLOAD_KINDS.key?(payload_kind)
      end

      def comment_anchored?
        start_boundary == :comment_region_start
      end

      def trailing_gap_extended?
        end_boundary == :owner_end_plus_trailing_gap
      end

      def structural_owner_body?
        payload_kind == :structural_owner_body
      end

      def comment_owned_body?
        payload_kind == :comment_owned_body
      end

      def section_branch?
        payload_kind == :section_branch
      end

      def to_h
        {
          start_boundary: start_boundary,
          start_boundary_family: start_boundary_family,
          known_start_boundary: known_start_boundary?,
          end_boundary: end_boundary,
          end_boundary_family: end_boundary_family,
          known_end_boundary: known_end_boundary?,
          payload_kind: payload_kind,
          payload_family: payload_family,
          known_payload_kind: known_payload_kind?,
          comment_anchored: comment_anchored?,
          trailing_gap_extended: trailing_gap_extended?,
          metadata: metadata
        }
      end

      private

      def normalize_start_boundary(value)
        value&.to_sym
      end

      def normalize_end_boundary(value)
        value&.to_sym
      end

      def normalize_payload_kind(value)
        value&.to_sym
      end
    end

    class DestinationProfile
      KNOWN_RESOLUTION_KINDS = {
        append_fallback: {
          family: :append,
          description: 'Insertion fell back to appending at the end of the document'
        },
        anchor_after_statement: {
          family: :anchored,
          description: 'Insertion resolved a statement anchor and spliced after it'
        }
      }.freeze
      KNOWN_RESOLUTION_SOURCES = {
        none: {
          family: :implicit,
          description: 'No destination object was provided'
        },
        callable: {
          family: :callable,
          description: 'Destination was resolved from a callable'
        },
        selector: {
          family: :selector,
          description: 'Destination was resolved from an owner selector anchor'
        }
      }.freeze
      KNOWN_ANCHOR_BOUNDARIES = {
        none: {
          family: :none,
          description: 'No anchor boundary was used'
        },
        statement_end_plus_following_gap: {
          family: :gap_preserving_statement,
          description: 'Insertion anchored after a statement and preserved its following blank-line gap'
        }
      }.freeze

      attr_reader :resolution_kind, :resolution_source, :anchor_boundary, :metadata

      def initialize(resolution_kind:, resolution_source:, anchor_boundary:, used_if_missing: false, metadata: {},
                     **options)
        @resolution_kind = normalize_resolution_kind(resolution_kind)
        @resolution_source = normalize_resolution_source(resolution_source)
        @anchor_boundary = normalize_anchor_boundary(anchor_boundary)
        @used_if_missing = used_if_missing ? true : false
        @metadata = metadata.merge(options).freeze
      end

      def resolution_kind_metadata
        KNOWN_RESOLUTION_KINDS[resolution_kind]&.dup&.freeze
      end

      def resolution_source_metadata
        KNOWN_RESOLUTION_SOURCES[resolution_source]&.dup&.freeze
      end

      def anchor_boundary_metadata
        KNOWN_ANCHOR_BOUNDARIES[anchor_boundary]&.dup&.freeze
      end

      def resolution_family
        resolution_kind_metadata&.fetch(:family, nil)
      end

      def resolution_source_family
        resolution_source_metadata&.fetch(:family, nil)
      end

      def anchor_boundary_family
        anchor_boundary_metadata&.fetch(:family, nil)
      end

      def known_resolution_kind?
        KNOWN_RESOLUTION_KINDS.key?(resolution_kind)
      end

      def known_resolution_source?
        KNOWN_RESOLUTION_SOURCES.key?(resolution_source)
      end

      def known_anchor_boundary?
        KNOWN_ANCHOR_BOUNDARIES.key?(anchor_boundary)
      end

      def append_fallback?
        resolution_kind == :append_fallback
      end

      def anchored?
        resolution_kind == :anchor_after_statement
      end

      def callable_resolved?
        resolution_source == :callable
      end

      def selector_resolved?
        resolution_source == :selector
      end

      def used_if_missing?
        @used_if_missing
      end

      def to_h
        {
          resolution_kind: resolution_kind,
          resolution_family: resolution_family,
          known_resolution_kind: known_resolution_kind?,
          resolution_source: resolution_source,
          resolution_source_family: resolution_source_family,
          known_resolution_source: known_resolution_source?,
          anchor_boundary: anchor_boundary,
          anchor_boundary_family: anchor_boundary_family,
          known_anchor_boundary: known_anchor_boundary?,
          used_if_missing: used_if_missing?,
          append_fallback: append_fallback?,
          anchored: anchored?,
          metadata: metadata
        }
      end

      private

      def normalize_resolution_kind(value)
        value&.to_sym
      end

      def normalize_resolution_source(value)
        value&.to_sym
      end

      def normalize_anchor_boundary(value)
        value&.to_sym
      end
    end

    class DestinationResolution
      attr_reader :mode, :anchor, :destination_profile

      def initialize(mode:, anchor:, destination_profile:)
        @mode = mode&.to_sym
        @anchor = anchor
        @destination_profile = destination_profile
      end

      def append_fallback?
        mode == :append
      end
    end

    class StructureProfile
      attr_reader :owner_scope, :owner_selector, :supported_comment_regions, :metadata

      def initialize(owner_scope:, owner_selector:, supported_comment_regions: [], metadata: {}, **options)
        @owner_scope = owner_scope&.to_sym
        @owner_selector = owner_selector&.to_sym
        @supported_comment_regions = Array(supported_comment_regions).map(&:to_sym).freeze
        @metadata = metadata.merge(options).freeze
      end

      def owner_selector_metadata
        Ast::Merge::Ruleset::ProfileVocabulary.owner_selector_metadata(owner_selector)
      end

      def owner_selector_family
        owner_selector_metadata&.fetch(:family, nil)
      end

      def known_owner_selector?
        Ast::Merge::Ruleset::ProfileVocabulary.known_owner_selector?(owner_selector)
      end

      def supports_comment_region?(region)
        supported_comment_regions.include?(region.to_sym)
      end

      def to_h
        {
          owner_scope: owner_scope,
          owner_selector: owner_selector,
          owner_selector_family: owner_selector_family,
          known_owner_selector: known_owner_selector?,
          supported_comment_regions: supported_comment_regions,
          metadata: metadata
        }
      end
    end

    class SelectionProfile
      KNOWN_SELECTION_INTENTS = {
        predicate_filter: {
          family: :predicate,
          description: 'Predicate-based structural owner filtering'
        },
        comment_anchored_owner: {
          family: :comment_anchor,
          description: 'Comment-region marker anchored owner selection'
        },
        section_branch: {
          family: :section_branch,
          description: 'Heading-owned section branch selection'
        }
      }.freeze

      attr_reader :owner_scope, :selector_kind, :selection_intent, :comment_region, :include_trailing_gap,
                  :structure_profile, :metadata

      def initialize(owner_scope:, selector_kind:, selection_intent:, structure_profile: nil, owner_selector: nil,
                     comment_region: nil,
                     include_trailing_gap: false, metadata: {}, **options)
        @owner_scope = owner_scope&.to_sym
        @selector_kind = selector_kind&.to_sym
        @selection_intent = selection_intent&.to_sym
        @comment_region = comment_region&.to_sym
        @include_trailing_gap = include_trailing_gap ? true : false
        @structure_profile = structure_profile || StructureProfile.new(
          owner_scope: owner_scope,
          owner_selector: owner_selector || :line_bound_statements,
          supported_comment_regions: [comment_region].compact
        )
        @metadata = metadata.merge(options).freeze
      end

      def selection_intent_metadata
        KNOWN_SELECTION_INTENTS[selection_intent]&.dup&.freeze
      end

      def owner_selector
        structure_profile.owner_selector
      end

      def owner_selector_family
        structure_profile.owner_selector_family
      end

      def selection_intent_family
        selection_intent_metadata&.fetch(:family, nil)
      end

      def known_selection_intent?
        KNOWN_SELECTION_INTENTS.key?(selection_intent)
      end

      def comment_anchored?
        !comment_region.nil?
      end

      def to_h
        {
          owner_scope: owner_scope,
          owner_selector: structure_profile.owner_selector,
          owner_selector_family: structure_profile.owner_selector_family,
          selector_kind: selector_kind,
          selection_intent: selection_intent,
          selection_intent_family: selection_intent_family,
          known_selection_intent: known_selection_intent?,
          comment_region: comment_region,
          include_trailing_gap: include_trailing_gap,
          comment_anchored: comment_anchored?,
          metadata: metadata
        }
      end
    end

    class OperationProfile
      KNOWN_OPERATION_KINDS = {
        replace: {
          family: :rewrite,
          description: 'Replace selected content with explicit replacement text'
        },
        merge_replace: {
          family: :rewrite,
          description: 'Replace selected content with the result of a merge-gem slice merge'
        },
        delete: {
          family: :removal,
          description: 'Delete selected content without inserting replacement text'
        },
        delete_batch: {
          family: :removal,
          description: 'Delete content selected by multiple structural selectors in one source pass'
        },
        insert: {
          family: :insertion,
          description: 'Insert explicit text at a destination anchor or append fallback'
        },
        move: {
          family: :relocation,
          description: 'Relocate selected content or explicit replacement text to a destination anchor'
        }
      }.freeze
      KNOWN_REQUIREMENTS = %i[none optional required].freeze
      KNOWN_REPLACEMENT_SOURCES = %i[none explicit_text captured_text_or_explicit merge_template_text].freeze

      attr_reader :operation_kind, :source_requirement, :destination_requirement, :replacement_source, :metadata

      def initialize(operation_kind:, source_requirement:, destination_requirement:, replacement_source:,
                     captures_source_text: false, supports_if_missing: false, metadata: {}, **options)
        @operation_kind = operation_kind&.to_sym
        @source_requirement = normalize_requirement(source_requirement, :source_requirement)
        @destination_requirement = normalize_requirement(destination_requirement, :destination_requirement)
        @replacement_source = normalize_replacement_source(replacement_source)
        @captures_source_text = captures_source_text ? true : false
        @supports_if_missing = supports_if_missing ? true : false
        @metadata = metadata.merge(options).freeze
      end

      def operation_kind_metadata
        KNOWN_OPERATION_KINDS[operation_kind]&.dup&.freeze
      end

      def operation_family
        operation_kind_metadata&.fetch(:family, nil)
      end

      def known_operation_kind?
        KNOWN_OPERATION_KINDS.key?(operation_kind)
      end

      def selects_source?
        source_requirement != :none
      end

      def requires_source?
        source_requirement == :required
      end

      def supports_destination?
        destination_requirement != :none
      end

      def requires_destination?
        destination_requirement == :required
      end

      def captures_source_text?
        @captures_source_text
      end

      def supports_if_missing?
        @supports_if_missing
      end

      def explicit_replacement?
        replacement_source == :explicit_text
      end

      def may_reuse_captured_text?
        replacement_source == :captured_text_or_explicit
      end

      def to_h
        {
          operation_kind: operation_kind,
          operation_family: operation_family,
          known_operation_kind: known_operation_kind?,
          source_requirement: source_requirement,
          destination_requirement: destination_requirement,
          replacement_source: replacement_source,
          captures_source_text: captures_source_text?,
          supports_if_missing: supports_if_missing?,
          metadata: metadata
        }
      end

      private

      def normalize_requirement(value, _field_name)
        value&.to_sym
      end

      def normalize_replacement_source(value)
        value&.to_sym
      end
    end

    module Adapters
      class Null
        def read_ast(document)
          raise Error.new('A CRISPR document adapter is required', details: { source_label: document.source_label })
        end

        def structural_owners(document, owner_scope: :shared_default)
          raise Error.new('A CRISPR document adapter is required',
                          details: { source_label: document.source_label, owner_scope: owner_scope })
        end

        def comment_regions_for(document, owner, region: :leading, owner_scope: :shared_default)
          raise Error.new(
            'A CRISPR document adapter is required',
            details: { source_label: document.source_label, owner: owner.inspect, region: region,
                       owner_scope: owner_scope }
          )
        end

        def comment_region_text(document, comment_region)
          raise Error.new('A CRISPR document adapter is required',
                          details: { source_label: document.source_label, comment_region: comment_region.inspect })
        end

        def structure_profile(owner_scope: :shared_default)
          StructureProfile.new(
            owner_scope: owner_scope,
            owner_selector: owner_scope,
            metadata: { source: :null_adapter }
          )
        end
      end
    end

    class DocumentContext
      attr_reader :content, :source_label, :metadata, :adapter

      def initialize(content:, source_label: 'source', adapter: Adapters::Null.new, metadata: {}, **options)
        @content = content.to_s
        @source_label = source_label
        @adapter = adapter
        @metadata = metadata.merge(options)
      end

      def lines
        @lines ||= content.lines
      end

      def ast
        @ast ||= adapter.read_ast(self)
      end

      def structural_owners(owner_scope: :shared_default)
        adapter.structural_owners(self, owner_scope: owner_scope)
      end

      def comment_regions_for(owner, region: :leading, owner_scope: :shared_default)
        adapter.comment_regions_for(self, owner, region: region, owner_scope: owner_scope)
      end

      def comment_region_text(comment_region)
        adapter.comment_region_text(self, comment_region)
      end

      def structure_profile(owner_scope: :shared_default)
        if adapter.respond_to?(:structure_profile)
          adapter.structure_profile(owner_scope: owner_scope)
        else
          StructureProfile.new(
            owner_scope: owner_scope,
            owner_selector: owner_scope,
            metadata: { source: :document_context_default }
          )
        end
      end

      def location_slice(location)
        content.byteslice(location.start_offset...location.end_offset).to_s
      end

      def expand_following_gap(line_number)
        last_line = line_number
        last_line += 1 while line_blank?(last_line + 1)
        last_line
      end

      def line_blank?(line_number)
        line = lines[line_number - 1]
        !line.nil? && line.strip.empty?
      end
    end

    Context = DocumentContext

    class OwnerSelector
      attr_reader :id, :locate, :owned_span, :anchor, :limit, :metadata

      def initialize(id:, locate:, owned_span: nil, anchor: nil, limit: nil, metadata: {}, **options)
        @id = id
        @locate = locate
        @owned_span = owned_span
        @anchor = anchor
        @limit = Limit.coerce(limit, default: { exactly: 1 })
        @metadata = metadata.merge(options)
      end

      def locate_matches(context)
        Array(invoke(locate, context)).flatten.compact.map { |candidate| coerce_match(candidate) }
      end

      def resolve_owned_match(context, match)
        candidate = owned_span ? invoke(owned_span, context, match) : match
        coerce_match(candidate).with_target(self)
      end

      def resolve_anchor(context, match = nil)
        return unless anchor

        invoke(anchor, context, match)
      end

      def owner_scope
        metadata.fetch(:owner_scope, :shared_default)
      end

      def structure_profile(context)
        context.structure_profile(owner_scope: owner_scope)
      end

      def selector_kind
        metadata[:selector_kind]&.to_sym
      end

      def selection_intent
        metadata[:selection_intent]&.to_sym
      end

      def comment_region
        metadata[:comment_region]&.to_sym
      end

      def include_trailing_gap?
        metadata[:include_trailing_gap] ? true : false
      end

      def selection_profile(context)
        SelectionProfile.new(
          owner_scope: owner_scope,
          selector_kind: selector_kind,
          selection_intent: selection_intent,
          comment_region: comment_region,
          include_trailing_gap: include_trailing_gap?,
          structure_profile: structure_profile(context),
          metadata: metadata
        )
      end

      private

      def coerce_match(candidate)
        case candidate
        when Match
          candidate.with_target(self)
        when Hash
          Match.new(target: self, **candidate)
        else
          unless candidate.respond_to?(:location) && candidate.location
            raise Error.new('Unsupported CRISPR match result', details: { target: id, candidate: candidate.inspect })
          end

          Match.new(
            target: self,
            node: candidate,
            start_line: candidate.location.start_line,
            end_line: candidate.location.end_line
          )

        end
      end

      def invoke(callable, *args)
        return callable.call(*args) if callable.arity.negative?

        callable.call(*args.first(callable.arity))
      end
    end

    Target = OwnerSelector

    module Selectors
      module_function

      def owner_filter(id:, limit: nil, owner_scope: :shared_default, include_trailing_gap: false, adapter: nil,
                       metadata: {}, &block)
        raise ArgumentError, 'owner_filter requires a block' unless block

        OwnerSelector.new(
          id: id,
          limit: limit,
          metadata: metadata_for(
            metadata,
            adapter,
            owner_scope: owner_scope,
            selector_kind: :owner_filter,
            selection_intent: :predicate_filter,
            include_trailing_gap: include_trailing_gap
          ),
          locate: lambda do |context|
            context.structural_owners(owner_scope: owner_scope).filter_map do |owner|
              next unless owner.respond_to?(:location) && owner.location

              match = block.call(context, owner)
              next unless match

              if match.is_a?(Match)
                match
              else
                end_line = owner.location.end_line
                end_line = context.expand_following_gap(end_line) if include_trailing_gap
                base_metadata = {
                  start_boundary: :owner_start,
                  end_boundary: (include_trailing_gap ? :owner_end_plus_trailing_gap : :owner_end),
                  payload_kind: :structural_owner_body
                }
                Match.new(
                  node: owner,
                  start_line: owner.location.start_line,
                  end_line: end_line,
                  metadata: base_metadata.merge(match == true ? {} : match.to_h)
                )
              end
            end
          end
        )
      end

      def comment_region_owned_owner(marker:, id: nil, limit: nil, owner_scope: :shared_default,
                                     comment_region: :leading, include_trailing_gap: true, adapter: nil, metadata: {}, **options)
        marker_text = marker.to_s.rstrip
        OwnerSelector.new(
          id: id || marker_text,
          limit: limit,
          metadata: metadata_for(
            metadata,
            adapter,
            owner_scope: owner_scope,
            comment_region: comment_region,
            selector_kind: :comment_region_owned_owner,
            selection_intent: :comment_anchored_owner,
            include_trailing_gap: include_trailing_gap
          ),
          locate: lambda do |context|
            context.structural_owners(owner_scope: owner_scope).filter_map do |owner|
              marker_region = context.comment_regions_for(owner, region: comment_region,
                                                                 owner_scope: owner_scope).find do |region|
                context.comment_region_text(region) == marker_text
              end
              next unless marker_region

              end_line = owner.location.end_line
              end_line = context.expand_following_gap(end_line) if include_trailing_gap
              Match.new(
                node: owner,
                start_line: marker_region.location.start_line,
                end_line: end_line,
                metadata: {
                  start_boundary: :comment_region_start,
                  end_boundary: (include_trailing_gap ? :owner_end_plus_trailing_gap : :owner_end),
                  payload_kind: :comment_owned_body,
                  marker: marker_text,
                  owner_scope: owner_scope,
                  comment_region: comment_region,
                  region: marker_region
                }
              )
            end
          end,
          **options
        )
      end

      def line_block(start_line_text:, end_line_text:, id: nil, limit: nil, include_trailing_gap: false, metadata: {},
                     **options)
        OwnerSelector.new(
          id: id || "line_block_#{start_line_text}",
          limit: limit,
          metadata: metadata_for(
            metadata,
            nil,
            owner_scope: :text_lines,
            selector_kind: :line_block,
            selection_intent: :line_marker_block,
            include_trailing_gap: include_trailing_gap
          ).merge(options),
          locate: lambda do |context|
            lines = context.content.to_s.lines
            open_lines = lines.each_with_index.filter_map do |line, index|
              index + 1 if line.chomp == start_line_text.to_s
            end
            close_lines = lines.each_with_index.filter_map do |line, index|
              index + 1 if line.chomp == end_line_text.to_s
            end
            start_line = open_lines.first
            end_line = close_lines.reverse.find { |candidate| start_line && candidate >= start_line }
            next [] unless start_line && end_line

            end_line = context.expand_following_gap(end_line) if include_trailing_gap
            [
              Match.new(
                start_line: start_line,
                end_line: end_line,
                metadata: {
                  start_boundary: :owner_start,
                  end_boundary: (include_trailing_gap ? :owner_end_plus_trailing_gap : :owner_end),
                  payload_kind: :structural_owner_body,
                  start_line_text: start_line_text,
                  end_line_text: end_line_text
                }
              )
            ]
          end
        )
      end

      def metadata_for(metadata, adapter, **options)
        payload = metadata.merge(options)
        adapter ? payload.merge(adapter: adapter) : payload
      end
      private_class_method :metadata_for
    end

    Targets = Selectors

    module OperationSupport
      private

      def normalize_matches(target, context)
        matches = target.locate_matches(context)
        enforce_limit!(target, matches.size)
        matches.map { |match| target.resolve_owned_match(context, match) }
      end

      def context_for(content:, source_label:, target: nil)
        adapter = target&.metadata&.[](:adapter)
        DocumentContext.new(content: content, source_label: source_label, adapter: adapter || Adapters::Null.new)
      end

      def context_for_targets(content:, source_label:, targets:)
        first_target = Array(targets).first
        context_for(content: content, source_label: source_label, target: first_target)
      end

      def enforce_limit!(target, count)
        return if target.limit.allows?(count)

        raise Error.new(
          "CRISPR target #{target.id.inspect} matched #{count} node(s); expected #{target.limit.describe}",
          details: { target: target.id, count: count, limit: target.limit.describe }
        )
      end

      def replace_line_ranges(source, matches, replacement)
        assert_non_overlapping!(matches)
        plans = matches.map do |match|
          Ast::Merge::StructuralEdit::SplicePlan.new(
            source: source,
            replace_start_line: match.start_line,
            replace_end_line: match.end_line,
            replacement: replacement
          )
        end
        Ast::Merge::StructuralEdit::PlanSet.new(source: source, plans: plans).merged_content
      end

      def merge_replace_line_ranges(source, matches, replacement, merger_class:, merger_options:)
        assert_non_overlapping!(matches)
        merge_results = []
        plans = matches.map do |match|
          destination_slice = match.slice_from(source)
          merge_result = merge_replacement_slice(
            replacement.to_s,
            destination_slice,
            merger_class: merger_class,
            merger_options: merger_options
          )
          merge_results << merge_result

          Ast::Merge::StructuralEdit::SplicePlan.new(
            source: source,
            replace_start_line: match.start_line,
            replace_end_line: match.end_line,
            replacement: merge_result.fetch(:content),
            metadata: { merge_result: merge_result, mode: :merge_replace }
          )
        end

        [
          Ast::Merge::StructuralEdit::PlanSet.new(source: source, plans: plans).merged_content,
          merge_results
        ]
      end

      def merge_replacement_slice(template_slice, destination_slice, merger_class:, merger_options:)
        merger = merger_class.new(template_slice, destination_slice, **merger_options)
        result = merger.respond_to?(:merge_result) ? merger.merge_result : merger.merge
        content = merge_result_content(result)

        {
          content: content,
          result: result,
          stats: merge_result_stats(result, merger),
          conflicts: merge_result_conflicts(result),
          unresolved: merge_result_unresolved?(result)
        }
      end

      def merge_result_content(result)
        return result if result.is_a?(String)
        return result.output if result.respond_to?(:output)
        return result.content if result.respond_to?(:content) && result.content.is_a?(String)

        result.to_s
      end

      def merge_result_stats(result, merger)
        if result.respond_to?(:stats)
          stats = result.stats
          return stats unless stats.respond_to?(:empty?) && stats.empty?
        end
        return merger.stats if merger.respond_to?(:stats)

        {}
      end

      def merge_result_conflicts(result)
        return result.conflicts if result.respond_to?(:conflicts)

        []
      end

      def merge_result_unresolved?(result)
        return result.unresolved? if result.respond_to?(:unresolved?)
        return result.review_required? if result.respond_to?(:review_required?)

        false
      end

      def assert_non_overlapping!(matches)
        ranges = matches.map(&:line_range).sort_by(&:begin)
        ranges.each_cons(2) do |left, right|
          next if left.end < right.begin

          raise Error.new('CRISPR target spans overlap', details: { left: left, right: right })
        end
      end

      def insertion_from(content, destination, if_missing:, source_label:)
        if destination.nil? && if_missing == :append
          return append_destination_resolution(source: :none,
                                               used_if_missing: true)
        end
        if destination.nil?
          raise Error.new('Missing CRISPR insertion destination',
                          details: { source_label: source_label })
        end

        target = destination if destination.is_a?(OwnerSelector)
        context = context_for(content: content, source_label: source_label, target: target)
        anchor, resolution_source = if destination.is_a?(OwnerSelector)
                                      matches = normalize_matches(destination, context)
                                      if matches.empty?
                                        raise Error.new('CRISPR destination target cannot be empty',
                                                        details: { target: destination.id })
                                      end

                                      [destination.resolve_anchor(context, matches.first), :selector]
                                    else
                                      [invoke_callable(destination, context), :callable]
                                    end

        if anchor.nil?
          if if_missing == :append
            return append_destination_resolution(source: resolution_source,
                                                 used_if_missing: true)
          end

          raise Error.new('Unable to resolve CRISPR insertion destination', details: { source_label: source_label })
        end

        anchored_destination_resolution(anchor, source: resolution_source)
      end

      def insert_text(content, text, destination:, if_missing:, source_label:)
        resolution = insertion_from(content, destination, if_missing: if_missing, source_label: source_label)
        return [append_to_end_of_file(content, text), resolution.destination_profile] if resolution.append_fallback?

        [splice_after_anchor(content, resolution.anchor, text), resolution.destination_profile]
      end

      def splice_after_anchor(content, injection_point, text)
        lines = content.lines
        start_line = statement_start_line(injection_point.anchor)
        end_line = expand_following_blank_lines(lines, statement_end_line(injection_point.anchor))
        raise Error.new('CRISPR insertion anchor is missing statement location') unless start_line && end_line

        replacement = lines[(start_line - 1)..(end_line - 1)].join + text.to_s.rstrip + "\n\n"
        Ast::Merge::StructuralEdit::PlanSet.new(
          source: content,
          plans: [
            Ast::Merge::StructuralEdit::SplicePlan.new(
              source: content,
              replace_start_line: start_line,
              replace_end_line: end_line,
              replacement: replacement
            )
          ]
        ).merged_content
      end

      def statement_start_line(statement)
        statement.start_line || statement.node&.location&.start_line
      end

      def statement_end_line(statement)
        statement.end_line || statement.node&.location&.end_line
      end

      def expand_following_blank_lines(lines, line_number)
        last_line = line_number
        last_line += 1 while !lines[last_line].nil? && lines[last_line].strip.empty?
        last_line
      end

      def append_to_end_of_file(content, text)
        body = content.rstrip
        return text.to_s if body.empty?

        body + "\n\n" + text.to_s
      end

      def capture_text(content, matches)
        matches.map { |match| match.slice_from(content).rstrip }.reject(&:empty?).join("\n\n")
      end

      def append_destination_resolution(source:, used_if_missing:)
        DestinationResolution.new(
          mode: :append,
          anchor: nil,
          destination_profile: DestinationProfile.new(
            resolution_kind: :append_fallback,
            resolution_source: source,
            anchor_boundary: :none,
            used_if_missing: used_if_missing
          )
        )
      end

      def anchored_destination_resolution(anchor, source:)
        DestinationResolution.new(
          mode: :anchor,
          anchor: anchor,
          destination_profile: DestinationProfile.new(
            resolution_kind: :anchor_after_statement,
            resolution_source: source,
            anchor_boundary: :statement_end_plus_following_gap,
            used_if_missing: false
          )
        )
      end

      def crispr_fail!(error)
        fail!(error: error.message, details: error.details)
      end

      def invoke_callable(callable, *args)
        return callable.call(*args) if callable.arity.negative?

        callable.call(*args.first(callable.arity))
      end
    end

    module OperationProfilable
      def self.included(base)
        base.extend(ClassMethods)
      end

      def operation_profile
        self.class.operation_profile
      end

      module ClassMethods
        def declare_operation_profile(**attributes)
          @operation_profile = OperationProfile.new(**attributes)
        end

        def operation_profile
          @operation_profile || raise(Error.new('CRISPR operation profile is not declared',
                                                details: { operation_class: name }))
        end
      end
    end

    class MergeReplace < Actor
      include OperationSupport
      include OperationProfilable

      declare_operation_profile(
        operation_kind: :merge_replace,
        source_requirement: :required,
        destination_requirement: :none,
        replacement_source: :merge_template_text,
        captures_source_text: true,
        supports_if_missing: false
      )

      input :content, type: String
      input :target, type: OwnerSelector
      input :replacement, type: String
      input :merger_class
      input :merger_options, default: -> { {} }
      input :source_label, type: String, default: 'source'

      output :updated_content
      output :matches, default: -> { [] }
      output :match_count, type: Integer, default: 0
      output :changed, default: false
      output :captured_text, allow_nil: true, default: nil
      output :merge_results, default: -> { [] }
      output :operation_profile

      def call
        self.operation_profile = self.class.operation_profile
        context = context_for(content: content, source_label: source_label, target: target)
        self.matches = normalize_matches(target, context)
        self.match_count = matches.size
        self.captured_text = capture_text(content, matches)
        if matches.empty?
          self.updated_content = content
          self.changed = false
          return
        end

        self.updated_content, self.merge_results = merge_replace_line_ranges(
          content,
          matches,
          replacement,
          merger_class: merger_class,
          merger_options: merger_options.to_h
        )
        self.changed = updated_content != content
      rescue Error => e
        crispr_fail!(e)
      end
    end

    class Replace < Actor
      include OperationSupport
      include OperationProfilable

      declare_operation_profile(
        operation_kind: :replace,
        source_requirement: :required,
        destination_requirement: :none,
        replacement_source: :explicit_text,
        captures_source_text: true,
        supports_if_missing: false
      )

      input :content, type: String
      input :target, type: OwnerSelector
      input :replacement, allow_nil: true, default: nil
      input :source_label, type: String, default: 'source'

      output :updated_content
      output :matches, default: -> { [] }
      output :match_count, type: Integer, default: 0
      output :changed, default: false
      output :captured_text, allow_nil: true, default: nil
      output :operation_profile

      def call
        self.operation_profile = self.class.operation_profile
        context = context_for(content: content, source_label: source_label, target: target)
        self.matches = normalize_matches(target, context)
        self.match_count = matches.size
        self.captured_text = capture_text(content, matches)
        if matches.empty?
          self.updated_content = content
          self.changed = false
          return
        end

        self.updated_content = replace_line_ranges(content, matches, replacement.to_s)
        self.changed = updated_content != content
      rescue Error => e
        crispr_fail!(e)
      end
    end

    class Delete < Actor
      include OperationSupport
      include OperationProfilable

      declare_operation_profile(
        operation_kind: :delete,
        source_requirement: :required,
        destination_requirement: :none,
        replacement_source: :none,
        captures_source_text: true,
        supports_if_missing: false
      )

      input :content, type: String
      input :target, type: OwnerSelector
      input :source_label, type: String, default: 'source'

      output :updated_content
      output :matches, default: -> { [] }
      output :match_count, type: Integer, default: 0
      output :changed, default: false
      output :captured_text, allow_nil: true, default: nil
      output :operation_profile

      def call
        self.operation_profile = self.class.operation_profile
        actor = Replace.result(
          content: content,
          target: target,
          replacement: '',
          source_label: source_label
        )
        fail!(error: actor.error, details: actor.details) if actor.failure?

        self.updated_content = actor.updated_content
        self.matches = actor.matches
        self.match_count = actor.match_count
        self.changed = actor.changed
        self.captured_text = actor.captured_text
      end
    end

    class DeleteBatch < Actor
      include OperationSupport
      include OperationProfilable

      declare_operation_profile(
        operation_kind: :delete_batch,
        source_requirement: :required,
        destination_requirement: :none,
        replacement_source: :none,
        captures_source_text: true,
        supports_if_missing: false
      )

      input :content, type: String
      input :targets, default: -> { [] }
      input :source_label, type: String, default: 'source'

      output :updated_content
      output :matches, default: -> { [] }
      output :match_count, type: Integer, default: 0
      output :changed, default: false
      output :captured_text, allow_nil: true, default: nil
      output :operation_profile

      def call
        self.operation_profile = self.class.operation_profile
        selector_targets = Array(targets)
        if selector_targets.empty?
          self.updated_content = content
          self.changed = false
          return
        end

        context = context_for_targets(content: content, source_label: source_label, targets: selector_targets)
        self.matches = selector_targets.flat_map { |target| normalize_matches(target, context) }
        self.match_count = matches.size
        self.captured_text = capture_text(content, matches)
        if matches.empty?
          self.updated_content = content
          self.changed = false
          return
        end

        self.updated_content = replace_line_ranges(content, matches, '')
        self.changed = updated_content != content
      rescue Error => e
        crispr_fail!(e)
      end
    end

    class Insert < Actor
      include OperationSupport
      include OperationProfilable

      declare_operation_profile(
        operation_kind: :insert,
        source_requirement: :none,
        destination_requirement: :optional,
        replacement_source: :explicit_text,
        captures_source_text: false,
        supports_if_missing: true
      )

      input :content, type: String
      input :text, type: String
      input :destination, allow_nil: true, default: nil
      input :if_missing, type: Symbol, default: :raise
      input :source_label, type: String, default: 'source'

      output :updated_content
      output :changed, default: false
      output :operation_profile
      output :destination_profile, allow_nil: true, default: nil

      def call
        self.operation_profile = self.class.operation_profile
        self.updated_content, self.destination_profile =
          insert_text(content, text, destination: destination, if_missing: if_missing, source_label: source_label)
        self.changed = updated_content != content
      rescue Error => e
        crispr_fail!(e)
      end
    end

    class Move < Actor
      include OperationSupport
      include OperationProfilable

      declare_operation_profile(
        operation_kind: :move,
        source_requirement: :optional,
        destination_requirement: :optional,
        replacement_source: :captured_text_or_explicit,
        captures_source_text: true,
        supports_if_missing: true
      )

      input :content, type: String
      input :source_target, type: OwnerSelector, allow_nil: true, default: nil
      input :destination, allow_nil: true, default: nil
      input :replacement, allow_nil: true, default: nil
      input :if_missing, type: Symbol, default: :raise
      input :source_label, type: String, default: 'source'

      output :updated_content
      output :source_matches, default: -> { [] }
      output :source_match_count, type: Integer, default: 0
      output :changed, default: false
      output :captured_text, allow_nil: true, default: nil
      output :operation_profile
      output :destination_profile, allow_nil: true, default: nil

      def call
        self.operation_profile = self.class.operation_profile
        working_content = content
        if source_target
          context = context_for(content: content, source_label: source_label, target: source_target)
          self.source_matches = normalize_matches(source_target, context)
          self.source_match_count = source_matches.size
          self.captured_text = capture_text(content, source_matches)
          working_content = replace_line_ranges(content, source_matches, '') unless source_matches.empty?
        end

        text_to_insert = replacement.nil? ? captured_text.to_s : replacement.to_s
        self.updated_content =
          if text_to_insert.empty?
            working_content
          else
            updated_content, profile = insert_text(working_content, text_to_insert, destination: destination,
                                                                                    if_missing: if_missing, source_label: source_label)
            self.destination_profile = profile
            updated_content
          end
        self.changed = updated_content != content
      rescue Error => e
        crispr_fail!(e)
      end
    end
  end
end

module Ast
  module Crispr
    module ProfileReportCompatibility
      private

      def stringify_report_value(value)
        case value
        when Symbol
          value.to_s
        when Hash
          value.transform_values { |inner| stringify_report_value(inner) }
        when Array
          value.map { |inner| stringify_report_value(inner) }
        else
          value
        end
      end

      def stringified_report(hash)
        hash.reject { |key, _| key == :metadata }
            .transform_values { |value| stringify_report_value(value) }
      end
    end

    class MatchProfile
      include ProfileReportCompatibility

      def report
        data = to_h.merge(
          start_boundary_family: start_boundary_family || :unknown,
          end_boundary_family: end_boundary_family || :unknown,
          payload_family: payload_family || :unknown
        )
        stringified_report(data)
      end
    end

    class SelectionProfile
      include ProfileReportCompatibility

      KNOWN_SELECTOR_KINDS = {
        owner_filter: { family: :owner_filter },
        comment_region_owner: { family: :comment_anchor },
        comment_region_owned_owner: { family: :comment_anchor },
        heading_section: { family: :section_branch }
      }.freeze
      KNOWN_COMMENT_REGIONS = {
        leading: { family: :leading },
        trailing: { family: :trailing },
        inline: { family: :inline }
      }.freeze
      COMPAT_SELECTION_INTENT_FAMILIES = {
        predicate_filter: :predicate,
        comment_anchored_owner: :comment_anchor,
        comment_region_filter: :comment,
        section_branch: :section_branch,
        section_heading: :section
      }.freeze

      def report
        data = to_h
        selector_kind_family = KNOWN_SELECTOR_KINDS[selector_kind]&.fetch(:family, nil)
        comment_region_family = comment_region.nil? ? :none : KNOWN_COMMENT_REGIONS[comment_region]&.fetch(:family, nil)
        owner_selector_family = owner_selector == :heading_sections ? :section : structure_profile.owner_selector_family
        known_comment_region = !comment_region.nil? && KNOWN_COMMENT_REGIONS.key?(comment_region)
        data.merge!(
          owner_selector_family: owner_selector_family || :unknown,
          known_owner_selector: structure_profile.known_owner_selector?,
          selector_kind_family: selector_kind_family || :unknown,
          known_selector_kind: KNOWN_SELECTOR_KINDS.key?(selector_kind),
          selection_intent_family: COMPAT_SELECTION_INTENT_FAMILIES.fetch(selection_intent, :unknown),
          known_selection_intent: COMPAT_SELECTION_INTENT_FAMILIES.key?(selection_intent),
          comment_region_family: comment_region_family || :unknown,
          known_comment_region: known_comment_region,
          comment_anchored: known_comment_region || selector_kind_family == :comment_anchor || COMPAT_SELECTION_INTENT_FAMILIES[selection_intent] == :comment
        )
        stringified_report(data)
      end
    end

    class DestinationProfile
      include ProfileReportCompatibility

      def report
        data = to_h.merge(
          known_resolution_kind: KNOWN_RESOLUTION_KINDS.key?(resolution_kind),
          known_resolution_source: KNOWN_RESOLUTION_SOURCES.key?(resolution_source),
          resolution_family: resolution_family || :unknown,
          resolution_source_family: resolution_source_family || :unknown,
          anchor_boundary_family: anchor_boundary_family || :unknown
        )
        stringified_report(data)
      end
    end

    class OperationProfile
      include ProfileReportCompatibility

      def report
        data = to_h.merge(
          operation_family: operation_family || :unknown,
          known_source_requirement: KNOWN_REQUIREMENTS.include?(source_requirement),
          known_destination_requirement: KNOWN_REQUIREMENTS.include?(destination_requirement),
          known_replacement_source: KNOWN_REPLACEMENT_SOURCES.include?(replacement_source),
          selects_source: selects_source?,
          requires_source: requires_source?,
          supports_destination: supports_destination?,
          requires_destination: requires_destination?,
          explicit_replacement: explicit_replacement?,
          may_reuse_captured_text: may_reuse_captured_text?
        )
        stringified_report(data)
      end
    end

    class StructureProfile
      include ProfileReportCompatibility

      def report
        stringified_report(to_h)
      end
    end

    class << self
      def ast_merge_contract_anchor
        'Ast::Merge.structured_edit'
      end

      def boundary_report
        {
          package: PACKAGE_NAME,
          layer: 'structural_edit_tool',
          status: 'active_thin_package',
          base_contract_package: 'ast-merge',
          relationship: {
            ast_merge: [
              'owns portable structured-edit envelope contracts',
              'owns transport, report, replay, review, and provider handoff vocabulary',
              'remains the substrate for provider-neutral fixtures'
            ],
            ast_crispr: [
              'owns ergonomic structural-edit selectors, profiles, and operation helpers',
              'wraps ast-merge contracts instead of forking them',
              'may grow compatibility helpers for old ast-crispr concepts after fixture-backed review'
            ],
            provider_packages: [
              'own parser-specific execution and metadata projection',
              'may expose provider adapters consumed by ast-crispr',
              'keep raw parser details behind normalized tree metadata or semantic sidecars'
            ],
            ast_template: [
              'orchestrates template and directory workflows',
              'invokes structural edits through ast-merge or ast-crispr registries/envelopes',
              'does not own parser-specific selectors'
            ]
          },
          implementations: [
            {
              language: 'go',
              package_name: 'astcrispr',
              import: 'github.com/structuredmerge/structuredmerge-go/astcrispr'
            },
            {
              language: 'ruby',
              package_name: 'ast-crispr',
              require: 'ast/crispr'
            },
            {
              language: 'rust',
              package_name: 'ast-crispr',
              crate: 'ast_crispr'
            },
            {
              language: 'typescript',
              package_name: '@structuredmerge/ast-crispr',
              import: '@structuredmerge/ast-crispr'
            }
          ],
          initial_exports: [
            'package identity',
            'boundary report',
            'ast-merge structured-edit contract anchor',
            'limit helpers',
            'match profile helpers',
            'selection profile helpers',
            'destination profile helpers',
            'operation profile helpers',
            'replace/delete/insert/move helpers',
            'batch operation helpers'
          ],
          future_exports: [],
          metadata: {
            source: 'legacy_crispr_reference',
            decision: 'Keep ast-merge as the base contract layer and revive ast-crispr as a separate thin package in every implementation.'
          }
        }
      end

      def limit(spec = nil)
        Limit.coerce(spec)
      end

      def match_profile(start_boundary: 'owner_start', end_boundary: 'owner_end', payload_kind: 'structural_owner_body')
        MatchProfile.new(start_boundary: start_boundary, end_boundary: end_boundary, payload_kind: payload_kind)
      end

      def selection_profile(
        owner_scope: 'shared_default',
        owner_selector: 'line_bound_statements',
        selector_kind: 'owner_filter',
        selection_intent: 'predicate_filter',
        comment_region: nil,
        include_trailing_gap: false
      )
        SelectionProfile.new(
          owner_scope: owner_scope,
          owner_selector: owner_selector,
          selector_kind: selector_kind,
          selection_intent: selection_intent,
          comment_region: comment_region,
          include_trailing_gap: include_trailing_gap
        )
      end

      def destination_profile(
        resolution_kind: 'append_fallback',
        resolution_source: 'none',
        anchor_boundary: 'none',
        used_if_missing: false
      )
        DestinationProfile.new(
          resolution_kind: resolution_kind,
          resolution_source: resolution_source,
          anchor_boundary: anchor_boundary,
          used_if_missing: used_if_missing
        )
      end

      def operation_profile(
        operation_kind: 'replace',
        source_requirement: 'required',
        destination_requirement: 'none',
        replacement_source: 'explicit_text',
        captures_source_text: false,
        supports_if_missing: false
      )
        OperationProfile.new(
          operation_kind: operation_kind,
          source_requirement: source_requirement,
          destination_requirement: destination_requirement,
          replacement_source: replacement_source,
          captures_source_text: captures_source_text,
          supports_if_missing: supports_if_missing
        )
      end

      def replace_operation
        OperationProfile.new(
          operation_kind: 'replace',
          source_requirement: 'required',
          destination_requirement: 'none',
          replacement_source: 'explicit_text',
          captures_source_text: true,
          supports_if_missing: false
        )
      end

      def delete_operation
        OperationProfile.new(
          operation_kind: 'delete',
          source_requirement: 'required',
          destination_requirement: 'none',
          replacement_source: 'none',
          captures_source_text: true,
          supports_if_missing: false
        )
      end

      def insert_operation
        OperationProfile.new(
          operation_kind: 'insert',
          source_requirement: 'none',
          destination_requirement: 'optional',
          replacement_source: 'explicit_text',
          captures_source_text: false,
          supports_if_missing: true
        )
      end

      def move_operation
        OperationProfile.new(
          operation_kind: 'move',
          source_requirement: 'optional',
          destination_requirement: 'optional',
          replacement_source: 'captured_text_or_explicit',
          captures_source_text: true,
          supports_if_missing: true
        )
      end

      def batch_operation_report(profiles)
        {
          operation_count: profiles.length,
          operation_kinds: profiles.map { |profile| profile.operation_kind.to_s },
          operation_profiles: profiles.map(&:report)
        }
      end
    end
  end
end
