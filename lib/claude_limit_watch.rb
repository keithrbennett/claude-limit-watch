# frozen_string_literal: true


# claude-limit-watch: watch the Claude subscription's 5-hour usage limit.
#
# Two processes:
#   claude-limit-watch record [interval-minutes]
#     Checks usage every N minutes (default 5) and appends each reading to a
#     history file (JSON Lines). Only one recorder runs at a time.
#   claude-limit-watch stop
#     Stops the recorder.
#   claude-limit-watch [view] [rate-window-minutes] [--lines]
#     Starts the recorder in the background (nohup) if it isn't running, then
#     shows the readings: a full-screen panel that redraws in place (quota
#     used vs. time elapsed in the window, and projected use at the end of
#     the window at the rate of the last 10m, 30m, 1h, 2h and the whole
#     window), or with --lines / non-terminal output, one line per reading.
#     Reads only the history file, so it can be closed and reopened freely
#     and has the full history from the start.
#
# The utilization is account-wide (the same undocumented endpoint the
# claude-dashboard status line uses), so it covers every concurrent Claude
# Code session and agent-council `claude`-harness agents.
#
# Stdlib only; works on Ruby 2.6+ (macOS system Ruby).
#
require 'fileutils'
require 'json'
require 'net/http'
require 'open3'
require 'rbconfig'
require 'time'
require 'uri'

require_relative "claude_limit_watch/version"

module ClaudeLimitWatch
  extend self

  USAGE_URL = URI('https://api.anthropic.com/api/oauth/usage')
  WINDOW_MIN = 300.0          # the 5-hour window
  DEFAULT_INTERVAL_MIN = 5    # how often to check
  DEFAULT_RATE_WINDOW_MIN = 30 # recent burn rate uses readings from the last N minutes
  URGENT_MIN = 20             # urgent when the limit is this close, whatever the pace
  URGENT_PACE = 2.0           # urgent when burning this many times the sustainable rate
  MIN_ELAPSED_MIN = 30        # no projections until this many minutes into the window
  MIN_INTERVAL_MIN = 0.5      # polling much faster gets HTTP 429 from the endpoint

  STATE_DIR = File.join(ENV['XDG_STATE_HOME'] || File.join(Dir.home, '.local', 'state'), 'claude-limit-watch')
  HISTORY_FILE = ENV['CLAUDE_LIMIT_WATCH_FILE'] || File.join(STATE_DIR, 'history.jsonl')
  LOCK_FILE = "#{HISTORY_FILE}.lock"
  RECORDER_LOG = File.join(File.dirname(HISTORY_FILE), 'recorder.log')
  # The command, which start_recorder runs to start a background recorder.
  EXECUTABLE = File.expand_path('../exe/claude-limit-watch', __dir__)
  KEEP_DAYS = 7               # the recorder drops readings older than this

  # 256-color codes: terminal themes often remap the 16 basic colors (yellow
  # showing as orange, say), but generally leave these alone.
  COLORS = { ok: '38;5;114', projected: '38;5;220', urgent: '38;5;196', dim: 90 }.freeze # green, yellow, red
  RATE_COL = 23 # width of the burn-rate column
  @rate_window_min = DEFAULT_RATE_WINDOW_MIN # set from the command line

  # Minutes for display: "5", "2.5".
  def num(minutes)
    minutes == minutes.round ? minutes.round.to_s : minutes.to_s
  end

  def header
    ['Time ', 'Level ', 'Window      ', 'Ends ', 'Used', "#{num(@rate_window_min)}m Burn Rate".ljust(RATE_COL),
     ' Pace', 'Outlook'].join(' | ')
  end

  def macos?
    RUBY_PLATFORM.include?('darwin')
  end

  def access_token
    raw =
      if macos?
        out, status = Open3.capture2('security', 'find-generic-password',
                                     '-s', 'Claude Code-credentials', '-w')
        status.success? ? out : nil
      else
        path = File.join(Dir.home, '.claude', '.credentials.json')
        File.exist?(path) ? File.read(path) : nil
      end
    raw && JSON.parse(raw).dig('claudeAiOauth', 'accessToken')
  rescue JSON::ParserError
    nil
  end

  # Returns [utilization_percent, resets_at_or_nil], or an error string.
  def fetch_five_hour
    token = access_token or return 'no Claude Code credentials found'
    req = Net::HTTP::Get.new(USAGE_URL)
    req['Authorization'] = "Bearer #{token}"
    req['anthropic-beta'] = 'oauth-2025-04-20'
    req['Accept'] = 'application/json'
    req['User-Agent'] = 'claude-limit-watch'
    res = Net::HTTP.start(USAGE_URL.host, USAGE_URL.port, use_ssl: true,
                          open_timeout: 10, read_timeout: 10) { |http| http.request(req) }
    if res.code == '401'
      return 'token expired (refreshes when a Claude Code session next runs)'
    end
    return 'rate-limited by the usage endpoint (HTTP 429); try a longer interval' if res.code == '429'
    return "HTTP #{res.code} from usage endpoint" unless res.is_a?(Net::HTTPSuccess)

    window = JSON.parse(res.body)['five_hour']
    return 'no 5-hour window in response' unless window.is_a?(Hash) && window['utilization'].is_a?(Numeric)

    resets = window['resets_at'] ? Time.parse(window['resets_at']) : nil
    [window['utilization'].to_f, resets]
  rescue StandardError => e
    "#{e.class}: #{e.message}"
  end

  # Duration in minutes as h:mm.
  def hm(min)
    min = [min.round, 0].max
    format('%d:%02d', min / 60, min % 60)
  end

  PROJECTION_WINDOWS = [10, 30, 60, 120].freeze # look-back windows shown on the panel

  # Rate (points per minute) over about the last `window` minutes, and the time
  # it actually covers, or nil when the history doesn't reach back far enough
  # (to at least 3/4 of the window). Readings come at intervals, so this uses
  # the reading closest to `window` minutes ago, allowing it to be up to 10%
  # (at least a minute) older. `history` holds the earlier readings in the
  # 5-hour window, oldest first; `util` is the latest.
  def rate_over(history, now, util, window)
    oldest = now - ((window + [window * 0.1, 1].max) * 60)
    first = history.select { |h| h[:t] >= oldest }.min_by { |h| (((now - h[:t]) / 60.0) - window).abs }
    return nil unless first

    span = (now - first[:t]) / 60.0
    span >= window * 0.75 ? [(util - first[:util]) / span, span] : nil
  end

  # Pace, projected limit time and level for a given rate.
  def assess(util, rate, reset_min)
    return { level: :urgent } if util >= 100
    return { level: :ok } unless rate && reset_min.positive?

    remaining = 100.0 - util
    a = { pace: remaining.positive? ? rate / (remaining / reset_min) : Float::INFINITY }
    a[:eta_min] = remaining / rate if rate.positive?
    hits_first = a[:eta_min] && a[:eta_min] < reset_min
    a[:left_at_reset] = remaining - (rate * reset_min) unless hits_first
    a[:level] =
      if hits_first && (a[:eta_min] <= URGENT_MIN || a[:pace] >= URGENT_PACE) then :urgent
      elsif hits_first then :projected
      else :ok
      end
    a
  end

  # Projection from the readings in the current window. Uses the recent rate
  # (last @rate_window_min minutes) when there's enough history, otherwise the
  # average since the window started.
  def project(history, now, util, resets)
    reset_min = (resets - now) / 60.0
    elapsed_min = WINDOW_MIN - reset_min
    avg_rate = elapsed_min.positive? ? util / elapsed_min : nil
    recent_rate, recent_span = rate_over(history, now, util, @rate_window_min)
    rate = recent_rate || avg_rate
    { util: util, resets: resets, reset_min: reset_min, elapsed_min: elapsed_min,
      avg_rate: avg_rate, recent_rate: recent_rate, recent_span_min: recent_span, rate: rate }
      .merge(assess(util, rate, reset_min))
  end

  # A compact duration label for a row, in minutes: "50m", "1h50m".
  def span_label(min)
    m = min.round
    m < 60 ? "#{m}m" : format('%dh%02dm', m / 60, m % 60)
  end

  # One row per look-back window, plus the whole 5-hour window so far, each with
  # its rate, where it leads (assess) and the projected use at the window's end.
  # Returns nil during the window's first MIN_ELAPSED_MIN minutes: windows often
  # start with a burst (resumed sessions re-sending their whole conversation),
  # and any projection from those minutes predicts a limit hit that isn't
  # coming.
  def projection_rows(history, now, util, resets)
    reset_min = (resets - now) / 60.0
    elapsed = WINDOW_MIN - reset_min
    return nil if elapsed < MIN_ELAPSED_MIN

    have = history.first ? (now - history.first[:t]) / 60.0 : 0
    windows = (PROJECTION_WINDOWS + [@rate_window_min]).map(&:to_f).uniq.sort
    rows = windows.map do |w|
      label = w >= 60 && (w % 60).zero? ? "#{(w / 60).to_i}h" : "#{num(w)}m"
      rate, span = rate_over(history, now, util, w)
      next { label: label, na: true, have: have } unless rate

      # When the history doesn't reach back the whole window, label the row
      # with what it actually covers (e.g. "1h50m" instead of "2h").
      label = span_label(span) if span < w * 0.95

      { label: label, rate: rate }.merge(assess(util, rate, reset_min))
    end
    rows << { label: 'window', rate: util / elapsed }.merge(assess(util, util / elapsed, reset_min))
    rows.each do |r|
      next if r[:na]

      r[:end_pct] = util + (r[:rate] * reset_min)
      r[:eta_at] = now + (r[:eta_min] * 60) if r[:eta_min]
    end
  end

  def color(text, key)
    return text unless $stdout.tty? && ENV['NO_COLOR'].to_s.empty?

    "\e[#{COLORS[key]}m#{text}\e[0m"
  end

  def format_line(now, p)
    rate_txt =
      if p[:recent_rate]
        "#{format('%4.1f', p[:recent_rate] * 60)}%/h (avg #{format('%.1f', p[:avg_rate] * 60)})"
      elsif p[:avg_rate]
        "#{format('%4.1f', p[:avg_rate] * 60)}%/h (avg so far)"
      else
        'rate n/a'
      end
    outlook =
      if p[:util] >= 100
        "AT LIMIT, resets in #{hm(p[:reset_min])}"
      elsif p[:eta_min] && p[:left_at_reset].nil?
        "LIMIT at #{(now + (p[:eta_min] * 60)).strftime('%H:%M')} (in #{hm(p[:eta_min])}), " \
          "#{hm(p[:reset_min] - p[:eta_min])} before reset"
      elsif p[:left_at_reset]
        "~#{p[:left_at_reset].round}% left at reset"
      else
        'not rising'
      end
    label = { ok: 'OK    ', projected: 'WARN  ', urgent: 'URGENT' }[p[:level]]
    pace = p[:pace]&.finite? ? format('%.1fx', p[:pace]) : 'n/a'
    [now.strftime('%H:%M'), label, "#{hm(p[:elapsed_min])} of 5:00", p[:resets].localtime.strftime('%H:%M'),
     format('%3d%%', p[:util].round), rate_txt.ljust(RATE_COL), pace.rjust(5), outlook].join(' | ')
  end

  # ---- history file ----

  def append_record(rec)
    File.open(HISTORY_FILE, 'a') { |f| f.puts(JSON.generate(rec)) }
  end

  # Drop readings older than KEEP_DAYS. Writes a new file and renames it over
  # the old one, so a reader never sees a half-written file.
  def prune_history
    return unless File.exist?(HISTORY_FILE)

    cutoff = Time.now - (KEEP_DAYS * 86_400)
    kept = File.readlines(HISTORY_FILE).select do |line|
      Time.parse(JSON.parse(line)['t']) >= cutoff
    rescue StandardError
      false
    end
    tmp = "#{HISTORY_FILE}.tmp"
    File.write(tmp, kept.join)
    File.rename(tmp, HISTORY_FILE)
  end

  # Readings as hashes: { t:, interval:, util:, resets: } or { t:, interval:, error: }.
  # Unparseable lines (e.g. one being written right now) are skipped.
  def read_history
    return [] unless File.exist?(HISTORY_FILE)

    File.readlines(HISTORY_FILE).map do |line|
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

  # ---- recorder ----

  def run_record(minutes)
    FileUtils.mkdir_p(File.dirname(HISTORY_FILE))
    lock = File.open(LOCK_FILE, File::RDWR | File::CREAT, 0o644)
    unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      warn "Another recorder is already running (pid #{File.read(LOCK_FILE).strip}). Only one can run at a time."
      exit 1
    end
    lock.truncate(0)
    lock.write(Process.pid.to_s)
    lock.flush
    # HUP isn't trapped: under nohup it stays ignored, so closing the terminal
    # that started the viewer doesn't stop a background recorder.
    %w[INT TERM].each { |sig| trap(sig) { exit 0 } }

    puts "Recording the Claude 5-hour usage every #{num(minutes)}m to #{HISTORY_FILE} (pid #{Process.pid}). Stop with Ctrl-C or: claude-limit-watch stop"
    last_prune = nil
    loop do
      if last_prune.nil? || Time.now - last_prune > 3600
        prune_history
        last_prune = Time.now
      end
      now = Time.now
      reading = fetch_five_hour
      stamp = now.strftime('%H:%M:%S')
      if reading.is_a?(String)
        append_record('t' => now.iso8601, 'interval_min' => minutes, 'error' => reading)
        puts "#{stamp}  error: #{reading}"
      else
        util, resets = reading
        append_record('t' => now.iso8601, 'interval_min' => minutes, 'util' => util,
                      'resets_at' => resets&.utc&.iso8601)
        puts "#{stamp}  #{format('%3d%%', util.round)}  #{resets ? "window ends #{clock(resets)}" : 'no active window'}"
      end
      $stdout.flush
      sleep(minutes * 60)
    end
  end

  # ---- viewer: turning the history into what to show ----

  # Everything the viewer needs, derived from the history as of `now`.
  def snapshot(records, now)
    st = { records: records }
    return st.merge(no_data: true) if records.empty?

    last = records.last
    st[:last_t] = last[:t]
    st[:interval] = last[:interval]
    st[:stale] = now - last[:t] > (last[:interval] * 60 * 2) + 60
    if last[:error]
      st[:error] = last[:error]
      st[:error_at] = last[:t]
    end

    good = records.reject { |r| r[:error] }
    latest = good.last
    return st.merge(no_reading: true, history: []) unless latest
    if latest[:resets].nil? || latest[:resets] <= now
      return st.merge(no_window: latest[:util], history: [])
    end

    window = good.select { |r| r[:resets] && (r[:resets] - latest[:resets]).abs < 60 }
    prior = window[0...-1].map { |r| { t: r[:t], util: r[:util] } }
    proj = project(prior, latest[:t], latest[:util], latest[:resets])
    st.merge(history: window, proj: proj, eta_at: proj[:eta_min] && latest[:t] + (proj[:eta_min] * 60),
             table: projection_rows(prior, latest[:t], latest[:util], latest[:resets]))
  end

  # Reads the history file only when it has changed.
  class HistoryCache
    def initialize
      @sig = nil
      @records = []
    end

    def records
      sig = File.exist?(HISTORY_FILE) ? [File.mtime(HISTORY_FILE), File.size(HISTORY_FILE)] : nil
      if sig != @sig
        @records = ClaudeLimitWatch.read_history
        @sig = sig
      end
      @records
    end
  end

  # ---- managing the background recorder ----

  # The running recorder's pid, or nil. The recorder holds an exclusive lock on
  # LOCK_FILE for as long as it runs, so the lock is the reliable signal.
  def recorder_pid
    return nil unless File.exist?(LOCK_FILE)

    File.open(LOCK_FILE, File::RDWR) do |f|
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
  # Ctrl-C in the viewer's terminal doesn't reach it. Returns its pid (or nil
  # if it didn't come up).
  def start_recorder
    FileUtils.mkdir_p(File.dirname(RECORDER_LOG))
    pid = Process.spawn('nohup', RbConfig.ruby, EXECUTABLE, 'record',
                        in: File::NULL, out: [RECORDER_LOG, 'a'], err: [:child, :out], pgroup: true)
    Process.detach(pid)
    20.times do
      sleep 0.1
      found = recorder_pid
      return found if found
    end
    nil
  end

  def stop_hint(pid)
    "Recorder running in the background (pid #{pid}). Stop it with: claude-limit-watch stop"
  end

  # Makes sure a recorder is running. Returns [pid, message].
  def ensure_recorder
    pid = recorder_pid
    return [pid, stop_hint(pid)] if pid

    pid = start_recorder
    if pid
      [pid, "Started the recorder (every #{num(DEFAULT_INTERVAL_MIN)}m). #{stop_hint(pid)}"]
    else
      [nil, "Couldn't start the recorder; see #{RECORDER_LOG}"]
    end
  end

  def run_stop
    pid = recorder_pid
    if pid.nil?
      puts 'No recorder is running.'
      return
    end
    Process.kill('TERM', pid)
    50.times do
      sleep 0.1
      if recorder_pid.nil?
        puts "Stopped the recorder (pid #{pid})."
        return
      end
    end
    warn "Sent TERM to pid #{pid}, but it's still running."
    exit 1
  rescue Errno::ESRCH
    puts "The recorder (pid #{pid}) had already exited."
  rescue Errno::EPERM
    warn "Not allowed to stop pid #{pid}."
    exit 1
  end

  RESTART_HINT = 'Restart the viewer to start the recorder, or run: claude-limit-watch record'

  # ---- viewer: one line per reading (non-terminal, or --lines) ----

  def run_lines
    trap('INT') { puts; exit 0 }
    _pid, message = ensure_recorder
    puts color(message, :dim)
    puts color("Claude 5-hour limit, from #{HISTORY_FILE}; burn rate over the last " \
               "#{num(@rate_window_min)}m. Ctrl-C to quit (the recorder keeps running).", :dim)
    puts color(header, :dim)

    cache = HistoryCache.new
    shown_t = nil # time of the last reading printed
    window = nil
    stale_noted = false
    loop do
      records = cache.records
      if shown_t.nil?
        # Start with the readings in the current window (or nothing before now).
        latest = records.reject { |r| r[:error] }.last
        first = latest && latest[:resets] &&
                records.find { |r| r[:resets] && (r[:resets] - latest[:resets]).abs < 60 }
        shown_t = first ? first[:t] - 1 : (records.last ? records.last[:t] : Time.at(0))
      end
      records.each_with_index do |rec, i|
        next unless rec[:t] > shown_t

        stamp = rec[:t].strftime('%H:%M')
        if rec[:error]
          puts color("#{stamp} | no reading: #{rec[:error]}", :dim)
        elsif rec[:resets].nil? || rec[:resets] <= rec[:t]
          puts color("#{stamp} | no active 5-hour window (#{rec[:util].round}% used)", :dim)
        else
          unless window && (rec[:resets] - window).abs < 60
            puts color("-- 5-hour window ends at #{clock(rec[:resets])} --", :dim) if window
            window = rec[:resets]
          end
          st = snapshot(records[0..i], rec[:t])
          puts color(format_line(rec[:t], st[:proj]), st[:proj][:level]) if st[:proj]
        end
        shown_t = rec[:t]
        stale_noted = false
      end
      st = snapshot(records, Time.now)
      if st[:stale] && !stale_noted
        puts color("#{Time.now.strftime('%H:%M')} | no new readings for #{dur(Time.now - st[:last_t])}. #{RESTART_HINT}", 33)
        stale_noted = true
      end
      $stdout.flush
      sleep 2
    end
  end

  # ---- viewer: full-screen dashboard (terminal) ----

  ANSI_RE = /\e\[[0-9;?]*[A-Za-z]/.freeze

  def term_width
    require 'io/console'
    w = IO.console&.winsize&.last.to_i
    w.positive? ? w : 80
  rescue StandardError
    80
  end

  # Truncate to a visible width, leaving ANSI escapes intact.
  def fit(str, width)
    out = +''
    visible = 0
    str.scan(/#{ANSI_RE}|./mo) do |tok|
      if tok.start_with?("\e")
        out << tok
      elsif visible < width
        out << tok
        visible += 1
      end
    end
    out
  end

  def paint(text, *codes)
    return text if ENV['NO_COLOR'].to_s != '' || codes.empty? || !$stdout.tty?

    "\e[#{codes.join(';')}m#{text}\e[0m"
  end

  def bar(fraction, width, *codes)
    filled = (fraction.clamp(0.0, 1.0) * width).round
    paint('█' * filled, *codes) + paint('░' * (width - filled), 90)
  end

  def clock(time)
    time.localtime.strftime('%H:%M')
  end

  # Duration in seconds, in unambiguous units: "1h 12m", "58m", "3m 48s", "48s".
  def dur(seconds)
    s = [seconds.round, 0].max
    if s >= 3600 then format('%dh %02dm', s / 3600, (s % 3600) / 60)
    elsif s >= 600 then "#{s / 60}m"
    elsif s >= 60 then format('%dm %02ds', s / 60, s % 60)
    else "#{s}s"
    end
  end

  # Duration to the minute, so the panel's text (and the screen) changes only
  # about once a minute: "1h 12m", "58m", "<1m".
  def dur_m(seconds)
    m = (seconds / 60.0).round
    return '<1m' if m < 1

    m >= 60 ? format('%dh %02dm', m / 60, m % 60) : "#{m}m"
  end

  # A status line for the states that aren't projections (no data, no active
  # window, at the limit), or nil. Projections are shown per look-back window
  # in the bars instead, so there's no single headline projection.
  def headline(st, now)
    p = st[:proj]
    return [paint(' NO DATA ', 1, 7, 90), "No readings yet in #{HISTORY_FILE}"] if st[:no_data]
    return [paint(' IDLE ', 1, 7, 90), "No active 5-hour window (#{st[:no_window].round}% used)"] if st[:no_window]
    return [paint(' ? ', 1, 7, 90), 'No successful reading yet'] unless p
    return nil if p[:util] < 100

    [paint(' AT LIMIT ', 1, 7, COLORS[:urgent]),
     paint("Resets at #{clock(p[:resets])} (in #{dur_m(p[:resets] - now)})", 1, COLORS[:urgent])]
  end

  # ---- banner ----

  ACCENT_COLOR = [38, 5, 141].freeze # lavender (256-color 141): the heading and the Time bar

  def banner_rows
    inner = "  ◆  #{'Claude Limit Watch'.upcase.chars.join(' ')}  ◆  "
    ["╔#{'═' * inner.size}╗", "║#{inner}║", "╚#{'═' * inner.size}╝"]
  end

  # The framed heading, in one color (plain when colors are off).
  def banner
    banner_rows.map { |row| paint(row, 1, *ACCENT_COLOR) }
  end

  def home_relative(path)
    path.start_with?("#{Dir.home}/") ? "~#{path[Dir.home.size..]}" : path
  end

  # once: printing a single copy (--once), so use a fixed width, don't
  # truncate, and leave out the quit instruction.
  def dashboard_lines(st, now, once: false)
    w = once ? 100 : term_width
    bar_w = (w - 47).clamp(10, 50) # leaves room for the projection rows' text
    p = st[:proj]
    info = st[:last_t] ? "last reading #{clock(st[:last_t])} (#{dur_m(now - st[:last_t])} ago)" : 'no readings yet'
    lines = []
    if w >= banner_rows.map(&:size).max + 4
      lines.concat(banner.map { |row| "  #{row}" })
      lines << ''
      lines << "  #{paint("Claude's 5-hour usage limit · #{info}", 90)}"
    else
      lines << "#{paint(' Claude 5-hour limit', 1)}   #{paint(info, 90)}"
    end
    lines << ''
    status = headline(st, now)
    lines.push("  #{status[0]}  #{status[1]}", '') if status
    if p
      elapsed = WINDOW_MIN - ((p[:resets] - now) / 60.0)
      window_start = p[:resets] - (WINDOW_MIN * 60)
      used_color = p[:util] >= 100 ? [COLORS[:urgent]] : [] # normal text color unless at the limit
      lines << "  Used   #{bar(p[:util] / 100.0, bar_w, *used_color)}  #{format('%3d%%', p[:util].round)}"
      lines << "  Time   #{bar(elapsed / WINDOW_MIN, bar_w, *ACCENT_COLOR)}  #{dur_m(elapsed * 60)} of 5h"
      lines << paint("         #{clock(window_start).ljust(bar_w - 5)}#{clock(p[:resets])}", 90)
      if st[:table] && p[:util] < 100
        lines << ''
        lines << paint("  If usage continues at the rate of the last ... (all: since #{clock(window_start)}):", 90)
        lines << ''
        lines.concat(projection_bar_lines(st[:table], p, bar_w, now))
        lines << ''
        # Each symbol drawn as it appears in the bars.
        lines << "         #{paint('█', *ACCENT_COLOR)}#{paint(' time so far · ', 90)}#{paint('█', COLORS[:ok])}" \
                 "#{paint(' time left at that rate · ', 90)}#{paint('█', COLORS[:urgent])}" \
                 "#{paint(' locked out (limit reached) · │ window ends', 90)}"
        lines << "         #{paint('Time left is ', 90)}#{paint('green', COLORS[:ok])}" \
                 "#{paint(' if that rate lasts to the end, ', 90)}#{paint('yellow', COLORS[:projected])}" \
                 "#{paint(' if it runs out first', 90)}"
      elsif p[:util] < 100
        lines << ''
        lines << paint("  Projections start #{MIN_ELAPSED_MIN}m into the window " \
                       "(at #{clock(window_start + (MIN_ELAPSED_MIN * 60))}): the first minutes are too little to go on.", 90)
      end
    end
    if st[:error]
      lines << ''
      lines << paint("  Last check failed at #{clock(st[:error_at])}: #{st[:error]}", 33)
    end
    if st[:stale] || (st[:no_data] && st[:recorder_pid].nil?)
      lines << ''
      gap = st[:last_t] ? "No new readings for #{dur_m(now - st[:last_t])}. " : ''
      lines << paint("  #{gap}#{RESTART_HINT}", 33)
    end
    lines << ''
    recorder =
      if st[:recorder_pid]
        "Recorder running (pid #{st[:recorder_pid]}), writing to #{home_relative(HISTORY_FILE)}"
      else
        "Recorder not running (history file: #{home_relative(HISTORY_FILE)})"
      end
    lines << paint("  #{recorder}", 90)
    return lines if once

    stop = st[:recorder_pid] ? ' · stop the recorder with: claude-limit-watch stop' : ''
    lines << paint("  q to quit#{stop}", 90)
    lines.map { |l| fit(l, w) }
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
      next "  #{label} #{paint("not enough history yet (have #{dur_m(r[:have] * 60)})", 90)}" if r[:na]

      # Two colors only: green if that rate lasts, yellow if it runs out. Red
      # is kept for the locked-out time.
      runs_out = r[:eta_at] && r[:eta_at] < p[:resets]
      color = COLORS[runs_out ? :projected : :ok]
      if runs_out
        hit = cells.call(r[:eta_at]).clamp(so_far, bar_w - 1) # leave at least one red cell
        locked = p[:resets] - [r[:eta_at], now].max
        bar = paint('█' * so_far, *ACCENT_COLOR) + paint('█' * (hit - so_far), color) +
              paint('█' * (bar_w - hit), COLORS[:urgent])
        text = "limit at #{clock(r[:eta_at])} · #{dur_m(locked)} locked out"
      else
        bar = paint('█' * so_far, *ACCENT_COLOR) + paint('█' * (bar_w - so_far), color)
        text = "lasts · #{r[:end_pct].round}% used at the end"
      end
      "  #{label} #{bar}#{paint('│', 90)} #{paint(text, color)}"
    end
  end

  def render(lines)
    return if lines == @last_render

    @last_render = lines
    $stdout.write("\e[H" + lines.map { |l| "#{l}\e[K" }.join("\n") + "\e[J")
    $stdout.flush
  end

  # Prints the panel once, without the full-screen mode, and exits. Doesn't
  # start the recorder.
  def run_once
    now = Time.now
    puts dashboard_lines(snapshot(read_history, now).merge(recorder_pid: recorder_pid), now, once: true)
  end

  def run_dashboard
    ensure_recorder
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
      pid = recorder_pid
      puts pid ? stop_hint(pid) : 'The recorder is not running.'
      $stdout.flush
    end
    %w[INT TERM HUP].each { |sig| trap(sig) { exit 0 } }

    cache = HistoryCache.new
    pid = nil
    ticks = 0
    loop do
      pid = recorder_pid if (ticks % 5).zero? # check every 5 seconds
      ticks += 1
      now = Time.now
      render(dashboard_lines(snapshot(cache.records, now).merge(recorder_pid: pid), now))
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

  # ---- command line ----

  USAGE = <<~TEXT
    Usage:
      claude-limit-watch record [interval-minutes]
          Check usage every N minutes (default #{DEFAULT_INTERVAL_MIN}; #{MIN_INTERVAL_MIN} or more) and append
          each reading to #{HISTORY_FILE}.
      claude-limit-watch stop
          Stop the recorder.
      claude-limit-watch [view] [rate-window-minutes] [--lines]
          Start the recorder in the background if it isn't running, then show the
          readings. rate-window-minutes: the look-back for --lines output's burn rate
          (default #{DEFAULT_RATE_WINDOW_MIN}); on the panel it adds a row if it isn't 10, 30, 60 or 120.
          --lines: one line per reading instead of the full-screen panel.
          --once:  print the panel once and exit (for copying); doesn't start the recorder.
  TEXT

  def number_arg(arg, default, min)
    n = Float(arg || default)
    n.finite? && n >= min ? n : nil
  rescue ArgumentError, TypeError
    nil
  end

  def main(argv = ARGV)
    args = argv.dup
    if args.first == 'record'
      args.shift
      minutes = number_arg(args[0], DEFAULT_INTERVAL_MIN, MIN_INTERVAL_MIN)
      (warn USAGE; exit 1) if minutes.nil? || args.size > 1
      run_record(minutes)
    elsif args.first == 'stop'
      (warn USAGE; exit 1) if args.size > 1
      run_stop
    else
      args.shift if args.first == 'view'
      lines_mode = !args.delete('--lines').nil?
      once = !args.delete('--once').nil?
      rate_window = number_arg(args[0], DEFAULT_RATE_WINDOW_MIN, 1)
      (warn USAGE; exit 1) if rate_window.nil? || args.size > 1
      @rate_window_min = rate_window
      if once then run_once
      elsif lines_mode || !$stdout.tty? then run_lines
      else run_dashboard
      end
    end
  end
end
