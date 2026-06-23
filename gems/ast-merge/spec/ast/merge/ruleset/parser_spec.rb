# frozen_string_literal: true

RSpec.describe Ast::Merge::Ruleset::Parser do
  describe '.parse' do
    let(:valid_ruleset) do
      <<~RULESET
        # comment

        format toml
        owners line_bound_statements
        match signature
        read native_read_portable_write
        attach normalize_tracked_layout_merge
        comment_style hash_comment
        render toml_pairs_and_tables
        capability inline_comments true
        logical_owner link_definition preserve_if_referenced
        repair comment_ownership_overlap warn
        surface fenced_code_block language_tag
        delegate fenced_code_block by_language
      RULESET
    end

    it 'parses a ruleset into normalized attributes' do
      parsed = described_class.parse(valid_ruleset, path: '/tmp/example.ruleset')

      expect(parsed).to include(
        source: valid_ruleset,
        path: '/tmp/example.ruleset',
        format: :toml,
        owners: :line_bound_statements,
        match: :signature,
        read: :native_read_portable_write,
        attach: :normalize_tracked_layout_merge,
        comment_style: :hash_comment,
        render: :toml_pairs_and_tables
      )
      expect(parsed[:capabilities]).to eq(inline_comments: true)
      expect(parsed[:logical_owners]).to eq(link_definition: :preserve_if_referenced)
      expect(parsed[:repair_policies]).to eq(comment_ownership_overlap: :warn)
      expect(parsed[:surfaces]).to eq([{ name: :fenced_code_block, selector: :language_tag }])
      expect(parsed[:delegation_policies]).to eq([{ surface_name: :fenced_code_block, strategy: :by_language }])
      expect(parsed[:directives].first).to include(name: :format, line_number: 3)
      expect(parsed[:directives].last).to include(name: :delegate)
    end

    it 'rejects old native-read read-strategy names' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read native_read_synthetic_write
          attach normalize_tracked_layout_merge
        RULESET
      end.to raise_error(ArgumentError, /Unknown read strategy/)
    end

    it 'rejects old source-augmented read-strategy names' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read source_augmented_synthetic
          attach normalize_tracked_layout_merge
        RULESET
      end.to raise_error(ArgumentError, /Unknown read strategy/)
    end

    it 'accepts source-augmented portable-write read-strategy names' do
      parsed = described_class.parse(<<~RULESET)
        format toml
        owners line_bound_statements
        match signature
        read source_augmented_portable_write
        attach normalize_tracked_layout_merge
      RULESET

      expect(parsed[:read]).to eq(:source_augmented_portable_write)
    end

    it 'rejects missing required directives' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          read native_read_portable_write
          attach normalize_tracked_layout_merge
        RULESET
      end.to raise_error(ArgumentError, /missing required directives: match/)
    end

    it 'rejects unknown directives' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
          frobnicate yes
        RULESET
      end.to raise_error(ArgumentError, /Unknown directive frobnicate/)
    end

    it 'rejects duplicate logical owner names' do
      expect do
        described_class.parse(<<~RULESET)
          format markdown
          owners link_definitions
          match normalized_reference
          read source_augmented_portable_write
          attach tracker_layout_merge
          logical_owner link_definition preserve_if_referenced
          logical_owner link_definition preserve_always
        RULESET
      end.to raise_error(ArgumentError, /Duplicate logical_owner link_definition/)
    end

    it 'rejects duplicate repair policy names' do
      expect do
        described_class.parse(<<~RULESET)
          format markdown
          owners link_definitions
          match normalized_reference
          read source_augmented_portable_write
          attach tracker_layout_merge
          repair comment_ownership_overlap warn
          repair comment_ownership_overlap error
        RULESET
      end.to raise_error(ArgumentError, /Duplicate repair comment_ownership_overlap/)
    end

    it 'rejects duplicate surface names' do
      expect do
        described_class.parse(<<~RULESET)
          format markdown
          owners link_definitions
          match normalized_reference
          read source_augmented_portable_write
          attach tracker_layout_merge
          surface fenced_code_block language_tag
          surface fenced_code_block fixed_kind
        RULESET
      end.to raise_error(ArgumentError, /Duplicate surface fenced_code_block/)
    end

    it 'rejects duplicate delegation policies for the same surface' do
      expect do
        described_class.parse(<<~RULESET)
          format markdown
          owners link_definitions
          match normalized_reference
          read source_augmented_portable_write
          attach tracker_layout_merge
          delegate fenced_code_block by_language
          delegate fenced_code_block same_ruleset
        RULESET
      end.to raise_error(ArgumentError, /Duplicate delegate fenced_code_block/)
    end
  end
end
