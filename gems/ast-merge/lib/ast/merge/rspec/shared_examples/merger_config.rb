# frozen_string_literal: true

# Shared examples for validating MergerConfig usage
#
# Usage in your spec:
#   require "ast/merge/rspec/shared_examples/merger_config"
#
#   RSpec.describe Ast::Merge::MergerConfig do
#     it_behaves_like "Ast::Merge::MergerConfig" do
#       let(:merger_config_class) { Ast::Merge::MergerConfig }
#       # Factory to create merger config instance
#       let(:build_merger_config) { ->(**opts) { merger_config_class.new(**opts) } }
#     end
#   end
#
# @note This is for testing the MergerConfig class itself or custom subclasses

RSpec.shared_examples('Ast::Merge::MergerConfig') do
  # Required let blocks:
  # - merger_config_class: The class under test (usually Ast::Merge::MergerConfig)
  # - build_merger_config: Lambda that creates a merger config instance

  describe 'constants' do
    it 'has VALID_PREFERENCES' do
      expect(merger_config_class::VALID_PREFERENCES).to(eq(%i[destination template]))
    end
  end

  describe 'default configuration' do
    let(:config) { build_merger_config.call }

    it 'defaults preference to :destination' do
      expect(config.preference).to(eq(:destination))
    end

    it 'defaults add_template_only_nodes to false' do
      expect(config.add_template_only_nodes).to(eq(false))
    end

    it 'defaults freeze_token to nil' do
      expect(config.freeze_token).to(be_nil)
    end

    it 'defaults signature_generator to nil' do
      expect(config.signature_generator).to(be_nil)
    end

    it 'defaults resolution_mode to :eager' do
      expect(config.resolution_mode).to(eq(:eager))
    end

    it 'defaults unresolved_policy to a policy object' do
      expect(config.unresolved_policy).to(be_a(Ast::Merge::UnresolvedPolicy))
    end
  end

  describe 'custom configuration' do
    it 'accepts preference: :template' do
      config = build_merger_config.call(preference: :template)
      expect(config.preference).to(eq(:template))
    end

    it 'accepts add_template_only_nodes: true' do
      config = build_merger_config.call(add_template_only_nodes: true)
      expect(config.add_template_only_nodes).to(eq(true))
    end

    it 'accepts freeze_token option' do
      config = build_merger_config.call(freeze_token: 'my-token')
      expect(config.freeze_token).to(eq('my-token'))
    end

    it 'accepts signature_generator proc' do
      generator = ->(node) { [:custom, node] }
      config = build_merger_config.call(signature_generator: generator)
      expect(config.signature_generator).to(eq(generator))
    end

    it 'accepts resolution_mode: :unresolved' do
      config = build_merger_config.call(resolution_mode: :unresolved)
      expect(config.resolution_mode).to(eq(:unresolved))
    end

    it 'accepts unresolved_policy as a Hash' do
      config = build_merger_config.call(unresolved_policy: {
                                          enabled_kinds: [:matched_line],
                                          provisional_winner: :template
                                        })

      expect(config.unresolved_policy).to(be_a(Ast::Merge::UnresolvedPolicy))
      expect(config.unresolved_policy.to_h).to(include(
                                                 enabled_kinds: [:matched_line],
                                                 provisional_winner: :template
                                               ))
    end
  end

  describe 'validation' do
    it 'raises ArgumentError for invalid preference' do
      expect { build_merger_config.call(preference: :invalid) }
        .to(raise_error(ArgumentError, /invalid.*preference/i))
    end

    it 'accepts :destination preference' do
      expect { build_merger_config.call(preference: :destination) }
        .not_to(raise_error)
    end

    it 'accepts :template preference' do
      expect { build_merger_config.call(preference: :template) }
        .not_to(raise_error)
    end

    it 'accepts Hash preference' do
      expect { build_merger_config.call(preference: { default: :destination }) }
        .not_to(raise_error)
    end

    it 'validates node_typing if provided' do
      expect { build_merger_config.call(node_typing: 'not a hash') }
        .to(raise_error(ArgumentError, /must be a Hash/))
    end

    it 'raises ArgumentError for invalid resolution_mode' do
      expect { build_merger_config.call(resolution_mode: :invalid) }
        .to(raise_error(ArgumentError, /invalid.*resolution_mode/i))
    end

    it 'raises ArgumentError for invalid unresolved_policy' do
      expect { build_merger_config.call(unresolved_policy: :invalid) }
        .to(raise_error(ArgumentError, /unresolved_policy/i))
    end
  end

  describe '#prefer_destination?' do
    it 'returns true when preference is :destination' do
      config = build_merger_config.call(preference: :destination)
      expect(config.prefer_destination?).to(be(true))
    end

    it 'returns false when preference is :template' do
      config = build_merger_config.call(preference: :template)
      expect(config.prefer_destination?).to(be(false))
    end
  end

  describe '#prefer_template?' do
    it 'returns true when preference is :template' do
      config = build_merger_config.call(preference: :template)
      expect(config.prefer_template?).to(be(true))
    end

    it 'returns false when preference is :destination' do
      config = build_merger_config.call(preference: :destination)
      expect(config.prefer_template?).to(be(false))
    end
  end

  describe '#to_h' do
    it 'returns a hash with configuration options' do
      config = build_merger_config.call(
        preference: :template,
        add_template_only_nodes: true
      )
      hash = config.to_h

      expect(hash).to(be_a(Hash))
      expect(hash[:preference]).to(eq(:template))
      expect(hash[:add_template_only_nodes]).to(eq(true))
    end

    it 'includes resolution_mode' do
      config = build_merger_config.call(resolution_mode: :unresolved)
      hash = config.to_h

      expect(hash[:resolution_mode]).to(eq(:unresolved))
    end

    it 'includes unresolved_policy' do
      config = build_merger_config.call(unresolved_policy: { provisional_winner: :template })
      hash = config.to_h

      expect(hash[:unresolved_policy]).to(include(provisional_winner: :template))
    end

    it 'includes freeze_token when set' do
      config = build_merger_config.call(freeze_token: 'my-token')
      hash = config.to_h

      expect(hash[:freeze_token]).to(eq('my-token'))
    end

    it 'uses default_freeze_token when none specified' do
      config = build_merger_config.call
      hash = config.to_h(default_freeze_token: 'default-token')

      expect(hash[:freeze_token]).to(eq('default-token'))
    end

    it 'includes signature_generator when set' do
      generator = ->(_node) { [:custom] }
      config = build_merger_config.call(signature_generator: generator)
      hash = config.to_h

      expect(hash[:signature_generator]).to(eq(generator))
    end

    it 'includes node_typing when set' do
      typing = { CallNode: ->(_node) { nil } }
      config = build_merger_config.call(node_typing: typing)
      hash = config.to_h

      expect(hash[:node_typing]).to(eq(typing))
    end
  end

  describe '#with' do
    it 'creates a new config with updated values' do
      original = build_merger_config.call(preference: :destination)
      updated = original.with(preference: :template)

      expect(original.preference).to(eq(:destination))
      expect(updated.preference).to(eq(:template))
    end

    it 'preserves unmodified values' do
      original = build_merger_config.call(
        preference: :destination,
        add_template_only_nodes: true
      )
      updated = original.with(preference: :template)

      expect(updated.add_template_only_nodes).to(eq(true))
    end

    it 'preserves node_typing' do
      typing = { CallNode: ->(_node) { nil } }
      original = build_merger_config.call(node_typing: typing)
      updated = original.with(preference: :template)

      expect(updated.node_typing).to(eq(typing))
    end

    it 'preserves resolution_mode' do
      original = build_merger_config.call(resolution_mode: :unresolved)
      updated = original.with(preference: :template)

      expect(updated.resolution_mode).to(eq(:unresolved))
    end

    it 'preserves unresolved_policy' do
      original = build_merger_config.call(unresolved_policy: { provisional_winner: :template })
      updated = original.with(preference: :template)

      expect(updated.unresolved_policy.to_h).to(include(provisional_winner: :template))
    end
  end

  describe '#inspect' do
    it 'returns a string representation' do
      config = build_merger_config.call
      expect(config.inspect).to(be_a(String))
      expect(config.inspect).to(include('MergerConfig'))
    end
  end
end
