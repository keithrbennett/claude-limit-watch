# frozen_string_literal: true

require 'fileutils'
require 'rbconfig'
require 'shellwords'
require 'time'

module ClaudeLimitWatch
  # The recorder: checks the usage at intervals and appends each reading to
  # the history file. Also finds, starts and stops a running recorder.
  module Recorder
    include Format
    extend self

    # Records every `minutes` minutes until stopped. Exits if another recorder
    # is running.
    def run(minutes)
      FileUtils.mkdir_p(File.dirname(History.file))
      # Open, and locked, for as long as the recorder runs.
      lock = File.open(History.lock_file, File::RDWR | File::CREAT, 0o644) # rubocop:disable Style/FileOpen
      unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        warn "Another recorder is already running (pid #{File.read(History.lock_file).strip}). " \
             'Only one can run at a time.'
        exit 1
      end
      lock.truncate(0)
      lock.write(Process.pid.to_s)
      lock.flush
      # HUP isn't trapped: under nohup it stays ignored, so closing the terminal
      # that started the viewer doesn't stop a background recorder.
      %w[INT TERM].each { |sig| trap(sig) { exit 0 } }

      puts "Recording the Claude 5-hour and 7-day usage every #{num(minutes)}m to #{History.file} " \
           "(pid #{Process.pid}).#{zone_note} Stop with Ctrl-C or: #{stop_command(Process.pid)}"
      last_prune = nil
      loop do
        if last_prune.nil? || Time.now - last_prune > 3600
          History.prune
          last_prune = Time.now
        end
        record_once(minutes)
        $stdout.flush
        sleep(minutes * 60)
      end
    end

    # Checks the usage now, and appends the reading (or the error) to the
    # history file and the log.
    def record_once(minutes)
      now = Time.now
      reading = UsageApi.fetch_usage
      stamp = clock(now, seconds: true)
      if reading.is_a?(String)
        History.append('t' => now.iso8601, 'interval_min' => minutes, 'error' => reading)
        puts "#{stamp}  error: #{reading}"
      else
        rec = { 't' => now.iso8601, 'interval_min' => minutes, 'util' => reading[:util],
                'resets_at' => reading[:resets]&.utc&.iso8601 }
        if reading[:util_7d]
          rec.merge!('util_7d' => reading[:util_7d], 'resets_7d_at' => reading[:resets_7d]&.utc&.iso8601)
        end
        History.append(rec)
        window = reading[:resets] ? "window ends #{clock(reading[:resets])}" : 'no active window'
        week = reading[:util_7d] ? "  7d #{pct(reading[:util_7d])}" : ''
        puts "#{stamp}  #{pct(reading[:util])}  #{window}#{week}"
      end
    end

    # Whether something holds the lock file's lock. The recorder holds it for
    # as long as it runs, so it's the reliable sign of a running recorder.
    def lock_held?
      File.open(History.lock_file, File::RDWR) { |f| held?(f) }
    rescue SystemCallError
      false
    end

    # The running recorder's pid, or nil: the pid in the lock file, while the
    # lock is held (checked again after reading it, in case the recorder just
    # exited). nil for a held lock without a pid: a recorder in the instant
    # between taking the lock and writing its pid (wait_for_pid waits that
    # out), or something that isn't a recorder. So it's never a pid to show
    # or signal that isn't in a held lock.
    def pid
      File.open(History.lock_file, File::RDWR) do |f|
        next nil unless held?(f)

        found = f.read.to_i
        found.positive? && held?(f) ? found : nil
      end
    rescue SystemCallError
      nil
    end

    # The pid of a recorder that's starting, once it has written it; nil if
    # none appears within 2 seconds.
    def wait_for_pid
      20.times do
        sleep 0.1
        found = pid
        return found if found
      end
      nil
    end

    # Starts `record` in the background with nohup, in its own process group so
    # Ctrl-C in the viewer's terminal doesn't reach it, recording to this
    # process's history file (given with --file), with --utc if this process
    # has it. Returns its pid (or nil if it didn't come up).
    def start
      log = History.log_file
      FileUtils.mkdir_p(File.dirname(log))
      child = Process.spawn('nohup', RbConfig.ruby, EXECUTABLE, 'record', '--file', History.file,
        *('--utc' if Format.utc),
        in: File::NULL, out: [log, 'a'], err: %i[child out], pgroup: true)
      Process.detach(child)
      wait_for_pid
    end

    # What to do when readings have stopped coming in, or nil. pid: the
    # running recorder's, or nil. record: whether this viewer starts the
    # recorder (not with --no-record or --once); restarting it the same way
    # also keeps its history file. Short, for the panel, which
    # truncates lines to the terminal's width.
    def stale_hint(pid, record:)
      if pid
        "Check the output of the recorder (pid #{pid})"
      elsif record
        'Restart the viewer, or see recorder.log'
      end
    end

    # The running recorder's pid, waiting for one that holds the lock but
    # hasn't written its pid yet. Returns [pid, foreign]: pid nil if there's
    # no recorder, and foreign true if the lock is held all the same, by
    # something that isn't a recorder (checked again after waiting, in case
    # it let go).
    def find
      return [nil, false] unless lock_held?

      found = pid || wait_for_pid
      [found, found.nil? && lock_held?]
    end

    def foreign_lock_message
      "Something holds #{History.lock_file} but isn't a recorder"
    end

    # Whether a recorder is running, as [pid, message], for a viewer that
    # doesn't start one (--no-record).
    def status
      running, foreign = find
      return [running, stop_hint(running)] if running

      [nil, foreign ? "#{foreign_lock_message}." : 'No recorder is running.']
    end

    # How to stop the recorder with this pid. `claude-limit-watch stop` finds
    # the recorder by its history file, so it needs --file unless this is the
    # default file. brief: kill instead of --file, for the panel's footer,
    # which has no room for a path.
    def stop_command(pid, brief: false)
      return 'claude-limit-watch stop' if bare_stop_works?

      brief ? "kill #{pid}" : "claude-limit-watch stop --file #{Shellwords.escape(History.file)}"
    end

    def stop_hint(pid)
      "Recorder running in the background (pid #{pid}). Stop it with: #{stop_command(pid)}"
    end

    # Makes sure a recorder is running. Returns [pid, message].
    def ensure_running
      running, foreign = find # a recorder, maybe just starting: don't start another
      return [running, stop_hint(running)] if running
      return [nil, "#{foreign_lock_message}; not starting one"] if foreign

      started = start
      if started
        [started, "Started the recorder (every #{num(DEFAULT_INTERVAL_MIN)}m). #{stop_hint(started)}"]
      else
        [nil, "Couldn't start the recorder; see #{History.log_file}"]
      end
    end

    # Stops the running recorder (the `stop` command).
    def stop
      running, foreign = find
      if foreign
        warn "#{foreign_lock_message}; not stopping anything."
        exit 1
      end
      if running.nil?
        puts 'No recorder is running.'
        return
      end
      Process.kill('TERM', running)
      50.times do
        sleep 0.1
        if pid.nil?
          puts "Stopped the recorder (pid #{running})."
          return
        end
      end
      warn "Sent TERM to pid #{running}, but it's still running."
      exit 1
    rescue Errno::ESRCH
      puts "The recorder (pid #{running}) had already exited."
    rescue Errno::EPERM
      warn "Not allowed to stop pid #{running}."
      exit 1
    end

    private def bare_stop_works?
      History.file == File.expand_path(History.default_file)
    rescue ArgumentError # HOME or XDG_STATE_HOME with ~nosuchuser: a bare stop couldn't use it either
      false
    end

    # Whether something else holds the lock on f.
    private def held?(f)
      return true unless f.flock(File::LOCK_EX | File::LOCK_NB)

      f.flock(File::LOCK_UN)
      false
    end
  end
end
