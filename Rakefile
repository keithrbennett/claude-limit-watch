# frozen_string_literal: true

require 'bundler/gem_tasks'

begin
  require 'rspec/core/rake_task'
rescue LoadError
  # No RSpec: the other tasks still work.
end

if defined?(RSpec::Core::RakeTask)
  RSpec::Core::RakeTask.new(:spec)
else
  desc 'Run the specs (needs RSpec: bundle install)'
  task(:spec) { abort 'RSpec is not installed. Run: bundle install, then: bundle exec rake' }
end

task default: :spec
