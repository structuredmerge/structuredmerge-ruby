# frozen_string_literal: true

RSpec.describe Ast::Merge::Recipe::ScriptLoader do
  let(:tmpdir) { Dir.mktmpdir }
  let(:recipe_path) { File.join(tmpdir, 'test_recipe.yml') }
  let(:scripts_dir) { File.join(tmpdir, 'test_recipe') }

  before do
    FileUtils.mkdir_p(scripts_dir)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '#initialize' do
    context 'with recipe_path' do
      before do
        FileUtils.mkdir_p(scripts_dir)
      end

      it 'determines scripts directory from recipe path' do
        loader = described_class.new(recipe_path: recipe_path)
        expect(loader.base_dir).to eq(scripts_dir)
      end
    end

    context 'without recipe_path' do
      it 'has nil base_dir' do
        loader = described_class.new
        expect(loader.base_dir).to be_nil
      end
    end

    context 'with explicit base_dir' do
      it 'uses the provided base_dir' do
        custom_dir = File.join(tmpdir, 'custom')
        FileUtils.mkdir_p(custom_dir)
        loader = described_class.new(base_dir: custom_dir)
        expect(loader.base_dir).to eq(custom_dir)
      end
    end
  end

  describe '#load_callable' do
    let(:loader) { described_class.new(recipe_path: recipe_path) }

    context 'with nil reference' do
      it 'returns nil' do
        expect(loader.load_callable(nil)).to be_nil
      end
    end

    context 'with existing callable' do
      let(:my_lambda) { ->(x) { x * 2 } }

      it 'returns the callable unchanged' do
        expect(loader.load_callable(my_lambda)).to eq(my_lambda)
      end
    end

    context 'with inline lambda expression' do
      it 'evaluates simple lambda' do
        callable = loader.load_callable('->(x) { x * 2 }')
        expect(callable.call(3)).to eq(6)
      end

      it 'evaluates lambda with keyword syntax' do
        callable = loader.load_callable('lambda { |x| x + 1 }')
        expect(callable.call(5)).to eq(6)
      end

      it 'evaluates proc' do
        callable = loader.load_callable('proc { |x| x.upcase }')
        expect(callable.call('hello')).to eq('HELLO')
      end

      it 'raises ArgumentError for invalid syntax' do
        expect do
          loader.load_callable('->(x { invalid }')
        end.to raise_error(ArgumentError, /syntax/i)
      end

      it "raises ArgumentError if expression doesn't return callable" do
        expect do
          loader.load_callable('"not a callable"')
        end.to raise_error(ArgumentError, /callable/i)
      end
    end

    context 'with script file reference' do
      before do
        File.write(File.join(scripts_dir, 'doubler.rb'), <<~RUBY)
          ->(x) { x * 2 }
        RUBY
      end

      it 'loads and returns the callable from file' do
        callable = loader.load_callable('doubler.rb')
        expect(callable.call(4)).to eq(8)
      end

      it 'caches loaded scripts' do
        callable1 = loader.load_callable('doubler.rb')
        callable2 = loader.load_callable('doubler.rb')
        expect(callable1).to equal(callable2)
      end

      it 'raises ArgumentError for missing file' do
        expect do
          loader.load_callable('nonexistent.rb')
        end.to raise_error(ArgumentError, /not found/i)
      end

      it "raises ArgumentError if script doesn't return callable" do
        File.write(File.join(scripts_dir, 'bad_script.rb'), '"just a string"')
        expect do
          loader.load_callable('bad_script.rb')
        end.to raise_error(ArgumentError, /callable/i)
      end
    end

    context 'with nested script path' do
      before do
        FileUtils.mkdir_p(File.join(scripts_dir, 'typing'))
        File.write(File.join(scripts_dir, 'typing', 'heading.rb'), <<~RUBY)
          lambda { |node| [:custom, :heading] }
        RUBY
      end

      it 'loads scripts from subdirectories' do
        callable = loader.load_callable('typing/heading.rb')
        expect(callable.call(nil)).to eq(%i[custom heading])
      end
    end
  end

  describe '#load_step_callable' do
    let(:loader) { described_class.new(recipe_path: recipe_path) }

    before do
      File.write(File.join(scripts_dir, 'step.rb'), <<~'RUBY')
        lambda do |content:, template_content:, **|
          "#{content}--#{template_content}"
        end
      RUBY
    end

    it 'loads step scripts through the same companion-folder convention' do
      callable = loader.load_step_callable('step.rb')
      expect(callable.call(content: 'dest', template_content: 'tpl')).to eq('dest--tpl')
    end
  end

  describe '#load_callable_hash' do
    let(:loader) { described_class.new(recipe_path: recipe_path) }

    before do
      File.write(File.join(scripts_dir, 'heading.rb'), '->(n) { :heading }')
      File.write(File.join(scripts_dir, 'table.rb'), '->(n) { :table }')
    end

    context 'with nil config' do
      it 'returns nil' do
        expect(loader.load_callable_hash(nil)).to be_nil
      end
    end

    context 'with empty config' do
      it 'returns nil' do
        expect(loader.load_callable_hash({})).to be_nil
      end
    end

    context 'with script references' do
      it 'loads all callables' do
        config = {
          'heading' => 'heading.rb',
          'table' => 'table.rb'
        }
        result = loader.load_callable_hash(config)

        expect(result['heading']).to respond_to(:call)
        expect(result['table']).to respond_to(:call)
        expect(result['heading'].call(nil)).to eq(:heading)
        expect(result['table'].call(nil)).to eq(:table)
      end
    end

    context 'with mixed inline and file references' do
      it 'loads both types' do
        config = {
          'heading' => 'heading.rb',
          'inline' => '->(n) { :inline }'
        }
        result = loader.load_callable_hash(config)

        expect(result['heading'].call(nil)).to eq(:heading)
        expect(result['inline'].call(nil)).to eq(:inline)
      end
    end
  end

  describe '#scripts_available?' do
    context 'when scripts directory exists' do
      let(:loader) { described_class.new(recipe_path: recipe_path) }

      it 'returns true' do
        expect(loader.scripts_available?).to be true
      end
    end

    context "when scripts directory doesn't exist" do
      let(:loader) { described_class.new(recipe_path: File.join(tmpdir, 'no_scripts.yml')) }

      it 'returns false' do
        expect(loader.scripts_available?).to be false
      end
    end
  end

  describe '#available_scripts' do
    let(:loader) { described_class.new(recipe_path: recipe_path) }

    before do
      File.write(File.join(scripts_dir, 'script1.rb'), '->(x) { x }')
      FileUtils.mkdir_p(File.join(scripts_dir, 'subdir'))
      File.write(File.join(scripts_dir, 'subdir', 'script2.rb'), '->(x) { x }')
    end

    it 'lists all scripts including nested' do
      scripts = loader.available_scripts
      expect(scripts).to include('script1.rb')
      expect(scripts).to include('subdir/script2.rb')
    end

    context 'when scripts not available' do
      let(:loader) { described_class.new }

      it 'returns empty array' do
        expect(loader.available_scripts).to eq([])
      end
    end
  end

  describe 'script file with syntax error' do
    let(:loader) { described_class.new(recipe_path: recipe_path) }

    before do
      File.write(File.join(scripts_dir, 'syntax_error.rb'), 'def broken( end')
    end

    it 'raises ArgumentError with syntax details' do
      expect do
        loader.load_callable('syntax_error.rb')
      end.to raise_error(ArgumentError, /syntax error|failed to load/i)
    end
  end

  describe 'resolve_script_path edge cases' do
    context 'with absolute path' do
      let(:loader) { described_class.new(recipe_path: recipe_path) }
      let(:absolute_path) { File.join(tmpdir, 'absolute_script.rb') }

      before do
        File.write(absolute_path, '->(x) { x * 3 }')
      end

      it 'uses absolute path directly' do
        callable = loader.load_callable(absolute_path)
        expect(callable.call(2)).to eq(6)
      end
    end

    context "when base_dir doesn't contain script" do
      let(:loader) { described_class.new }

      it 'falls back to current directory resolution and raises error for missing file' do
        expect do
          loader.load_callable('definitely_nonexistent_script_12345.rb')
        end.to raise_error(ArgumentError, /not found/i)
      end
    end
  end

  describe '#scripts_available? with nil base_dir' do
    let(:loader) { described_class.new }

    it 'returns false' do
      expect(loader.scripts_available?).to be false
    end
  end
end
