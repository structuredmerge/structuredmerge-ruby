# frozen_string_literal: true

module Ast
  module Template
    # Converts transport shapes only; configuration resolution and planning
    # remain in Rust. No Ruby selection, template execution or writes occur here.
    module TypedCoreBridge
      REPORT_FIELDS = {
        'TemplateSessionRequestReport' => %w[request_kind profile_name mode ready diagnostics resolved_options],
        'TemplateSessionOptions' => %w[mode template_root destination_root context default_strategy overrides replacements allowed_families config],
        'TemplateDestinationContext' => %w[project_name],
        'TemplateStrategyOverride' => %w[path strategy],
        'TemplateTokenConfig' => %w[pre post separators min_segments max_segments segment_pattern],
        'SessionDiagnostic' => %w[severity category reason path family message],
        'TemplateSessionPlanReport' => %w[mode runner_report],
        'TemplateDirectoryRunnerReport' => %w[plan_report preview run_report apply_report],
        'TemplateDirectoryPlanReport' => %w[entries summary],
        'TemplateDirectoryPlanReportEntry' => %w[template_source_path logical_destination_path destination_path execution_action write_action status previewable],
        'TemplateDirectoryPlanReportSummary' => %w[create update keep blocked omitted],
        'TemplatePreviewResult' => %w[result_files created_paths updated_paths kept_paths blocked_paths omitted_paths]
      }.freeze
      OMIT_NIL = {
        'TemplateSessionRequestReport' => %w[profile_name],
        'TemplateSessionOptions' => %w[config],
        'TemplateDestinationContext' => %w[project_name],
        'TemplateTokenConfig' => %w[max_segments],
        'SessionDiagnostic' => %w[path family]
      }.freeze

      private

      def core_report(request)
        request = require_hash(normalize_transport(request))
        options = template_options(request.fetch('options'))
        result = case request.fetch('kind')
                 when 'options'
                   host.report_template_options(options)
                 when 'profile'
                   profiles = require_hash(request.fetch('profiles', {})).transform_values { |profile| template_profile(profile) }
                   host.report_template_profile(host::TemplateProfileRequest.new(
                     profile_name: request.fetch('profile_name'), profiles: profiles, options: options))
                 when 'plan'
                   host.plan_template_directory(options)
                 else
                   raise ArgumentError, "unsupported ast-template report kind #{request['kind'].inspect}"
                 end
        project_report(result).transform_keys(&:to_sym)
      end

      def normalize_transport(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, normalize_transport(item)] }
        when Array then value.map { |item| normalize_transport(item) }
        when Symbol then value.to_s
        else value
        end
      end

      def template_fields(value)
        value = require_hash(value)
        fields = %w[mode default_strategy replacements].to_h { |field| [field.to_sym, value.fetch(field)] }
        fields[:replacements] = require_hash(fields[:replacements])
        fields[:context] = host::TemplateDestinationContext.new(project_name: require_hash(value.fetch('context'))['project_name'])
        overrides = value.fetch('overrides')
        raise TypeError, 'template overrides must be an array' unless overrides.is_a?(Array)

        fields[:overrides] = overrides.map do |entry|
          entry = require_hash(entry)
          host::TemplateStrategyOverride.new(path: entry.fetch('path'), strategy: entry.fetch('strategy'))
        end
        fields[:allowed_families] = value['allowed_families']
        fields[:config] = unless value['config'].nil?
                            config = require_hash(value['config'])
                            args = %w[pre post separators min_segments segment_pattern].to_h { |key| [key.to_sym, config.fetch(key)] }
                            host::TemplateTokenConfig.new(**args, max_segments: config['max_segments'])
                          end
        fields
      end

      def require_hash(value)
        raise TypeError, 'template request fields must be objects' unless value.is_a?(Hash)

        value
      end

      def template_options(value)
        host::TemplateSessionOptions.new(**template_fields(value),
          template_root: value.fetch('template_root'), destination_root: value.fetch('destination_root'))
      end

      def template_profile(value)
        host::DirectorySessionProfile.new(**template_fields(value))
      end

      def project_report(value)
        case value
        when Hash then value.transform_values { |item| project_report(item) }
        when Array then value.map { |item| project_report(item) }
        when Symbol then value.to_s
        when NilClass, String, Numeric, TrueClass, FalseClass then value
        else
          type = value.class.name.delete_prefix('StructuredmergeCore::')
          REPORT_FIELDS.fetch(type).each_with_object({}) do |field, result|
            item = value.public_send(field)
            next if item.nil? && OMIT_NIL.fetch(type, []).include?(field)

            result[field] = project_report(item)
          end
        end
      end
    end
  end
end
