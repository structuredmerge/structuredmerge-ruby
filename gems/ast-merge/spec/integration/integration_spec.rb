# frozen_string_literal: true

# Integration specs for ast-merge base layer tools
# These serve as implementation examples for *-merge gems
#
# This spec demonstrates:
# 1. Minimal required integration of Ast::Merge::DebugLogger
# 2. Minimal required integration of Ast::Merge::FreezeNodeBase
# 3. Minimal required integration of Ast::Merge::MergeResult
# 4. Dog-fooding of the shared examples provided by ast-merge

require 'ast/merge/rspec/shared_examples'

RSpec.describe 'Ast::Merge integration examples' do
  describe 'Minimal DebugLogger integration' do
    # This is the MINIMAL required integration pattern for any *-merge gem.
    # Simply extend Ast::Merge::DebugLogger and configure env_var_name and log_prefix.
    # All methods (debug, info, warning, time, etc.) are inherited from the base module.

    # Use before block with stub_const to avoid leaky constant declaration
    before do
      stub_const('ExampleMergeDebugLogger', Module.new do
        extend Ast::Merge::DebugLogger

        # Configure the environment variable name for this module
        self.env_var_name = 'EXAMPLE_MERGE_DEBUG'

        # Configure the log prefix for this module
        self.log_prefix = '[ExampleMerge]'
      end)
    end

    # Dog-food the shared examples to validate minimal integration
    it_behaves_like 'Ast::Merge::DebugLogger' do
      let(:described_logger) { ExampleMergeDebugLogger }
      let(:env_var_name) { 'EXAMPLE_MERGE_DEBUG' }
      let(:log_prefix) { '[ExampleMerge]' }
    end

    describe 'minimal integration verification' do
      it 'only adds configuration accessors, not method redefinitions' do
        # The module should only have singleton methods for configuration accessors
        # (env_var_name, env_var_name=, log_prefix, log_prefix=) which are set up
        # by the extended hook, NOT redefinitions of behavior methods
        own_methods = ExampleMergeDebugLogger.singleton_methods(false)

        # These are the behavior methods that should NOT be redefined
        behavior_methods = %i[
          enabled?
          debug
          info
          warning
          time
          log_node
          extract_node_info
          safe_type_name
          extract_lines
        ]

        # Verify that none of the behavior methods are redefined as singleton methods
        redefined = own_methods & behavior_methods
        expect(redefined).to be_empty,
                             "Expected no redefined behavior methods, but found: #{redefined.join(', ')}"
      end

      it 'has configuration accessors from extended hook' do
        # These are expected to be available via prepended module in extended hook
        expect(ExampleMergeDebugLogger).to respond_to(:env_var_name)
        expect(ExampleMergeDebugLogger).to respond_to(:log_prefix)
        expect(ExampleMergeDebugLogger).to respond_to(:env_var_name=)
        expect(ExampleMergeDebugLogger).to respond_to(:log_prefix=)
      end

      it 'inherits all base methods via extend' do
        base_methods = %i[
          enabled?
          debug
          info
          warning
          time
          log_node
          extract_node_info
          safe_type_name
          extract_lines
          env_var_name
          log_prefix
        ]

        base_methods.each do |method|
          expect(ExampleMergeDebugLogger).to respond_to(method),
                                             "Expected to inherit #{method} from Ast::Merge::DebugLogger"
        end
      end

      it 'uses the configured env_var_name' do
        expect(ExampleMergeDebugLogger.env_var_name).to eq('EXAMPLE_MERGE_DEBUG')
      end

      it 'uses the configured log_prefix' do
        expect(ExampleMergeDebugLogger.log_prefix).to eq('[ExampleMerge]')
      end
    end
  end

  describe 'Base Ast::Merge::DebugLogger (self-validation)' do
    # Validate the base module itself works correctly
    it_behaves_like 'Ast::Merge::DebugLogger' do
      let(:described_logger) { Ast::Merge::DebugLogger }
      let(:env_var_name) { 'AST_MERGE_DEBUG' }
      let(:log_prefix) { '[Ast::Merge]' }
    end
  end

  describe 'Base Ast::Merge::FreezeNodeBase (self-validation)' do
    # Validate the base FreezeNodeBase class works correctly
    it_behaves_like 'Ast::Merge::FreezeNodeBase' do
      let(:freeze_node_class) { Ast::Merge::FreezeNodeBase }
      let(:default_pattern_type) { :hash_comment }
      let(:build_freeze_node) do
        lambda { |start_line:, end_line:, **opts|
          Ast::Merge::FreezeNodeBase.new(start_line: start_line, end_line: end_line, **opts)
        }
      end
    end
  end

  describe 'Base Ast::Merge::MergeResultBase (self-validation)' do
    # Validate the base MergeResultBase class works correctly
    it_behaves_like 'Ast::Merge::MergeResultBase' do
      let(:merge_result_class) { Ast::Merge::MergeResultBase }
      let(:build_merge_result) { -> { Ast::Merge::MergeResultBase.new } }
    end
  end
end
