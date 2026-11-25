# frozen_string_literal: true

module ClaudeLimitWatch
  # What the viewer shows for a history, as of a time.
  module Snapshot
    extend self

    # Everything the viewer needs, derived from the history `records` as of
    # `now`, with recent rates over the last `rate_window` minutes.
    def build(records, now, rate_window:)
      return { no_data: true } if records.empty?

      last = records.last
      st = { last_t: last[:t] }
      st[:stale] = now - last[:t] > (last[:interval] * 60 * 2) + 60
      if last[:error]
        st[:error] = last[:error]
        st[:error_at] = last[:t]
      end

      good = records.reject { |r| r[:error] }
      week = week(good, now)
      st[:week] = week if week
      latest = good.last
      return st unless latest
      return st.merge(no_window: latest[:util]) if latest[:resets].nil? || latest[:resets] <= now

      window = good.select { |r| r[:resets] && (r[:resets] - latest[:resets]).abs < 60 }
      prior = window[0...-1].map { |r| { t: r[:t], util: r[:util] } }
      args = [prior, latest[:t], latest[:util], latest[:resets]]
      st.merge(proj: Projection.project(*args, rate_window: rate_window),
        table: Projection.projection_rows(*args, rate_window: rate_window))
    end

    # The 7-day window, from the latest good reading: { util:, resets:,
    # locked: } (locked: at the limit), or nil when that reading hasn't it
    # (so an older reading's figure is never shown as current) or its window
    # has since reset.
    private def week(good, now)
      r = good.last
      return unless r && r[:util_7d] && r[:resets_7d] && r[:resets_7d] > now

      { util: r[:util_7d], resets: r[:resets_7d], locked: r[:util_7d] >= 100 }
    end
  end
end
