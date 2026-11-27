# frozen_string_literal: true

module ClaudeLimitWatch
  # The viewer's full-screen panel, redrawn in place each second.
  module Panel
    include Format
    include Term
    extend self

    # Projection bar fills: distinct shapes, so the parts can be told apart
    # without color too (NO_COLOR, piped --once).
    SO_FAR_CHAR = '█'
    LEFT_CHAR = '▒'
    LOCKED_CHAR = 'X'
    LOCKED_COLOR = [1, 38, 5, 196, 48, 5, 52].freeze # bold red X on a dark red background
    ACCENT_COLOR = [38, 5, 141].freeze # lavender (256-color 141): the title and the Time bar
    TITLE_RULE_COLOR = [38, 5, 97].freeze # a dimmer lavender: the rules on the title line
    WEEK_WARN_PCT = 80 # the 7-day usage turns yellow from here
    # The 7-day line at its widest: 100% used, 6 days 23 hours 59 minutes to
    # go, and a reset on a two-digit day in every time zone (Sep 15, 12:00 UTC).
    WEEK_WIDEST = [100, (7 * 86_400) - 60, Time.utc(2026, 9, 15, 12)].freeze

    # The panel's lines for a snapshot (Snapshot.build, plus :recorder_pid).
    # once: printing a single copy (--once), so use a fixed width, don't
    # truncate, and leave out the quit instruction.
    # record: whether this viewer starts the recorder (false with --no-record).
    def lines(st, now, once: false, record: true)
      w = once ? 100 : term_width
      bar_w = (w - 47).clamp(10, 50) # leaves room for the projection rows' text
      # The title line and the rule above the bottom lines end where the
      # legend does (or at the edge of a narrower terminal).
      rule_w = [[legend_width, w].min - 2, 0].max
      p = st[:proj]
      now_text = "now #{clock(now)}" # on the Time bar's second line, and at the bottom
      out = []
      blank = -> { out << '' unless out.last.empty? } # a blank line, never two
      legend_drawn = false
      title = title_line(rule_w)
      out << "  #{title}"
      week = st[:week]
      if week && !week[:locked]
        # The 7-day usage, yellow from WEEK_WARN_PCT: centered under the title
        # when the title is centered on its rule, else at the left, as it is.
        text = week_line(week, now, rule_w)
        text = text.center(rule_w).rstrip if title.include?('━')
        out << paint("  #{text}", week[:util] >= WEEK_WARN_PCT ? WARN : GRAY)
      end
      out << ''
      if week&.[](:locked)
        # The 5-hour limit doesn't matter until the 7-day one resets.
        out << paint('  The 7-day usage limit has been reached.', 1, COLORS[:urgent])
        out << paint("  It resets in #{resets_in(week[:resets] - now, week[:resets])}.", COLORS[:urgent])
        p = nil
      else
        status = headline(st, now)
        out.push("  #{status[0]}  #{status[1]}", '') if status
      end
      if p
        elapsed = WINDOW_MIN - ((p[:resets] - now) / 60.0)
        window_start = p[:resets] - (WINDOW_MIN * 60)
        used_color = p[:util] >= 100 ? [COLORS[:urgent]] : [] # normal text color unless at the limit
        out << "  Used   #{bar(p[:util] / 100.0, bar_w, *used_color)}  #{pct(p[:util])}"
        out << "  Time   #{bar(elapsed / WINDOW_MIN, bar_w, *ACCENT_COLOR)}  #{dur_m(elapsed * 60)} of 5h"
        # The window's start and end times, then the current time, under the
        # elapsed time above it.
        times = "#{clock(window_start).ljust(bar_w - 5)}#{clock(p[:resets])}"
        out << paint("         #{times}  #{now_text}", GRAY)
        if st[:table] && p[:util] < 100
          out << ''
          since = clock(window_start)
          # A heading for the bars, right above them: a blank line there would
          # push the worst case past 24 rows.
          out << paint("  If usage continues at the rate of the last ... (all: since #{since}):", GRAY)
          out.concat(projection_bar_lines(st[:table], p, bar_w, now))
          out << ''
          out << legend
          legend_drawn = true
        elsif p[:util] < 100
          out << ''
          # Projections are made as of the latest reading, so once that time
          # has passed, they start with the next one.
          start_at = window_start + (Projection::MIN_ELAPSED_MIN * 60)
          out << if now < start_at
            paint("  Projections start #{Projection::MIN_ELAPSED_MIN}m into the window " \
                  "(at #{clock(start_at)}). Before then, there is not enough data.", GRAY)
          else
            paint("  The last reading was under #{Projection::MIN_ELAPSED_MIN}m into the window; " \
                  'projections start with the next one.', GRAY)
          end
        end
      end
      if st[:error]
        blank.call
        out << paint("  Last check failed at #{clock(st[:error_at])}: #{st[:error]}", WARN)
      end
      if st[:stale] || (st[:no_data] && st[:recorder_pid].nil?)
        gap = st[:last_t] && "No new readings for #{dur_m(now - st[:last_t])}."
        hint = Recorder.stale_hint(st[:recorder_pid], record: record)
        warning = [gap, hint].compact.join(' ')
        unless warning.empty?
          blank.call
          out << paint("  #{warning}", WARN)
        end
      end
      recorder =
        if st[:recorder_pid]
          "Recorder running (pid #{st[:recorder_pid]}), writing to:"
        else
          'Recorder not running. History file:'
        end
      # Without a reading, the headline says so.
      last_reading = st[:last_t] ? last_reading_text(st[:last_t], now) : ''
      # A blank line goes above the rule only when no legend was drawn and
      # the last line isn't already blank. With a legend, the rule sits right
      # under it, or under any warning after it, with no blank line: one
      # there would push the worst case past 24 rows.
      blank.call unless legend_drawn
      # How to quit and stop the recorder (not with --once), then the current
      # time.
      footer =
        if once
          ''
        elsif st[:recorder_pid]
          "q to quit · stop the recorder with: #{Recorder.stop_command(st[:recorder_pid], brief: true)}"
        else
          'q to quit'
        end
      # Then the recorder's status, and when it last took a reading. The
      # history file gets a line of its own, since its path can be long; one
      # too long for the terminal loses its start, not its file name. With
      # --once it's whole, for copying.
      bottom, bar_col = columns([[footer, now_text], [recorder, last_reading]], rule_w)
      rule = '─' * rule_w
      rule[bar_col] = '┬' if bar_col # joins the bar below it
      out << paint("  #{rule}", GRAY)
      out.concat(bottom.map { |l| paint("  #{l}", GRAY) })
      path = home_relative(History.file)
      out << paint("  #{once ? path : shorten_left(path, w - 2)}", GRAY)
      return out if once

      out.map { |l| fit(l, w) }
    end

    # One bar per look-back window, on the same time scale as the Time bar and
    # aligned under it: the time so far, then the time you could keep working
    # at that rate, then (red) the time you'd be locked out after hitting the
    # limit, at least one column whenever there's any.
    def projection_bar_lines(rows, p, bar_w, now)
      start = p[:resets] - (WINDOW_MIN * 60)
      # Same rounding as bar(), so the time-so-far part lines up with the Time bar.
      cells = ->(t) { (((t - start) / (WINDOW_MIN * 60)) * bar_w).round.clamp(0, bar_w) }
      so_far = cells.call(now)
      rows.map do |r|
        label = (r[:label] == 'window' ? 'all' : r[:label]).ljust(6)
        next "  #{label} #{paint("not enough history yet (have #{dur_m(r[:have] * 60)})", GRAY)}" if r[:na]

        # Time left is always green; a rate that runs out is followed by red,
        # the locked-out time, and its text is red too.
        runs_out = r[:eta_at] && r[:eta_at] < p[:resets]
        if runs_out
          hit = cells.call(r[:eta_at]).clamp(so_far, bar_w - 1) # leave at least one red cell
          locked = p[:resets] - [r[:eta_at], now].max
          bar = paint(SO_FAR_CHAR * so_far, *ACCENT_COLOR) + paint(LEFT_CHAR * (hit - so_far), COLORS[:ok]) +
            paint(LOCKED_CHAR * (bar_w - hit), *LOCKED_COLOR)
          text = "limit at #{clock(r[:eta_at])} · #{dur_m(locked)} locked out"
        else
          bar = paint(SO_FAR_CHAR * so_far, *ACCENT_COLOR) + paint(LEFT_CHAR * (bar_w - so_far), COLORS[:ok])
          text = "limit not reached · #{r[:end_pct].round}% at the end"
        end
        "  #{label} #{bar}#{paint('│', GRAY)} #{paint(text, COLORS[runs_out ? :urgent : :ok])}"
      end
    end

    # Prints the panel once, without the full-screen mode, then the version
    # and project page, as quitting the full-screen panel does. Never starts
    # the recorder.
    def run_once(rate_window)
      now = Time.now
      st = Snapshot.build(History.read, now, rate_window: rate_window).merge(recorder_pid: Recorder.pid)
      puts lines(st, now, once: true, record: false) # --once never starts one
      puts paint("  #{VERSION_LINE}", GRAY)
    end

    # Shows the panel full-screen, redrawing it each second, until q or Ctrl-C.
    # CLI starts the recorder first, unless record is false (--no-record).
    def run(rate_window, record: true)
      # Read keys as they're pressed (no Enter, no echo), so q quits. Ctrl-C
      # still works. The terminal settings are restored on exit.
      keys = $stdin.tty?
      saved_tty = keys ? `stty -g`.chomp : nil
      system('stty', '-icanon', '-echo', 'min', '1') if keys
      $stdout.write("\e[?1049h\e[?25l") # alternate screen, hide cursor
      at_exit do
        system('stty', saved_tty) if saved_tty && !saved_tty.empty?
        $stdout.write("\e[?25h\e[?1049l")
        # Leave the stop instruction in the scrollback.
        pid = Recorder.pid
        puts pid ? Recorder.stop_hint(pid) : 'The recorder is not running.'
        puts VERSION_LINE
        $stdout.flush
      end
      %w[INT TERM HUP].each { |sig| trap(sig) { exit 0 } }

      cache = History::Cache.new
      pid = nil
      ticks = 0
      loop do
        pid = Recorder.pid if (ticks % 5).zero? # check every 5 seconds
        ticks += 1
        now = Time.now
        st = Snapshot.build(cache.records, now, rate_window: rate_window).merge(recorder_pid: pid)
        render(lines(st, now, record: record))
        if keys
          # Wait up to a second for a key.
          if IO.select([$stdin], nil, nil, 1) # rubocop:disable Lint/IncompatibleIoSelectWithFiberScheduler -- no fibers
            key = $stdin.read_nonblock(1, exception: false)
            exit 0 if key.is_a?(String) && key.casecmp?('q')
          end
        else
          sleep 1
        end
      end
    end

    private def bar(fraction, width, *codes)
      filled = (fraction.clamp(0.0, 1.0) * width).round
      paint('█' * filled, *codes) + paint('░' * (width - filled), GRAY)
    end

    # A status line for the states that aren't projections (no data, no active
    # window, at the limit), or nil. Projections are shown per look-back window
    # in the bars instead, so there's no single headline projection.
    private def headline(st, now)
      p = st[:proj]
      return [paint(' NO DATA ', 1, 7, GRAY), 'No readings yet in the history file (below)'] if st[:no_data]

      if st[:no_window]
        return [paint(' IDLE ', 1, 7, GRAY), "No active 5-hour window (#{st[:no_window].round}% used)"]
      end

      return [paint(' ? ', 1, 7, GRAY), 'No successful reading yet'] unless p
      return nil if p[:util] < 100

      [paint(' AT LIMIT ', 1, 7, COLORS[:urgent]),
        paint("Resets at #{clock(p[:resets])} (in #{dur_m(p[:resets] - now)})", 1, COLORS[:urgent])]
    end

    # The title line, width columns wide: the name (bold lavender) and
    # version, centered on a dimmer lavender rule. With --utc, "times in UTC"
    # follows (it covers every time on the panel). The name is letter-spaced
    # when that fits. With less room, the rule is left out, then the
    # version, then the name: "times in UTC" goes last, since it says how to
    # read every time.
    private def title_line(width)
      name = 'CLAUDE LIMIT WATCH'
      utc = ' · times in UTC' if Format.utc
      after = "v#{VERSION}#{utc}"
      rule = ->(n) { paint('━' * n, *TITLE_RULE_COLOR) }
      # The version follows the name after its word gap.
      [[name.chars.join(' '), '   '], [name, ' ']].each do |text, gap|
        rules = width - text.size - gap.size - after.size - 4 # 2 spaces either side
        next if rules < 16 # at least 8 on each side, to read as a border

        return "#{rule.call(rules / 2)}  #{paint(text, 1, *ACCENT_COLOR)}#{gap}#{paint(after, GRAY)}  " \
          "#{rule.call(rules - (rules / 2))}"
      end
      bold = paint(name, 1, *ACCENT_COLOR)
      return "#{bold} #{paint(after, GRAY)}" if width >= name.size + 1 + after.size
      return bold unless utc
      return "#{bold}#{paint(utc, GRAY)}" if width >= name.size + utc.size

      paint('times in UTC', GRAY)
    end

    # Lines of [left, right] text, width columns wide: the right text in a
    # column at the end, after a bar centered between the columns. The right
    # column has room for the usual last-reading text, so the bar stays put
    # as the times change; a longer one (an hour or more ago) moves it left.
    # With no room for the bar (and a space either side), it's left out and
    # each right text ends where the line does, or is left out if it would
    # be cut off. Returns [lines, the bar's column, or nil].
    private def columns(rows, width)
      left_w = rows.map { |left, _| left.size }.max
      usual = last_reading_text(Time.at(0), Time.at(0)).size # a reading under a minute old
      right_w = [*rows.map { |_, right| right.size }, usual].max
      gap = width - left_w - right_w
      bar_col = gap < 3 ? nil : left_w + ((gap - 1) / 2)
      lines = rows.map do |l, r|
        if bar_col
          "#{l.ljust(bar_col)}│#{' ' * (width - right_w - bar_col - 1)}#{r}"
        else
          l.size + 2 + r.size > width ? l : l + r.rjust(width - l.size)
        end
      end
      [lines.map(&:rstrip), bar_col] # an empty right text leaves no trailing spaces
    end

    # The 7-day usage, for the line under the title, width columns wide at
    # most: how much is used, how long until it resets, and when. With less
    # room, the time until it resets is left out, then the reset time; the
    # shortest form may still be cut at the terminal's edge.
    # The form is chosen by the widest it can be, not by the current text, so
    # it doesn't change as the minutes tick.
    private def week_line(week, now, width)
      @week_widths ||= week_forms(*WEEK_WIDEST).map(&:size)
      forms = week_forms(week[:util], week[:resets] - now, week[:resets])
      forms[@week_widths.index { |w| w <= width } || -1]
    end

    # The 7-day line's forms, longest first, for a usage, the seconds until it
    # resets, and the reset time.
    private def week_forms(util, left, resets)
      used = "7-day: #{util.round}% used"
      ["#{used} · resets in #{resets_in(left, resets)}",
        "#{used} · resets in #{dur_short(left)}, #{day_clock(resets)}",
        "#{used} · resets #{day_clock(resets)}",
        used]
    end

    # "1 day, 3 hours and 12 minutes, on Thu Nov 26 at 01:00"
    private def resets_in(left, resets)
      "#{dur_words(left)}, on #{date_clock(resets)}"
    end

    private def last_reading_text(time, now)
      "last reading #{clock(time)} (#{dur_m(now - time)} ago)"
    end

    # The projection bars' key: each symbol drawn as it appears in the bars.
    private def legend
      "         #{paint(SO_FAR_CHAR, *ACCENT_COLOR)}#{paint(' time so far · ', GRAY)}" \
        "#{paint(LEFT_CHAR, COLORS[:ok])}#{paint(' time left at that rate · ', GRAY)}" \
        "#{paint(LOCKED_CHAR, *LOCKED_COLOR)}#{paint(' locked out (limit reached) · │ window ends', GRAY)}"
    end

    # The legend's visible width (it's the same with or without colors).
    private def legend_width
      @legend_width ||= legend.gsub(ANSI_RE, '').size
    end

    private def render(lines)
      return if lines == @last_render

      @last_render = lines
      $stdout.write("\e[H" + lines.map { |l| "#{l}\e[K" }.join("\n") + "\e[J")
      $stdout.flush
    end
  end
end
