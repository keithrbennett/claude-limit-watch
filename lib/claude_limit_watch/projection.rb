# frozen_string_literal: true

module ClaudeLimitWatch
  # Burn rates, and where they lead: the numbers behind both views.
  #
  # `history` is the earlier readings in the 5-hour window, oldest first, as
  # { t:, util: }; `util` is the latest reading's utilization (percent) and
  # `now` its time; `resets` is when the window ends.
  module Projection
    include Format
    extend self

    URGENT_MIN = 20           # urgent when the limit is this close, whatever the pace
    URGENT_PACE = 2.0         # urgent when burning this many times the sustainable rate
    MIN_ELAPSED_MIN = 30      # no projections until this many minutes into the window
    PROJECTION_WINDOWS = [10, 30, 60, 120].freeze # look-back windows shown on the panel
    SAME_WINDOW_SECONDS = 60  # reset times this close are the same window's

    # Whether two reset times are the same window's: within a minute, since
    # the reported reset time can vary slightly between readings.
    def same_window?(resets, other)
      (resets - other).abs < SAME_WINDOW_SECONDS
    end

    # Rate (points per minute) over about the last `window` minutes, and the time
    # it actually covers, or nil when the history doesn't reach back far enough
    # (to at least 3/4 of the window). Readings come at intervals, so this uses
    # the reading closest to `window` minutes ago, allowing it to be up to 10%
    # (at least a minute) older.
    def rate_over(history, now, util, window)
      oldest = now - ((window + [window * 0.1, 1].max) * 60)
      first = history.select { |h| h[:t] >= oldest }.min_by { |h| (((now - h[:t]) / 60.0) - window).abs }
      return nil unless first

      span = (now - first[:t]) / 60.0
      span >= window * 0.75 ? [(util - first[:util]) / span, span] : nil
    end

    # Pace, projected limit time and level for a given rate.
    def assess(util, rate, reset_min)
      return { level: :urgent } if util >= 100
      return { level: :ok } unless rate && reset_min.positive?

      remaining = 100.0 - util
      a = { pace: remaining.positive? ? rate / (remaining / reset_min) : Float::INFINITY }
      a[:eta_min] = remaining / rate if rate.positive?
      hits_first = a[:eta_min] && a[:eta_min] < reset_min
      a[:left_at_reset] = remaining - (rate * reset_min) unless hits_first
      a[:level] =
        if hits_first && (a[:eta_min] <= URGENT_MIN || a[:pace] >= URGENT_PACE) then :urgent
        elsif hits_first then :projected
        else :ok
        end
      a
    end

    # Projection from the readings in the current window. Uses the recent rate
    # (the last `rate_window` minutes) when there's enough history, otherwise
    # the average since the window started.
    def project(history, now, util, resets, rate_window:)
      reset_min = (resets - now) / 60.0
      elapsed_min = WINDOW_MIN - reset_min
      avg_rate = elapsed_min.positive? ? util / elapsed_min : nil
      recent_rate, = rate_over(history, now, util, rate_window)
      rate = recent_rate || avg_rate
      { util: util, resets: resets, reset_min: reset_min, elapsed_min: elapsed_min,
        avg_rate: avg_rate, recent_rate: recent_rate, rate: rate }
        .merge(assess(util, rate, reset_min))
    end

    # One row per look-back window (PROJECTION_WINDOWS and `rate_window`), plus
    # the whole 5-hour window so far, each with its rate, where it leads
    # (assess) and the projected use at the window's end.
    # Returns nil during the window's first MIN_ELAPSED_MIN minutes: windows often
    # start with a burst (resumed sessions re-sending their whole conversation),
    # and any projection from those minutes predicts a limit hit that isn't
    # coming.
    def projection_rows(history, now, util, resets, rate_window:)
      reset_min = (resets - now) / 60.0
      elapsed = WINDOW_MIN - reset_min
      return nil if elapsed < MIN_ELAPSED_MIN

      have = history.first ? (now - history.first[:t]) / 60.0 : 0
      windows = (PROJECTION_WINDOWS + [rate_window]).map(&:to_f).uniq.sort
      rows = windows.map do |w|
        label = w >= 60 && (w % 60).zero? ? "#{(w / 60).to_i}h" : "#{num(w)}m"
        rate, span = rate_over(history, now, util, w)
        next { label: label, na: true, have: have } unless rate

        # When the history doesn't reach back the whole window, label the row
        # with what it actually covers (e.g. "1h50m" instead of "2h").
        label = span_label(span) if span < w * 0.95

        { label: label, rate: rate }.merge(assess(util, rate, reset_min))
      end
      rows << { label: 'window', rate: util / elapsed }.merge(assess(util, util / elapsed, reset_min))
      rows.each do |r|
        next if r[:na]

        r[:end_pct] = util + (r[:rate] * reset_min)
        r[:eta_at] = now + (r[:eta_min] * 60) if r[:eta_min]
      end
    end
  end
end
