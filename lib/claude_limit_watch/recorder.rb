# frozen_string_literal: true

require 'fileutils'
require 'rbconfig'
require 'time'

module ClaudeLimitWatch
  # The recorder: checks the usage at intervals and appends each reading to
  # the history file. Also finds, starts and stops a running recorder.
  module Recorder
    extend self
    include Format

    RESTART_HINT = 'Restart the viewer to start the recorder, or run: claude-limit-watch record'

    # Records every `minutes` minutes until stopped. Exits if another recorder
    # is running.
    def run(minutes)
      FileUtils.mkdir_p(File.dirname(History.file))
      lock = File.open(History.lock_file, File::RDWR | File::CREAT, 0o644)
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

      puts "Recording the Claude 5-hour usage every #{num(minutes)}m to #{History.file} (pid #{Process.pid}). " \
           'Stop with Ctrl-C or: claude-limit-watch stop'
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
      reading = UsageApi.fetch_five_hour
      stamp = now.strftime('%H:%M:%S')
      if reading.is_a?(String)
        History.append('t' => now.iso8601, 'interval_min' => minutes, 'error' => reading)
        puts "#{stamp}  error: #{reading}"
      else
        util, resets = reading
        History.append('t' => now.iso8601, 'interval_min' => minutes, 'util' => util,
                       'resets_at' => resets&.utc&.iso8601)
        puts "#{stamp}  #{format('%3d%%', util.round)}  #{resets ? "window ends #{clock(resets)}" : 'no active window'}"
      end
    end

    # The running recorder's pid, or nil. The recorder holds an exclusive lock
    # on the lock file for as long as it runs, so the lock is the reliable signal.
    def pid
      return nil unless File.exist?(History.lock_file)

      File.open(History.lock_file, File::RDWR) do |f|
        if f.flock(File::LOCK_EX | File::LOCK_NB)
          f.flock(File::LOCK_UN)
          nil
        else
          pid = f.read.to_i
          pid.positive? ? pid : -1
        end
      end
    rescue SystemCallError
      nil
    end

    # Starts `record` in the background with nohup, in its own process group so
    # Ctrl-C in the viewer's terminal doesn't reach it, recording to this
    # process's history file. Returns its pid (or nil if it didn't come up).
    def start
      log = History.log_file
      FileUtils.mkdir_p(File.dirname(log))
      child = Process.spawn({ 'CLAUDE_LIMIT_WATCH_FILE' => History.file },
                            'nohup', RbConfig.ruby, EXECUTABLE, 'record',
                            in: File::NULL, out: [log, 'a'], err: [:child, :out], pgroup: true)
      Process.detach(child)
      20.times do
        sleep 0.1
        found = pid
        return found if found
      end
      nil
    end

    def stop_hint(pid)
      "Recorder running in the background (pid #{pid}). Stop it with: claude-limit-watch stop"
    end

    # Makes sure a recorder is running. Returns [pid, message].
    def ensure_running
      running = pid
      return [running, stop_hint(running)] if running

      started = start
      if started
        [started, "Started the recorder (every #{num(DEFAULT_INTERVAL_MIN)}m). #{stop_hint(started)}"]
      else
        [nil, "Couldn't start the recorder; see #{History.log_file}"]
      end
    end

    # Stops the running recorder (the `stop` command).
    def stop
      running = pid
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
  end
end
