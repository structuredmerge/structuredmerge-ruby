# frozen_string_literal: true

require 'digest'

module Ast
  module Merge
    module UnresolvedSupport
      protected

      def unresolved_mode?
        @resolution_mode == :unresolved
      end

      def unresolved_path_segments
        @unresolved_path_segments ||= []
      end

      def with_unresolved_path_segment(segment)
        return yield unless segment

        unresolved_path_segments << segment
        yield
      ensure
        unresolved_path_segments.pop if segment
      end

      def unresolved_surface_path(*segments, root: 'document[0]')
        ([root] + unresolved_path_segments + segments.compact).join(' > ')
      end

      def unresolved_case_id_for(prefix, *parts, node: nil)
        line = node&.respond_to?(:start_line) ? node.start_line : nil
        ([prefix] + parts + [line]).compact.join('-')
      end

      def unresolved_line_span(node)
        return unless node.respond_to?(:start_line)

        end_line = if node.respond_to?(:effective_end_line)
                     node.effective_end_line
                   elsif node.respond_to?(:end_line)
                     node.end_line
                   end
        return unless node.start_line && end_line

        [node.start_line, end_line]
      end

      def unresolved_identifier_for_nodes(*nodes, methods:)
        nodes.each do |node|
          next unless node

          Array(methods).each do |method_name|
            next unless node.respond_to?(method_name)

            value = node.public_send(method_name)
            return value if value
          end
        end

        nil
      end

      def unresolved_typed_path_segment(node_type, identifier: nil, node: nil, fallback: node_type)
        return "#{node_type}[#{identifier.inspect}]" if identifier

        line = node&.respond_to?(:start_line) ? node.start_line : nil
        return "#{node_type}[line=#{line}]" if line

        fallback
      end

      def unresolved_surface_path_for(segment = nil, fallback_segment: nil, root: 'document[0]')
        return unresolved_surface_path(segment, root: root) if segment
        return unresolved_surface_path(fallback_segment, root: root) if fallback_segment

        root
      end

      def with_first_unresolved_path_segment(*nodes, segment_builder:, &block)
        segment = nodes.lazy.filter_map { |node| segment_builder.call(node) if node }.first
        with_unresolved_path_segment(segment, &block)
      end

      def record_unresolved_node_choice(
        result:,
        template_node:,
        destination_node:,
        template_text:,
        destination_text:,
        provisional_winner:,
        case_prefix:,
        case_parts:,
        surface_path:, case_id: nil,
        metadata: {},
        conflict_fields: {},
        reason: :conflict,
        case_node: nil
      )
        result.record_unresolved_choice(
          template_text: template_text,
          destination_text: destination_text,
          provisional_winner: provisional_winner,
          case_id: case_id || unresolved_case_id_for(case_prefix, *Array(case_parts),
                                                     node: case_node || destination_node),
          surface_path: surface_path,
          reason: reason,
          metadata: {
            template_lines: unresolved_line_span(template_node),
            destination_lines: unresolved_line_span(destination_node)
          }.merge(metadata),
          conflict_fields: conflict_fields
        )
      end

      def review_identity_for_unresolved_choice(
        template_text:,
        destination_text:,
        provisional_winner:,
        surface_path: nil,
        **attributes
      )
        components = {
          destination_text: destination_text,
          provisional_winner: provisional_winner,
          surface_path: surface_path,
          template_text: template_text
        }.merge(attributes)

        Digest::SHA256.hexdigest(
          serialize_review_identity_components(components)
        )
      end

      def serialize_review_identity_components(value)
        case value
        when Hash
          value.sort_by { |key, _component| key.to_s }
               .map { |key, component| "#{key}=#{serialize_review_identity_components(component)}" }
               .join("\u001f")
        when Array
          value.map { |component| serialize_review_identity_components(component) }.join("\u001e")
        else
          value.to_s
        end
      end
    end
  end
end
