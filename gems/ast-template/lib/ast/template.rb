# frozen_string_literal: true

require 'fileutils'
require 'ast/merge'
require_relative 'template/version'

module Ast
  module Template
    MODES = %w[plan apply reapply].freeze
    SESSION_STATUS_TRANSPORT_VERSION = 1
    SESSION_DIAGNOSTICS_TRANSPORT_VERSION = 1
    SESSION_OUTCOME_TRANSPORT_VERSION = 1
    SESSION_INSPECTION_TRANSPORT_VERSION = 1
    SESSION_REQUEST_TRANSPORT_VERSION = 1
    SESSION_RUNNER_REQUEST_TRANSPORT_VERSION = 1
    SESSION_RUNNER_PAYLOAD_TRANSPORT_VERSION = 1
    SESSION_ENTRYPOINT_TRANSPORT_VERSION = 1
    SESSION_COMMAND_TRANSPORT_VERSION = 1
    SESSION_COMMAND_PAYLOAD_TRANSPORT_VERSION = 1
    SESSION_INVOCATION_TRANSPORT_VERSION = 1
    README_FAMILY_LANGUAGE_ORDER = %w[go ruby rust typescript].freeze
    README_FAMILY_LANGUAGE_LABELS = {
      'go' => 'Go',
      'ruby' => 'Ruby',
      'rust' => 'Rust',
      'typescript' => 'TypeScript'
    }.freeze

    class << self
      def readme_family_language_aliases(self_language, language_order = README_FAMILY_LANGUAGE_ORDER)
        self_id = self_language.to_s
        alternatives = language_order.map(&:to_s).reject { |language| language == self_id }
        aliases = {
          'SELF_LANG' => README_FAMILY_LANGUAGE_LABELS.fetch(self_id, self_id),
          'SELF_LANG_ID' => self_id
        }
        alternatives.each_with_index do |language, index|
          alias_prefix = "IMP_LANG#{index + 1}"
          aliases[alias_prefix] = README_FAMILY_LANGUAGE_LABELS.fetch(language, language)
          aliases["#{alias_prefix}_ID"] = language
        end
        aliases
      end

      def readme_family_token_values(family_metadata)
        family = Ast::Merge.normalize_value(family_metadata || {})
        self_entry = family.fetch(:self, {})
        self_id = self_entry.fetch(:id).to_s
        implementations = Array(family[:implementations]).each_with_object({}) do |entry, memo|
          normalized_entry = Ast::Merge.normalize_value(entry)
          memo[normalized_entry[:id].to_s] = normalized_entry
        end
        aliases = readme_family_language_aliases(self_id)
        tokens = {
          'FAMILY_SECTION_HEADING' => family[:section_heading].to_s,
          'FAMILY_DESCRIPTION' => family[:description].to_s,
          'SELF_PACKAGE_ROOT' => self_entry[:package_root].to_s,
          'SELF_PACKAGE_MANAGER' => self_entry[:package_manager].to_s
        }.merge(aliases)

        README_FAMILY_LANGUAGE_ORDER.reject { |language| language == self_id }.each_with_index do |language, index|
          implementation = implementations.fetch(language, {})
          alias_prefix = "IMP_LANG#{index + 1}"
          tokens["#{alias_prefix}_PACKAGE_ROOT"] = implementation[:package_root].to_s
          tokens["#{alias_prefix}_PACKAGE_MANAGER"] = implementation[:package_manager].to_s
        end

        tokens
      end

      def render_readme_family_section(template_partial, family_metadata, config = nil)
        replacements = readme_family_token_values(family_metadata).transform_keys { |key| "SM|#{key}" }
        Ast::Merge.resolve_template_tokens(template_partial.to_s, replacements, config)
      end

      def apply_readme_family_section(template_partial, package_metadata, family_metadata, destination_content,
                                      config = nil)
        package_entry = Ast::Merge.normalize_value(package_metadata || {})
        family = Ast::Merge.normalize_value(family_metadata || {})
        rendered_section = render_readme_family_section(template_partial, family, config).rstrip
        base_content = if destination_content.nil?
                         "# #{package_entry[:name]}\n\n#{package_entry[:summary]}\n"
                       else
                         destination_content.to_s
                       end
        content = replace_or_insert_markdown_heading_section(
          base_content,
          family[:section_heading].to_s,
          2,
          rendered_section
        )
        {
          content: content,
          changed: content != base_content
        }
      end

      def apply_readme_family_sections_to_package_directories(root, template_partial, packages, config = nil)
        run_readme_family_sections_for_package_directories(root, template_partial, packages, true, config)
      end

      def plan_readme_family_sections_for_package_directories(root, template_partial, packages, config = nil)
        run_readme_family_sections_for_package_directories(root, template_partial, packages, false, config)
      end

      def run_readme_family_section_command(command, config = nil)
        normalized = Ast::Merge.normalize_value(command || {})
        mode = normalized.fetch(:mode, 'plan').to_s
        write_changes = %w[apply reapply].include?(mode)
        {
          profile_name: normalized.fetch(:profile_name, '').to_s,
          mode: mode,
          runner: run_readme_family_sections_for_package_directories(
            normalized.fetch(:root, '').to_s,
            normalized.fetch(:template_partial, '').to_s,
            Array(normalized[:packages]),
            write_changes,
            config
          )
        }
      end

      def run_readme_family_sections_for_package_directories(root, template_partial, packages, write_changes,
                                                             config = nil)
        report = {
          package_count: packages.length,
          changed_count: 0,
          created_count: 0,
          entries: []
        }
        packages.each do |package_entry|
          normalized_entry = Ast::Merge.normalize_value(package_entry)
          readme_path = normalized_entry.fetch(:readme_path).to_s
          full_path = File.join(root.to_s, readme_path.split('/'))
          created = !File.exist?(full_path)
          destination_content = created ? nil : File.read(full_path)
          application = apply_readme_family_section(
            template_partial,
            normalized_entry.fetch(:package, {}),
            normalized_entry.fetch(:family, {}),
            destination_content,
            config
          )
          if application[:changed]
            if write_changes
              FileUtils.mkdir_p(File.dirname(full_path))
              File.write(full_path, application[:content])
            end
            report[:changed_count] += 1
            report[:created_count] += 1 if created
          end
          report[:entries] << {
            id: normalized_entry.fetch(:id).to_s,
            readme_path: readme_path,
            changed: application[:changed],
            created: created && application[:changed]
          }
        end
        report
      end

      def merge_prepared_content_from_registry(registry, entry)
        family = entry.dig(:classification, :family) || entry.dig('classification', 'family')
        adapter = registry[family.to_s]
        unless adapter
          return {
            ok: false,
            diagnostics: [{
              severity: 'error',
              category: 'configuration_error',
              message: "missing family adapter for #{family}"
            }],
            policies: []
          }
        end

        adapter.call(deep_dup(entry))
      end

      def registered_adapter_families(registry)
        registry.keys.map(&:to_s).sort
      end

      def report_template_directory_registry_session(mode, entries, registry, result = nil)
        normalized_mode = mode.to_s
        raise ArgumentError, "unsupported template session mode: #{mode}" unless MODES.include?(normalized_mode)

        {
          mode: normalized_mode,
          adapter_families: registered_adapter_families(registry),
          diagnostics: Array(result&.dig(:apply_result, :diagnostics) || result&.dig('apply_result', 'diagnostics')),
          runner_report: Ast::Merge.report_template_directory_runner(entries, result)
        }
      end

      def default_family_merge_adapter_registry(allowed_families = nil)
        allowed = Array(allowed_families).map(&:to_s)
        include_family = lambda do |family|
          allowed.empty? || allowed.include?(family)
        end

        registry = {}
        if include_family.call('markdown')
          begin
            require 'markly-merge'
            registry['markdown'] = lambda do |entry|
              {
                ok: true,
                output: Markly::Merge::SmartMerger.new(
                  entry[:prepared_template_content],
                  entry[:destination_content],
                  add_template_only_nodes: true
                ).merge,
                diagnostics: [],
                policies: []
              }
            end
          rescue LoadError
            begin
              require 'markdown-merge'
              registry['markdown'] = lambda do |entry|
                Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], 'markdown')
              end
            rescue LoadError
            end
          end
        end
        if include_family.call('toml')
          begin
            require 'toml-merge'
            registry['toml'] = lambda do |entry|
              Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], 'toml')
            end
          rescue LoadError
          end
        end
        if include_family.call('ruby')
          begin
            require 'prism-merge'
            registry['ruby'] = lambda do |entry|
              Prism::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], 'ruby')
            end
          rescue LoadError
            begin
              require 'ruby-merge'
              registry['ruby'] = lambda do |entry|
                Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], 'ruby')
              end
            rescue LoadError
            end
          end
        end

        registry
      end

      def report_template_directory_session(mode, entries, result = nil)
        normalized_mode = mode.to_s
        raise ArgumentError, "unsupported template session mode: #{mode}" unless MODES.include?(normalized_mode)

        {
          mode: normalized_mode,
          runner_report: Ast::Merge.report_template_directory_runner(entries, result)
        }
      end

      def plan_template_directory_session_from_directories(template_root, destination_root,
                                                           context, default_strategy, overrides, replacements, config = nil)
        entries = Ast::Merge.plan_template_tree_execution_from_directories(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        )
        report_template_directory_session(:plan, entries)
      end

      def apply_template_directory_session_to_directory(template_root, destination_root,
                                                        context, default_strategy, overrides, replacements, config = nil, &merge_callback)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config,
          &merge_callback
        )
        report_template_directory_session(:apply, result[:execution_plan], result)
      end

      def reapply_template_directory_session_to_directory(template_root, destination_root,
                                                          context, default_strategy, overrides, replacements, config = nil, &merge_callback)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config,
          &merge_callback
        )
        report_template_directory_session(:reapply, result[:execution_plan], result)
      end

      def apply_template_directory_session_with_registry_to_directory(template_root, destination_root,
                                                                      context, default_strategy, overrides, replacements, registry, config = nil)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        ) do |entry|
          merge_prepared_content_from_registry(registry, entry)
        end
        report_template_directory_registry_session(:apply, result[:execution_plan], registry, result)
      end

      def apply_template_directory_session_with_default_registry_to_directory(template_root, destination_root,
                                                                              context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        registry = default_family_merge_adapter_registry(allowed_families)
        apply_template_directory_session_with_registry_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          registry,
          config
        )
      end

      def required_families(entries)
        Array(entries).filter_map do |entry|
          next unless (entry[:execution_action] || entry['execution_action']).to_s == 'merge_prepared_content'

          entry.dig(:classification, :family) || entry.dig('classification', 'family')
        end.uniq.sort
      end

      def report_adapter_capabilities(entries, registry)
        available = registered_adapter_families(registry)
        required = required_families(entries)
        missing = required - available
        {
          required_families: required,
          adapter_families: available,
          missing_families: missing,
          ready: missing.empty?
        }
      end

      def report_adapter_capabilities_from_directories(template_root, destination_root,
                                                       context, default_strategy, overrides, replacements, registry, config = nil)
        entries = Ast::Merge.plan_template_tree_execution_from_directories(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        )
        report_adapter_capabilities(entries, registry)
      end

      def report_default_adapter_capabilities_from_directories(template_root, destination_root,
                                                               context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        report_adapter_capabilities_from_directories(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          default_family_merge_adapter_registry(allowed_families),
          config
        )
      end

      def report_template_directory_session_envelope(session_report, adapter_capabilities)
        {
          session_report: session_report,
          adapter_capabilities: adapter_capabilities
        }
      end

      def plan_template_directory_session_envelope_from_directories(template_root, destination_root,
                                                                    context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        report_template_directory_session_envelope(
          plan_template_directory_session_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            config
          ),
          report_default_adapter_capabilities_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        )
      end

      def apply_template_directory_session_envelope_with_default_registry_to_directory(template_root, destination_root,
                                                                                       context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        report_template_directory_session_envelope(
          apply_template_directory_session_with_default_registry_to_directory(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          ),
          report_default_adapter_capabilities_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        )
      end

      def report_template_directory_session_status(envelope)
        session_report = envelope[:session_report] || envelope['session_report'] || {}
        adapter_capabilities = envelope[:adapter_capabilities] || envelope['adapter_capabilities'] || {}
        runner_report = session_report[:runner_report] || session_report['runner_report'] || {}
        plan_report = runner_report[:plan_report] || runner_report['plan_report'] || {}
        entries = Array(plan_report[:entries] || plan_report['entries'])
        plan_summary = plan_report[:summary] || plan_report['summary'] || {}
        apply_report = runner_report[:apply_report] || runner_report['apply_report'] || {}
        apply_entries = Array(apply_report[:entries] || apply_report['entries'])
        apply_summary = apply_report[:summary] || apply_report['summary'] || {}
        blocked_paths = (entries + apply_entries).filter_map do |entry|
          status = entry[:status] || entry['status']
          destination_path = entry[:destination_path] || entry['destination_path']
          destination_path if status.to_s == 'blocked' && destination_path
        end.uniq.sort
        missing_families = Array(
          adapter_capabilities[:missing_families] || adapter_capabilities['missing_families']
        ).map(&:to_s).sort

        {
          mode: (session_report[:mode] || session_report['mode']).to_s,
          ready: !(adapter_capabilities[:ready] || adapter_capabilities['ready']).nil? && blocked_paths.empty?,
          missing_families: missing_families,
          blocked_paths: blocked_paths,
          planned_write_count: plan_summary.fetch(:create, plan_summary.fetch('create', 0)) +
            plan_summary.fetch(:update, plan_summary.fetch('update', 0)),
          written_count: apply_summary.fetch(:written, apply_summary.fetch('written', 0))
        }
      end

      def template_directory_session_status_envelope(status)
        {
          kind: 'template_directory_session_status',
          version: SESSION_STATUS_TRANSPORT_VERSION,
          status: deep_dup(status)
        }
      end

      def import_template_directory_session_status_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_status'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_status envelope kind.' }]
        end
        unless envelope[:version] == SESSION_STATUS_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_status envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:status]), nil]
      end

      def report_template_directory_session_diagnostics(mode, entries, adapter_capabilities, result = nil)
        missing_families = Array(
          adapter_capabilities[:missing_families] || adapter_capabilities['missing_families']
        ).map(&:to_s)
        blocked_apply_paths = Array(
          result&.dig(:apply_report, :entries) || result&.dig('apply_report', 'entries')
        ).filter_map do |entry|
          destination_path = entry[:destination_path] || entry['destination_path']
          status = entry[:status] || entry['status']
          destination_path if status.to_s == 'blocked' && destination_path
        end

        diagnostics = Array(entries).flat_map do |entry|
          path = entry[:destination_path] || entry['destination_path'] ||
                 entry[:logical_destination_path] || entry['logical_destination_path']
          family = entry.dig(:classification, :family) || entry.dig('classification', 'family')
          result_entries = []
          block_reason = entry[:block_reason] || entry['block_reason']
          if (entry[:blocked] || entry['blocked']) && block_reason.to_s == 'unresolved_tokens'
            result_entries << {
              severity: 'error',
              category: 'configuration_error',
              reason: 'unresolved_tokens',
              path: path,
              message: "unresolved template tokens block #{path}"
            }
          end
          if (entry[:execution_action] || entry['execution_action']).to_s == 'merge_prepared_content' &&
             missing_families.include?(family.to_s) &&
             (result.nil? || blocked_apply_paths.empty? || blocked_apply_paths.include?(path))
            result_entries << {
              severity: 'error',
              category: 'configuration_error',
              reason: 'missing_family_adapter',
              path: path,
              family: family.to_s,
              message: "missing family adapter for #{family} blocks #{path}"
            }
          end
          result_entries
        end.sort_by { |entry| [entry[:path].to_s, entry[:reason].to_s, entry[:family].to_s] }

        {
          mode: mode.to_s,
          ready: diagnostics.empty?,
          diagnostics: diagnostics
        }
      end

      def template_directory_session_diagnostics_envelope(diagnostics)
        {
          kind: 'template_directory_session_diagnostics',
          version: SESSION_DIAGNOSTICS_TRANSPORT_VERSION,
          diagnostics: deep_dup(diagnostics)
        }
      end

      def import_template_directory_session_diagnostics_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_diagnostics'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_diagnostics envelope kind.' }]
        end
        unless envelope[:version] == SESSION_DIAGNOSTICS_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_diagnostics envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:diagnostics]), nil]
      end

      def plan_template_directory_session_diagnostics_from_directories(template_root, destination_root,
                                                                       context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        entries = Ast::Merge.plan_template_tree_execution_from_directories(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        )
        report_template_directory_session_diagnostics(
          :plan,
          entries,
          report_adapter_capabilities(entries, default_family_merge_adapter_registry(allowed_families))
        )
      end

      def apply_template_directory_session_diagnostics_with_default_registry_to_directory(template_root, destination_root,
                                                                                          context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        registry = default_family_merge_adapter_registry(allowed_families)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        ) do |entry|
          merge_prepared_content_from_registry(registry, entry)
        end
        report_template_directory_session_diagnostics(
          :apply,
          result[:execution_plan],
          report_adapter_capabilities(result[:execution_plan], registry),
          result
        )
      end

      def report_template_directory_session_outcome(session_report, status, diagnostics)
        {
          session_report: session_report,
          status: status,
          diagnostics: diagnostics
        }
      end

      def plan_template_directory_session_outcome_from_directories(template_root, destination_root,
                                                                   context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        report_template_directory_session_outcome(
          plan_template_directory_session_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            config
          ),
          report_template_directory_session_status(
            plan_template_directory_session_envelope_from_directories(
              template_root,
              destination_root,
              context,
              default_strategy,
              overrides,
              replacements,
              allowed_families,
              config
            )
          ),
          plan_template_directory_session_diagnostics_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        )
      end

      def apply_template_directory_session_outcome_with_default_registry_to_directory(template_root, destination_root,
                                                                                      context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        registry = default_family_merge_adapter_registry(allowed_families)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        ) do |entry|
          merge_prepared_content_from_registry(registry, entry)
        end
        session_report = report_template_directory_registry_session(:apply, result[:execution_plan], registry, result)
        capabilities = report_adapter_capabilities(result[:execution_plan], registry)
        report_template_directory_session_outcome(
          session_report,
          report_template_directory_session_status(
            report_template_directory_session_envelope(session_report, capabilities)
          ),
          report_template_directory_session_diagnostics(
            :apply,
            result[:execution_plan],
            capabilities,
            result
          )
        )
      end

      def reapply_template_directory_session_outcome_with_default_registry_to_directory(template_root, destination_root,
                                                                                        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        registry = default_family_merge_adapter_registry(allowed_families)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        ) do |entry|
          merge_prepared_content_from_registry(registry, entry)
        end
        session_report = report_template_directory_registry_session(:reapply, result[:execution_plan], registry, result)
        capabilities = report_adapter_capabilities(result[:execution_plan], registry)
        report_template_directory_session_outcome(
          session_report,
          report_template_directory_session_status(
            report_template_directory_session_envelope(session_report, capabilities)
          ),
          report_template_directory_session_diagnostics(
            :reapply,
            result[:execution_plan],
            capabilities,
            result
          )
        )
      end

      def run_template_directory_session_with_default_registry_to_directory(mode, template_root, destination_root,
                                                                            context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        case mode.to_s
        when 'plan'
          plan_template_directory_session_outcome_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        when 'apply'
          apply_template_directory_session_outcome_with_default_registry_to_directory(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        when 'reapply'
          reapply_template_directory_session_outcome_with_default_registry_to_directory(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        else
          raise ArgumentError, "unsupported template session mode: #{mode}"
        end
      end

      def run_template_directory_session_with_options(options)
        request = report_template_directory_session_options_request(options)
        unless request[:ready]
          return report_template_directory_session_configuration_outcome(
            request[:mode],
            { mode: request[:mode], ready: request[:ready], diagnostics: request[:diagnostics] }
          )
        end
        normalized = deep_dup(request[:resolved_options])
        run_template_directory_session_with_default_registry_to_directory(
          normalized[:mode] || normalized['mode'],
          normalized[:template_root] || normalized['template_root'],
          normalized[:destination_root] || normalized['destination_root'],
          normalized[:context] || normalized['context'] || {},
          normalized[:default_strategy] || normalized['default_strategy'],
          normalized[:overrides] || normalized['overrides'] || [],
          normalized[:replacements] || normalized['replacements'] || {},
          normalized[:allowed_families] || normalized['allowed_families'],
          normalized[:config] || normalized['config']
        )
      end

      def report_template_directory_session_options_configuration(options)
        normalized = deep_dup(options)
        diagnostics = []
        unless (normalized[:destination_root] || normalized['destination_root']).to_s.length.positive?
          diagnostics << {
            severity: 'error',
            category: 'configuration_error',
            reason: 'missing_destination_root',
            message: 'missing destination_root for template session'
          }
        end
        unless (normalized[:template_root] || normalized['template_root']).to_s.length.positive?
          diagnostics << {
            severity: 'error',
            category: 'configuration_error',
            reason: 'missing_template_root',
            message: 'missing template_root for template session'
          }
        end
        diagnostics.sort_by! { |entry| entry[:reason] }
        {
          mode: normalize_session_mode(normalized[:mode] || normalized['mode']),
          ready: diagnostics.empty?,
          diagnostics: diagnostics
        }
      end

      def report_template_directory_session_options_request(options)
        normalized = deep_dup(options)
        configuration = report_template_directory_session_options_configuration(normalized)
        {
          request_kind: 'options',
          mode: configuration[:mode],
          ready: configuration[:ready],
          diagnostics: deep_dup(configuration[:diagnostics]),
          resolved_options: configuration[:ready] ? compact_session_request_options(normalized) : nil
        }
      end

      def report_template_directory_session_profile_configuration(profiles, profile_name, overrides)
        normalized_profiles = deep_dup(profiles)
        normalized_overrides = deep_dup(overrides)
        diagnostics = report_template_directory_session_options_configuration(normalized_overrides)[:diagnostics]
        profile = normalized_profiles[profile_name.to_s] || normalized_profiles[profile_name.to_sym]
        mode = normalize_session_mode(
          normalized_overrides[:mode] || normalized_overrides['mode'] || profile&.[](:mode) || profile&.[]('mode')
        )
        unless profile
          diagnostics << {
            severity: 'error',
            category: 'configuration_error',
            reason: 'missing_profile',
            message: "unknown template session profile: #{profile_name}"
          }
        end
        diagnostics.sort_by! { |entry| entry[:reason] }
        {
          mode: mode,
          ready: diagnostics.empty?,
          diagnostics: diagnostics
        }
      end

      def report_template_directory_session_profile_request(profiles, profile_name, overrides)
        configuration = report_template_directory_session_profile_configuration(profiles, profile_name, overrides)
        {
          request_kind: 'profile',
          profile_name: profile_name.to_s,
          mode: configuration[:mode],
          ready: configuration[:ready],
          diagnostics: deep_dup(configuration[:diagnostics]),
          resolved_options: if configuration[:ready]
                              compact_session_request_options(
                                resolve_template_directory_session_options(profiles, profile_name, overrides)
                              )
                            end
        }
      end

      def report_template_directory_session_configuration_outcome(mode, diagnostics)
        report_template_directory_session_outcome(
          report_template_directory_session(mode, []),
          {
            mode: mode,
            ready: false,
            missing_families: [],
            blocked_paths: [],
            planned_write_count: 0,
            written_count: 0
          },
          diagnostics
        )
      end

      def template_directory_session_outcome_envelope(outcome)
        {
          kind: 'template_directory_session_outcome',
          version: SESSION_OUTCOME_TRANSPORT_VERSION,
          outcome: deep_dup(outcome)
        }
      end

      def import_template_directory_session_outcome_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_outcome'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_outcome envelope kind.' }]
        end
        unless envelope[:version] == SESSION_OUTCOME_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_outcome envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:outcome]), nil]
      end

      def run_template_directory_session_request(request)
        normalized = deep_dup(request)
        unless normalized[:ready] || normalized['ready']
          mode = normalized[:mode] || normalized['mode']
          diagnostics = normalized[:diagnostics] || normalized['diagnostics'] || []
          return report_template_directory_session_configuration_outcome(
            mode,
            { mode: mode, ready: false, diagnostics: diagnostics }
          )
        end

        run_template_directory_session_with_options(
          normalized[:resolved_options] || normalized['resolved_options']
        )
      end

      def template_directory_session_request_envelope(request)
        {
          kind: 'template_directory_session_request',
          version: SESSION_REQUEST_TRANSPORT_VERSION,
          request: deep_dup(request)
        }
      end

      def import_template_directory_session_request_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_request'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_request envelope kind.' }]
        end
        unless envelope[:version] == SESSION_REQUEST_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_request envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:request]), nil]
      end

      def run_template_directory_session_runner_request(request, profiles = {})
        normalized = deep_dup(request)
        request_kind = normalized[:request_kind] || normalized['request_kind']
        if request_kind.to_s == 'profile'
          return run_template_directory_session_request(
            report_template_directory_session_profile_request(
              profiles,
              normalized[:profile_name] || normalized['profile_name'],
              normalized[:overrides] || normalized['overrides'] || {}
            )
          )
        end

        run_template_directory_session_request(
          report_template_directory_session_options_request(
            normalized[:options] || normalized['options'] || {}
          )
        )
      end

      def template_directory_session_runner_request_envelope(request)
        {
          kind: 'template_directory_session_runner_request',
          version: SESSION_RUNNER_REQUEST_TRANSPORT_VERSION,
          request: deep_dup(request)
        }
      end

      def import_template_directory_session_runner_request_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_runner_request'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_runner_request envelope kind.' }]
        end
        unless envelope[:version] == SESSION_RUNNER_REQUEST_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_runner_request envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:request]), nil]
      end

      def report_template_directory_session_runner_input(input)
        normalized = deep_dup(input)
        request_kind = (normalized[:request_kind] || normalized['request_kind']).to_s
        options = {
          mode: normalized[:mode] || normalized['mode'],
          template_root: normalized[:template_root] || normalized['template_root'],
          destination_root: normalized[:destination_root] || normalized['destination_root'],
          context: normalized[:context] || normalized['context'] || {},
          default_strategy: normalized[:default_strategy] || normalized['default_strategy'] || 'merge',
          overrides: normalized[:overrides] || normalized['overrides'] || [],
          replacements: normalized[:replacements] || normalized['replacements'] || {},
          allowed_families: if normalized.key?(:allowed_families) || normalized.key?('allowed_families')
                              normalized[:allowed_families] || normalized['allowed_families']
                            end
        }
        if request_kind == 'profile'
          return {
            request_kind: 'profile',
            profile_name: normalized[:profile_name] || normalized['profile_name'],
            overrides: begin
              sparse = {
                mode: normalized[:mode] || normalized['mode'],
                template_root: normalized[:template_root] || normalized['template_root'],
                destination_root: normalized[:destination_root] || normalized['destination_root']
              }
              context = normalized[:context] || normalized['context']
              sparse[:context] = context if context.is_a?(Hash) && (context[:project_name] || context['project_name'])
              strategy = normalized[:default_strategy] || normalized['default_strategy']
              sparse[:default_strategy] = strategy if strategy && strategy != 'merge'
              overrides = normalized[:overrides] || normalized['overrides']
              sparse[:overrides] = overrides if overrides.is_a?(Array) && !overrides.empty?
              replacements = normalized[:replacements] || normalized['replacements']
              sparse[:replacements] = replacements if replacements.is_a?(Hash) && !replacements.empty?
              allowed_families = normalized.key?(:allowed_families) ? normalized[:allowed_families] : normalized['allowed_families']
              sparse[:allowed_families] = allowed_families unless allowed_families.nil?
              sparse
            end
          }
        end

        {
          request_kind: 'options',
          options: options
        }
      end

      def report_template_directory_session_runner_payload(payload)
        normalized = deep_dup(payload)
        request_kind = normalized[:request_kind] || normalized['request_kind']
        request_kind = if request_kind.to_s.empty?
                         if normalized.key?(:profile_name) || normalized.key?('profile_name') ||
                            normalized.key?(:default_profile_name) || normalized.key?('default_profile_name')
                           'profile'
                         else
                           'options'
                         end
                       else
                         request_kind.to_s
                       end

        result = {
          request_kind: request_kind,
          mode: normalized[:mode] || normalized['mode'],
          template_root: normalized[:template_root] || normalized['template_root'],
          destination_root: normalized[:destination_root] || normalized['destination_root'],
          context: normalized[:context] || normalized['context'] || {},
          default_strategy: normalized[:default_strategy] || normalized['default_strategy'] || 'merge',
          overrides: normalized[:overrides] || normalized['overrides'] || [],
          replacements: normalized[:replacements] || normalized['replacements'] || {},
          allowed_families: if normalized.key?(:allowed_families) || normalized.key?('allowed_families')
                              normalized.key?(:allowed_families) ? normalized[:allowed_families] : normalized['allowed_families']
                            end
        }
        profile_name = normalized[:profile_name] || normalized['profile_name'] ||
                       normalized[:default_profile_name] || normalized['default_profile_name']
        result[:profile_name] = profile_name if profile_name
        result
      end

      def run_template_directory_session_runner_payload(payload, profiles = {})
        run_template_directory_session_runner_request(
          report_template_directory_session_runner_input(
            report_template_directory_session_runner_payload(payload)
          ),
          profiles
        )
      end

      def template_directory_session_runner_payload_envelope(payload)
        {
          kind: 'template_directory_session_runner_payload',
          version: SESSION_RUNNER_PAYLOAD_TRANSPORT_VERSION,
          payload: deep_dup(payload)
        }
      end

      def import_template_directory_session_runner_payload_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_runner_payload'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_runner_payload envelope kind.' }]
        end
        unless envelope[:version] == SESSION_RUNNER_PAYLOAD_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_runner_payload envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:payload]), nil]
      end

      def run_template_directory_session_entrypoint(entrypoint, profiles = {})
        normalized = deep_dup(entrypoint)
        if normalized[:payload] || normalized['payload']
          return run_template_directory_session_runner_payload(
            normalized[:payload] || normalized['payload'],
            profiles
          )
        end

        if normalized[:request] || normalized['request']
          return run_template_directory_session_runner_request(
            normalized[:request] || normalized['request'],
            profiles
          )
        end

        report_template_directory_session_configuration_outcome(
          'plan',
          { mode: 'plan', ready: false, diagnostics: [] }
        )
      end

      def report_template_directory_session_entrypoint(entrypoint)
        normalized = deep_dup(entrypoint)
        if normalized[:payload] || normalized['payload']
          return {
            source_kind: 'payload',
            runner_request: report_template_directory_session_runner_input(
              report_template_directory_session_runner_payload(
                normalized[:payload] || normalized['payload']
              )
            )
          }
        end

        if normalized[:request] || normalized['request']
          return {
            source_kind: 'request',
            runner_request: normalized[:request] || normalized['request']
          }
        end

        {
          source_kind: '',
          runner_request: { request_kind: 'options' }
        }
      end

      def report_template_directory_session_resolution(entrypoint, profiles = {})
        entrypoint_report = report_template_directory_session_entrypoint(entrypoint)
        {
          source_kind: entrypoint_report[:source_kind],
          runner_request: entrypoint_report[:runner_request],
          session_request: report_session_request_from_runner_request(
            entrypoint_report[:runner_request],
            profiles
          )
        }
      end

      def report_template_directory_session_inspection(entrypoint, profiles = {})
        entrypoint_report = report_template_directory_session_entrypoint(entrypoint)
        session_resolution = report_template_directory_session_resolution(entrypoint, profiles)
        session_request = session_resolution[:session_request]

        unless session_request[:ready] && session_request[:resolved_options]
          return {
            entrypoint_report: entrypoint_report,
            session_resolution: session_resolution,
            adapter_capabilities: {
              required_families: [],
              adapter_families: [],
              missing_families: [],
              ready: false
            },
            status: {
              mode: session_request[:mode],
              ready: false,
              missing_families: [],
              blocked_paths: [],
              planned_write_count: 0,
              written_count: 0
            },
            diagnostics: {
              mode: session_request[:mode],
              ready: false,
              diagnostics: session_request[:diagnostics]
            }
          }
        end

        resolved = session_request[:resolved_options]
        adapter_capabilities = report_default_adapter_capabilities_from_directories(
          resolved[:template_root],
          resolved[:destination_root],
          resolved[:context],
          resolved[:default_strategy],
          resolved[:overrides],
          resolved[:replacements],
          resolved[:allowed_families],
          resolved[:config]
        )
        session_report = plan_template_directory_session_from_directories(
          resolved[:template_root],
          resolved[:destination_root],
          resolved[:context],
          resolved[:default_strategy],
          resolved[:overrides],
          resolved[:replacements],
          resolved[:config]
        )

        {
          entrypoint_report: entrypoint_report,
          session_resolution: session_resolution,
          adapter_capabilities: adapter_capabilities,
          status: report_template_directory_session_status(
            report_template_directory_session_envelope(session_report, adapter_capabilities)
          ),
          diagnostics: plan_template_directory_session_diagnostics_from_directories(
            resolved[:template_root],
            resolved[:destination_root],
            resolved[:context],
            resolved[:default_strategy],
            resolved[:overrides],
            resolved[:replacements],
            resolved[:allowed_families],
            resolved[:config]
          )
        }
      end

      def template_directory_session_inspection_envelope(inspection)
        {
          kind: 'template_directory_session_inspection',
          version: SESSION_INSPECTION_TRANSPORT_VERSION,
          inspection: deep_dup(inspection)
        }
      end

      def import_template_directory_session_inspection_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_inspection'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_inspection envelope kind.' }]
        end
        unless envelope[:version] == SESSION_INSPECTION_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_inspection envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:inspection]), nil]
      end

      def run_template_directory_session_dispatch(operation, entrypoint, profiles = {})
        case operation.to_s
        when 'inspect'
          {
            operation: operation.to_s,
            inspection: report_template_directory_session_inspection(entrypoint, profiles),
            outcome: nil
          }
        when 'run'
          {
            operation: operation.to_s,
            inspection: nil,
            outcome: run_template_directory_session_entrypoint(entrypoint, profiles)
          }
        else
          raise ArgumentError, "unsupported template directory session operation: #{operation}"
        end
      end

      def run_template_directory_session_command(command, profiles = {})
        normalized = deep_dup(command)
        run_template_directory_session_dispatch(
          normalized[:operation] || normalized['operation'],
          {
            payload: normalized[:payload] || normalized['payload'],
            request: normalized[:request] || normalized['request']
          },
          profiles
        )
      end

      def run_template_directory_session_command_payload(command, profiles = {})
        normalized = deep_dup(command)
        run_template_directory_session_command(
          {
            operation: normalized[:operation] || normalized['operation'],
            payload: {
              request_kind: normalized[:request_kind] || normalized['request_kind'],
              default_profile_name: normalized[:default_profile_name] || normalized['default_profile_name'],
              profile_name: normalized[:profile_name] || normalized['profile_name'],
              mode: normalized[:mode] || normalized['mode'],
              template_root: normalized[:template_root] || normalized['template_root'],
              destination_root: normalized[:destination_root] || normalized['destination_root'],
              context: normalized[:context] || normalized['context'],
              default_strategy: normalized[:default_strategy] || normalized['default_strategy'],
              overrides: normalized[:overrides] || normalized['overrides'],
              replacements: normalized[:replacements] || normalized['replacements'],
              allowed_families: normalized.key?(:allowed_families) ? normalized[:allowed_families] : normalized['allowed_families']
            }
          },
          profiles
        )
      end

      def run_template_directory_session(invocation, profiles = {})
        normalized = deep_dup(invocation)
        if normalized[:payload] || normalized['payload'] || normalized[:request] || normalized['request']
          return run_template_directory_session_command(normalized, profiles)
        end

        run_template_directory_session_command_payload(normalized, profiles)
      end

      def template_directory_session_entrypoint_envelope(entrypoint)
        {
          kind: 'template_directory_session_entrypoint',
          version: SESSION_ENTRYPOINT_TRANSPORT_VERSION,
          entrypoint: deep_dup(entrypoint)
        }
      end

      def import_template_directory_session_entrypoint_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_entrypoint'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_entrypoint envelope kind.' }]
        end
        unless envelope[:version] == SESSION_ENTRYPOINT_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_entrypoint envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:entrypoint]), nil]
      end

      def template_directory_session_command_envelope(command)
        {
          kind: 'template_directory_session_command',
          version: SESSION_COMMAND_TRANSPORT_VERSION,
          command: deep_dup(command)
        }
      end

      def import_template_directory_session_command_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_command'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_command envelope kind.' }]
        end
        unless envelope[:version] == SESSION_COMMAND_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_command envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:command]), nil]
      end

      def template_directory_session_command_payload_envelope(payload)
        {
          kind: 'template_directory_session_command_payload',
          version: SESSION_COMMAND_PAYLOAD_TRANSPORT_VERSION,
          payload: deep_dup(payload)
        }
      end

      def import_template_directory_session_command_payload_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_command_payload'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_command_payload envelope kind.' }]
        end
        unless envelope[:version] == SESSION_COMMAND_PAYLOAD_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_command_payload envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:payload]), nil]
      end

      def template_directory_session_invocation_envelope(invocation)
        {
          kind: 'template_directory_session_invocation',
          version: SESSION_INVOCATION_TRANSPORT_VERSION,
          invocation: deep_dup(invocation)
        }
      end

      def import_template_directory_session_invocation_envelope(envelope)
        unless envelope[:kind] == 'template_directory_session_invocation'
          return [nil,
                  { category: 'kind_mismatch',
                    message: 'expected template_directory_session_invocation envelope kind.' }]
        end
        unless envelope[:version] == SESSION_INVOCATION_TRANSPORT_VERSION
          return [nil,
                  { category: 'unsupported_version',
                    message: "unsupported template_directory_session_invocation envelope version #{envelope[:version]}." }]
        end

        [deep_dup(envelope[:invocation]), nil]
      end

      def report_session_request_from_runner_request(request, profiles = {})
        normalized = deep_dup(request)
        if (normalized[:request_kind] || normalized['request_kind']).to_s == 'profile'
          return report_template_directory_session_profile_request(
            profiles,
            normalized[:profile_name] || normalized['profile_name'],
            normalized[:overrides] || normalized['overrides'] || {}
          )
        end

        report_template_directory_session_options_request(
          normalized[:options] || normalized['options'] || {}
        )
      end

      def resolve_template_directory_session_options(profiles, profile_name, overrides)
        profile = profiles[profile_name.to_s] || profiles[profile_name.to_sym]
        return nil unless profile

        normalized_profile = deep_dup(profile)
        normalized_overrides = deep_dup(overrides)
        {
          mode: normalized_overrides[:mode] || normalized_overrides['mode'] ||
            normalized_profile[:mode] || normalized_profile['mode'],
          template_root: normalized_overrides[:template_root] || normalized_overrides['template_root'],
          destination_root: normalized_overrides[:destination_root] || normalized_overrides['destination_root'],
          context: normalized_overrides[:context] || normalized_overrides['context'] ||
            normalized_profile[:context] || normalized_profile['context'] || {},
          default_strategy: normalized_overrides[:default_strategy] || normalized_overrides['default_strategy'] ||
            normalized_profile[:default_strategy] || normalized_profile['default_strategy'],
          overrides: normalized_overrides[:overrides] || normalized_overrides['overrides'] ||
            normalized_profile[:overrides] || normalized_profile['overrides'] || [],
          replacements: normalized_overrides[:replacements] || normalized_overrides['replacements'] ||
            normalized_profile[:replacements] || normalized_profile['replacements'] || {},
          allowed_families: normalized_overrides[:allowed_families] || normalized_overrides['allowed_families'] ||
            normalized_profile[:allowed_families] || normalized_profile['allowed_families'],
          config: normalized_overrides[:config] || normalized_overrides['config'] ||
            normalized_profile[:config] || normalized_profile['config']
        }
      end

      def run_template_directory_session_with_profile(profiles, profile_name, overrides)
        request = report_template_directory_session_profile_request(profiles, profile_name, overrides)
        unless request[:ready]
          return report_template_directory_session_configuration_outcome(
            request[:mode],
            { mode: request[:mode], ready: request[:ready], diagnostics: request[:diagnostics] }
          )
        end

        run_template_directory_session_with_options(request[:resolved_options])
      end

      private

      def replace_or_insert_markdown_heading_section(content, heading_text, heading_level, replacement)
        normalized = content.to_s.rstrip
        return "#{replacement}\n" if normalized.empty?

        lines = normalized.split("\n")
        heading = "#{'#' * heading_level} #{heading_text}"
        heading_index = lines.index { |line| line.strip == heading }
        if heading_index
          section_end = lines.length
          ((heading_index + 1)...lines.length).each do |index|
            level = markdown_heading_level(lines[index])
            if level.positive? && level <= heading_level
              section_end = index
              break
            end
          end
          output_lines = lines[0...heading_index] + replacement.split("\n")
          output_lines << '' if section_end < lines.length && lines[section_end] != ''
          output_lines += lines[section_end..]
          return "#{output_lines.join("\n")}\n"
        end

        insert_at = readme_family_section_insert_index(lines)
        output_lines = lines[0...insert_at]
        output_lines << '' if output_lines.any? && output_lines.last != ''
        output_lines += replacement.split("\n")
        output_lines << '' if insert_at < lines.length && lines[insert_at] != ''
        output_lines += lines[insert_at..]
        "#{output_lines.join("\n")}\n"
      end

      def markdown_heading_level(line)
        match = line.to_s.strip.match(/\A(#+)\s/)
        match && match[1].length <= 6 ? match[1].length : 0
      end

      def readme_family_section_insert_index(lines)
        index = 0
        if markdown_heading_level(lines[0]) == 1
          index = 1
          index += 1 while index < lines.length && lines[index] == ''
        end
        while index < lines.length
          if lines[index] == ''
            index += 1 while index < lines.length && lines[index] == ''
            return index
          end
          index += 1
        end
        lines.length
      end

      def deep_dup(value)
        Ast::Merge.deep_dup(value)
      end

      def normalize_session_mode(mode)
        normalized_mode = mode.to_s
        MODES.include?(normalized_mode) ? normalized_mode : 'plan'
      end

      def compact_session_request_options(options)
        normalized = deep_dup(options)
        normalized.delete(:config)
        normalized.delete('config')
        normalized
      end
    end
  end
end
