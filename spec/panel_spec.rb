# frozen_string_literal: true

# The full-screen panel's layout.
RSpec.describe ClaudeLimitWatch::Panel, '.lines' do
  m = described_class
  banner_text = 'C L A U D E'
  one_line_title = /\A Claude 5-hour limit/

  # The demo scenario, then a failed check, then no readings for 15 minutes:
  # with an extra rate-window row, the tallest panel there is.
  let(:worst_records) { window_records + [error_record(NOW + 60)] }
  let(:worst_now) { NOW + 60 + 900 }

  # Each state the panel can be in: [records, now, recorder pid].
  let(:states) do
    idle = { t: NOW, interval: 5.0, util: 3.0, resets: NOW - 60 }
    {
      'normal' => [window_records, NOW, 1234],
      'no data' => [[], NOW, 1234],
      'no data, no recorder' => [[], NOW, nil],
      'only failed checks' => [[error_record(NOW)], NOW, 1234],
      'idle' => [[idle], NOW, 1234],
      'idle, then a failed check' => [[idle, error_record(NOW + 60)], NOW + 61, 1234],
      'early in the window' => [window_records(elapsed: 20, knots: [[0, 0], [20, 5]]), NOW, 1234],
      'at the limit' => [window_records(knots: [[0, 0], [200, 100]]), NOW, 1234],
      'stale' => [window_records, NOW + 900, 1234],
      'failed and stale' => [worst_records, worst_now, 1234],
      'failed and stale, no recorder' => [worst_records, worst_now, nil]
    }
  end

  it 'shows the normal panel in 23 rows' do
    lines = panel(window_records, NOW)
    expect(lines.size).to eq(23)
    expect(lines[1]).to include(banner_text)
    expect(lines).to include('  q to quit · stop the recorder with: claude-limit-watch stop')
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
end
