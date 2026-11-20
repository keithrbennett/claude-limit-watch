# frozen_string_literal: true

module ClaudeLimitWatch
  # What the viewer shows for a history, as of a time.
  module Snapshot
    extend self

    # Everything the viewer needs, derived from the history `records` as of
    # `now`, with recent rates over the last `rate_window` minutes.
    def build(records, now, rate_window:)
      st = { records: records }
      return st.merge(no_data: true) if records.empty?

      last = records.last
      st[:last_t] = last[:t]
      st[:interval] = last[:interval]
      st[:stale] = now - last[:t] > (last[:interval] * 60 * 2) + 60
      if last[:error]
        st[:error] = last[:error]
        st[:error_at] = last[:t]
      end

      good = records.reject { |r| r[:error] }
      latest = good.last
      return st.merge(no_reading: true, history: []) unless latest
      if latest[:resets].nil? || latest[:resets] <= now
        return st.merge(no_window: latest[:util], history: [])
      end

      window = good.select { |r| r[:resets] && (r[:resets] - latest[:resets]).abs < 60 }
      prior = window[0...-1].map { |r| { t: r[:t], util: r[:util] } }
      args = [prior, latest[:t], latest[:util], latest[:resets]]
      proj = Projection.project(*args, rate_window: rate_window)
      st.merge(history: window, proj: proj, eta_at: proj[:eta_min] && latest[:t] + (proj[:eta_min] * 60),
               table: Projection.projection_rows(*args, rate_window: rate_window))
    end
  end
end
