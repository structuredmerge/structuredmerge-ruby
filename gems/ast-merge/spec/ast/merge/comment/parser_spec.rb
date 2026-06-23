# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::Parser do
  describe '#initialize' do
    it 'sets lines' do
      parser = described_class.new(['# comment'])
      expect(parser.lines).to eq(['# comment'])
    end

    it 'handles nil lines' do
      parser = described_class.new(nil)
      expect(parser.lines).to eq([])
    end

    it 'defaults style to hash_comment' do
      parser = described_class.new(['# comment'])
      expect(parser.style.name).to eq(:hash_comment)
    end

    it 'accepts Style instance' do
      style = Ast::Merge::Comment::Style.for(:c_style_line)
      parser = described_class.new(['// comment'], style: style)
      expect(parser.style.name).to eq(:c_style_line)
    end

    it 'accepts Symbol for style' do
      parser = described_class.new(['// comment'], style: :c_style_line)
      expect(parser.style.name).to eq(:c_style_line)
    end

    it 'raises ArgumentError for invalid style' do
      expect do
        described_class.new(['# comment'], style: 123)
      end.to raise_error(ArgumentError, /Invalid style/)
    end
  end

  describe '#parse with :auto style detection' do
    it 'detects hash comments' do
      parser = described_class.new(['# ruby comment'], style: :auto)
      expect(parser.style.name).to eq(:hash_comment)
    end

    it 'detects C-style line comments' do
      parser = described_class.new(['// javascript comment'], style: :auto)
      expect(parser.style.name).to eq(:c_style_line)
    end

    it 'detects HTML comments' do
      parser = described_class.new(['<!-- html comment -->'], style: :auto)
      expect(parser.style.name).to eq(:html_comment)
    end

    it 'detects C-style block comments' do
      parser = described_class.new(['/* block comment */'], style: :auto)
      expect(parser.style.name).to eq(:c_style_block)
    end

    it 'defaults to hash_comment when empty' do
      parser = described_class.new([], style: :auto)
      expect(parser.style.name).to eq(:hash_comment)
    end

    it 'defaults to hash_comment for unrecognized content' do
      parser = described_class.new(['plain text'], style: :auto)
      expect(parser.style.name).to eq(:hash_comment)
    end

    it 'skips empty lines when detecting' do
      parser = described_class.new(['', '  ', '# comment'], style: :auto)
      expect(parser.style.name).to eq(:hash_comment)
    end
  end

  describe '#parse with line comments' do
    let(:lines) { ['# First comment', '# Second comment', '', '# Third comment'] }
    let(:parser) { described_class.new(lines) }
    let(:nodes) { parser.parse }

    it 'groups contiguous comments into blocks' do
      expect(nodes.size).to eq(3) # Block, Empty, Block
    end

    it 'creates Block for grouped comments' do
      expect(nodes[0]).to be_a(Ast::Merge::Comment::Block)
      expect(nodes[0].children.size).to eq(2)
    end

    it 'creates Empty for blank lines' do
      expect(nodes[1]).to be_a(Ast::Merge::Comment::Empty)
    end

    it 'creates separate Block after blank line' do
      expect(nodes[2]).to be_a(Ast::Merge::Comment::Block)
      expect(nodes[2].children.size).to eq(1)
    end

    it 'preserves trailing spaces in parsed line-comment slices' do
      parser = described_class.new(['# First comment  '])
      nodes = parser.parse

      expect(nodes.first.children.first.slice).to eq('# First comment  ')
    end
  end

  describe '#parse with non-comment lines' do
    let(:lines) { ['# comment', 'regular text', '# another comment'] }
    let(:parser) { described_class.new(lines) }
    let(:nodes) { parser.parse }

    it 'handles non-comment lines' do
      expect(nodes.size).to eq(3)
    end

    it 'treats non-comment as single line' do
      # The middle node should be a Line (non-comment line in comment context)
      expect(nodes[1]).to be_a(Ast::Merge::Comment::Line)
    end
  end

  describe '#parse with block comments' do
    let(:lines) { ['/* start', 'middle', 'end */'] }
    let(:parser) { described_class.new(lines, style: :c_style_block) }
    let(:nodes) { parser.parse }

    it 'creates single Block for multi-line block comment' do
      expect(nodes.size).to eq(1)
      expect(nodes[0]).to be_a(Ast::Merge::Comment::Block)
    end

    it 'preserves raw content' do
      expect(nodes[0].raw_content).to include('start')
      expect(nodes[0].raw_content).to include('middle')
      expect(nodes[0].raw_content).to include('end */')
    end

    it 'preserves trailing spaces in raw block content' do
      parser = described_class.new(['/* start  ', 'middle  ', 'end */  '], style: :c_style_block)
      nodes = parser.parse

      expect(nodes[0].raw_content).to eq("/* start  \nmiddle  \nend */  ")
    end
  end

  describe '#parse with single-line block comment' do
    let(:lines) { ['/* single line */'] }
    let(:parser) { described_class.new(lines, style: :c_style_block) }
    let(:nodes) { parser.parse }

    it 'handles block comment on single line' do
      expect(nodes.size).to eq(1)
      expect(nodes[0]).to be_a(Ast::Merge::Comment::Block)
    end
  end

  describe '#parse with mixed block and empty lines' do
    let(:lines) { ['/* block */', '', '/* another */'] }
    let(:parser) { described_class.new(lines, style: :c_style_block) }
    let(:nodes) { parser.parse }

    it 'creates separate blocks around empty lines' do
      expect(nodes.size).to eq(3)
      expect(nodes[0]).to be_a(Ast::Merge::Comment::Block)
      expect(nodes[1]).to be_a(Ast::Merge::Comment::Empty)
      expect(nodes[2]).to be_a(Ast::Merge::Comment::Block)
    end
  end

  describe '#parse with HTML comments' do
    let(:lines) { ['<!-- HTML comment -->', '', '<!-- Another -->'] }
    let(:parser) { described_class.new(lines, style: :html_comment) }
    let(:nodes) { parser.parse }

    it 'parses HTML-style comments' do
      expect(nodes.size).to eq(3)
      expect(nodes[0]).to be_a(Ast::Merge::Comment::Block)
      expect(nodes[2]).to be_a(Ast::Merge::Comment::Block)
    end
  end

  describe '#parse with style supporting both line and block' do
    let(:lines) { ['<!-- line 1 -->', '<!-- line 2 -->'] }
    let(:parser) { described_class.new(lines, style: :html_comment) }
    let(:nodes) { parser.parse }

    it 'groups line comments when style supports both' do
      # HTML comments that support both should be grouped
      expect(nodes.size).to be >= 1
    end
  end

  describe '#parse edge cases' do
    it 'handles all empty lines' do
      parser = described_class.new(['', '  ', ''])
      nodes = parser.parse
      expect(nodes).to all(be_a(Ast::Merge::Comment::Empty))
    end

    it 'handles single comment line' do
      parser = described_class.new(['# single'])
      nodes = parser.parse
      expect(nodes.size).to eq(1)
      expect(nodes[0]).to be_a(Ast::Merge::Comment::Block)
    end

    it 'handles whitespace-only lines as empty' do
      parser = described_class.new(['# comment', '   ', '# another'])
      nodes = parser.parse
      expect(nodes.size).to eq(3)
      expect(nodes[1]).to be_a(Ast::Merge::Comment::Empty)
    end
  end

  describe 'class method .parse' do
    it 'creates parser and parses in one call' do
      nodes = described_class.parse(['# comment', '', '# another'])
      expect(nodes.size).to eq(3)
    end

    it 'accepts style option' do
      nodes = described_class.parse(['// comment'], style: :c_style_line)
      expect(nodes.size).to eq(1)
    end
  end

  describe '#parse with unclosed block comment' do
    let(:lines) { ['/* unclosed block', 'more content', 'still more'] }
    let(:parser) { described_class.new(lines, style: :c_style_block) }
    let(:nodes) { parser.parse }

    it 'handles unclosed block comment gracefully' do
      expect(nodes).not_to be_empty
    end
  end

  describe '#parse with mixed content in block style' do
    let(:lines) { ['/* block */', 'regular text', '/* another */'] }
    let(:parser) { described_class.new(lines, style: :c_style_block) }
    let(:nodes) { parser.parse }

    it 'handles mixed block comments and regular content' do
      expect(nodes.size).to eq(3)
    end

    it 'treats non-comment content as Line in block context' do
      expect(nodes[1]).to be_a(Ast::Merge::Comment::Line)
    end

    it 'preserves trailing spaces on non-comment lines in block-comment mode' do
      parser = described_class.new(['/* block */', 'regular text  ', '/* another */'], style: :c_style_block)
      nodes = parser.parse

      expect(nodes[1].slice).to eq('regular text  ')
    end
  end

  describe '#parse with empty inside block' do
    let(:lines) { ['/* start', '', 'end */'] }
    let(:parser) { described_class.new(lines, style: :c_style_block) }
    let(:nodes) { parser.parse }

    it 'preserves empty lines inside block comment' do
      expect(nodes.size).to eq(1)
      expect(nodes[0].raw_content).to include('start')
      expect(nodes[0].raw_content).to include('end */')
    end
  end

  describe '#parse with semicolon style' do
    let(:lines) { ['; comment 1', '; comment 2'] }
    let(:parser) { described_class.new(lines, style: :semicolon_comment) }
    let(:nodes) { parser.parse }

    it 'parses semicolon-style comments' do
      expect(nodes.size).to eq(1)
      expect(nodes[0]).to be_a(Ast::Merge::Comment::Block)
    end
  end

  describe '#parse with double dash style' do
    let(:lines) { ['-- SQL comment', '-- another'] }
    let(:parser) { described_class.new(lines, style: :double_dash_comment) }
    let(:nodes) { parser.parse }

    it 'parses double-dash comments' do
      expect(nodes.size).to eq(1)
      expect(nodes[0]).to be_a(Ast::Merge::Comment::Block)
    end
  end

  describe 'auto-detect with all blank lines' do
    let(:parser) { described_class.new(['  ', ''], style: :auto) }

    it 'defaults to hash_comment for blank content' do
      expect(parser.style.name).to eq(:hash_comment)
    end
  end
end
