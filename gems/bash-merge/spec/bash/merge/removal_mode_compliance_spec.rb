# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

RSpec.describe Bash::Merge::SmartMerger, :bash_grammar do
  it_behaves_like 'Ast::Merge::RemovalModeCompliance' do
    let(:merger_class) { described_class }

    let(:removal_mode_leading_comments_case) do
      {
        template: <<~BASH,
          echo "template"
        BASH
        destination: <<~BASH,
          echo "template"

          # Destination cleanup docs
          cleanup() {
            echo "destination cleanup"
          }
        BASH
        expected: <<~BASH
          echo "template"

          # Destination cleanup docs
        BASH
      }
    end

    let(:removal_mode_inline_comments_case) do
      {
        template: <<~BASH,
          echo "template"
        BASH
        destination: <<~BASH,
          echo "template"
          APP_MODE="destination" # destination env docs
        BASH
        expected: <<~BASH
          echo "template"
          # destination env docs
        BASH
      }
    end

    let(:removal_mode_separator_blank_line_case) do
      {
        template: <<~BASH,
          echo "template"
          echo "keep"
        BASH
        destination: <<~BASH,
          echo "template"
          APP_MODE="destination" # destination env docs

          # trailing note
          echo "keep"
        BASH
        expected: <<~BASH
          echo "template"
          # destination env docs

          # trailing note
          echo "keep"
        BASH
      }
    end

    let(:unsupported_removal_mode_case_reasons) do
      {
        removal_mode_recursive_case: 'Bash smart merge currently has no recursive or container-level removal path'
      }
    end
  end
end
