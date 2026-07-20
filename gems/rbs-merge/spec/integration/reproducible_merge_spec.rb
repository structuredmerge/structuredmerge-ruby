# frozen_string_literal: true

require 'spec_helper'
require 'rbs/merge'
require 'ast/merge/rspec/shared_examples'

# Integration specs - works with any RBS parser backend
# Tagged with :rbs_parsing since SmartMerger supports both RBS gem and tree-sitter-rbs
RSpec.describe 'RBS reproducible merge', :rbs_parsing do
  let(:fixtures_path) { File.expand_path('../fixtures/reproducible', __dir__) }
  let(:merger_class) { Rbs::Merge::SmartMerger }
  let(:file_extension) { 'rbs' }

  shared_examples 'comment-aware reproducible merge scenarios' do
    describe 'comment-aware declaration scenarios' do
      context 'when template preference keeps an adjacent destination-owned declaration doc block' do
        it_behaves_like 'a reproducible merge', '04_adjacent_declaration_comment_template_preference', {
          preference: :template
        }
      end

      context 'when removal promotes an adjacent destination-only declaration doc block' do
        it_behaves_like 'a reproducible merge', '05_adjacent_removed_declaration_comment_promotion', {
          remove_template_missing_nodes: true
        }
      end

      context 'when template preference keeps destination-owned docs on a matched alias declaration' do
        it_behaves_like 'a reproducible merge', '08_alias_declaration_comment_template_preference', {
          preference: :template
        }
      end

      context 'when a destination-owned frozen type alias must remain intact' do
        it_behaves_like 'a reproducible merge', '09_frozen_type_alias_destination_preserved'
      end

      context 'when a destination-owned frozen alias block must remain intact' do
        it_behaves_like 'a reproducible merge', '11_frozen_alias_destination_preserved'
      end

      context 'when a matched declaration follows a frozen destination block' do
        it_behaves_like 'a reproducible merge', '12_freeze_marker_not_attached_to_following_declaration', {
          preference: :template
        }
      end

      context 'when a matched declaration follows a custom-token frozen destination block' do
        it_behaves_like 'a reproducible merge', '13_custom_freeze_marker_not_attached_to_following_declaration', {
          preference: :template,
          freeze_token: 'custom-token'
        }
      end

      context 'when a matched declaration follows a reason-bearing frozen destination block' do
        it_behaves_like 'a reproducible merge', '14_reason_bearing_freeze_marker_not_attached_to_following_declaration', {
          preference: :template
        }
      end

      context 'when a matched declaration follows a reason-bearing custom-token frozen destination block' do
        it_behaves_like 'a reproducible merge', '15_reason_bearing_custom_freeze_marker_not_attached_to_following_declaration', {
          preference: :template,
          freeze_token: 'custom-token'
        }
      end

      context 'when docs immediately above a frozen destination block must stay with the block' do
        it_behaves_like 'a reproducible merge', '16_freeze_block_leading_docs_preserved', {
          preference: :template
        }
      end

      context 'when docs immediately above a custom-token frozen destination block must stay with the block' do
        it_behaves_like 'a reproducible merge', '17_custom_freeze_block_leading_docs_preserved', {
          preference: :template,
          freeze_token: 'custom-token'
        }
      end

      context 'when docs immediately above a reason-bearing frozen destination block must stay with the block' do
        it_behaves_like 'a reproducible merge', '18_reason_bearing_freeze_block_leading_docs_preserved', {
          preference: :template
        }
      end

      context 'when docs immediately above a reason-bearing custom-token frozen destination block must stay with the block' do
        it_behaves_like 'a reproducible merge', '19_reason_bearing_custom_freeze_block_leading_docs_preserved', {
          preference: :template,
          freeze_token: 'custom-token'
        }
      end
    end

    describe 'recursive member scenarios' do
      context 'when template preference keeps destination-owned docs on a matched nested member' do
        it_behaves_like 'a reproducible merge', '07_recursive_member_comment_template_preference', {
          preference: :template
        }
      end

      context 'when template preference aligns reordered overloads by callable shape' do
        it_behaves_like 'a reproducible merge', '06_recursive_overloaded_member_template_preference', {
          preference: :template,
          add_template_only_nodes: true
        }
      end
    end

    describe 'document boundary scenarios' do
      context 'when the destination is comment-only' do
        it_behaves_like 'a reproducible merge', '10_comment_only_destination_preserved'
      end
    end
  end

  describe 'basic merge scenarios (destination wins by default)' do
    context 'when a method is removed in destination' do
      it_behaves_like 'a reproducible merge', '01_method_removed'
    end

    context 'when a method is added in destination' do
      it_behaves_like 'a reproducible merge', '02_method_added'
    end

    context 'when a type signature is changed in destination' do
      it_behaves_like 'a reproducible merge', '03_signature_changed'
    end
  end

  it_behaves_like 'comment-aware reproducible merge scenarios'

  describe 'recursive member scenarios' do
    context 'when template preference keeps destination-owned docs on a matched nested member' do
      it_behaves_like 'a reproducible merge', '07_recursive_member_comment_template_preference', {
        preference: :template
      }
    end

    context 'when template preference aligns reordered overloads by callable shape' do
      it_behaves_like 'a reproducible merge', '06_recursive_overloaded_member_template_preference', {
        preference: :template,
        add_template_only_nodes: true
      }
    end

    it 'does not duplicate destination member comments before recursively matched declarations' do
      template = <<~RBS
        module Kettle
          module Family
            module Version
              VERSION: String
            end
            VERSION: String
          end
        end
      RBS
      destination = <<~RBS
        module Kettle
          module Family
            # See the writing guide of rbs: https://github.com/ruby/rbs#guides
            module Version
              VERSION: String
            end
            VERSION: String
          end
        end
      RBS

      merged = merger_class.new(template, destination, preference: :destination).merge.to_s
      merged_again = merger_class.new(template, merged, preference: :destination).merge.to_s

      expect(merged.scan('See the writing guide of rbs:')).to contain_exactly('See the writing guide of rbs:')
      expect(merged_again).to eq(merged)
    end
  end

  context 'with explicit RBS backend', :rbs_backend do
    around do |example|
      TreeHaver.with_backend(:rbs) do
        example.run
      end
    end

    it_behaves_like 'comment-aware reproducible merge scenarios'
  end

  context 'with explicit tree-sitter backend via MRI', :mri_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:mri) do
        example.run
      end
    end

    it_behaves_like 'comment-aware reproducible merge scenarios'
  end

  context 'with explicit Java backend', :java_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:java) do
        example.run
      end
    end

    it_behaves_like 'comment-aware reproducible merge scenarios'
  end

  context 'with explicit Rust backend', :rbs_grammar, :rust_backend do
    around do |example|
      TreeHaver.with_backend(:rust) do
        example.run
      end
    end

    it_behaves_like 'comment-aware reproducible merge scenarios'
  end

  context 'with explicit FFI backend', :ffi_backend, :rbs_grammar do
    around do |example|
      TreeHaver.with_backend(:ffi) do
        example.run
      end
    end

    it_behaves_like 'comment-aware reproducible merge scenarios'
  end
end
