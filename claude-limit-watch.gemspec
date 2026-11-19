# frozen_string_literal: true

require_relative 'lib/claude_limit_watch/version'

Gem::Specification.new do |spec|
  spec.name          = 'claude-limit-watch'
  spec.version       = ClaudeLimitWatch::VERSION
  spec.authors       = ['Keith R. Bennett']
  spec.email         = ['keithrbennett@gmail.com']

  spec.summary       = "Watch the Claude subscription's 5-hour usage limit"
  spec.description   = 'Records Claude subscription usage in the background and shows a terminal ' \
                       'dashboard projecting when the 5-hour usage limit will be reached at recent burn rates.'
  spec.license       = 'MIT'

  spec.homepage      = 'https://github.com/keithrbennett/claude-limit-watch'
  spec.required_ruby_version = '>= 2.6'

  spec.files = Dir['lib/**/*.rb', 'exe/*', 'docs/images/*', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.bindir        = 'exe'
  spec.executables   = ['claude-limit-watch']
  spec.require_paths = ['lib']

  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'
end
