# frozen_string_literal: true

require 'json'

# The history file.
RSpec.describe ClaudeLimitWatch do
  m = described_class

  before { FileUtils.rm_f(m::HISTORY_FILE) }

  it 'uses the spec history file, not the real one' do
    expect(m::HISTORY_FILE).to start_with(SPEC_TMP_DIR)
  end

  describe '.append_record and .read_history' do
    it 'round-trip readings and failed checks' do
      m.append_record('t' => NOW.iso8601, 'interval_min' => 5.0, 'util' => 42.0,
                      'resets_at' => (NOW + 600).utc.iso8601)
      m.append_record('t' => (NOW + 300).iso8601, 'interval_min' => 5.0, 'error' => 'token expired')
      expect(m.read_history).to eq([{ t: NOW, interval: 5.0, util: 42.0, resets: NOW + 600 },
                                    { t: NOW + 300, interval: 5.0, error: 'token expired' }])
    end

    it 'skips lines it cannot parse' do
      File.write(m::HISTORY_FILE, "#{JSON.generate('t' => NOW.iso8601, 'interval_min' => 5, 'util' => 1)}\n" \
                                  "{\"t\":\"2026-11\n")
      expect(m.read_history.size).to eq(1)
    end

    it 'reads nothing without a file' do
      expect(m.read_history).to eq([])
    end
  end

  describe '.prune_history' do
    it 'drops readings older than KEEP_DAYS' do
      now = Time.now
      m.append_record('t' => (now - ((m::KEEP_DAYS + 1) * 86_400)).iso8601, 'interval_min' => 5.0, 'util' => 1.0)
      m.append_record('t' => now.iso8601, 'interval_min' => 5.0, 'util' => 2.0)
      m.prune_history
      expect(m.read_history.map { |r| r[:util] }).to eq([2.0])
    end
  end
end
