# frozen_string_literal: true

module Ruby
  module Merge
    # Computes stable name/parameter similarity scores for Ruby methods.
    #
    # The dynamic-programming distance calculation is intentionally kept local
    # to this value object so the matching contract stays easy to audit.
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    class MethodSimilarity
      DEFAULT_NAME_WEIGHT = 0.7
      DEFAULT_PARAMS_WEIGHT = 0.3

      attr_reader :name_weight, :params_weight

      def initialize(name_weight: DEFAULT_NAME_WEIGHT, params_weight: DEFAULT_PARAMS_WEIGHT)
        @name_weight = name_weight
        @params_weight = params_weight
      end

      def call(template_name:, template_params:, dest_name:, dest_params:)
        name_score = string_similarity(template_name.to_s, dest_name.to_s)
        param_score = param_similarity(Array(template_params), Array(dest_params))

        (name_score * name_weight) + (param_score * params_weight)
      end

      def param_similarity(template_params, dest_params)
        return 1.0 if template_params.empty? && dest_params.empty?
        return 0.0 if template_params.empty? || dest_params.empty?

        common = (template_params & dest_params).size
        total = [template_params.size, dest_params.size].max
        count_ratio = [template_params.size, dest_params.size].min.to_f / total
        name_match_ratio = common.to_f / total

        (name_match_ratio * 0.7) + (count_ratio * 0.3)
      end

      def string_similarity(str1, str2)
        return 1.0 if str1 == str2
        return 0.0 if str1.empty? || str2.empty?

        distance = levenshtein_distance(str1, str2)
        max_len = [str1.length, str2.length].max

        1.0 - (distance.to_f / max_len)
      end

      def levenshtein_distance(str1, str2)
        return str2.length if str1.empty?
        return str1.length if str2.empty?

        str1, str2 = str2, str1 if str1.length > str2.length

        m = str1.length
        n = str2.length
        previous_row = (0..m).to_a
        current_row = Array.new(m + 1, 0)

        (1..n).each do |j|
          current_row[0] = j

          (1..m).each do |i|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            current_row[i] = [
              previous_row[i] + 1,
              current_row[i - 1] + 1,
              previous_row[i - 1] + cost
            ].min
          end

          previous_row, current_row = current_row, previous_row
        end

        previous_row[m]
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
