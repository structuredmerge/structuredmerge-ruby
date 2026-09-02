# frozen_string_literal: true

module Ruby
  # Ruby workflow provider integration.
  module Merge
    # Tree-sitter workflow provider backed by the shared Ruby substrate.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- provider operations keep request, rendering, and result-envelope logic together
    class Provider
      DEFAULT_PROFILE = :source_preserving
      TREE_SITTER_BACKENDS = [
        *TreeHaver::NATIVE_BACKENDS,
        :tslp,
        :'kreuzberg-language-pack'
      ].freeze

      def provider_id = 'ruby.ruby'
      def family = 'ruby'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[ruby],
          backends: TREE_SITTER_BACKENDS,
          profiles: [DEFAULT_PROFILE],
          role: :workflow,
          parser_requirements: {
            allowed_backend_families: ['tree-sitter'],
            denied_backend_ids: ['prism'],
            required_capabilities: %w[normalized-nodes exact-byte-spans]
          },
          source_preservation: %i[exact_source owner_fragments line_provenance reparse]
        }.freeze
      end

      def analyze(request)
        parsed = parse_source(request.fetch(:source), request)
        return parse_failure(:analyze, :source, parsed, request) unless parsed[:ok]

        result(
          :analyze,
          request,
          analysis: parsed.fetch(:analysis),
          verification: { source_parsed: true }
        )
      end

      def diff2(request)
        before = parse_source(request.fetch(:before_source), request)
        return parse_failure(:diff2, :before, before, request) unless before[:ok]

        after = parse_source(request.fetch(:after_source), request)
        return parse_failure(:diff2, :after, after, request) unless after[:ok]

        changes = owner_changes(
          request.fetch(:before_source),
          request.fetch(:after_source)
        )
        result(
          :diff2,
          request,
          diff: { changes: changes },
          changes: changes,
          verification: { before_parsed: true, after_parsed: true }
        )
      end

      def merge2(request)
        merged = Ruby::Merge.merge_ruby(
          request.fetch(:incoming_source),
          request.fetch(:current_source),
          'ruby',
          backend: request[:backend]
        )
        return substrate_failure(:merge2, merged, request) unless merged[:ok]

        output = merged.fetch(:output)
        verified = parse_source(output, request)
        return parse_failure(:merge2, :output, verified, request, category: :render_failure) unless verified[:ok]

        result(
          :merge2,
          request,
          output: output,
          render_report: { strategy: :ruby_substrate, synthesis: :family_emission },
          verification: { output_reparsed: true }
        )
      end

      def merge3(request)
        parsed = %i[base ours theirs].to_h do |role|
          result = parse_source(request.fetch(:"#{role}_source"), request)
          return parse_failure(:merge3, role, result, request) unless result[:ok]

          [role, result]
        end
        winner = exact_revision_role(request)
        unless winner
          return failure(
            :merge3,
            request,
            category: :unsupported_capability,
            message: 'ruby-merge has not proven composite three-way merging for tree-sitter runtimes.',
            verification: { base_participated: true }
          )
        end

        output = request.fetch(:"#{winner}_source")
        result(
          :merge3,
          request,
          output: output,
          render_report: { strategy: :exact_revision, source_role: winner },
          verification: {
            base_participated: true,
            output_reparsed: parsed.fetch(winner)[:ok],
            byte_exact: true,
            source_role: winner
          }
        )
      end

      private

      def parse_source(source, request)
        Ruby::Merge.parse_ruby(source, 'ruby', backend: request[:backend])
      end

      def owner_changes(before_source, after_source)
        before = Ruby::Merge.ruby_source_owner_identity_profile(before_source)
        after = Ruby::Merge.ruby_source_owner_identity_profile(after_source)
        before_by_identity = before.to_h { |owner| [owner[:structural_identity], owner] }
        after_by_identity = after.to_h { |owner| [owner[:structural_identity], owner] }
        [*before_by_identity.keys, *after_by_identity.keys].uniq.filter_map do |identity|
          left = before_by_identity[identity]
          right = after_by_identity[identity]
          next if left == right

          {
            path: right&.fetch(:address) || left.fetch(:address),
            before: left ? :present : :absent,
            after: right ? :present : :absent,
            change: if left.nil?
                      :added
                    elsif right.nil?
                      :deleted
                    else
                      :edited
                    end
          }.freeze
        end.freeze
      end

      def exact_revision_role(request)
        base = request.fetch(:base_source)
        ours = request.fetch(:ours_source)
        theirs = request.fetch(:theirs_source)
        return :ours if ours == theirs || base == theirs

        :theirs if base == ours
      end

      def parse_failure(operation, role, parsed, request, category: :parse_error)
        diagnostic = Array(parsed[:diagnostics]).first || {}
        failure(
          operation,
          request,
          category: category,
          message: "#{role} parse error: #{diagnostic[:message] || 'Ruby parse failed'}",
          source_role: role,
          verification: operation == :merge3 ? { base_participated: true } : {}
        )
      end

      def substrate_failure(operation, merged, request)
        diagnostic = Array(merged[:diagnostics]).first || {}
        failure(
          operation,
          request,
          category: (diagnostic[:category] || :merge_failure).to_sym,
          message: diagnostic[:message] || 'Ruby substrate merge failed.'
        )
      end

      def result(operation, request, changes: [], diagnostics: [], render_report: {}, verification: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: true,
          envelope: envelope(
            request,
            changes: changes,
            diagnostics: diagnostics,
            render_report: render_report,
            verification: verification
          ),
          **payload
        )
      end

      def failure(operation, request, category:, message:, verification: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: false,
          envelope: envelope(
            request,
            diagnostics: [{ category: category, severity: :error, message: message, blocking: true }],
            verification: verification
          ),
          **payload
        )
      end

      def envelope(request, **fields)
        {
          provider: {
            provider_id: provider_id,
            family: family,
            dialect: request[:dialect] || :ruby,
            backend: request[:backend] || :'kreuzberg-language-pack',
            package: Ruby::Merge::PACKAGE_NAME,
            package_version: Ruby::Merge::Version::VERSION
          },
          profile: { profile_id: request[:profile_id] || DEFAULT_PROFILE }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity

    class << self
      def merge_provider
        @merge_provider ||= Provider.new
      end

      def register_provider!(replace: false)
        Ast::Merge.register_provider(merge_provider, replace: replace)
      end
    end
  end
end
