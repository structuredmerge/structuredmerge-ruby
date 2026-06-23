# frozen_string_literal: true

RSpec.describe Ast::Merge::OwnerSelection do
  describe '.match_by_path' do
    it 'matches owners by stable path and reports unmatched paths' do
      template = {
        owners: [
          { path: '/imports/0' },
          { path: '/declarations/alpha' },
          { path: '/declarations/beta' }
        ]
      }
      destination = {
        owners: [
          { path: '/imports/0' },
          { path: '/declarations/beta' },
          { path: '/declarations/gamma' }
        ]
      }

      expect(described_class.match_by_path(template, destination)).to eq(
        matched: [
          { template_path: '/imports/0', destination_path: '/imports/0' },
          { template_path: '/declarations/beta', destination_path: '/declarations/beta' }
        ],
        unmatched_template: ['/declarations/alpha'],
        unmatched_destination: ['/declarations/gamma']
      )
    end
  end

  describe '.selector_kind' do
    it 'distinguishes shared default, explicit, and logical-owner selectors' do
      expect(described_class.selector_kind(:shared_default)).to eq(:shared_default)
      expect(described_class.selector_kind(:line_bound_statements)).to eq(:explicit)
      expect(
        described_class.selector_kind(:link_definitions, logical_owners: { link_definition: :preserve_if_referenced })
      ).to eq(:logical_owner)
    end
  end
end
