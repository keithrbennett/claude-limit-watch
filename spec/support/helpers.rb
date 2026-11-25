# frozen_string_literal: true

# A fixed "now": 2027-01-15 08:00 UTC. Top-level so spec blocks can see it.
NOW = Time.at(1_800_000_000)

module SpecHelpers
  # The demo scenario: 60% used 3h20m in, after an early burst and a recent
  # surge, so the 10m and 30m rates run out and the others last.
  DEMO_KNOTS = [[0, 0], [5, 8], [30, 14], [80, 30], [140, 42], [170, 47], [190, 54], [200, 60]].freeze

  # Readings every 5 minutes up to `now`, in a window `elapsed` minutes old.
  # `knots` are [minutes into the window, utilization %] points; readings are
  # interpolated between them, the way the demo history is.
  def window_records(now: NOW, elapsed: 200, knots: DEMO_KNOTS, interval: 5)
    resets = now + ((300 - elapsed) * 60)
    (interval..elapsed).step(interval).map do |min|
      a, b = knots.each_cons(2).find { |(m0, _), (m1, _)| min.between?(m0, m1) }
      util = (a[1] + ((b[1] - a[1]) * (min - a[0]).fdiv(b[0] - a[0]))).round.to_f
      { t: now - ((elapsed - min) * 60), interval: interval.to_f, util: util, resets: resets }
    end
  end

  def error_record(time, message = 'HTTP 429 from usage endpoint')
    { t: time, interval: 5.0, error: message }
  end

  # The history in the form Projection's functions take: earlier readings.
  def prior(records)
    records[0...-1].map { |r| { t: r[:t], util: r[:util] } }
  end

  # Runs the block with local time in another zone (the specs run in UTC).
  def in_zone(tz)
    saved = ENV['TZ']
    ENV['TZ'] = tz
    yield
  ensure
    ENV['TZ'] = saved
  end

  def plain(lines)
    lines.map { |l| l.gsub(ClaudeLimitWatch::Term::ANSI_RE, '') }
  end

  # The panel as plain text, for a terminal of the given width.
  def panel(records, now, cols: 120, pid: 1234, once: false, rate_window: 30, record: true)
    allow(ClaudeLimitWatch::Panel).to receive(:term_width).and_return(cols)
    st = ClaudeLimitWatch::Snapshot.build(records, now, rate_window: rate_window).merge(recorder_pid: pid)
    plain(ClaudeLimitWatch::Panel.lines(st, now, once: once, record: record))
  end
end
