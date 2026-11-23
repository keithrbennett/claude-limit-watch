# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'rake', '~> 13.0'
gem 'rspec', '~> 3.0'

# RuboCop itself needs Ruby 2.7 or later; the code it checks targets 2.6.
# Pinned to the patch level, as in cov-loupe: with NewCops enabled, a new
# minor release could add offenses to unchanged code.
if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7')
  gem 'rubocop', '~> 1.92.0', require: false
  gem 'rubocop-rspec', '~> 3.10.0', require: false
end

# Coverage (./coverage, gitignored), which cov-loupe reads. SimpleCov 1.0
# through 1.2 need Ruby 3.2 or later, and 1.3 needs 3.3; on older Rubies
# the specs run without coverage. Not pinned like RuboCop: Bundler picks the
# newest release the Ruby allows (a 1.3.x pin couldn't install on 3.2), and
# a release that changed the setup calls in spec/spec_helper.rb would
# raise there, failing the run.
if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.2')
  gem 'simplecov', '>= 1.0', '< 2.0', require: false
end
