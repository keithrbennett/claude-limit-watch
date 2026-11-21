# frozen_string_literal: true

require 'json'
require 'time'

module ClaudeLimitWatch
  # The history file: one reading (or failed check) per line, as JSON. The
  # recorder appends to it; the viewer only reads it.
  module History
    extend self

    KEEP_DAYS = 7 # the recorder drops readings older than this

    # The history file's absolute path: $CLAUDE_LIMIT_WATCH_FILE (if set and
    # not empty), or history.jsonl in the XDG state directory. Settable, for a different file
    # (--file). Made absolute (and ~ expanded) once, here, so the viewer, the
    # recorder it starts and the stop hint all name the same file. Raises
    # ArgumentError for a path that can't be expanded, such as ~nosuchuser/x.
    def file
      @file ||= File.expand_path(env_file || default_file)
    end

    def file=(path)
      @file = path && File.expand_path(path)
    end

    # $CLAUDE_LIMIT_WATCH_FILE as given, or nil if it's unset or empty (an
    # empty path would otherwise mean the current directory).
    def env_file
      env = ENV['CLAUDE_LIMIT_WATCH_FILE']
      env unless env.nil? || env.empty?
    end

    # The history file when $CLAUDE_LIMIT_WATCH_FILE isn't set.
    def default_file
      File.join(ENV['XDG_STATE_HOME'] || File.join(Dir.home, '.local', 'state'), 'claude-limit-watch', 'history.jsonl')
    end

    # Held by the running recorder; holds its pid.
    def lock_file
      "#{file}.lock"
    end

    # The background recorder's output.
    def log_file
      File.join(File.dirname(file), 'recorder.log')
    end

    def append(rec)
      File.open(file, 'a') { |f| f.puts(JSON.generate(rec)) }
    end

    # Drop readings older than KEEP_DAYS. Writes a new file and renames it over
    # the old one, so a reader never sees a half-written file.
    def prune
      return unless File.exist?(file)

      cutoff = Time.now - (KEEP_DAYS * 86_400)
      kept = File.readlines(file).select do |line|
        Time.parse(JSON.parse(line)['t']) >= cutoff
      rescue StandardError
        false
      end
      tmp = "#{file}.tmp"
      File.write(tmp, kept.join)
      File.rename(tmp, file)
    end

    # Readings as hashes: { t:, interval:, util:, resets: } or { t:, interval:, error: }.
    # Unparseable lines (e.g. one being written right now) are skipped.
    def read
      return [] unless File.exist?(file)

      File.readlines(file).map do |line|
        h = JSON.parse(line)
        rec = { t: Time.parse(h['t']), interval: h['interval_min'].to_f }
        if h['error']
          rec.merge(error: h['error'])
        else
          rec.merge(util: h['util'].to_f, resets: h['resets_at'] && Time.parse(h['resets_at']))
        end
      rescue StandardError
        nil
      end.compact
    end

    # Reads the history file only when it has changed.
    class Cache
      def initialize
        @sig = nil
        @records = []
      end

      def records
        file = History.file
        sig = File.exist?(file) ? [File.mtime(file), File.size(file)] : nil
        if sig != @sig
          @records = History.read
          @sig = sig
        end
        @records
      end
    end
  end
end
