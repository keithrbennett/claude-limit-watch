# frozen_string_literal: true

# Rates, assessments and projections: the numbers behind both views.
RSpec.describe ClaudeLimitWatch::Projection do
  m = described_class

  # Readings `minutes_ago` back, rising `per_min` points a minute to `util_now`.
  def rising(minutes_ago, util_now: 50.0, per_min: 0.2)
    minutes_ago.map { |min| { t: NOW - (min * 60), util: util_now - (min * per_min) } }
  end

  describe '.rate_over' do
    it 'needs history' do
      expect(m.rate_over([], NOW, 50.0, 30)).to be_nil
    end

    it 'uses the reading closest to the window' do
      rate, span = m.rate_over(rising([60, 55, 45, 30, 20, 10, 5]), NOW, 50.0, 30)
      expect(rate).to be_within(1e-9).of(0.2)
      expect(span).to be_within(1e-9).of(30.0)
    end

    it 'needs the history to cover 3/4 of the window' do
      expect(m.rate_over(rising([20, 15, 10, 5]), NOW, 50.0, 30)).to be_nil # 20 < 22.5

      _rate, span = m.rate_over(rising([25, 20, 15, 10, 5]), NOW, 50.0, 30)
      expect(span).to be_within(1e-9).of(25.0)
    end

    it 'allows a reading up to 10% older than the window' do
      _rate, span = m.rate_over(rising([65, 5]), NOW, 50.0, 60) # 65 <= 60 + 6
      expect(span).to be_within(1e-9).of(65.0)

      expect(m.rate_over(rising([70, 5]), NOW, 50.0, 60)).to be_nil # 70 is too old; 5 too recent
    end

    it 'allows at least a minute older for short windows' do
      _rate, span = m.rate_over(rising([6]), NOW, 50.0, 5)
      expect(span).to be_within(1e-9).of(6.0)

      expect(m.rate_over(rising([7]), NOW, 50.0, 5)).to be_nil
    end
  end

  describe '.assess' do
    it 'is urgent at the limit' do
      expect(m.assess(100.0, 0.5, 60)).to eq(level: :urgent)
    end

    it 'is ok without a rate or time left' do
      expect(m.assess(50.0, nil, 60)).to eq(level: :ok)
      expect(m.assess(50.0, 0.5, 0)).to eq(level: :ok)
    end

    it 'is ok for a rate that lasts' do
      a = m.assess(50.0, 0.1, 100.0)
      expect(a[:level]).to eq(:ok)
      expect(a[:pace]).to be_within(1e-9).of(0.2) # 0.1 against a sustainable 0.5
      expect(a[:left_at_reset]).to be_within(1e-9).of(40.0)
      expect(a[:eta_min]).to be_within(1e-9).of(500.0)
    end

    it 'is projected for a rate that runs out' do
      a = m.assess(50.0, 0.6, 100.0)
      expect(a[:level]).to eq(:projected)
      expect(a[:eta_min]).to be_within(0.01).of(83.33)
      expect(a[:left_at_reset]).to be_nil
    end

    it 'is urgent at twice the sustainable pace' do
      a = m.assess(50.0, 1.0, 100.0)
      expect(a[:pace]).to be_within(1e-9).of(2.0)
      expect(a[:level]).to eq(:urgent)
    end

    it 'is urgent when the limit is near, whatever the pace' do
      a = m.assess(90.0, 0.55, 25.0) # pace 1.4, but the limit is 18 minutes away
      expect(a[:pace]).to be < m::URGENT_PACE
      expect(a[:eta_min]).to be <= m::URGENT_MIN
      expect(a[:level]).to eq(:urgent)
    end

    it 'is urgent with the limit exactly URGENT_MIN away' do
      a = m.assess(90.0, 0.5, 30.0) # 10 points at 0.5 a minute: 20 minutes; pace 1.5
      expect(a[:eta_min]).to be_within(1e-9).of(m::URGENT_MIN)
      expect(a[:level]).to eq(:urgent)
    end

    it 'is ok for a flat rate' do
      a = m.assess(50.0, 0.0, 100.0)
      expect(a[:level]).to eq(:ok)
      expect(a[:eta_min]).to be_nil
      expect(a[:left_at_reset]).to be_within(1e-9).of(50.0)
    end
  end

  describe '.project' do
    let(:resets) { NOW + (100 * 60) }

    it 'uses the recent rate when there is history' do
      p = m.project(rising((5..60).step(5).to_a), NOW, 50.0, resets, rate_window: 30)
      expect(p[:recent_rate]).to be_within(1e-9).of(0.2)
      expect(p[:avg_rate]).to be_within(1e-9).of(0.25) # 50% in 200 minutes
      expect(p[:rate]).to be_within(1e-9).of(0.2)
      expect(p[:elapsed_min]).to be_within(1e-9).of(200.0)
      expect(p[:reset_min]).to be_within(1e-9).of(100.0)
    end

    it 'falls back to the window average' do
      p = m.project([], NOW, 50.0, resets, rate_window: 30)
      expect(p[:recent_rate]).to be_nil
      expect(p[:rate]).to be_within(1e-9).of(0.25)
    end

    it 'uses the rate window' do
      history = rising([30, 25, 20, 15, 10, 5])
      expect(m.project(history, NOW, 50.0, resets, rate_window: 30)[:recent_rate]).not_to be_nil
      expect(m.project(history, NOW, 50.0, resets, rate_window: 60)[:recent_rate]).to be_nil
    end
  end

  describe '.projection_rows' do
    def rows_for(records, rate_window: 30)
      last = records.last
      ClaudeLimitWatch::Projection.projection_rows(prior(records), last[:t], last[:util], last[:resets],
                                                   rate_window: rate_window)
    end

    it 'waits out the first minutes of the window' do
      expect(rows_for(window_records(elapsed: 25, knots: [[0, 0], [25, 10]]))).to be_nil
      expect(rows_for(window_records(elapsed: 30, knots: [[0, 0], [30, 10]]))).not_to be_nil
    end

    it 'projects the demo scenario' do
      rows = rows_for(window_records)
      expect(rows.map { |r| r[:label] }).to eq(%w[10m 30m 1h 2h window])

      resets = window_records.last[:resets]
      runs_out = rows.select { |r| r[:eta_at] && r[:eta_at] < resets }.map { |r| r[:label] }
      expect(runs_out).to eq(%w[10m 30m])
      expect(rows.last(3).map { |r| r[:end_pct].round }).to eq([90, 85, 90])
    end

    it 'adds the rate window once' do
      expect(rows_for(window_records, rate_window: 45).map { |r| r[:label] }).to eq(%w[10m 30m 45m 1h 2h window])
      expect(rows_for(window_records, rate_window: 60).map { |r| r[:label] }).to eq(%w[10m 30m 1h 2h window])
    end

    it 'marks rows without enough history' do
      rows = rows_for(window_records.last(9)) # 40 minutes of readings
      expect(rows.map { |r| r[:na] == true }).to eq([false, false, true, true, false])
      expect(rows[2][:have]).to be_within(1e-9).of(40.0)
    end

    it 'labels what a partial window covers' do
      records = window_records.select { |r| r[:t] >= NOW - (110 * 60) } # 1h50m of readings
      expect(rows_for(records)[3][:label]).to eq('1h50m')
    end
  end
end
