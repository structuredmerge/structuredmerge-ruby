# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ast::Merge::FileAlignerBase do
  before do
    stub_const('BaseAligner', described_class)
    stub_const('Analysis', Struct.new(:statements, :signatures) do
      def signature_at(index)
        signatures[index]
      end

      def generate_signature(node)
        node[:signature]
      end
    end)
    stub_const('FixtureAnalysis', Struct.new(:statements) do
      def signature_at(index)
        statements.fetch(index).fetch(:primary_signature)
      end

      def generate_signature(node)
        node.fetch(:primary_signature)
      end
    end)
    stub_const('TestAligner', Class.new(described_class) do
      attr_reader :logged_alignment

      private

      def template_only_entry_context(template_index:, matched_entries_by_template_position:, **)
        _previous_match, next_match = surrounding_matched_entries(matched_entries_by_template_position, template_index)
        {
          anchor_dest_index: next_match&.[](:dest_index),
          anchor_position: next_match ? :before : :append
        }
      end

      def log_alignment(alignment)
        @logged_alignment = alignment
      end
    end)
    stub_const('AliasAligner', Class.new(described_class) do
      private

      def template_entry_key
        :template_decl
      end

      def dest_entry_key
        :dest_decl
      end

      def add_signature_aliases(map, statement, index, _analysis)
        Array(statement[:aliases]).each do |signature|
          map[signature] << index if signature
        end
      end
    end)
  end

  let(:template_statements) do
    [
      { name: :a },
      { name: :middle },
      { name: :b }
    ]
  end
  let(:dest_statements) do
    [
      { name: :a },
      { name: :b }
    ]
  end
  let(:template_analysis) do
    Analysis.new(
      template_statements,
      {
        0 => %i[sig a],
        1 => %i[sig middle],
        2 => %i[sig b]
      }
    )
  end
  let(:dest_analysis) do
    Analysis.new(
      dest_statements,
      {
        0 => %i[sig a],
        1 => %i[sig b]
      }
    )
  end

  describe '#align' do
    it 'matches statements pairwise by signature and appends unmatched template statements by default' do
      result = TestAligner.new(template_analysis, dest_analysis).align

      expect(result.map { |entry| [entry[:type], entry[:template_index], entry[:dest_index]] }).to eq([
                                                                                                        [:match, 0, 0],
                                                                                                        [:match, 2, 1],
                                                                                                        [
                                                                                                          :template_only, 1, nil
                                                                                                        ]
                                                                                                      ])
    end

    it 'adds template-only anchor metadata using surrounding matched entries' do
      result = TestAligner.new(template_analysis, dest_analysis).align
      template_only = result.find { |entry| entry[:type] == :template_only }

      expect(template_only[:anchor_dest_index]).to eq(1)
      expect(template_only[:anchor_position]).to eq(:before)
    end

    it 'preserves unmatched nil-signature statements as template-only entries' do
      nil_sig_analysis = Analysis.new([{ name: :custom }], { 0 => nil })

      result = BaseAligner.new(nil_sig_analysis, Analysis.new([], {})).align

      expect(result).to eq([
                             {
                               type: :template_only,
                               template_index: 0,
                               dest_index: nil,
                               signature: nil,
                               template_node: { name: :custom },
                               dest_node: nil
                             }
                           ])
    end

    it 'pairs duplicate signatures in order and leaves extra template statements unmatched' do
      duplicate_template_analysis = Analysis.new([{ id: 1 }, { id: 2 }], { 0 => [:dup], 1 => [:dup] })
      duplicate_dest_analysis = Analysis.new([{ id: :dest }], { 0 => [:dup] })

      result = BaseAligner.new(duplicate_template_analysis, duplicate_dest_analysis).align

      expect(result.count { |entry| entry[:type] == :match }).to eq(1)
      expect(result.count { |entry| entry[:type] == :template_only }).to eq(1)
    end

    it 'does not duplicate matches through content aliases after primary signatures match' do
      template_statement = { name: :template, normalized_content: 'same' }
      dest_statement = { name: :dest, normalized_content: 'same' }
      template_analysis = Analysis.new([template_statement], { 0 => [:primary] })
      dest_analysis = Analysis.new([dest_statement], { 0 => [:primary] })

      result = BaseAligner.new(template_analysis, dest_analysis).align

      expect(result).to eq([
                             {
                               type: :match,
                               template_index: 0,
                               dest_index: 0,
                               signature: [:primary],
                               template_node: template_statement,
                               dest_node: dest_statement
                             }
                           ])
    end

    it 'matches identical content when opaque primary signatures differ by source position' do
      fixture_path = Pathname(__dir__).join(
        '..',
        '..',
        '..',
        '..',
        '..',
        '..',
        'fixtures',
        'diagnostics',
        'slice-904-content-identity-positional-signature',
        'content-identity-positional-signature.json'
      ).expand_path
      fixture = Ast::Merge.normalize_value(JSON.parse(fixture_path.read))
      template_analysis = FixtureAnalysis.new(fixture.dig(:matching, :template_nodes))
      dest_analysis = FixtureAnalysis.new(fixture.dig(:matching, :destination_nodes))

      result = BaseAligner.new(template_analysis, dest_analysis).align

      expect(result.count { |entry| entry[:type] == :match }).to eq(fixture.dig(:expected, :match_count))
      expect(result.count { |entry| entry[:type] == :template_only }).to eq(
        fixture.dig(:expected, :template_only_count)
      )
      expect(result.count { |entry| entry[:type] == :dest_only }).to eq(fixture.dig(:expected, :dest_only_count))
      match = result.find { |entry| entry[:type] == :match }
      expected_signature = fixture.dig(:expected, :first_match_signature)
      expect(match[:signature]).to eq([expected_signature.first.to_sym, *expected_signature.drop(1)])
      expect(match[:template_index]).to eq(fixture.dig(:expected, :first_template_index))
      expect(match[:dest_index]).to eq(fixture.dig(:expected, :first_dest_index))
    end

    it 'supports optional fuzzy refinement for otherwise unmatched statements' do
      template_statement = { name: :template_table }
      dest_statement = { name: :dest_table }
      refined_template_analysis = Analysis.new([template_statement], { 0 => %i[table template] })
      refined_dest_analysis = Analysis.new([dest_statement], { 0 => %i[table dest] })
      match = Struct.new(:template_node, :dest_node, :score).new(template_statement, dest_statement, 0.9)
      refiner = lambda do |template_nodes, dest_nodes, context|
        expect(template_nodes).to eq([template_statement])
        expect(dest_nodes).to eq([dest_statement])
        expect(context[:template_analysis]).to eq(refined_template_analysis)
        expect(context[:dest_analysis]).to eq(refined_dest_analysis)
        [match]
      end

      result = BaseAligner.new(refined_template_analysis, refined_dest_analysis, match_refiner: refiner).align

      expect(result).to eq([
                             {
                               type: :match,
                               template_index: 0,
                               dest_index: 0,
                               signature: [:refined_match, 0.9],
                               template_node: template_statement,
                               dest_node: dest_statement
                             }
                           ])
    end

    it 'supports additional signature aliases and custom payload keys in subclasses' do
      template_statement = { name: :template, aliases: [%i[alias foo]] }
      dest_statement = { name: :dest }
      alias_template_analysis = Analysis.new([template_statement], { 0 => %i[primary bar] })
      alias_dest_analysis = Analysis.new([dest_statement], { 0 => %i[alias foo] })

      result = AliasAligner.new(alias_template_analysis, alias_dest_analysis).align

      expect(result).to eq([
                             {
                               type: :match,
                               template_index: 0,
                               dest_index: 0,
                               signature: %i[alias foo],
                               template_decl: template_statement,
                               dest_decl: dest_statement
                             }
                           ])
    end

    it 'calls the logging hook with the final sorted alignment' do
      aligner = TestAligner.new(template_analysis, dest_analysis)
      result = aligner.align

      expect(aligner.logged_alignment).to eq(result)
    end
  end

  describe '#build_signature_map' do
    it 'collects statement indices by signature and skips nil signatures' do
      analysis = Analysis.new([{ name: :one }, { name: :two }], { 0 => [:one], 1 => nil })
      aligner = BaseAligner.new(analysis, Analysis.new([], {}))

      expect(aligner.send(:build_signature_map, analysis.statements, analysis)).to eq({ [:one] => [0] })
    end
  end
end
