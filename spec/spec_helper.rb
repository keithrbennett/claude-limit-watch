# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

# Set before loading the library, which reads these when it loads: never touch
# the real history file, and keep times and output predictable.
SPEC_TMP_DIR = Dir.mktmpdir('claude-limit-watch-spec')
ENV['CLAUDE_LIMIT_WATCH_FILE'] = File.join(SPEC_TMP_DIR, 'history.jsonl')
ENV['TZ'] = 'UTC'
ENV['NO_COLOR'] = '1'
at_exit { FileUtils.remove_entry(SPEC_TMP_DIR) }

require 'rspec'
require 'claude_limit_watch'
require_relative 'support/helpers'

RSpec.configure do |config|
  config.include SpecHelpers
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
