# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Parses and validates a compact merge-ruleset document into normalized attributes.
      class Parser
        REQUIRED_DIRECTIVES = %i[format owners match read attach].freeze
        OPTIONAL_SINGLE_VALUE_DIRECTIVES = %i[comment_style render].freeze
        MULTI_VALUE_DIRECTIVES = %i[capability logical_owner repair surface delegate].freeze
        KNOWN_DIRECTIVES = (REQUIRED_DIRECTIVES + OPTIONAL_SINGLE_VALUE_DIRECTIVES + MULTI_VALUE_DIRECTIVES).freeze

        READ_STRATEGIES = %i[
          source_augmented_portable_write
          native_read_portable_write
          native_mutation
        ].freeze

        IDENTIFIER_RE = /\A[A-Za-z][A-Za-z0-9_.-]*\z/
        TOKEN_RE = /\A[!-~]+\z/

        attr_reader :source, :path, :directives, :capabilities, :logical_owners, :repair_policies, :surfaces,
                    :delegation_policies

        class << self
          def parse(source, path: nil)
            new(source, path: path).parse
          end
        end

        def initialize(source, path: nil)
          @source = source.to_s
          @path = path
          @directives = []
          @capabilities = {}
          @logical_owners = {}
          @repair_policies = {}
          @surfaces = []
          @delegation_policies = []
          @parsed_values = {}
        end

        def parse
          parse_source!
          validate_required_directives!

          {
            source: source,
            path: path,
            directives: directives.dup,
            capabilities: capabilities.dup,
            logical_owners: logical_owners.dup,
            repair_policies: repair_policies.dup,
            surfaces: surfaces.map(&:dup),
            delegation_policies: delegation_policies.map(&:dup)
          }.merge(@parsed_values)
        end

        private

        def parse_source!
          source.each_line.with_index(1) do |raw_line, line_number|
            stripped = raw_line.strip
            next if stripped.empty?
            next if stripped.start_with?('#')

            parse_directive_line!(stripped, line_number)
          end
        end

        def parse_directive_line!(line, line_number)
          tokens = line.split(/\s+/)
          directive_token = tokens.shift
          directive = parse_identifier!(directive_token, line_number, field: :directive).to_sym

          validate_known_directive!(directive, line_number)
          validate_token_list!(tokens, line_number)

          case directive
          when *REQUIRED_DIRECTIVES, *OPTIONAL_SINGLE_VALUE_DIRECTIVES
            parse_single_value_directive!(directive, tokens, line_number)
          when :capability
            parse_capability!(tokens, line_number)
          when :logical_owner
            parse_logical_owner!(tokens, line_number)
          when :repair
            parse_repair_policy!(tokens, line_number)
          when :surface
            parse_surface!(tokens, line_number)
          when :delegate
            parse_delegate!(tokens, line_number)
          end

          directives << {
            name: directive,
            arguments: tokens.dup,
            line_number: line_number
          }
        end

        def parse_single_value_directive!(directive, tokens, line_number)
          if tokens.length != 1
            raise ArgumentError, "Directive #{directive} on line #{line_number} requires exactly 1 argument"
          end

          value = parse_scalar(tokens.first, line_number)

          case directive
          when :format, :owners, :match, :comment_style, :render
            value = value.to_sym
          when :read
            value = parse_strategy!(value, READ_STRATEGIES, directive, line_number)
          when :attach
            value = parse_strategy!(
              value,
              ProfileVocabulary::ATTACHMENT_STRATEGIES.keys,
              directive,
              line_number
            )
          end

          value = validate_owner_selector!(value, line_number) if directive == :owners
          value = validate_match_key!(value, line_number) if directive == :match

          if @parsed_values.key?(directive)
            raise ArgumentError,
                  "Duplicate directive #{directive} on line #{line_number}"
          end

          @parsed_values[directive] = value
        end

        def parse_capability!(tokens, line_number)
          if tokens.length != 2
            raise ArgumentError, "Directive capability on line #{line_number} requires exactly 2 arguments"
          end

          name = parse_identifier!(tokens[0], line_number, field: :capability).to_sym
          raise ArgumentError, "Duplicate capability #{name} on line #{line_number}" if capabilities.key?(name)

          capabilities[name] = parse_scalar(tokens[1], line_number)
        end

        def parse_logical_owner!(tokens, line_number)
          if tokens.length != 2
            raise ArgumentError, "Directive logical_owner on line #{line_number} requires exactly 2 arguments"
          end

          owner_kind = parse_identifier!(tokens[0], line_number, field: :logical_owner).to_sym
          if logical_owners.key?(owner_kind)
            raise ArgumentError,
                  "Duplicate logical_owner #{owner_kind} on line #{line_number}"
          end

          logical_owners[owner_kind] = parse_scalar(tokens[1], line_number).to_sym
        end

        def parse_repair_policy!(tokens, line_number)
          if tokens.length != 2
            raise ArgumentError, "Directive repair on line #{line_number} requires exactly 2 arguments"
          end

          kind = parse_identifier!(tokens[0], line_number, field: :repair).to_sym
          raise ArgumentError, "Duplicate repair #{kind} on line #{line_number}" if repair_policies.key?(kind)

          repair_policies[kind] =
            Ast::Merge::Healer.normalize_mode(parse_identifier!(tokens[1], line_number, field: :repair_handling))
        end

        def parse_surface!(tokens, line_number)
          if tokens.length != 2
            raise ArgumentError, "Directive surface on line #{line_number} requires exactly 2 arguments"
          end

          name = parse_identifier!(tokens[0], line_number, field: :surface).to_sym
          raise ArgumentError, "Duplicate surface #{name} on line #{line_number}" if surfaces.any? do |surface|
            surface[:name] == name
          end

          surfaces << {
            name: name,
            selector: parse_identifier!(tokens[1], line_number, field: :surface_selector).to_sym
          }
        end

        def parse_delegate!(tokens, line_number)
          if tokens.length != 2
            raise ArgumentError, "Directive delegate on line #{line_number} requires exactly 2 arguments"
          end

          surface_name = parse_identifier!(tokens[0], line_number, field: :delegate_surface).to_sym
          if delegation_policies.any? { |policy| policy[:surface_name] == surface_name }
            raise ArgumentError, "Duplicate delegate #{surface_name} on line #{line_number}"
          end

          delegation_policies << {
            surface_name: surface_name,
            strategy: parse_identifier!(tokens[1], line_number, field: :delegate_strategy).to_sym
          }
        end

        def validate_required_directives!
          missing = REQUIRED_DIRECTIVES.reject { |directive| @parsed_values.key?(directive) }
          return if missing.empty?

          raise ArgumentError, "Ruleset missing required directives: #{missing.join(', ')}"
        end

        def validate_known_directive!(directive, line_number)
          return if KNOWN_DIRECTIVES.include?(directive)

          raise ArgumentError, "Unknown directive #{directive} on line #{line_number}"
        end

        def validate_token_list!(tokens, line_number)
          tokens.each do |token|
            next if TOKEN_RE.match?(token) && !token.include?('#') && !token.include?('"')

            raise ArgumentError, "Invalid token #{token.inspect} on line #{line_number}"
          end
        end

        def parse_identifier!(token, line_number, field:)
          return token if IDENTIFIER_RE.match?(token)

          raise ArgumentError, "Invalid #{field} #{token.inspect} on line #{line_number}"
        end

        def parse_strategy!(value, allowed_values, directive, line_number)
          strategy = value.to_sym
          return strategy if allowed_values.include?(strategy)

          raise ArgumentError, "Unknown #{directive} strategy #{value.inspect} on line #{line_number}"
        end

        def validate_owner_selector!(value, line_number)
          owner_selector = value.to_sym
          return owner_selector if ProfileVocabulary.known_owner_selector?(owner_selector)

          raise ArgumentError, "Unknown owner selector #{value.inspect} on line #{line_number}"
        end

        def validate_match_key!(value, line_number)
          match_key = value.to_sym
          return match_key if ProfileVocabulary.known_match_key?(match_key)

          raise ArgumentError, "Unknown match key #{value.inspect} on line #{line_number}"
        end

        def parse_scalar(token, line_number)
          return true if token == 'true'
          return false if token == 'false'
          return token if IDENTIFIER_RE.match?(token)
          return token if TOKEN_RE.match?(token) && !token.include?('#') && !token.include?('"')

          raise ArgumentError, "Invalid scalar #{token.inspect} on line #{line_number}"
        end
      end
    end
  end
end
