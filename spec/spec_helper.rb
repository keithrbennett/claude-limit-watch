# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

# Predictable times and output.
ENV['TZ'] = 'UTC'
ENV['NO_COLOR'] = '1'

require 'rspec'
require 'claude_limit_watch'
require_relative 'support/helpers'

# Never touch the real history file.
SPEC_TMP_DIR = Dir.mktmpdir('claude-limit-watch-spec')
at_exit { FileUtils.remove_entry(SPEC_TMP_DIR) }
SPEC_HISTORY_FILE = File.join(SPEC_TMP_DIR, 'history.jsonl')
ClaudeLimitWatch::History.file = SPEC_HISTORY_FILE

RSpec.configure do |config|
  config.include SpecHelpers
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  # Specs delete the history file; make sure it's never the real one.
  config.before do
    raise "not the spec history file: #{ClaudeLimitWatch::History.file}" \
      unless ClaudeLimitWatch::History.file == SPEC_HISTORY_FILE
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
