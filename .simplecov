# frozen_string_literal: true

# Family root (monorepo) coverage: the aggregate suite at the repository root
# loads every member's code from gems/*/lib, so track those files here.
SimpleCov.configure do
  if SimpleCov::Configuration.instance_methods.include?(:cover)
    cover 'gems/*/lib/**/*.rb', 'gems/*/lib/**/*.rake', 'gems/*/exe/*.rb'
  else
    track_files '{gems/*/lib/**/*.rb,gems/*/lib/**/*.rake,gems/*/exe/*.rb}'
  end
  Dir.glob('gems/*').each do |dir|
    add_group File.basename(dir), "#{dir}/"
  end
end
