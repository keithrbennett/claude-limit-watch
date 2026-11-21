# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

# Predictable times and output.
ENV['TZ'] = 'UTC'
ENV['NO_COLOR'] = '1'
ENV.delete('CLAUDE_LIMIT_WATCH_FILE') # specs that need it set it themselves

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

  # Specs delete the history file; make sure it's never the real one. An
  # example that changes it fails, and the file is put back for the next one.
  config.around do |example|
    file = ClaudeLimitWatch::History.file
    raise "not the spec history file before the example: #{file}" unless file == SPEC_HISTORY_FILE

    example.run
    file = ClaudeLimitWatch::History.file
    raise "the example changed the history file to: #{file}" unless file == SPEC_HISTORY_FILE
  ensure
    ClaudeLimitWatch::History.file = SPEC_HISTORY_FILE
    ClaudeLimitWatch::Format.utc = nil # --utc sets it
  end

  # The spec history file stands in for the default one, as for most users;
  # specs about another history file stub default_file themselves.
  config.before do
    allow(ClaudeLimitWatch::History).to receive(:default_file).and_return(SPEC_HISTORY_FILE)
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
