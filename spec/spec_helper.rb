# frozen_string_literal: true

# Coverage, in ./coverage, when SimpleCov 1.x is installed (Ruby 3.2 or
# later). It starts before the library loads, so the library's lines count.
project_root = File.expand_path('..', __dir__)
report_dir = File.join(project_root, 'coverage')
begin
  require 'simplecov'
rescue LoadError => e
  # Expected below Ruby 3.2, where the Gemfile leaves SimpleCov out.
  if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.2')
    warn "Can't load SimpleCov (#{e.message}); skipping coverage"
  end
else
  # A dangling symlink counts as present: SimpleCov can't create the directory.
  report_dir_writable =
    if File.exist?(report_dir) || File.symlink?(report_dir)
      File.directory?(report_dir) && File.writable?(report_dir)
    else
      File.writable?(project_root)
    end
  if Gem::Version.new(SimpleCov::VERSION) < Gem::Version.new('1.0')
    # Possible outside Bundler; this setup needs 1.x.
    warn "SimpleCov #{SimpleCov::VERSION} is older than 1.0; skipping coverage"
  elsif !report_dir_writable
    # Writing the report would fail at exit and fail the run.
    warn "Can't write the coverage report to #{report_dir}; skipping coverage"
  else
    SimpleCov.start do
      enable_coverage :branch
      # From any working directory, measure this project and report here.
      root project_root
      coverage_dir report_dir
      # Report only lib/, including files no spec loads.
      cover 'lib/**/*.rb'
      # The gemspec loads it before SimpleCov starts, so it would show 0%.
      skip 'lib/claude_limit_watch/version.rb'
    end
  end
end

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
