# frozen_string_literal: true

# claude-limit-watch: watch the Claude subscription's 5-hour usage limit.
#
# Two processes:
# - The recorder (`record`) checks usage every N minutes (default 5) and
#   appends each reading to a history file (JSON Lines). Only one recorder
#   runs at a time.
# - The viewer (the default command) starts the recorder in the background
#   (nohup) if it isn't running (unless --no-record or --once), then shows the
#   readings: a full-screen panel that redraws in place (quota used vs.
#   time elapsed in the window, and projected use at the rate of the last
#   10m, 30m, 1h, 2h and the whole window), or with --lines / non-terminal
#   output, one line per reading.
#   It reads only the history file, so it can be closed and reopened freely
#   and has the full history from the start.
#
# `claude-limit-watch --help` lists the commands and options.
#
# The utilization is account-wide (the same undocumented endpoint the
# claude-dashboard status line uses), so it covers every concurrent Claude
# Code session and any other tools using your Claude login.
#
# Stdlib only; works on Ruby 2.6+ (macOS system Ruby).
#
# The parts, each a module of functions:
#   UsageApi    fetches the current usage
#   History     the history file
#   Recorder    the recorder process, and starting and stopping it
#   Projection  burn rates and where they lead
#   Snapshot    what the viewer shows for a history, as of a time
#   LinesView   the one-line-per-reading view
#   Panel       the full-screen panel
#   CLI         the command line
#   Format, Term  text formatting, and colors and the terminal's size
#
# A module that includes Format or Term does so before `extend self`: before
# Ruby 3.0, extend self doesn't pick up modules included after it.

require_relative 'claude_limit_watch/version'

module ClaudeLimitWatch
  WINDOW_MIN = 300.0           # the 5-hour window
  DEFAULT_INTERVAL_MIN = 5     # how often to check
  MIN_INTERVAL_MIN = 0.5       # polling much faster gets HTTP 429 from the endpoint
  DEFAULT_RATE_WINDOW_MIN = 30 # recent burn rate uses readings from the last N minutes
  VERSION_LINE = "claude-limit-watch #{VERSION} · #{HOMEPAGE}"
  # The command, which Recorder.start runs to start a background recorder.
  EXECUTABLE = File.expand_path('../exe/claude-limit-watch', __dir__)
end

require_relative 'claude_limit_watch/format'
require_relative 'claude_limit_watch/term'
require_relative 'claude_limit_watch/usage_api'
require_relative 'claude_limit_watch/history'
require_relative 'claude_limit_watch/projection'
require_relative 'claude_limit_watch/snapshot'
require_relative 'claude_limit_watch/recorder'
require_relative 'claude_limit_watch/lines_view'
require_relative 'claude_limit_watch/panel'
require_relative 'claude_limit_watch/cli'
