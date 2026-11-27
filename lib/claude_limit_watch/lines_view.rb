# frozen_string_literal: true

module ClaudeLimitWatch
  # The viewer's one-line-per-reading output (--lines, or when output isn't
  # a terminal).
  module LinesView
    include Format
    include Term
    extend self

    RATE_COL = 23 # width of the burn-rate column

    def header(rate_window)
      ['Time ', 'Level ', 'Window      ', 'Ends ', 'Used', '  7d',
        "#{num(rate_window)}m Burn Rate".ljust(RATE_COL), ' Pace', 'Outlook'].join(' | ')
    end

    # One reading's line, from its projection (Projection.project) and its
    # 7-day usage (Snapshot's { util:, resets:, locked: }, or nil when there's
    # none to show). At the 7-day limit, that's the outlook, since the 5-hour
    # one doesn't matter until it resets.
    def format_line(now, p, week = nil)
      rate_txt =
        if p[:recent_rate]
          "#{format('%4.1f', p[:recent_rate] * 60)}%/h (avg #{format('%.1f', p[:avg_rate] * 60)})"
        elsif p[:avg_rate]
          "#{format('%4.1f', p[:avg_rate] * 60)}%/h (avg so far)"
        else
          'rate n/a'
        end
      week_locked = week&.[](:locked)
      outlook =
        if week_locked
          week_limit(week, now)
        elsif p[:util] >= 100
          "AT LIMIT, resets in #{hm(p[:reset_min])}"
        elsif p[:eta_min] && p[:left_at_reset].nil?
          "LIMIT at #{clock(now + (p[:eta_min] * 60))} (in #{hm(p[:eta_min])}), " \
            "#{hm(p[:reset_min] - p[:eta_min])} before reset"
        elsif p[:left_at_reset]
          "~#{p[:left_at_reset].round}% left at reset"
        else
          'not rising'
        end
      label = { ok: 'OK    ', projected: 'WARN  ', urgent: 'URGENT' }[week_locked ? :urgent : p[:level]]
      pace = p[:pace]&.finite? ? format('%.1fx', p[:pace]) : 'n/a'
      [clock(now), label, "#{hm(p[:elapsed_min])} of 5:00", clock(p[:resets]),
        pct(p[:util]), week ? pct(week[:util]) : '   -',
        rate_txt.ljust(RATE_COL), pace.rjust(5), outlook].join(' | ')
    end

    # The line for a reading with no active 5-hour window, with its 7-day
    # usage (as for format_line); at the 7-day limit, URGENT, saying so.
    def idle_line(rec, week)
      text = "#{clock(rec[:t])} | no active 5-hour window (#{rec[:util].round}% used)"
      return paint(text, GRAY) unless week
      return paint("#{text}, #{week_limit(week, rec[:t])}", COLORS[:urgent]) if week[:locked]

      paint("#{text} · 7-day #{week[:util].round}%", GRAY)
    end

    # "7-DAY LIMIT, resets Thu 01:00 (in 27h 10m)"
    private def week_limit(week, now)
      "7-DAY LIMIT, resets #{day_clock(week[:resets])} (in #{dur_m(week[:resets] - now)})"
    end

    # The warning that readings have stopped coming in. pid: the running
    # recorder's, or nil; record: as for run.
    def stale_line(now, last_t, pid, record:)
      hint = Recorder.stale_hint(pid, record: record)
      paint("#{clock(now)} | no new readings for #{dur_m(now - last_t)}.#{" #{hint}" if hint}", WARN)
    end

    # The lines before the readings. pid: the running recorder's, or nil;
    # recorder_message: what the viewer did about the recorder.
    def intro(rate_window, pid, recorder_message)
      keeps = pid ? ' (the recorder keeps running)' : ''
      [paint(recorder_message, GRAY),
        paint("Claude 5-hour and 7-day limits, from #{History.file}; burn rate over the last " \
              "#{num(rate_window)}m.#{zone_note} Ctrl-C to quit#{keeps}.", GRAY),
        paint(VERSION_LINE, GRAY),
        paint(header(rate_window), GRAY)]
    end

    # Prints a line per reading as they come in, until Ctrl-C. pid and
    # recorder_message: as for intro. record: whether this viewer started the
    # recorder (false with --no-record).
    def run(rate_window, pid, recorder_message, record: true)
      trap('INT') do
        puts
        exit 0
      end
      puts intro(rate_window, pid, recorder_message)

      cache = History::Cache.new
      shown_t = nil # time of the last reading printed
      window = nil
      stale_noted = false
      loop do
        records = cache.records
        if shown_t.nil?
          # Start with the readings in the current window (or nothing before now).
          latest = records.reject { |r| r[:error] }.last
          first = latest && latest[:resets] &&
            records.find { |r| r[:resets] && Projection.same_window?(r[:resets], latest[:resets]) }
          shown_t = if first
            first[:t] - 1
          else
            (records.last ? records.last[:t] : Time.at(0))
          end
        end
        records.each_with_index do |rec, i|
          next unless rec[:t] > shown_t

          stamp = clock(rec[:t])
          if rec[:error]
            puts paint("#{stamp} | no reading: #{rec[:error]}", GRAY)
          elsif rec[:resets].nil? || rec[:resets] <= rec[:t]
            puts idle_line(rec, Snapshot.build(records[0..i], rec[:t], rate_window: rate_window)[:week])
          else
            unless window && Projection.same_window?(rec[:resets], window)
              puts paint("-- 5-hour window ends at #{clock(rec[:resets])} --", GRAY) if window
              window = rec[:resets]
            end
            st = Snapshot.build(records[0..i], rec[:t], rate_window: rate_window)
            if st[:proj]
              week = st[:week] # as the panel shows it: none once its window has reset
              level = week&.[](:locked) ? :urgent : st[:proj][:level]
              puts paint(format_line(rec[:t], st[:proj], week), COLORS[level])
            end
          end
          shown_t = rec[:t]
          stale_noted = false
        end
        st = Snapshot.build(records, Time.now, rate_window: rate_window)
        if st[:stale] && !stale_noted
          puts stale_line(Time.now, st[:last_t], Recorder.pid, record: record)
          stale_noted = true
        end
        $stdout.flush
        sleep 2
      end
    end
  end
end
