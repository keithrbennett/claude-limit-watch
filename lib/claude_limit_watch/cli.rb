# frozen_string_literal: true

module ClaudeLimitWatch
  # The command line.
  module CLI
    extend self

    def usage
      <<~TEXT
        Usage:
          claude-limit-watch record [interval-minutes] [--utc]
              Check usage every N minutes (default #{DEFAULT_INTERVAL_MIN}; #{MIN_INTERVAL_MIN} or more) and append
              each reading to #{History.file}.
              --utc: show times in UTC instead of local time.
          claude-limit-watch stop
              Stop the recorder for this history file. If the recorder was started
              with CLAUDE_LIMIT_WATCH_FILE set, set it to the same value here.
          claude-limit-watch [view] [rate-window-minutes]
                             [--lines] [--once] [--no-record] [--utc]
              Show the readings, first starting the recorder in the background if it
              isn't running (except with --no-record or --once).
              rate-window-minutes: the look-back for --lines output's burn rate
              (default #{DEFAULT_RATE_WINDOW_MIN}); on the panel, it adds a row if it isn't 10, 30, 60
              or 120.
              --lines:     one line per reading instead of the full-screen panel.
              --once:      print the panel once and exit (for copying).
              --no-record: don't start the recorder; just show the history file.
              --utc:       show times in UTC instead of local time.
          claude-limit-watch --help | -h
              Show this help.
          claude-limit-watch --version | -v
              Show the version.

        #{VERSION_LINE}
      TEXT
    end

    def main(argv = ARGV)
      args = argv.dup
      if (args & %w[--help -h]).any?
        puts usage
      elsif (args & %w[--version -v]).any?
        puts "claude-limit-watch #{VERSION}"
      elsif args.first == 'record'
        args.shift
        utc_option(args)
        minutes = number_arg(args[0], DEFAULT_INTERVAL_MIN, MIN_INTERVAL_MIN)
        usage_error if minutes.nil? || args.size > 1
        Recorder.run(minutes)
      elsif args.first == 'stop'
        usage_error if args.size > 1
        Recorder.stop
      else
        view(args)
      end
    end

    private

    def view(args)
      args.shift if args.first == 'view'
      utc_option(args)
      lines_mode = !args.delete('--lines').nil?
      once = !args.delete('--once').nil?
      record = args.delete('--no-record').nil?
      rate_window = number_arg(args[0], DEFAULT_RATE_WINDOW_MIN, 1)
      usage_error if rate_window.nil? || args.size > 1
      return Panel.run_once(rate_window) if once

      # Ctrl-C while the recorder starts (up to 2 seconds) exits quietly.
      trap('INT') { puts; exit 0 }
      # The viewer starts the recorder, unless told not to.
      if lines_mode || !$stdout.tty?
        pid, message = record ? Recorder.ensure_running : Recorder.status
        LinesView.run(rate_window, pid, message, record: record)
      else
        Recorder.ensure_running if record
        Panel.run(rate_window, record: record)
      end
    end

    # Takes --utc out of the arguments; times are in UTC if it was there.
    def utc_option(args)
      Format.utc = !args.delete('--utc').nil?
    end

    # The argument as a number, or the default if it's missing; nil if it
    # isn't a number at least `min`.
    def number_arg(arg, default, min)
      n = Float(arg || default)
      n.finite? && n >= min ? n : nil
    rescue ArgumentError, TypeError
      nil
    end

    def usage_error
      warn usage
      exit 1
    end
  end
end
