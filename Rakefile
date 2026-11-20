# frozen_string_literal: true

require 'bundler/gem_tasks'

begin
  require 'rspec/core/rake_task'
rescue LoadError => e
  # No RSpec: the other tasks still work.
  desc 'Run the specs (needs RSpec: bundle install)'
  task(:spec) { abort "Can't load RSpec (#{e.message}). Run: bundle install, then: bundle exec rake" }
else
  RSpec::Core::RakeTask.new(:spec)
end

task default: :spec
