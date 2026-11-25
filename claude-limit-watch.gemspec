# frozen_string_literal: true

require 'English'
require_relative 'lib/claude_limit_watch/version'

Gem::Specification.new do |spec|
  spec.name          = 'claude-limit-watch'
  spec.version       = ClaudeLimitWatch::VERSION
  spec.authors       = ['Keith R. Bennett']
  spec.email         = ['keithrbennett@gmail.com']

  spec.summary       = "Watch the Claude subscription's 5-hour and 7-day usage limits (unofficial)"
  spec.description   = 'Records Claude subscription usage in the background and shows a terminal ' \
                       'panel projecting when the 5-hour usage limit will be reached at recent ' \
                       'burn rates, with the 7-day (weekly) usage. Unofficial: not affiliated with ' \
                       'Anthropic; uses an undocumented usage endpoint.'
  spec.license       = 'MIT'

  spec.homepage      = ClaudeLimitWatch::HOMEPAGE
  spec.required_ruby_version = '>= 2.6'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    files = Dir['lib/**/*.rb', 'exe/*', 'docs/images/*', 'README.md', 'RELEASE_NOTES.md', 'LICENSE']
    # In a git checkout, ship only tracked files, so untracked or ignored files
    # in the working tree never end up in the gem. Without git or a .git
    # directory (e.g. building from a source tarball), ship the globbed files.
    tracked = begin
      `git ls-files -z 2>#{File::NULL}`.split("\x0")
    rescue SystemCallError
      []
    end
    tracked_files = files & tracked
    $CHILD_STATUS&.success? && !tracked_files.empty? ? tracked_files : files
  end
  spec.bindir        = 'exe'
  spec.executables   = ['claude-limit-watch']
  spec.require_paths = ['lib']

  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/RELEASE_NOTES.md"
  spec.metadata['rubygems_mfa_required'] = 'true'
end
