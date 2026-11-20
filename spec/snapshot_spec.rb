# frozen_string_literal: true

# What the viewer shows for a history (snapshot), and the --lines output.
RSpec.describe ClaudeLimitWatch do
  m = described_class

  describe '.snapshot' do
    it 'reports no data' do
      expect(m.snapshot([], NOW)[:no_data]).to be(true)
    end

    it 'reports only failed checks' do
      st = m.snapshot([error_record(NOW - 60)], NOW)
      expect(st[:no_reading]).to be(true)
      expect(st[:error]).to eq('HTTP 429 from usage endpoint')
    end

    it 'reports no active window' do
      rec = { t: NOW - 60, interval: 5.0, util: 12.0, resets: NOW - 120 }
      expect(m.snapshot([rec], NOW)[:no_window]).to be_within(1e-9).of(12.0)
    end

    it 'projects the current window' do
      st = m.snapshot(window_records, NOW)
      expect(st[:proj][:util]).to be_within(1e-9).of(60.0)
      expect(st[:table].size).to eq(5) # 10m 30m 1h 2h, and the whole window
      expect(st[:stale]).to be(false)
      expect(st[:error]).to be_nil
    end

    it 'counts only the current window' do
      old = { t: NOW - (400 * 60), interval: 5.0, util: 90.0, resets: NOW - (100 * 60) }
      expect(m.snapshot([old] + window_records, NOW)[:history].size).to eq(window_records.size)
    end

    it 'is stale after two intervals and a minute' do
      last = window_records.last[:t]
      expect(m.snapshot(window_records, last + 660)[:stale]).to be(false)
      expect(m.snapshot(window_records, last + 661)[:stale]).to be(true)
    end

    it 'reports a failed check after good readings, still projecting' do
      st = m.snapshot(window_records + [error_record(NOW + 60)], NOW + 61)
      expect(st[:error]).to eq('HTTP 429 from usage endpoint')
      expect(st[:error_at]).to eq(NOW + 60)
      expect(st[:proj][:util]).to be_within(1e-9).of(60.0) # from the last good reading
    end
  end

  describe '.format_line' do
    def fields(util, rate, reset_min)
      history = (5..60).step(5).map { |min| { t: NOW - (min * 60), util: util - (min * rate) } }
      p = with_rate_window(30) { ClaudeLimitWatch.project(history, NOW, util, NOW + (reset_min * 60)) }
      ClaudeLimitWatch.format_line(NOW, p).split('|').map(&:strip)
    end

    it 'formats an OK line' do
      expect(fields(50.0, 0.2, 100))
        .to eq(['08:00', 'OK', '3:20 of 5:00', '09:40', '50%', '12.0%/h (avg 15.0)', '0.4x', '~30% left at reset'])
    end

    it 'formats a WARN line' do
      f = fields(50.0, 0.6, 100)
      expect(f[1]).to eq('WARN')
      expect(f[7]).to eq('LIMIT at 09:23 (in 1:23), 0:17 before reset')
    end

    it 'formats a line at the limit' do
      f = fields(100.0, 0.5, 30)
      expect(f[1]).to eq('URGENT')
      expect(f[7]).to eq('AT LIMIT, resets in 0:30')
    end
  end

  describe '.header' do
    it 'names the rate window' do
      expect(with_rate_window(45) { m.header }).to include('45m Burn Rate')
    end
  end
end
