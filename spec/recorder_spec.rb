# frozen_string_literal: true

# Finding, starting and stopping the recorder. Process.spawn and Process.kill
# are stubbed: no real recorder is started or signalled.
RSpec.describe ClaudeLimitWatch::Recorder do
  m = described_class

  before { FileUtils.rm_f(ClaudeLimitWatch::History.lock_file) }

  it 'finds no recorder without a lock file' do
    expect(m.pid).to be_nil
  end

  it 'finds no recorder when nothing holds the lock' do
    File.write(ClaudeLimitWatch::History.lock_file, '99999')
    expect(m.pid).to be_nil
  end

  it 'finds the recorder holding the lock' do
    File.open(ClaudeLimitWatch::History.lock_file, File::RDWR | File::CREAT) do |lock|
      lock.write('4321')
      lock.flush
      # flock locks are per open file, so a second open (as pid does) sees it.
      lock.flock(File::LOCK_EX)
      expect(m.pid).to eq(4321)
    end
  end

  describe 'a held lock without a pid' do
    def hold_lock
      File.open(ClaudeLimitWatch::History.lock_file, File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        yield lock
      end
    end

    it 'has no pid, without waiting' do
      hold_lock do
        expect(m).not_to receive(:sleep)
        expect(m.pid).to be_nil
      end
    end

    it "is something else's if no pid comes, so stop signals nothing and says so" do
      hold_lock do
        allow(m).to receive(:sleep)
        expect(m.find).to eq([nil, true])
        expect(Process).not_to receive(:kill)
        expect do
          expect { m.stop }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        end.to output(/\ASomething holds .* but isn't a recorder; not stopping anything/).to_stderr
        expect(m.status).to eq([nil, "Something holds #{ClaudeLimitWatch::History.lock_file} but isn't a recorder."])
      end
    end

    it "is a starting recorder's if its pid comes, which stop then stops" do
      hold_lock do |lock|
        allow(m).to receive(:sleep) do
          lock.write('4321')
          lock.flush
        end
        expect(m.find).to eq([4321, false])
      end
    end
  end

  describe '.find' do
    it 'finds no recorder without a held lock, without waiting' do
      expect(m).not_to receive(:sleep)
      expect(m.find).to eq([nil, false])
    end

    it 'finds none, and starts one, if the lock is let go during the wait' do
      allow(m).to receive(:lock_held?).and_return(true, false)
      allow(m).to receive(:pid).and_return(nil)
      allow(m).to receive(:sleep)
      expect(m.find).to eq([nil, false])
      expect(m).to receive(:start).and_return(999)
      expect(m.ensure_running.first).to eq(999)
    end
  end

  it "doesn't return the pid of a recorder that exited while it was read" do
    File.write(ClaudeLimitWatch::History.lock_file, '4321')
    # Held at the first check (flock fails), then free (it succeeds; unlock).
    allow_any_instance_of(File).to receive(:flock).and_return(false, 0, 0)
    expect(m.pid).to be_nil
  end

  it 'finds a recorder that starts while the viewer starts one too' do
    allow(Process).to receive_messages(spawn: 999, detach: nil)
    allow(m).to receive(:sleep)
    allow(m).to receive(:pid).and_return(nil, nil, 4321) # the other recorder writes its pid
    expect(m.start).to eq(4321)
  end

  it 'says how to stop it when it starts recording' do
    allow(m).to receive(:trap)
    allow(ClaudeLimitWatch::History).to receive(:prune)
    allow(m).to receive(:record_once)
    allow(m).to receive(:sleep).and_raise(StopIteration) # ends the loop
    expect { m.run(5) }.to output(/\ARecording .* Stop with Ctrl-C or: claude-limit-watch stop\n/).to_stdout
  ensure
    FileUtils.rm_f(ClaudeLimitWatch::History.lock_file) # its lock, still held
  end

  describe '.record_once' do
    before do
      allow(Time).to receive(:now).and_return(NOW + 15)
      allow(ClaudeLimitWatch::UsageApi).to receive(:fetch_five_hour).and_return([46.0, NOW + 3600])
    end

    it 'prints the reading in local time' do
      in_zone('Asia/Singapore') do
        expect { m.record_once(5) }.to output("16:00:15   46%  window ends 17:00\n").to_stdout
      end
    end

    it 'prints it in UTC with --utc' do
      ClaudeLimitWatch::Format.utc = true
      in_zone('Asia/Singapore') do
        expect { m.record_once(5) }.to output("08:00:15   46%  window ends 09:00\n").to_stdout
      end
    end
  end

  it 'says in UTC when it starts recording with --utc' do
    ClaudeLimitWatch::Format.utc = true
    allow(m).to receive(:trap)
    allow(ClaudeLimitWatch::History).to receive(:prune)
    allow(m).to receive(:record_once)
    allow(m).to receive(:sleep).and_raise(StopIteration)
    expect { m.run(5) }.to output(/\(pid \d+\)\. Times are in UTC\. Stop with Ctrl-C/).to_stdout
  ensure
    FileUtils.rm_f(ClaudeLimitWatch::History.lock_file)
  end

  it 'says so when asked to stop with no recorder running' do
    expect { m.stop }.to output("No recorder is running.\n").to_stdout
  end

  it 'stops the running recorder' do
    allow(m).to receive(:find).and_return([4321, false])
    allow(m).to receive(:pid).and_return(4321, nil)
    allow(m).to receive(:sleep)
    expect(Process).to receive(:kill).with('TERM', 4321)
    expect { m.stop }.to output("Stopped the recorder (pid 4321).\n").to_stdout
  end

  it 'starts the recorder in the background, on this history file' do
    history = ClaudeLimitWatch::History
    expect(Process).to receive(:spawn)
      .with({ 'CLAUDE_LIMIT_WATCH_FILE' => history.file }, 'nohup', RbConfig.ruby,
            ClaudeLimitWatch::EXECUTABLE, 'record',
            in: File::NULL, out: [history.log_file, 'a'], err: [:child, :out], pgroup: true)
      .and_return(999)
    expect(Process).to receive(:detach).with(999)
    allow(m).to receive(:sleep)
    allow(m).to receive(:pid).and_return(nil, 999)
    expect(m.start).to eq(999)
  end

  describe '.status' do
    it 'names a running recorder' do
      allow(m).to receive(:find).and_return([4321, false])
      expect(m.status)
        .to eq([4321, 'Recorder running in the background (pid 4321). Stop it with: claude-limit-watch stop'])
    end

    it 'says when none is' do
      expect(m.status).to eq([nil, 'No recorder is running.'])
    end
  end

  it 'starts the recorder with --utc when the viewer has it' do
    ClaudeLimitWatch::Format.utc = true
    expect(Process).to receive(:spawn).with(Hash, 'nohup', RbConfig.ruby, ClaudeLimitWatch::EXECUTABLE,
                                            'record', '--utc', Hash).and_return(999)
    allow(Process).to receive(:detach)
    allow(m).to receive(:pid).and_return(999)
    expect(m.start).to eq(999)
  end

  describe '.stop_command' do
    it 'is the stop command for the default history file' do
      expect(m.stop_command(4321)).to eq('claude-limit-watch stop')
    end

    it 'is kill for another history file, which stop would miss' do
      allow(ClaudeLimitWatch::History).to receive(:default_file).and_return('/elsewhere/history.jsonl')
      expect(m.stop_command(4321)).to eq('kill 4321')
      expect(m.stop_hint(4321)).to end_with('Stop it with: kill 4321')
    end
  end

  describe '.stale_hint' do
    it 'says to check a running recorder' do
      [true, false].each do |record|
        expect(m.stale_hint(4321, record: record)).to eq('Recorder (pid 4321) stuck? Check its output')
      end
    end

    it 'says to restart a viewer that starts the recorder' do
      expect(m.stale_hint(nil, record: true)).to eq('Restart the viewer, or see recorder.log')
    end

    it "has nothing to say to a viewer that doesn't" do
      expect(m.stale_hint(nil, record: false)).to be_nil
    end
  end

  it 'reports a recorder that is already running' do
    allow(m).to receive_messages(lock_held?: true, pid: 4321)
    expect(m).not_to receive(:start)
    expect(m.ensure_running).to eq(
      [4321, 'Recorder running in the background (pid 4321). Stop it with: claude-limit-watch stop']
    )
  end

  it 'waits for a recorder that has the lock but no pid yet, rather than starting another' do
    allow(m).to receive(:lock_held?).and_return(true)
    allow(m).to receive(:pid).and_return(nil, nil, 4321)
    allow(m).to receive(:sleep)
    expect(m).not_to receive(:start)
    expect(m.ensure_running.first).to eq(4321)
  end

  it "doesn't start a recorder when something else holds the lock" do
    allow(m).to receive_messages(lock_held?: true, pid: nil)
    allow(m).to receive(:sleep)
    expect(m).not_to receive(:start)
    expect(m.ensure_running)
      .to eq([nil, "Something holds #{ClaudeLimitWatch::History.lock_file} but isn't a recorder; not starting one"])
  end

  it 'tells whether something holds the lock' do
    expect(m.lock_held?).to be(false) # no lock file
    File.write(ClaudeLimitWatch::History.lock_file, '')
    expect(m.lock_held?).to be(false)
    File.open(ClaudeLimitWatch::History.lock_file) do |lock|
      lock.flock(File::LOCK_EX)
      expect(m.lock_held?).to be(true)
    end
  end

  it 'reports a recorder it started' do
    allow(m).to receive_messages(pid: nil, start: 999)
    expect(m.ensure_running).to eq(
      [999, 'Started the recorder (every 5m). ' \
            'Recorder running in the background (pid 999). Stop it with: claude-limit-watch stop']
    )
  end

  it "reports a recorder that doesn't come up" do
    allow(Process).to receive_messages(spawn: 999, detach: nil)
    allow(m).to receive(:sleep)
    allow(m).to receive(:pid).and_return(nil)
    expect(m.ensure_running)
      .to eq([nil, "Couldn't start the recorder; see #{ClaudeLimitWatch::History.log_file}"])
  end
end
