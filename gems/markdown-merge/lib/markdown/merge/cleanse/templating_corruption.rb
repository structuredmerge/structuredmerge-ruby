# frozen_string_literal: true

module Markdown
  module Merge
    module Cleanse
      # Composes targeted repair passes for known templating corruption
      # signatures seen in historical kettle-jem runs.
      class TemplatingCorruption
        PASS_TYPES = [
          ListMarkerDuplication,
          CondensedLinkRefs,
          CodeFenceSpacing,
          BlockSpacing
        ].freeze

        attr_reader :source, :passes, :issues

        def initialize(source)
          @source = source.to_s
          @passes = []
          @issues = []
          analyze
        end

        def malformed?
          issues.any?
        end

        def issue_count
          issues.length
        end

        def fix
          current = source

          PASS_TYPES.each do |pass_type|
            pass = pass_type.new(current)
            next unless pass_issues?(pass)

            current = pass_output(pass, current)
          end

          current
        end

        private

        def analyze
          current = source

          PASS_TYPES.each do |pass_type|
            pass = pass_type.new(current)
            @passes << pass
            append_issues(pass)
            current = pass_output(pass, current) if pass_issues?(pass)
          end
        end

        def append_issues(pass)
          if pass.respond_to?(:issues)
            issues.concat(Array(pass.issues))
          elsif pass_issues?(pass)
            issues << {
              type: pass.class.name.split('::').last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym,
              description: "#{pass.class.name} detected malformed content"
            }
          end
        end

        def pass_issues?(pass)
          pass.respond_to?(:malformed?) ? pass.malformed? : pass.respond_to?(:condensed?) && pass.condensed?
        end

        def pass_output(pass, fallback)
          if pass.respond_to?(:fix)
            pass.fix
          elsif pass.respond_to?(:expand)
            pass.expand
          else
            fallback
          end
        end
      end
    end
  end
end
