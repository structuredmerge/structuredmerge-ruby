# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'mylib'
  spec.add_development_dependency('gitmoji-regex', '~> 1.0', '>= 1.0.3')

  # HTTP recording for deterministic specs
  # In Ruby 3.5 (HEAD) the CGI library has been pared down.
  # spec.add_development_dependency("vcr", ">= 4")
  # spec.add_development_dependency("webmock", ">= 3")
end
