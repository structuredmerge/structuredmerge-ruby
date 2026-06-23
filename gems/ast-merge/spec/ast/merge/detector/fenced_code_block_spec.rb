# frozen_string_literal: true

RSpec.describe Ast::Merge::Detector::FencedCodeBlock do
  describe '.new' do
    it 'creates a detector with language' do
      detector = described_class.new('ruby')
      expect(detector.language).to eq('ruby')
    end

    it 'normalizes language to lowercase' do
      detector = described_class.new('RUBY')
      expect(detector.language).to eq('ruby')
    end

    it 'accepts aliases' do
      detector = described_class.new('ruby', aliases: ['rb'])
      expect(detector.aliases).to eq(['rb'])
    end

    it 'normalizes aliases to lowercase' do
      detector = described_class.new('ruby', aliases: %w[RB Ruby])
      expect(detector.aliases).to eq(%w[rb ruby])
    end
  end

  describe '#region_type' do
    it 'returns a symbol based on language' do
      detector = described_class.new('ruby')
      expect(detector.region_type).to eq(:ruby_code_block)
    end

    it 'handles multi-word languages' do
      detector = described_class.new('javascript')
      expect(detector.region_type).to eq(:javascript_code_block)
    end
  end

  describe '#detect_all' do
    let(:detector) { described_class.new('ruby', aliases: ['rb']) }

    context 'with backtick fences' do
      let(:source) do
        <<~MD
          # Header

          ```ruby
          def hello
            puts "world"
          end
          ```

          Some text
        MD
      end

      it 'detects ruby code blocks' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end

      it 'captures the content without delimiters' do
        regions = detector.detect_all(source)
        expect(regions.first.content).to eq("def hello\n  puts \"world\"\nend\n")
      end

      it 'captures correct line numbers' do
        regions = detector.detect_all(source)
        expect(regions.first.start_line).to eq(3)
        expect(regions.first.end_line).to eq(7)
      end

      it 'captures delimiters' do
        regions = detector.detect_all(source)
        expect(regions.first.delimiters).to eq(['```ruby', '```'])
      end

      it 'sets metadata with language' do
        regions = detector.detect_all(source)
        expect(regions.first.metadata[:language]).to eq('ruby')
      end
    end

    context 'with tilde fences' do
      let(:source) do
        <<~MD
          ~~~ruby
          code here
          ~~~
        MD
      end

      it 'detects code blocks with tilde fences' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.delimiters).to eq(['~~~ruby', '~~~'])
      end
    end

    context 'with language alias' do
      let(:source) do
        <<~MD
          ```rb
          code here
          ```
        MD
      end

      it 'detects code blocks using alias' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.metadata[:language]).to eq('rb')
      end
    end

    context 'with multiple code blocks' do
      let(:source) do
        <<~MD
          ```ruby
          first block
          ```

          ```rb
          second block
          ```

          ```python
          should not match
          ```
        MD
      end

      it 'detects all matching blocks' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(2)
      end

      it 'returns blocks in document order' do
        regions = detector.detect_all(source)
        expect(regions.first.content).to eq("first block\n")
        expect(regions.last.content).to eq("second block\n")
      end

      it 'ignores non-matching language blocks' do
        regions = detector.detect_all(source)
        contents = regions.map(&:content)
        expect(contents).not_to include("should not match\n")
      end
    end

    context 'with indented code blocks' do
      let(:source) do
        <<~MD
          - List item
            ```ruby
            indented code
            ```
        MD
      end

      it 'detects indented code blocks' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.content).to eq("indented code\n")
      end

      it 'preserves indentation info in metadata' do
        regions = detector.detect_all(source)
        expect(regions.first.metadata[:indent]).to eq('  ')
      end
    end

    context 'with extended fence markers' do
      let(:source) do
        <<~MD
          `````ruby
          code with many backticks
          ```
          nested backticks preserved
          ```
          `````
        MD
      end

      it 'handles extended fence markers' do
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
        expect(regions.first.content).to include('nested backticks preserved')
      end
    end

    context 'with empty content' do
      it 'returns empty array for nil' do
        expect(detector.detect_all(nil)).to eq([])
      end

      it 'returns empty array for empty string' do
        expect(detector.detect_all('')).to eq([])
      end

      it 'returns empty array when no matches' do
        expect(detector.detect_all('no code blocks here')).to eq([])
      end
    end

    context 'with unclosed code block' do
      let(:source) do
        <<~MD
          ```ruby
          unclosed block
        MD
      end

      it 'does not detect unclosed blocks' do
        regions = detector.detect_all(source)
        expect(regions).to eq([])
      end
    end
  end

  describe 'factory methods' do
    describe '.ruby' do
      let(:detector) { described_class.ruby }

      it 'creates a ruby detector' do
        expect(detector.language).to eq('ruby')
      end

      it 'includes rb alias' do
        expect(detector.aliases).to include('rb')
      end

      it 'detects rb code blocks' do
        source = "```rb\ncode\n```"
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end
    end

    describe '.yaml' do
      let(:detector) { described_class.yaml }

      it 'creates a yaml detector' do
        expect(detector.language).to eq('yaml')
      end

      it 'includes yml alias' do
        expect(detector.aliases).to include('yml')
      end
    end

    describe '.json' do
      let(:detector) { described_class.json }

      it 'creates a json detector' do
        expect(detector.language).to eq('json')
      end
    end

    describe '.toml' do
      let(:detector) { described_class.toml }

      it 'creates a toml detector' do
        expect(detector.language).to eq('toml')
      end
    end

    describe '.mermaid' do
      let(:detector) { described_class.mermaid }

      it 'creates a mermaid detector' do
        expect(detector.language).to eq('mermaid')
      end
    end

    describe '.javascript' do
      let(:detector) { described_class.javascript }

      it 'creates a javascript detector' do
        expect(detector.language).to eq('javascript')
      end

      it 'includes js alias' do
        expect(detector.aliases).to include('js')
      end
    end

    describe '.typescript' do
      let(:detector) { described_class.typescript }

      it 'creates a typescript detector' do
        expect(detector.language).to eq('typescript')
      end

      it 'includes ts alias' do
        expect(detector.aliases).to include('ts')
      end
    end

    describe '.python' do
      let(:detector) { described_class.python }

      it 'creates a python detector' do
        expect(detector.language).to eq('python')
      end

      it 'includes py alias' do
        expect(detector.aliases).to include('py')
      end

      it 'detects python code blocks' do
        source = "```python\ndef hello():\n    pass\n```"
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end

      it 'detects py code blocks' do
        source = "```py\nprint('hi')\n```"
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end
    end

    describe '.bash' do
      let(:detector) { described_class.bash }

      it 'creates a bash detector' do
        expect(detector.language).to eq('bash')
      end

      it 'includes sh, shell, and zsh aliases' do
        expect(detector.aliases).to include('sh')
        expect(detector.aliases).to include('shell')
        expect(detector.aliases).to include('zsh')
      end

      it 'detects bash code blocks' do
        source = "```bash\necho 'hello'\n```"
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end

      it 'detects shell code blocks' do
        source = "```shell\nls -la\n```"
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end
    end

    describe '.sql' do
      let(:detector) { described_class.sql }

      it 'creates a sql detector' do
        expect(detector.language).to eq('sql')
      end

      it 'detects sql code blocks' do
        source = "```sql\nSELECT * FROM users;\n```"
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end
    end

    describe '.html' do
      let(:detector) { described_class.html }

      it 'creates an html detector' do
        expect(detector.language).to eq('html')
      end

      it 'detects html code blocks' do
        source = "```html\n<div>Hello</div>\n```"
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end
    end

    describe '.css' do
      let(:detector) { described_class.css }

      it 'creates a css detector' do
        expect(detector.language).to eq('css')
      end

      it 'detects css code blocks' do
        source = "```css\nbody { color: red; }\n```"
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end
    end

    describe '.markdown' do
      let(:detector) { described_class.markdown }

      it 'creates a markdown detector' do
        expect(detector.language).to eq('markdown')
      end

      it 'includes md alias' do
        expect(detector.aliases).to include('md')
      end

      it 'detects markdown code blocks' do
        source = "```markdown\n# Nested heading\n```"
        regions = detector.detect_all(source)
        expect(regions.size).to eq(1)
      end
    end
  end

  describe '#inspect' do
    let(:detector) { described_class.new('ruby', aliases: ['rb']) }

    it 'includes class name' do
      expect(detector.inspect).to include('FencedCodeBlock')
    end

    it 'includes language' do
      expect(detector.inspect).to include('language=ruby')
    end

    it 'includes aliases when present' do
      expect(detector.inspect).to include('aliases=')
      expect(detector.inspect).to include('rb')
    end

    context 'without aliases' do
      let(:detector) { described_class.new('sql') }

      it 'does not include aliases string' do
        expect(detector.inspect).not_to include('aliases=')
      end
    end
  end

  describe '#matches_language?' do
    let(:detector) { described_class.new('ruby', aliases: ['rb']) }

    it 'matches primary language' do
      expect(detector.matches_language?('ruby')).to be true
    end

    it 'matches aliases' do
      expect(detector.matches_language?('rb')).to be true
    end

    it 'is case insensitive' do
      expect(detector.matches_language?('RUBY')).to be true
      expect(detector.matches_language?('RB')).to be true
    end

    it 'does not match other languages' do
      expect(detector.matches_language?('python')).to be false
    end
  end
end
