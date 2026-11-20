# frozen_string_literal: true

module ClaudeLimitWatch
  # The command line.
  module CLI
    extend self

    def usage
      <<~TEXT
        Usage:
          claude-limit-watch record [interval-minutes]
              Check usage every N minutes (default #{DEFAULT_INTERVAL_MIN}; #{MIN_INTERVAL_MIN} or more) and append
              each reading to #{History.file}.
          claude-limit-watch stop
              Stop the recorder.
          claude-limit-watch [view] [rate-window-minutes] [--lines]
              Start the recorder in the background if it isn't running, then show the
              readings. rate-window-minutes: the look-back for --lines output's burn rate
              (default #{DEFAULT_RATE_WINDOW_MIN}); on the panel it adds a row if it isn't 10, 30, 60 or 120.
              --lines: one line per reading instead of the full-screen panel.
              --once:  print the panel once and exit (for copying); doesn't start the recorder.
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
      lines_mode = !args.delete('--lines').nil?
      once = !args.delete('--once').nil?
      rate_window = number_arg(args[0], DEFAULT_RATE_WINDOW_MIN, 1)
      usage_error if rate_window.nil? || args.size > 1
      if once then Panel.run_once(rate_window)
      elsif lines_mode || !$stdout.tty? then LinesView.run(rate_window)
      else Panel.run(rate_window)
      end
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
