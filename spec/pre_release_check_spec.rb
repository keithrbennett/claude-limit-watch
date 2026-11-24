# frozen_string_literal: true

require_relative '../script/pre_release_check'

RSpec.describe PreReleaseCheck do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:head) { 'a' * 40 }
  let(:other) { 'b' * 40 }
  let(:release_notes) { "# Release Notes\n\n## 1.2.0 (2027-01-15)\n\n- A change.\n" }
  let(:passed) do
    { 'databaseId' => 7, 'status' => 'completed', 'conclusion' => 'success', 'event' => 'push' }
  end
  # What successive `gh run list` calls return (the last one repeats).
  let(:ci_lists) { [[passed]] }
  # Output by the start of the command; other commands output nothing.
  let(:outputs) do
    {
      'git rev-parse --abbrev-ref' => "main\n",
      'git rev-parse HEAD'         => "#{head}\n",
      'git rev-parse origin/main'  => "#{head}\n",
    }
  end
  # Commands that fail, by their start, with their stderr.
  let(:failures) { {} }
  let(:installed_version) { 'claude-limit-watch 1.2.0' }
  let(:commands) { [] }
  let(:envs) { {} }
  let(:runner) do
    ->(cmd, env) do
      command = cmd.join(' ')
      commands << command
      envs[command] = env
      failure = failures.find { |prefix, _| command.start_with?(prefix) }
      next ['', failure.last, false] if failure
      next ["#{installed_version}\n", '', true] if command.end_with?('claude-limit-watch --version')
      next [JSON.generate(ci_lists.size > 1 ? ci_lists.shift : ci_lists.first), '', true] if
        command.start_with?('gh run list')

      [outputs.find { |prefix, _| command.start_with?(prefix) }&.last || '', '', true]
    end
  end
  let(:sleeps) { [] }
  let(:checker) { described_class.new(out: out, err: err, runner: runner, sleeper: ->(s) { sleeps << s }) }

  before do
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with(end_with('version.rb')).and_return("  VERSION = '1.2.0'\n")
    allow(File).to receive(:read).with(end_with('RELEASE_NOTES.md')).and_return(release_notes)
    allow(FileUtils).to receive(:rm_f)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with('claude-limit-watch-1.2.0.gem').and_return(true)
    allow(Digest::SHA256).to receive(:file).and_return(instance_double(Digest::SHA256, hexdigest: 'f00d'))
  end

  it 'passes, builds and smoke-tests the gem, and prints the commands for HEAD' do
    expect(checker.call).to be(true)
    expect(commands).to include('gem build claude-limit-watch.gemspec', end_with('--help'))
    expect(commands.grep(/gem install/).first).to include('--install-dir', 'claude-limit-watch-1.2.0.gem')
    expect(out.string).to include("git tag -a v1.2.0 -m 'Version 1.2.0' #{head}", 'SHA256:     f00d')
    expect(err.string).to eq('')
    expect(Digest::SHA256).to have_received(:file).with('claude-limit-watch-1.2.0.gem')
  end

  it "prints the gem's full path for gem push" do
    checker.call
    expect(out.string).to include("gem push #{File.join(described_class::ROOT,
      'claude-limit-watch-1.2.0.gem')}")
  end

  it "smoke-tests outside this checkout's bundle, even under bundle exec" do
    checker.call
    install_env = envs.find { |command, _| command.start_with?('gem install') }.last
    expect(install_env.values_at('BUNDLER_SETUP', 'BUNDLE_GEMFILE', 'RUBYOPT', 'RUBYLIB')).to all(be_nil)
  end

  it 'never tags, pushes, or publishes' do
    checker.call
    expect(commands).not_to include(start_with('git tag -a'), start_with('git push'), start_with('gem push'))
  end

  # The smoke test must never start a recorder: --once, on a scratch file.
  it 'runs the installed gem only with --once on a scratch history file, besides --version and --help' do
    checker.call
    runs = commands.grep(%r{bin/claude-limit-watch })
    expect(runs.map { |c| c.split('bin/claude-limit-watch ').last }).to match(
      ['--version', '--help',
        a_string_matching(%r{\A--once --file .*claude-limit-watch-smoke.*/history\.jsonl\z})]
    )
  end

  [
    ['the tree is dirty', { 'git status' => " M README.md\n" }, 'Uncommitted changes'],
    ['not on main', { 'git rev-parse --abbrev-ref' => "topic\n" }, 'Not on main'],
    ['ahead of origin/main', { 'git rev-parse origin/main' => :other, 'git merge-base' => :other },
      'push first'],
    ['behind origin/main', { 'git rev-parse origin/main' => :other, 'git merge-base' => :head },
      'pull first'],
    ['diverged from origin/main', { 'git rev-parse origin/main' => :other }, 'Diverged'],
    ['the tag exists', { 'git tag' => "v1.2.0\n" }, 'Tag v1.2.0 exists'],
  ].each do |situation, overrides, message|
    it "fails when #{situation}, without building" do
      overrides.each { |prefix, value| outputs[prefix] = value.is_a?(Symbol) ? send(value) : value }
      expect(checker.call).to be(false)
      expect(err.string).to include(message)
      expect(commands).not_to include(start_with('gem build'))
    end
  end

  [
    ['an invalid version', "  VERSION = 'one'\n", 'Invalid version: one'],
    ['no version', "# nothing\n", 'Expected one VERSION'],
  ].each do |situation, source, message|
    it "fails on #{situation}" do
      allow(File).to receive(:read).with(end_with('version.rb')).and_return(source)
      expect(checker.call).to be(false)
      expect(err.string).to include(message)
    end
  end

  [
    ['no section for the version', "## 1.1.0 (2027-01-01)\n\n- Old.\n",
      "Add a '## 1.2.0 (YYYY-MM-DD)' section"],
    ['a section without a date', "## 1.2.0\n", "Add a '## 1.2.0 (YYYY-MM-DD)' section"],
    ['the version still unreleased', "## 1.2.0 (unreleased)\n",
      "Change '## 1.2.0 (unreleased)' to '## 1.2.0 (YYYY-MM-DD)'"],
    ['entries under another version', "## 1.1.1 (unreleased)\n\n- New.\n",
      "section to RELEASE_NOTES.md. Entries are under '## 1.1.1 (unreleased)'."],
  ].each do |situation, text, message|
    it "fails when the release notes have #{situation}" do
      allow(File).to receive(:read).with(end_with('RELEASE_NOTES.md')).and_return(text)
      expect(checker.call).to be(false)
      expect(err.string).to include(message)
    end
  end

  # The bare "## Unreleased" is the old form, and the form other projects use.
  ['## 1.3.0 (unreleased)', '## 1.3.0 (Unreleased)', '## Unreleased'].each do |heading|
    it "warns about entries under '#{heading}'" do
      allow(File).to receive(:read).with(end_with('RELEASE_NOTES.md'))
        .and_return("#{heading} \n\n- Forgotten.\n\n## 1.2.0 (2027-01-15)\n")
      expect(checker.call).to be(true)
      expect(err.string).to include("has entries under '#{heading}'; check whether they belong in 1.2.0.")
    end
  end

  it 'does not warn about an empty unreleased section' do
    allow(File).to receive(:read).with(end_with('RELEASE_NOTES.md'))
      .and_return("## 1.3.0 (unreleased)\n\n## 1.2.0 (2027-01-15)\n")
    expect(checker.call).to be(true)
    expect(err.string).not_to include('unreleased')
  end

  describe 'CI' do
    it 'watches the newest run while it is still in progress' do
      ci_lists.replace([[passed.merge('databaseId' => 9, 'status' => 'in_progress', 'conclusion' => nil),
        passed]])
      expect(checker.call).to be(true)
      expect(commands).to include('gh run watch 9 --exit-status')
    end

    it 'fails, naming the run, when the newest run failed, even after an older success' do
      failed = passed.merge('databaseId' => 8, 'conclusion' => 'failure', 'url' => 'https://example.test/8')
      ci_lists.replace([[failed, passed]])
      expect(checker.call).to be(false)
      expect(err.string).to include('CI run 8 for HEAD ended in failure: https://example.test/8',
        'gh run view 8 --log-failed')
    end

    it 'fails, naming the run, when a watched run fails' do
      ci_lists.replace([[passed.merge('databaseId' => 9, 'status' => 'in_progress')]])
      failures['gh run watch'] = 'failed'
      expect(checker.call).to be(false)
      expect(err.string).to include('gh run view 9 --log-failed')
    end

    it 'ignores pull request runs' do
      ci_lists.replace([[passed.merge('event' => 'pull_request')]])
      expect(checker.call).to be(false)
      expect(err.string).to include('gh workflow run ci.yml')
    end

    it 'waits for GitHub to list the run just after a push' do
      ci_lists.replace([[], [], [passed]])
      expect(checker.call).to be(true)
      expect(sleeps).to eq([5, 5])
    end

    it 'gives up waiting, and says how to start a run' do
      ci_lists.replace([[]])
      expect(checker.call).to be(false)
      expect(sleeps.size).to eq(described_class::CI_WAIT_ATTEMPTS)
      expect(err.string).to include('gh workflow run ci.yml --ref main')
    end

    it "fails cleanly when gh's JSON isn't a list of runs" do
      allow(JSON).to receive(:parse).and_return(nil)
      expect(checker.call).to be(false)
      expect(err.string).to include("gh's run list isn't a list")
    end

    it "fails cleanly when gh's output isn't JSON" do
      allow(JSON).to receive(:parse).and_raise(JSON::ParserError, 'unexpected token')
      expect(checker.call).to be(false)
      expect(err.string).to include("Couldn't read gh's run list")
    end
  end

  it 'fails with its stderr when a command fails' do
    failures['git fetch'] = 'no network'
    expect(checker.call).to be(false)
    expect(err.string).to include('`git fetch origin --tags` failed:', 'no network')
  end

  [
    [Errno::ENOENT, 'Is it installed and on PATH?'],
    [Errno::EACCES, 'Permission denied'],
  ].each do |error, message|
    it "fails cleanly on #{error}, with the right hint" do
      allow(runner).to receive(:call).and_raise(error, 'gh')
      expect(checker.call).to be(false)
      expect(err.string).to include(message)
      expect(err.string.include?('on PATH')).to eq(error == Errno::ENOENT)
    end
  end

  it "fails when the gem file wasn't built" do
    allow(File).to receive(:exist?).with('claude-limit-watch-1.2.0.gem').and_return(false)
    expect(checker.call).to be(false)
    expect(err.string).to include("claude-limit-watch-1.2.0.gem wasn't built")
  end

  context 'when the installed gem reports another version' do
    let(:installed_version) { 'claude-limit-watch 1.2.0.pre.1' }

    it 'fails' do
      expect(checker.call).to be(false)
      expect(err.string).to include('says claude-limit-watch 1.2.0.pre.1, not 1.2.0')
    end
  end
end
