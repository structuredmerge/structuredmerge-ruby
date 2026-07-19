# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Ruby::Merge::SignatureSupport do
  it 'builds canonical Ruby definition signatures' do
    expect(described_class.method_definition(:call, %i[arg opts])).to eq([:def, :call, %i[arg opts]])
    expect(described_class.class_definition('Admin::User')).to eq([:class, 'Admin::User'])
    expect(described_class.module_definition('Admin')).to eq([:module, 'Admin'])
  end

  it 'builds canonical Ruby call signatures' do
    expect(described_class.call(:gemspec, nil)).to eq([:call, :gemspec, nil])
    expect(described_class.call(:appraise, 'rails', block: true)).to eq([:call_with_block, :appraise, 'rails'])
    expect(described_class.call_operator_write(:files, Ruby::Merge::GemspecSupport::GEMSPEC_VAR_PLACEHOLDER)).to eq(
      [:call_op_write, :files, Ruby::Merge::GemspecSupport::GEMSPEC_VAR_PLACEHOLDER]
    )
  end

  it 'builds canonical Ruby control-flow signatures' do
    expect(described_class.super_call(block: false)).to eq([:super, :no_block])
    expect(described_class.forwarding_super_call(block: true)).to eq([:forwarding_super, :with_block])
    expect(described_class.begin_block('do_work')).to eq([:begin, 'do_work'])
  end

  it 'keeps the textual method signature format used by ruby-merge analysis' do
    expect(described_class.textual_method_signature('self.', 'build')).to eq('self.build')
  end
end
