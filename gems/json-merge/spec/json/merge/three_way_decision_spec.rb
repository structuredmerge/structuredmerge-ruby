# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable Metrics/BlockLength -- recursive merge cases share one semantic contract
RSpec.describe Json::Merge::ThreeWayDecision do
  subject(:decision) { described_class.new }

  it 'combines independent object additions from ours and theirs' do
    result = decision.call(
      base: { 'shared' => true },
      ours: { 'shared' => true, 'ours' => 1 },
      theirs: { 'shared' => true, 'theirs' => 2 }
    )

    expect(result.value).to eq('shared' => true, 'ours' => 1, 'theirs' => 2)
    expect(result).not_to be_conflicted
    expect(result.changes).to contain_exactly(
      { path: '/ours', ours: :added, theirs: :unchanged },
      { path: '/theirs', ours: :unchanged, theirs: :added }
    )
  end

  it 'combines independent nested edits under the same owner' do
    result = decision.call(
      base: { 'settings' => { 'left' => 0, 'right' => 0 } },
      ours: { 'settings' => { 'left' => 1, 'right' => 0 } },
      theirs: { 'settings' => { 'left' => 0, 'right' => 2 } }
    )

    expect(result.value).to eq('settings' => { 'left' => 1, 'right' => 2 })
    expect(result).not_to be_conflicted
  end

  it 'combines independent children when both sides add the same object owner' do
    result = decision.call(
      base: {},
      ours: { 'added' => { 'ours' => 1 } },
      theirs: { 'added' => { 'theirs' => 2 } }
    )

    expect(result.value).to eq('added' => { 'ours' => 1, 'theirs' => 2 })
    expect(result).not_to be_conflicted
  end

  it 'localizes overlapping children when both sides add the same object owner' do
    result = decision.call(
      base: {},
      ours: { 'added' => { 'value' => 1 } },
      theirs: { 'added' => { 'value' => 2 } }
    )

    expect(result.conflicts).to contain_exactly(
      hash_including(category: :edit_edit, path: '/added/value')
    )
  end

  it 'detects edit/edit conflicts at the smallest semantic path' do
    result = decision.call(
      base: { 'settings' => { 'value' => 0 } },
      ours: { 'settings' => { 'value' => 1 } },
      theirs: { 'settings' => { 'value' => 2 } }
    )

    expect(result).to be_conflicted
    expect(result.conflicts).to contain_exactly(
      hash_including(
        conflict_id: 'json-conflict-settings-value',
        category: :edit_edit,
        path: '/settings/value'
      )
    )
  end

  it 'distinguishes delete/edit conflicts from a shared deletion' do
    conflict = decision.call(
      base: { 'value' => 0 },
      ours: {},
      theirs: { 'value' => 1 }
    )
    shared_deletion = decision.call(
      base: { 'value' => 0 },
      ours: {},
      theirs: {}
    )

    expect(conflict.conflicts).to contain_exactly(hash_including(category: :delete_edit, path: '/value'))
    expect(shared_deletion.value).to eq({})
    expect(shared_deletion).not_to be_conflicted
  end

  it 'escapes JSON pointer path segments' do
    result = decision.call(
      base: { 'a/b~c' => 0 },
      ours: { 'a/b~c' => 1 },
      theirs: { 'a/b~c' => 2 }
    )

    expect(result.conflicts.first.fetch(:path)).to eq('/a~1b~0c')
  end

  it 'treats concurrent array changes as an atomic conflict' do
    result = decision.call(base: [1], ours: [1, 2], theirs: [1, 3])

    expect(result).to be_conflicted
    expect(result.conflicts).to contain_exactly(
      hash_including(category: :edit_edit, path: '')
    )
  end
end
# rubocop:enable Metrics/BlockLength
