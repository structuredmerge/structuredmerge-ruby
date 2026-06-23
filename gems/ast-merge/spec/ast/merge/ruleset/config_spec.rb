# frozen_string_literal: true

RSpec.describe Ast::Merge::Ruleset::Config do
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
      capability quoted_hash_inline_literals false
      logical_owner link_definition preserve_if_referenced
      repair comment_ownership_overlap warn
      surface fenced_code_block language_tag
      delegate fenced_code_block by_language
    RULESET
  end

  describe '.parse' do
    it 'parses a valid compact ruleset' do
      ruleset = described_class.parse(valid_ruleset)

      expect(ruleset.to_h).to include(
        format: :toml,
        owners: :line_bound_statements,
        match: :signature,
        read: :native_read_portable_write,
        attach: :normalize_tracked_layout_merge,
        comment_style: :hash_comment,
        render: :toml_pairs_and_tables
      )
      expect(ruleset.capabilities).to eq(
        inline_comments: true,
        quoted_hash_inline_literals: false
      )
      expect(ruleset.logical_owners).to eq(
        link_definition: :preserve_if_referenced
      )
      expect(ruleset.repair_policies.map(&:to_h)).to eq(
        [{ kind: :comment_ownership_overlap, handling: :warn, metadata: {} }]
      )
      expect(ruleset.surfaces.map(&:to_h)).to eq(
        [{ name: :fenced_code_block, selector: :language_tag, metadata: {} }]
      )
      expect(ruleset.delegation_policies.map(&:to_h)).to eq(
        [{ surface_name: :fenced_code_block, strategy: :by_language, metadata: {} }]
      )
    end

    it 'tracks parsed directives with line numbers' do
      ruleset = described_class.parse(valid_ruleset)

      expect(ruleset.directives.first).to include(name: :format, line_number: 3)
      expect(ruleset.directives.last).to include(name: :delegate)
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

    it 'rejects duplicate required directives' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          format yaml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
        RULESET
      end.to raise_error(ArgumentError, /Duplicate directive format/)
    end

    it 'rejects unknown read strategies' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read mystery_strategy
          attach normalize_tracked_layout_merge
        RULESET
      end.to raise_error(ArgumentError, /Unknown read strategy/)
    end

    it 'rejects unknown attachment strategies' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach mystery_strategy
        RULESET
      end.to raise_error(ArgumentError, /Unknown attach strategy/)
    end

    it 'rejects unknown owner selectors' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners mystery_owner
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
        RULESET
      end.to raise_error(ArgumentError, /Unknown owner selector/)
    end

    it 'rejects unknown match keys' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match mystery_match
          read native_read_portable_write
          attach normalize_tracked_layout_merge
        RULESET
      end.to raise_error(ArgumentError, /Unknown match key/)
    end

    it 'rejects invalid token content' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
          render bad#token
        RULESET
      end.to raise_error(ArgumentError, /Invalid token/)
    end

    it 'rejects duplicate capability names' do
      expect do
        described_class.parse(<<~RULESET)
          format toml
          owners line_bound_statements
          match signature
          read native_read_portable_write
          attach normalize_tracked_layout_merge
          capability inline_comments true
          capability inline_comments false
        RULESET
      end.to raise_error(ArgumentError, /Duplicate capability inline_comments/)
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
  end

  describe '.load' do
    let(:fixture_path) { File.expand_path('../../../fixtures/rulesets/basic_toml.ruleset', __dir__) }

    it 'loads and parses a ruleset file' do
      ruleset = described_class.load(fixture_path)

      expect(ruleset.path).to eq(fixture_path)
      expect(ruleset.format).to eq(:toml)
      expect(ruleset.read).to eq(:native_read_portable_write)
    end
  end

  describe '#support_style' do
    it 'bridges parsed read strategy to a support style value object' do
      ruleset = described_class.parse(valid_ruleset)
      support_style = ruleset.support_style(source: :toml_native, capability: :full)

      expect(support_style.native_read_portable_write?).to be(true)
      expect(support_style.details[:source]).to eq(:toml_native)
      expect(support_style.details[:style]).to eq(:hash_comment)
    end

    it 'supports comment-free rulesets without creating a comment support style' do
      ruleset = described_class.parse(<<~RULESET)
        format json
        owners mapping_entries
        match key_name
        read native_mutation
        attach layout_only
      RULESET

      expect(ruleset.runtime_declaration).to be_comment_free
      expect(ruleset.support_style(source: :json_native)).to be_nil
      expect(ruleset.feature_profile.comment_aware?).to be(false)
    end
  end

  describe '#feature_profile' do
    it 'carries repair policies, surfaces, and delegation policies into the shared profile' do
      ruleset = described_class.parse(valid_ruleset)
      profile = ruleset.feature_profile

      expect(profile.repair_policies.map(&:to_h)).to eq(
        [{ kind: :comment_ownership_overlap, handling: :warn, metadata: {} }]
      )
      expect(profile.surfaces.map(&:to_h)).to eq(
        [{ name: :fenced_code_block, selector: :language_tag, metadata: {} }]
      )
      expect(profile.delegation_policies.map(&:to_h)).to eq(
        [{ surface_name: :fenced_code_block, strategy: :by_language, metadata: {} }]
      )
    end

    it 'is built through the runtime declaration translator' do
      ruleset = described_class.parse(valid_ruleset)
      declaration = ruleset.runtime_declaration(source: :toml_native, capability: :full)
      profile = ruleset.feature_profile(source: :toml_native, capability: :full)

      expect(declaration).to be_a(Ast::Merge::Ruleset::RuntimeDeclaration)
      expect(declaration.read_strategy).to eq(:native_read_portable_write)
      expect(declaration.attachment_strategy).to eq(:normalize_tracked_layout_merge)
      expect(declaration.render_family).to eq(:toml_pairs_and_tables)
      expect(declaration.capabilities).to eq(
        inline_comments: true,
        quoted_hash_inline_literals: false
      )
      expect(declaration.logical_owners).to eq(link_definition: :preserve_if_referenced)
      expect(declaration.logical_owner_policies.map(&:to_h)).to eq(
        [{ kind: :link_definition, action: :preserve_if_referenced, metadata: {} }]
      )
      expect(profile.read_strategy).to eq(declaration.read_strategy)
      expect(profile.attachment_strategy).to eq(declaration.attachment_strategy)
      expect(profile.render_family).to eq(declaration.render_family)
      expect(profile.logical_owners).to eq(declaration.logical_owners)
      expect(profile.logical_owner_policies.map(&:to_h)).to eq(declaration.logical_owner_policies.map(&:to_h))
      expect(profile.support_style.to_h).to eq(declaration.support_style.to_h)
    end
  end
end
