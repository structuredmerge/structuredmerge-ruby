# frozen_string_literal: true

RSpec.describe Plain::Merge do
  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def manifest
    @manifest ||= read_json(fixtures_root.join('conformance', 'slice-24-manifest', 'family-feature-profiles.json'))
  end

  def family_profile_fixture
    path = Ast::Merge.conformance_family_feature_profile_path(manifest, 'text')
    read_json(fixtures_root.join(*path))
  end

  def text_fixture(role)
    path = Ast::Merge.conformance_fixture_path(manifest, 'text', role)
    raise "missing text fixture for #{role}" unless path

    read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it 'conforms to the slice-03 analysis fixture' do
    fixture = text_fixture('analysis')
    analysis = described_class.analyze_text(fixture[:source])

    expect(analysis[:normalized_source]).to eq(fixture.dig(:expected, :normalized_source))
    expect(
      json_ready(analysis[:blocks].map { |block| block.slice(:index, :normalized) })
    ).to eq(json_ready(fixture.dig(:expected, :blocks)))
  end

  it 'conforms to the slice-11 exact matching fixture' do
    fixture = text_fixture('matching_exact')
    result = described_class.match_text_blocks(fixture[:template], fixture[:destination])

    expect(
      json_ready(result[:matched].map { |match| [match[:template_index], match[:destination_index]] })
    ).to eq(json_ready(fixture.dig(:expected, :matched)))
    expect(json_ready(result[:unmatched_template])).to eq(json_ready(fixture.dig(:expected, :unmatched_template)))
    expect(json_ready(result[:unmatched_destination])).to eq(json_ready(fixture.dig(:expected, :unmatched_destination)))
  end

  it 'conforms to the slice-05 similarity fixture' do
    fixture = text_fixture('similarity')

    fixture[:cases].each do |test_case|
      expect(described_class.similarity_score(test_case[:left], test_case[:right])).to eq(test_case[:expected_score])
      expect(
        json_ready(described_class.is_similar(test_case[:left], test_case[:right], test_case[:threshold]))
      ).to eq(
        json_ready(
          score: test_case[:expected_score],
          threshold: test_case[:threshold],
          matched: test_case[:expected_match]
        )
      )
    end
  end

  it 'conforms to the slice-13 refined matching fixture' do
    fixture = text_fixture('merge_refined')
    result = described_class.match_text_blocks(fixture[:template], fixture[:destination])

    expect(
      json_ready(
        result[:matched]
          .sort_by { |match| match[:destination_index] }
          .map do |match|
            {
              templateIndex: match[:template_index],
              destinationIndex: match[:destination_index],
              phase: match[:phase]
            }
          end
      )
    ).to eq(json_ready(fixture.dig(:expected, :matched)))
    expect(json_ready(result[:unmatched_template])).to eq(json_ready(fixture.dig(:expected, :unmatchedTemplate)))
    expect(json_ready(result[:unmatched_destination])).to eq(json_ready(fixture.dig(:expected, :unmatchedDestination)))

    merged = described_class.merge_text(fixture[:template], fixture[:destination])
    expect(merged[:output]).to eq(fixture.dig(:expected, :output))
  end

  it 'conforms to the shared text family feature profile fixture' do
    expect(json_ready(described_class.text_feature_profile)).to eq(json_ready(family_profile_fixture[:feature_profile]))
  end
end

RSpec.describe 'Plain::Merge TreeHaver backend registration' do
  it 'registers text and plain line backends through TreeHaver parser lookup' do
    source = "First paragraph\n\nSecond paragraph\n"

    text_analysis = TreeHaver.parser_for(:text, backend_type: :line).parse(source)
    plain_analysis = TreeHaver.parser_for(:plain, backend_type: :line).parse(source)

    expect(text_analysis[:kind]).to eq('text')
    expect(text_analysis[:blocks].map { |block| block[:normalized] }).to eq(['First paragraph', 'Second paragraph'])
    expect(plain_analysis).to eq(text_analysis)
  end
end

# rubocop:disable Metrics/BlockLength -- complete portable provider operation matrix
RSpec.describe 'Plain::Merge provider conformance' do
  subject(:provider) { Plain::Merge.merge_provider }

  let(:provider_conformance) do
    {
      dialect: :text,
      backend: :'plain-line',
      profile_id: :coarse_document,
      role: :workflow,
      parse_failures: false,
      requests: {
        analyze: { source: "stable\n" },
        diff2: { before_source: "stable\n", after_source: "changed\n" },
        merge2: { current_source: "ours\n", incoming_source: "theirs\n" },
        merge3: {
          base_source: "base\n",
          ours_source: "base\n",
          theirs_source: "theirs\n"
        }
      },
      base_adversarial_merge3: {
        request: {
          base_source: "obsolete\nstable\n",
          ours_source: "obsolete\nstable\n",
          theirs_source: "stable\n"
        },
        expected_value: "stable\n"
      },
      parse_output: ->(source) { source }
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'

  it 'reports a whole-document conflict when both sides differ from base' do
    result = provider.merge3(
      base_source: "base\n",
      ours_source: "ours\n",
      theirs_source: "theirs\n",
      dialect: :text,
      profile_id: :coarse_document
    )

    expect(result).to include(ok: false, operation: :merge3)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :edit_edit, path: '')
    )
    expect(result.fetch(:conflicted_output)).to include(
      "<<<<<<< ours\nours\n||||||| base\nbase\n=======\ntheirs\n>>>>>>> theirs\n"
    )
    expect(result.dig(:verification, :base_participated)).to be(true)
  end
end
# rubocop:enable Metrics/BlockLength
