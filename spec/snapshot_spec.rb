# frozen_string_literal: true

# What the viewer shows for a history.
RSpec.describe ClaudeLimitWatch::Snapshot, '.build' do
  # The snapshot of `records` as of `now`.
  def snap(records, now)
    ClaudeLimitWatch::Snapshot.build(records, now, rate_window: 30)
  end

  it 'reports no data' do
    expect(snap([], NOW)[:no_data]).to be(true)
  end

  it 'reports only failed checks' do
    st = snap([error_record(NOW - 60)], NOW)
    expect(st[:no_reading]).to be(true)
    expect(st[:error]).to eq('HTTP 429 from usage endpoint')
  end

  it 'reports no active window' do
    rec = { t: NOW - 60, interval: 5.0, util: 12.0, resets: NOW - 120 }
    expect(snap([rec], NOW)[:no_window]).to be_within(1e-9).of(12.0)
  end

  it 'reports no active window without a reset time' do
    rec = { t: NOW - 60, interval: 5.0, util: 0.0, resets: nil }
    expect(snap([rec], NOW)[:no_window]).to eq(0.0)
  end

  it 'projects the current window' do
    st = snap(window_records, NOW)
    expect(st[:proj][:util]).to be_within(1e-9).of(60.0)
    expect(st[:table].size).to eq(5) # 10m 30m 1h 2h, and the whole window
    expect(st[:stale]).to be(false)
    expect(st[:error]).to be_nil
  end

  it 'counts only the current window' do
    old = { t: NOW - (400 * 60), interval: 5.0, util: 90.0, resets: NOW - (100 * 60) }
    expect(snap([old] + window_records, NOW)[:history].size).to eq(window_records.size)
  end

  it 'is stale after two intervals and a minute' do
    last = window_records.last[:t]
    expect(snap(window_records, last + 660)[:stale]).to be(false)
    expect(snap(window_records, last + 661)[:stale]).to be(true)
  end

  it 'reports a failed check after good readings, still projecting' do
    st = snap(window_records + [error_record(NOW + 60)], NOW + 61)
    expect(st[:error]).to eq('HTTP 429 from usage endpoint')
    expect(st[:error_at]).to eq(NOW + 60)
    expect(st[:proj][:util]).to be_within(1e-9).of(60.0) # from the last good reading
  end
end
