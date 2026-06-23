# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ast::Merge::TrailingGroups::AlignmentSort do
  let(:test_class) do
    Class.new do
      include Ast::Merge::TrailingGroups::AlignmentSort
    end
  end

  let(:instance) { test_class.new }

  describe '#sort_alignment_with_template_position' do
    it 'sorts matches by destination index' do
      alignment = [
        { type: :match, dest_index: 2, template_index: 0 },
        { type: :match, dest_index: 0, template_index: 1 }
      ]
      result = instance.sort_alignment_with_template_position(alignment, 3)
      expect(result.map { |e| e[:dest_index] }).to eq([0, 2])
    end

    it 'interleaves dest-only with matches by destination index' do
      alignment = [
        { type: :dest_only, dest_index: 1 },
        { type: :match, dest_index: 0, template_index: 0 },
        { type: :match, dest_index: 2, template_index: 1 }
      ]
      result = instance.sort_alignment_with_template_position(alignment, 3)
      expect(result.map { |e| e[:type] }).to eq(%i[match dest_only match])
    end

    it 'places template-only entries after all dest-backed entries' do
      alignment = [
        { type: :template_only, template_index: 0 },
        { type: :match, dest_index: 0, template_index: 1 },
        { type: :dest_only, dest_index: 1 }
      ]
      result = instance.sort_alignment_with_template_position(alignment, 2)
      expect(result.map { |e| e[:type] }).to eq(%i[match dest_only template_only])
    end

    it 'orders multiple template-only entries by template_index' do
      alignment = [
        { type: :template_only, template_index: 5 },
        { type: :template_only, template_index: 2 },
        { type: :template_only, template_index: 8 }
      ]
      result = instance.sort_alignment_with_template_position(alignment, 0)
      expect(result.map { |e| e[:template_index] }).to eq([2, 5, 8])
    end

    it 'handles an empty alignment' do
      result = instance.sort_alignment_with_template_position([], 0)
      expect(result).to eq([])
    end

    it 'handles alignment with only matches' do
      alignment = [
        { type: :match, dest_index: 1, template_index: 0 },
        { type: :match, dest_index: 0, template_index: 1 }
      ]
      result = instance.sort_alignment_with_template_position(alignment, 2)
      expect(result.map { |e| e[:dest_index] }).to eq([0, 1])
    end
  end

  describe '#match_sort_key' do
    it 'returns [0, dest_index, 0, template_index]' do
      entry = { type: :match, dest_index: 3, template_index: 5 }
      expect(instance.match_sort_key(entry)).to eq([0, 3, 0, 5])
    end

    it 'handles nil template_index gracefully' do
      entry = { type: :match, dest_index: 3, template_index: nil }
      expect(instance.match_sort_key(entry)).to eq([0, 3, 0, 0])
    end
  end

  describe '#dest_only_sort_key' do
    it 'returns [0, dest_index, 1, 0]' do
      entry = { type: :dest_only, dest_index: 7 }
      expect(instance.dest_only_sort_key(entry)).to eq([0, 7, 1, 0])
    end
  end

  describe '#template_only_sort_key' do
    it 'returns [2, template_index, 0, 0]' do
      entry = { type: :template_only, template_index: 4 }
      expect(instance.template_only_sort_key(entry, 10)).to eq([2, 4, 0, 0])
    end
  end

  describe 'overriding hooks' do
    it 'allows overriding template_only_sort_key for custom positioning' do
      custom_class = Class.new do
        include Ast::Merge::TrailingGroups::AlignmentSort

        def template_only_sort_key(entry, dest_size)
          # Insert at dest_size + template_index position (dotenv-merge style)
          [dest_size + entry[:template_index], 1, 0, 0]
        end
      end

      inst = custom_class.new
      alignment = [
        { type: :match, dest_index: 0, template_index: 0 },
        { type: :template_only, template_index: 1 }
      ]
      result = inst.sort_alignment_with_template_position(alignment, 2)
      expect(result.map { |e| e[:type] }).to eq(%i[match template_only])
    end

    it 'allows overriding dest_only_sort_key for freeze blocks' do
      custom_class = Class.new do
        include Ast::Merge::TrailingGroups::AlignmentSort

        def dest_only_sort_key(entry)
          if entry[:freeze_block]
            [1, entry[:dest_index], 0, 0]
          else
            super
          end
        end
      end

      inst = custom_class.new
      alignment = [
        { type: :match, dest_index: 0, template_index: 0 },
        { type: :dest_only, dest_index: 1, freeze_block: true },
        { type: :template_only, template_index: 1 }
      ]
      result = inst.sort_alignment_with_template_position(alignment, 2)
      expect(result.map { |e| e[:type] }).to eq(%i[match dest_only template_only])
    end
  end
end
