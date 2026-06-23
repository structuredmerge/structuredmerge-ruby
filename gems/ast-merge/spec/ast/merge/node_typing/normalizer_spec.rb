# frozen_string_literal: true

# -- This spec tests thread safety and requires creating threads
RSpec.describe Ast::Merge::NodeTyping::Normalizer do
  # Create a test module that extends Normalizer for testing
  let(:test_normalizer) do
    Module.new do
      extend Ast::Merge::NodeTyping::Normalizer

      configure_normalizer(
        backend_a: {
          raw_heading: :heading,
          raw_paragraph: :paragraph,
          raw_code: :code_block
        }.freeze,
        backend_b: {
          h1: :heading,
          h2: :heading,
          para: :paragraph,
          code: :code_block
        }.freeze
      )
    end
  end

  describe '.extended' do
    it 'sets up instance variables when extending a module' do
      new_module = Module.new { extend Ast::Merge::NodeTyping::Normalizer }

      expect(new_module.instance_variable_get(:@normalizer_mutex)).to be_a(Mutex)
      expect(new_module.instance_variable_get(:@backend_mappings)).to eq({})
    end
  end

  describe '#configure_normalizer' do
    it 'configures initial backend mappings' do
      expect(test_normalizer.registered_backends).to contain_exactly(:backend_a, :backend_b)
    end

    it 'freezes mappings that are not already frozen' do
      new_module = Module.new do
        extend Ast::Merge::NodeTyping::Normalizer

        configure_normalizer(
          test_backend: { unfrozen: :type }
        )
      end

      mappings = new_module.mappings_for(:test_backend)
      expect(mappings).to be_frozen
    end

    it 'preserves already frozen mappings' do
      frozen_hash = { already: :frozen }.freeze
      new_module = Module.new do
        extend Ast::Merge::NodeTyping::Normalizer

        configure_normalizer(test_backend: frozen_hash)
      end

      expect(new_module.mappings_for(:test_backend)).to be(frozen_hash)
    end
  end

  describe '#register_backend' do
    it 'registers a new backend at runtime' do
      test_normalizer.register_backend(:backend_c, {
                                         new_type: :heading
                                       })

      expect(test_normalizer.backend_registered?(:backend_c)).to be true
      expect(test_normalizer.canonical_type(:new_type, :backend_c)).to eq(:heading)
    end

    it 'freezes the mappings' do
      test_normalizer.register_backend(:frozen_test, { test: :value })

      expect(test_normalizer.mappings_for(:frozen_test)).to be_frozen
    end

    it 'converts backend name to symbol' do
      test_normalizer.register_backend('string_backend', { a: :b })

      expect(test_normalizer.backend_registered?(:string_backend)).to be true
    end

    it 'is thread-safe' do
      threads = 10.times.map do |i|
        Thread.new do
          test_normalizer.register_backend(:"thread_backend_#{i}", { type: :value })
        end
      end
      threads.each(&:join)

      10.times do |i|
        expect(test_normalizer.backend_registered?(:"thread_backend_#{i}")).to be true
      end
    end
  end

  describe '#canonical_type' do
    it 'returns the canonical type for a mapped backend type' do
      expect(test_normalizer.canonical_type(:raw_heading, :backend_a)).to eq(:heading)
      expect(test_normalizer.canonical_type(:h1, :backend_b)).to eq(:heading)
    end

    it 'returns the original type when no mapping exists (passthrough)' do
      expect(test_normalizer.canonical_type(:unknown_type, :backend_a)).to eq(:unknown_type)
    end

    it 'returns nil when backend_type is nil' do
      expect(test_normalizer.canonical_type(nil, :backend_a)).to be_nil
    end

    it 'converts string backend_type to symbol for lookup' do
      expect(test_normalizer.canonical_type('raw_heading', :backend_a)).to eq(:heading)
    end

    it 'returns original type when backend is not registered' do
      expect(test_normalizer.canonical_type(:some_type, :nonexistent_backend)).to eq(:some_type)
    end

    it 'is thread-safe for concurrent reads' do
      # Use Queue for thread-safe result collection
      results = Queue.new
      threads = 100.times.map do
        Thread.new do
          results << test_normalizer.canonical_type(:raw_heading, :backend_a)
        end
      end
      threads.each(&:join)

      # Convert Queue to array for assertion
      results_array = []
      results_array << results.pop until results.empty?

      expect(results_array).to all(eq(:heading))
    end
  end

  describe '#wrap' do
    let(:mock_node) do
      double('MockNode', type: :raw_heading)
    end

    it 'wraps a node with its canonical type as merge_type' do
      wrapped = test_normalizer.wrap(mock_node, :backend_a)

      expect(wrapped).to be_a(Ast::Merge::NodeTyping::Wrapper)
      expect(wrapped.merge_type).to eq(:heading)
      expect(wrapped.node).to eq(mock_node)
    end

    it 'uses passthrough when no mapping exists' do
      unmapped_node = double('UnmappedNode', type: :custom_type)
      wrapped = test_normalizer.wrap(unmapped_node, :backend_a)

      expect(wrapped.merge_type).to eq(:custom_type)
    end
  end

  describe '#registered_backends' do
    it 'returns all registered backend identifiers' do
      backends = test_normalizer.registered_backends

      expect(backends).to include(:backend_a)
      expect(backends).to include(:backend_b)
    end
  end

  describe '#backend_registered?' do
    it 'returns true for registered backends' do
      expect(test_normalizer.backend_registered?(:backend_a)).to be true
      expect(test_normalizer.backend_registered?(:backend_b)).to be true
    end

    it 'returns false for unregistered backends' do
      expect(test_normalizer.backend_registered?(:nonexistent)).to be false
    end

    it 'converts string to symbol for lookup' do
      expect(test_normalizer.backend_registered?('backend_a')).to be true
    end
  end

  describe '#mappings_for' do
    it 'returns the mappings hash for a registered backend' do
      mappings = test_normalizer.mappings_for(:backend_a)

      expect(mappings).to be_a(Hash)
      expect(mappings[:raw_heading]).to eq(:heading)
      expect(mappings[:raw_paragraph]).to eq(:paragraph)
    end

    it 'returns nil for unregistered backends' do
      expect(test_normalizer.mappings_for(:nonexistent)).to be_nil
    end
  end

  describe '#canonical_types' do
    it 'returns all unique canonical types across all backends' do
      types = test_normalizer.canonical_types

      expect(types).to include(:heading)
      expect(types).to include(:paragraph)
      expect(types).to include(:code_block)
    end

    it 'returns unique values (no duplicates)' do
      types = test_normalizer.canonical_types

      expect(types.size).to eq(types.uniq.size)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent registration and lookup' do
      concurrent_module = Module.new do
        extend Ast::Merge::NodeTyping::Normalizer

        configure_normalizer(initial: { a: :b }.freeze)
      end

      errors = []
      threads = []

      # Writers
      5.times do |i|
        threads << Thread.new do
          concurrent_module.register_backend(:"writer_#{i}", { type: :value })
        rescue StandardError => e
          errors << e
        end
      end

      # Readers
      20.times do
        threads << Thread.new do
          concurrent_module.canonical_type(:a, :initial)
          concurrent_module.registered_backends
          concurrent_module.canonical_types
        rescue StandardError => e
          errors << e
        end
      end

      threads.each(&:join)
      expect(errors).to be_empty
    end
  end

  describe 'isolation between modules' do
    it 'each module has its own backend mappings' do
      module_a = Module.new do
        extend Ast::Merge::NodeTyping::Normalizer

        configure_normalizer(backend: { type_a: :canonical_a }.freeze)
      end

      module_b = Module.new do
        extend Ast::Merge::NodeTyping::Normalizer

        configure_normalizer(backend: { type_b: :canonical_b }.freeze)
      end

      expect(module_a.canonical_type(:type_a, :backend)).to eq(:canonical_a)
      expect(module_a.canonical_type(:type_b, :backend)).to eq(:type_b) # passthrough

      expect(module_b.canonical_type(:type_b, :backend)).to eq(:canonical_b)
      expect(module_b.canonical_type(:type_a, :backend)).to eq(:type_a) # passthrough
    end

    it 'registering a backend in one module does not affect another' do
      module_a = Module.new do
        extend Ast::Merge::NodeTyping::Normalizer
      end

      module_b = Module.new do
        extend Ast::Merge::NodeTyping::Normalizer
      end

      module_a.register_backend(:only_in_a, { x: :y })

      expect(module_a.backend_registered?(:only_in_a)).to be true
      expect(module_b.backend_registered?(:only_in_a)).to be false
    end
  end
end
