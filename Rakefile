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

begin
  require 'rubocop/rake_task'
rescue LoadError
  # No RuboCop (it needs Ruby 2.7 or later): the other tasks still work.
  desc 'Check the style (needs RuboCop, on Ruby 2.7 or later: bundle install)'
  task(:rubocop) { abort "Can't load RuboCop. On Ruby 2.7 or later, run: bundle install" }
else
  RuboCop::RakeTask.new
end

# Not RuboCop: it can't run on Ruby 2.6, which CI also tests. CI runs it
# separately.
task default: :spec
