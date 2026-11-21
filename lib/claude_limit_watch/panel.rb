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
    ACCENT_COLOR = [38, 5, 141].freeze # lavender (256-color 141): the heading and the Time bar

    # The panel's lines for a snapshot (Snapshot.build, plus :recorder_pid).
    # once: printing a single copy (--once), so use a fixed width, don't
    # truncate, and leave out the quit instruction.
    # show_banner: false uses the one-line title even when the banner fits the
    # width; the panel redraws that way when the terminal is too short for it.
    # record: whether this viewer starts the recorder (false with --no-record).
    def lines(st, now, once: false, show_banner: true, record: true)
      w = once ? 100 : term_width
      bar_w = (w - 47).clamp(10, 50) # leaves room for the projection rows' text
      p = st[:proj]
      info = st[:last_t] ? "last reading #{clock(st[:last_t])} (#{dur_m(now - st[:last_t])} ago)" : 'no readings yet'
      info = "times in UTC · #{info}" if Format.utc # covers every time on the panel
      out = []
      blank = -> { out << '' unless out.last.empty? } # a blank line, never two
      banner_drawn = show_banner && w >= banner_rows.map(&:size).max + 4
      legend_drawn = false
      if banner_drawn
        out.concat(banner.map { |row| "  #{row}" })
        out << ''
        out << "  #{paint("Claude's 5-hour usage limit · #{info}", GRAY)}"
      else
        out << "#{paint(' Claude 5-hour limit', 1)}   #{paint(info, GRAY)}"
      end
      out << ''
      status = headline(st, now)
      out.push("  #{status[0]}  #{status[1]}", '') if status
      if p
        elapsed = WINDOW_MIN - ((p[:resets] - now) / 60.0)
        window_start = p[:resets] - (WINDOW_MIN * 60)
        used_color = p[:util] >= 100 ? [COLORS[:urgent]] : [] # normal text color unless at the limit
        out << "  Used   #{bar(p[:util] / 100.0, bar_w, *used_color)}  #{format('%3d%%', p[:util].round)}"
        out << "  Time   #{bar(elapsed / WINDOW_MIN, bar_w, *ACCENT_COLOR)}  #{dur_m(elapsed * 60)} of 5h"
        out << paint("         #{clock(window_start).ljust(bar_w - 5)}#{clock(p[:resets])}", GRAY)
        if st[:table] && p[:util] < 100
          out << ''
          out << paint("  If usage continues at the rate of the last ... (all: since #{clock(window_start)}):", GRAY)
          out << ''
          out.concat(projection_bar_lines(st[:table], p, bar_w, now))
          out << ''
          out << legend
          legend_drawn = true
        elsif p[:util] < 100
          out << ''
          start_at = clock(window_start + (Projection::MIN_ELAPSED_MIN * 60))
          out << paint("  Projections start #{Projection::MIN_ELAPSED_MIN}m into the window " \
                       "(at #{start_at}): the first minutes are too little to go on.", GRAY)
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
          "Recorder running (pid #{st[:recorder_pid]}), writing to #{home_relative(History.file)}"
        else
          "Recorder not running (history file: #{home_relative(History.file)})"
        end
      # The rule ends where the legend does (or at the edge of a narrower
      # terminal). A blank line goes above it only when no legend was drawn
      # and the last line isn't already blank. With a legend, the rule sits
      # right under it, or under any warning after it, with no blank line:
      # one there would push the worst case past 24 rows.
      blank.call unless legend_drawn
      rule_w = [[legend_width, w].min - 2, 0].max
      out << paint("  #{'─' * rule_w}", GRAY)
      unless once
        stop = st[:recorder_pid] ? " · stop the recorder with: #{Recorder.stop_command(st[:recorder_pid])}" : ''
        out << paint("  q to quit#{stop}", GRAY)
      end
      out << paint("  #{VERSION_LINE}", GRAY)
      out << paint("  #{recorder}", GRAY)
      return out if once

      # In a terminal too short for the panel, the one-line title replaces the
      # banner (4 rows fewer) rather than letting the top scroll off.
      h = term_height
      return lines(st, now, show_banner: false, record: record) if banner_drawn && h && out.size > h

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
          text = "lasts · #{r[:end_pct].round}% used at the end"
        end
        "  #{label} #{bar}#{paint('│', GRAY)} #{paint(text, COLORS[runs_out ? :urgent : :ok])}"
      end
    end

    # Prints the panel once, without the full-screen mode. Never starts the
    # recorder.
    def run_once(rate_window)
      now = Time.now
      st = Snapshot.build(History.read, now, rate_window: rate_window).merge(recorder_pid: Recorder.pid)
      puts lines(st, now, once: true, record: false) # --once never starts one
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
          if IO.select([$stdin], nil, nil, 1)
            key = $stdin.read_nonblock(1, exception: false)
            exit 0 if key.is_a?(String) && key.casecmp?('q')
          end
        else
          sleep 1
        end
      end
    end

    private

    def bar(fraction, width, *codes)
      filled = (fraction.clamp(0.0, 1.0) * width).round
      paint('█' * filled, *codes) + paint('░' * (width - filled), GRAY)
    end

    # A status line for the states that aren't projections (no data, no active
    # window, at the limit), or nil. Projections are shown per look-back window
    # in the bars instead, so there's no single headline projection.
    def headline(st, now)
      p = st[:proj]
      return [paint(' NO DATA ', 1, 7, GRAY), "No readings yet in #{History.file}"] if st[:no_data]
      return [paint(' IDLE ', 1, 7, GRAY), "No active 5-hour window (#{st[:no_window].round}% used)"] if st[:no_window]
      return [paint(' ? ', 1, 7, GRAY), 'No successful reading yet'] unless p
      return nil if p[:util] < 100

      [paint(' AT LIMIT ', 1, 7, COLORS[:urgent]),
       paint("Resets at #{clock(p[:resets])} (in #{dur_m(p[:resets] - now)})", 1, COLORS[:urgent])]
    end

    def banner_rows
      inner = "  ◆  #{'Claude Limit Watch'.upcase.chars.join(' ')}  ◆  "
      ["╔#{'═' * inner.size}╗", "║#{inner}║", "╚#{'═' * inner.size}╝"]
    end

    # The framed heading, in one color (plain when colors are off).
    def banner
      banner_rows.map { |row| paint(row, 1, *ACCENT_COLOR) }
    end

    # The projection bars' key: each symbol drawn as it appears in the bars.
    def legend
      "         #{paint(SO_FAR_CHAR, *ACCENT_COLOR)}#{paint(' time so far · ', GRAY)}#{paint(LEFT_CHAR, COLORS[:ok])}" \
        "#{paint(' time left at that rate · ', GRAY)}#{paint(LOCKED_CHAR, *LOCKED_COLOR)}" \
        "#{paint(' locked out (limit reached) · │ window ends', GRAY)}"
    end

    # The legend's visible width (it's the same with or without colors).
    def legend_width
      @legend_width ||= legend.gsub(ANSI_RE, '').size
    end

    def render(lines)
      return if lines == @last_render

      @last_render = lines
      $stdout.write("\e[H" + lines.map { |l| "#{l}\e[K" }.join("\n") + "\e[J")
      $stdout.flush
    end
  end
end
