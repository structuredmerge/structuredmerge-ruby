# frozen_string_literal: true

module Ast
  module Merge
    # Shared helpers for recurring owner-selection and owner-matching shapes.
    module OwnerSelection
      module_function

      def match_by_path(template, destination, owners_key: :owners)
        template_owners = owners_from(template, owners_key)
        destination_owners = owners_from(destination, owners_key)
        destination_paths = owner_paths(destination_owners)
        template_paths = owner_paths(template_owners)

        {
          matched: template_owners.filter_map do |owner|
            path = owner_path(owner)
            next unless destination_paths.key?(path)

            { template_path: path, destination_path: path }
          end,
          unmatched_template: template_paths.keys.reject { |path| destination_paths.key?(path) },
          unmatched_destination: destination_paths.keys.reject { |path| template_paths.include?(path) }
        }
      end

      def selector_kind(owner_selector, logical_owners: {})
        normalized = owner_selector&.to_sym
        if logical_owners && !logical_owners.empty?
          :logical_owner
        elsif normalized == :shared_default
          :shared_default
        else
          :explicit
        end
      end

      def owner_path(owner)
        value_for(owner, :path)
      end

      def owners_from(analysis, owners_key)
        value_for(analysis, owners_key) || []
      end

      def owner_paths(owners)
        Array(owners).to_h { |owner| [owner_path(owner), true] }
      end

      def value_for(object, key)
        if object.respond_to?(:key?) && object.key?(key)
          object[key]
        elsif object.respond_to?(:key?) && object.key?(key.to_s)
          object[key.to_s]
        elsif object.respond_to?(key)
          object.public_send(key)
        end
      end
      private_class_method :value_for
    end
  end
end
