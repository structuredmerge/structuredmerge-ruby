# frozen_string_literal: true

RSpec.describe Ast::Merge::Detector::Mergeable do
  # Create a minimal merger class that includes the module
  let(:merger_class) do
    Class.new do
      include Ast::Merge::Detector::Mergeable

      attr_reader :template_content, :dest_content

      def initialize(template, dest, regions: [], region_placeholder: nil)
        @template_content = template
        @dest_content = dest
        setup_regions(regions: regions, region_placeholder: region_placeholder)
      end

      def merge
        # Simple passthrough merge for testing
        @dest_content
      end
    end
  end

  # Create a mock merger class for region merging
  let(:mock_region_merger_class) do
    Class.new do
      def initialize(template, dest, **options)
        @template = template
        @dest = dest
        @options = options
      end

      def merge
        # Simple merge: prefer dest, or template if dest empty
        @dest.empty? ? @template : @dest
      end
    end
  end

  describe '#setup_regions' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    it 'configures region detection' do
      merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
      expect(merger.regions_configured?).to be true
    end

    it 'handles empty regions array' do
      merger = merger_class.new('t', 'd', regions: [])
      expect(merger.regions_configured?).to be false
    end

    it 'handles nil regions' do
      merger = merger_class.new('t', 'd', regions: nil)
      expect(merger.regions_configured?).to be false
    end

    it 'accepts custom placeholder' do
      merger = merger_class.new('t', 'd', regions: [{ detector: detector }], region_placeholder: '###CUSTOM_')
      expect(merger.instance_variable_get(:@region_placeholder_prefix)).to eq('###CUSTOM_')
    end
  end

  describe '#regions_configured?' do
    it 'returns false when no regions configured' do
      merger = merger_class.new('t', 'd')
      expect(merger.regions_configured?).to be false
    end

    it 'returns true when regions configured' do
      detector = Ast::Merge::Detector::YamlFrontmatter.new
      merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
      expect(merger.regions_configured?).to be true
    end
  end

  describe '#extract_template_regions' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    context 'with no regions configured' do
      it 'returns content unchanged' do
        merger = merger_class.new('template', 'dest')
        result = merger.extract_template_regions('template')
        expect(result).to eq('template')
      end
    end

    context 'with regions configured' do
      let(:source) do
        <<~MD
          ---
          title: Test
          ---
          # Body
        MD
      end

      it 'extracts regions and replaces with placeholders' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        result = merger.extract_template_regions(source)

        expect(result).to include('<<<AST_MERGE_REGION_')
        expect(result).not_to include('---')
        expect(result).to include('# Body')
      end

      it 'stores extracted regions' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        merger.extract_template_regions(source)

        extracted = merger.instance_variable_get(:@extracted_template_regions)
        expect(extracted.size).to eq(1)
        expect(extracted.first.region.content).to eq("title: Test\n")
      end
    end

    context 'with placeholder collision' do
      let(:source) do
        'Content with <<<AST_MERGE_REGION_0>>> in it'
      end

      it 'raises PlaceholderCollisionError' do
        merger = merger_class.new('t', 'd', regions: [{ detector: Ast::Merge::Detector::YamlFrontmatter.new }])

        expect do
          merger.extract_template_regions(source)
        end.to raise_error(Ast::Merge::PlaceholderCollisionError)
      end

      it 'can be avoided with custom placeholder' do
        merger = merger_class.new(
          't',
          'd',
          regions: [{ detector: Ast::Merge::Detector::YamlFrontmatter.new }],
          region_placeholder: '###MY_PLACEHOLDER_'
        )

        expect do
          merger.extract_template_regions(source)
        end.not_to raise_error
      end
    end
  end

  describe '#extract_dest_regions' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }
    let(:source) do
      <<~MD
        ---
        title: Dest
        ---
        Content
      MD
    end

    it 'extracts regions and replaces with placeholders' do
      merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
      result = merger.extract_dest_regions(source)

      expect(result).to include('<<<AST_MERGE_REGION_')
      expect(result).not_to include('---')
    end

    it 'stores extracted regions separately from template' do
      merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
      merger.extract_template_regions("---\ntitle: T\n---\nT")
      merger.extract_dest_regions(source)

      template_extracted = merger.instance_variable_get(:@extracted_template_regions)
      dest_extracted = merger.instance_variable_get(:@extracted_dest_regions)

      expect(template_extracted.first.region.content).to include('title: T')
      expect(dest_extracted.first.region.content).to include('title: Dest')
    end
  end

  describe '#substitute_merged_regions' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    context 'with no regions configured' do
      it 'returns content unchanged' do
        merger = merger_class.new('t', 'd')
        result = merger.substitute_merged_regions('content')
        expect(result).to eq('content')
      end
    end

    context 'with regions but no merger_class' do
      let(:template) do
        <<~MD
          ---
          title: Template
          ---
          Body
        MD
      end

      let(:dest) do
        <<~MD
          ---
          title: Destination
          author: Jane
          ---
          Body
        MD
      end

      it 'prefers destination content (preserves customizations)' do
        merger = merger_class.new(template, dest, regions: [{ detector: detector }])

        # Extract regions (template_processed not needed for this test)
        merger.extract_template_regions(template)
        dest_processed = merger.extract_dest_regions(dest)

        # Simulate merge - in real use, this would be the merged body
        merged = dest_processed

        result = merger.substitute_merged_regions(merged)

        expect(result).to include('title: Destination')
        expect(result).to include('author: Jane')
      end
    end

    context 'with regions and merger_class' do
      let(:template) do
        <<~MD
          ---
          title: Template
          ---
          Body
        MD
      end

      let(:dest) do
        <<~MD
          ---
          author: Jane
          ---
          Body
        MD
      end

      it 'uses the merger_class to merge region content' do
        merger = merger_class.new(
          template,
          dest,
          regions: [{
            detector: detector,
            merger_class: mock_region_merger_class
          }]
        )

        merger.extract_template_regions(template)
        dest_processed = merger.extract_dest_regions(dest)

        result = merger.substitute_merged_regions(dest_processed)

        # Mock merger prefers dest content
        expect(result).to include('author: Jane')
        expect(result).not_to include('title: Template')
      end
    end
  end

  describe 'Config struct' do
    let(:config_class) { Ast::Merge::Detector::Mergeable::Config }
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    it 'creates with required detector' do
      config = config_class.new(detector: detector)
      expect(config.detector).to eq(detector)
    end

    it 'defaults merger_class to nil' do
      config = config_class.new(detector: detector)
      expect(config.merger_class).to be_nil
    end

    it 'defaults merger_options to empty hash' do
      config = config_class.new(detector: detector)
      expect(config.merger_options).to eq({})
    end

    it 'defaults regions to empty array' do
      config = config_class.new(detector: detector)
      expect(config.regions).to eq([])
    end

    it 'accepts all options' do
      config = config_class.new(
        detector: detector,
        merger_class: mock_region_merger_class,
        merger_options: { foo: :bar },
        regions: [{ detector: detector }]
      )

      expect(config.merger_class).to eq(mock_region_merger_class)
      expect(config.merger_options).to eq({ foo: :bar })
      expect(config.regions.size).to eq(1)
    end
  end

  describe '#build_region_configs' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }
    let(:config_class) { Ast::Merge::Detector::Mergeable::Config }

    context 'when config is already a RegionConfig' do
      it 'passes through unchanged' do
        config = config_class.new(detector: detector)
        merger = merger_class.new('t', 'd', regions: [config])

        configs = merger.instance_variable_get(:@region_configs)
        expect(configs.first).to eq(config)
      end
    end

    context 'when config is an invalid type' do
      it 'raises ArgumentError for string config' do
        expect do
          merger_class.new('t', 'd', regions: ['invalid'])
        end.to raise_error(ArgumentError, /Invalid region config/)
      end

      it 'raises ArgumentError for integer config' do
        expect do
          merger_class.new('t', 'd', regions: [123])
        end.to raise_error(ArgumentError, /Invalid region config/)
      end

      it 'raises ArgumentError for array config' do
        expect do
          merger_class.new('t', 'd', regions: [[detector]])
        end.to raise_error(ArgumentError, /Invalid region config/)
      end
    end
  end

  describe 'ExtractedRegion struct' do
    let(:struct_class) { Ast::Merge::Detector::Mergeable::ExtractedRegion }
    let(:region) do
      Ast::Merge::Detector::Region.new(
        type: :yaml_frontmatter,
        content: 'title: Test',
        start_line: 1,
        end_line: 3,
        delimiters: ['---', '---'],
        metadata: {}
      )
    end
    let(:config) do
      Ast::Merge::Detector::Mergeable::Config.new(
        detector: Ast::Merge::Detector::YamlFrontmatter.new
      )
    end

    it 'stores region, config, and placeholder' do
      extracted = struct_class.new(
        region: region,
        config: config,
        placeholder: '<<<TEST>>>',
        merged_content: nil
      )

      expect(extracted.region).to eq(region)
      expect(extracted.config).to eq(config)
      expect(extracted.placeholder).to eq('<<<TEST>>>')
      expect(extracted.merged_content).to be_nil
    end
  end

  describe 'multiple region types' do
    let(:yaml_detector) { Ast::Merge::Detector::YamlFrontmatter.new }
    let(:ruby_detector) { Ast::Merge::Detector::FencedCodeBlock.ruby }

    let(:source) do
      <<~MD
        ---
        title: Test
        ---

        # Header

        ```ruby
        def hello
          puts "world"
        end
        ```
      MD
    end

    it 'extracts multiple region types' do
      merger = merger_class.new(
        't',
        'd',
        regions: [
          { detector: yaml_detector },
          { detector: ruby_detector }
        ]
      )

      merger.extract_template_regions(source)
      extracted = merger.instance_variable_get(:@extracted_template_regions)

      expect(extracted.size).to eq(2)
      expect(extracted.map { |e| e.region.type }).to contain_exactly(:yaml_frontmatter, :ruby_code_block)
    end
  end

  describe '#merge_region edge cases' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }
    let(:config_class) { Ast::Merge::Detector::Mergeable::Config }
    let(:extracted_class) { Ast::Merge::Detector::Mergeable::ExtractedRegion }

    context 'when both template and dest extracted are nil' do
      it 'returns nil' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        result = merger.send(:merge_region, nil, nil)
        expect(result).to be_nil
      end
    end

    context 'when only template region exists' do
      let(:template_region) do
        Ast::Merge::Detector::Region.new(
          type: :yaml_frontmatter,
          content: "title: Template\n",
          start_line: 1,
          end_line: 3,
          delimiters: ['---', '---'],
          metadata: {}
        )
      end

      let(:config) { config_class.new(detector: detector) }

      let(:template_extracted) do
        extracted_class.new(
          region: template_region,
          config: config,
          placeholder: '<<<P>>>',
          merged_content: nil
        )
      end

      it 'returns template text when dest is empty' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        result = merger.send(:merge_region, template_extracted, nil)
        expect(result).to include('title: Template')
      end
    end

    context 'when only dest region exists' do
      let(:dest_region) do
        Ast::Merge::Detector::Region.new(
          type: :yaml_frontmatter,
          content: "author: Jane\n",
          start_line: 1,
          end_line: 3,
          delimiters: ['---', '---'],
          metadata: {}
        )
      end

      let(:config) { config_class.new(detector: detector) }

      let(:dest_extracted) do
        extracted_class.new(
          region: dest_region,
          config: config,
          placeholder: '<<<P>>>',
          merged_content: nil
        )
      end

      it 'returns dest text' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        result = merger.send(:merge_region, nil, dest_extracted)
        expect(result).to include('author: Jane')
      end
    end

    context 'with merger_class configured' do
      let(:template_region) do
        Ast::Merge::Detector::Region.new(
          type: :yaml_frontmatter,
          content: "title: Template\n",
          start_line: 1,
          end_line: 3,
          delimiters: ['---', '---'],
          metadata: {}
        )
      end

      let(:dest_region) do
        Ast::Merge::Detector::Region.new(
          type: :yaml_frontmatter,
          content: "title: Dest\nauthor: Jane\n",
          start_line: 1,
          end_line: 4,
          delimiters: ['---', '---'],
          metadata: {}
        )
      end

      let(:config) do
        config_class.new(
          detector: detector,
          merger_class: mock_region_merger_class
        )
      end

      let(:template_extracted) do
        extracted_class.new(
          region: template_region,
          config: config,
          placeholder: '<<<P>>>',
          merged_content: nil
        )
      end

      let(:dest_extracted) do
        extracted_class.new(
          region: dest_region,
          config: config,
          placeholder: '<<<P>>>',
          merged_content: nil
        )
      end

      it 'uses the merger_class to merge content' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector, merger_class: mock_region_merger_class }])
        result = merger.send(:merge_region, template_extracted, dest_extracted)
        # mock_region_merger_class prefers dest content
        expect(result).to include('title: Dest')
      end
    end
  end

  describe '#reconstruct_region_with_delimiters edge cases' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    context 'when region has no delimiters' do
      let(:region) do
        Ast::Merge::Detector::Region.new(
          type: :raw,
          content: 'raw content',
          start_line: 1,
          end_line: 1,
          delimiters: nil,
          metadata: {}
        )
      end

      it 'returns content as-is' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        result = merger.send(:reconstruct_region_with_delimiters, region, 'new content')
        expect(result).to eq('new content')
      end
    end

    context "when content doesn't end with newline" do
      let(:region) do
        Ast::Merge::Detector::Region.new(
          type: :yaml_frontmatter,
          content: 'title: Test',
          start_line: 1,
          end_line: 3,
          delimiters: ['---', '---'],
          metadata: {}
        )
      end

      it 'adds newline before closing delimiter' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        result = merger.send(:reconstruct_region_with_delimiters, region, 'title: New')
        expect(result).to eq("---\ntitle: New\n---\n")
      end
    end

    context 'when content ends with newline' do
      let(:region) do
        Ast::Merge::Detector::Region.new(
          type: :yaml_frontmatter,
          content: "title: Test\n",
          start_line: 1,
          end_line: 3,
          delimiters: ['---', '---'],
          metadata: {}
        )
      end

      it "doesn't add extra newline" do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        result = merger.send(:reconstruct_region_with_delimiters, region, "title: New\n")
        expect(result).to eq("---\ntitle: New\n---\n")
      end
    end
  end

  describe '#validate_no_placeholder_collision!' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    context 'with nil content' do
      it 'does not raise' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        expect do
          merger.send(:validate_no_placeholder_collision!, nil)
        end.not_to raise_error
      end
    end

    context 'with empty content' do
      it 'does not raise' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        expect do
          merger.send(:validate_no_placeholder_collision!, '')
        end.not_to raise_error
      end
    end
  end

  describe '#replace_region_with_placeholder edge cases' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }

    context 'with LF line endings (not CRLF)' do
      let(:source_with_lf) { "line1\nline2\nline3\n" }
      let(:region) do
        Ast::Merge::Detector::Region.new(
          type: :test,
          content: 'line2',
          start_line: 2,
          end_line: 2,
          delimiters: nil,
          metadata: {}
        )
      end

      it 'uses LF newlines for placeholder' do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
        result = merger.send(:replace_region_with_placeholder, source_with_lf, region, '<<<PLACEHOLDER>>>')
        expect(result).to include("<<<PLACEHOLDER>>>\n")
        expect(result).not_to include("\r\n")
      end
    end
  end

  describe '#merge_region when merge_region returns nil' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }
    let(:config_class) { Ast::Merge::Detector::Mergeable::Config }
    let(:extracted_class) { Ast::Merge::Detector::Mergeable::ExtractedRegion }

    context 'when both template and dest extracted have nil config' do
      it "returns nil and doesn't substitute" do
        merger = merger_class.new('t', 'd', regions: [{ detector: detector }])

        # Directly test merge_region returning nil
        result = merger.send(:merge_region, nil, nil)
        expect(result).to be_nil
      end
    end
  end

  describe '#merge_region with regions in config' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }
    let(:config_class) { Ast::Merge::Detector::Mergeable::Config }
    let(:extracted_class) { Ast::Merge::Detector::Mergeable::ExtractedRegion }

    let(:template_region) do
      Ast::Merge::Detector::Region.new(
        type: :yaml_frontmatter,
        content: "title: Template\n",
        start_line: 1,
        end_line: 3,
        delimiters: ['---', '---'],
        metadata: {}
      )
    end

    let(:dest_region) do
      Ast::Merge::Detector::Region.new(
        type: :yaml_frontmatter,
        content: "title: Dest\n",
        start_line: 1,
        end_line: 3,
        delimiters: ['---', '---'],
        metadata: {}
      )
    end

    context 'when config has nested regions' do
      let(:nested_detector) { Ast::Merge::Detector::FencedCodeBlock.ruby }
      let(:config) do
        config_class.new(
          detector: detector,
          merger_class: mock_region_merger_class,
          regions: [{ detector: nested_detector }]
        )
      end

      let(:template_extracted) do
        extracted_class.new(
          region: template_region,
          config: config,
          placeholder: '<<<P>>>',
          merged_content: nil
        )
      end

      let(:dest_extracted) do
        extracted_class.new(
          region: dest_region,
          config: config,
          placeholder: '<<<P>>>',
          merged_content: nil
        )
      end

      it 'passes nested regions to the merger' do
        merger = merger_class.new('t', 'd', regions: [
                                    { detector: detector, merger_class: mock_region_merger_class, regions: [{ detector: nested_detector }] }
                                  ])
        result = merger.send(:merge_region, template_extracted, dest_extracted)
        expect(result).not_to be_nil
      end
    end
  end

  describe '#merge_region with dest_text empty' do
    let(:detector) { Ast::Merge::Detector::YamlFrontmatter.new }
    let(:config_class) { Ast::Merge::Detector::Mergeable::Config }
    let(:extracted_class) { Ast::Merge::Detector::Mergeable::ExtractedRegion }

    let(:template_region) do
      Ast::Merge::Detector::Region.new(
        type: :yaml_frontmatter,
        content: "title: Template\n",
        start_line: 1,
        end_line: 3,
        delimiters: ['---', '---'],
        metadata: {}
      )
    end

    # Empty region with no content
    let(:dest_region) do
      Ast::Merge::Detector::Region.new(
        type: :yaml_frontmatter,
        content: '',
        start_line: 1,
        end_line: 2,
        delimiters: ['---', '---'],
        metadata: {}
      )
    end

    let(:config) { config_class.new(detector: detector) }

    let(:template_extracted) do
      extracted_class.new(
        region: template_region,
        config: config,
        placeholder: '<<<P>>>',
        merged_content: nil
      )
    end

    let(:dest_extracted) do
      extracted_class.new(
        region: dest_region,
        config: config,
        placeholder: '<<<P>>>',
        merged_content: nil
      )
    end

    it 'returns template text when dest region has empty full_text' do
      # Override full_text to return empty
      allow(dest_region).to receive(:full_text).and_return('')

      merger = merger_class.new('t', 'd', regions: [{ detector: detector }])
      result = merger.send(:merge_region, template_extracted, dest_extracted)
      expect(result).to include('title: Template')
    end
  end
end
