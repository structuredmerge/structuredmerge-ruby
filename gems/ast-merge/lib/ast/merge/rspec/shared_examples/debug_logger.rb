# frozen_string_literal: true

require 'silent_stream'
require 'rspec/stubbed_env'

# Shared examples for validating DebugLogger integration
#
# Usage in your spec:
#   require "ast/merge/rspec/shared_examples/debug_logger"
#
#   RSpec.describe MyMerge::DebugLogger do
#     it_behaves_like "Ast::Merge::DebugLogger" do
#       let(:described_logger) { MyMerge::DebugLogger }
#       let(:env_var_name) { "MY_MERGE_DEBUG" }
#       let(:log_prefix) { "[MyMerge]" }
#     end
#   end
#
# @note The extending module must configure:
#   - self.env_var_name = "YOUR_ENV_VAR"
#   - self.log_prefix = "[YourPrefix]"

RSpec.shared_examples('Ast::Merge::DebugLogger') do
  include SilentStream

  include_context 'with stubbed env'

  # Required let blocks that must be provided by including spec:
  # - described_logger: The module that extends Ast::Merge::DebugLogger
  # - env_var_name: Expected environment variable name
  # - log_prefix: Expected log prefix

  describe 'module configuration' do
    it 'has env_var_name configured' do
      expect(described_logger.env_var_name).to(eq(env_var_name))
    end

    it 'has log_prefix configured' do
      expect(described_logger.log_prefix).to(eq(log_prefix))
    end

    it 'has BENCHMARK_AVAILABLE constant from base' do
      expect(described_logger::BENCHMARK_AVAILABLE).to(eq(Ast::Merge::DebugLogger::BENCHMARK_AVAILABLE))
    end
  end

  describe 'core methods from Ast::Merge::DebugLogger' do
    it 'responds to #enabled?' do
      expect(described_logger).to(respond_to(:enabled?))
    end

    it 'responds to #debug' do
      expect(described_logger).to(respond_to(:debug))
    end

    it 'responds to #info' do
      expect(described_logger).to(respond_to(:info))
    end

    it 'responds to #warning' do
      expect(described_logger).to(respond_to(:warning))
    end

    it 'responds to #time' do
      expect(described_logger).to(respond_to(:time))
    end

    it 'responds to #log_node' do
      expect(described_logger).to(respond_to(:log_node))
    end

    it 'responds to #extract_node_info' do
      expect(described_logger).to(respond_to(:extract_node_info))
    end

    it 'responds to #safe_type_name' do
      expect(described_logger).to(respond_to(:safe_type_name))
    end

    it 'responds to #extract_lines' do
      expect(described_logger).to(respond_to(:extract_lines))
    end
  end

  describe 'when debug is enabled' do
    before do
      stub_env(env_var_name => '1')
    end

    it '#enabled? returns true' do
      expect(described_logger.enabled?).to(be(true))
    end

    it '#debug outputs message with configured prefix' do
      expect { described_logger.debug('test message') }
        .to(output(/#{Regexp.escape(log_prefix)} test message/).to_stderr)
    end

    it '#debug includes context hash when provided' do
      expect { described_logger.debug('test', key: 'value') }
        .to(output(/key.*value/).to_stderr)
    end

    it '#info outputs with INFO label' do
      expect { described_logger.info('info message') }
        .to(output(/#{Regexp.escape(log_prefix)} INFO\] info message/).to_stderr)
    end

    it '#time logs start and completion with timing' do
      output = capture(:stderr) { described_logger.time('test operation') { 42 } }
      if Ast::Merge::DebugLogger::BENCHMARK_AVAILABLE
        expect(output).to(include('Starting: test operation'))
        expect(output).to(include('Completed: test operation'))
        expect(output).to(match(/real_ms/))
      else
        expect(output).to(include('WARNING'))
        expect(output).to(include('Benchmark gem not available'))
        expect(output).to(include('test operation'))
      end
    end

    it '#time returns the block result' do
      result = described_logger.time('operation') { 42 }
      expect(result).to(eq(42))
    end
  end

  describe 'when debug is disabled' do
    before do
      stub_env(env_var_name => nil)
    end

    it '#enabled? returns false' do
      expect(described_logger.enabled?).to(be(false))
    end

    it '#debug does not output anything' do
      expect { described_logger.debug('test') }.not_to(output.to_stderr)
    end

    it '#info does not output anything' do
      expect { described_logger.info('test') }.not_to(output.to_stderr)
    end

    it '#time still executes block and returns result without logging' do
      output = capture(:stderr) { @result = described_logger.time('operation') { 42 } }
      expect(@result).to(eq(42))
      expect(output).to(be_empty)
    end
  end

  describe '#warning (always outputs)' do
    before do
      stub_env(env_var_name => nil)
    end

    it 'outputs warning even when debug is disabled' do
      expect { described_logger.warning('warning message') }
        .to(output(/#{Regexp.escape(log_prefix)} WARNING\] warning message/).to_stderr)
    end
  end

  describe '#extract_node_info' do
    it 'extracts type name from object' do
      node = Object.new
      info = described_logger.extract_node_info(node)
      expect(info[:type]).to(eq('Object'))
    end
  end

  describe '#safe_type_name' do
    it 'returns class name for standard objects' do
      expect(described_logger.safe_type_name('test')).to(eq('String'))
    end

    it 'returns short name without module prefix' do
      expect(described_logger.safe_type_name([])).to(eq('Array'))
    end
  end
end
