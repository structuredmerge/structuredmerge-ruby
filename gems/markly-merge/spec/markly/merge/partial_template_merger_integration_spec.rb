# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Markly::Merge::PartialTemplateMerger, :markly do
  describe 'standalone HTML comment fixture parity' do
    let(:fixture_dir) { File.join(__dir__, '../../fixtures/reproducible/07_partial_replace_comments') }
    let(:template) { File.read(File.join(fixture_dir, 'template.md')) }
    let(:destination) { File.read(File.join(fixture_dir, 'destination.md')) }
    let(:expected_result) { File.read(File.join(fixture_dir, 'result.md')) }

    it 'preserves a between-block standalone HTML comment during replace_mode section replacement' do
      result = described_class.new(
        template: template,
        destination: destination,
        anchor: { type: :heading, text: /Description/ },
        preference: :template,
        replace_mode: true
      ).merge

      expect(result.content).to eq(expected_result)
    end
  end

  it 'preserves destination-only link reference definitions during replace_mode section replacement' do
    template = <<~MARKDOWN
      ## Description

      Template intro.

      Template body with [Docs][docs].
    MARKDOWN

    destination = <<~MARKDOWN
      # Title

      ## Description

      <!-- Destination docs -->

      [docs]: https://example.test/docs

      Destination body.

      ## After

      Keep me.
    MARKDOWN

    expected = <<~MARKDOWN
      # Title

      ## Description

      <!-- Destination docs -->

      [docs]: https://example.test/docs

      Template intro.

      Template body with [Docs][docs].

      ## After

      Keep me.
    MARKDOWN

    result = described_class.new(
      template: template,
      destination: destination,
      anchor: { type: :heading, text: /Description/ },
      preference: :template,
      replace_mode: true
    ).merge

    expect(result.content).to eq(expected)
    expect(result.stats).to include(
      mode: :replace,
      preserved_destination_comment_fragments: 1,
      preserved_destination_link_definitions: 1
    )
  end

  it 'preserves a trailing standalone HTML comment plus trailing destination-only link reference definitions during replace_mode section replacement' do
    template = <<~MARKDOWN
      ## Description

      Template body with [Docs][docs] and [API][api].
    MARKDOWN

    destination = <<~MARKDOWN
      # Title

      ## Description

      Destination body.

      <!-- Destination trailing docs -->

      [docs]: https://example.test/docs
      [api]: https://example.test/api

      ## After

      Keep me.
    MARKDOWN

    expected = <<~MARKDOWN
      # Title

      ## Description

      Template body with [Docs][docs] and [API][api].

      <!-- Destination trailing docs -->

      [docs]: https://example.test/docs
      [api]: https://example.test/api

      ## After

      Keep me.
    MARKDOWN

    result = described_class.new(
      template: template,
      destination: destination,
      anchor: { type: :heading, text: /Description/ },
      preference: :template,
      replace_mode: true
    ).merge

    expect(result.content).to eq(expected)
    expect(result.stats).to include(
      mode: :replace,
      preserved_destination_comment_fragments: 1,
      preserved_destination_link_definitions: 2
    )
  end

  it 'preserves a destination standalone HTML comment-only fragment at the end of the replaced section' do
    template = <<~MARKDOWN
      ## Description

      Template intro.
    MARKDOWN

    destination = <<~MARKDOWN
      # Title

      ## Description

      Destination intro.

      <!-- Destination trailing docs -->

      ## After

      Keep me.
    MARKDOWN

    expected = <<~MARKDOWN
      # Title

      ## Description

      Template intro.

      <!-- Destination trailing docs -->

      ## After

      Keep me.
    MARKDOWN

    result = described_class.new(
      template: template,
      destination: destination,
      anchor: { type: :heading, text: /Description/ },
      preference: :template,
      replace_mode: true
    ).merge

    expect(result.content).to eq(expected)
    expect(result.stats).to include(
      mode: :replace,
      preserved_destination_comment_fragments: 1
    )
  end
end
