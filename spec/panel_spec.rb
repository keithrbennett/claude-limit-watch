# frozen_string_literal: true

# The full-screen panel's layout.
RSpec.describe ClaudeLimitWatch::Panel, '.lines' do
  let(:m) { described_class }
  let(:banner_text) { 'C L A U D E' }
  let(:one_line_title) { /\A Claude 5-hour limit/ }

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

  it 'shows the normal panel in 23 rows' do
    lines = panel(window_records, NOW)
    expect(lines.size).to eq(23)
    expect(lines[1]).to include(banner_text)
    expect(lines)
      .to include(a_string_starting_with('  q to quit · stop the recorder with: claude-limit-watch stop '))
    expect(lines[-2]).to eq("  #{ClaudeLimitWatch::VERSION_LINE}")
    expect(lines[-1]).to start_with('  Recorder running (pid 1234)')
  end

  it 'drops the banner to fit the tallest panel in 24 rows' do
    expect(panel(worst_records, worst_now, rate_window: 45).size).to eq(28) # unknown height: the banner stays

    lines = panel(worst_records, worst_now, rows: 24, rate_window: 45)
    expect(lines.size).to eq(24)
    expect(lines.first).to match(one_line_title)
  end

  it 'fits 24 rows in every state' do
    states.each do |state, (records, now, pid)|
      size = panel(records, now, rows: 24, pid: pid, rate_window: 45).size
      expect(size).to be <= 24, "#{size} rows in the #{state} panel"
    end
  end

  it 'keeps the banner when it fits' do
    expect(panel(window_records, NOW, rows: 24)[1]).to include(banner_text)
  end

  it 'uses the one-line title in narrow terminals' do
    expect(panel(window_records, NOW, cols: 40).first).to match(one_line_title)
  end

  it 'keeps the banner and leaves out quitting with --once' do
    lines = panel(worst_records, worst_now, rows: 10, once: true) # --once ignores the terminal's height
    expect(lines[1]).to include(banner_text)
    expect(lines.grep(/q to quit/)).to be_empty
    expect(lines).to include(a_string_matching(/\A +\d\d:\d\d +\d\d:\d\d  now 08:16\z/))
    expect(lines).to include(a_string_matching(/\A +now 08:16\z/))
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

  it 'shows the current time at the end of the rule, with or without a window' do
    [[window_records, 80], [window_records, 120], [[], 80]].each do |records, cols|
      lines = panel(records, NOW + 59, cols: cols)
      rule = lines.find { |l| l.include?('──') }
      expect(lines[lines.index(rule) + 1])
        .to match(/\A  q to quit · .* {2,}now 08:00\z/).and have_attributes(size: rule.size)
    end
    expect(panel([], NOW, pid: nil)).to include(a_string_matching(/\A  q to quit {2,}now 08:00\z/))
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
    allow(m).to receive_messages(term_width: 120, term_height: nil)
    st = ClaudeLimitWatch::Snapshot.build(worst_records, worst_now, rate_window: 30).merge(recorder_pid: 1234)
    lines = m.lines(st, worst_now)
    expect(lines).to include(a_string_starting_with("\e[38;5;220m  Last check failed"),
      a_string_starting_with("\e[38;5;220m  No new readings"),
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

    it 'says how to stop the recorder, by pid for another history file' do
      hint = '  q to quit · stop the recorder with: '
      expect(panel(window_records, NOW)).to include(a_string_starting_with("#{hint}claude-limit-watch stop "))
      allow(ClaudeLimitWatch::History).to receive(:default_file).and_return('/elsewhere/history.jsonl')
      expect(panel(window_records, NOW)).to include(a_string_starting_with("#{hint}kill 1234 "))
    end

    it 'keeps --no-record when it drops the banner' do
      lines = panel(worst_records, worst_now, pid: nil, rows: 24, rate_window: 45, record: false)
      expect(lines.first).to match(one_line_title)
      expect(lines).to include('  No new readings for 15m.')
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
      allow(panel).to receive_messages(term_width: 120, term_height: nil)
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
      heading = lines.grep(/last reading/).first[/(times in UTC · )?last reading \S+/]
      [heading, lines.grep(/\A +\d\d:\d\d +\d\d:\d\d  now \d\d:\d\d\z/).first.split]
    end

    it 'shows local time' do
      in_zone('Asia/Singapore') do
        expect(times(panel(window_records, NOW))).to eq(['last reading 16:00', %w[12:40 17:40 now 16:00]])
      end
    end

    it 'shows UTC with --utc, and says so' do
      ClaudeLimitWatch::Format.utc = true
      in_zone('Asia/Singapore') do
        expect(times(panel(window_records, NOW)))
          .to eq(['times in UTC · last reading 08:00', %w[04:40 09:40 now 08:00]])
        expect(panel(window_records, NOW).grep(/limit at 0\d:\d\d/)).not_to be_empty
      end
    end
  end
end
