# frozen_string_literal: true

require 'json'

# The history file.
RSpec.describe ClaudeLimitWatch::History do
  m = described_class

  before { FileUtils.rm_f(m.file) } # spec_helper makes sure it's the spec file

  describe '.file' do
    around do |example|
      example.run
    ensure
      m.file = SPEC_HISTORY_FILE
    end

    def env(vars)
      allow(ENV).to receive(:[]).and_call_original
      vars.each { |name, value| allow(ENV).to receive(:[]).with(name).and_return(value) }
      allow(ClaudeLimitWatch::History).to receive(:default_file).and_call_original
      ClaudeLimitWatch::History.file = nil
    end

    it 'comes from CLAUDE_LIMIT_WATCH_FILE' do
      env('CLAUDE_LIMIT_WATCH_FILE' => '/x/h.jsonl')
      expect([m.file, m.lock_file, m.log_file]).to eq(['/x/h.jsonl', '/x/h.jsonl.lock', '/x/recorder.log'])
    end

    it 'makes CLAUDE_LIMIT_WATCH_FILE absolute, expanding ~' do
      env('CLAUDE_LIMIT_WATCH_FILE' => '~/h.jsonl')
      expect(m.file).to eq(File.join(Dir.home, 'h.jsonl'))
      env('CLAUDE_LIMIT_WATCH_FILE' => 'rel/h.jsonl')
      expect(m.file).to eq(File.join(Dir.pwd, 'rel/h.jsonl'))
    end

    it 'ignores an empty CLAUDE_LIMIT_WATCH_FILE, which would mean the current directory' do
      env('CLAUDE_LIMIT_WATCH_FILE' => '', 'XDG_STATE_HOME' => '/state')
      expect(m.file).to eq('/state/claude-limit-watch/history.jsonl')
    end

    it 'makes a file it is given absolute' do
      m.file = 'rel/h.jsonl'
      expect(m.file).to eq(File.join(Dir.pwd, 'rel/h.jsonl'))
    end

    it 'expands ~ in XDG_STATE_HOME' do
      env('CLAUDE_LIMIT_WATCH_FILE' => nil, 'XDG_STATE_HOME' => '~/state')
      expect(m.file).to eq(File.join(Dir.home, 'state/claude-limit-watch/history.jsonl'))
    end

    it 'is in the XDG state directory otherwise' do
      env('CLAUDE_LIMIT_WATCH_FILE' => nil, 'XDG_STATE_HOME' => '/state')
      expect(m.file).to eq('/state/claude-limit-watch/history.jsonl')
    end

    it 'defaults to ~/.local/state' do
      env('CLAUDE_LIMIT_WATCH_FILE' => nil, 'XDG_STATE_HOME' => nil)
      expect(m.file).to eq(File.join(Dir.home, '.local/state/claude-limit-watch/history.jsonl'))
    end
  end

  describe '.append and .read' do
    it 'round-trip readings and failed checks' do
      m.append('t' => NOW.iso8601, 'interval_min' => 5.0, 'util' => 42.0,
               'resets_at' => (NOW + 600).utc.iso8601)
      m.append('t' => (NOW + 300).iso8601, 'interval_min' => 5.0, 'error' => 'token expired')
      expect(m.read).to eq([{ t: NOW, interval: 5.0, util: 42.0, resets: NOW + 600 },
                            { t: NOW + 300, interval: 5.0, error: 'token expired' }])
    end

    it 'skips lines it cannot parse' do
      File.write(m.file, "#{JSON.generate('t' => NOW.iso8601, 'interval_min' => 5, 'util' => 1)}\n" \
                       "{\"t\":\"2026-11\n")
      expect(m.read.size).to eq(1)
    end

    it 'reads nothing without a file' do
      expect(m.read).to eq([])
    end
  end

  describe '.prune' do
    it 'drops readings older than KEEP_DAYS' do
      now = Time.now
      m.append('t' => (now - ((m::KEEP_DAYS + 1) * 86_400)).iso8601, 'interval_min' => 5.0, 'util' => 1.0)
      m.append('t' => now.iso8601, 'interval_min' => 5.0, 'util' => 2.0)
      m.prune
      expect(m.read.map { |r| r[:util] }).to eq([2.0])
    end

    it 'drops lines it cannot parse, and leaves no temporary file' do
      File.write(m.file, "#{JSON.generate('t' => Time.now.iso8601, 'interval_min' => 5, 'util' => 1)}\nnot json\n")
      m.prune
      expect(File.readlines(m.file).size).to eq(1)
      expect(File.exist?("#{m.file}.tmp")).to be(false)
    end
  end
end
