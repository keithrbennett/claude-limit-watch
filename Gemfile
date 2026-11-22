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
