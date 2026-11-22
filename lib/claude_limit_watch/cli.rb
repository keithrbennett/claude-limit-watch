# frozen_string_literal: true

module ClaudeLimitWatch
  # The command line.
  module CLI
    include Format
    extend self

    def usage
      <<~TEXT
        Usage:
          claude-limit-watch record [interval-minutes] [--utc]
              Check usage every N minutes (default #{DEFAULT_INTERVAL_MIN}; #{MIN_INTERVAL_MIN} or more) and append
              each reading to #{shown_file}.
              --utc: show times in UTC instead of local time.
          claude-limit-watch stop
              Stop the recorder for this history file: for a history file other
              than the default, give the same --file as the recorder's.
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

        Every command also takes:
          --file PATH: the history file to use (default:
                       #{home_relative(History.default_file)}).

        #{VERSION_LINE}
      TEXT
    end

    def main(argv = ARGV)
      args = argv.dup
      file_option(args)
      if (args & %w[--help -h]).any?
        puts usage
      elsif (args & %w[--version -v]).any?
        puts "claude-limit-watch #{VERSION}"
      else
        check_file
        command(args)
      end
    end

    private

    def command(args)
      if args.first == 'record'
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

    # Reports a history file path that can't be expanded (~nosuchuser) now,
    # not partway through a command.
    def check_file
      History.file
    rescue ArgumentError => e
      abort "claude-limit-watch: can't use the default history file (check HOME and XDG_STATE_HOME): #{e.message}"
    end

    # The history file for the help, with ~ for the home directory; as given,
    # if it can't be expanded, so the help still shows.
    def shown_file
      home_relative(History.file)
    rescue ArgumentError
      History.default_file
    end

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

    # Takes --file PATH (or --file=PATH) out of the arguments, and uses that
    # history file.
    def file_option(args)
      file_arg = ->(a) { a == '--file' || a.start_with?('--file=') }
      i = args.index(&file_arg)
      return unless i

      arg = args.delete_at(i)
      # A separate path can't look like an option (--file --once); with = it can.
      path = arg == '--file' ? args.delete_at(i) : arg.sub('--file=', '')
      usage_error if path.nil? || path.empty? || (arg == '--file' && path.start_with?('-')) || args.any?(&file_arg)
      begin
        History.file = path
      rescue ArgumentError => e
        abort "claude-limit-watch: can't use --file #{path}: #{e.message}"
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
