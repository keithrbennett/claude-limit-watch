# frozen_string_literal: true

# The full-screen panel's layout.
RSpec.describe ClaudeLimitWatch::Panel, '.lines' do
  let(:m) { described_class }
  let(:spaced_name) { 'C L A U D E   L I M I T   W A T C H' }

  # The demo scenario, then a failed check, then no readings for 15 minutes:
  # with an extra rate-window row, the tallest panel there is.
  let(:worst_records) { window_records + [error_record(NOW + 60)] }
  let(:worst_now) { NOW + 60 + 900 }

  # Each state the panel can be in: [records, now, recorder pid].
  let(:states) do
    idle = { t: NOW, interval: 5.0, util: 3.0, resets: NOW - 60 }
    {
      'normal'                        => [window_records, NOW, 1234],
      'no data'                       => [[], NOW, 1234],
      'no data, no recorder'          => [[], NOW, nil],
      'only failed checks'            => [[error_record(NOW)], NOW, 1234],
      'idle'                          => [[idle], NOW, 1234],
      'idle, then a failed check'     => [[idle, error_record(NOW + 60)], NOW + 61, 1234],
      'early in the window'           => [window_records(elapsed: 20, knots: [[0, 0], [20, 5]]), NOW, 1234],
      'at the limit'                  => [window_records(knots: [[0, 0], [200, 100]]), NOW, 1234],
      'stale'                         => [window_records, NOW + 900, 1234],
      'failed and stale'              => [worst_records, worst_now, 1234],
      'failed and stale, no recorder' => [worst_records, worst_now, nil],
    }
  end

  it 'shows the normal panel in 19 rows' do
    lines = panel(window_records, NOW)
    expect(lines.size).to eq(19)
    expect(lines.first).to include(spaced_name)
    expect(lines)
      .to include(a_string_starting_with('  q to quit · stop the recorder with: claude-limit-watch stop '))
    expect(lines[-2]).to start_with('  Recorder running (pid 1234), writing to:  ')
      .and end_with('  last reading 08:00 (<1m ago)')
      .and have_attributes(size: lines.find { |l| l.include?('──') }.size)
    expect(lines[-1]).to eq("  #{m.home_relative(ClaudeLimitWatch::History.file)}")
  end

  it 'says there are no readings yet in the headline only' do
    lines = panel([], NOW, pid: nil)
    expect(lines.grep(/no readings yet/i)).to eq(['   NO DATA   No readings yet in the history file (below)'])
    expect(lines[-2]).to match(/\A  Recorder not running\. History file: +│\z/)
  end

  it 'leaves the version and project page line out of the panel' do
    expect(panel(window_records, NOW).grep(/#{Regexp.escape(ClaudeLimitWatch::HOMEPAGE)}/)).to be_empty
  end

  it 'fits 24 rows in every state' do
    expect(panel(worst_records, worst_now, rate_window: 45).size).to eq(24) # the tallest
    states.each do |state, (records, now, pid)|
      size = panel(records, now, pid: pid, rate_window: 45).size
      expect(size).to be <= 24, "#{size} rows in the #{state} panel"
    end
  end

  describe 'the title line' do
    before { stub_const('ClaudeLimitWatch::VERSION', '0.2.0.pre.1') }

    def title(cols, utc: false)
      ClaudeLimitWatch::Format.utc = utc
      lines = panel(window_records, NOW, cols: cols)
      [lines.first, lines.find { |l| l.include?('──') }]
    end

    # The title centered on the rule, with left and right rule cells.
    def centered(left, text, right)
      "  #{'━' * left}  #{text}  #{'━' * right}"
    end

    it 'centers the name and version on a rule that ends where the bottom rule does' do
      spaced = "#{spaced_name}   v0.2.0.pre.1"
      plain = 'CLAUDE LIMIT WATCH v0.2.0.pre.1'
      {
        [120, false] => centered(20, spaced, 20),
        [120, true]  => centered(12, "#{spaced} · times in UTC", 13),
        [80, false]  => centered(12, spaced, 12),
        [80, true]   => centered(14, "#{plain} · times in UTC", 14), # spaced would leave 4 and 5
        [60, false]  => centered(11, plain, 12),
      }.each do |(cols, utc), expected|
        line, rule = title(cols, utc: utc)
        expect(line).to eq(expected)
        expect(line.size).to eq(rule.size), "at #{cols} columns"
      end
    end

    it 'leaves out the rule when it would be shorter than 8 on each side' do
      expect(title(60, utc: true).first).to eq('  CLAUDE LIMIT WATCH v0.2.0.pre.1 · times in UTC')
    end

    it 'leaves out the version, then the name, keeping the UTC note, when they would be cut off' do
      {
        [33, false] => '  CLAUDE LIMIT WATCH v0.2.0.pre.1',
        [32, false] => '  CLAUDE LIMIT WATCH',
        [47, true]  => '  CLAUDE LIMIT WATCH · times in UTC',
        [35, true]  => '  CLAUDE LIMIT WATCH · times in UTC',
        [34, true]  => '  times in UTC',
        [14, true]  => '  times in UTC',
      }.each do |(cols, utc), expected|
        expect(title(cols, utc: utc).first).to eq(expected), "at #{cols} columns"
      end
    end

    it 'draws the name in bold lavender, the rules in dimmer lavender, and the rest in gray' do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('NO_COLOR').and_return(nil)
      allow(m).to receive(:term_width).and_return(120)
      st = ClaudeLimitWatch::Snapshot.build(window_records, NOW, rate_window: 30).merge(recorder_pid: 1234)
      rule = "\e[38;5;97m#{'━' * 20}\e[0m"
      expect(m.lines(st, NOW).first)
        .to eq("  #{rule}  \e[1;38;5;141m#{spaced_name}\e[0m   \e[90mv0.2.0.pre.1\e[0m  #{rule}")
    end
  end

  describe 'a history file path too long for the terminal' do
    let(:long) { "/#{'very-long-directory/' * 6}history.jsonl" } # 134 characters

    before { allow(ClaudeLimitWatch::History).to receive(:file).and_return(long) }

    it 'goes on a line of its own, shortened from the left, leaving the recorder line whole' do
      lines = panel(window_records, NOW, pid: nil, cols: 80)
      expect(lines[-2]).to start_with('  Recorder not running. History file:')
      expect(lines[-1]).to eq("  ...#{long[-75..]}").and have_attributes(size: 80)
      expect(lines[-1]).to end_with('/history.jsonl')
    end

    it 'is whole with --once, for copying' do
      expect(panel(window_records, NOW, pid: nil, once: true)[-1]).to eq("  #{long}")
    end
  end

  it 'leaves out quitting with --once' do
    lines = panel(worst_records, worst_now, once: true)
    expect(lines.first).to include(spaced_name)
    expect(lines.grep(/q to quit/)).to be_empty
    expect(lines).to include(a_string_matching(/\A +\d\d:\d\d +\d\d:\d\d  now 08:16\z/))
    expect(lines).to include(a_string_matching(/\A +│ +now 08:16\z/))
  end

  it "shows the current time after the window's end time, under the elapsed time" do
    # Ten minutes after the last reading, so the current time can't be
    # mistaken for the last reading's.
    [60, 80, 120].each do |cols|
      lines = panel(window_records, NOW + 600, cols: cols)
      time_bar = lines.index { |l| l.start_with?('  Time ') }
      expect(lines[time_bar + 1]).to match(/\A +\d\d:\d\d +\d\d:\d\d  now 08:10\z/)
      expect(lines[time_bar + 1].index('now')).to eq(lines[time_bar].index(/(\d+h )?\S+ of 5h\z/))
    end
  end

  describe 'the bottom lines' do
    # The footer and recorder lines, under the rule.
    def bottom(records, pid: 1234, cols: 120, now: NOW + 59)
      lines = panel(records, now, pid: pid, cols: cols)
      rule = lines.index { |l| l.include?('──') }
      [lines[rule], *lines[rule + 1, 2]]
    end

    it 'shows the current time and the last reading in a column, after a bar centered between the columns' do
      [[window_records, 1234, 'claude-limit-watch stop'], [window_records, nil, 'q to quit'],
        [[], 1234, 'claude-limit-watch stop']].each do |records, pid, left_end|
        rule, footer, recorder = bottom(records, pid: pid)
        bar = footer.index('│')
        expect(recorder.index('│')).to eq(bar)
        expect(rule.index('┬')).to eq(bar) # joined to the rule
        expect(rule.count('┬')).to eq(1)
        right = footer.index('now 08:00')
        # With no readings, the headline says so, and the right side is blank.
        expect(recorder.index('last reading') || recorder.size).to eq(records.empty? ? bar + 1 : right)
        left = [footer.index(left_end) + left_end.size, recorder.index(':', 20) + 1].max
        expect((bar - left) - (right - bar - 1)).to be_between(-1, 0) # centered, any odd space after it
        expect(right + 'last reading 08:00 (<1m ago)'.size).to eq(rule.size) # room for the usual reading
      end
    end

    it 'keeps the bar in place for readings up to an hour old' do
      columns = [60, 600, 3540].map do |age| # 1m, 10m and 59m
        rule, footer, recorder = bottom(window_records, now: NOW + age)
        [rule.index('┬'), footer.index('│'), recorder.index('│'), recorder.index('last reading')]
      end
      expect(columns.uniq.size).to eq(1)
    end

    it 'keeps the bar, moved left, for a reading an hour or more old' do
      [NOW + (65 * 60), NOW + (605 * 60)].each do |now| # 1h 05m and 10h 05m
        rule, footer, recorder = bottom(window_records, now: now)
        expect(recorder).to end_with(' ago)').and have_attributes(size: rule.size)
        expect([rule.index('┬'), footer.index('│'), recorder.index('│')].uniq.size).to eq(1)
        expect(footer.index('now')).to eq(recorder.index('last reading'))
        expect(footer).to match(/stop +│/)
      end
    end

    it 'never cuts off a time: in narrow terminals, a right text that does not fit is left out' do
      (40..100).each do |cols|
        _, footer, recorder = bottom(window_records, cols: cols)
        { footer => [' now', 'now 08:00'], recorder => ['last r', 'last reading 08:00 (1m ago)'] }
          .each do |line, (start, whole)|
            expect(!line.include?(start) || line.end_with?(whole)).to be(true), "at #{cols}: #{line.inspect}"
          end
      end
    end

    it 'right-aligns the current time and the last reading, without the bar, when there is no room for it' do
      rule, footer, recorder = bottom(window_records, cols: 80)
      expect([rule, footer, recorder].grep(/[│┬]/)).to be_empty
      expect(footer).to end_with('  now 08:00').and have_attributes(size: rule.size)
      expect(recorder).to end_with('  last reading 08:00 (1m ago)').and have_attributes(size: rule.size)
    end
  end

  it 'shows the current time in UTC with --utc, with no marker of its own' do
    ClaudeLimitWatch::Format.utc = true
    in_zone('Asia/Singapore') { expect(panel(window_records, NOW).grep(/now 08:00\z/)).not_to be_empty }
  end

  it 'never doubles a blank line' do
    states.each do |state, (records, now, pid)|
      doubled = panel(records, now, pid: pid).each_cons(2).any? { |a, b| a.strip.empty? && b.strip.empty? }
      expect(doubled).to be(false), "doubled blank line in the #{state} panel"
    end
  end

  it 'shows warnings in yellow, and secondary text in gray' do
    allow($stdout).to receive(:tty?).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('NO_COLOR').and_return(nil)
    allow(m).to receive(:term_width).and_return(120)
    st = ClaudeLimitWatch::Snapshot.build(worst_records, worst_now, rate_window: 30).merge(recorder_pid: 1234)
    lines = m.lines(st, worst_now)
    expect(lines).to include(a_string_starting_with("\e[38;5;136m  Last check failed"),
      a_string_starting_with("\e[38;5;136m  No new readings"),
      a_string_starting_with("\e[90m  q to quit"))
  end

  describe 'when readings stop' do
    def warning(pid: nil, record: true, now: NOW + 900, records: window_records)
      panel(records, now, pid: pid, record: record, cols: 80).find { |l| l.include?('No new readings') }
    end

    it 'says to check a running recorder, in full at 80 columns' do
      expect(warning(pid: 4_194_304, now: NOW + (65 * 60))) # the largest pid on Linux
        .to eq('  No new readings for 1h 05m. Check the output of the recorder (pid 4194304)')
    end

    it 'says to restart the viewer when no recorder is running' do
      expect(warning).to eq('  No new readings for 15m. Restart the viewer, or see recorder.log')
    end

    it "only says readings stopped with --no-record, which doesn't start one" do
      expect(warning(record: false)).to eq('  No new readings for 15m.')
    end

    it 'only says readings stopped with --once, which never starts one' do
      allow(ClaudeLimitWatch::History).to receive(:read).and_return(window_records)
      allow(ClaudeLimitWatch::Recorder).to receive(:pid).and_return(nil)
      allow(Time).to receive(:now).and_return(NOW + 900)
      expect { m.run_once(30) }.to output(/^  No new readings for 15m\.$/).to_stdout
    end

    it 'ends --once with the version and project page' do
      allow(ClaudeLimitWatch::History).to receive(:read).and_return(window_records)
      allow(ClaudeLimitWatch::Recorder).to receive(:pid).and_return(nil)
      allow(Time).to receive(:now).and_return(NOW)
      expect { m.run_once(30) }.to output(/\n  #{Regexp.escape(ClaudeLimitWatch::VERSION_LINE)}\n\z/).to_stdout
    end

    it 'says how to stop the recorder, by pid for another history file' do
      hint = '  q to quit · stop the recorder with: '
      expect(panel(window_records, NOW)).to include(a_string_starting_with("#{hint}claude-limit-watch stop "))
      allow(ClaudeLimitWatch::History).to receive(:default_file).and_return('/elsewhere/history.jsonl')
      expect(panel(window_records, NOW)).to include(a_string_starting_with("#{hint}kill 1234 "))
    end

    it 'leaves out the warning with no data and nothing to say' do
      expect(panel([], NOW, pid: nil, record: false).grep(/Restart|recorder\)/)).to be_empty
    end
  end

  describe '.run' do
    # Draws one frame (its sleep ends the loop), without touching the
    # terminal, and returns it as plain text.
    def first_frame(record:)
      frame = nil
      panel = ClaudeLimitWatch::Panel
      allow($stdin).to receive(:tty?).and_return(false) # no key reading, no stty
      allow(panel).to receive(:at_exit)
      allow(panel).to receive(:trap)
      allow(panel).to receive(:term_width).and_return(120)
      allow(ClaudeLimitWatch::History::Cache).to receive(:new).and_return(double(records: window_records))
      allow(ClaudeLimitWatch::Recorder).to receive(:pid).and_return(nil)
      allow(Time).to receive(:now).and_return(NOW + 900)
      allow(panel).to receive(:render) { |lines| frame = lines }
      allow(panel).to receive(:sleep).and_raise(StopIteration)
      expect { panel.run(30, record: record) }.to output("\e[?1049h\e[?25l").to_stdout # alternate screen
      plain(frame)
    end

    it 'passes --no-record to the panel' do
      expect(first_frame(record: true))
        .to include('  No new readings for 15m. Restart the viewer, or see recorder.log')
      expect(first_frame(record: false)).to include('  No new readings for 15m.')
    end
  end

  it 'ends the rule where the legend ends' do
    [80, 97, 98, 120].each do |cols|
      lines = panel(window_records, NOW, cols: cols)
      legend = lines.find { |l| l.include?('time so far') }
      rule = lines.find { |l| l.include?('──') }
      expect(rule.size).to eq(legend.size), "at #{cols} columns"
    end
  end

  it 'renders at any width' do
    expect { (1..200).each { |cols| panel(window_records, NOW, cols: cols) } }.not_to raise_error
  end

  it 'draws the projection bars' do
    lines = panel(window_records, NOW)
    bar_w = 50 # at 120 columns
    so_far = lines.find { |l| l.start_with?('  Time ') }[9, bar_w].count(m::SO_FAR_CHAR)
    bars = %w[10m 30m 1h 2h all].to_h do |label|
      [label, lines.find { |l| l.start_with?("  #{label.ljust(6)} ") }[9, bar_w]]
    end

    bars.each_value { |bar| expect(bar.count(m::SO_FAR_CHAR)).to eq(so_far) } # lines up with the Time bar
    expect(bars['10m']).to match(/\A█+▒+X+\z/)
    expect(bars['30m']).to match(/\A█+▒+X\z/)
    %w[1h 2h all].each { |label| expect(bars[label]).to match(/\A█+▒+\z/) }
  end

  it 'shows one X for a lockout shorter than a cell' do
    resets = NOW + (100 * 60)
    row = { label: '10m', eta_at: resets - 60 } # locked out for the last minute only
    bar = plain(m.projection_bar_lines([row], { resets: resets }, 50, NOW)).first[9, 50]
    expect(bar).to match(/\A█+▒+X\z/)
  end

  it 'shows the time left, and the text of a rate that lasts, in green' do
    allow($stdout).to receive(:tty?).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('NO_COLOR').and_return(nil)
    row = { label: '1h', end_pct: 90.0 } # doesn't reach the limit
    line = m.projection_bar_lines([row], { resets: NOW + (100 * 60) }, 50, NOW).first
    expect(line).to include("\e[38;5;34m▒", "\e[38;5;34mlimit not reached · 90% at the end")
  end

  it 'shows no projections early in the window' do
    lines = panel(window_records(elapsed: 20, knots: [[0, 0], [20, 5]]), NOW)
    expect(lines.grep(/Projections start 30m into the window/)).not_to be_empty
    expect(lines.grep(/time so far/)).to be_empty
  end

  it 'shows the reset time at the limit, without projections' do
    lines = panel(window_records(knots: [[0, 0], [200, 100]]), NOW)
    expect(lines.grep(/AT LIMIT.*Resets at/)).not_to be_empty
    expect(lines.grep(/time so far/)).to be_empty
  end

  describe 'times' do
    def times(lines)
      [lines.first.include?('times in UTC'), lines.grep(/last reading/).first[/last reading \S+/],
        lines.grep(/\A +\d\d:\d\d +\d\d:\d\d  now \d\d:\d\d\z/).first.split]
    end

    it 'shows local time' do
      in_zone('Asia/Singapore') do
        expect(times(panel(window_records, NOW)))
          .to eq([false, 'last reading 16:00', %w[12:40 17:40 now 16:00]])
      end
    end

    it 'shows UTC with --utc, and says so' do
      ClaudeLimitWatch::Format.utc = true
      in_zone('Asia/Singapore') do
        expect(times(panel(window_records, NOW)))
          .to eq([true, 'last reading 08:00', %w[04:40 09:40 now 08:00]])
        expect(panel(window_records, NOW).grep(/limit at 0\d:\d\d/)).not_to be_empty
      end
    end
  end
end
