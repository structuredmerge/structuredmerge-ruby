# frozen_string_literal: true

require 'prism/merge'

# PragmaMerger resolves file-level pragmas (magic comments) as a discrete
# document, separately from the main node resolver.
#
# Two axes are specified and tested independently:
#
#   KEPT     - preference resolved exactly like ordinary content. Either side may
#              add or remove a pragma. Presence of a one-sided pragma follows the
#              add/remove flags (measured against how template-only and
#              destination-only code resolves); `preference` resolves the VALUE
#              when both sides declare the pragma.
#   POSITION - never follows merge placement rules. Ruby only honours a magic
#              comment appearing before the first statement, so the merged block
#              is always pinned to the top (below any shebang).
RSpec.describe Prism::Merge::PragmaMerger do
  let(:body) do
    <<~RUBY
      require "bundler/gem_tasks"

      task :default do
        puts "Default task complete."
      end
    RUBY
  end
  let(:fsl) { '# frozen_string_literal: true' }
  let(:encoding_pragma) { '# encoding: utf-8' }

  # Resolves the pragmas kept for a template/destination pair.
  def kept_keys(template, destination, **options)
    described_class.new(template_source: template, destination_source: destination, **options)
                   .resolved_entries
                   .map(&:key)
  end

  def merger(template, destination, **options)
    described_class.new(template_source: template, destination_source: destination, **options)
  end

  describe 'KEPT axis: resolved like ordinary content' do
    # Measured baseline from ordinary code (a template-only method or constant):
    # dropped when add_template_only_nodes is false regardless of preference, and
    # kept when it is true. Pragmas must match that, or they resolve differently
    # from code.
    %i[destination template].each do |preference|
      [false, true].each do |remove_missing|
        it 'drops a template-only pragma when add_template_only_nodes is false ' \
           "(preference: #{preference}, remove_template_missing_nodes: #{remove_missing})" do
          keys = kept_keys(
            "#{fsl}\n\n#{body}",
            body,
            preference: preference,
            add_template_only_nodes: false,
            remove_template_missing_nodes: remove_missing
          )

          expect(keys).to eq([])
        end

        it 'keeps a template-only pragma when add_template_only_nodes is true ' \
           "(preference: #{preference}, remove_template_missing_nodes: #{remove_missing})" do
          keys = kept_keys(
            "#{fsl}\n\n#{body}",
            body,
            preference: preference,
            add_template_only_nodes: true,
            remove_template_missing_nodes: remove_missing
          )

          expect(keys).to eq(['frozen_string_literal'])
        end
      end

      it 'keeps a destination-only pragma unless remove_template_missing_nodes ' \
           "(preference: #{preference})" do
        expect(kept_keys(body, "#{fsl}\n\n#{body}", preference: preference))
          .to eq(['frozen_string_literal'])
        expect(
          kept_keys(body, "#{fsl}\n\n#{body}", preference: preference, remove_template_missing_nodes: true)
        ).to eq([])
      end
    end

    it 'keeps a pragma both sides declare, regardless of add/remove settings' do
      [false, true].each do |add|
        [false, true].each do |remove|
          keys = kept_keys("#{fsl}\n\n#{body}", "#{fsl}\n\n#{body}",
                           add_template_only_nodes: add, remove_template_missing_nodes: remove)

          expect(keys).to eq(['frozen_string_literal'])
        end
      end
    end

    it 'resolves the VALUE by preference when both sides declare the pragma' do
      template = "#{fsl}\n\n#{body}"
      destination = "# frozen_string_literal: false\n\n#{body}"

      expect(merger(template, destination, preference: :destination).resolved_entries.first.value).to eq('false')
      expect(merger(template, destination, preference: :template).resolved_entries.first.value).to eq('true')
    end
  end

  describe 'POSITION axis: pinned to the header' do
    it 'renders one pragma per line with no surrounding blank lines' do
      rendered = merger("#{fsl}\n\n#{body}", "#{fsl}\n", preference: :destination).render

      expect(rendered).to eq("#{fsl}\n")
    end

    it 'renders an empty string when no pragma is kept' do
      expect(merger(body, body).render).to eq('')
    end

    it 'places the pragma block below a shebang' do
      placed = merger("#{fsl}\n\n#{body}", "#{fsl}\n").place_in("#!/usr/bin/env ruby\nx = 1\n")

      expect(placed.lines.first).to eq("#!/usr/bin/env ruby\n")
      expect(placed.lines[1]).to eq("#{fsl}\n")
    end

    it 'places the pragma block above the first statement when there is no shebang' do
      placed = merger("#{fsl}\n\n#{body}", "#{fsl}\n").place_in("x = 1\n")

      expect(placed.lines.first).to eq("#{fsl}\n")
    end

    it 'returns content unchanged when no pragma is kept' do
      expect(merger(body, body).place_in("x = 1\n")).to eq("x = 1\n")
    end

    # A stranded pragma is present in the text but inert: Ruby ignores it, and
    # RuboCop reports Lint/MisplacedMagicComment. Stripping must remove it from
    # wherever it landed so the pinned block is the only copy.
    it 'strips pragma lines from anywhere in the content' do
      expect(described_class.strip_pragma_lines("#{fsl}\n\nx = 1\n#{fsl}\n")).to eq("\nx = 1\n")
    end

    it 'is stable when re-applied to already pinned content' do
      once = merger("#{fsl}\n\n#{body}", "#{fsl}\n").place_in(described_class.strip_pragma_lines("x = 1\n"))
      twice = merger("#{fsl}\n\n#{body}", "#{fsl}\n").place_in(described_class.strip_pragma_lines(once))

      expect(twice).to eq(once)
    end
  end

  describe 'scope: block directives are not file-level pragmas' do
    let(:freeze_source) { "# kettle-jem:freeze\n# preserved\n# kettle-jem:unfreeze\n\nx = 1\n" }
    let(:coverage_source) { "# simplecov:disable\nx = 1\n# simplecov:enable\n" }

    # Prism classifies ANY leading `# key: value` as a magic comment, including
    # freeze markers and coverage directives. Those are positionally meaningful and
    # legitimately appear mid-file, so they must be excluded by key.
    it 'does not treat freeze markers as pragmas' do
      expect(kept_keys(freeze_source, "x = 1\n")).to eq([])
    end

    it 'does not treat coverage directives as pragmas' do
      expect(kept_keys(coverage_source, "x = 1\n")).to eq([])
    end

    it 'leaves freeze markers untouched when stripping' do
      expect(described_class.strip_pragma_lines(freeze_source)).to eq(freeze_source)
    end

    it 'leaves coverage directives untouched when stripping' do
      expect(described_class.strip_pragma_lines(coverage_source)).to eq(coverage_source)
    end

    it 'keeps a pragma alongside directives without reordering them' do
      source = "#{fsl}\n\n#{freeze_source}"

      expect(described_class.strip_pragma_lines(source)).to eq("\n#{freeze_source}")
    end
  end

  describe 'ordering' do
    it 'renders template-declared pragmas in template order' do
      keys = merger("#{fsl}\n#{encoding_pragma}\n\n#{body}", "#{encoding_pragma}\n#{fsl}\n\n#{body}")
             .resolved_entries
             .map(&:key)

      expect(keys).to eq(%w[frozen_string_literal encoding])
    end

    it 'appends destination-only pragmas after template-declared ones' do
      keys = merger("#{fsl}\n\n#{body}", "#{encoding_pragma}\n\n#{body}", add_template_only_nodes: true)
             .resolved_entries
             .map(&:key)

      expect(keys).to eq(%w[frozen_string_literal encoding])
    end
  end

  describe 'edge cases' do
    it 'handles empty sources without raising' do
      expect(kept_keys('', '')).to eq([])
      expect(kept_keys('', "#{fsl}\n")).to eq(['frozen_string_literal'])
      expect(kept_keys("#{fsl}\n", '')).to eq([])
    end

    it 'handles nil sources as empty' do
      expect(kept_keys(nil, nil)).to eq([])
    end

    it 'treats a comment-only file as all-header' do
      expect(kept_keys("#{fsl}\n", "#{fsl}\n")).to eq(['frozen_string_literal'])
    end

    it 'collapses a duplicated pragma of the same type to one entry' do
      expect(kept_keys("#{fsl}\n#{fsl}\n\n#{body}", "#{fsl}\n")).to eq(['frozen_string_literal'])
    end
  end
end
