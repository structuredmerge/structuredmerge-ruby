# frozen_string_literal: true

### DUPLICATE DRIFT TASKS
begin
  require "kettle/drift"
  Kettle::Drift.install_tasks
rescue LoadError
  desc("(stub) kettle:drift:check is unavailable")
  task("kettle:drift:check") do
    warn("NOTE: kettle-drift isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
  desc("(stub) kettle:drift:update is unavailable")
  task("kettle:drift:update") do
    warn("NOTE: kettle-drift isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
  desc("(stub) kettle:drift:force_update is unavailable")
  task("kettle:drift:force_update") do
    warn("NOTE: kettle-drift isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
  desc("(stub) kettle:drift is unavailable")
  task("kettle:drift" => "kettle:drift:update")
end
