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
      ['Time ', 'Level ', 'Window      ', 'Ends ', 'Used', "#{num(rate_window)}m Burn Rate".ljust(RATE_COL),
       ' Pace', 'Outlook'].join(' | ')
    end

    # One reading's line, from its projection (Projection.project).
    def format_line(now, p)
      rate_txt =
        if p[:recent_rate]
          "#{format('%4.1f', p[:recent_rate] * 60)}%/h (avg #{format('%.1f', p[:avg_rate] * 60)})"
        elsif p[:avg_rate]
          "#{format('%4.1f', p[:avg_rate] * 60)}%/h (avg so far)"
        else
          'rate n/a'
        end
      outlook =
        if p[:util] >= 100
          "AT LIMIT, resets in #{hm(p[:reset_min])}"
        elsif p[:eta_min] && p[:left_at_reset].nil?
          "LIMIT at #{(now + (p[:eta_min] * 60)).strftime('%H:%M')} (in #{hm(p[:eta_min])}), " \
            "#{hm(p[:reset_min] - p[:eta_min])} before reset"
        elsif p[:left_at_reset]
          "~#{p[:left_at_reset].round}% left at reset"
        else
          'not rising'
        end
      label = { ok: 'OK    ', projected: 'WARN  ', urgent: 'URGENT' }[p[:level]]
      pace = p[:pace]&.finite? ? format('%.1fx', p[:pace]) : 'n/a'
      [now.strftime('%H:%M'), label, "#{hm(p[:elapsed_min])} of 5:00", p[:resets].localtime.strftime('%H:%M'),
       format('%3d%%', p[:util].round), rate_txt.ljust(RATE_COL), pace.rjust(5), outlook].join(' | ')
    end

    # The warning that readings have stopped coming in.
    def stale_line(now, last_t)
      paint("#{now.strftime('%H:%M')} | no new readings for #{dur(now - last_t)}. #{Recorder::RESTART_HINT}", WARN)
    end

    # Prints a line per reading as they come in, until Ctrl-C.
    def run(rate_window)
      trap('INT') { puts; exit 0 }
      _pid, message = Recorder.ensure_running
      puts paint(message, GRAY)
      puts paint("Claude 5-hour limit, from #{History.file}; burn rate over the last " \
                 "#{num(rate_window)}m. Ctrl-C to quit (the recorder keeps running).", GRAY)
      puts paint(VERSION_LINE, GRAY)
      puts paint(header(rate_window), GRAY)

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
                  records.find { |r| r[:resets] && (r[:resets] - latest[:resets]).abs < 60 }
          shown_t = first ? first[:t] - 1 : (records.last ? records.last[:t] : Time.at(0))
        end
        records.each_with_index do |rec, i|
          next unless rec[:t] > shown_t

          stamp = rec[:t].strftime('%H:%M')
          if rec[:error]
            puts paint("#{stamp} | no reading: #{rec[:error]}", GRAY)
          elsif rec[:resets].nil? || rec[:resets] <= rec[:t]
            puts paint("#{stamp} | no active 5-hour window (#{rec[:util].round}% used)", GRAY)
          else
            unless window && (rec[:resets] - window).abs < 60
              puts paint("-- 5-hour window ends at #{clock(rec[:resets])} --", GRAY) if window
              window = rec[:resets]
            end
            st = Snapshot.build(records[0..i], rec[:t], rate_window: rate_window)
            puts paint(format_line(rec[:t], st[:proj]), COLORS[st[:proj][:level]]) if st[:proj]
          end
          shown_t = rec[:t]
          stale_noted = false
        end
        st = Snapshot.build(records, Time.now, rate_window: rate_window)
        if st[:stale] && !stale_noted
          puts stale_line(Time.now, st[:last_t])
          stale_noted = true
        end
        $stdout.flush
        sleep 2
      end
    end
  end
end
