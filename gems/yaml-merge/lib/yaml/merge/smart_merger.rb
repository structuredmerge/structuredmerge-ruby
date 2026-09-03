# frozen_string_literal: true

module Yaml
  module Merge
    class SmartMerger < Ast::Merge::SmartMergerBase
      def initialize(template_content, dest_content, preference: :destination, merge_sequences: false, **options)
        @merge_sequences = merge_sequences
        super(template_content, dest_content, preference: preference, **options)
      end

      protected

      def analysis_class
        FileAnalysis
      end

      def resolver_class
        Resolver
      end

      def result_class
        MergeResult
      end

      def build_resolver
        resolver_class.new(
          @template_analysis,
          @dest_analysis,
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          remove_template_missing_nodes: @remove_template_missing_nodes,
          merge_sequences: @merge_sequences
        )
      end

      def build_result
        MergeResult.new
      end

      def perform_merge
        @resolver.resolve(@result)
        @result
      end

      def template_parse_error_class
        TemplateParseError
      end

      def destination_parse_error_class
        DestinationParseError
      end

      class Resolver < Ast::Merge::ConflictResolverBase
        include Ast::Merge::StructuredEmitterProvenanceSupport
        include Ast::Merge::CommentLayoutEmissionSupport

        def initialize(template_analysis, dest_analysis, merge_sequences: false, **options)
          super(strategy: :batch, template_analysis: template_analysis, dest_analysis: dest_analysis, **options)
          @merge_sequences = merge_sequences
          @emitter = Emitter.new
        end

        protected

        def resolve_batch(result)
          @result = result
          @emitter.clear
          merge_node_lists(
            @template_analysis.statements,
            @dest_analysis.statements,
            @template_analysis,
            @dest_analysis
          )
          transfer_emitter_output(result)
        end

        private

        def merge_node_lists(template_nodes, dest_nodes, template_analysis, dest_analysis, template_boundary_line: nil,
                             dest_boundary_line: nil)
          dest_by_sig = build_signature_map(dest_nodes, dest_analysis)
          consumed_dest = Set.new

          template_nodes.each do |template_node|
            template_sig = template_analysis.generate_signature(template_node)
            dest_info = next_node_info(dest_by_sig[template_sig], consumed_dest)

            if dest_info
              emit_destination_only_nodes_before(
                dest_info[:index],
                dest_nodes,
                dest_analysis,
                consumed_dest,
                boundary_line: dest_boundary_line
              )
              merge_matched_nodes(
                template_node,
                dest_info[:node],
                template_analysis,
                dest_analysis,
                template_owners: template_nodes,
                dest_owners: dest_nodes,
                template_boundary_line: template_boundary_line,
                dest_boundary_line: dest_boundary_line
              )
              consumed_dest << dest_info[:index]
            elsif @add_template_only_nodes
              emit_node_with_leading_gap(template_node, template_analysis, template_nodes,
                                         boundary_line: template_boundary_line)
            end
          end

          dest_nodes.each_with_index do |dest_node, index|
            next if consumed_dest.include?(index)

            next if @remove_template_missing_nodes

            emit_node_with_leading_gap(dest_node, dest_analysis, dest_nodes, boundary_line: dest_boundary_line)
          end
        end

        def next_node_info(candidates, consumed_indices)
          Array(candidates).find { |candidate| !consumed_indices.include?(candidate[:index]) }
        end

        def merge_matched_nodes(template_node, dest_node, template_analysis, dest_analysis, template_owners: nil,
                                dest_owners: nil, template_boundary_line: nil, dest_boundary_line: nil)
          if node_kind?(template_node, :document?) && node_kind?(dest_node, :document?)
            dest_header_end = emit_document_header(dest_node, dest_analysis)
            template_header_end = document_header_end_line(template_node)
            merge_node_lists(
              template_node.mergeable_children,
              dest_node.mergeable_children,
              template_analysis,
              dest_analysis,
              template_boundary_line: template_header_end,
              dest_boundary_line: dest_header_end
            )
          elsif node_kind?(template_node, :mapping_pair?) && node_kind?(dest_node, :mapping_pair?)
            merge_mapping_pair(template_node, dest_node, template_analysis, dest_analysis, template_owners: template_owners,
                                                                                           dest_owners: dest_owners,
                                                                                           template_boundary_line: template_boundary_line,
                                                                                           dest_boundary_line: dest_boundary_line)
          elsif node_kind?(template_node, :mapping?) && node_kind?(dest_node, :mapping?)
            merge_node_lists(
              template_node.mergeable_children,
              dest_node.mergeable_children,
              template_analysis,
              dest_analysis,
              template_boundary_line: template_boundary_line,
              dest_boundary_line: dest_boundary_line
            )
          else
            selected_node, selected_analysis, gap_node, gap_analysis, gap_owners, gap_boundary_line =
              preferred_atomic_emit_sources(
                template_node,
                dest_node,
                template_analysis,
                dest_analysis,
                template_owners: template_owners,
                dest_owners: dest_owners,
                template_boundary_line: template_boundary_line,
                dest_boundary_line: dest_boundary_line
              )
            emit_node_leading_gap(gap_node, gap_analysis, gap_owners, boundary_line: gap_boundary_line)
            emit_raw_node(selected_node, selected_analysis)
          end
        end

        def node_kind?(node, predicate)
          node.respond_to?(predicate) && node.public_send(predicate)
        end

        def merge_mapping_pair(template_node, dest_node, template_analysis, dest_analysis, template_owners: nil,
                               dest_owners: nil, template_boundary_line: nil, dest_boundary_line: nil)
          template_value = template_node.value_node&.unwrap_value_node
          dest_value = dest_node.value_node&.unwrap_value_node

          unless template_value&.mapping? && dest_value&.mapping?
            selected_node, selected_analysis, gap_node, gap_analysis, gap_owners, gap_boundary_line =
              preferred_atomic_emit_sources(
                template_node,
                dest_node,
                template_analysis,
                dest_analysis,
                template_owners: template_owners,
                dest_owners: dest_owners,
                template_boundary_line: template_boundary_line,
                dest_boundary_line: dest_boundary_line
              )
            emit_node_leading_gap(gap_node, gap_analysis, gap_owners, boundary_line: gap_boundary_line)
            return emit_raw_node(selected_node, selected_analysis)
          end

          header_node, header_analysis, gap_node, gap_analysis, gap_owners, gap_boundary_line =
            preferred_atomic_emit_sources(
              template_node,
              dest_node,
              template_analysis,
              dest_analysis,
              template_owners: template_owners,
              dest_owners: dest_owners,
              template_boundary_line: template_boundary_line,
              dest_boundary_line: dest_boundary_line
            )

          emit_node_leading_gap(gap_node, gap_analysis, gap_owners, boundary_line: gap_boundary_line)
          @emitter.emit_raw_lines(
            header_node.header_lines_before(header_node.equal?(dest_node) ? dest_value : template_value),
            metadata: emitter_block_metadata(header_analysis, header_node.start_line)
          )
          merge_node_lists(
            template_value.mergeable_children,
            dest_value.mergeable_children,
            template_analysis,
            dest_analysis,
            template_boundary_line: template_node.start_line,
            dest_boundary_line: dest_node.start_line
          )
          emit_container_tail(dest_value, dest_analysis)
        end

        def preferred_atomic_emit_sources(template_node, dest_node, template_analysis, dest_analysis,
                                          template_owners: nil, dest_owners: nil, template_boundary_line: nil,
                                          dest_boundary_line: nil)
          if @preference == :template
            [template_node, template_analysis, dest_node, dest_analysis, dest_owners, dest_boundary_line]
          else
            [dest_node, dest_analysis, dest_node, dest_analysis, dest_owners, dest_boundary_line]
          end
        end

        def emit_destination_only_nodes_before(index, dest_nodes, dest_analysis, consumed_dest, boundary_line:)
          dest_nodes.each_with_index do |dest_node, dest_index|
            break if dest_index >= index
            next if consumed_dest.include?(dest_index)

            emit_node_with_leading_gap(dest_node, dest_analysis, dest_nodes, boundary_line: boundary_line)
            consumed_dest << dest_index
          end
        end

        def emit_node_with_leading_gap(node, analysis, owners, boundary_line: nil)
          emit_node_leading_gap(node, analysis, owners, boundary_line: boundary_line)
          emit_raw_node(node, analysis)
        end

        def emit_node_leading_gap(node, analysis, owners, boundary_line: nil)
          gap_lines = source_leading_gap_lines_for(node, analysis, owners, boundary_line: boundary_line)
          return if gap_lines.empty?
          return if @emitter.blank_lines?(gap_lines) && @emitter.ends_with_blank_line?

          start_line = source_leading_gap_start_line_for(node, analysis, owners, boundary_line: boundary_line)
          @emitter.emit_raw_lines(gap_lines, metadata: emitter_block_metadata(analysis, start_line))
        end

        def source_leading_gap_lines_for(node, analysis, owners, boundary_line: nil)
          start_line = source_leading_gap_start_line_for(node, analysis, owners, boundary_line: boundary_line)
          return [] unless start_line && node.start_line && start_line < node.start_line

          (start_line...node.start_line).filter_map { |line_num| analysis.line_at(line_num) }
        end

        def source_leading_gap_start_line_for(node, _analysis, owners, boundary_line: nil)
          previous = previous_owner_for(node, nil, owners: owners)
          return previous.end_line + 1 if previous&.end_line
          return boundary_line + 1 if boundary_line

          nil
        end

        def emit_raw_node(node, analysis)
          return unless node.start_line && node.end_line

          lines = (node.start_line..node.end_line).filter_map { |line_num| analysis.line_at(line_num) }
          @emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, node.start_line))
        end

        def emit_document_header(document, analysis)
          header_end = document_header_end_line(document)
          body = document.body_node
          header_lines = if body
                           document.header_lines_before(body).select { |line| document_boundary_line?(line) }
                         else
                           []
                         end
          @emitter.emit_raw_lines(header_lines, metadata: emitter_block_metadata(analysis, document.start_line))
          header_end
        end

        def document_header_end_line(document)
          body = document.body_node
          return document.start_line unless body

          boundary_line = document.header_lines_before(body).each_with_index.filter_map do |line, index|
            document.start_line + index if document_boundary_line?(line)
          end.max
          boundary_line || document.start_line - 1
        end

        def emit_container_tail(container, analysis)
          children = container.mergeable_children
          return if children.empty?

          last_child = children.last
          return unless last_child.end_line && container.end_line && container.end_line > last_child.end_line

          lines = ((last_child.end_line + 1)..container.end_line).filter_map { |line_num| analysis.line_at(line_num) }
          @emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, last_child.end_line + 1))
        end

        def document_boundary_line?(line)
          %w[--- ...].include?(line.to_s.strip)
        end
      end
    end
  end
end
