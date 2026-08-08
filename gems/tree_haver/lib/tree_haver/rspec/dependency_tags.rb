# frozen_string_literal: true

require 'tree_haver'

module TreeHaver
  module RSpec
    module DependencyTags
      class << self
        def configure_filters(config)
          TreeHaver::BackendRegistry.registered_tags.each do |tag|
            if TreeHaver::BackendRegistry.tag_available?(tag)
              config.filter_run_excluding("not_#{tag}": true)
            else
              config.filter_run_excluding(tag => true)
            end
          end
        end

        def available?(tag_name)
          TreeHaver::BackendRegistry.tag_available?(tag_name)
        end

        def summary
          TreeHaver::BackendRegistry.tag_summary
        end

        def reset!
          TreeHaver::BackendRegistry.clear_cache!
          TreeHaver::BackendRegistry.registered_tags.each do |tag|
            backend = TreeHaver::BackendRegistry.tag_metadata(tag)&.fetch(:backend_name, nil)
            backend ||= TreeHaver::BackendRegistry.send(:inferred_backend_name, tag)
            ivar = :"@#{backend}_available"
            remove_instance_variable(ivar) if instance_variable_defined?(ivar)
          end
        end
      end
    end
  end
end

if defined?(::RSpec)
  ::RSpec.configure do |config|
    TreeHaver::RSpec::DependencyTags.configure_filters(config)

    config.before(:suite) do
      next if ENV.fetch('TREE_HAVER_DEBUG', 'false').casecmp?('false')

      puts "\n=== TreeHaver Test Dependencies ==="
      TreeHaver::RSpec::DependencyTags.summary.each do |dep, available|
        status = available ? 'available' : 'not available'
        puts "  #{dep}: #{status}"
      end
      puts "===================================\n"
    end
  end
end
