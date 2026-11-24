# frozen_string_literal: true

# The release preflight, run by bin/pre-release-check (see
# docs/dev/RELEASING.md). Adapted from cov-loupe's, scaled down: it checks
# that main is clean, pushed, versioned, in the release notes, untagged, and
# green in CI, then builds the gem once, smoke-tests it in a scratch gem
# directory, and prints the commands that finish the release. It never tags,
# pushes, or publishes.

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

class PreReleaseCheck
  ROOT = File.expand_path('..', __dir__)
  GEM_NAME = 'claude-limit-watch'
  WORKFLOW = 'ci.yml'
  # A run GitHub hasn't listed yet, just after a push, is waited for this long.
  CI_WAIT_ATTEMPTS = 12
  CI_WAIT_SECONDS = 5

  class Failure < StandardError; end

  # Runs a command with extra environment; returns [stdout, stderr, success?].
  RUNNER = ->(cmd, env) do
    stdout, stderr, status = Open3.capture3(env, *cmd)
    [stdout, stderr, status.success?]
  end

  def initialize(out: $stdout, err: $stderr, runner: RUNNER, sleeper: ->(seconds) { sleep seconds })
    @out = out
    @err = err
    @runner = runner
    @sleeper = sleeper
    @notes = []
  end

  # Returns true on success; prints the reason and returns false otherwise.
  def call
    Dir.chdir(ROOT) { check_and_build }
    true
  rescue Errno::ENOENT => e # A command not found, for example gh.
    @err.puts "✗ #{e.message}. Is it installed and on PATH?"
    false
  rescue Failure, SystemCallError => e
    @err.puts "✗ #{e.message}"
    false
  end

  private def check_and_build
    check('Working tree is clean') { verify_clean }
    check('On main') { verify_main }
    check('In sync with origin/main') { verify_sync }
    @version = read_version
    @tag = "v#{@version}"
    check("Version #{@version} is in RELEASE_NOTES.md") { verify_changelog }
    check("Tag #{@tag} doesn't exist yet") { verify_tag_new }
    check("CI passed for #{@head[0, 7]}") { verify_ci }
    check("Built #{gem_file}") { build_gem }
    check('Smoke-tested the built gem') { smoke_test }
    print_next_steps
  end

  private def check(label)
    yield
    @out.puts "✓ #{label}"
    @notes.each { |note| @err.puts "  ! #{note}" }
    @notes.clear
  end

  private def fail!(message)
    raise Failure, message
  end

  # Runs a command; returns its standard output, or fails with its output.
  private def run(*cmd, env: {})
    stdout, stderr, success = @runner.call(cmd, env)
    fail!("`#{cmd.join(' ')}` failed:\n#{stderr}#{stdout}") unless success
    stdout
  end

  private def git(*args)
    run('git', *args).strip
  end

  private def verify_clean
    fail!('Uncommitted changes; commit or stash them first.') unless git('status', '--porcelain').empty?
  end

  private def verify_main
    fail!('Not on main; release from main.') unless git('rev-parse', '--abbrev-ref', 'HEAD') == 'main'
  end

  private def verify_sync
    git('fetch', 'origin', '--tags')
    @head = git('rev-parse', 'HEAD')
    remote = git('rev-parse', 'origin/main')
    return if @head == remote

    base = git('merge-base', 'HEAD', 'origin/main')
    fail!('Behind origin/main; pull first.') if base == @head
    fail!('Ahead of origin/main; push first.') if base == remote
    fail!('Diverged from origin/main; reconcile first.')
  end

  private def read_version
    source = File.read(File.join(ROOT, 'lib/claude_limit_watch/version.rb'))
    versions = source.scan(/^\s*VERSION\s*=\s*['"]([^'"]+)['"]/).flatten
    fail!('Expected one VERSION in lib/claude_limit_watch/version.rb.') unless versions.size == 1
    fail!("Invalid version: #{versions.first}") unless Gem::Version.correct?(versions.first)
    versions.first
  end

  private def verify_changelog
    changelog = File.read(File.join(ROOT, 'RELEASE_NOTES.md'))
    heading = "## #{@version}"
    unless changelog.match?(/^#{Regexp.escape(heading)} \(\d{4}-\d{2}-\d{2}\)$/)
      if changelog.match?(/^#{Regexp.escape(heading)} \(unreleased\)$/)
        fail!("Change '#{heading} (unreleased)' to '#{heading} (YYYY-MM-DD)' in RELEASE_NOTES.md.")
      end
      fail!("Add a '#{heading} (YYYY-MM-DD)' section to RELEASE_NOTES.md.")
    end

    changelog.scan(/^## (\S+) \(unreleased\)\n(.*?)(?=^## |\z)/m) do |version, entries|
      next if entries.strip.empty?

      @notes << "RELEASE_NOTES.md has entries under '## #{version} (unreleased)'; " \
                "check whether they belong in #{@version}."
    end
  end

  private def verify_tag_new
    fail!("Tag #{@tag} exists; bump the version.") unless git('tag', '-l', @tag).empty?
  end

  # Judges the newest push or manual run of ci.yml for HEAD (both run the
  # same jobs): passed, failed, or still running (watched). Just after a
  # push, GitHub may not list the run yet, so it waits for one to appear.
  private def verify_ci
    runs = ci_runs
    CI_WAIT_ATTEMPTS.times do
      break unless runs.empty?

      @out.puts "Waiting for GitHub to list a #{WORKFLOW} run for #{@head[0, 7]}..."
      @sleeper.call(CI_WAIT_SECONDS)
      runs = ci_runs
    end
    if runs.empty?
      fail!("No #{WORKFLOW} run for #{@head}. Start one: gh workflow run #{WORKFLOW} --ref main")
    end

    newest = runs.first
    id = newest['databaseId']
    if newest['status'] != 'completed'
      @out.puts "Watching CI run #{id}..."
      watch_ci(id)
    elsif newest['conclusion'] != 'success'
      fail!("CI run #{id} for HEAD ended in #{newest['conclusion']}: #{newest['url']}\n" \
            "See why: gh run view #{id} --log-failed")
    end
  end

  # Newest first, as gh lists them.
  private def ci_runs
    json = run('gh', 'run', 'list', '--workflow', WORKFLOW, '--branch', 'main', '--commit', @head,
      '--json', 'databaseId,status,conclusion,event,url', '--limit', '20')
    runs = JSON.parse(json)
    fail!("gh's run list isn't a list: #{json.strip[0, 200]}") unless runs.is_a?(Array) && runs.all?(Hash)
    runs.select { |r| %w[push workflow_dispatch].include?(r['event']) }
  rescue JSON::ParserError => e
    fail!("Couldn't read gh's run list: #{e.message}")
  end

  private def watch_ci(id)
    run('gh', 'run', 'watch', id.to_s, '--exit-status')
  rescue Failure
    fail!("CI run #{id} for HEAD failed. See why: gh run view #{id} --log-failed")
  end

  private def gem_file
    "#{GEM_NAME}-#{@version}.gem"
  end

  private def gem_path
    File.join(ROOT, gem_file)
  end

  private def build_gem
    FileUtils.rm_f(gem_file)
    run('gem', 'build', "#{GEM_NAME}.gemspec")
    fail!("#{gem_file} wasn't built.") unless File.exist?(gem_file)
    @sha256 = Digest::SHA256.file(gem_file).hexdigest
  end

  # Cleared for the smoke test, so it runs the installed gem, not this
  # checkout or its bundle, even under `bundle exec`.
  SMOKE_ENV_UNSET = %w[BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB].freeze

  # Installs the built gem into a scratch gem directory and runs it from
  # there: --version, --help, and --once on a scratch history file (--once
  # never starts a recorder).
  private def smoke_test
    Dir.mktmpdir('claude-limit-watch-smoke') do |dir|
      gem_home = File.join(dir, 'gems')
      env = SMOKE_ENV_UNSET.to_h { |name| [name, nil] }.merge('GEM_HOME' => gem_home, 'GEM_PATH' => gem_home)
      run('gem', 'install', '--local', '--no-document', '--install-dir', gem_home,
        gem_path, env: env)
      exe = [RbConfig.ruby, File.join(gem_home, 'bin', GEM_NAME)]
      version = run(*exe, '--version', env: env).strip
      fail!("The installed gem says #{version}, not #{@version}.") unless version == "#{GEM_NAME} #{@version}"
      run(*exe, '--help', env: env)
      run(*exe, '--once', '--file', File.join(dir, 'history.jsonl'), env: env)
    end
  end

  private def print_next_steps
    @out.puts <<~TEXT

      #{gem_path} is the release artifact.
      Don't rebuild it (a rerun of this script rebuilds it, with a new SHA256).
        Built from: #{@head}
        SHA256:     #{@sha256}

      To finish the release:
        git tag -a #{@tag} -m 'Version #{@version}' #{@head}
        git push origin #{@tag}
        gem push #{gem_path}
    TEXT
  end
end
