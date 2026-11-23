# frozen_string_literal: true

# The --lines output.
RSpec.describe ClaudeLimitWatch::LinesView do
  let(:m) { described_class }

  describe '.format_line' do
    def fields(util, rate, reset_min)
      history = (5..60).step(5).map { |min| { t: NOW - (min * 60), util: util - (min * rate) } }
      p = ClaudeLimitWatch::Projection.project(history, NOW, util, NOW + (reset_min * 60), rate_window: 30)
      ClaudeLimitWatch::LinesView.format_line(NOW, p).split('|').map(&:strip)
    end

    it 'formats an OK line' do
      expect(fields(50.0, 0.2, 100))
        .to eq(['08:00', 'OK', '3:20 of 5:00', '09:40', '50%', '12.0%/h (avg 15.0)', '0.4x',
          '~30% left at reset'])
    end

    it 'formats a WARN line' do
      f = fields(50.0, 0.6, 100)
      expect(f[1]).to eq('WARN')
      expect(f[7]).to eq('LIMIT at 09:23 (in 1:23), 0:17 before reset')
    end

    it 'shows times in local time, or UTC with --utc' do
      in_zone('Asia/Singapore') do
        expect(fields(50.0, 0.6, 100).values_at(0, 3, 7))
          .to eq(['16:00', '17:40', 'LIMIT at 17:23 (in 1:23), 0:17 before reset'])
        ClaudeLimitWatch::Format.utc = true
        expect(fields(50.0, 0.6, 100).values_at(0, 3, 7))
          .to eq(['08:00', '09:40', 'LIMIT at 09:23 (in 1:23), 0:17 before reset'])
      end
    end

    it 'formats a line at the limit' do
      f = fields(100.0, 0.5, 30)
      expect(f[1]).to eq('URGENT')
      expect(f[7]).to eq('AT LIMIT, resets in 0:30')
    end
  end

  describe '.stale_line' do
    it 'warns in yellow when colors are on' do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('NO_COLOR').and_return(nil)
      expect(m.stale_line(NOW, NOW - 900, nil, record: true))
        .to eq("\e[38;5;220m08:00 | no new readings for 15m. Restart the viewer, or see recorder.log\e[0m")
    end

    it 'adds no hint when there is none' do
      expect(m.stale_line(NOW, NOW - 900, nil, record: false)).to eq('08:00 | no new readings for 15m.')
    end

    it 'gives the gap to the nearest minute, as the panel does' do
      expect(m.stale_line(NOW, NOW - 228, nil, record: false)).to eq('08:00 | no new readings for 4m.')
      expect(m.stale_line(NOW, NOW - 948, nil, record: false)).to eq('08:00 | no new readings for 16m.')
    end
  end

  describe '.intro' do
    def intro(pid, message)
      plain(ClaudeLimitWatch::LinesView.intro(45, pid, message))
    end

    it 'starts with the recorder message, then says the recorder keeps running' do
      lines = intro(4321, 'Started the recorder')
      expect(lines[0]).to eq('Started the recorder')
      expect(lines[1])
        .to end_with('burn rate over the last 45m. Ctrl-C to quit (the recorder keeps running).')
      expect(lines[2]).to eq(ClaudeLimitWatch::VERSION_LINE)
      expect(lines[3]).to start_with('Time  | Level')
    end

    it 'says when times are in UTC' do
      expect(intro(nil, 'x')[1]).not_to include('UTC')
      ClaudeLimitWatch::Format.utc = true
      expect(intro(nil, 'x')[1]).to include('burn rate over the last 45m. Times are in UTC. Ctrl-C to quit.')
    end

    it "doesn't say the recorder keeps running when none is" do
      expect(intro(nil, "Couldn't start the recorder")[1]).to end_with('Ctrl-C to quit.')
    end
  end

  describe '.run' do
    # Runs one pass of the loop: its sleep ends it.
    def run_once(record:, pid:)
      allow(ClaudeLimitWatch::History::Cache).to receive(:new).and_return(double(records: window_records))
      allow(ClaudeLimitWatch::Recorder).to receive(:pid).and_return(pid)
      allow(Time).to receive(:now).and_return(NOW + 900)
      view = ClaudeLimitWatch::LinesView
      allow(view).to receive(:trap)
      allow(view).to receive(:sleep).and_raise(StopIteration)
      plain(capture_lines { view.run(30, pid, 'recorder message', record: record) })
    end

    def capture_lines
      saved = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string.lines.map(&:chomp)
    ensure
      $stdout = saved
    end

    it 'prints the intro, the readings, then that they stopped, with what to do' do
      lines = run_once(record: true, pid: nil)
      expect(lines.first).to eq('recorder message')
      expect(lines.grep(/\A\d\d:\d\d \| (OK|WARN|URGENT)/).size).to eq(window_records.size)
      expect(lines.last).to eq('08:15 | no new readings for 15m. Restart the viewer, or see recorder.log')
    end

    it 'shows the readings and the warning in UTC with --utc' do
      ClaudeLimitWatch::Format.utc = true
      in_zone('Asia/Singapore') do
        lines = run_once(record: true, pid: nil)
        expect(lines.grep(/\A\d\d:\d\d \| (OK|WARN|URGENT)/).last).to start_with('08:00 |')
        expect(lines.last).to start_with('08:15 | no new readings')
      end
    end

    it 'passes --no-record and the running recorder to the warning' do
      expect(run_once(record: false, pid: nil).last).to eq('08:15 | no new readings for 15m.')
      expect(run_once(record: false, pid: 4321).last)
        .to eq('08:15 | no new readings for 15m. Check the output of the recorder (pid 4321)')
    end
  end

  describe '.header' do
    it 'names the rate window' do
      expect(m.header(45)).to include('45m Burn Rate')
    end
  end
end
