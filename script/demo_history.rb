# frozen_string_literal: true

# Writes a made-up history file for screenshots, and keeps it current until
# Ctrl-C. Usage:
#
#   ruby script/demo_history.rb [history-file]       # in one terminal
#   exe/claude-limit-watch --file <history-file>      # in another
#
# The scenario: 3h20m into the window at 60% used, after an early burst and a
# recent surge, so the 10m and 30m rows run out (green time left, then red
# locked-out time) while 1h, 2h and all last to the end (all green).
#
# It holds the recorder lock, so the viewer shows it as the running recorder
# and doesn't start a real one (which would append real readings). That's
# also why --no-record isn't needed to view it.

require 'fileutils'
require 'shellwords'
require 'json'
require 'time'

file = File.expand_path(ARGV[0] || '/tmp/claude-limit-watch-demo/history.jsonl')
FileUtils.mkdir_p(File.dirname(file))

ELAPSED = 200 # minutes into the 5-hour window
INTERVAL = 5
# [minutes into the window, utilization %]; readings are interpolated between these.
KNOTS = [[0, 0], [5, 8], [30, 14], [80, 30], [140, 42], [170, 47], [190, 54], [200, 60]].freeze

def util_at(min)
  a, b = KNOTS.each_cons(2).find { |(m0, _), (m1, _)| min.between?(m0, m1) }
  (a[1] + ((b[1] - a[1]) * (min - a[0]).fdiv(b[0] - a[0]))).round
end

def write_history(file)
  now = Time.now
  resets = now + ((300 - ELAPSED) * 60)
  lines = (INTERVAL..ELAPSED).step(INTERVAL).map do |min|
    t = now - ((ELAPSED - min) * 60)
    JSON.generate('t' => t.iso8601, 'interval_min' => INTERVAL.to_f, 'util' => util_at(min).to_f,
      'resets_at' => resets.utc.iso8601)
  end
  tmp = "#{file}.tmp"
  File.write(tmp, lines.join("\n") + "\n")
  File.rename(tmp, file)
end

lock = File.open("#{file}.lock", File::RDWR | File::CREAT, 0o644) # rubocop:disable Style/FileOpen -- held until exit
abort "Something else holds #{file}.lock; stop it first." unless lock.flock(File::LOCK_EX | File::LOCK_NB)
lock.truncate(0)
lock.write(Process.pid.to_s)
lock.flush

%w[INT TERM].each { |sig| trap(sig) { exit 0 } }
puts "Writing demo history to #{file} every minute (pid #{Process.pid}). Ctrl-C to stop. View it with:"
puts "  exe/claude-limit-watch --file #{Shellwords.escape(file)}"
loop do
  write_history(file)
  sleep 60
end
