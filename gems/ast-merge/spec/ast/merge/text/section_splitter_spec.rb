# frozen_string_literal: true

# - Testing related classes in Text::Section namespace
RSpec.describe Ast::Merge::Text::Section do
  describe '#initialize' do
    subject(:section) do
      described_class.new(
        name: 'Installation',
        header: "## Installation\n",
        body: "Run `gem install`\n",
        start_line: 10,
        end_line: 15,
        metadata: { heading_level: 2 }
      )
    end

    it 'sets name' do
      expect(section.name).to eq('Installation')
    end

    it 'sets header' do
      expect(section.header).to eq("## Installation\n")
    end

    it 'sets body' do
      expect(section.body).to eq("Run `gem install`\n")
    end

    it 'sets start_line' do
      expect(section.start_line).to eq(10)
    end

    it 'sets end_line' do
      expect(section.end_line).to eq(15)
    end

    it 'sets metadata' do
      expect(section.metadata).to eq({ heading_level: 2 })
    end
  end

  describe '#line_range' do
    context 'with start_line and end_line' do
      subject(:section) do
        described_class.new(
          name: 'Test',
          header: nil,
          body: 'content',
          start_line: 5,
          end_line: 10,
          metadata: nil
        )
      end

      it 'returns a Range from start_line to end_line' do
        expect(section.line_range).to eq(5..10)
      end
    end

    context 'without start_line' do
      subject(:section) do
        described_class.new(
          name: 'Test',
          header: nil,
          body: 'content',
          start_line: nil,
          end_line: 10,
          metadata: nil
        )
      end

      it 'returns nil' do
        expect(section.line_range).to be_nil
      end
    end

    context 'without end_line' do
      subject(:section) do
        described_class.new(
          name: 'Test',
          header: nil,
          body: 'content',
          start_line: 5,
          end_line: nil,
          metadata: nil
        )
      end

      it 'returns nil' do
        expect(section.line_range).to be_nil
      end
    end
  end

  describe '#line_count' do
    context 'with valid line range' do
      subject(:section) do
        described_class.new(
          name: 'Test',
          header: nil,
          body: 'content',
          start_line: 5,
          end_line: 10,
          metadata: nil
        )
      end

      it 'returns the line count' do
        expect(section.line_count).to eq(6)
      end
    end

    context 'without line range' do
      subject(:section) do
        described_class.new(
          name: 'Test',
          header: nil,
          body: 'content',
          start_line: nil,
          end_line: nil,
          metadata: nil
        )
      end

      it 'returns nil' do
        expect(section.line_count).to be_nil
      end
    end
  end

  describe '#full_text' do
    context 'with header and body' do
      subject(:section) do
        described_class.new(
          name: 'Test',
          header: "## Test\n",
          body: "Content here\n",
          start_line: 1,
          end_line: 2,
          metadata: nil
        )
      end

      it 'includes header and body' do
        expect(section.full_text).to eq("## Test\nContent here\n")
      end
    end

    context 'without header' do
      subject(:section) do
        described_class.new(
          name: 'Test',
          header: nil,
          body: "Content only\n",
          start_line: 1,
          end_line: 1,
          metadata: nil
        )
      end

      it 'returns only body' do
        expect(section.full_text).to eq("Content only\n")
      end
    end

    context 'with empty body' do
      subject(:section) do
        described_class.new(
          name: 'Test',
          header: "## Header\n",
          body: nil,
          start_line: 1,
          end_line: 1,
          metadata: nil
        )
      end

      it 'returns only header' do
        expect(section.full_text).to eq("## Header\n")
      end
    end
  end

  describe '#preamble?' do
    context 'when name is :preamble' do
      subject(:section) do
        described_class.new(
          name: :preamble,
          header: nil,
          body: 'Content',
          start_line: 1,
          end_line: 5,
          metadata: nil
        )
      end

      it 'returns true' do
        expect(section.preamble?).to be true
      end
    end

    context 'when name is not :preamble' do
      subject(:section) do
        described_class.new(
          name: 'Installation',
          header: nil,
          body: 'Content',
          start_line: 1,
          end_line: 5,
          metadata: nil
        )
      end

      it 'returns false' do
        expect(section.preamble?).to be false
      end
    end
  end

  describe '#normalized_name' do
    it 'handles symbols' do
      section = described_class.new(name: :preamble, header: nil, body: '', start_line: nil, end_line: nil,
                                    metadata: nil)
      expect(section.normalized_name).to eq('preamble')
    end

    it 'strips whitespace and downcases' do
      section = described_class.new(name: '  Installation  ', header: nil, body: '', start_line: nil, end_line: nil,
                                    metadata: nil)
      expect(section.normalized_name).to eq('installation')
    end

    it 'normalizes multiple spaces' do
      section = described_class.new(name: 'Getting   Started', header: nil, body: '', start_line: nil, end_line: nil,
                                    metadata: nil)
      expect(section.normalized_name).to eq('getting started')
    end

    it 'handles nil' do
      section = described_class.new(name: nil, header: nil, body: '', start_line: nil, end_line: nil, metadata: nil)
      expect(section.normalized_name).to eq('')
    end
  end
end

RSpec.describe Ast::Merge::Text::SectionSplitter do
  let(:concrete_splitter_class) do
    Class.new(described_class) do
      def split(content)
        [Ast::Merge::Text::Section.new(name: :preamble, header: nil, body: content, start_line: 1,
                                       end_line: content.lines.length, metadata: nil)]
      end

      def join(sections)
        sections.map(&:full_text).join
      end
    end
  end

  let(:splitter) { concrete_splitter_class.new }

  describe '#initialize' do
    it 'accepts options' do
      splitter = concrete_splitter_class.new(custom: 'option')
      expect(splitter.options).to eq({ custom: 'option' })
    end
  end

  describe '#split' do
    context 'with base class' do
      it 'raises NotImplementedError' do
        base = described_class.new
        expect { base.split('content') }.to raise_error(NotImplementedError, /must be implemented/)
      end
    end

    context 'with concrete subclass' do
      it 'returns sections' do
        sections = splitter.split('hello world')
        expect(sections.length).to eq(1)
        expect(sections.first.body).to eq('hello world')
      end
    end
  end

  describe '#join' do
    context 'with base class' do
      it 'raises NotImplementedError' do
        base = described_class.new
        sections = [Ast::Merge::Text::Section.new(name: :test, header: nil, body: 'content', start_line: nil,
                                                  end_line: nil, metadata: nil)]
        expect { base.join(sections) }.to raise_error(NotImplementedError, /must be implemented/)
      end
    end

    context 'with concrete subclass' do
      it 'reconstructs content' do
        sections = [
          Ast::Merge::Text::Section.new(name: :preamble, header: nil, body: 'hello ', start_line: nil, end_line: nil,
                                        metadata: nil),
          Ast::Merge::Text::Section.new(name: :second, header: "## Second\n", body: 'world', start_line: nil,
                                        end_line: nil, metadata: nil)
        ]
        expect(splitter.join(sections)).to eq("hello ## Second\nworld")
      end
    end
  end

  describe '#normalize_name' do
    it 'handles nil' do
      expect(splitter.normalize_name(nil)).to eq('')
    end

    it 'handles symbols by converting to string' do
      expect(splitter.normalize_name(:preamble)).to eq('preamble')
    end

    it 'strips whitespace' do
      expect(splitter.normalize_name('  test  ')).to eq('test')
    end

    it 'downcases' do
      expect(splitter.normalize_name('UPPER')).to eq('upper')
    end

    it 'normalizes multiple spaces' do
      expect(splitter.normalize_name('hello   world')).to eq('hello world')
    end
  end

  describe '#preference_for_section' do
    context 'with symbol preference' do
      it 'returns the preference directly' do
        expect(splitter.preference_for_section('Any', :template)).to eq(:template)
        expect(splitter.preference_for_section('Other', :destination)).to eq(:destination)
      end
    end

    context 'with hash preference' do
      it 'returns exact match' do
        pref = { 'Installation' => :template, :default => :destination }
        expect(splitter.preference_for_section('Installation', pref)).to eq(:template)
      end

      it 'returns normalized match' do
        pref = { 'installation' => :template, :default => :destination }
        expect(splitter.preference_for_section('  Installation  ', pref)).to eq(:template)
      end

      it 'returns default when no match' do
        pref = { 'Installation' => :template, :default => :destination }
        expect(splitter.preference_for_section('Usage', pref)).to eq(:destination)
      end

      it 'uses DEFAULT_PREFERENCE when no default specified' do
        pref = { 'Installation' => :template }
        expect(splitter.preference_for_section('Usage', pref)).to eq(:destination)
      end
    end
  end

  describe '#section_signature' do
    it 'returns normalized name' do
      section = Ast::Merge::Text::Section.new(name: '  TEST  ', header: nil, body: '', start_line: nil, end_line: nil,
                                              metadata: nil)
      expect(splitter.section_signature(section)).to eq('test')
    end
  end

  describe '#merge_sections' do
    let(:template_section) do
      Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Test (template)\n",
        body: "Template body\n",
        start_line: 1,
        end_line: 2,
        metadata: { source: :template }
      )
    end

    let(:dest_section) do
      Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Test (dest)\n",
        body: "Destination body\n",
        start_line: 10,
        end_line: 11,
        metadata: { source: :dest }
      )
    end

    context 'with :template preference' do
      it 'returns template section' do
        result = splitter.merge_sections(template_section, dest_section, :template)
        expect(result).to eq(template_section)
      end
    end

    context 'with :destination preference' do
      it 'returns destination section' do
        result = splitter.merge_sections(template_section, dest_section, :destination)
        expect(result).to eq(dest_section)
      end
    end

    context 'with unknown preference' do
      it 'defaults to destination section' do
        result = splitter.merge_sections(template_section, dest_section, :unknown)
        expect(result).to eq(dest_section)
      end
    end

    context 'with :merge preference' do
      it 'merges content using default implementation' do
        result = splitter.merge_sections(template_section, dest_section, :merge)
        expect(result.name).to eq('Test')
        expect(result.header).to eq("## Test (template)\n") # template header
        expect(result.body).to eq("Destination body\n") # dest body
      end
    end
  end

  describe '#merge_section_content' do
    it 'uses template header and dest body' do
      template = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Template Header\n",
        body: "Template body\n",
        start_line: 1,
        end_line: 2,
        metadata: { from: :template }
      )
      dest = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Dest Header\n",
        body: "Dest body\n",
        start_line: 10,
        end_line: 11,
        metadata: { from: :dest }
      )

      result = splitter.merge_section_content(template, dest)
      expect(result.header).to eq("## Template Header\n")
      expect(result.body).to eq("Dest body\n")
    end

    it 'handles nil dest metadata' do
      template = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Template Header\n",
        body: "Template body\n",
        start_line: 1,
        end_line: 2,
        metadata: { from: :template }
      )
      dest = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Dest Header\n",
        body: "Dest body\n",
        start_line: 10,
        end_line: 11,
        metadata: nil
      )

      result = splitter.merge_section_content(template, dest)
      # When dest metadata is nil, safe navigation returns nil
      expect(result.metadata).to be_nil
    end

    it 'handles nil template metadata' do
      template = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Template Header\n",
        body: "Template body\n",
        start_line: 1,
        end_line: 2,
        metadata: nil
      )
      dest = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Dest Header\n",
        body: "Dest body\n",
        start_line: 10,
        end_line: 11,
        metadata: { from: :dest }
      )

      result = splitter.merge_section_content(template, dest)
      # Merges dest metadata with empty hash from template
      expect(result.metadata).to eq({ from: :dest })
    end

    it 'handles both nil metadata' do
      template = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Template Header\n",
        body: "Template body\n",
        start_line: 1,
        end_line: 2,
        metadata: nil
      )
      dest = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: nil,
        body: "Dest body\n",
        start_line: 10,
        end_line: 11,
        metadata: nil
      )

      result = splitter.merge_section_content(template, dest)
      expect(result.metadata).to be_nil
      expect(result.header).to eq("## Template Header\n")
    end

    it 'uses dest header when template header is nil' do
      template = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: nil,
        body: "Template body\n",
        start_line: 1,
        end_line: 2,
        metadata: nil
      )
      dest = Ast::Merge::Text::Section.new(
        name: 'Test',
        header: "## Dest Header\n",
        body: "Dest body\n",
        start_line: 10,
        end_line: 11,
        metadata: nil
      )

      result = splitter.merge_section_content(template, dest)
      expect(result.header).to eq("## Dest Header\n")
    end
  end

  describe '#merge_section_lists' do
    let(:template_sections) do
      [
        Ast::Merge::Text::Section.new(name: 'Intro', header: "## Intro\n", body: "T intro\n", start_line: 1,
                                      end_line: 2, metadata: nil),
        Ast::Merge::Text::Section.new(name: 'Install', header: "## Install\n", body: "T install\n", start_line: 3,
                                      end_line: 4, metadata: nil),
        Ast::Merge::Text::Section.new(name: 'NewSection', header: "## New\n", body: "T new\n", start_line: 5,
                                      end_line: 6, metadata: nil)
      ]
    end

    let(:dest_sections) do
      [
        Ast::Merge::Text::Section.new(name: 'Intro', header: "## Intro\n", body: "D intro\n", start_line: 1,
                                      end_line: 2, metadata: nil),
        Ast::Merge::Text::Section.new(name: 'Install', header: "## Install\n", body: "D install\n", start_line: 3,
                                      end_line: 4, metadata: nil),
        Ast::Merge::Text::Section.new(name: 'DestOnly', header: "## DestOnly\n", body: "D custom\n", start_line: 5,
                                      end_line: 6, metadata: nil)
      ]
    end

    context 'with :destination preference' do
      it 'preserves destination content for matching sections' do
        merged = splitter.merge_section_lists(template_sections, dest_sections, preference: :destination)
        intro = merged.find { |s| s.name == 'Intro' }
        expect(intro.body).to eq("D intro\n")
      end

      it 'includes destination-only sections' do
        merged = splitter.merge_section_lists(template_sections, dest_sections, preference: :destination)
        dest_only = merged.find { |s| s.name == 'DestOnly' }
        expect(dest_only).not_to be_nil
        expect(dest_only.body).to eq("D custom\n")
      end

      it 'excludes template-only sections by default' do
        merged = splitter.merge_section_lists(template_sections, dest_sections, preference: :destination)
        new_section = merged.find { |s| s.name == 'NewSection' }
        expect(new_section).to be_nil
      end
    end

    context 'with add_template_only: true' do
      it 'includes template-only sections' do
        merged = splitter.merge_section_lists(template_sections, dest_sections, preference: :destination,
                                                                                add_template_only: true)
        new_section = merged.find { |s| s.name == 'NewSection' }
        expect(new_section).not_to be_nil
        expect(new_section.body).to eq("T new\n")
      end
    end

    context 'with :template preference' do
      it 'uses template content for matching sections' do
        merged = splitter.merge_section_lists(template_sections, dest_sections, preference: :template)
        intro = merged.find { |s| s.name == 'Intro' }
        expect(intro.body).to eq("T intro\n")
      end
    end

    context 'with per-section preferences' do
      it 'applies different preferences per section' do
        pref = {
          :default => :destination,
          'Install' => :template
        }
        merged = splitter.merge_section_lists(template_sections, dest_sections, preference: pref)

        intro = merged.find { |s| s.name == 'Intro' }
        install = merged.find { |s| s.name == 'Install' }

        expect(intro.body).to eq("D intro\n") # destination
        expect(install.body).to eq("T install\n") # template
      end
    end
  end

  describe '#merge' do
    let(:advanced_splitter_class) do
      Class.new(described_class) do
        def split(content)
          sections = []
          lines = content.lines
          current_section = nil
          preamble_lines = []

          lines.each_with_index do |line, index|
            if line.start_with?('## ')
              if current_section
                sections << current_section
              elsif preamble_lines.any?
                sections << Ast::Merge::Text::Section.new(
                  name: :preamble,
                  header: nil,
                  body: preamble_lines.join,
                  start_line: 1,
                  end_line: index,
                  metadata: nil
                )
              end
              current_section = Ast::Merge::Text::Section.new(
                name: line[3..].strip,
                header: line,
                body: '',
                start_line: index + 1,
                end_line: nil,
                metadata: nil
              )
            elsif current_section
              current_section = Ast::Merge::Text::Section.new(
                name: current_section.name,
                header: current_section.header,
                body: current_section.body + line,
                start_line: current_section.start_line,
                end_line: index + 1,
                metadata: nil
              )
            else
              preamble_lines << line
            end
          end

          sections << current_section if current_section
          sections
        end

        def join(sections)
          sections.map(&:full_text).join
        end
      end
    end

    let(:advanced_splitter) { advanced_splitter_class.new }

    let(:template) do
      <<~MD
        ## Installation

        Template install instructions.

        ## Usage

        Template usage.
      MD
    end

    let(:destination) do
      <<~MD
        ## Installation

        Custom install instructions.

        ## Usage

        Custom usage with project-specific info.

        ## Contributing

        Custom contributing section.
      MD
    end

    it 'merges documents preserving destination by default' do
      result = advanced_splitter.merge(template, destination)
      expect(result).to include('Custom install instructions')
      expect(result).to include('Custom usage with project-specific info')
      expect(result).to include('Custom contributing section')
    end

    it 'preserves destination-only sections' do
      result = advanced_splitter.merge(template, destination)
      expect(result).to include('## Contributing')
    end

    it 'excludes template-only sections by default' do
      template_with_extra = "#{template}## NewSection\n\nNew content.\n"
      result = advanced_splitter.merge(template_with_extra, destination)
      expect(result).not_to include('## NewSection')
    end

    it 'includes template-only sections when add_template_only is true' do
      template_with_extra = "#{template}## NewSection\n\nNew content.\n"
      result = advanced_splitter.merge(template_with_extra, destination, add_template_only: true)
      expect(result).to include('## NewSection')
    end

    it 'applies per-section preferences' do
      result = advanced_splitter.merge(template, destination,
                                       preference: { :default => :destination, 'Installation' => :template })
      expect(result).to include('Template install instructions')
      expect(result).to include('Custom usage with project-specific info')
    end
  end

  describe '.validate!' do
    it 'accepts nil' do
      expect { described_class.validate!(nil) }.not_to raise_error
    end

    it 'accepts Hash' do
      expect { described_class.validate!({ key: 'value' }) }.not_to raise_error
    end

    it 'raises for non-Hash' do
      expect { described_class.validate!('string') }.to raise_error(ArgumentError, /must be a Hash/)
    end
  end
end

RSpec.describe Ast::Merge::Text::LineSectionSplitter do
  let(:splitter) { described_class.new(pattern: /^## (.+)$/) }

  describe '#initialize' do
    it 'sets pattern' do
      expect(splitter.pattern).to eq(/^## (.+)$/)
    end

    it 'sets name_capture with default' do
      expect(splitter.name_capture).to eq(1)
    end

    it 'accepts custom name_capture' do
      custom = described_class.new(pattern: /^(##) (.+)$/, name_capture: 2)
      expect(custom.name_capture).to eq(2)
    end
  end

  describe '#split' do
    context 'with markdown headings' do
      let(:content) do
        <<~MD
          # Title

          Intro text.

          ## Installation

          Install steps.

          ## Usage

          Usage info.
        MD
      end

      it 'returns sections for each heading' do
        sections = splitter.split(content)
        names = sections.map(&:name)
        expect(names).to include('Installation')
        expect(names).to include('Usage')
      end

      it 'captures preamble before first matched heading' do
        sections = splitter.split(content)
        preamble = sections.find(&:preamble?)
        expect(preamble).not_to be_nil
        expect(preamble.body).to include('# Title')
        expect(preamble.body).to include('Intro text')
      end

      it 'captures body content after heading' do
        sections = splitter.split(content)
        install = sections.find { |s| s.name == 'Installation' }
        expect(install.body).to include('Install steps')
      end

      it 'sets line numbers' do
        sections = splitter.split(content)
        install = sections.find { |s| s.name == 'Installation' }
        expect(install.start_line).to be > 0
        expect(install.end_line).to be >= install.start_line
      end
    end

    context 'with no matching sections' do
      it 'returns entire content as preamble' do
        sections = splitter.split("just plain text\nwith no headings")
        expect(sections.length).to eq(1)
        expect(sections.first.preamble?).to be true
      end
    end

    context 'with empty content' do
      it 'returns empty array for blank content' do
        sections = splitter.split('')
        expect(sections).to eq([])
      end
    end
  end

  describe '#join' do
    it 'reconstructs content from sections' do
      sections = [
        Ast::Merge::Text::Section.new(name: :preamble, header: nil, body: "Intro\n\n", start_line: nil, end_line: nil,
                                      metadata: nil),
        Ast::Merge::Text::Section.new(name: 'Test', header: "## Test\n", body: "\nContent\n", start_line: nil,
                                      end_line: nil, metadata: nil)
      ]
      expect(splitter.join(sections)).to eq("Intro\n\n## Test\n\nContent\n")
    end
  end

  describe 'roundtrip' do
    let(:content) do
      <<~MD
        ## First

        First content.

        ## Second

        Second content.
      MD
    end

    it 'splits and joins without loss' do
      sections = splitter.split(content)
      result = splitter.join(sections)
      expect(result).to eq(content)
    end
  end
end
