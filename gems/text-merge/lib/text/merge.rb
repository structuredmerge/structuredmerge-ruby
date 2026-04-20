# frozen_string_literal: true

require "tree_haver"

module Text
  module Merge
    PACKAGE_NAME = "text-merge"
    DEFAULT_TEXT_REFINEMENT_THRESHOLD = 0.7
    DEFAULT_TEXT_REFINEMENT_WEIGHTS = {
      content: 0.7,
      length: 0.15,
      position: 0.15
    }.freeze

    module_function

    def text_feature_profile
      {
        family: "text",
        supported_dialects: [],
        supported_policies: []
      }
    end

    def text_parse_request(source)
      TreeHaver::ParserRequest.new(source: source, language: "text")
    end

    def normalize_text(source)
      source
        .gsub(/\r\n?/, "\n")
        .strip
        .split(/\n\s*\n+/)
        .map { |block| block.strip.gsub(/\s+/, " ") }
        .reject(&:empty?)
        .join("\n\n")
    end

    def analyze_text(source)
      normalized_source = normalize_text(source)
      parts = normalized_source.empty? ? [] : normalized_source.split("\n\n")
      cursor = 0

      blocks = parts.each_with_index.map do |normalized, index|
        start_offset = cursor
        end_offset = start_offset + normalized.length
        cursor = end_offset + 2

        {
          index: index,
          normalized: normalized,
          span: {
            start: start_offset,
            end: end_offset
          }
        }
      end

      {
        kind: "text",
        normalized_source: normalized_source,
        blocks: blocks
      }
    end

    def similarity_score(left_source, right_source)
      left = analyze_text(left_source)
      right = analyze_text(right_source)
      total = [left[:blocks].length, right[:blocks].length].max
      return 1.0 if total.zero?

      sum = 0.0
      total.times do |index|
        left_block = left[:blocks][index]
        right_block = right[:blocks][index]
        next unless left_block && right_block

        sum += jaccard(left_block[:normalized], right_block[:normalized])
      end

      sum / total
    end

    def is_similar(left_source, right_source, threshold)
      score = similarity_score(left_source, right_source)
      {
        score: score,
        threshold: threshold,
        matched: score >= threshold
      }
    end

    def match_text_blocks(template_source, destination_source)
      template = analyze_text(template_source)
      destination = analyze_text(destination_source)
      matched_template = {}
      matched_destination = {}
      matched = []

      destination[:blocks].each_with_index do |destination_block, destination_index|
        template_index = template[:blocks].find_index.with_index do |template_block, candidate_index|
          !matched_template[candidate_index] && template_block[:normalized] == destination_block[:normalized]
        end
        next unless template_index

        matched_template[template_index] = true
        matched_destination[destination_index] = true
        matched << {
          template_index: template_index,
          destination_index: destination_index,
          phase: "exact",
          score: 1.0
        }
      end

      destination[:blocks].each_with_index do |destination_block, destination_index|
        next if matched_destination[destination_index]

        best_template_index = nil
        best_score = 0.0
        template[:blocks].each_with_index do |template_block, template_index|
          next if matched_template[template_index]

          score = refined_text_similarity(
            template_block,
            destination_block,
            template[:blocks].length,
            destination[:blocks].length
          )
          next unless score >= DEFAULT_TEXT_REFINEMENT_THRESHOLD && score > best_score

          best_score = score
          best_template_index = template_index
        end

        next unless best_template_index

        matched_template[best_template_index] = true
        matched_destination[destination_index] = true
        matched << {
          template_index: best_template_index,
          destination_index: destination_index,
          phase: "refined",
          score: best_score
        }
      end

      {
        matched: matched,
        unmatched_template: template[:blocks].each_index.reject { |index| matched_template[index] },
        unmatched_destination: destination[:blocks].each_index.reject { |index| matched_destination[index] }
      }
    end

    def merge_text(template_source, destination_source)
      template = analyze_text(template_source)
      destination = analyze_text(destination_source)
      matches = match_text_blocks(template_source, destination_source)
      matched_template = matches[:matched].each_with_object({}) { |match, memo| memo[match[:template_index]] = true }
      merged_blocks = destination[:blocks].map { |block| block[:normalized] }

      template[:blocks].each_with_index do |block, index|
        next if matched_template[index]

        merged_blocks << block[:normalized]
      end

      {
        ok: true,
        diagnostics: [],
        output: merged_blocks.join("\n\n")
      }
    end

    def refined_text_similarity(template_block, destination_block, template_total, destination_total, weights = DEFAULT_TEXT_REFINEMENT_WEIGHTS)
      content = string_similarity(template_block[:normalized], destination_block[:normalized])
      length = length_similarity(template_block[:normalized], destination_block[:normalized])
      position = position_similarity(
        template_block[:index],
        destination_block[:index],
        template_total,
        destination_total
      )

      (weights[:content] * content) + (weights[:length] * length) + (weights[:position] * position)
    end

    def token_set(normalized)
      normalized.split(/\s+/).reject(&:empty?).to_h { |token| [token, true] }
    end
    private_class_method :token_set

    def jaccard(left, right)
      left_tokens = token_set(left)
      right_tokens = token_set(right)
      return 1.0 if left_tokens.empty? && right_tokens.empty?

      intersection = left_tokens.keys.count { |token| right_tokens[token] }
      union = (left_tokens.keys + right_tokens.keys).uniq.length
      union.zero? ? 1.0 : intersection.to_f / union
    end
    private_class_method :jaccard

    def levenshtein_distance(left, right)
      return 0 if left == right
      return right.length if left.empty?
      return left.length if right.empty?

      previous = (0..left.length).to_a
      current = Array.new(left.length + 1, 0)

      (1..right.length).each do |right_index|
        current[0] = right_index

        (1..left.length).each do |left_index|
          cost = left[left_index - 1] == right[right_index - 1] ? 0 : 1
          current[left_index] = [
            current[left_index - 1] + 1,
            previous[left_index] + 1,
            previous[left_index - 1] + cost
          ].min
        end

        previous = current.dup
      end

      previous[left.length]
    end
    private_class_method :levenshtein_distance

    def string_similarity(left, right)
      return 1.0 if left == right
      return 0.0 if left.empty? || right.empty?

      distance = levenshtein_distance(left, right)
      1.0 - (distance.to_f / [left.length, right.length].max)
    end
    private_class_method :string_similarity

    def length_similarity(left, right)
      return 1.0 if left.length == right.length
      max_length = [left.length, right.length].max
      return 1.0 if max_length.zero?

      [left.length, right.length].min.to_f / max_length
    end
    private_class_method :length_similarity

    def relative_position(index, total)
      total > 1 ? index.to_f / (total - 1) : 0.5
    end
    private_class_method :relative_position

    def position_similarity(template_index, destination_index, template_total, destination_total)
      1.0 - (
        relative_position(template_index, template_total) -
        relative_position(destination_index, destination_total)
      ).abs
    end
    private_class_method :position_similarity
  end
end
